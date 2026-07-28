const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");

const COVER_BACKGROUND_COLOR = "#000000";
const COVER_FILE_EXTENSION = "jpg";
const COVER_IMAGE_FORMAT = "JPEG";
const SRGB_COLOR_PROFILE_PATHS = [
  "/System/Library/ColorSync/Profiles/sRGB Profile.icc",
  "/Library/ColorSync/Profiles/sRGB Profile.icc",
];
const PRESERVE_ICC_PROFILE_ARGS = ["+profile", "!icc,*"];
const commandAvailability = new Map();

async function resolveCoverTools() {
  const convertCommand = await firstExistingCommand(["magick", "convert"]);
  if (!convertCommand) {
    throw new Error("No cover normalization tool found. Install ImageMagick to normalize RGB/no-alpha cover sources.");
  }

  const hasXcrun = await commandExists("xcrun");
  if (!hasXcrun) {
    throw new Error("No Xcode asset validation tool found. Install Xcode command line tools so xcrun actool can validate cover assets.");
  }

  const hasSips = await commandExists("sips");
  if (!hasSips) {
    throw new Error("No Apple image inspection tool found. Install macOS sips to validate cover color profiles.");
  }

  const identifyCommand = await firstExistingCommand(["magick", "identify"]);
  if (!identifyCommand) {
    throw new Error("No cover validation tool found. Install ImageMagick identify to validate RGB/no-alpha cover output.");
  }

  const srgbProfilePath = await firstExistingFile(SRGB_COLOR_PROFILE_PATHS);
  if (!srgbProfilePath) {
    throw new Error("No sRGB ICC profile found. Expected one of: " + SRGB_COLOR_PROFILE_PATHS.join(", "));
  }

  return {
    convertCommand,
    hasSips,
    hasXcrun,
    identifyCommand,
    srgbProfilePath,
  };
}

async function convertCover(coverTools, inputPath, outputPath, size, quality) {
  const sourceColorProfile = await inspectSourceColorProfile(coverTools, inputPath);
  await writeValidatedCover(coverTools, outputPath, size, async (tempOutputPath) => {
    await writeJPEGCover(coverTools, inputPath, tempOutputPath, size, quality, sourceColorProfile);
  });
}

async function writePlaceholderCover(coverTools, outputPath, collectionName, size, quality, fallbackLabel) {
  const label = String(collectionName ?? fallbackLabel ?? "Collection").slice(0, 32);
  await writeValidatedCover(coverTools, outputPath, size, async (tempOutputPath) => {
    await writeJPEGPlaceholder(coverTools, tempOutputPath, label, size, quality);
  });
}

async function writeCoverContents(imagesetPath, coverAssetId, fileExtension = COVER_FILE_EXTENSION) {
  await fs.writeFile(path.join(imagesetPath, "Contents.json"), `${JSON.stringify({
    images: [
      {
        filename: `${coverAssetId}.${fileExtension}`,
        idiom: "universal",
      },
    ],
    info: {
      author: "xcode",
      version: 1,
    },
  }, null, 2)}\n`);
}

function coverAssetIdForCollection(collection) {
  return collection.cover?.assetId ?? collection.collectionId;
}

function assertUniqueCoverAssetIds(collections, { caseInsensitive = false } = {}) {
  const seen = new Map();
  for (const collection of collections) {
    const coverAssetId = coverAssetIdForCollection(collection);
    const coverAssetKey = caseInsensitive ? coverAssetId.toLowerCase() : coverAssetId;
    const existing = seen.get(coverAssetKey);
    if (existing) {
      throw new Error(`Cover asset id ${coverAssetId} is used by both ${existing.name} and ${collection.name}.`);
    }
    seen.set(coverAssetKey, collection);
  }
}

async function assertCoverIsDecodeSafeJPEG(coverTools, outputPath, expectedSize) {
  const sipsInspection = await inspectCoverWithSips(outputPath);
  if (sipsInspection.format !== "jpeg") {
    throw new Error(`cover ${outputPath} was ${sipsInspection.format}, expected jpeg`);
  }
  if (sipsInspection.pixelWidth !== String(expectedSize) || sipsInspection.pixelHeight !== String(expectedSize)) {
    throw new Error(`cover ${outputPath} must be ${expectedSize}x${expectedSize}; got ${sipsInspection.pixelWidth}x${sipsInspection.pixelHeight}`);
  }
  if (sipsInspection.hasAlpha !== "no" || sipsInspection.samplesPerPixel !== "3") {
    throw new Error(`cover ${outputPath} must be RGB JPEG without alpha; got hasAlpha=${sipsInspection.hasAlpha}, samplesPerPixel=${sipsInspection.samplesPerPixel}`);
  }
  const outputSipsProfile = normalizeSipsProfile(sipsInspection.profile);
  if (!isSrgbProfile(outputSipsProfile)) {
    throw new Error(`cover ${outputPath} must use a standard sRGB color profile; got ${outputSipsProfile || "none"}`);
  }

  const imageMagickInspection = await inspectCoverWithImageMagick(coverTools.identifyCommand, outputPath);
  if (imageMagickInspection.format !== COVER_IMAGE_FORMAT) {
    throw new Error(`cover ${outputPath} was ${imageMagickInspection.format}, expected ${COVER_IMAGE_FORMAT}`);
  }
  if (imageMagickInspection.width !== String(expectedSize) || imageMagickInspection.height !== String(expectedSize)) {
    throw new Error(`cover ${outputPath} must be ${expectedSize}x${expectedSize}; got ${imageMagickInspection.width}x${imageMagickInspection.height}`);
  }
  if (!isThreeChannelRGBWithoutAlpha(imageMagickInspection.channels)) {
    throw new Error(`cover ${outputPath} must be RGB JPEG without alpha; got channels=${imageMagickInspection.channels}`);
  }
  if (!isSrgbColorSpace(imageMagickInspection.colorspace)) {
    throw new Error(`cover ${outputPath} must use sRGB pixels; got colorspace=${imageMagickInspection.colorspace}`);
  }
  if (!hasImageMagickIccProfile(imageMagickInspection.profiles)) {
    throw new Error(`cover ${outputPath} must include the standard sRGB ICC profile`);
  }
}

async function writeValidatedCover(coverTools, outputPath, expectedSize, writeTempOutput) {
  const tempOutputPath = temporaryCoverPath(outputPath);
  try {
    await writeTempOutput(tempOutputPath);
    await assertCoverIsDecodeSafeJPEG(coverTools, tempOutputPath, expectedSize);
    await fs.rename(tempOutputPath, outputPath);
  } catch (error) {
    await fs.rm(tempOutputPath, { force: true });
    throw error;
  }
}

function temporaryCoverPath(outputPath) {
  return temporarySiblingPath(outputPath, path.extname(outputPath) || `.${COVER_FILE_EXTENSION}`);
}

function temporarySiblingPath(outputPath, extension) {
  const outputDirectory = path.dirname(outputPath);
  const outputBaseName = path.basename(outputPath, path.extname(outputPath));
  const uniqueSuffix = `${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  return path.join(outputDirectory, `.${outputBaseName}.${uniqueSuffix}.tmp${extension}`);
}

async function writeJPEGCover(coverTools, inputPath, outputPath, size, quality, colorProfileOptions) {
  await runCommand(coverTools.convertCommand, [
    `${inputPath}[0]`,
    "-auto-orient",
    ...coverColorSpaceArgs(coverTools, colorProfileOptions),
    "-resize", `${size}x${size}^`,
    "-gravity", "center",
    "-background", COVER_BACKGROUND_COLOR,
    "-extent", `${size}x${size}`,
    "-alpha", "remove",
    "-alpha", "off",
    ...PRESERVE_ICC_PROFILE_ARGS,
    "-depth", "8",
    "-type", "TrueColor",
    "-sampling-factor", "4:2:0",
    "-interlace", "none",
    "-quality", String(quality),
    outputPath,
  ]);
}

async function writeJPEGPlaceholder(coverTools, outputPath, label, size, quality) {
  await runCommand(coverTools.convertCommand, [
    "-size", `${size}x${size}`,
    `xc:${COVER_BACKGROUND_COLOR}`,
    "-colorspace", "sRGB",
    "-profile", coverTools.srgbProfilePath,
    "-depth", "8",
    "-fill", "#f4f1e8",
    "-gravity", "center",
    "-font", "Helvetica",
    "-pointsize", "28",
    "-annotate", "0", label,
    "-alpha", "off",
    ...PRESERVE_ICC_PROFILE_ARGS,
    "-type", "TrueColor",
    "-sampling-factor", "4:2:0",
    "-interlace", "none",
    "-quality", String(quality),
    outputPath,
  ]);
}

async function assertCoverCatalogIsAssetCatalogCompatible(assetCatalogPath) {
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "cover-actool-"));
  try {
    for (const spec of coverActoolValidationSpecs()) {
      const compilePath = path.join(tempRoot, `compiled-${spec.label}`);
      await fs.mkdir(compilePath, { recursive: true });
      const { output } = await runCommandCombinedOutput("xcrun", [
        "actool",
        "--compile", compilePath,
        "--platform", spec.platform,
        "--minimum-deployment-target", spec.minimumDeploymentTarget,
        "--target-device", spec.targetDevice,
        "--warnings",
        "--errors",
        "--notices",
        "--output-format", "human-readable-text",
        assetCatalogPath,
      ]);
      if (/Invalid value for reserved bit/u.test(output)) {
        throw new Error(`cover catalog ${assetCatalogPath} is not ${spec.label} asset-catalog safe: actool reported "Invalid value for reserved bit"`);
      }
    }
  } finally {
    await fs.rm(tempRoot, { force: true, recursive: true });
  }
}

function coverActoolValidationSpecs() {
  return [
    {
      label: "tvOS",
      platform: "appletvos",
      minimumDeploymentTarget: "15.0",
      targetDevice: "tv",
    },
    {
      label: "visionOS",
      platform: "xros",
      minimumDeploymentTarget: "1.0",
      targetDevice: "vision",
    },
  ];
}

async function inspectCoverWithSips(outputPath) {
  const output = await runCommandOutput("sips", [
    "-g", "format",
    "-g", "pixelWidth",
    "-g", "pixelHeight",
    "-g", "hasAlpha",
    "-g", "samplesPerPixel",
    "-g", "profile",
    outputPath,
  ]);
  return {
    format: output.match(/format: (\S+)/u)?.[1] ?? "",
    pixelWidth: output.match(/pixelWidth: (\S+)/u)?.[1] ?? "",
    pixelHeight: output.match(/pixelHeight: (\S+)/u)?.[1] ?? "",
    hasAlpha: output.match(/hasAlpha: (\S+)/u)?.[1] ?? "",
    samplesPerPixel: output.match(/samplesPerPixel: (\S+)/u)?.[1] ?? "",
    profile: output.match(/profile: (.+)$/mu)?.[1] ?? "",
  };
}

async function inspectCoverWithImageMagick(identifyCommand, outputPath) {
  if (!identifyCommand) {
    return null;
  }
  const args = identifyCommand === "magick"
    ? ["identify", "-format", "%m\n%[colorspace]\n%[channels]\n%w\n%h\n%[profiles]\n", outputPath]
    : ["-format", "%m\n%[colorspace]\n%[channels]\n%w\n%h\n%[profiles]\n", outputPath];
  const [format = "", colorspace = "", channels = "", width = "", height = "", ...profileLines] = (await runCommandOutput(identifyCommand, args)).trim().split(/\r?\n/u);
  const profiles = profileLines.join("\n");
  return { format, colorspace, channels, width, height, profiles };
}

async function inspectSourceColorProfile(coverTools, inputPath) {
  if (coverTools.identifyCommand) {
    try {
      const sourceInspection = await inspectSourceWithImageMagick(coverTools, inputPath);
      return { hasIccProfile: hasImageMagickIccProfile(sourceInspection.profiles) };
    } catch {
    }
  }

  return { hasIccProfile: false };
}

function coverColorSpaceArgs(coverTools, colorProfileOptions) {
  if (colorProfileOptions.hasIccProfile) {
    return ["-profile", coverTools.srgbProfilePath];
  }
  return ["-colorspace", "sRGB", "-profile", coverTools.srgbProfilePath];
}

async function inspectSourceWithImageMagick(coverTools, inputPath) {
  const args = coverTools.identifyCommand === "magick"
    ? ["identify", "-quiet", "-format", "%[channels]\n%[profiles]", `${inputPath}[0]`]
    : ["-quiet", "-format", "%[channels]\n%[profiles]", `${inputPath}[0]`];
  const [channels = "", ...profileLines] = (await runCommandOutput(coverTools.identifyCommand, args)).trim().split(/\r?\n/u);
  const profiles = profileLines.join("\n");
  return { channels, profiles };
}

function normalizeSipsProfile(profile) {
  const value = String(profile ?? "").trim();
  const normalized = value.toLowerCase();
  return normalized === "" || normalized === "<nil>" || normalized === "none" ? "" : value;
}

function isSrgbProfile(profile) {
  return /^srgb(?:\b|$)/iu.test(profile);
}

function isSrgbColorSpace(colorspace) {
  return String(colorspace ?? "").trim().toLowerCase() === "srgb";
}

function hasImageMagickIccProfile(profiles) {
  return String(profiles ?? "")
    .split(/[\s,;]+/u)
    .some((profile) => profile.toLowerCase() === "icc");
}

function imageMagickChannelInfo(channels) {
  const value = String(channels ?? "");
  return {
    channelName: value.replace(/\s+\d+(?:\.\d+)?$/u, "").trim().toLowerCase(),
    sampleCount: value.match(/(\d+(?:\.\d+)?)$/u)?.[1] ?? "",
  };
}

function isThreeChannelRGBWithoutAlpha(channels) {
  const { channelName, sampleCount } = imageMagickChannelInfo(channels);
  return (channelName === "rgb" || channelName === "srgb")
    && (sampleCount === "3" || sampleCount === "3.0");
}

async function firstExistingCommand(commands) {
  for (const command of commands) {
    if (await commandExists(command)) {
      return command;
    }
  }
  return null;
}

async function firstExistingFile(filePaths) {
  for (const filePath of filePaths) {
    try {
      await fs.access(filePath);
      return filePath;
    } catch {
    }
  }
  return null;
}

async function commandExists(command) {
  if (commandAvailability.has(command)) {
    return commandAvailability.get(command);
  }

  const exists = await new Promise((resolve) => {
    const child = spawn("which", [command], { stdio: "ignore" });
    child.on("close", (code) => resolve(code === 0));
    child.on("error", () => resolve(false));
  });
  commandAvailability.set(command, exists);
  return exists;
}

async function runCommand(command, args) {
  await runCommandOutput(command, args, { captureStdout: false });
}

async function runCommandOutput(command, args, { captureStdout = true } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ["ignore", captureStdout ? "pipe" : "ignore", "pipe"] });
    let stdout = "";
    let stderr = "";
    if (captureStdout) {
      child.stdout.on("data", (chunk) => {
        stdout += chunk.toString();
      });
    }
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("close", (code) => {
      if (code === 0) {
        resolve(stdout);
      } else {
        reject(new Error(`${command} exited ${code}: ${stderr.trim()}`));
      }
    });
    child.on("error", reject);
  });
}

async function runCommandCombinedOutput(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("close", (code) => {
      const output = `${stdout}${stderr}`;
      if (code === 0) {
        resolve({ stdout, stderr, output });
      } else {
        reject(new Error(`${command} exited ${code}: ${output.trim()}`));
      }
    });
    child.on("error", reject);
  });
}

module.exports = {
  assertCoverCatalogIsAssetCatalogCompatible,
  assertUniqueCoverAssetIds,
  convertCover,
  coverAssetIdForCollection,
  resolveCoverTools,
  writeCoverContents,
  writePlaceholderCover,
};

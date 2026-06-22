const fs = require("node:fs/promises");
const path = require("node:path");
const { spawn } = require("node:child_process");

const COVER_BACKGROUND_COLOR = "#000000";
const PRESERVE_ICC_PROFILE_ARGS = ["+profile", "!icc,*"];
const commandAvailability = new Map();

async function resolveCoverTools() {
  const convertCommand = await firstExistingCommand(["magick", "convert"]);
  if (!convertCommand) {
    throw new Error("No cover conversion tool found. Install ImageMagick to generate RGB/no-alpha HEIC covers.");
  }

  const hasSips = await commandExists("sips");
  const hasHeifInfo = await commandExists("heif-info");
  const identifyCommand = await firstExistingCommand(["magick", "identify"]);
  if (!hasSips && !identifyCommand) {
    throw new Error("No cover validation tool found. Install sips or ImageMagick identify.");
  }

  return {
    convertCommand,
    hasHeifInfo,
    hasSips,
    identifyCommand,
  };
}

async function convertCover(coverTools, inputPath, outputPath, size, quality) {
  const sourceColorProfile = await inspectSourceColorProfile(coverTools, inputPath);
  await writeValidatedCover(coverTools, outputPath, size, sourceColorProfile, async (tempOutputPath) => {
    await runCommand(coverTools.convertCommand, [
      `${inputPath}[0]`,
      "-auto-orient",
      ...coverColorSpaceArgs(sourceColorProfile),
      "-resize", `${size}x${size}^`,
      "-gravity", "center",
      "-background", COVER_BACKGROUND_COLOR,
      "-extent", `${size}x${size}`,
      "-alpha", "remove",
      "-alpha", "off",
      ...PRESERVE_ICC_PROFILE_ARGS,
      "-depth", "8",
      "-quality", String(quality),
      tempOutputPath,
    ]);
  });
}

async function writePlaceholderCover(coverTools, outputPath, collectionName, size, quality, fallbackLabel) {
  const label = String(collectionName ?? fallbackLabel ?? "Collection").slice(0, 32);
  await writeValidatedCover(coverTools, outputPath, size, { requireIccProfile: false }, async (tempOutputPath) => {
    await runCommand(coverTools.convertCommand, [
      "-size", `${size}x${size}`,
      `xc:${COVER_BACKGROUND_COLOR}`,
      "-colorspace", "sRGB",
      "-depth", "8",
      "-fill", "#f4f1e8",
      "-gravity", "center",
      "-font", "Helvetica",
      "-pointsize", "28",
      "-annotate", "0", label,
      "-alpha", "off",
      ...PRESERVE_ICC_PROFILE_ARGS,
      "-quality", String(quality),
      tempOutputPath,
    ]);
  });
}

async function writeCoverContents(imagesetPath, coverAssetId) {
  await fs.writeFile(path.join(imagesetPath, "Contents.json"), `${JSON.stringify({
    images: [
      {
        filename: `${coverAssetId}.heic`,
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

async function assertCoverIsDecodeSafeHEIC(coverTools, outputPath, expectedSize, validationOptions = {}) {
  let outputHasIccProfile = false;
  let outputSipsProfile = "";
  if (coverTools.hasSips) {
    const sipsInspection = await inspectCoverWithSips(outputPath);
    if (sipsInspection.format !== "heic") {
      throw new Error(`cover ${outputPath} was ${sipsInspection.format}, expected heic`);
    }
    if (sipsInspection.pixelWidth !== String(expectedSize) || sipsInspection.pixelHeight !== String(expectedSize)) {
      throw new Error(`cover ${outputPath} must be ${expectedSize}x${expectedSize}; got ${sipsInspection.pixelWidth}x${sipsInspection.pixelHeight}`);
    }
    if (sipsInspection.hasAlpha !== "no" || sipsInspection.samplesPerPixel !== "3") {
      throw new Error(`cover ${outputPath} must be RGB HEIC without alpha; got hasAlpha=${sipsInspection.hasAlpha}, samplesPerPixel=${sipsInspection.samplesPerPixel}`);
    }
    outputSipsProfile = normalizeSipsProfile(sipsInspection.profile);
  } else {
    const imageMagickInspection = await inspectCoverWithImageMagick(coverTools.identifyCommand, outputPath);
    if (!imageMagickInspection) {
      throw new Error(`cover ${outputPath} could not be validated; install sips or ImageMagick identify`);
    }
    if (imageMagickInspection.format !== "HEIC") {
      throw new Error(`cover ${outputPath} was ${imageMagickInspection.format}, expected HEIC`);
    }
    if (imageMagickInspection.width !== String(expectedSize) || imageMagickInspection.height !== String(expectedSize)) {
      throw new Error(`cover ${outputPath} must be ${expectedSize}x${expectedSize}; got ${imageMagickInspection.width}x${imageMagickInspection.height}`);
    }
    if (!isThreeChannelRGBWithoutAlpha(imageMagickInspection.channels)) {
      throw new Error(`cover ${outputPath} must be RGB HEIC without alpha; got channels=${imageMagickInspection.channels}`);
    }
    outputHasIccProfile = hasImageMagickIccProfile(imageMagickInspection.profiles);
  }

  const sipsProfileMatches = Boolean(validationOptions.expectedSipsProfile)
    && outputSipsProfile === validationOptions.expectedSipsProfile;
  if (validationOptions.expectedSipsProfile && !sipsProfileMatches) {
    throw new Error(`cover ${outputPath} must preserve source ICC profile ${validationOptions.expectedSipsProfile}; got ${outputSipsProfile || "none"}`);
  }
  if (validationOptions.requireIccProfile && sipsProfileMatches) {
    outputHasIccProfile = true;
  } else if (validationOptions.requireIccProfile && coverTools.hasSips && coverTools.identifyCommand) {
    outputHasIccProfile = await outputHasImageMagickIccProfile(coverTools, outputPath);
  }
  if (validationOptions.requireIccProfile && !outputHasIccProfile) {
    throw new Error(`cover ${outputPath} must preserve source ICC profile; no ICC profile found in output`);
  }

  if (coverTools.hasHeifInfo) {
    const heifInspection = await inspectCoverWithHeifInfo(outputPath);
    if (validationOptions.requireIccProfile && heifInspection.colorProfile !== "prof") {
      throw new Error(`cover ${outputPath} must preserve source ICC profile; got colorProfile=${heifInspection.colorProfile}`);
    }
    if (heifInspection.mainBrand !== "heic" || heifInspection.bitDepth !== "8" || !isAllowedColorProfile(heifInspection.colorProfile) || heifInspection.alphaChannel !== "no" || heifInspection.hasMetadata || heifInspection.hasMimeItems) {
      throw new Error(`cover ${outputPath} must be stripped 8-bit HEIC without alpha or non-color metadata; got mainBrand=${heifInspection.mainBrand}, bitDepth=${heifInspection.bitDepth}, colorProfile=${heifInspection.colorProfile}, alphaChannel=${heifInspection.alphaChannel}, metadata=${heifInspection.hasMetadata}, mimeItems=${heifInspection.hasMimeItems}`);
    }
  }
}

async function writeValidatedCover(coverTools, outputPath, expectedSize, validationOptions, writeTempOutput) {
  const tempOutputPath = temporaryCoverPath(outputPath);
  try {
    await writeTempOutput(tempOutputPath);
    await assertCoverIsDecodeSafeHEIC(coverTools, tempOutputPath, expectedSize, validationOptions);
    await fs.rename(tempOutputPath, outputPath);
  } catch (error) {
    await fs.rm(tempOutputPath, { force: true });
    throw error;
  }
}

function temporaryCoverPath(outputPath) {
  const outputDirectory = path.dirname(outputPath);
  const outputBaseName = path.basename(outputPath, path.extname(outputPath));
  const uniqueSuffix = `${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  return path.join(outputDirectory, `.${outputBaseName}.${uniqueSuffix}.tmp.heic`);
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
    ? ["identify", "-format", "%m\n%[channels]\n%w\n%h\n%[profiles]\n", outputPath]
    : ["-format", "%m\n%[channels]\n%w\n%h\n%[profiles]\n", outputPath];
  const [format = "", channels = "", width = "", height = "", ...profileLines] = (await runCommandOutput(identifyCommand, args)).trim().split(/\r?\n/u);
  const profiles = profileLines.join("\n");
  return { format, channels, width, height, profiles };
}

async function inspectSourceColorProfile(coverTools, inputPath) {
  if (coverTools.identifyCommand) {
    try {
      const sourceInspection = await inspectSourceWithImageMagick(coverTools, inputPath);
      if (hasImageMagickIccProfile(sourceInspection.profiles) && isRgbCompatibleChannels(sourceInspection.channels)) {
        const sipsProfile = coverTools.hasSips
          ? await sourceSipsProfile(inputPath)
          : "";
        return {
          ...(sipsProfile ? { expectedSipsProfile: sipsProfile } : {}),
          requireIccProfile: true,
        };
      }
    } catch {
      // If profile inspection fails, let conversion and structural validation decide the cover.
    }
  }

  return { requireIccProfile: false };
}

function coverColorSpaceArgs(validationOptions) {
  return validationOptions.requireIccProfile ? [] : ["-colorspace", "sRGB"];
}

async function inspectSourceWithImageMagick(coverTools, inputPath) {
  const args = coverTools.identifyCommand === "magick"
    ? ["identify", "-quiet", "-format", "%[channels]\n%[profiles]", `${inputPath}[0]`]
    : ["-quiet", "-format", "%[channels]\n%[profiles]", `${inputPath}[0]`];
  const [channels = "", ...profileLines] = (await runCommandOutput(coverTools.identifyCommand, args)).trim().split(/\r?\n/u);
  const profiles = profileLines.join("\n");
  return { channels, profiles };
}

async function outputHasImageMagickIccProfile(coverTools, outputPath) {
  const inspection = await inspectCoverWithImageMagick(coverTools.identifyCommand, outputPath);
  return hasImageMagickIccProfile(inspection?.profiles);
}

async function sourceSipsProfile(inputPath) {
  try {
    return normalizeSipsProfile((await inspectCoverWithSips(inputPath)).profile);
  } catch {
    return "";
  }
}

async function inspectCoverWithHeifInfo(outputPath) {
  const output = await runCommandOutput("heif-info", [outputPath]);
  return {
    mainBrand: output.match(/main brand:\s*(\S+)/u)?.[1] ?? "",
    bitDepth: output.match(/bit depth:\s*(\S+)/u)?.[1] ?? "",
    colorProfile: output.match(/color profile:\s*(\S+)/u)?.[1] ?? "",
    alphaChannel: output.match(/alpha channel:\s*(\S+)/u)?.[1] ?? "",
    hasMetadata: heifSectionHasContent(output, "metadata"),
    hasMimeItems: heifSectionHasContent(output, "MIME items"),
  };
}

function heifSectionHasContent(output, header) {
  const lines = output.split(/\r?\n/u);
  const start = lines.findIndex((line) => line === `${header}:`);
  if (start < 0) {
    return false;
  }

  for (let index = start + 1; index < lines.length; index += 1) {
    const line = lines[index];
    if (line && !/^\s/u.test(line) && /:$/.test(line)) {
      break;
    }
    const value = line.trim();
    if (value && value !== "none") {
      return true;
    }
  }
  return false;
}

function isAllowedColorProfile(colorProfile) {
  return colorProfile === "no" || colorProfile === "prof";
}

function normalizeSipsProfile(profile) {
  const value = String(profile ?? "").trim();
  const normalized = value.toLowerCase();
  return normalized === "" || normalized === "<nil>" || normalized === "none" ? "" : value;
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

function isRgbCompatibleChannels(channels) {
  const { channelName, sampleCount } = imageMagickChannelInfo(channels);
  return ["rgb", "srgb", "rgba", "srgba"].includes(channelName)
    && ["3", "3.0", "4", "4.0"].includes(sampleCount);
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

module.exports = {
  assertUniqueCoverAssetIds,
  convertCover,
  coverAssetIdForCollection,
  resolveCoverTools,
  writeCoverContents,
  writePlaceholderCover,
};

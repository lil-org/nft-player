const fs = require("node:fs/promises");
const path = require("node:path");
const { spawn } = require("node:child_process");

const COVER_BACKGROUND_COLOR = "#161616";
const commandAvailability = new Map();

async function resolveCoverTools() {
  const convertCommand = await firstExistingCommand(["magick", "convert"]);
  if (!convertCommand) {
    throw new Error("No cover conversion tool found. Install ImageMagick to generate stripped RGB/no-alpha HEIC covers.");
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
  await writeValidatedCover(coverTools, outputPath, async (tempOutputPath) => {
    await runCommand(coverTools.convertCommand, [
      `${inputPath}[0]`,
      "-auto-orient",
      "-colorspace", "sRGB",
      "-depth", "8",
      "-resize", `${size}x${size}^`,
      "-gravity", "center",
      "-extent", `${size}x${size}`,
      "-background", COVER_BACKGROUND_COLOR,
      "-alpha", "remove",
      "-alpha", "off",
      "-strip",
      "-quality", String(quality),
      tempOutputPath,
    ]);
  });
}

async function writePlaceholderCover(coverTools, outputPath, collectionName, size, quality, fallbackLabel) {
  const label = String(collectionName ?? fallbackLabel ?? "Collection").slice(0, 32);
  await writeValidatedCover(coverTools, outputPath, async (tempOutputPath) => {
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
      "-strip",
      "-quality", String(quality),
      tempOutputPath,
    ]);
  });
}

async function writeCoverContents(imagesetPath, collectionId) {
  await fs.writeFile(path.join(imagesetPath, "Contents.json"), `${JSON.stringify({
    images: [
      {
        filename: `${collectionId}.heic`,
        idiom: "universal",
      },
    ],
    info: {
      author: "xcode",
      version: 1,
    },
  }, null, 2)}\n`);
}

async function assertCoverIsDecodeSafeHEIC(coverTools, outputPath) {
  if (coverTools.hasSips) {
    const sipsInspection = await inspectCoverWithSips(outputPath);
    if (sipsInspection.format !== "heic") {
      throw new Error(`cover ${outputPath} was ${sipsInspection.format}, expected heic`);
    }
    if (sipsInspection.hasAlpha !== "no" || sipsInspection.samplesPerPixel !== "3") {
      throw new Error(`cover ${outputPath} must be RGB HEIC without alpha; got hasAlpha=${sipsInspection.hasAlpha}, samplesPerPixel=${sipsInspection.samplesPerPixel}`);
    }
  } else {
    const imageMagickInspection = await inspectCoverWithImageMagick(coverTools.identifyCommand, outputPath);
    if (!imageMagickInspection) {
      throw new Error(`cover ${outputPath} could not be validated; install sips or ImageMagick identify`);
    }
    if (imageMagickInspection.format !== "HEIC") {
      throw new Error(`cover ${outputPath} was ${imageMagickInspection.format}, expected HEIC`);
    }
    if (!isThreeChannelRGBWithoutAlpha(imageMagickInspection.channels)) {
      throw new Error(`cover ${outputPath} must be RGB HEIC without alpha; got channels=${imageMagickInspection.channels}`);
    }
  }

  if (coverTools.hasHeifInfo) {
    const heifInspection = await inspectCoverWithHeifInfo(outputPath);
    if (heifInspection.mainBrand !== "heic" || heifInspection.bitDepth !== "8" || heifInspection.colorProfile !== "no" || heifInspection.alphaChannel !== "no" || heifInspection.hasMetadata || heifInspection.hasMimeItems) {
      throw new Error(`cover ${outputPath} must be stripped 8-bit HEIC without alpha/profile/metadata; got mainBrand=${heifInspection.mainBrand}, bitDepth=${heifInspection.bitDepth}, colorProfile=${heifInspection.colorProfile}, alphaChannel=${heifInspection.alphaChannel}, metadata=${heifInspection.hasMetadata}, mimeItems=${heifInspection.hasMimeItems}`);
    }
  }
}

async function writeValidatedCover(coverTools, outputPath, writeTempOutput) {
  const tempOutputPath = temporaryCoverPath(outputPath);
  try {
    await writeTempOutput(tempOutputPath);
    await assertCoverIsDecodeSafeHEIC(coverTools, tempOutputPath);
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
    "-g", "hasAlpha",
    "-g", "samplesPerPixel",
    outputPath,
  ]);
  return {
    format: output.match(/format: (\S+)/u)?.[1] ?? "",
    hasAlpha: output.match(/hasAlpha: (\S+)/u)?.[1] ?? "",
    samplesPerPixel: output.match(/samplesPerPixel: (\S+)/u)?.[1] ?? "",
  };
}

async function inspectCoverWithImageMagick(identifyCommand, outputPath) {
  if (!identifyCommand) {
    return null;
  }
  const args = identifyCommand === "magick"
    ? ["identify", "-format", "%m\n%[channels]\n", outputPath]
    : ["-format", "%m\n%[channels]\n", outputPath];
  const [format = "", channels = ""] = (await runCommandOutput(identifyCommand, args)).trim().split(/\r?\n/u);
  return { format, channels };
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

function isThreeChannelRGBWithoutAlpha(channels) {
  const channelName = channels.replace(/\s+\d+(?:\.\d+)?$/u, "").trim().toLowerCase();
  const sampleCount = channels.match(/(\d+(?:\.\d+)?)$/u)?.[1];
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
  convertCover,
  resolveCoverTools,
  writeCoverContents,
  writePlaceholderCover,
};

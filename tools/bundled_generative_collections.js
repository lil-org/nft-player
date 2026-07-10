const fs = require("node:fs/promises");
const path = require("node:path");

const DOWNLOAD_DIRECTORY_NAME = "Art Blocks Generative";
const SKIP_REASON = "rendered from a bundled generative script";

async function loadBundledGenerativeCollectionIds(bundlePath) {
  const scriptsPath = path.join(bundlePath, "Scripts");
  let entries;
  try {
    entries = await fs.readdir(scriptsPath, { withFileTypes: true });
  } catch (error) {
    if (error.code === "ENOENT") return new Set();
    throw error;
  }

  return new Set(
    entries
      .filter((entry) => entry.isFile() && entry.name.endsWith(".json"))
      .map((entry) => entry.name.slice(0, -".json".length).toLowerCase()),
  );
}

function isBundledGenerativeCollectionId(collectionId, collectionIds) {
  return collectionIds.has(String(collectionId).toLowerCase());
}

function isBundledGenerativeDownloadDirectory(name) {
  return name === DOWNLOAD_DIRECTORY_NAME;
}

module.exports = {
  DOWNLOAD_DIRECTORY_NAME,
  SKIP_REASON,
  isBundledGenerativeCollectionId,
  isBundledGenerativeDownloadDirectory,
  loadBundledGenerativeCollectionIds,
};

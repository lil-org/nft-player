const fs = require("node:fs/promises");
const path = require("node:path");

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isValidTmpFileName(value) {
  return typeof value === "string"
    && value.length > 0
    && value.trim() === value
    && !value.includes("\0")
    && !value.includes("/")
    && !value.includes("\\")
    && value !== "."
    && value !== ".."
    && path.posix.extname(value).length > 1;
}

function tokenIdsFromPayload(payload) {
  if (!Array.isArray(payload?.items)) {
    return [];
  }

  const ids = [];
  const seen = new Set();
  for (const row of payload.items) {
    if (!Array.isArray(row) || row.length === 0 || row[0] == null) {
      continue;
    }
    const id = String(row[0]);
    if (!seen.has(id)) {
      ids.push(id);
      seen.add(id);
    }
  }
  return ids;
}

function preserveTmpFiles(existingPayload, nextPayload) {
  const payload = { ...nextPayload };
  delete payload.tmp_files;

  const report = {
    sourceExists: true,
    preservedIds: [],
    staleIds: [],
    invalidIds: [],
    invalidMap: false,
  };
  const existingTmpFiles = existingPayload?.tmp_files;
  if (existingTmpFiles == null) {
    return { payload, report };
  }
  if (!isPlainObject(existingTmpFiles)) {
    report.invalidMap = true;
    return { payload, report };
  }

  const currentIds = tokenIdsFromPayload(nextPayload);
  const currentIdSet = new Set(currentIds);
  const validEntries = new Map();

  for (const [id, fileName] of Object.entries(existingTmpFiles)) {
    if (!isValidTmpFileName(fileName)) {
      report.invalidIds.push(id);
    } else if (!currentIdSet.has(id)) {
      report.staleIds.push(id);
    } else {
      validEntries.set(id, fileName);
    }
  }

  if (validEntries.size > 0) {
    report.preservedIds = currentIds.filter((id) => validEntries.has(id));
    payload.tmp_files = Object.fromEntries(
      report.preservedIds.map((id) => [id, validEntries.get(id)])
    );
  }

  return { payload, report };
}

async function preserveTmpFilesFromFile(filePath, nextPayload) {
  let existingPayload;
  try {
    existingPayload = JSON.parse(await fs.readFile(filePath, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") {
      const result = preserveTmpFiles(null, nextPayload);
      result.report.sourceExists = false;
      return result;
    }
    throw error;
  }
  return preserveTmpFiles(existingPayload, nextPayload);
}

function reportTmpFilesChanges(collectionId, report, logger = console) {
  if (report.invalidMap) {
    logger.warn(`Ignored invalid tmp_files map while rebundling ${collectionId}.`);
  }
  if (report.invalidIds.length > 0) {
    logger.warn(
      `Dropped ${report.invalidIds.length} invalid tmp_files entr${report.invalidIds.length === 1 ? "y" : "ies"} while rebundling ${collectionId}: ${report.invalidIds.join(", ")}`
    );
  }
  if (report.staleIds.length > 0) {
    logger.warn(
      `Dropped ${report.staleIds.length} stale tmp_files entr${report.staleIds.length === 1 ? "y" : "ies"} while rebundling ${collectionId}: ${report.staleIds.join(", ")}`
    );
  }
}

module.exports = {
  isValidTmpFileName,
  preserveTmpFiles,
  preserveTmpFilesFromFile,
  reportTmpFilesChanges,
  tokenIdsFromPayload,
};

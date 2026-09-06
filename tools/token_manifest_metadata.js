const fs = require("node:fs/promises");

async function preserveMidAvailabilityFromFile(filePath, nextPayload) {
  try {
    const existingPayload = JSON.parse(await fs.readFile(filePath, "utf8"));
    return typeof existingPayload?.hasMid === "boolean"
      ? { ...nextPayload, hasMid: existingPayload.hasMid }
      : nextPayload;
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
    return nextPayload;
  }
}

module.exports = { preserveMidAvailabilityFromFile };

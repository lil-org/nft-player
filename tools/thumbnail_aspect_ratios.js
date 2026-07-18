"use strict";

const fs = require("node:fs/promises");

const ASPECT_RATIOS_KEY = "thumbnailAspectRatios";
const ASPECT_RATIO_OVERRIDES_KEY = "thumbnailAspectRatioOverrides";
const COLLECTION_BROWSER_DEFAULT_COLUMN_COUNT = 3;
const COLLECTION_BROWSER_LANDSCAPE_COLUMN_COUNT = 2;

function greatestCommonDivisor(left, right) {
  let a = left;
  let b = right;
  while (b !== 0) {
    [a, b] = [b, a % b];
  }
  return a;
}

function normalizedRatio(value, context = "Thumbnail aspect ratio") {
  if (
    !Array.isArray(value)
    || value.length !== 2
    || !Number.isSafeInteger(value[0])
    || !Number.isSafeInteger(value[1])
    || value[0] <= 0
    || value[1] <= 0
  ) {
    throw new TypeError(`${context} must be a [positiveWidth, positiveHeight] integer pair`);
  }

  const divisor = greatestCommonDivisor(value[0], value[1]);
  return [value[0] / divisor, value[1] / divisor];
}

function ratioKey(ratio) {
  return `${ratio[0]}:${ratio[1]}`;
}

function tokenIdsFromPayload(payload) {
  if (!Array.isArray(payload?.items)) {
    throw new TypeError("Token payload must contain an items array");
  }

  return payload.items.map((row, index) => {
    const value = Array.isArray(row) ? row[0] : row?.id;
    if (value == null || (typeof value === "string" && value.length === 0)) {
      throw new TypeError(`Token item ${index} must contain an id`);
    }
    return String(value);
  });
}

function decodeAspectRatioMetadata(payload) {
  const encodedRatios = payload?.[ASPECT_RATIOS_KEY];
  const encodedOverrides = payload?.[ASPECT_RATIO_OVERRIDES_KEY];
  if (encodedRatios == null && encodedOverrides == null) {
    return null;
  }
  if (!Array.isArray(encodedRatios) || encodedRatios.length === 0) {
    throw new TypeError(`${ASPECT_RATIOS_KEY} must be a non-empty array when aspect-ratio metadata is present`);
  }

  const ratios = encodedRatios.map((ratio, index) =>
    normalizedRatio(ratio, `${ASPECT_RATIOS_KEY}[${index}]`)
  );
  const ratioKeys = ratios.map(ratioKey);
  if (new Set(ratioKeys).size !== ratioKeys.length) {
    throw new TypeError(`${ASPECT_RATIOS_KEY} must not contain duplicate ratios`);
  }

  if (encodedOverrides != null && !Array.isArray(encodedOverrides)) {
    throw new TypeError(`${ASPECT_RATIO_OVERRIDES_KEY} must be an array`);
  }

  const itemCount = tokenIdsFromPayload(payload).length;
  const resolved = Array.from({ length: itemCount }, () => [...ratios[0]]);
  const overriddenTokenIndices = new Set();
  for (const [index, override] of (encodedOverrides ?? []).entries()) {
    if (
      !Array.isArray(override)
      || override.length !== 2
      || !Number.isSafeInteger(override[0])
      || !Number.isSafeInteger(override[1])
    ) {
      throw new TypeError(
        `${ASPECT_RATIO_OVERRIDES_KEY}[${index}] must be a [tokenIndex, ratioIndex] integer pair`
      );
    }

    const [tokenIndex, ratioIndex] = override;
    if (tokenIndex < 0 || tokenIndex >= itemCount) {
      throw new RangeError(
        `${ASPECT_RATIO_OVERRIDES_KEY}[${index}] has an invalid token index: ${tokenIndex}`
      );
    }
    if (ratioIndex <= 0 || ratioIndex >= ratios.length) {
      throw new RangeError(
        `${ASPECT_RATIO_OVERRIDES_KEY}[${index}] has an invalid ratio index: ${ratioIndex}`
      );
    }
    if (overriddenTokenIndices.has(tokenIndex)) {
      throw new TypeError(`${ASPECT_RATIO_OVERRIDES_KEY} repeats token index: ${tokenIndex}`);
    }

    overriddenTokenIndices.add(tokenIndex);
    resolved[tokenIndex] = [...ratios[ratioIndex]];
  }
  return resolved;
}

function encodeAspectRatioMetadata(values) {
  if (!Array.isArray(values) || values.length === 0) {
    throw new TypeError("Thumbnail aspect ratios must be a non-empty array");
  }

  const normalized = values.map((ratio, index) =>
    normalizedRatio(ratio, `Thumbnail aspect ratio ${index}`)
  );
  const statsByRatio = new Map();
  normalized.forEach((ratio, index) => {
    const key = ratioKey(ratio);
    const existing = statsByRatio.get(key);
    if (existing) {
      existing.count += 1;
    } else {
      statsByRatio.set(key, {
        ratio,
        count: 1,
        firstIndex: index,
      });
    }
  });

  const stats = [...statsByRatio.values()].sort(
    (left, right) => right.count - left.count || left.firstIndex - right.firstIndex
  );
  const ratioIndexByKey = new Map(
    stats.map((entry, index) => [ratioKey(entry.ratio), index])
  );
  const overrides = [];
  normalized.forEach((ratio, tokenIndex) => {
    const ratioIndex = ratioIndexByKey.get(ratioKey(ratio));
    if (ratioIndex > 0) {
      overrides.push([tokenIndex, ratioIndex]);
    }
  });

  return {
    [ASPECT_RATIOS_KEY]: stats.map((entry) => [...entry.ratio]),
    ...(overrides.length === 0 ? {} : { [ASPECT_RATIO_OVERRIDES_KEY]: overrides }),
  };
}

function collectionBrowserColumnCountFromAspectRatios(values) {
  if (!Array.isArray(values) || values.length === 0) {
    throw new TypeError("Thumbnail aspect ratios must be a non-empty array");
  }

  let landscapeCount = 0;
  let verticalCount = 0;
  values.forEach((value, index) => {
    const [width, height] = normalizedRatio(
      value,
      `Thumbnail aspect ratio ${index}`
    );
    if (width > height) {
      landscapeCount += 1;
    } else {
      verticalCount += 1;
    }
  });

  return landscapeCount > verticalCount
    ? COLLECTION_BROWSER_LANDSCAPE_COLUMN_COUNT
    : COLLECTION_BROWSER_DEFAULT_COLUMN_COUNT;
}

function withoutAspectRatioMetadata(payload) {
  const result = { ...payload };
  delete result[ASPECT_RATIOS_KEY];
  delete result[ASPECT_RATIO_OVERRIDES_KEY];
  return result;
}

function uniqueTokenIds(payload, label) {
  const ids = tokenIdsFromPayload(payload);
  const seen = new Set();
  for (const id of ids) {
    if (seen.has(id)) {
      throw new TypeError(`${label} repeats token id: ${id}`);
    }
    seen.add(id);
  }
  return ids;
}

function preserveAspectRatioMetadata(existingPayload, nextPayload) {
  const payload = withoutAspectRatioMetadata(nextPayload);
  const report = {
    sourceExists: true,
    metadataExists: false,
    preservedIds: [],
    staleIds: [],
    missingIds: [],
  };

  const existingRatios = decodeAspectRatioMetadata(existingPayload);
  if (existingRatios == null) {
    return { payload, report, collectionBrowserColumnCount: null };
  }
  report.metadataExists = true;

  const existingIds = uniqueTokenIds(existingPayload, "Existing token payload");
  const nextIds = uniqueTokenIds(nextPayload, "Next token payload");
  const nextIdSet = new Set(nextIds);
  report.staleIds = existingIds.filter((id) => !nextIdSet.has(id));

  const ratioById = new Map(
    existingIds.map((id, index) => [id, existingRatios[index]])
  );
  report.missingIds = nextIds.filter((id) => !ratioById.has(id));
  if (report.missingIds.length > 0 || nextIds.length === 0) {
    return { payload, report, collectionBrowserColumnCount: null };
  }

  report.preservedIds = [...nextIds];
  const preservedRatios = nextIds.map((id) => ratioById.get(id));
  Object.assign(
    payload,
    encodeAspectRatioMetadata(preservedRatios)
  );
  return {
    payload,
    report,
    collectionBrowserColumnCount:
      collectionBrowserColumnCountFromAspectRatios(preservedRatios),
  };
}

async function preserveAspectRatioMetadataFromFile(filePath, nextPayload) {
  let existingPayload;
  try {
    existingPayload = JSON.parse(await fs.readFile(filePath, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") {
      const result = {
        payload: withoutAspectRatioMetadata(nextPayload),
        report: {
          sourceExists: false,
          metadataExists: false,
          preservedIds: [],
          staleIds: [],
          missingIds: [],
        },
        collectionBrowserColumnCount: null,
      };
      return result;
    }
    throw error;
  }
  return preserveAspectRatioMetadata(existingPayload, nextPayload);
}

function summarizedIds(ids) {
  const sample = ids.slice(0, 10).join(", ");
  return ids.length <= 10 ? sample : `${sample}, ...`;
}

function reportAspectRatioMetadataChanges(collectionId, report, logger = console) {
  if (!report.sourceExists) {
    logger.warn(
      `No existing token payload was available to preserve thumbnail aspect ratios while bundling ${collectionId}.`
    );
    return;
  }
  if (!report.metadataExists) {
    logger.warn(
      `No existing thumbnail aspect-ratio metadata was available while rebundling ${collectionId}.`
    );
    return;
  }
  if (report.missingIds.length > 0) {
    logger.warn(
      `Omitted thumbnail aspect-ratio metadata while rebundling ${collectionId} because ${report.missingIds.length} token id(s) have no existing ratio: ${summarizedIds(report.missingIds)}`
    );
  }
  if (report.staleIds.length > 0) {
    logger.warn(
      `Dropped thumbnail aspect ratios for ${report.staleIds.length} stale token id(s) while rebundling ${collectionId}: ${summarizedIds(report.staleIds)}`
    );
  }
}

module.exports = {
  ASPECT_RATIOS_KEY,
  ASPECT_RATIO_OVERRIDES_KEY,
  COLLECTION_BROWSER_DEFAULT_COLUMN_COUNT,
  COLLECTION_BROWSER_LANDSCAPE_COLUMN_COUNT,
  collectionBrowserColumnCountFromAspectRatios,
  decodeAspectRatioMetadata,
  encodeAspectRatioMetadata,
  preserveAspectRatioMetadataFromFile,
  reportAspectRatioMetadataChanges,
  tokenIdsFromPayload,
};

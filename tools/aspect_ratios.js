"use strict";

const fs = require("node:fs/promises");

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

function normalizedRatio(value, context = "Aspect ratio") {
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
    if (row == null || typeof row !== "object" || Array.isArray(row)) {
      throw new TypeError(`Token item ${index} must be an object`);
    }
    const value = row.id;
    if (value == null || (typeof value === "string" && value.length === 0)) {
      throw new TypeError(`Token item ${index} must contain an id`);
    }
    return String(value);
  });
}

function decodeAspectRatioMetadata(payload, defaultAspectRatio) {
  tokenIdsFromPayload(payload);
  const defaultRatio = defaultAspectRatio == null
    ? null
    : normalizedRatio(defaultAspectRatio, "Collection aspectRatio");
  const resolved = payload.items.map((item, index) => item.aspectRatio == null
    ? defaultRatio
    : normalizedRatio(item.aspectRatio, `Token item ${index} aspectRatio`)
  );
  return defaultRatio == null && resolved.every((ratio) => ratio == null) ? null : resolved;
}

function encodeAspectRatioMetadata(payload, values) {
  if (!Array.isArray(values) || values.length === 0) {
    throw new TypeError("Aspect ratios must be a non-empty array");
  }
  if (tokenIdsFromPayload(payload).length !== values.length) {
    throw new TypeError("Aspect ratios must match the token count");
  }
  const normalized = values.map((ratio, index) =>
    normalizedRatio(ratio, `Aspect ratio ${index}`)
  );
  const counts = new Map();
  for (const ratio of normalized) {
    const key = ratioKey(ratio);
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  const defaultKey = [...counts.keys()].sort((a, b) => counts.get(b) - counts.get(a))[0];
  const defaultRatio = normalized.find((ratio) => ratioKey(ratio) === defaultKey);
  const result = withoutAspectRatioMetadata(payload);
  return {
    aspectRatio: [...defaultRatio],
    payload: {
      items: result.items.map((item, index) => ({
        ...item,
        ...(ratioKey(normalized[index]) === defaultKey ? {} : { aspectRatio: normalized[index] }),
      })),
    },
  };
}

function collectionBrowserColumnCountFromAspectRatios(values) {
  if (!Array.isArray(values) || values.length === 0) {
    throw new TypeError("Aspect ratios must be a non-empty array");
  }

  let landscapeCount = 0;
  let verticalCount = 0;
  values.forEach((value, index) => {
    const [width, height] = normalizedRatio(
      value,
      `Aspect ratio ${index}`
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
  return {
    items: payload.items.map((item) => {
      const token = { ...item };
      delete token.aspectRatio;
      return token;
    }),
  };
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

function preserveAspectRatioMetadata(existingPayload, nextPayload, defaultAspectRatio) {
  const payload = withoutAspectRatioMetadata(nextPayload);
  const report = {
    sourceExists: true,
    metadataExists: false,
    preservedIds: [],
    staleIds: [],
    missingIds: [],
  };

  const existingRatios = decodeAspectRatioMetadata(existingPayload, defaultAspectRatio);
  if (existingRatios == null) {
    return { payload, aspectRatio: null, report, collectionBrowserColumnCount: null };
  }
  report.metadataExists = true;

  const existingIds = uniqueTokenIds(existingPayload, "Existing token payload");
  const nextIds = uniqueTokenIds(nextPayload, "Next token payload");
  const nextIdSet = new Set(nextIds);
  report.staleIds = existingIds.filter((id) => !nextIdSet.has(id));

  const ratioById = new Map(
    existingIds.flatMap((id, index) => existingRatios[index] == null ? [] : [[id, existingRatios[index]]])
  );
  report.missingIds = nextIds.filter((id) => !ratioById.has(id));
  if (report.missingIds.length > 0 || nextIds.length === 0) {
    return { payload, aspectRatio: null, report, collectionBrowserColumnCount: null };
  }

  report.preservedIds = [...nextIds];
  const preservedRatios = nextIds.map((id) => ratioById.get(id));
  return {
    ...encodeAspectRatioMetadata(payload, preservedRatios),
    report,
    collectionBrowserColumnCount:
      collectionBrowserColumnCountFromAspectRatios(preservedRatios),
  };
}

async function preserveAspectRatioMetadataFromFile(filePath, nextPayload, defaultAspectRatio) {
  let existingPayload;
  try {
    existingPayload = JSON.parse(await fs.readFile(filePath, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") {
      const result = {
        payload: withoutAspectRatioMetadata(nextPayload),
        aspectRatio: null,
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
  return preserveAspectRatioMetadata(existingPayload, nextPayload, defaultAspectRatio);
}

function summarizedIds(ids) {
  const sample = ids.slice(0, 10).join(", ");
  return ids.length <= 10 ? sample : `${sample}, ...`;
}

function reportAspectRatioMetadataChanges(collectionId, report, logger = console) {
  if (!report.sourceExists) {
    logger.warn(
      `No existing token payload was available to preserve aspect ratios while bundling ${collectionId}.`
    );
    return;
  }
  if (!report.metadataExists) {
    logger.warn(
      `No existing aspect-ratio metadata was available while rebundling ${collectionId}.`
    );
    return;
  }
  if (report.missingIds.length > 0) {
    logger.warn(
      `Omitted aspect-ratio metadata while rebundling ${collectionId} because ${report.missingIds.length} token id(s) have no existing ratio: ${summarizedIds(report.missingIds)}`
    );
  }
  if (report.staleIds.length > 0) {
    logger.warn(
      `Dropped aspect ratios for ${report.staleIds.length} stale token id(s) while rebundling ${collectionId}: ${summarizedIds(report.staleIds)}`
    );
  }
}

module.exports = {
  COLLECTION_BROWSER_DEFAULT_COLUMN_COUNT,
  COLLECTION_BROWSER_LANDSCAPE_COLUMN_COUNT,
  collectionBrowserColumnCountFromAspectRatios,
  decodeAspectRatioMetadata,
  encodeAspectRatioMetadata,
  normalizedRatio,
  preserveAspectRatioMetadataFromFile,
  reportAspectRatioMetadataChanges,
  tokenIdsFromPayload,
};

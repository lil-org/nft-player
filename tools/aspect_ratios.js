"use strict";

const { decodeTokenManifest } = require("./token_manifest");

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

function decodeAspectRatioMetadata(payload, defaultAspectRatio) {
  const { items } = decodeTokenManifest(payload);
  const defaultRatio = defaultAspectRatio == null
    ? null
    : normalizedRatio(defaultAspectRatio, "Collection aspectRatio");
  const resolved = items.map((item, index) => item.aspectRatio == null
    ? defaultRatio
    : normalizedRatio(item.aspectRatio, `Token item ${index} aspectRatio`)
  );
  return defaultRatio == null && resolved.every((ratio) => ratio == null) ? null : resolved;
}

module.exports = { decodeAspectRatioMetadata, normalizedRatio };

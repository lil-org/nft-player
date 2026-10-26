"use strict";

const INTERNAL_SLUG_PATTERN = /^[a-z0-9]+(?:_[a-z0-9]+)*$/u;
const MAX_INTERNAL_SLUG_LENGTH = 120;

function assertValidInternalSlugs(items) {
  if (!Array.isArray(items)) throw new TypeError("Suggested items must be an array");
  const seen = new Map();
  for (const item of items) {
    assertInternalSlug(item?.internal_slug, item);
    const previous = seen.get(item.internal_slug);
    if (previous) {
      throw new Error(`Duplicate internal_slug ${item.internal_slug} for ${itemLabel(previous)} and ${itemLabel(item)}`);
    }
    seen.set(item.internal_slug, item);
  }
  return items;
}

function assertInternalSlug(value, item) {
  if (typeof value !== "string" || !INTERNAL_SLUG_PATTERN.test(value) || value.length > MAX_INTERNAL_SLUG_LENGTH) {
    throw new Error(`Invalid internal_slug ${JSON.stringify(value)} for ${itemLabel(item)}; expected ${INTERNAL_SLUG_PATTERN} and at most ${MAX_INTERNAL_SLUG_LENGTH} characters`);
  }
}

function itemLabel(item) {
  return `${item?.name ?? "unnamed collection"} (${item?.address ?? ""}${item?.abId ?? item?.collectionId ?? ""})`;
}

module.exports = { INTERNAL_SLUG_PATTERN, MAX_INTERNAL_SLUG_LENGTH, assertValidInternalSlugs };

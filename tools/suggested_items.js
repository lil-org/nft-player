const crypto = require("node:crypto");

const INTERNAL_SLUG_PATTERN = /^[a-z0-9]+(?:_[a-z0-9]+)*$/u;
const MAX_INTERNAL_SLUG_LENGTH = 120;
const CASE_INSENSITIVE_ID_CHAINS = new Set(["base", "ethereum", "optimism", "zora"]);
const LATIN_ASCII_REPLACEMENTS = new Map([
  ["Æ", "AE"], ["æ", "ae"], ["Œ", "OE"], ["œ", "oe"], ["ß", "ss"],
  ["Ø", "O"], ["ø", "o"], ["Ł", "L"], ["ł", "l"], ["Ð", "D"], ["ð", "d"],
  ["Þ", "Th"], ["þ", "th"], ["Đ", "D"], ["đ", "d"], ["Ħ", "H"], ["ħ", "h"],
  ["Ŋ", "N"], ["ŋ", "n"], ["ı", "i"], ["ſ", "s"],
]);
const PRESERVED_GENERATED_SUGGESTED_ITEM_FIELDS = [
  "playerBackgroundColor",
  "webURL",
  "internal_slug",
  "standardThumbsPathsAvailable",
];

function mergeGeneratedSuggestedItem(existingItem, generatedItem) {
  return {
    ...pickExistingFields(existingItem, PRESERVED_GENERATED_SUGGESTED_ITEM_FIELDS),
    ...generatedItem,
  };
}

function suggestedItemId(item) {
  return `${item.address}${item.abId ?? item.collectionId ?? ""}`;
}

function collectionIdentityKey(id, chain) {
  const normalizedChain = String(chain ?? "").toLowerCase();
  const value = String(id ?? "");
  const normalizedId = CASE_INSENSITIVE_ID_CHAINS.has(normalizedChain) ? value.toLowerCase() : value;
  return `${normalizedChain}:${normalizedId}`;
}

function suggestedItemIdentityKey(item) {
  return collectionIdentityKey(suggestedItemId(item), item.chain);
}

function slugifyCollectionName(name) {
  return String(name ?? "")
    .replace(/\+/gu, "plus")
    .replace(/[ÆæŒœßØøŁłÐðÞþĐđĦħŊŋıſ]/gu, (character) => LATIN_ASCII_REPLACEMENTS.get(character))
    .normalize("NFD")
    .replace(/\p{M}+/gu, "")
    .toLowerCase()
    .replace(/\s+/gu, "_")
    .replace(/[^a-z0-9_]/gu, "")
    .replace(/_+/gu, "_")
    .replace(/^_+|_+$/gu, "");
}

function assignInternalSlugs(items) {
  const used = new Map();
  const assigned = new Map();

  for (const item of items) {
    if (item.internal_slug == null) {
      continue;
    }
    assertInternalSlug(item.internal_slug, item);
    const previous = used.get(item.internal_slug);
    if (previous) {
      throw new Error(`Duplicate internal_slug ${item.internal_slug} for ${itemLabel(previous)} and ${itemLabel(item)}`);
    }
    used.set(item.internal_slug, item);
  }

  const groups = new Map();
  for (const item of items) {
    if (item.internal_slug != null) continue;
    const base = slugifyCollectionName(item.name);
    if (!base) {
      throw new Error(`Cannot derive internal_slug for ${itemLabel(item)}; provide an explicit ASCII slug`);
    }
    const boundedBase = boundedGeneratedSlug(base, item);
    const record = {
      item,
      base: boundedBase,
      stableKey: `${item.name ?? ""}\u0000${suggestedItemIdentityKey(item)}`,
    };
    const group = groups.get(boundedBase) ?? [];
    group.push(record);
    groups.set(boundedBase, group);
  }

  const pending = [];
  for (const base of [...groups.keys()].sort(compareStrings)) {
    const group = groups.get(base).sort((left, right) => compareStrings(left.stableKey, right.stableKey));
    if (!used.has(base)) {
      const first = group.shift();
      assigned.set(first.item, base);
      used.set(base, first.item);
    }
    pending.push(...group);
  }

  pending.sort((left, right) => compareStrings(left.base, right.base) || compareStrings(left.stableKey, right.stableKey));
  for (const record of pending) {
    let suffix = 2;
    let internalSlug = suffixedSlug(record.base, suffix);
    while (used.has(internalSlug)) {
      suffix += 1;
      internalSlug = suffixedSlug(record.base, suffix);
    }
    assigned.set(record.item, internalSlug);
    used.set(internalSlug, record.item);
  }

  return items.map((item) => {
    const internalSlug = item.internal_slug ?? assigned.get(item);
    if (item.internal_slug != null) return item;
    return {
      ...item,
      internal_slug: internalSlug,
    };
  });
}

function assertValidInternalSlugs(items) {
  const seen = new Map();
  for (const item of items) {
    assertInternalSlug(item.internal_slug, item);
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

function boundedGeneratedSlug(base, item) {
  if (base.length <= MAX_INTERNAL_SLUG_LENGTH) return base;
  const hash = crypto.createHash("sha256").update(suggestedItemIdentityKey(item)).digest("hex").slice(0, 10);
  const prefixLength = MAX_INTERNAL_SLUG_LENGTH - hash.length - 1;
  const prefix = base.slice(0, prefixLength).replace(/_+$/gu, "");
  return `${prefix}_${hash}`;
}

function suffixedSlug(base, suffixNumber) {
  const suffix = `_${suffixNumber}`;
  const prefix = base.slice(0, MAX_INTERNAL_SLUG_LENGTH - suffix.length).replace(/_+$/gu, "");
  return `${prefix}${suffix}`;
}

function compareStrings(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function itemLabel(item) {
  return `${item?.name ?? "unnamed collection"} (${suggestedItemId(item ?? {})})`;
}

function pickExistingFields(item, fields) {
  return Object.fromEntries(
    fields
      .filter((field) => Object.prototype.hasOwnProperty.call(item, field))
      .map((field) => [field, item[field]])
  );
}

module.exports = {
  INTERNAL_SLUG_PATTERN,
  MAX_INTERNAL_SLUG_LENGTH,
  assignInternalSlugs,
  assertValidInternalSlugs,
  collectionIdentityKey,
  mergeGeneratedSuggestedItem,
  slugifyCollectionName,
  suggestedItemId,
  suggestedItemIdentityKey,
};

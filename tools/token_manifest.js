"use strict";

const MAX_ID = 9223372036854775807n;
const columns = ["name", "hash", "urlSuffix", "aspectRatio", "contractParameters"];

function object(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
}

function validateRatio(value, label) {
  if (!Array.isArray(value) || value.length !== 2
      || value.some((part) => !Number.isSafeInteger(part) || part <= 0)) {
    throw new TypeError(`${label} must be a [positiveWidth, positiveHeight] integer pair`);
  }
}

function validateField(field, value, label) {
  if (value == null) return;
  if (field === "aspectRatio") {
    validateRatio(value, label);
  } else if (field === "contractParameters") {
    if (!object(value) || Object.values(value).some((part) => typeof part !== "string")) {
      throw new TypeError(`${label} must be a string-to-string object`);
    }
  } else if (typeof value !== "string") {
    throw new TypeError(`${label} must be a string`);
  }
}

function validateIndices(value, count) {
  if (!Array.isArray(value) || value.some((index, position) => !Number.isSafeInteger(index)
      || index < 0 || index >= count || (position > 0 && index <= value[position - 1]))) {
    throw new TypeError("excludedMediaIndices must be sorted unique token indices");
  }
  return value;
}

function validateRows(items) {
  if (!Array.isArray(items)) throw new TypeError("Token payload must contain an items array");
  return items.map((item, index) => {
    if (!object(item) || typeof item.id !== "string" || item.id.length === 0) {
      throw new TypeError(`Token item ${index} must be an object with a non-empty string id`);
    }
    const unknown = Object.keys(item).find((key) => key !== "id" && !columns.includes(key));
    if (unknown) throw new TypeError(`Token item ${index} has unsupported field ${unknown}`);
    const result = { id: item.id };
    for (const field of columns) {
      validateField(field, item[field], `Token item ${index} ${field}`);
      if (item[field] != null) result[field] = item[field];
    }
    return result;
  });
}

function decodeTokenManifest(payload, { allowLegacy = true } = {}) {
  if (!object(payload)) throw new TypeError("Token payload must be an object");
  if (Object.hasOwn(payload, "items")) {
    if (!allowLegacy || Object.keys(payload).some((key) => key !== "items")) {
      throw new TypeError("Legacy items cannot be combined with compact manifest fields");
    }
    return { items: validateRows(payload.items) };
  }
  if (payload.version !== 2) throw new TypeError("Unsupported token manifest version");
  const { count } = payload;
  if (!Number.isSafeInteger(count) || count < 0) throw new TypeError("Token count must be a nonnegative integer");
  const hasRange = Object.hasOwn(payload, "firstId");
  if (hasRange === Object.hasOwn(payload, "ids")) {
    throw new TypeError("Token manifest must contain exactly one of firstId or ids");
  }
  let ids;
  if (hasRange) {
    if (typeof payload.firstId !== "string" || !/^(0|[1-9][0-9]*)$/u.test(payload.firstId)
        || BigInt(payload.firstId) > MAX_ID
        || (count > 0 && BigInt(payload.firstId) + BigInt(count - 1) > MAX_ID)) {
      throw new TypeError("firstId must be a canonical nonnegative Int64 range without overflow");
    }
    const first = BigInt(payload.firstId);
    ids = Array.from({ length: count }, (_, index) => String(first + BigInt(index)));
  } else {
    if (!Array.isArray(payload.ids) || payload.ids.length !== count
        || payload.ids.some((id) => typeof id !== "string" || id.length === 0)) {
      throw new TypeError("ids must contain count non-empty strings");
    }
    ids = payload.ids;
  }
  const items = ids.map((id) => ({ id }));
  for (const field of columns) {
    if (!Object.hasOwn(payload, field)) continue;
    const values = payload[field];
    if (!Array.isArray(values) || values.length !== count) {
      throw new TypeError(`${field} array must match token count`);
    }
    values.forEach((value, index) => {
      validateField(field, value, `Token item ${index} ${field}`);
      if (value != null) items[index][field] = value;
    });
  }
  if (Object.hasOwn(payload, "urlTemplate")) {
    const template = payload.urlTemplate;
    if (Object.hasOwn(payload, "urlSuffix") || !object(template)
        || !["id", "index0", "index1"].includes(template.value) || typeof template.suffix !== "string"
        || Object.keys(template).some((key) => !["value", "suffix"].includes(key))) {
      throw new TypeError("urlTemplate must have a supported value and suffix, without urlSuffix");
    }
    items.forEach((item, index) => {
      const value = template.value === "id" ? item.id : String(index + (template.value === "index1" ? 1 : 0));
      item.urlSuffix = value + template.suffix;
    });
  }
  const unknown = Object.keys(payload).find((key) => ![
    "version", "count", "firstId", "ids", ...columns, "urlTemplate", "excludedMediaIndices",
  ].includes(key));
  if (unknown) throw new TypeError(`Unsupported token manifest field ${unknown}`);
  const indices = Object.hasOwn(payload, "excludedMediaIndices")
    ? validateIndices(payload.excludedMediaIndices, count) : [];
  return { items, ...(indices.length > 0 ? { excludedMediaIndices: indices } : {}) };
}

function rangeStart(items) {
  if (items.length === 0 || !/^(0|[1-9][0-9]*)$/u.test(items[0].id)) return null;
  const first = BigInt(items[0].id);
  if (first + BigInt(items.length - 1) > MAX_ID) return null;
  return items.every((item, index) => item.id === String(first + BigInt(index))) ? items[0].id : null;
}

function urlTemplate(items) {
  if (items.length === 0 || items.some((item) => item.urlSuffix == null)) return null;
  for (const value of ["id", "index0", "index1"]) {
    const source = (item, index) => value === "id" ? item.id : String(index + (value === "index1" ? 1 : 0));
    const first = source(items[0], 0);
    if (!items[0].urlSuffix.startsWith(first)) continue;
    const suffix = items[0].urlSuffix.slice(first.length);
    if (items.every((item, index) => item.urlSuffix === source(item, index) + suffix)) return { value, suffix };
  }
  return null;
}

function encodeTokenManifest(payload, options = {}) {
  const decoded = Array.isArray(payload) ? { items: validateRows(payload) } : decodeTokenManifest(payload);
  const { items } = decoded;
  const firstId = rangeStart(items);
  const result = { version: 2, count: items.length,
    ...(firstId == null ? { ids: items.map((item) => item.id) } : { firstId }) };
  const template = urlTemplate(items);
  for (const field of columns) {
    if (field === "urlSuffix" && template) {
      result.urlTemplate = template;
    } else if (items.some((item) => item[field] != null)) {
      result[field] = items.map((item) => {
        const value = item[field] ?? null;
        return field === "contractParameters" && value != null
          ? Object.fromEntries(Object.entries(value).sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0))
          : value;
      });
    }
  }
  const indices = Object.hasOwn(options, "excludedMediaIndices")
    ? validateIndices(options.excludedMediaIndices, items.length) : decoded.excludedMediaIndices ?? [];
  if (indices.length > 0) result.excludedMediaIndices = [...indices];
  return result;
}

function serializeTokenManifest(payload, options) {
  return `${JSON.stringify(encodeTokenManifest(payload, options))}\n`;
}

module.exports = { decodeTokenManifest, encodeTokenManifest, serializeTokenManifest };

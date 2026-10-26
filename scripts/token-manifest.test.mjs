import assert from "node:assert/strict";
import test from "node:test";
import tokenManifest from "../tools/token_manifest.js";

const { decodeTokenManifest, encodeTokenManifest, serializeTokenManifest } = tokenManifest;

test("ranges preserve canonical decimal IDs through Int64.max", () => {
  for (const ids of [["0", "1"], ["8", "9"], ["9223372036854775806", "9223372036854775807"]]) {
    const rows = ids.map((id) => ({ id }));
    const encoded = encodeTokenManifest(rows);
    assert.equal(encoded.firstId, ids[0]);
    assert.equal(encoded.ids, undefined);
    assert.deepEqual(decodeTokenManifest(encoded).items, rows);
  }
});

test("explicit IDs retain sparse, duplicate, nonnumeric, zero-padded, negative, and oversized values", () => {
  for (const ids of [[], ["0", "2"], ["1", "1"], ["mint"], ["01", "02"], ["-1", "0"],
    ["9223372036854775807", "9223372036854775808"], ["18446744073709551615"]]) {
    const rows = ids.map((id) => ({ id }));
    assert.deepEqual(encodeTokenManifest(rows), { version: 2, count: rows.length, ids });
    assert.deepEqual(decodeTokenManifest(encodeTokenManifest(rows)).items, rows);
  }
});

test("columns preserve present values and null placeholders without normalizing ratios", () => {
  const rows = [
    { id: "10", name: "", hash: "0x123", aspectRatio: [8, 6], contractParameters: { z: "two", a: "one" } },
    { id: "11", urlSuffix: "" },
  ];
  const encoded = encodeTokenManifest(rows);
  assert.deepEqual(encoded.name, ["", null]);
  assert.deepEqual(encoded.hash, ["0x123", null]);
  assert.deepEqual(encoded.aspectRatio, [[8, 6], null]);
  assert.deepEqual(encoded.urlSuffix, [null, ""]);
  assert.deepEqual(decodeTokenManifest(encoded).items, rows);
  assert.equal(serializeTokenManifest(rows), serializeTokenManifest(encoded));
  assert.ok(serializeTokenManifest(rows).endsWith("\n"));
  assert.equal(serializeTokenManifest(rows).split("\n").length, 2);
});

test("templates prefer IDs then source index zero then source index one", () => {
  for (const [ids, suffixes, expected] of [
    [["0", "1"], ["0.png", "1.png"], { value: "id", suffix: ".png" }],
    [["mint", "other"], ["0?ext=svg", "1?ext=svg"], { value: "index0", suffix: "?ext=svg" }],
    [["mint", "other"], ["1.gif", "2.gif"], { value: "index1", suffix: ".gif" }],
    [["abc", "def"], ["abc", "def"], { value: "id", suffix: "" }],
  ]) {
    const rows = ids.map((id, index) => ({ id, urlSuffix: suffixes[index] }));
    const encoded = encodeTokenManifest(rows, { excludedMediaIndices: [0] });
    assert.deepEqual(encoded.urlTemplate, expected);
    assert.equal(encoded.urlSuffix, undefined);
    assert.deepEqual(decodeTokenManifest(encoded), { items: rows, excludedMediaIndices: [0] });
  }
  assert.deepEqual(encodeTokenManifest([{ id: "1", urlSuffix: "1.png" }, { id: "2" }]).urlSuffix, ["1.png", null]);
  assert.deepEqual(encodeTokenManifest([{ id: "1", urlSuffix: "01.png" }, { id: "2", urlSuffix: "02.png" }]).urlSuffix, ["01.png", "02.png"]);
});

test("exclusions remain sorted, omit empty lists, and can be replaced during regeneration", () => {
  const compact = { version: 2, count: 3, firstId: "1", excludedMediaIndices: [0, 2] };
  assert.deepEqual(encodeTokenManifest(compact), compact);
  assert.equal(encodeTokenManifest(compact, { excludedMediaIndices: [] }).excludedMediaIndices, undefined);
  for (const excludedMediaIndices of [[-1], [3], [0, 0], [2, 1], [0.5], null]) {
    assert.throws(() => decodeTokenManifest({ ...compact, excludedMediaIndices }), /sorted unique/u);
    assert.throws(() => encodeTokenManifest(compact, { excludedMediaIndices }), /sorted unique/u);
  }
});

test("rejects malformed schemas, conflicting fields, invalid columns and overflowing ranges", () => {
  const base = { version: 2, count: 2, firstId: "1" };
  for (const payload of [null, [], {}, { items: {} }, { items: [], version: 2 },
    { ...base, version: 1 }, { ...base, version: 3 }, { ...base, count: -1 }, { ...base, count: 1.1 },
    { ...base, ids: ["1", "2"] }, { version: 2, count: 0 },
    { ...base, firstId: "01" }, { ...base, firstId: "-1" }, { ...base, firstId: "9223372036854775807" },
    { ...base, firstId: "9223372036854775808", count: 0 },
    { version: 2, count: 2, ids: ["1"] }, { version: 2, count: 1, ids: [1] },
    { ...base, name: ["one"] }, { ...base, hash: [null, false] }, { ...base, aspectRatio: [[0, 1], null] },
    { ...base, aspectRatio: [[1.5, 1], null] }, { ...base, contractParameters: [{ a: 1 }, null] },
    { ...base, urlTemplate: { value: "index2", suffix: ".png" } },
    { ...base, urlTemplate: { value: "id", suffix: ".png" }, urlSuffix: [null, null] },
    { ...base, urlTemplate: { value: "id" } }, { ...base, extra: true },
    { items: [{ id: "1", extra: true }] }, { items: [{ id: "1", aspectRatio: [1, 2, 3] }] },
  ]) assert.throws(() => decodeTokenManifest(payload), undefined, JSON.stringify(payload));
  assert.throws(() => decodeTokenManifest({ items: [] }), /version/u);
  assert.throws(() => encodeTokenManifest({ items: [] }), /version/u);
});

test("row encoding rejects malformed values instead of silently dropping them", () => {
  for (const rows of [[null], [[]], [{}], [{ id: 1 }], [{ id: "" }],
    [{ id: "1", extra: true }], [{ id: "1", name: 1 }], [{ id: "1", hash: false }],
    [{ id: "1", urlSuffix: {} }], [{ id: "1", aspectRatio: [1, 2, 3] }],
    [{ id: "1", contractParameters: [] }], [{ id: "1", contractParameters: { count: 1 } }]]) {
    assert.throws(() => encodeTokenManifest(rows), undefined, JSON.stringify(rows));
  }
});

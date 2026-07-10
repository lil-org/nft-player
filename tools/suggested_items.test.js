const assert = require("node:assert/strict");
const test = require("node:test");
const {
  assignInternalSlugs,
  assertValidInternalSlugs,
  collectionIdentityKey,
  MAX_INTERNAL_SLUG_LENGTH,
  mergeGeneratedSuggestedItem,
  slugifyCollectionName,
} = require("./suggested_items");

test("slugifies collection names using the canonical rules", () => {
  assert.equal(slugifyCollectionName("A Clean Name"), "a_clean_name");
  assert.equal(slugifyCollectionName("pfp+"), "pfpplus");
  assert.equal(slugifyCollectionName("Túnel Dimensional"), "tunel_dimensional");
  assert.equal(slugifyCollectionName("Cloudcastle ☆ 限定版アルファ"), "cloudcastle");
  assert.equal(slugifyCollectionName("Horses?2"), "horses2");
  assert.equal(slugifyCollectionName("  MANY   SPACES!  "), "many_spaces");
  assert.equal(slugifyCollectionName("Łódź Æther smørrebrød Straße"), "lodz_aether_smorrebrod_strasse");
  assert.equal(slugifyCollectionName("Øresund"), "oresund");
});

test("rejects a name that cannot produce an ASCII slug", () => {
  assert.throws(
    () => assignInternalSlugs([{ address: "id", name: "限定版" }]),
    /provide an explicit ASCII slug/u,
  );
});

test("preserves existing slugs and suffixes new collisions", () => {
  const assigned = assignInternalSlugs([
    { address: "first", name: "Stable Name", internal_slug: "kept_slug" },
    { address: "second", name: "Super Metal Mons!" },
    { address: "third", name: "Super Metal Mons!!" },
  ]);
  assert.deepEqual(assigned.map((item) => item.internal_slug), [
    "kept_slug",
    "super_metal_mons",
    "super_metal_mons_2",
  ]);
});

test("assigns collision suffixes independently of input order", () => {
  const first = { address: "a", chain: "solana", name: "Same!" };
  const second = { address: "b", chain: "solana", name: "Same!!" };
  const forward = assignInternalSlugs([first, second]);
  const reverse = assignInternalSlugs([second, first]);
  const byAddress = (items) => Object.fromEntries(items.map((item) => [item.address, item.internal_slug]));
  assert.deepEqual(byAddress(forward), byAddress(reverse));
  assert.deepEqual(byAddress(forward), { a: "same", b: "same_2" });
});

test("bounds generated and explicit slugs to a safe path length", () => {
  const [item] = assignInternalSlugs([{ address: "long", chain: "solana", name: "a".repeat(300) }]);
  assert.equal(item.internal_slug.length, MAX_INTERNAL_SLUG_LENGTH);
  assert.match(item.internal_slug, /^[a-z0-9_]+$/u);
  assert.throws(
    () => assertValidInternalSlugs([{ address: "id", name: "Long", internal_slug: "a".repeat(MAX_INTERNAL_SLUG_LENGTH + 1) }]),
    /at most 120 characters/u,
  );
});

test("normalizes only case-insensitive chain identifiers", () => {
  assert.equal(collectionIdentityKey("0xAbC", "ethereum"), collectionIdentityKey("0xabc", "ethereum"));
  assert.notEqual(collectionIdentityKey("AbC", "solana"), collectionIdentityKey("aBc", "solana"));
  assert.notEqual(collectionIdentityKey("KT1AbC", "tezos"), collectionIdentityKey("KT1aBc", "tezos"));
});

test("preserves an existing slug when generated metadata is merged", () => {
  assert.deepEqual(
    mergeGeneratedSuggestedItem(
      { internal_slug: "stable_slug", playerBackgroundColor: "#ffffff", name: "Old" },
      { address: "id", name: "Updated" },
    ),
    {
      playerBackgroundColor: "#ffffff",
      internal_slug: "stable_slug",
      address: "id",
      name: "Updated",
    },
  );
});

test("rejects invalid or duplicate stored slugs", () => {
  assert.throws(
    () => assertValidInternalSlugs([{ address: "id", name: "Bad", internal_slug: "Bad-Slug" }]),
    /Invalid internal_slug/u,
  );
  assert.throws(
    () => assertValidInternalSlugs([
      { address: "one", name: "One", internal_slug: "same" },
      { address: "two", name: "Two", internal_slug: "same" },
    ]),
    /Duplicate internal_slug/u,
  );
});

const CDN_LIL_MANAGED_COLLECTION_IDS = new Set([
  "EAzEpagtyeRAx9npnpVMpygoA8ouX7DRpLTghhPvYTiu", // Card NFT 2
  "JCTP3kK3xGtWs5mDHxJBuRro38HftaiCDdKsfkXuK2gH", // Poncho Drifella
].map((value) => value.toLowerCase()));

function isCdnLilManagedCollection(itemOrId) {
  const id = typeof itemOrId === "string" ? itemOrId : itemOrId?.address;
  return CDN_LIL_MANAGED_COLLECTION_IDS.has(String(id ?? "").toLowerCase());
}

module.exports = {
  CDN_LIL_MANAGED_COLLECTION_IDS,
  isCdnLilManagedCollection,
};

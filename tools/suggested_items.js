const PRESERVED_GENERATED_SUGGESTED_ITEM_FIELDS = ["playerBackgroundColor", "webURL"];

function mergeGeneratedSuggestedItem(existingItem, generatedItem) {
  return {
    ...pickExistingFields(existingItem, PRESERVED_GENERATED_SUGGESTED_ITEM_FIELDS),
    ...generatedItem,
  };
}

function suggestedItemId(item) {
  return `${item.address}${item.abId ?? item.collectionId ?? ""}`;
}

function pickExistingFields(item, fields) {
  return Object.fromEntries(
    fields
      .filter((field) => Object.prototype.hasOwnProperty.call(item, field))
      .map((field) => [field, item[field]])
  );
}

module.exports = {
  mergeGeneratedSuggestedItem,
  suggestedItemId,
};

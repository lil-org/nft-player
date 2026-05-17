const PRESERVED_GENERATED_SUGGESTED_ITEM_FIELDS = ["playerBackgroundColor"];

function mergeGeneratedSuggestedItem(existingItem, generatedItem) {
  return {
    ...pickExistingFields(existingItem, PRESERVED_GENERATED_SUGGESTED_ITEM_FIELDS),
    ...generatedItem,
  };
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
};

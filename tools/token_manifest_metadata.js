const {
  preserveAspectRatioMetadataFromFile,
  reportAspectRatioMetadataChanges,
} = require("./aspect_ratios");
const { preserveTmpFiles, reportTmpFilesChanges } = require("./tmp_files");
const { suggestedItemId, withIOSCollectionBrowserColumnCount } = require("./suggested_items");

async function preserveTokenMetadataFromFile(filePath, nextPayload, collectionItem) {
  const collectionId = suggestedItemId(collectionItem);
  const ratios = await preserveAspectRatioMetadataFromFile(
    filePath, nextPayload, collectionItem.aspectRatio
  );
  reportAspectRatioMetadataChanges(collectionId, ratios.report);
  const tmpFiles = preserveTmpFiles(collectionItem, nextPayload);
  reportTmpFilesChanges(collectionId, tmpFiles.report);

  const item = withIOSCollectionBrowserColumnCount(
    collectionItem, ratios.collectionBrowserColumnCount
  );
  delete item.aspectRatio;
  delete item.tmp_files;
  if (ratios.aspectRatio != null) item.aspectRatio = ratios.aspectRatio;
  if (tmpFiles.payload.tmp_files != null) item.tmp_files = tmpFiles.payload.tmp_files;
  if (typeof item.hasMid !== "boolean") delete item.hasMid;
  return { payload: ratios.payload, collectionItem: item };
}

module.exports = { preserveTokenMetadataFromFile };

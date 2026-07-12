#!/usr/bin/env node

"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const fsp = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const process = require("node:process");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");

const execFileAsync = promisify(execFile);

const REPO_ROOT = path.resolve(__dirname, "..");
const ORIGINALS_ROOT = path.join(REPO_ROOT, "Originals Downloaded");
const PRIMARY_TOKENS_ROOT = path.join(REPO_ROOT, "Suggested Items", "Suggested.bundle", "Tokens");
const WIDGET_TOKENS_ROOT = path.join(REPO_ROOT, "Suggested Items", "WidgetSuggested.bundle", "Tokens");
const REPORT_PATH = path.join(ORIGINALS_ROOT, "filename-cleanup-report.json");

const EXPECTED_COLLECTIONS = 109;
const EXPECTED_PHYSICAL_FILES = 145_179;
const EXPECTED_SOLANA_MINTS = 65_332;
const EXPECTED_WIDGET_COLLECTIONS = 32;
const EXPECTED_JSON_MANIFESTS = 83;
const EXPECTED_ONE_BYTE_FILES = 28;
const EXPECTED_SYNTHETIC_REPAIRS = 2;

const EXPECTED_MISSING = Object.freeze([
  "moeshit/1093.png",
  "moeshit/1112.png",
  "moeshit/1119.jpg",
  "moeshit/1124.png",
  "moeshit/1133.png",
  "moeshit/1135.png",
  "moeshit/1149.png",
]);

const PREFIX_BASES = Object.freeze({
  archetype: "23000000",
  beyond_the_veil: "580000",
  fidenza: "78000000",
  flore_perdue: "29000000",
  fragments_of_an_infinite_field: "159000000",
  landscape_sublime: "680000",
  letters_to_my_future_self: "174000000",
  math_art: "430000",
  meridian: "163000000",
  parnassus: "2000000",
  ringers: "13000000",
  storms: "160000",
  the_eternal_pump: "22000000",
  tokyo_nude: "280000",
});

const SYNTHETIC_NON_SOLANA = new Set(["screenshot_catalog", "vacation"]);

const APPROVED_SOLANA_REPAIRS = Object.freeze({
  cloudcastle: {
    duplicateId: "0",
    missingId: "9",
    mints: [
      "HmTNthqfH81V6GnPEGcMkREBUE3e3WqaP7dgmstiCgca",
      "GngC88gV7Q3RYmDjvJmV9SjxJHexcVAhmHHCyxNjZhmp",
    ],
  },
  pray4lowbie: {
    duplicateId: "0",
    missingId: "10",
    mints: [
      "H81xDmV8wzc6AoDsi3hsoyN2H8kmRucvxNmRMj6D5SFu",
      "2NH3pwVBJKKpz8BwBW1vBpUFw1Wbjp6H1Yzd4L5XRP8P",
    ],
  },
});

const EXTENSION_BY_KIND = Object.freeze({
  gif: "gif",
  glb: "glb",
  heic: "heic",
  html: "html",
  jpg: "jpg",
  json: "json",
  mov: "mov",
  mp4: "mp4",
  pdf: "pdf",
  png: "png",
  svg: "svg",
  tiff: "tiff",
  webm: "webm",
  webp: "webp",
});

const RETRYABLE_HTTP_STATUS = new Set([408, 425, 429, 500, 502, 503, 504]);
const BASE58_MINT = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/u;
const DECIMAL = /^\d+$/u;
const SAFE_BASENAME = /^[^/\\\0]+$/u;
const MANIFEST_NAME = "manifest.json";
const CLEANUP_VERSION = 1;
const LOCK_DIRECTORY_NAME = ".filename-cleanup-lock";
const AUDITED_CONTENT_REPLACEMENTS = new Map([
  ["beyond_the_veil", "580011", "580011.png", "580011.jpeg", "9c152c0738c7e158e8b714932204bd652d3174ce04f23b638fa7d33debfd1f3a", 100_153, "7c15b7e53701133cbb4767f46137862590856aa502b06e3c6c2e753c086953be", 9_299_948, "jpg"],
  ["bloomers", "336", "336.png", "336.png", "bada2d86506d3929d1ef41ff3e4533c58b4feb0f5a58fdc18b780db0171f9b44", 65_913, "be3f6b9186ad95b534acfade735846d119aa20ce24b572962671290f357debab", 1_200_839, "png"],
  ["bloomers", "351", "351.png", "351.png", "764d8bef1da9930dd28b5925f0a64c76ba4c3c58ef05e5303cd10c5b8833259b", 73_286, "9f57ea633d33e2191740abb0f382161195c9317336aa810ca3e1bd78bc6c0c91", 614_364, "png"],
  ["bloomers", "358", "358.png", "358.png", "8a05bb27c1809e88899ff981f8cf4f7a81826914bbfea4c7d231247b553a22e3", 118_512, "d547c90f67c71a94d7179e728d14136417771ae458bb5e55b803a06d507e281a", 3_122_410, "png"],
  ["bloomers", "361", "361.png", "361.png", "53e50e96e020bc6a340208f0607ecf23aeda41756016765cef7be4efb65aac72", 62_720, "16aa32a55e54a539d06c731ddbd1f0997543bbfec05ef1bd2ffb7bf2d7900875", 643_618, "png"],
  ["bloomers", "363", "363.png", "363.png", "cafa24c297261169bf0bf3650c77fcb8882379a2a6eb40a14229b63ae96fa47a", 54_003, "6a47d840cde99674b864e240dd6410a01b4f55856c31777a923d1828bc9797b4", 1_087_344, "png"],
  ["bloomers", "365", "365.png", "365.png", "9a472f81763e072bac99bc4907189115c9c92c5024991745d022952fd82d7acb", 73_845, "2482b01cd3734dd570f2ccf1e59a0c6947875e160dad3a788e9db0ae346d8deb", 1_269_006, "png"],
  ["bloomers", "371", "371.png", "371.png", "e0777ef9a6fb6e2ee0b6ff6ab422dd951dc6884f9b8bc8978088ad214a502491", 59_793, "aac98fac6db547d7413685444b91e878221c879e3c316ec40c1f258779d0878c", 520_348, "png"],
  ["bloomers", "380", "380.png", "380.png", "4d9318250e9af4cb2e7efaddd64256fc78e87e2ad2f07046003f7476d57cb766", 78_471, "6bd19483542b180f208e23bff68e249f55e29d4acfb32adc744fca92bb5c7db0", 1_525_723, "png"],
  ["bloomers", "396", "396.png", "396.png", "cdfb7cae81718edd06d3c156125bfb930b0717642e6b5dab65fb1d3a3693bfb0", 66_027, "c3cb7904a8e730d2ecd548508f0512e1e1df79b31940d0c2f56660edaddfa823", 1_270_288, "png"],
  ["bloomers", "406", "406.png", "406.png", "a493c92b3ea3fd1fd3fdec7d6699e6254186cfb2c4944e3b362593a5578034df", 71_115, "fa432bc068f5194ef2bb6c1a71cc17c8aaa904378fae4db57d876a70d1948048", 886_859, "png"],
  ["bloomers", "409", "409.png", "409.png", "b63adc172694fb06f12e562d6143904121dac060289b758a96b40ab9983fdf91", 62_102, "84567ab0f195fb0c5a1ecc1845132de9672331866e7a67bf5fe1b1040dc18142", 1_495_128, "png"],
  ["bloomers", "436", "436.png", "436.png", "0035fef22c6389558ef2111548750fd93a7f7a3f35bf36d6896a7d7b7d567088", 76_882, "47c5ea4464c4507182d756d27e27a921b5d76fb75ba3586d6beed8d801adc848", 2_008_787, "png"],
  ["bloomers", "447", "447.png", "447.png", "5692f5be5a5dece33ac8505bbaf1afcb6ec17f0038e646225951676a11ab3dbc", 85_584, "832b462d2a6899a09406ae83e0b3113a1ac825d88d258f8f923e63ee25eb1938", 1_779_213, "png"],
  ["bloomers", "458", "458.png", "458.png", "de5ad4ee2fd90136d2b12174bd051b941248478f7475293e7c9ba340d00e72f4", 80_979, "3e1f75a41a4bdc6f92967a7bdb87c517a68278fb66f4112038855a69ba3c0eed", 1_653_841, "png"],
  ["bloomers", "460", "460.png", "460.png", "ecd70d238dc7c1b100d725bfcec05d28e7c9e45739558062e1e7170ce8921fc8", 87_705, "c1d1c2882ee5758dc16898453c73e2d07b611c68087a8e4f780e5ba849748f60", 1_147_821, "png"],
  ["bloomers", "467", "467.png", "467.png", "3a3e69eb7f1c5ec410024b89125f95f4b23127621e513226a923e0d7d1527da9", 81_827, "01d1e0877aa0c495d8ef98faf678497d0284c8d296bc331b6a432e866ac9b384", 1_523_256, "png"],
  ["bloomers", "471", "471.png", "471.png", "e4d3efe8508523f5bbc76cb0ed928b8be03a99f15f9ceca2c4ec1c24aefbc738", 77_551, "cb12707fe21559fbabb8817a096ca150a22e961131bdb5f646b554a2f0c004fb", 1_472_183, "png"],
  ["bloomers", "483", "483.png", "483.png", "9ae9fd882ed9674d4411e8ad856c91b78d714abda1853728a59fcd7f64fe2e47", 72_538, "1409e00b25ebca4b9bcc56f2b3a9064f923be71fd8c388073a07e111fa90d78f", 1_290_988, "png"],
  ["bloomers", "491", "491.png", "491.png", "b490f544bfb3a3e401981d137f69c0d3819c69df99e90e1b1cc2b6eed0c0f069", 72_467, "43fe485b97763023a63517f055f15585b2bb5e2d9d25a38e0bf00f40bf3111c0", 837_414, "png"],
  ["bloomers", "501", "501.png", "501.png", "dd92a560fce32508d888a6efcc565cacb534a09623b9dcdadc39f469398ac41c", 74_635, "43f6786887ceda81de872afd485f49bac12c98f9548eb0bc3800ecde780f7098", 1_082_394, "png"],
  ["screenshot_catalog", "1663259644", "1663259644.png", "1663259644.png", "41f630cc44c45068c4ea90e9e61089104eab9638718f7e87e88bc5aec4c16c6b", 18_152, "2015011d9b1a0bd03e11e2c9d264a36692246e2acfa2bfefe72b74ccff1f4acb", 104_421, "png"],
  ["tubbypxgan", "1333", "1333.png", "1333.png", "5f61b74a04cee966361055e41812cadbed694b88f15a05c71fc75f196a49220c", 6_533, "048f9d3c8b9275e098a6fba5d5e2ccd7c310d8a9f931f34c7bf2e30ac6bd1d91", 4_346, "png"],
  ["tubbypxgan", "211", "211.png", "211.png", "6e9fef3eea72ecd92e659132a71a8e51e26005b066d14aae16986c7aea93a912", 10_668, "89739ca6f4ae15e7afc089e0b9e4db1eeeb56e6c24f0de97a6043e177ee36c6d", 10_540, "png"],
  ["tubbypxgan", "66", "66.png", "66.png", "cf63cc35d9f75ddbcb64a5bb9e890e78746cb1ac27340026e9b93947a183cf34", 6_011, "af8dc4a8461207d791d6ba31c99be9c1c6c879ef70afb554417213e178ed9958", 3_841, "png"],
  ["tubbypxgan", "931", "931.png", "931.png", "873c2199a034afca95f592a7e6b838ce7c1383bb95e60317eae52741663255a9", 6_208, "bcc802b04f61229bd3a2b4ff476cd8a9bc3049d5de3fd991b72d91a96067553e", 6_640, "png"],
].map(([slug, tokenId, manifestFileName, physicalFileName, manifestSha256, manifestBytes, actualSha256, actualBytes, kind]) => [
  `${slug}\0${tokenId}`,
  Object.freeze({ slug, tokenId, manifestFileName, physicalFileName, manifestSha256, manifestBytes, actualSha256, actualBytes, kind }),
]));
const RECORD_OF_HYPERWAR_DUPLICATE = Object.freeze({
  slug: "record_of_hyperwar",
  ordinal: "0",
  mintsByExtension: Object.freeze({
    png: "AfpgARLXMYdx39KU8Rmko5LiKZzxwVkUBww979r7ZN3g",
    mp4: "7ux4UTRhtQxnn2DhtScR1sgCc1UB2uUnDKCHXpMo9tpV",
  }),
});

class CleanupError extends Error {
  constructor(message, details = undefined) {
    super(message);
    this.name = "CleanupError";
    this.details = details;
  }
}

async function main(argv = process.argv.slice(2)) {
  const options = parseArguments(argv);
  if (options.help) {
    printHelp();
    return;
  }

  if (options.apply && options.recover) {
    throw new CleanupError("--apply and --recover are mutually exclusive.");
  }

  let lock = null;
  if (options.apply || options.recover) {
    lock = await acquireCleanupLock(options.repoRoot, { forRecovery: options.recover });
  }
  try {
    if (options.recover) {
      const result = await recoverStaleTransaction(options.repoRoot);
      console.log(result);
      return;
    }

    const mode = options.apply ? "APPLY" : "DRY RUN";
    console.log(`[${mode}] Loading 109 downloaded collection manifests and token bundles...`);
    const plan = await buildCleanupPlan({
      repoRoot: options.repoRoot,
      heliusApiKey: options.heliusApiKey,
      hashConcurrency: options.hashConcurrency,
      heliusConcurrency: options.heliusConcurrency,
      strictCorpus: !options.allowFixture,
    });

    printPlanSummary(plan, mode);
    if (!options.apply) {
      console.log("Dry run complete. No files were changed. Re-run with --apply to commit this verified plan.");
      return;
    }
    if (plan.alreadyNormalized) {
      console.log("The corpus is already normalized and its audit report is intact. No files were changed.");
      return;
    }

    await applyCleanupPlan(plan);
    console.log(`Cleanup applied successfully. Report: ${path.relative(plan.repoRoot, plan.reportPath)}`);
  } finally {
    await lock?.release();
  }
}

function parseArguments(argv) {
  const options = {
    apply: false,
    recover: false,
    help: false,
    repoRoot: REPO_ROOT,
    heliusApiKey: null,
    hashConcurrency: 4,
    heliusConcurrency: 6,
    allowFixture: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--apply") {
      options.apply = true;
    } else if (argument === "--recover") {
      options.recover = true;
    } else if (argument === "--help" || argument === "-h") {
      options.help = true;
    } else if (argument === "--repo-root") {
      options.repoRoot = path.resolve(requireValue(argv, ++index, argument));
    } else if (argument === "--helius-api-key") {
      options.heliusApiKey = requireValue(argv, ++index, argument);
    } else if (argument === "--hash-concurrency") {
      options.hashConcurrency = positiveInteger(requireValue(argv, ++index, argument), argument);
    } else if (argument === "--helius-concurrency") {
      options.heliusConcurrency = positiveInteger(requireValue(argv, ++index, argument), argument);
    } else if (argument === "--allow-fixture") {
      options.allowFixture = true;
    } else {
      throw new CleanupError(`Unknown argument: ${argument}`);
    }
  }
  return options;
}

function printHelp() {
  console.log(`Usage: node tools/normalize_downloaded_originals.js [options]

Strictly verify and normalize files inside Originals Downloaded. The default is a
read-only dry run. --apply repeats the complete preflight and commits the plan.

Options:
  --apply                    Commit the verified rename and JSON transaction
  --recover                  Roll back one interrupted transaction, or finalize a completed one
  --helius-api-key VALUE     Override HELIUS_API_KEY / local tools secret
  --hash-concurrency N       Concurrent full-file hash streams (default: 4)
  --helius-concurrency N     Concurrent Helius batches (default: 6)
  --repo-root PATH           Repository root (primarily for focused tests)
  --help                     Show this help
`);
}

async function buildCleanupPlan({
  repoRoot = REPO_ROOT,
  heliusApiKey = null,
  hashConcurrency = 4,
  heliusConcurrency = 6,
  strictCorpus = true,
} = {}) {
  const resolvedRoot = path.resolve(repoRoot);
  const originalsRoot = path.join(resolvedRoot, "Originals Downloaded");
  const primaryRoot = path.join(resolvedRoot, "Suggested Items", "Suggested.bundle", "Tokens");
  const widgetRoot = path.join(resolvedRoot, "Suggested Items", "WidgetSuggested.bundle", "Tokens");
  const reportPath = path.join(originalsRoot, "filename-cleanup-report.json");
  await rejectStaleTransactions(resolvedRoot);

  const [collections, primaryBundles, widgetBundles] = await Promise.all([
    loadCollections(originalsRoot),
    loadTokenBundles(primaryRoot, "primary"),
    loadTokenBundles(widgetRoot, "widget"),
  ]);

  if (strictCorpus && collections.length !== EXPECTED_COLLECTIONS) {
    throw new CleanupError(`Found ${collections.length} downloaded collection directories; expected ${EXPECTED_COLLECTIONS}.`);
  }

  const inventory = mapPhysicalFiles(collections, primaryBundles);
  const downloadedCollectionIds = new Set(collections.map((collection) => collection.collectionId));
  for (const primary of primaryBundles.values()) {
    if (!downloadedCollectionIds.has(primary.collectionId) && Object.hasOwn(primary.payload, "tmp_files")) {
      throw new CleanupError(`Unaffected primary bundle ${primary.fileName} unexpectedly has tmp_files.`);
    }
  }
  if (strictCorpus) {
    assertExactCorpusInventory(inventory);
  }

  const solanaRecords = inventory.records.filter((record) => record.collection.chain === "solana");
  if (strictCorpus && solanaRecords.length !== EXPECTED_SOLANA_MINTS) {
    throw new CleanupError(`Mapped ${solanaRecords.length} present Solana mints; expected ${EXPECTED_SOLANA_MINTS}.`);
  }

  const keyPromise = solanaRecords.length > 0
    ? resolveHeliusApiKey(heliusApiKey)
    : Promise.resolve(null);

  console.log(`Preflight mapped ${inventory.records.length.toLocaleString()} physical files. Hashing every byte and resolving ${solanaRecords.length.toLocaleString()} Solana mints...`);
  const [inspections, heliusAssets] = await Promise.all([
    inspectPhysicalFiles(inventory.records, hashConcurrency),
    keyPromise.then((key) => fetchHeliusAssets(solanaRecords.map((record) => record.tokenId), key, heliusConcurrency)),
  ]);

  for (let index = 0; index < inventory.records.length; index += 1) {
    inventory.records[index].inspection = inspections[index];
  }
  verifyManifestHashes(inventory.records, strictCorpus);

  const naming = resolveNormalizedIds(collections, inventory.records, heliusAssets, strictCorpus);
  assignTargetFileNames(inventory.records, naming.localIds);
  validateRenamePlan(inventory.records);

  const warningFiles = collectWarningFiles(inventory.records);
  if (strictCorpus) {
    if (warningFiles.arweaveJsonManifests.length !== EXPECTED_JSON_MANIFESTS) {
      throw new CleanupError(`Found ${warningFiles.arweaveJsonManifests.length} Arweave JSON path manifests; expected ${EXPECTED_JSON_MANIFESTS}.`);
    }
    if (warningFiles.oneByteFiles.length !== EXPECTED_ONE_BYTE_FILES) {
      throw new CleanupError(`Found ${warningFiles.oneByteFiles.length} one-byte files; expected ${EXPECTED_ONE_BYTE_FILES}.`);
    }
  }

  const existingReport = await readJsonIfExists(reportPath);
  const alreadyNormalized = isAlreadyNormalized({
    collections,
    inventory,
    primaryBundles,
    widgetBundles,
    warningFiles,
    existingReport,
  });
  const timestamp = new Date().toISOString();
  const jsonUpdates = await buildJsonUpdates({
    collections,
    primaryBundles,
    widgetBundles,
    inventory,
    naming,
    warningFiles,
    timestamp,
    originalsRoot,
    reportPath,
    existingReport,
    strictCorpus,
  });

  return {
    repoRoot: resolvedRoot,
    originalsRoot,
    reportPath,
    collections,
    records: inventory.records,
    missing: inventory.missing,
    renames: inventory.records.filter((record) => record.currentName !== record.targetName),
    naming,
    warningFiles,
    alreadyNormalized,
    hashConcurrency,
    timestamp,
    ...jsonUpdates,
  };
}

async function loadCollections(originalsRoot) {
  const entries = await fsp.readdir(originalsRoot, { withFileTypes: true });
  const collections = [];
  for (const entry of entries.sort((left, right) => naturalCompare(left.name, right.name))) {
    if (!entry.isDirectory()) {
      continue;
    }
    if (entry.name.startsWith(".filename-cleanup-transaction-")) {
      throw new CleanupError(`Unfinished cleanup transaction exists: ${entry.name}`);
    }
    const directoryPath = path.join(originalsRoot, entry.name);
    const manifestPath = path.join(directoryPath, MANIFEST_NAME);
    const manifest = await readJson(manifestPath);
    if (!Array.isArray(manifest.tokens)) {
      throw new CleanupError(`${relative(originalsRoot, manifestPath)} has no tokens array.`);
    }
    const collectionId = stringValue(manifest?.collection?.id);
    if (!collectionId) {
      throw new CleanupError(`${relative(originalsRoot, manifestPath)} has no collection.id.`);
    }
    const slug = entry.name;
    const manifestSlug = stringValue(manifest?.collection?.internal_slug);
    if (manifestSlug && manifestSlug !== slug) {
      throw new CleanupError(`${slug}/manifest.json declares internal_slug ${manifestSlug}.`);
    }
    const chain = String(manifest?.collection?.chain ?? "").toLowerCase();
    const directoryEntries = await fsp.readdir(directoryPath, { withFileTypes: true });
    const physicalNames = [];
    for (const child of directoryEntries) {
      if (child.name === MANIFEST_NAME) {
        continue;
      }
      if (!child.isFile()) {
        throw new CleanupError(`${slug}/${child.name} is not a regular file.`);
      }
      if (!isSafeBasename(child.name) || child.name.startsWith(".filename-cleanup-")) {
        throw new CleanupError(`${slug}/${child.name} is unsafe or is a stale cleanup temporary file.`);
      }
      physicalNames.push(child.name);
    }
    collections.push({
      slug,
      chain,
      collectionId,
      directoryPath,
      manifestPath,
      manifest,
      physicalNames: physicalNames.sort(naturalCompare),
    });
  }
  return collections;
}

async function loadTokenBundles(root, label) {
  const entries = await fsp.readdir(root, { withFileTypes: true });
  const bundles = new Map();
  for (const entry of entries.sort((left, right) => naturalCompare(left.name, right.name))) {
    if (!entry.isFile() || path.extname(entry.name).toLowerCase() !== ".json") {
      continue;
    }
    const filePath = path.join(root, entry.name);
    const payload = await readJson(filePath);
    const itemIds = tokenIdsFromPayload(payload, `${label} bundle ${entry.name}`);
    const collectionId = entry.name.slice(0, -5);
    bundles.set(collectionId, { collectionId, filePath, fileName: entry.name, payload, itemIds, label });
  }
  return bundles;
}

function mapPhysicalFiles(collections, primaryBundles) {
  const records = [];
  const missing = [];
  const collectionById = new Set();

  for (const collection of collections) {
    if (collectionById.has(collection.collectionId)) {
      throw new CleanupError(`Duplicate downloaded collection ID ${collection.collectionId}.`);
    }
    collectionById.add(collection.collectionId);
    const primary = primaryBundles.get(collection.collectionId);
    if (!primary) {
      throw new CleanupError(`${collection.slug} has no primary bundle ${collection.collectionId}.json.`);
    }
    collection.primary = primary;

    const manifestIds = collection.manifest.tokens.map((token, index) => {
      const tokenId = stringValue(token?.tokenId);
      if (!tokenId) {
        throw new CleanupError(`${collection.slug}/manifest.json token[${index}] has no tokenId.`);
      }
      return tokenId;
    });
    assertArrayEqual(manifestIds, primary.itemIds, `${collection.slug} manifest token IDs vs primary bundle item IDs`);

    const physicalSet = new Set(collection.physicalNames);
    const byStem = new Map();
    for (const fileName of collection.physicalNames) {
      const stem = path.parse(fileName).name;
      const values = byStem.get(stem) ?? [];
      values.push(fileName);
      byStem.set(stem, values);
    }
    const used = new Set();
    const existingTmpFiles = isPlainObject(primary.payload.tmp_files) ? primary.payload.tmp_files : {};

    for (let tokenIndex = 0; tokenIndex < collection.manifest.tokens.length; tokenIndex += 1) {
      const token = collection.manifest.tokens[tokenIndex];
      const tokenId = manifestIds[tokenIndex];
      const candidates = [];
      const addCandidate = (candidate) => {
        if (typeof candidate === "string" && physicalSet.has(candidate) && !candidates.includes(candidate)) {
          candidates.push(candidate);
        }
      };
      addCandidate(existingTmpFiles[tokenId]);
      addCandidate(token.fileName);
      for (const candidate of byStem.get(tokenId) ?? []) {
        addCandidate(candidate);
      }
      const available = candidates.filter((candidate) => !used.has(candidate));
      if (available.length > 1) {
        throw new CleanupError(`${collection.slug} token ${tokenId} ambiguously maps to ${available.join(", ")}.`);
      }
      if (available.length === 0) {
        const expectedName = typeof token.fileName === "string" ? token.fileName : `${tokenId}.${token.extension ?? "unknown"}`;
        missing.push({ collection, token, tokenId, tokenIndex, expectedName });
        continue;
      }
      const currentName = available[0];
      used.add(currentName);
      records.push({
        collection,
        token,
        tokenId,
        tokenIndex,
        currentName,
        currentPath: path.join(collection.directoryPath, currentName),
      });
    }

    const unused = collection.physicalNames.filter((fileName) => !used.has(fileName));
    if (unused.length > 0) {
      throw new CleanupError(`${collection.slug} has ${unused.length} unreferenced physical file(s): ${unused.slice(0, 10).join(", ")}`);
    }
  }

  return { records, missing };
}

function assertExactCorpusInventory(inventory) {
  if (inventory.records.length !== EXPECTED_PHYSICAL_FILES) {
    throw new CleanupError(`Mapped ${inventory.records.length} physical files; expected ${EXPECTED_PHYSICAL_FILES}.`);
  }
  const actualMissing = inventory.missing
    .map((entry) => `${entry.collection.slug}/${entry.expectedName}`)
    .sort(naturalCompare);
  const expectedMissing = [...EXPECTED_MISSING].sort(naturalCompare);
  assertArrayEqual(actualMissing, expectedMissing, "physically missing manifest rows");
}

async function inspectPhysicalFiles(records, concurrency) {
  let completed = 0;
  let bytes = 0;
  const started = Date.now();
  const timer = setInterval(() => {
    console.log(`Hash progress: ${completed.toLocaleString()}/${records.length.toLocaleString()} files, ${formatBytes(bytes)} read.`);
  }, 30_000);
  timer.unref();
  try {
    return await mapWithConcurrency(records, concurrency, async (record) => {
      const inspection = await hashAndInspectFile(record.currentPath);
      completed += 1;
      bytes += inspection.size;
      if (completed % 5_000 === 0 || completed === records.length) {
        const seconds = Math.max(1, (Date.now() - started) / 1000);
        console.log(`Hash progress: ${completed.toLocaleString()}/${records.length.toLocaleString()} files, ${formatBytes(bytes)} read (${formatBytes(bytes / seconds)}/s).`);
      }
      return inspection;
    });
  } finally {
    clearInterval(timer);
  }
}

async function hashAndInspectFile(filePath) {
  const hash = crypto.createHash("sha256");
  const headChunks = [];
  let headLength = 0;
  let size = 0;
  const stream = fs.createReadStream(filePath);
  for await (const chunk of stream) {
    hash.update(chunk);
    size += chunk.length;
    if (headLength < 4096) {
      const wanted = Math.min(chunk.length, 4096 - headLength);
      headChunks.push(chunk.subarray(0, wanted));
      headLength += wanted;
    }
  }
  const stat = await fsp.stat(filePath);
  if (!stat.isFile() || stat.size !== size) {
    throw new CleanupError(`${filePath} changed while it was being hashed.`);
  }
  const head = Buffer.concat(headChunks, headLength);
  let kind = detectFileKind(head, size);
  let jsonValue = null;
  if (kind === "json") {
    try {
      jsonValue = JSON.parse(await fsp.readFile(filePath, "utf8"));
    } catch (error) {
      throw new CleanupError(`${filePath} begins like JSON but is invalid: ${error.message}`);
    }
  }
  if (kind === "unknown") {
    throw new CleanupError(`${filePath} has an unrecognized file signature.`);
  }
  const currentExtension = path.extname(filePath).slice(1).toLowerCase();
  const canonicalExtension = kind === "one-byte" ? currentExtension : EXTENSION_BY_KIND[kind];
  if (!canonicalExtension) {
    throw new CleanupError(`${filePath} has no canonical extension for detected kind ${kind}.`);
  }
  return {
    sha256: hash.digest("hex"),
    size,
    dev: stat.dev,
    ino: stat.ino,
    kind,
    canonicalExtension,
    jsonValue,
  };
}

function detectFileKind(bytes, fileSize = bytes.length) {
  if (fileSize === 1) return "one-byte";
  if (startsWith(bytes, [0xff, 0xd8, 0xff])) return "jpg";
  if (startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return "png";
  if (/^GIF8[79]a/u.test(ascii(bytes, 0, 6))) return "gif";
  if (ascii(bytes, 0, 4) === "RIFF" && ascii(bytes, 8, 12) === "WEBP") return "webp";
  if (ascii(bytes, 0, 4) === "glTF") return "glb";
  if (startsWith(bytes, [0x49, 0x49, 0x2a, 0x00]) || startsWith(bytes, [0x4d, 0x4d, 0x00, 0x2a])) return "tiff";
  if (ascii(bytes, 0, 5) === "%PDF-") return "pdf";
  if (ascii(bytes, 4, 8) === "ftyp") {
    const brand = ascii(bytes, 8, 12);
    if (brand === "qt  ") return "mov";
    if (["heic", "heix", "hevc", "hevx", "mif1", "msf1"].includes(brand)) return "heic";
    return "mp4";
  }
  if (startsWith(bytes, [0x1a, 0x45, 0xdf, 0xa3])) return "webm";
  const text = bytes.toString("utf8");
  if (/^(?:\uFEFF)?\s*[{[]/u.test(text)) return "json";
  const trimmed = text.replace(/^\uFEFF/u, "").trimStart();
  if (/^(?:<!doctype\s+html|<html[\s>])/iu.test(trimmed)) return "html";
  if (/^(?:<\?xml[\s\S]{0,400}<svg|<svg[\s>])/iu.test(trimmed)) return "svg";
  return "unknown";
}

function verifyManifestHashes(records, strictCorpus) {
  const acceptedDrifts = [];
  for (const record of records) {
    const expectedHash = String(record.token.sha256 ?? "").toLowerCase();
    const expectedBytes = Number(record.token.bytesWritten);
    const matches = /^[a-f0-9]{64}$/u.test(expectedHash)
      && expectedHash === record.inspection.sha256
      && Number.isFinite(expectedBytes)
      && expectedBytes === record.inspection.size;
    if (matches) {
      continue;
    }
    const auditedReplacement = auditedContentReplacement(record);
    if (auditedReplacement) {
      acceptedDrifts.push(record);
      record.auditedContentReplacement = auditedReplacement;
      continue;
    }
    throw new CleanupError(
      `${record.collection.slug}/${record.currentName} does not match its manifest hash/size `
      + `(manifest ${expectedHash || "missing"}/${expectedBytes}, actual ${record.inspection.sha256}/${record.inspection.size}).`
    );
  }
  if (strictCorpus && acceptedDrifts.length !== 0 && acceptedDrifts.length !== AUDITED_CONTENT_REPLACEMENTS.size) {
    throw new CleanupError(
      `Found ${acceptedDrifts.length}/${AUDITED_CONTENT_REPLACEMENTS.size} exact audited content replacements. `
      + "Expected either the complete pre-cleanup replacement batch or an already-updated corpus."
    );
  }
}

function auditedContentReplacement(record) {
  const expected = AUDITED_CONTENT_REPLACEMENTS.get(`${record.collection.slug}\0${record.tokenId}`);
  if (!expected) return null;
  return record.currentName === expected.physicalFileName
    && record.token.fileName === expected.manifestFileName
    && String(record.token.sha256).toLowerCase() === expected.manifestSha256
    && Number(record.token.bytesWritten) === expected.manifestBytes
    && record.inspection.sha256 === expected.actualSha256
    && record.inspection.size === expected.actualBytes
    && record.inspection.kind === expected.kind
    ? expected
    : null;
}

function resolveNormalizedIds(collections, records, heliusAssets, strictCorpus) {
  const localIds = new Map();
  const solanaSources = {};
  const collectionNamingSources = {};
  const repairs = [];
  const recordsByCollection = groupBy(records, (record) => record.collection.slug);

  for (const collection of collections) {
    const collectionRecords = recordsByCollection.get(collection.slug) ?? [];
    if (collection.chain === "solana") {
      const result = resolveSolanaCollectionIds(collection, collectionRecords, heliusAssets);
      for (const [tokenId, localId] of result.localIds) {
        localIds.set(`${collection.slug}\0${tokenId}`, localId);
      }
      solanaSources[collection.slug] = {
        method: result.method,
        assets: collectionRecords.length,
        repairs: result.repairs,
      };
      collectionNamingSources[collection.slug] = {
        kind: "helius-das",
        method: result.method,
        keyedBy: "mint",
      };
      repairs.push(...result.repairs.map((repair) => ({ collection: collection.slug, ...repair })));
      continue;
    }

    const allTokenIds = collection.manifest.tokens.map((token) => String(token.tokenId));
    let ids;
    if (Object.hasOwn(PREFIX_BASES, collection.slug)) {
      const base = BigInt(PREFIX_BASES[collection.slug]);
      collectionNamingSources[collection.slug] = {
        kind: "shared-contract-prefix",
        operation: "subtract",
        base: String(base),
      };
      ids = new Map(allTokenIds.map((tokenId) => {
        const value = decimalBigInt(tokenId, `${collection.slug} token ID`);
        if (value < base) {
          throw new CleanupError(`${collection.slug} token ${tokenId} is below audited prefix ${base}.`);
        }
        return [tokenId, String(value - base)];
      }));
      assertContiguousZeroBased(ids.values(), `${collection.slug} prefix-stripped IDs`);
    } else if (SYNTHETIC_NON_SOLANA.has(collection.slug)) {
      collectionNamingSources[collection.slug] = {
        kind: "synthetic-numeric-sort",
        zeroBased: true,
      };
      const sorted = [...allTokenIds].sort(compareDecimalStrings);
      if (new Set(sorted).size !== sorted.length) {
        throw new CleanupError(`${collection.slug} has duplicate original token IDs.`);
      }
      ids = new Map(sorted.map((tokenId, index) => [tokenId, String(index)]));
    } else {
      collectionNamingSources[collection.slug] = {
        kind: "token-id",
        preservesGaps: true,
      };
      ids = new Map(allTokenIds.map((tokenId) => {
        decimalBigInt(tokenId, `${collection.slug} token ID`);
        return [tokenId, normalizeDecimal(tokenId)];
      }));
    }
    for (const record of collectionRecords) {
      localIds.set(`${collection.slug}\0${record.tokenId}`, ids.get(record.tokenId));
    }
  }

  if (strictCorpus && repairs.length !== EXPECTED_SYNTHETIC_REPAIRS) {
    throw new CleanupError(`Applied ${repairs.length} Solana synthetic repairs; expected ${EXPECTED_SYNTHETIC_REPAIRS}.`);
  }
  return { localIds, solanaSources, collectionNamingSources, repairs };
}

function resolveSolanaCollectionIds(collection, records, assetsByMint) {
  const methods = [
    { name: "metadata-name", extract: numericMetadataName },
    { name: "metadata-uri", extract: numericMetadataUri },
    { name: "media-uri", extract: numericMediaUri },
  ];
  const failures = [];

  for (const method of methods) {
    const candidate = new Map();
    let incomplete = false;
    let ambiguous = false;
    for (const record of records) {
      const asset = assetsByMint.get(record.tokenId);
      if (!asset) {
        throw new CleanupError(`${collection.slug}: Helius omitted mint ${record.tokenId}.`);
      }
      const result = method.extract(asset);
      if (result.status === "missing") {
        incomplete = true;
        break;
      }
      if (result.status === "ambiguous") {
        ambiguous = true;
        break;
      }
      candidate.set(record.tokenId, result.value);
    }
    if (incomplete || ambiguous) {
      failures.push(`${method.name}:${ambiguous ? "ambiguous" : "incomplete"}`);
      continue;
    }

    const ordinalCollisions = ordinalCollisionGroups(records, candidate);
    const unapprovedOrdinalCollisions = ordinalCollisions.filter((group) => (
      !isApprovedRecordOfHyperwarDuplicate(collection, group)
      && !isPotentialSyntheticRepair(collection, group)
    ));
    if (unapprovedOrdinalCollisions.length > 0) {
      failures.push(`${method.name}:ordinal-collisions(${formatOrdinalCollisionGroups(unapprovedOrdinalCollisions)})`);
      continue;
    }

    const collisionGroups = targetCollisionGroups(records, candidate);
    if (collisionGroups.length === 0) {
      return { localIds: candidate, method: method.name, repairs: [] };
    }

    const repair = APPROVED_SOLANA_REPAIRS[collection.slug];
    if (!repair || !matchesApprovedRepair(collisionGroups, candidate, repair)) {
      failures.push(`${method.name}:collisions(${formatCollisionGroups(collisionGroups)})`);
      continue;
    }

    const repaired = new Map(candidate);
    const sortedMints = [...repair.mints].sort();
    repaired.set(sortedMints[0], repair.duplicateId);
    repaired.set(sortedMints[1], repair.missingId);
    const remainingCollisions = targetCollisionGroups(records, repaired);
    if (remainingCollisions.length > 0) {
      throw new CleanupError(`${collection.slug}: approved repair did not remove all collisions.`);
    }
    return {
      localIds: repaired,
      method: method.name,
      repairs: [{
        duplicateId: repair.duplicateId,
        missingId: repair.missingId,
        keptMint: sortedMints[0],
        reassignedMint: sortedMints[1],
      }],
    };
  }

  throw new CleanupError(`${collection.slug}: no complete, unambiguous Helius ordinal source (${failures.join("; ")}).`);
}

function ordinalCollisionGroups(records, candidate) {
  const recordsByTokenId = new Map(records.map((record) => [record.tokenId, record]));
  const groups = new Map();
  for (const [tokenId, ordinal] of candidate) {
    const group = groups.get(ordinal) ?? [];
    group.push(recordsByTokenId.get(tokenId));
    groups.set(ordinal, group);
  }
  return [...groups.entries()]
    .filter(([, group]) => group.length > 1)
    .map(([ordinal, group]) => ({ ordinal, records: group }));
}

function isApprovedRecordOfHyperwarDuplicate(collection, group) {
  if (collection.slug !== RECORD_OF_HYPERWAR_DUPLICATE.slug
      || group.ordinal !== RECORD_OF_HYPERWAR_DUPLICATE.ordinal
      || group.records.length !== 2) {
    return false;
  }
  return group.records.every((record) => (
    RECORD_OF_HYPERWAR_DUPLICATE.mintsByExtension[record.inspection.canonicalExtension] === record.tokenId
  ));
}

function isPotentialSyntheticRepair(collection, group) {
  const repair = APPROVED_SOLANA_REPAIRS[collection.slug];
  if (!repair || group.ordinal !== repair.duplicateId || group.records.length !== 2) {
    return false;
  }
  return group.records.map((record) => record.tokenId).sort()
    .every((mint, index) => mint === [...repair.mints].sort()[index]);
}

function numericMetadataName(asset) {
  const name = asset?.content?.metadata?.name;
  if (typeof name !== "string") return { status: "missing" };
  const match = name.trim().match(/(\d+)\s*$/u);
  return match ? { status: "value", value: normalizeDecimal(match[1]) } : { status: "missing" };
}

function numericMetadataUri(asset) {
  return uniqueNumericUriValues([asset?.content?.json_uri]);
}

function numericMediaUri(asset) {
  const values = [];
  for (const file of Array.isArray(asset?.content?.files) ? asset.content.files : []) {
    values.push(file?.uri, file?.cdn_uri);
  }
  const links = asset?.content?.links;
  if (isPlainObject(links)) {
    values.push(links.image, links.animation_url);
  }
  return uniqueNumericUriValues(values);
}

function uniqueNumericUriValues(values) {
  const candidates = new Set();
  let hadUri = false;
  for (const value of values) {
    if (typeof value !== "string" || value.trim() === "") continue;
    hadUri = true;
    const candidate = numericUriBasename(value);
    if (candidate !== null) candidates.add(candidate);
  }
  if (candidates.size === 1) return { status: "value", value: [...candidates][0] };
  if (candidates.size > 1) return { status: "ambiguous" };
  return { status: hadUri ? "missing" : "missing" };
}

function numericUriBasename(value) {
  let pathname;
  try {
    pathname = new URL(value).pathname;
  } catch {
    pathname = value.split(/[?#]/u, 1)[0];
  }
  const pieces = pathname.replace(/\/+$/u, "").split("/");
  let basename = pieces.at(-1) ?? "";
  try {
    basename = decodeURIComponent(basename);
  } catch {
    return null;
  }
  const match = basename.match(/^(\d+)(?:\.[A-Za-z0-9_-]+)?$/u);
  return match ? normalizeDecimal(match[1]) : null;
}

function targetCollisionGroups(records, candidate) {
  const groups = new Map();
  for (const record of records) {
    const localId = candidate.get(record.tokenId);
    if (localId === undefined) continue;
    const fileName = `${localId}.${record.inspection.canonicalExtension}`;
    const group = groups.get(fileName.toLowerCase()) ?? [];
    group.push(record.tokenId);
    groups.set(fileName.toLowerCase(), group);
  }
  return [...groups.entries()].filter(([, mints]) => mints.length > 1);
}

function matchesApprovedRepair(collisionGroups, candidate, repair) {
  if (collisionGroups.length !== 1) return false;
  const [, collidingMints] = collisionGroups[0];
  if (collidingMints.length !== 2) return false;
  if (new Set(collidingMints).size !== 2) return false;
  if (![...collidingMints].sort().every((mint, index) => mint === [...repair.mints].sort()[index])) return false;
  if (!collidingMints.every((mint) => candidate.get(mint) === repair.duplicateId)) return false;
  const allIds = new Set(candidate.values());
  return !allIds.has(repair.missingId);
}

function assignTargetFileNames(records, localIds) {
  for (const record of records) {
    const localId = localIds.get(`${record.collection.slug}\0${record.tokenId}`);
    if (localId === undefined || !DECIMAL.test(localId)) {
      throw new CleanupError(`${record.collection.slug} token ${record.tokenId} has no valid normalized local ID.`);
    }
    record.localId = localId;
    record.targetName = `${localId}.${record.inspection.canonicalExtension}`;
    record.targetPath = path.join(record.collection.directoryPath, record.targetName);
  }
}

function validateRenamePlan(records) {
  const byCollection = groupBy(records, (record) => record.collection.slug);
  for (const [slug, collectionRecords] of byCollection) {
    const currentPaths = new Set(collectionRecords.map((record) => path.resolve(record.currentPath)));
    const targets = new Map();
    const foldedTargets = new Map();
    for (const record of collectionRecords) {
      if (!isSafeBasename(record.currentName) || !isSafeBasename(record.targetName)) {
        throw new CleanupError(`${slug}: unsafe source or target basename for token ${record.tokenId}.`);
      }
      if (!/^\d+\.[a-z0-9]+$/u.test(record.targetName)) {
        throw new CleanupError(`${slug}: target ${record.targetName} is not a normalized numeric filename.`);
      }
      const target = path.resolve(record.targetPath);
      if (path.dirname(target) !== path.resolve(record.collection.directoryPath)) {
        throw new CleanupError(`${slug}: target path escapes its collection directory: ${record.targetName}.`);
      }
      const prior = targets.get(target);
      if (prior) {
        throw new CleanupError(`${slug}: ${prior.tokenId} and ${record.tokenId} both target ${record.targetName}.`);
      }
      targets.set(target, record);
      const folded = target.toLowerCase();
      const foldedPrior = foldedTargets.get(folded);
      if (foldedPrior) {
        throw new CleanupError(`${slug}: case-folded target collision between ${foldedPrior.targetName} and ${record.targetName}.`);
      }
      foldedTargets.set(folded, record);
      if (target !== path.resolve(record.currentPath) && fs.existsSync(target) && !currentPaths.has(target)) {
        throw new CleanupError(`${slug}: refusing to overwrite unplanned target ${record.targetName}.`);
      }
    }
  }
  return true;
}

function collectWarningFiles(records) {
  const arweaveJsonManifests = [];
  const oneByteFiles = [];
  for (const record of records) {
    const relativePath = `${record.collection.slug}/${record.targetName}`;
    if (record.inspection.kind === "json") {
      if (record.inspection.jsonValue?.manifest !== "arweave/paths") {
        throw new CleanupError(`${record.collection.slug}/${record.currentName} is JSON but is not an Arweave path manifest.`);
      }
      arweaveJsonManifests.push(relativePath);
    } else if (record.inspection.kind === "one-byte") {
      oneByteFiles.push(relativePath);
    }
  }
  arweaveJsonManifests.sort(naturalCompare);
  oneByteFiles.sort(naturalCompare);
  return {
    arweaveJsonManifests,
    oneByteFiles,
    presentButNonPlayable: [...arweaveJsonManifests, ...oneByteFiles].sort(naturalCompare),
  };
}

async function buildJsonUpdates({
  collections,
  primaryBundles,
  widgetBundles,
  inventory,
  naming,
  warningFiles,
  timestamp,
  originalsRoot,
  reportPath,
  existingReport,
  strictCorpus,
}) {
  const recordsByCollection = groupBy(inventory.records, (record) => record.collection.slug);
  const missingByCollection = groupBy(inventory.missing, (entry) => entry.collection.slug);
  const manifestUpdates = [];
  const primaryUpdates = [];
  const widgetUpdates = [];
  const primaryTmpFiles = new Map();

  for (const collection of collections) {
    const collectionRecords = recordsByCollection.get(collection.slug) ?? [];
    const collectionMissing = missingByCollection.get(collection.slug) ?? [];
    const recordByTokenId = new Map(collectionRecords.map((record) => [record.tokenId, record]));
    const missingByTokenId = new Map(collectionMissing.map((entry) => [entry.tokenId, entry]));
    const manifest = structuredClone(collection.manifest);

    for (const token of manifest.tokens) {
      const tokenId = String(token.tokenId);
      const record = recordByTokenId.get(tokenId);
      if (record) {
        token.fileName = record.targetName;
        token.extension = record.inspection.canonicalExtension;
        if (record.auditedContentReplacement) {
          const probe = await probeImage(record.currentPath, record.inspection.kind);
          token.contentType = record.inspection.kind === "jpg" ? "image/jpeg" : `image/${record.inspection.kind}`;
          token.contentLength = record.inspection.size;
          token.bytesWritten = record.inspection.size;
          token.sha256 = record.inspection.sha256;
          token.mediaProbe = probe;
        }
      } else if (missingByTokenId.has(tokenId)) {
        token.status = "missing";
        token.missingReason = "File absent during filename cleanup preflight";
        token.checkedAt = timestamp;
      } else {
        throw new CleanupError(`${collection.slug}: manifest token ${tokenId} has neither a physical file nor a missing record.`);
      }
    }

    manifest.generatedAt = timestamp;
    manifest.updatedAt = timestamp;
    manifest.partial = false;
    manifest.totals = {
      ...manifest.totals,
      tokensRecorded: manifest.tokens.length,
      successfulFiles: collectionRecords.length,
      failedFiles: manifest.tokens.filter((token) => token.status !== "success").length,
      missingFiles: collectionMissing.length,
      reusedFiles: collectionRecords.length,
      bytesWritten: collectionRecords.reduce((sum, record) => sum + record.inspection.size, 0),
    };
    manifest.filenameCleanup = {
      version: CLEANUP_VERSION,
      normalizedAt: timestamp,
      report: "../filename-cleanup-report.json",
    };
    manifestUpdates.push({ path: collection.manifestPath, payload: manifest, kind: "manifest", collection });

    const primary = primaryBundles.get(collection.collectionId);
    const tmpFiles = Object.fromEntries(primary.itemIds
      .filter((tokenId) => recordByTokenId.has(tokenId))
      .map((tokenId) => [tokenId, recordByTokenId.get(tokenId).targetName]));
    if (Object.keys(tmpFiles).length !== collectionRecords.length) {
      throw new CleanupError(`${collection.slug}: primary tmp_files map cardinality mismatch.`);
    }
    const primaryPayload = withOnlyTmpFilesChanged(primary.payload, tmpFiles);
    primaryTmpFiles.set(collection.collectionId, tmpFiles);
    primaryUpdates.push({ path: primary.filePath, payload: primaryPayload, kind: "primary", collection });
  }

  let widgetCollectionsWithMaps = 0;
  for (const widget of widgetBundles.values()) {
    const primaryMap = primaryTmpFiles.get(widget.collectionId);
    if (!primaryMap) {
      if (Object.hasOwn(widget.payload, "tmp_files")) {
        throw new CleanupError(`Unaffected widget bundle ${widget.fileName} unexpectedly already has tmp_files.`);
      }
      continue;
    }
    const tmpFiles = Object.fromEntries(widget.itemIds
      .filter((tokenId) => Object.hasOwn(primaryMap, tokenId))
      .map((tokenId) => [tokenId, primaryMap[tokenId]]));
    if (Object.keys(tmpFiles).length === 0) {
      continue;
    }
    widgetCollectionsWithMaps += 1;
    widgetUpdates.push({
      path: widget.filePath,
      payload: withOnlyTmpFilesChanged(widget.payload, tmpFiles),
      kind: "widget",
      collection: collections.find((entry) => entry.collectionId === widget.collectionId),
    });
  }
  if (strictCorpus && widgetCollectionsWithMaps !== EXPECTED_WIDGET_COLLECTIONS) {
    throw new CleanupError(`Prepared ${widgetCollectionsWithMaps} widget tmp_files subsets; expected ${EXPECTED_WIDGET_COLLECTIONS}.`);
  }

  const renames = inventory.records
    .filter((record) => record.currentName !== record.targetName)
    .map((record) => ({
      collection: record.collection.slug,
      tokenId: record.tokenId,
      from: record.currentName,
      to: record.targetName,
    }));
  const missingFiles = inventory.missing.map((entry) => `${entry.collection.slug}/${entry.expectedName}`).sort(naturalCompare);
  const knownDrifts = inventory.records.filter((record) => record.auditedContentReplacement).map((record) => ({
    collection: record.collection.slug,
    tokenId: record.tokenId,
    manifestFileName: record.token.fileName,
    physicalFileName: record.currentName,
    oldSha256: record.token.sha256,
    actualSha256: record.inspection.sha256,
    oldBytes: record.token.bytesWritten,
    actualBytes: record.inspection.size,
  }));
  let report = {
    schemaVersion: CLEANUP_VERSION,
    generatedAt: timestamp,
    sourceOfTruth: "109 per-folder manifests and their physical collection directories; the root manifest is intentionally ignored as stale",
    summary: {
      collectionDirectories: collections.length,
      physicalFiles: inventory.records.length,
      renamedFiles: renames.length,
      unchangedFiles: inventory.records.length - renames.length,
      primaryTmpFiles: inventory.records.length,
      widgetCollectionsWithTmpFiles: widgetCollectionsWithMaps,
      missingFiles: missingFiles.length,
      presentButNonPlayableFiles: warningFiles.presentButNonPlayable.length,
      arweaveJsonManifests: warningFiles.arweaveJsonManifests.length,
      oneByteFiles: warningFiles.oneByteFiles.length,
      solanaSyntheticRepairs: naming.repairs.length,
      auditedContentReplacements: knownDrifts.length,
    },
    renames,
    missingFiles,
    warnings: {
      arweaveJsonManifests: warningFiles.arweaveJsonManifests,
      oneByteFiles: warningFiles.oneByteFiles,
      presentButNonPlayable: warningFiles.presentButNonPlayable,
    },
    auditedContentReplacements: knownDrifts,
    knownManifestDrifts: knownDrifts,
    collectionNamingSources: naming.collectionNamingSources,
    solanaOrdinalSources: naming.solanaSources,
  };
  if (existingReport !== null) {
    validateExistingCleanupReport(existingReport);
    report = {
      ...report,
      generatedAt: existingReport.generatedAt,
      lastVerifiedAt: timestamp,
      renames: mergeAuditEntries(existingReport.renames, report.renames, (entry) => (
        `${entry.collection}\0${entry.tokenId}\0${entry.from}\0${entry.to}`
      )),
      knownManifestDrifts: mergeAuditEntries(
        existingReport.knownManifestDrifts,
        report.knownManifestDrifts,
        (entry) => `${entry.collection}\0${entry.tokenId}\0${entry.actualSha256}`,
      ),
    };
    report.summary = {
      ...report.summary,
      renamedFiles: report.renames.length,
    };
  }
  const reportUpdate = { path: reportPath, payload: report, kind: "report", collection: null };
  return { manifestUpdates, primaryUpdates, widgetUpdates, reportUpdate, report };
}

function withOnlyTmpFilesChanged(payload, tmpFiles) {
  if (!isPlainObject(tmpFiles) || Object.keys(tmpFiles).length === 0) {
    throw new CleanupError("Refusing to write an empty tmp_files map for a downloaded collection.");
  }
  const next = { ...payload, tmp_files: tmpFiles };
  const before = structuredClone(payload);
  const after = structuredClone(next);
  delete before.tmp_files;
  delete after.tmp_files;
  if (!deepEqualJson(before, after)) {
    throw new CleanupError("Token bundle data changed beyond tmp_files.");
  }
  return next;
}

function isAlreadyNormalized({ collections, inventory, primaryBundles, widgetBundles, warningFiles, existingReport }) {
  if (existingReport === null) return false;
  try {
    validateExistingCleanupReport(existingReport);
  } catch {
    return false;
  }
  if (inventory.records.some((record) => (
    record.currentName !== record.targetName
    || record.token.fileName !== record.targetName
    || record.token.extension !== record.inspection.canonicalExtension
    || record.auditedContentReplacement
  ))) {
    return false;
  }
  if (inventory.missing.some((entry) => entry.token.status !== "missing")) return false;
  if (!deepEqualJson(existingReport.missingFiles, inventory.missing.map((entry) => `${entry.collection.slug}/${entry.expectedName}`).sort(naturalCompare))) {
    return false;
  }
  if (!deepEqualJson(existingReport?.warnings?.arweaveJsonManifests, warningFiles.arweaveJsonManifests)
      || !deepEqualJson(existingReport?.warnings?.oneByteFiles, warningFiles.oneByteFiles)) {
    return false;
  }

  const expectedPrimaryMaps = new Map();
  const recordsByCollection = groupBy(inventory.records, (record) => record.collection.slug);
  for (const collection of collections) {
    if (collection.manifest?.filenameCleanup?.version !== CLEANUP_VERSION
        || collection.manifest?.filenameCleanup?.report !== "../filename-cleanup-report.json") {
      return false;
    }
    const byToken = new Map((recordsByCollection.get(collection.slug) ?? []).map((record) => [record.tokenId, record.targetName]));
    const primary = primaryBundles.get(collection.collectionId);
    const expected = Object.fromEntries(primary.itemIds.filter((id) => byToken.has(id)).map((id) => [id, byToken.get(id)]));
    if (!deepEqualJson(primary.payload.tmp_files, expected)) return false;
    expectedPrimaryMaps.set(collection.collectionId, expected);
  }
  for (const widget of widgetBundles.values()) {
    const primary = expectedPrimaryMaps.get(widget.collectionId);
    if (!primary) {
      if (Object.hasOwn(widget.payload, "tmp_files")) return false;
      continue;
    }
    const expected = Object.fromEntries(widget.itemIds.filter((id) => Object.hasOwn(primary, id)).map((id) => [id, primary[id]]));
    if (Object.keys(expected).length === 0) {
      if (Object.hasOwn(widget.payload, "tmp_files")) return false;
    } else if (!deepEqualJson(widget.payload.tmp_files, expected)) {
      return false;
    }
  }
  return true;
}

function validateExistingCleanupReport(report) {
  if (!isPlainObject(report)
      || report.schemaVersion !== CLEANUP_VERSION
      || typeof report.generatedAt !== "string"
      || !Array.isArray(report.renames)
      || !Array.isArray(report.missingFiles)
      || !Array.isArray(report.knownManifestDrifts)
      || !isPlainObject(report.warnings)) {
    throw new CleanupError("Existing filename-cleanup-report.json is invalid; refusing to erase its audit history.");
  }
}

function mergeAuditEntries(existingEntries, newEntries, keyForEntry) {
  const merged = [];
  const seen = new Set();
  for (const entry of [...existingEntries, ...newEntries]) {
    const key = keyForEntry(entry);
    if (!seen.has(key)) {
      seen.add(key);
      merged.push(entry);
    }
  }
  return merged;
}

async function applyCleanupPlan(plan) {
  validateRenamePlan(plan.records);
  const transactionId = `${Date.now()}-${process.pid}-${crypto.randomBytes(6).toString("hex")}`;
  const transactionRoot = path.join(plan.repoRoot, `.filename-cleanup-transaction-${transactionId}`);
  const stagingRoot = path.join(transactionRoot, "staged");
  const backupRoot = path.join(transactionRoot, "backups");
  await fsp.mkdir(stagingRoot, { recursive: true });
  await fsp.mkdir(backupRoot, { recursive: true });

  const renameRecords = plan.renames.map((record, index) => ({
    ...record,
    tempPath: path.join(record.collection.directoryPath, `.filename-cleanup-${transactionId}-${index}.tmp`),
  }));
  const manifestAndReport = [...plan.manifestUpdates, plan.reportUpdate];
  const bundleUpdates = [...plan.primaryUpdates, ...plan.widgetUpdates];
  const allUpdates = [...manifestAndReport, ...bundleUpdates];
  const stagedUpdates = [];
  let interruptedSignal = null;
  let commitPointReached = false;
  const handleSignal = (signal) => {
    if (commitPointReached) {
      console.error(`Received ${signal} after the verified commit point; finishing transaction cleanup.`);
      return;
    }
    if (!interruptedSignal) {
      interruptedSignal = signal;
      console.error(`Received ${signal}; stopping at the next safe boundary and rolling back.`);
    }
  };
  const checkInterrupted = () => {
    if (interruptedSignal) throw new CleanupError(`Cleanup interrupted by ${interruptedSignal}.`);
  };
  const sigintHandler = () => handleSignal("SIGINT");
  const sigtermHandler = () => handleSignal("SIGTERM");
  process.on("SIGINT", sigintHandler);
  process.on("SIGTERM", sigtermHandler);

  try {
    for (let index = 0; index < allUpdates.length; index += 1) {
      checkInterrupted();
      const update = allUpdates[index];
      const stagedPath = path.join(stagingRoot, `${String(index).padStart(4, "0")}-${path.basename(update.path)}`);
      const serialized = update.kind === "primary" || update.kind === "widget"
        ? JSON.stringify(update.payload)
        : JSON.stringify(update.payload, null, 2);
      await fsp.writeFile(stagedPath, `${serialized}\n`, { encoding: "utf8", flag: "wx" });
      JSON.parse(await fsp.readFile(stagedPath, "utf8"));
      stagedUpdates.push({
        ...update,
        stagedPath,
        backupPath: path.join(backupRoot, `${String(index).padStart(4, "0")}-${path.basename(update.path)}`),
        targetExisted: await pathExists(update.path),
      });
    }

    const journal = {
      schemaVersion: CLEANUP_VERSION,
      transactionId,
      startedAt: new Date().toISOString(),
      phase: "prepared",
      renames: renameRecords.map((record) => ({
        collection: record.collection.slug,
        tokenId: record.tokenId,
        from: record.currentPath,
        temporary: record.tempPath,
        to: record.targetPath,
        dev: String(record.inspection.dev),
        ino: String(record.inspection.ino),
        size: record.inspection.size,
        sha256: record.inspection.sha256,
      })),
      jsonUpdates: stagedUpdates.map((update) => ({
        target: update.path,
        staged: update.stagedPath,
        backup: update.backupPath,
        targetExisted: update.targetExisted,
        kind: update.kind,
      })),
    };
    const journalPath = path.join(transactionRoot, "journal.json");
    await writeJsonAtomicNew(journalPath, journal);

    console.log(`Applying ${renameRecords.length.toLocaleString()} two-phase same-directory renames...`);
    await executeTwoPhaseRenames(renameRecords, { concurrency: 32, checkAbort: checkInterrupted });
    journal.phase = "files-renamed";
    await replaceJsonFile(journalPath, journal);
    await verifyRenamedHashes(plan.records, plan.hashConcurrency, checkInterrupted);

    const committed = [];
    try {
      console.log("Committing normalized folder manifests and cleanup report...");
      await commitJsonUpdates(
        stagedUpdates.filter((update) => manifestAndReport.some((candidate) => candidate.path === update.path)),
        committed,
        checkInterrupted,
      );
      await verifyCommittedManifests(plan);

      console.log("Folder manifests verified. Committing primary and widget tmp_files maps...");
      await commitJsonUpdates(
        stagedUpdates.filter((update) => bundleUpdates.some((candidate) => candidate.path === update.path)),
        committed,
        checkInterrupted,
      );
      await verifyCommittedBundles(plan);
      checkInterrupted();
      commitPointReached = true;
      journal.phase = "complete";
      await replaceJsonFile(journalPath, journal);
    } catch (error) {
      try {
        await rollbackJsonUpdates(committed);
      } catch (rollbackError) {
        const composite = new CleanupError(`Cleanup failed (${error.message}) and JSON rollback failed (${rollbackError.message}).`);
        composite.retainTransaction = true;
        throw composite;
      }
      throw error;
    }
  } catch (error) {
    let physicalRollbackError = null;
    try {
      await rollbackPhysicalRenames(renameRecords, { concurrency: 32 });
    } catch (rollbackError) {
      physicalRollbackError = rollbackError;
    }
    let retainTransaction = Boolean(error.retainTransaction || physicalRollbackError);
    let cleanupError = null;
    if (!retainTransaction) {
      try {
        await fsp.rm(transactionRoot, { recursive: true, force: true });
      } catch (removeError) {
        cleanupError = removeError;
        retainTransaction = true;
      }
    }
    process.off("SIGINT", sigintHandler);
    process.off("SIGTERM", sigtermHandler);
    if (retainTransaction) {
      throw new CleanupError(
        `Cleanup failed (${error.message})${physicalRollbackError ? ` and physical rollback failed (${physicalRollbackError.message})` : ""}`
        + `${cleanupError ? ` and transaction cleanup failed (${cleanupError.message})` : ""}. `
        + `Recovery data was retained at ${transactionRoot}; run the normalizer with --recover.`,
      );
    }
    throw error;
  }

  try {
    await fsp.rm(transactionRoot, { recursive: true, force: true });
  } finally {
    process.off("SIGINT", sigintHandler);
    process.off("SIGTERM", sigtermHandler);
  }
}

async function executeTwoPhaseRenames(renameRecords, { concurrency = 32, checkAbort = () => {} } = {}) {
  validateExecutableRenameRecords(renameRecords);
  try {
    await mapWithConcurrency(renameRecords, concurrency, async (record) => {
      checkAbort();
      await assertPathAbsent(record.tempPath);
      await fsp.rename(record.currentPath, record.tempPath);
      record.cleanupState = "temporary";
    });
    await mapWithConcurrency(renameRecords, concurrency, async (record) => {
      checkAbort();
      await assertPathAbsent(record.targetPath);
      await fsp.rename(record.tempPath, record.targetPath);
      record.cleanupState = "target";
    });
  } catch (error) {
    await rollbackPhysicalRenames(renameRecords, { concurrency });
    throw new CleanupError(`Two-phase rename failed and was rolled back: ${error.message}`);
  }
}

async function rollbackPhysicalRenames(renameRecords, { concurrency = 32 } = {}) {
  await mapWithConcurrency(renameRecords, concurrency, async (record) => {
    if (record.cleanupState === "source") return;
    if (record.cleanupState === "target") {
      await assertPathAbsent(record.tempPath);
      await fsp.rename(record.targetPath, record.tempPath);
      record.cleanupState = "temporary";
      return;
    }
    if (record.cleanupState === "temporary" || record.cleanupState === undefined) return;
    throw new CleanupError(`Unknown rollback state ${record.cleanupState} for ${record.currentPath}.`);
  });
  await mapWithConcurrency(renameRecords, concurrency, async (record) => {
    if (record.cleanupState === "source") return;
    if (record.cleanupState === undefined) {
      if (await pathExists(record.currentPath)) {
        record.cleanupState = "source";
        return;
      }
      if (await pathExists(record.tempPath)) {
        record.cleanupState = "temporary";
      } else {
        throw new CleanupError(`Cannot restore ${record.currentPath}; source and temporary file are absent.`);
      }
    }
    if (record.cleanupState === "temporary") {
      await assertPathAbsent(record.currentPath);
      await fsp.rename(record.tempPath, record.currentPath);
      record.cleanupState = "source";
    }
  });
}

function validateExecutableRenameRecords(records) {
  const sources = new Set();
  const temps = new Set();
  const targets = new Set();
  for (const record of records) {
    for (const [label, value] of [["source", record.currentPath], ["temporary", record.tempPath], ["target", record.targetPath]]) {
      if (typeof value !== "string" || !path.isAbsolute(value)) {
        throw new CleanupError(`Rename ${label} must be an absolute path.`);
      }
    }
    if (path.dirname(record.currentPath) !== path.dirname(record.tempPath) || path.dirname(record.currentPath) !== path.dirname(record.targetPath)) {
      throw new CleanupError(`Rename paths must remain in one directory: ${record.currentPath}.`);
    }
    if (sources.has(record.currentPath) || temps.has(record.tempPath) || targets.has(record.targetPath)) {
      throw new CleanupError("Rename journal contains a duplicate source, temporary path, or target.");
    }
    sources.add(record.currentPath);
    temps.add(record.tempPath);
    targets.add(record.targetPath);
  }
}

async function verifyRenamedHashes(records, concurrency, checkAbort) {
  console.log(`Re-hashing ${records.length.toLocaleString()} final paths before any manifest or tmp_files commit...`);
  let completed = 0;
  let bytes = 0;
  await mapWithConcurrency(records, concurrency, async (record) => {
    checkAbort();
    const inspection = await hashAndInspectFile(record.targetPath);
    completed += 1;
    bytes += inspection.size;
    if (inspection.sha256 !== record.inspection.sha256
        || inspection.size !== record.inspection.size
        || inspection.dev !== record.inspection.dev
        || inspection.ino !== record.inspection.ino
        || inspection.kind !== record.inspection.kind
        || inspection.canonicalExtension !== record.inspection.canonicalExtension) {
      throw new CleanupError(`${record.collection.slug}/${record.targetName} differs from its complete preflight hash/signature/inode.`);
    }
    if (completed % 5_000 === 0 || completed === records.length) {
      console.log(`Post-rename hash progress: ${completed.toLocaleString()}/${records.length.toLocaleString()} files, ${formatBytes(bytes)} read.`);
    }
  });
}

async function commitJsonUpdates(updates, committed, checkAbort = () => {}) {
  for (const update of updates) {
    checkAbort();
    const targetExisted = await pathExists(update.path);
    if (targetExisted !== update.targetExisted) {
      throw new CleanupError(`${update.path} existence changed after transaction preparation.`);
    }
    if (targetExisted) {
      await assertPathAbsent(update.backupPath);
      await fsp.rename(update.path, update.backupPath);
    }
    const state = { ...update, targetExisted, installed: false };
    committed.push(state);
    await fsp.rename(update.stagedPath, update.path);
    state.installed = true;
  }
}

async function rollbackJsonUpdates(committed) {
  for (const update of [...committed].reverse()) {
    if (update.installed && await pathExists(update.path)) {
      await fsp.unlink(update.path);
    }
    if (update.targetExisted && await pathExists(update.backupPath)) {
      await fsp.rename(update.backupPath, update.path);
    }
  }
}

async function verifyCommittedManifests(plan) {
  for (const update of plan.manifestUpdates) {
    const manifest = await readJson(update.path);
    const physicalNames = new Set((await fsp.readdir(update.collection.directoryPath, { withFileTypes: true }))
      .filter((entry) => entry.isFile() && entry.name !== MANIFEST_NAME && !entry.name.startsWith(".filename-cleanup-"))
      .map((entry) => entry.name));
    for (const token of manifest.tokens) {
      if (token.status === "missing") continue;
      if (!physicalNames.has(token.fileName)) {
        throw new CleanupError(`${update.collection.slug}/manifest.json references absent ${token.fileName} after commit.`);
      }
    }
  }
}

async function verifyCommittedBundles(plan) {
  for (const update of [...plan.primaryUpdates, ...plan.widgetUpdates]) {
    const payload = await readJson(update.path);
    if (!deepEqualJson(payload.tmp_files, update.payload.tmp_files)) {
      throw new CleanupError(`${update.path} tmp_files changed during commit.`);
    }
    const before = structuredClone(update.payload);
    const after = structuredClone(payload);
    delete before.tmp_files;
    delete after.tmp_files;
    if (!deepEqualJson(before, after)) {
      throw new CleanupError(`${update.path} changed beyond tmp_files during commit.`);
    }
  }
}

async function probeImage(filePath, expectedKind) {
  const { stdout } = await execFileAsync("identify", ["-ping", "-format", "%m\t%w\t%h\t%z\t%Q", filePath], {
    encoding: "utf8",
    maxBuffer: 1024 * 1024,
  });
  const [formatRaw, widthRaw, heightRaw, bitDepthRaw, qualityRaw] = stdout.trim().split("\t");
  const width = Number(widthRaw);
  const height = Number(heightRaw);
  const bitDepth = Number(bitDepthRaw);
  const quality = Number(qualityRaw);
  const format = formatRaw.toLowerCase() === "jpg" ? "jpeg" : formatRaw.toLowerCase();
  const expectedFormat = expectedKind === "jpg" ? "jpeg" : expectedKind;
  if (format !== expectedFormat || !Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) {
    throw new CleanupError(`Unexpected ImageMagick probe for audited ${expectedKind} replacement: ${stdout}`);
  }
  return {
    kind: "image",
    format,
    width,
    height,
    area: width * height,
    aspectRatio: Number((width / height).toFixed(6)),
    bitDepth,
    quality,
  };
}

async function fetchHeliusAssets(mints, apiKey, concurrency) {
  if (mints.length === 0) return new Map();
  const uniqueMints = [...new Set(mints)];
  const expectedMintSet = new Set(uniqueMints);
  if (uniqueMints.length !== mints.length) {
    throw new CleanupError("Solana bundle contains duplicate mint IDs.");
  }
  for (const mint of uniqueMints) {
    if (!BASE58_MINT.test(mint)) {
      throw new CleanupError(`Invalid Solana mint in bundle: ${mint}`);
    }
  }
  const endpoint = `https://mainnet.helius-rpc.com/?api-key=${encodeURIComponent(apiKey)}`;
  const batches = chunk(uniqueMints, 100);
  const assets = new Map();
  let completed = 0;
  const results = await mapWithConcurrency(batches, concurrency, async (ids, batchIndex) => {
    const result = await fetchHeliusBatch(endpoint, ids, batchIndex);
    completed += ids.length;
    if (completed % 5_000 < ids.length || completed === uniqueMints.length) {
      console.log(`Helius progress: ${completed.toLocaleString()}/${uniqueMints.length.toLocaleString()} exact mints.`);
    }
    return result;
  });
  for (const result of results) {
    for (const asset of result) {
      const id = stringValue(asset?.id);
      if (!id || !expectedMintSet.has(id)) {
        throw new CleanupError(`Helius returned an unexpected or invalid asset ID: ${JSON.stringify(id)}.`);
      }
      if (assets.has(id)) {
        throw new CleanupError(`Helius returned mint ${id} more than once.`);
      }
      assets.set(id, asset);
    }
  }
  const missing = uniqueMints.filter((mint) => !assets.has(mint));
  if (missing.length > 0 || assets.size !== uniqueMints.length) {
    throw new CleanupError(`Helius returned ${assets.size}/${uniqueMints.length} expected mints. Missing: ${missing.slice(0, 20).join(", ")}`);
  }
  return assets;
}

async function fetchHeliusBatch(endpoint, ids, batchIndex) {
  const maxAttempts = 6;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: `filename-cleanup-${batchIndex}`, method: "getAssetBatch", params: { ids } }),
        signal: AbortSignal.timeout(45_000),
      });
      if (!response.ok) {
        const body = (await response.text()).slice(0, 500);
        if (!RETRYABLE_HTTP_STATUS.has(response.status) || attempt === maxAttempts) {
          throw new CleanupError(`Helius HTTP ${response.status}: ${body}`);
        }
        const retryAfter = Number(response.headers.get("retry-after"));
        await delay(Number.isFinite(retryAfter) ? retryAfter * 1000 : retryDelay(attempt));
        continue;
      }
      const payload = await response.json();
      if (payload?.error) {
        const code = Number(payload.error.code);
        if ((code === -32005 || code === -32603) && attempt < maxAttempts) {
          await delay(retryDelay(attempt));
          continue;
        }
        throw new CleanupError(`Helius RPC error ${code}: ${String(payload.error.message ?? "unknown")}`);
      }
      if (!Array.isArray(payload?.result)) {
        throw new CleanupError("Helius getAssetBatch response has no result array.");
      }
      return payload.result.filter(Boolean);
    } catch (error) {
      if (error instanceof CleanupError) throw error;
      if (attempt === maxAttempts) {
        throw new CleanupError(`Helius batch failed after ${maxAttempts} attempts: ${error.message}`);
      }
      await delay(retryDelay(attempt));
    }
  }
  throw new CleanupError("Unreachable Helius retry state.");
}

async function resolveHeliusApiKey(explicitKey) {
  if (typeof explicitKey === "string" && explicitKey.trim()) return explicitKey.trim();
  if (typeof process.env.HELIUS_API_KEY === "string" && process.env.HELIUS_API_KEY.trim()) return process.env.HELIUS_API_KEY.trim();
  const secretPath = path.join(process.env.HOME ?? "", "Developer", "secrets", "tools", "HELIUS_API_KEY");
  try {
    const value = (await fsp.readFile(secretPath, "utf8")).trim();
    if (value) return value;
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  throw new CleanupError("A Helius API key is required (HELIUS_API_KEY or ~/Developer/secrets/tools/HELIUS_API_KEY). No downloads will be attempted.");
}

async function rejectStaleTransactions(repoRoot) {
  const stale = await staleTransactionDirectories(repoRoot);
  if (stale.length > 0) {
    throw new CleanupError(`Refusing to start while cleanup transaction journal(s) remain: ${stale.map((entry) => path.basename(entry)).join(", ")}. Run with --recover.`);
  }
}

async function acquireCleanupLock(repoRoot, { forRecovery = false } = {}) {
  const resolvedRoot = path.resolve(repoRoot);
  const lockPath = path.join(resolvedRoot, LOCK_DIRECTORY_NAME);
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      await fsp.mkdir(lockPath);
      const owner = {
        pid: process.pid,
        hostname: os.hostname(),
        startedAt: new Date().toISOString(),
        purpose: forRecovery ? "recover" : "apply",
      };
      try {
        await writeJsonAtomicNew(path.join(lockPath, "owner.json"), owner);
      } catch (ownerError) {
        await fsp.rm(lockPath, { recursive: true, force: true });
        throw ownerError;
      }
      let released = false;
      return {
        path: lockPath,
        async release() {
          if (released) return;
          released = true;
          await fsp.rm(lockPath, { recursive: true, force: true });
        },
      };
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      let owner = null;
      try {
        owner = await readJsonIfExists(path.join(lockPath, "owner.json"));
      } catch {
        owner = null;
      }
      if (!owner || !Number.isInteger(owner.pid) || typeof owner.hostname !== "string") {
        const lockStat = await fsp.stat(lockPath);
        const ageMs = Date.now() - lockStat.mtimeMs;
        if (ageMs < 30_000) {
          throw new CleanupError(`Cleanup lock ${lockPath} is still initializing and has no valid owner metadata.`);
        }
        const staleTransactions = await staleTransactionDirectories(resolvedRoot);
        if (staleTransactions.length > 0 && !forRecovery) {
          throw new CleanupError("An ownerless cleanup lock accompanies recovery data. Run with --recover.");
        }
        await fsp.rm(lockPath, { recursive: true, force: true });
        continue;
      }
      if (owner.hostname !== os.hostname() || isPidAlive(owner.pid)) {
        throw new CleanupError(`Another filename cleanup process holds ${lockPath} (PID ${owner.pid} on ${owner.hostname}).`);
      }
      const staleTransactions = await staleTransactionDirectories(resolvedRoot);
      if (staleTransactions.length > 0 && !forRecovery) {
        throw new CleanupError(`A crashed cleanup left recovery data. Run with --recover before applying again.`);
      }
      await fsp.rm(lockPath, { recursive: true, force: true });
    }
  }
  throw new CleanupError(`Could not acquire cleanup lock ${lockPath}.`);
}

function isPidAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
}

async function staleTransactionDirectories(repoRoot) {
  const entries = await fsp.readdir(repoRoot, { withFileTypes: true });
  return entries
    .filter((entry) => entry.isDirectory() && entry.name.startsWith(".filename-cleanup-transaction-"))
    .map((entry) => path.join(repoRoot, entry.name))
    .sort(naturalCompare);
}

async function recoverStaleTransaction(repoRoot = REPO_ROOT) {
  const resolvedRoot = path.resolve(repoRoot);
  const transactions = await staleTransactionDirectories(resolvedRoot);
  if (transactions.length === 0) {
    return "No interrupted filename-cleanup transaction exists.";
  }
  if (transactions.length !== 1) {
    throw new CleanupError(`Expected one interrupted transaction, found ${transactions.length}: ${transactions.join(", ")}`);
  }
  const transactionRoot = transactions[0];
  const journalPath = path.join(transactionRoot, "journal.json");
  const journal = await readJsonIfExists(journalPath);
  if (journal === null) {
    const backupRoot = path.join(transactionRoot, "backups");
    const backups = await fsp.readdir(backupRoot).catch((error) => error.code === "ENOENT" ? [] : Promise.reject(error));
    if (backups.length > 0) {
      throw new CleanupError(`Transaction ${transactionRoot} has backups but no journal; retaining it for manual inspection.`);
    }
    await fsp.rm(transactionRoot, { recursive: true, force: true });
    return `Removed abandoned pre-journal staging directory ${transactionRoot}; no media or JSON targets had been touched.`;
  }
  validateRecoveryJournal(journal, resolvedRoot, transactionRoot);
  if (journal.phase === "complete") {
    await fsp.rm(transactionRoot, { recursive: true, force: true });
    return `Finalized completed transaction ${journal.transactionId}; verified work had already committed.`;
  }

  await restoreJsonFromJournal(journal.jsonUpdates);
  await restorePhysicalFromJournal(journal.renames);
  await verifyRecoveredHashes(journal.renames);
  await fsp.rm(transactionRoot, { recursive: true, force: true });
  return `Rolled back interrupted transaction ${journal.transactionId} and verified ${journal.renames.length.toLocaleString()} original file hashes.`;
}

function validateRecoveryJournal(journal, repoRoot, transactionRoot) {
  if (!isPlainObject(journal)
      || journal.schemaVersion !== CLEANUP_VERSION
      || typeof journal.transactionId !== "string"
      || !["prepared", "files-renamed", "complete"].includes(journal.phase)
      || !Array.isArray(journal.renames)
      || !Array.isArray(journal.jsonUpdates)) {
    throw new CleanupError(`Invalid cleanup recovery journal at ${transactionRoot}.`);
  }
  const originalsRoot = path.join(repoRoot, "Originals Downloaded");
  for (const rename of journal.renames) {
    if (!isPlainObject(rename)
        || !absolutePathInside(rename.from, originalsRoot)
        || !absolutePathInside(rename.temporary, originalsRoot)
        || !absolutePathInside(rename.to, originalsRoot)
        || path.dirname(rename.from) !== path.dirname(rename.temporary)
        || path.dirname(rename.from) !== path.dirname(rename.to)
        || typeof rename.dev !== "string"
        || typeof rename.ino !== "string"
        || !Number.isSafeInteger(rename.size)
        || !/^[a-f0-9]{64}$/u.test(rename.sha256)) {
      throw new CleanupError(`Unsafe or incomplete physical rename entry in ${transactionRoot}.`);
    }
  }
  for (const update of journal.jsonUpdates) {
    if (!isPlainObject(update)
        || !absolutePathInside(update.target, repoRoot)
        || !absolutePathInside(update.staged, transactionRoot)
        || !absolutePathInside(update.backup, transactionRoot)
        || typeof update.targetExisted !== "boolean") {
      throw new CleanupError(`Unsafe or incomplete JSON update entry in ${transactionRoot}.`);
    }
  }
}

async function restoreJsonFromJournal(updates) {
  for (const update of [...updates].reverse()) {
    const backupExists = await pathExists(update.backup);
    const targetExists = await pathExists(update.target);
    if (backupExists) {
      if (targetExists) await fsp.unlink(update.target);
      await fsp.rename(update.backup, update.target);
    } else if (update.targetExisted) {
      if (!targetExists) {
        throw new CleanupError(`Cannot recover missing original JSON target ${update.target}; its backup is also absent.`);
      }
    } else if (targetExists) {
      await fsp.unlink(update.target);
    }
  }
}

async function restorePhysicalFromJournal(renames) {
  const candidatePaths = new Set();
  for (const rename of renames) {
    candidatePaths.add(rename.from);
    candidatePaths.add(rename.temporary);
    candidatePaths.add(rename.to);
  }
  const locationsByInode = new Map();
  for (const candidatePath of candidatePaths) {
    try {
      const stat = await fsp.stat(candidatePath);
      if (!stat.isFile()) throw new CleanupError(`Recovery candidate is not a regular file: ${candidatePath}`);
      const key = `${stat.dev}:${stat.ino}`;
      const locations = locationsByInode.get(key) ?? [];
      locations.push(candidatePath);
      locationsByInode.set(key, locations);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }

  const states = [];
  for (const rename of renames) {
    const key = `${rename.dev}:${rename.ino}`;
    const locations = locationsByInode.get(key) ?? [];
    if (locations.length !== 1) {
      throw new CleanupError(`Expected exactly one inode location for ${rename.collection}/${rename.tokenId}; found ${locations.length}.`);
    }
    states.push({ ...rename, location: locations[0] });
  }
  await mapWithConcurrency(states, 32, async (state) => {
    if (state.location === state.from || state.location === state.temporary) return;
    await assertPathAbsent(state.temporary);
    await fsp.rename(state.location, state.temporary);
    state.location = state.temporary;
  });
  await mapWithConcurrency(states, 32, async (state) => {
    if (state.location === state.from) return;
    await assertPathAbsent(state.from);
    await fsp.rename(state.temporary, state.from);
    state.location = state.from;
  });
}

async function verifyRecoveredHashes(renames) {
  await mapWithConcurrency(renames, 8, async (rename) => {
    const inspection = await hashAndInspectFile(rename.from);
    if (inspection.sha256 !== rename.sha256 || inspection.size !== rename.size
        || String(inspection.dev) !== rename.dev || String(inspection.ino) !== rename.ino) {
      throw new CleanupError(`Recovered file failed journal verification: ${rename.from}`);
    }
  });
}

function absolutePathInside(candidate, root) {
  if (typeof candidate !== "string" || !path.isAbsolute(candidate)) return false;
  const resolvedCandidate = path.resolve(candidate);
  const resolvedRoot = path.resolve(root);
  return resolvedCandidate.startsWith(`${resolvedRoot}${path.sep}`);
}

function tokenIdsFromPayload(payload, label) {
  if (!Array.isArray(payload?.items)) {
    throw new CleanupError(`${label} has no items array.`);
  }
  const ids = [];
  const seen = new Set();
  for (let index = 0; index < payload.items.length; index += 1) {
    const row = payload.items[index];
    let id;
    if (Array.isArray(row)) {
      id = row[0];
    } else if (isPlainObject(row)) {
      id = row.id;
    }
    const tokenId = stringValue(id);
    if (!tokenId) throw new CleanupError(`${label} item[${index}] has no token ID.`);
    if (seen.has(tokenId)) throw new CleanupError(`${label} repeats token ID ${tokenId}.`);
    seen.add(tokenId);
    ids.push(tokenId);
  }
  return ids;
}

function assertContiguousZeroBased(values, label) {
  const sorted = [...values].map((value) => decimalBigInt(value, label)).sort((left, right) => left < right ? -1 : left > right ? 1 : 0);
  for (let index = 0; index < sorted.length; index += 1) {
    if (sorted[index] !== BigInt(index)) {
      throw new CleanupError(`${label} are not contiguous zero-based at index ${index}: found ${sorted[index]}.`);
    }
  }
}

function decimalBigInt(value, label) {
  const string = String(value);
  if (!DECIMAL.test(string)) throw new CleanupError(`${label} is not a non-negative decimal: ${string}`);
  return BigInt(string);
}

function normalizeDecimal(value) {
  return String(BigInt(value));
}

function compareDecimalStrings(left, right) {
  const leftValue = decimalBigInt(left, "synthetic source ID");
  const rightValue = decimalBigInt(right, "synthetic source ID");
  return leftValue < rightValue ? -1 : leftValue > rightValue ? 1 : String(left).localeCompare(String(right));
}

function printPlanSummary(plan, mode) {
  console.log(`[${mode}] Preflight passed:`);
  console.log(`  collections: ${plan.collections.length.toLocaleString()}`);
  console.log(`  physical files/tmp_files mappings: ${plan.records.length.toLocaleString()}`);
  console.log(`  physical renames: ${plan.renames.length.toLocaleString()}`);
  console.log(`  missing rows (unmapped): ${plan.missing.length.toLocaleString()}`);
  console.log(`  Arweave JSON warnings: ${plan.warningFiles.arweaveJsonManifests.length.toLocaleString()}`);
  console.log(`  one-byte warnings: ${plan.warningFiles.oneByteFiles.length.toLocaleString()}`);
  console.log(`  Solana synthetic repairs: ${plan.naming.repairs.length.toLocaleString()}`);
  console.log(`  primary bundle updates: ${plan.primaryUpdates.length.toLocaleString()}`);
  console.log(`  widget bundle updates: ${plan.widgetUpdates.length.toLocaleString()}`);
}

function startsWith(buffer, bytes) {
  return bytes.every((byte, index) => buffer[index] === byte);
}

function ascii(buffer, start, end) {
  return buffer.subarray(start, end).toString("ascii");
}

function isSafeBasename(value) {
  return typeof value === "string"
    && value.length > 0
    && value !== "."
    && value !== ".."
    && value.trim() === value
    && SAFE_BASENAME.test(value)
    && path.basename(value) === value;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function stringValue(value) {
  if (typeof value === "string" && value.length > 0) return value;
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return null;
}

function groupBy(values, key) {
  const groups = new Map();
  for (const value of values) {
    const groupKey = key(value);
    const group = groups.get(groupKey) ?? [];
    group.push(value);
    groups.set(groupKey, group);
  }
  return groups;
}

async function mapWithConcurrency(values, concurrency, transform) {
  const results = new Array(values.length);
  let nextIndex = 0;
  let firstError = null;
  const workerCount = Math.max(1, Math.min(concurrency, values.length || 1));
  await Promise.all(Array.from({ length: workerCount }, async () => {
    while (nextIndex < values.length && !firstError) {
      const index = nextIndex;
      nextIndex += 1;
      try {
        results[index] = await transform(values[index], index);
      } catch (error) {
        firstError = error;
      }
    }
  }));
  if (firstError) throw firstError;
  return results;
}

function chunk(values, size) {
  const chunks = [];
  for (let index = 0; index < values.length; index += size) chunks.push(values.slice(index, index + size));
  return chunks;
}

function retryDelay(attempt) {
  return Math.min(10_000, 250 * (2 ** (attempt - 1))) + Math.floor(Math.random() * 250);
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function readJson(filePath) {
  try {
    return JSON.parse(await fsp.readFile(filePath, "utf8"));
  } catch (error) {
    throw new CleanupError(`Cannot parse ${filePath}: ${error.message}`);
  }
}

async function readJsonIfExists(filePath) {
  try {
    return JSON.parse(await fsp.readFile(filePath, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw new CleanupError(`Cannot parse ${filePath}: ${error.message}`);
  }
}

async function writeJsonFile(filePath, value, flag = "w") {
  await fsp.writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, { encoding: "utf8", flag });
}

async function writeJsonAtomicNew(filePath, value) {
  const temporary = `${filePath}.new-${process.pid}-${crypto.randomBytes(4).toString("hex")}`;
  let handle;
  try {
    handle = await fsp.open(temporary, "wx");
    await handle.writeFile(`${JSON.stringify(value, null, 2)}\n`, "utf8");
    await handle.sync();
    await handle.close();
    handle = null;
    await assertPathAbsent(filePath);
    await fsp.rename(temporary, filePath);
  } catch (error) {
    await handle?.close().catch(() => {});
    await fsp.rm(temporary, { force: true }).catch(() => {});
    throw error;
  }
}

async function replaceJsonFile(filePath, value) {
  const temporary = `${filePath}.tmp-${process.pid}-${crypto.randomBytes(4).toString("hex")}`;
  await writeJsonFile(temporary, value, "wx");
  await fsp.rename(temporary, filePath);
}

async function pathExists(filePath) {
  try {
    await fsp.lstat(filePath);
    return true;
  } catch (error) {
    if (error.code === "ENOENT") return false;
    throw error;
  }
}

async function assertPathAbsent(filePath) {
  if (await pathExists(filePath)) throw new CleanupError(`Refusing to overwrite existing path ${filePath}.`);
}

function assertArrayEqual(actual, expected, label) {
  if (actual.length !== expected.length || actual.some((value, index) => value !== expected[index])) {
    let firstDifference = -1;
    for (let index = 0; index < Math.max(actual.length, expected.length); index += 1) {
      if (actual[index] !== expected[index]) { firstDifference = index; break; }
    }
    throw new CleanupError(`${label} differ (lengths ${actual.length}/${expected.length}, first difference ${firstDifference}: ${JSON.stringify(actual[firstDifference])}/${JSON.stringify(expected[firstDifference])}).`);
  }
}

function deepEqualJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function naturalCompare(left, right) {
  return String(left).localeCompare(String(right), "en", { numeric: true, sensitivity: "base" });
}

function formatCollisionGroups(groups) {
  return groups.slice(0, 5).map(([fileName, mints]) => `${fileName}=[${mints.join(",")}]`).join("; ");
}

function formatOrdinalCollisionGroups(groups) {
  return groups.slice(0, 5)
    .map((group) => `${group.ordinal}=[${group.records.map((record) => record.tokenId).join(",")}]`)
    .join("; ");
}

function formatBytes(bytes) {
  const units = ["B", "KiB", "MiB", "GiB", "TiB"];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit += 1; }
  return `${value.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`;
}

function relative(root, filePath) {
  return path.relative(root, filePath) || ".";
}

function positiveInteger(value, flag) {
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0) throw new CleanupError(`${flag} requires a positive integer.`);
  return number;
}

function requireValue(argv, index, flag) {
  if (index >= argv.length) throw new CleanupError(`${flag} requires a value.`);
  return argv[index];
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack ?? error.message);
    process.exitCode = 1;
  });
}

module.exports = {
  APPROVED_SOLANA_REPAIRS,
  CleanupError,
  buildCleanupPlan,
  detectFileKind,
  executeTwoPhaseRenames,
  numericUriBasename,
  recoverStaleTransaction,
  rollbackPhysicalRenames,
  resolveSolanaCollectionIds,
  validateRenamePlan,
};

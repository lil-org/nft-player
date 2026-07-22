#!/usr/bin/env node

/**
 * Fetch creator/artist metadata for all bundled Suggested Items collections
 * and write artists.md grouped by artist.
 *
 * Sources:
 * - Art Blocks token API (artist name + website) for abId collections
 * - OpenSea collection API (twitter/instagram/website) for EVM collections
 * - Objkt GraphQL (creator alias + socials) for Tezos
 * - Helius DAS + Magic Eden (creator / twitter) for Solana
 */

const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");

const ROOT = path.resolve(__dirname, "..");
const ITEMS_PATH = path.join(ROOT, "Suggested Items", "Suggested.bundle", "items.json");
const OUT_MD = path.join(__dirname, "artists.md");
const OUT_JSON = path.join(__dirname, "collection-artists.json");

const OPENSEA_API_BASE_URL = "https://api.opensea.io/api/v2";
const ARTBLOCKS_TOKEN_URL = "https://token.artblocks.io";
const OBJKT_GRAPHQL = "https://data.objkt.com/v3/graphql";
const MAGIC_EDEN_API = "https://api-mainnet.magiceden.dev/v2";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function readSecret(name) {
  const env = process.env[name];
  if (env) return env.trim();
  const filePath = path.join(os.homedir(), "Developer", "secrets", "tools", name);
  try {
    return (await fs.readFile(filePath, "utf8")).trim();
  } catch {
    return null;
  }
}

async function fetchJson(url, { headers = {}, timeoutMs = 30000, retries = 6 } = {}) {
  for (let attempt = 0; ; attempt += 1) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(url, {
        headers: {
          accept: "application/json",
          "User-Agent": "nft-player-artist-credits/1.0",
          ...headers,
        },
        redirect: "follow",
        signal: controller.signal,
      });
      const text = await response.text();
      clearTimeout(timer);

      if (response.status === 429 || response.status >= 500) {
        if (attempt >= retries) {
          throw new Error(`HTTP ${response.status} for ${url}: ${text.slice(0, 200)}`);
        }
        const retryAfter = Number(response.headers.get("retry-after"));
        await sleep(Number.isFinite(retryAfter) ? retryAfter * 1000 : 1000 * 2 ** attempt);
        continue;
      }

      if (!response.ok) {
        const err = new Error(`HTTP ${response.status} for ${url}: ${text.slice(0, 200)}`);
        err.status = response.status;
        throw err;
      }

      if (!text) return null;
      return JSON.parse(text);
    } catch (error) {
      clearTimeout(timer);
      if (attempt >= retries) throw error;
      if (error.name === "AbortError" || error.status >= 500 || error.status === 429) {
        await sleep(1000 * 2 ** attempt);
        continue;
      }
      throw error;
    }
  }
}

function suggestedItemId(item) {
  return `${item.address}${item.abId ?? item.collectionId ?? ""}`;
}

function slugifyOpenSea(collectionName) {
  return String(collectionName || "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function normalizeArtistKey(name) {
  return String(name || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");
}

function pickSocials(...sources) {
  const out = {
    twitter: null,
    instagram: null,
    website: null,
    discord: null,
  };
  for (const source of sources) {
    if (!source) continue;
    for (const key of Object.keys(out)) {
      if (!out[key] && source[key]) out[key] = cleanSocial(key, source[key]);
    }
  }
  return out;
}

function cleanSocial(kind, value) {
  if (value == null) return null;
  let v = String(value).trim();
  if (!v) return null;
  if (kind === "twitter") {
    v = v.replace(/^@/, "");
    v = v.replace(/^https?:\/\/(www\.)?(twitter|x)\.com\//i, "");
    v = v.replace(/\/$/, "");
    if (!v) return null;
    return `https://x.com/${v}`;
  }
  if (kind === "instagram") {
    v = v.replace(/^@/, "");
    v = v.replace(/^https?:\/\/(www\.)?instagram\.com\//i, "");
    v = v.replace(/\/$/, "");
    if (!v) return null;
    return `https://instagram.com/${v}`;
  }
  if (kind === "discord") {
    if (v.startsWith("http")) return v;
    return v;
  }
  if (kind === "website") {
    if (!/^https?:\/\//i.test(v)) v = `https://${v}`;
    return v;
  }
  return v;
}

function openSeaChain(chain) {
  if (chain === "ethereum" || chain === "base" || chain === "zora" || chain === "optimism") return chain;
  return null;
}

async function fetchArtBlocks(item) {
  if (item.abId == null) return null;
  const tokenId = `${item.abId}000000`;
  const url = `${ARTBLOCKS_TOKEN_URL}/${item.address}/${tokenId}`;
  try {
    const data = await fetchJson(url);
    if (!data || !data.artist) return null;
    // Guard against wrong project on shared flex contracts
    if (
      data.collection_name &&
      item.name &&
      !String(data.collection_name).toLowerCase().includes(String(item.name).toLowerCase().slice(0, 12)) &&
      !String(data.name || "").toLowerCase().startsWith(String(item.name).toLowerCase())
    ) {
      // Still accept if project_id matches
      if (String(data.project_id) !== String(item.abId)) {
        return {
          artist: data.artist,
          website: data.website || null,
          collectionName: data.collection_name || null,
          mismatch: true,
          rawName: data.name,
        };
      }
    }
    return {
      artist: data.artist,
      website: data.website || null,
      collectionName: data.collection_name || null,
      mismatch: false,
    };
  } catch (error) {
    return { error: error.message };
  }
}

async function fetchOpenSeaCollection(item, openSeaKey, preferredSlug) {
  const chain = openSeaChain(item.chain);
  if (!chain || !openSeaKey) return null;

  let slug = preferredSlug;
  if (!slug) {
    try {
      const contract = await fetchJson(
        `${OPENSEA_API_BASE_URL}/chain/${chain}/contract/${item.address}`,
        { headers: { "x-api-key": openSeaKey } },
      );
      slug = contract?.collection || null;
    } catch (error) {
      return { error: `contract: ${error.message}` };
    }
  }

  if (!slug) return { error: "no collection slug" };

  try {
    const collection = await fetchJson(`${OPENSEA_API_BASE_URL}/collections/${slug}`, {
      headers: { "x-api-key": openSeaKey },
    });
    return {
      slug,
      name: collection?.name || null,
      twitter: collection?.twitter_username || null,
      instagram: collection?.instagram_username || null,
      website: collection?.project_url || null,
      discord: collection?.discord_url || null,
      description: collection?.description || null,
      owner: collection?.owner || null,
    };
  } catch (error) {
    if (preferredSlug) {
      // fall back to contract slug
      return fetchOpenSeaCollection(item, openSeaKey, null);
    }
    return { error: error.message, slug };
  }
}

async function fetchObjkt(item) {
  const query = {
    query: `{
      token(where: {fa_contract: {_eq: "${item.address}"}}, limit: 5) {
        name
        creators {
          creator_address
          holder {
            alias
            twitter
            website
            github
            instagram
            discord
          }
        }
      }
      fa(where: {contract: {_eq: "${item.address}"}}) {
        name
        description
      }
    }`,
  };

  const response = await fetch(OBJKT_GRAPHQL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json",
      "User-Agent": "nft-player-artist-credits/1.0",
    },
    body: JSON.stringify(query),
  });
  const body = await response.json();
  if (body.errors) {
    return { error: JSON.stringify(body.errors) };
  }

  const creators = new Map();
  for (const token of body.data?.token || []) {
    for (const creator of token.creators || []) {
      const address = creator.creator_address;
      const holder = creator.holder || {};
      if (!creators.has(address)) {
        creators.set(address, {
          address,
          artist: holder.alias || address,
          twitter: holder.twitter || null,
          instagram: holder.instagram || null,
          website: holder.website || null,
          discord: holder.discord || null,
          github: holder.github || null,
        });
      }
    }
  }

  return {
    collectionName: body.data?.fa?.[0]?.name || item.name,
    creators: [...creators.values()],
  };
}

async function fetchHeliusCollection(item, heliusKey) {
  if (!heliusKey) return null;
  const url = `https://mainnet.helius-rpc.com/?api-key=${heliusKey}`;
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: "artist-credits",
      method: "getAsset",
      params: { id: item.address },
    }),
  });
  const body = await response.json();
  const result = body.result;
  if (!result) return { error: body.error?.message || "no asset" };

  const creators = result.creators || [];
  const primary = creators.find((c) => c.verified) || creators[0] || null;
  return {
    name: result.content?.metadata?.name || item.name,
    creatorAddress: primary?.address || null,
    authorities: (result.authorities || []).map((a) => a.address),
  };
}

async function fetchMagicEden(item) {
  // Try slug from internal_slug / name
  const candidates = [
    item.internal_slug,
    slugifyOpenSea(item.name),
    String(item.name || "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, ""),
  ].filter(Boolean);

  for (const symbol of [...new Set(candidates)]) {
    try {
      const data = await fetchJson(`${MAGIC_EDEN_API}/collections/${encodeURIComponent(symbol)}`, {
        retries: 3,
      });
      if (data && (data.name || data.symbol)) {
        return {
          symbol: data.symbol || symbol,
          name: data.name || null,
          twitter: data.twitter || data.twitterLink || null,
          discord: data.discord || data.discordLink || null,
          website: data.website || data.websiteLink || null,
          description: data.description || null,
        };
      }
    } catch (error) {
      if (error.status === 404) continue;
      // rate limit / other — try next later
      return { error: error.message, tried: symbol };
    }
  }
  return { error: "not found", tried: candidates };
}

function artistFromOpenSeaName(collectionName, itemName) {
  if (!collectionName) return null;
  const by = collectionName.match(/^(.*?)\s+by\s+(.+)$/i);
  if (by) return by[2].trim();
  return null;
}

async function enrichItem(item, keys, cache) {
  const id = suggestedItemId(item);
  if (cache[id]) return cache[id];

  const record = {
    id,
    name: item.name,
    chain: item.chain,
    address: item.address,
    abId: item.abId ?? null,
    internal_slug: item.internal_slug ?? null,
    artists: [],
    socials: { twitter: null, instagram: null, website: null, discord: null },
    sources: [],
    notes: [],
  };

  if (item.abId != null) {
    const ab = await fetchArtBlocks(item);
    await sleep(120);
    if (ab?.artist) {
      record.artists.push(ab.artist);
      record.socials = pickSocials(record.socials, { website: ab.website });
      record.sources.push("artblocks");
      if (ab.mismatch) record.notes.push(`artblocks name mismatch: ${ab.rawName || ab.collectionName}`);

      const preferredSlug = ab.collectionName ? slugifyOpenSea(ab.collectionName) : null;
      const os = await fetchOpenSeaCollection(item, keys.openSea, preferredSlug);
      await sleep(250);
      if (os && !os.error) {
        record.socials = pickSocials(record.socials, {
          twitter: os.twitter,
          instagram: os.instagram,
          website: os.website,
          discord: os.discord,
        });
        record.sources.push("opensea");
        const osArtist = artistFromOpenSeaName(os.name, item.name);
        if (osArtist && !record.artists.some((a) => normalizeArtistKey(a) === normalizeArtistKey(osArtist))) {
          // usually same as AB artist
        }
      } else if (os?.error) {
        record.notes.push(`opensea: ${os.error}`);
      }
    } else {
      record.notes.push(`artblocks: ${ab?.error || "no artist"}`);
    }
  } else if (["ethereum", "base", "zora", "optimism"].includes(item.chain)) {
    const os = await fetchOpenSeaCollection(item, keys.openSea, null);
    await sleep(250);
    if (os && !os.error) {
      const osArtist = artistFromOpenSeaName(os.name, item.name);
      if (osArtist) record.artists.push(osArtist);
      record.socials = pickSocials(record.socials, {
        twitter: os.twitter,
        instagram: os.instagram,
        website: os.website,
        discord: os.discord,
      });
      record.sources.push("opensea");
      if (!record.artists.length) {
        // Keep placeholder — filled by manual map later if needed
        record.notes.push("artist name not in OpenSea collection title");
      }
    } else {
      record.notes.push(`opensea: ${os?.error || "failed"}`);
    }
  } else if (item.chain === "tezos") {
    const objkt = await fetchObjkt(item);
    await sleep(200);
    if (objkt?.creators?.length) {
      for (const creator of objkt.creators) {
        record.artists.push(creator.artist);
        record.socials = pickSocials(record.socials, {
          twitter: creator.twitter,
          instagram: creator.instagram,
          website: creator.website,
          discord: creator.discord,
        });
      }
      record.sources.push("objkt");
    } else {
      record.notes.push(`objkt: ${objkt?.error || "no creators"}`);
    }
  } else if (item.chain === "solana") {
    const [helius, me] = await Promise.all([
      fetchHeliusCollection(item, keys.helius),
      fetchMagicEden(item),
    ]);
    await sleep(400);
    if (me && !me.error) {
      record.socials = pickSocials(record.socials, {
        twitter: me.twitter,
        website: me.website,
        discord: me.discord,
      });
      record.sources.push("magiceden");
    } else if (me?.error) {
      record.notes.push(`magiceden: ${me.error}`);
    }
    if (helius?.creatorAddress) {
      record.notes.push(`helius creator wallet: ${helius.creatorAddress}`);
      record.sources.push("helius");
    }
    if (!record.artists.length) {
      record.notes.push("artist name not resolved from Solana APIs");
    }
  }

  cache[id] = record;
  return record;
}

function renderMarkdown(records) {
  // Group by primary artist; collections with multiple creators listed under each
  const groups = new Map();
  const unresolved = [];

  for (const record of records) {
    if (!record.artists.length) {
      unresolved.push(record);
      continue;
    }
    for (const artist of record.artists) {
      const key = normalizeArtistKey(artist);
      if (!groups.has(key)) {
        groups.set(key, {
          artist,
          socials: { ...record.socials },
          collections: [],
        });
      }
      const group = groups.get(key);
      group.socials = pickSocials(group.socials, record.socials);
      group.collections.push(record);
    }
  }

  const sortedArtists = [...groups.values()].sort((a, b) =>
    a.artist.localeCompare(b.artist, undefined, { sensitivity: "base" }),
  );

  const lines = [];
  lines.push("# Artists");
  lines.push("");
  lines.push(
    "Creator credits for collections bundled in the app (`Suggested Items/Suggested.bundle`). Collections are grouped by artist.",
  );
  lines.push("");
  lines.push(
    `Generated from on-chain / marketplace metadata (Art Blocks, OpenSea, Objkt, Magic Eden, Helius). ${records.length} collections · ${sortedArtists.length} artists with identified creators · ${unresolved.length} still need a manual artist attribution.`,
  );
  lines.push("");

  for (const group of sortedArtists) {
    lines.push(`## ${group.artist}`);
    lines.push("");
    const socialBits = [];
    if (group.socials.twitter) socialBits.push(`[X/Twitter](${group.socials.twitter})`);
    if (group.socials.instagram) socialBits.push(`[Instagram](${group.socials.instagram})`);
    if (group.socials.website) socialBits.push(`[Website](${group.socials.website})`);
    if (group.socials.discord) socialBits.push(`[Discord](${group.socials.discord})`);
    if (socialBits.length) {
      lines.push(socialBits.join(" · "));
      lines.push("");
    }
    lines.push("Collections:");
    lines.push("");
    const cols = [...group.collections].sort((a, b) => a.name.localeCompare(b.name));
    for (const col of cols) {
      lines.push(`- **${col.name}** (${col.chain})`);
    }
    lines.push("");
  }

  if (unresolved.length) {
    lines.push("## Unresolved artist attribution");
    lines.push("");
    lines.push(
      "These collections have marketplace/project socials and/or creator wallets, but no clear individual artist name in the automated sources. Fill in manually.",
    );
    lines.push("");
    for (const record of unresolved.sort((a, b) => a.name.localeCompare(b.name))) {
      lines.push(`### ${record.name}`);
      lines.push("");
      lines.push(`- Chain: ${record.chain}`);
      lines.push(`- Address: \`${record.address}\``);
      const socialBits = [];
      if (record.socials.twitter) socialBits.push(`[X/Twitter](${record.socials.twitter})`);
      if (record.socials.instagram) socialBits.push(`[Instagram](${record.socials.instagram})`);
      if (record.socials.website) socialBits.push(`[Website](${record.socials.website})`);
      if (record.socials.discord) socialBits.push(`[Discord](${record.socials.discord})`);
      if (socialBits.length) lines.push(`- Socials: ${socialBits.join(" · ")}`);
      if (record.notes.length) lines.push(`- Notes: ${record.notes.join("; ")}`);
      lines.push("");
    }
  }

  return lines.join("\n");
}

async function main() {
  const items = JSON.parse(await fs.readFile(ITEMS_PATH, "utf8"));
  const keys = {
    openSea: await readSecret("OPENSEA_API_KEY"),
    helius: await readSecret("HELIUS_API_KEY"),
  };

  if (!keys.openSea) console.warn("WARN: no OPENSEA_API_KEY");
  if (!keys.helius) console.warn("WARN: no HELIUS_API_KEY");

  const cachePath = path.join(__dirname, "collection-artists.cache.json");
  let cache = {};
  try {
    cache = JSON.parse(await fs.readFile(cachePath, "utf8"));
  } catch {
    cache = {};
  }

  const records = [];
  let i = 0;
  for (const item of items) {
    i += 1;
    process.stdout.write(`[${i}/${items.length}] ${item.chain} ${item.name}\n`);
    try {
      const record = await enrichItem(item, keys, cache);
      records.push(record);
    } catch (error) {
      records.push({
        id: suggestedItemId(item),
        name: item.name,
        chain: item.chain,
        address: item.address,
        abId: item.abId ?? null,
        artists: [],
        socials: { twitter: null, instagram: null, website: null, discord: null },
        sources: [],
        notes: [error.message],
      });
    }
    if (i % 10 === 0) {
      await fs.mkdir(path.dirname(cachePath), { recursive: true });
      await fs.writeFile(cachePath, JSON.stringify(cache, null, 2));
    }
  }

  await fs.mkdir(path.dirname(cachePath), { recursive: true });
  await fs.writeFile(cachePath, JSON.stringify(cache, null, 2));
  await fs.writeFile(OUT_JSON, JSON.stringify(records, null, 2));

  const md = renderMarkdown(records);
  await fs.writeFile(OUT_MD, md);

  const withArtist = records.filter((r) => r.artists.length).length;
  const withSocial = records.filter(
    (r) => r.socials.twitter || r.socials.instagram || r.socials.website,
  ).length;
  console.log(`\nDone. ${withArtist}/${records.length} with artist, ${withSocial}/${records.length} with socials`);
  console.log(`Wrote ${OUT_MD}`);
  console.log(`Wrote ${OUT_JSON}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

export function cdnAssetURL(source) {
  let url;
  try { url = new URL(source); } catch { throw new Error("Assets must use HTTPS on cdn.lil.org."); }
  if (typeof source !== "string" || url.protocol !== "https:" || url.hostname !== "cdn.lil.org"
      || url.port || url.username || url.password || url.href.includes("#")) {
    throw new Error("Assets must use HTTPS on cdn.lil.org.");
  }
  return url;
}

export async function downloadCDNAsset(source, fetchAsset = fetch) {
  let url = cdnAssetURL(source);
  const signal = AbortSignal.timeout(60_000);
  for (let redirects = 0; ; redirects += 1) {
    const response = await fetchAsset(url.href, { redirect: "manual", signal });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      await response.body?.cancel();
      const location = response.headers.get("location");
      if (!location || redirects >= 5) throw new Error("Invalid CDN asset redirect.");
      url = cdnAssetURL(new URL(location, url).href);
      continue;
    }
    if (response.status !== 200) {
      await response.body?.cancel();
      return { statusCode: response.status, data: Buffer.alloc(0) };
    }
    return { statusCode: response.status, data: Buffer.from(await response.arrayBuffer()) };
  }
}

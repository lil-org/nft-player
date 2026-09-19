"use strict";

function commonURLDirectoryPrefix(urls) {
  let origin;
  let prefix;
  for (const value of urls) {
    let url;
    try {
      url = new URL(value);
    } catch {
      return "";
    }
    if (url.origin === "null" || (origin != null && url.origin !== origin)) return "";
    origin = url.origin;

    const path = value.split(/[?#]/u, 1)[0];
    const authority = path.match(/^[a-z][a-z0-9+.-]*:\/\/[^/]+\//iu)?.[0];
    if (authority == null) return "";
    const directory = path.slice(0, path.lastIndexOf("/") + 1);
    if (prefix == null) {
      prefix = directory;
    } else {
      let index = 0;
      while (index < prefix.length && index < directory.length && prefix[index] === directory[index]) {
        index += 1;
      }
      prefix = prefix.slice(0, index);
      prefix = prefix.slice(0, prefix.lastIndexOf("/") + 1);
    }
    if (prefix.length < authority.length) return "";
  }
  return prefix ?? "";
}

module.exports = { commonURLDirectoryPrefix };

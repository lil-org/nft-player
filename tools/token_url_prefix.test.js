"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { commonURLDirectoryPrefix } = require("./token_url_prefix");

test("URL prefixes share complete directories without changing URL bytes", () => {
  const cases = [
    { urls: [], prefix: "" },
    { urls: ["https://example.com/art/1.png"], prefix: "https://example.com/art/" },
    { urls: ["https://example.com/art/1.png", "https://example.com/art/2.png"], prefix: "https://example.com/art/" },
    { urls: ["https://example.com/art/one/1.png", "https://example.com/art/two/2.png"], prefix: "https://example.com/art/" },
    { urls: ["https://example.com/art/1.png", "https://example.com/artist/2.png"], prefix: "https://example.com/" },
    { urls: ["https://example.com/1.png", "https://other.example/2.png"], prefix: "" },
    { urls: ["https://example.com/1.png", "http://example.com/2.png"], prefix: "" },
    { urls: ["https://example.com/1.png", "https://example.com:8443/2.png"], prefix: "" },
    { urls: ["https://example.com"], prefix: "" },
    { urls: ["data:image/png;base64,abc"], prefix: "" },
    { urls: ["relative/1.png"], prefix: "" },
    { urls: ["https://EXAMPLE.com:443/a%2fb/1.png?redirect=/x/y#z/q", "https://EXAMPLE.com:443/a%2fb/2.png"], prefix: "https://EXAMPLE.com:443/a%2fb/" },
    { urls: ["https://example.com/art/1.png?redirect=/x/y#z/q"], prefix: "https://example.com/art/" },
    { urls: ["https://EXAMPLE.com/1.png", "https://example.com/2.png"], prefix: "" },
  ];
  for (const { urls, prefix } of cases) {
    assert.equal(commonURLDirectoryPrefix(urls), prefix, JSON.stringify(urls));
    for (const url of urls) {
      assert.equal(prefix + url.slice(prefix.length), url);
    }
  }
});

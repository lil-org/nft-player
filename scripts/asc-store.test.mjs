import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

async function fixture(t) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "nft-release-test-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const log = path.join(directory, "calls.log");
  await fs.writeFile(path.join(directory, "asc"), `#!/bin/bash
printf '%s\\n' "$*" >> "$ASC_TEST_LOG"
case "$*" in
  version) printf '%s\\n' "$ASC_TEST_VERSION" ;;
  'metadata validate --dir '*) ;;
  *) exit 99 ;;
esac
`, { mode: 0o755 });
  return {
    log,
    run(version, command = "validate") {
      return spawnSync("bash", ["scripts/asc-store.sh", command, "macos"], {
        cwd: repositoryRoot,
        encoding: "utf8",
        env: {
          ...process.env,
          PATH: `${directory}${path.delimiter}${process.env.PATH}`,
          ASC_TEST_LOG: log,
          ASC_TEST_VERSION: version,
        },
      });
    },
  };
}

test("release validation accepts the supported asc baseline and newer versions", async (t) => {
  const { run, log } = await fixture(t);
  for (const version of ["1.9.1 (commit: unknown, date: unknown)", "1.10.0", "2.0.0"]) {
    const result = run(version);
    assert.equal(result.status, 0, result.stderr);
  }
  const calls = (await fs.readFile(log, "utf8")).trim().split("\n");
  assert.deepEqual(calls, Array.from({ length: 3 }, () => [
    "version", "metadata validate --dir app_store/metadata/macos",
  ]).flat());
});

test("release commands reject old or unrecognized asc versions before other operations", async (t) => {
  const { run, log } = await fixture(t);
  const versions = ["1.9.0", "1.8.99", "0.99.99", "1.9.1-rc.1", "unknown"];
  for (const version of versions) {
    const result = run(version, "release");
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /asc 1\.9\.1 or later is required/);
  }
  assert.equal(await fs.readFile(log, "utf8"), "version\n".repeat(versions.length));
});

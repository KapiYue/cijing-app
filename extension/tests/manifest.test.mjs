import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const manifest = JSON.parse(await readFile(new URL("../manifest.json", import.meta.url), "utf8"));

test("requests only the extension's current runtime permissions", () => {
  assert.deepEqual(manifest.permissions, ["storage", "contextMenus", "activeTab", "offscreen"]);
  assert.deepEqual(manifest.host_permissions, [
    "https://daudpwwdhdyvfodpwvny.supabase.co/*",
    "https://api.dictionaryapi.dev/*",
    "https://ssl.gstatic.com/*"
  ]);
  assert.ok(!manifest.host_permissions.includes("http://*/*"));
  assert.ok(!manifest.host_permissions.includes("https://*.supabase.co/*"));
});

test("injects only into ordinary web pages and loads shared text helpers first", () => {
  const [contentScript] = manifest.content_scripts;
  assert.deepEqual(contentScript.matches, ["http://*/*", "https://*/*"]);
  assert.deepEqual(contentScript.js, ["shared/text-utils.js", "content/content.js"]);
});

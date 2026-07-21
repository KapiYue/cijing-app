import test from "node:test";
import assert from "node:assert/strict";

test("shares and sanitizes extension preferences", async () => {
  const storage = new Map();
  globalThis.chrome = {
    storage: {
      local: {
        async get(key) { return { [key]: storage.get(key) }; },
        async set(values) { Object.entries(values).forEach(([key, value]) => storage.set(key, value)); }
      }
    }
  };

  try {
    const preferences = await import("../shared/preferences.js");
    assert.deepEqual(await preferences.getPreferences(), preferences.DEFAULT_PREFERENCES);

    const updated = await preferences.updatePreferences({
      autoSave: true,
      saveContext: false,
      theme: "blue",
      disabledHosts: [" Example.COM ", "example.com", ""]
    });
    assert.deepEqual(updated, {
      autoSave: true,
      saveContext: false,
      privacyMode: false,
      disabledHosts: ["example.com"],
      theme: "blue"
    });
    assert.equal(preferences.isHostDisabled(updated, "EXAMPLE.COM"), true);

    const sanitized = await preferences.updatePreferences({ theme: "unknown", disabledHosts: "bad" });
    assert.equal(sanitized.theme, "purple");
    assert.deepEqual(sanitized.disabledHosts, []);
  } finally {
    delete globalThis.chrome;
  }
});

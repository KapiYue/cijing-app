export const PREFERENCES_KEY = "cijingPreferences";

export const DEFAULT_PREFERENCES = Object.freeze({
  autoSave: false,
  saveContext: true,
  privacyMode: false,
  disabledHosts: [],
  theme: "purple"
});

export const THEME_OPTIONS = Object.freeze([
  { id: "purple", label: "鲸紫", color: "#7651c9" },
  { id: "blue", label: "海蓝", color: "#3977d6" },
  { id: "green", label: "青绿", color: "#2d936c" },
  { id: "orange", label: "暖橙", color: "#d9823d" },
  { id: "rose", label: "玫红", color: "#b95579" }
]);

const BOOLEAN_KEYS = ["autoSave", "saveContext", "privacyMode"];
const THEME_IDS = new Set(THEME_OPTIONS.map(({ id }) => id));

export function sanitizePreferences(value = {}) {
  const next = { ...DEFAULT_PREFERENCES };
  for (const key of BOOLEAN_KEYS) {
    if (typeof value[key] === "boolean") next[key] = value[key];
  }
  if (THEME_IDS.has(value.theme)) next.theme = value.theme;
  if (Array.isArray(value.disabledHosts)) {
    next.disabledHosts = [...new Set(value.disabledHosts
      .map((host) => String(host || "").trim().toLowerCase())
      .filter(Boolean))].slice(0, 100);
  }
  return next;
}

export async function getPreferences() {
  const value = await chrome.storage.local.get(PREFERENCES_KEY);
  return sanitizePreferences(value[PREFERENCES_KEY]);
}

export async function updatePreferences(patch) {
  const current = await getPreferences();
  const next = sanitizePreferences({ ...current, ...patch });
  await chrome.storage.local.set({ [PREFERENCES_KEY]: next });
  return next;
}

export function isHostDisabled(preferences, host) {
  return Boolean(host) && preferences.disabledHosts.includes(String(host).toLowerCase());
}

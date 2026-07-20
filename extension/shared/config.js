import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from "./generated-client-config.js";

export const DEFAULT_CONFIG = Object.freeze({
  supabaseUrl: SUPABASE_URL,
  supabasePublishableKey: SUPABASE_PUBLISHABLE_KEY
});

export async function getConfig() {
  return DEFAULT_CONFIG;
}

import { createClient, SupabaseClient, User } from "https://esm.sh/@supabase/supabase-js@2";

export type AuthContext = {
  client: SupabaseClient;
  user: User;
  token: string;
};

function firstPublicKey(value: unknown): string | undefined {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) {
    const values = value.map(firstPublicKey).filter((item): item is string => Boolean(item));
    return values.find((item) => item.startsWith("sb_publishable_")) ?? values[0];
  }
  if (value && typeof value === "object") {
    const values = Object.values(value).map(firstPublicKey).filter((item): item is string => Boolean(item));
    return values.find((item) => item.startsWith("sb_publishable_")) ?? values[0];
  }
  return undefined;
}

function resolvePublishableKey(): string | undefined {
  const direct = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY");
  if (direct) return direct;
  const bundled = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (!bundled) return undefined;
  try {
    return firstPublicKey(JSON.parse(bundled));
  } catch {
    return undefined;
  }
}

export async function requireUser(request: Request): Promise<AuthContext> {
  const authorization = request.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("AUTH_REQUIRED");

  const url = Deno.env.get("SUPABASE_URL");
  const publishableKey = resolvePublishableKey();
  if (!url || !publishableKey) throw new Error("SUPABASE_ENV_MISSING");

  const client = createClient(url, publishableKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) throw new Error("AUTH_INVALID");
  return { client, user: data.user, token };
}

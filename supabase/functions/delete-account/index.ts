import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireUser } from "../_shared/auth.ts";
import { handleOptions, jsonResponse } from "../_shared/cors.ts";

Deno.serve(async (request) => {
  const preflight = handleOptions(request);
  if (preflight) return preflight;
  if (request.method !== "POST") return jsonResponse({ error: "METHOD_NOT_ALLOWED" }, 405);

  try {
    const { user } = await requireUser(request);
    const url = Deno.env.get("SUPABASE_URL");
    const adminKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY");
    if (!url || !adminKey) throw new Error("SUPABASE_ADMIN_ENV_MISSING");

    const admin = createClient(url, adminKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error } = await admin.auth.admin.deleteUser(user.id);
    if (error) throw error;

    return jsonResponse({ deleted: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : "UNKNOWN_ERROR";
    const status = message.startsWith("AUTH_") ? 401 : 500;
    return jsonResponse({ error: message, message: status === 401 ? "登录已过期，请重新登录" : "账号删除失败，请稍后重试" }, status);
  }
});

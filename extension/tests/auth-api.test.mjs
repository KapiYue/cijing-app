import test from "node:test";
import assert from "node:assert/strict";

test("uses the real email for sign-in and requires email confirmation", async () => {
  const storage = new Map();
  globalThis.chrome = {
    storage: {
      local: {
        async get(key) { return { [key]: storage.get(key) }; },
        async set(values) { Object.entries(values).forEach(([key, value]) => storage.set(key, value)); },
        async remove(key) { storage.delete(key); }
      }
    }
  };

  const requests = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    const body = JSON.parse(options.body);
    requests.push({ url: String(url), body });

    if (String(url).includes("grant_type=password") && requests.length === 1) {
      return new Response(JSON.stringify({ error_description: "Invalid login credentials" }), {
        status: 400,
        headers: { "Content-Type": "application/json" }
      });
    }
    if (String(url).endsWith("/auth/v1/signup") && body.email === "pending@example.com") {
      return new Response(JSON.stringify({ user: { id: "pending-user", email: body.email } }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }
    return new Response(JSON.stringify({
      access_token: "access-token",
      refresh_token: "refresh-token",
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      user: { email: body.email }
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  };

  try {
    const api = await import("../shared/api.js");
    const session = await api.signIn("\u200BTest5@QQ.COM ", " Ｚｚ１３５２４６。\u200B ");
    assert.equal(session.user.email, "test5@qq.com");
    assert.deepEqual(requests.slice(0, 2).map(({ body }) => body), [
      { email: "test5@qq.com", password: " Ｚｚ１３５２４６。\u200B " },
      { email: "test5@qq.com", password: "Zz135246." }
    ]);
    assert.deepEqual(await api.sessionSummary(), { signedIn: true, email: "test5@qq.com" });

    await assert.rejects(
      () => api.signUp(" New_User@Example.COM ", "StrongPass9!"),
      /邮箱验证服务暂时不可用/
    );
    assert.deepEqual(await api.sessionSummary(), { signedIn: false });

    const pending = await api.signUp("pending@example.com", "StrongPass9!");
    assert.deepEqual(pending, {
      confirmationRequired: true,
      email: "pending@example.com",
      session: null
    });
    assert.deepEqual(await api.sessionSummary(), { signedIn: false });

    await assert.rejects(() => api.signUp("bad@name", "StrongPass9!"), /有效邮箱/);
    await assert.rejects(() => api.signUp("valid@example.com", "short"), /密码至少需要 8 位/);
  } finally {
    globalThis.fetch = originalFetch;
    delete globalThis.chrome;
  }
});

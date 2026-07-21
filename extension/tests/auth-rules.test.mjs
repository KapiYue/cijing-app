import test from "node:test";
import assert from "node:assert/strict";
import {
  compatibilityPassword,
  isValidEmail,
  normalizeEmail,
  validateCredentials
} from "../shared/auth.js";

test("normalizes and validates email credentials in one shared module", () => {
  assert.equal(normalizeEmail(" \u200BＴｅｓｔ５＠ＱＱ．ＣＯＭ "), "test5@qq.com");
  assert.equal(isValidEmail("test5@qq.com"), true);
  assert.equal(isValidEmail("test5@qq"), false);
  assert.deepEqual(validateCredentials(" Test5@QQ.COM ", "123456", { isSignUp: false }), {
    email: "test5@qq.com",
    password: "123456"
  });
  assert.throws(
    () => validateCredentials("test5@qq.com", "123456", { isSignUp: true }),
    /密码至少需要 8 位/
  );
  assert.equal(compatibilityPassword(" Ｚｚ１３５２４６。\u200B "), "Zz135246.");
});

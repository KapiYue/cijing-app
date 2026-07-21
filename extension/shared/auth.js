export const MIN_PASSWORD_LENGTH = 8;

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/u;
const INVISIBLE_CHARACTERS = /[\u200B-\u200D\uFEFF]/g;

export function normalizeEmail(value) {
  return String(value || "")
    .normalize("NFKC")
    .replace(INVISIBLE_CHARACTERS, "")
    .trim()
    .toLowerCase();
}

export function isValidEmail(value) {
  const email = normalizeEmail(value);
  return email.length <= 254 && EMAIL_PATTERN.test(email);
}

export function validateCredentials(email, password, { isSignUp = false } = {}) {
  const normalizedEmail = normalizeEmail(email);
  if (!isValidEmail(normalizedEmail)) throw new Error("请输入有效邮箱地址。");
  if (!String(password).length) throw new Error("请输入密码。");
  if (isSignUp && String(password).length < MIN_PASSWORD_LENGTH) {
    throw new Error(`密码至少需要 ${MIN_PASSWORD_LENGTH} 位。`);
  }
  return { email: normalizedEmail, password: String(password) };
}

export function compatibilityPassword(value) {
  return String(value || "")
    .normalize("NFKC")
    .replace(INVISIBLE_CHARACTERS, "")
    .replaceAll("。", ".")
    .trim();
}

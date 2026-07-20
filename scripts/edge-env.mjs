import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { readEnvFile } from "./load-env.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const config = readEnvFile(path.join(root, ".env"));
const mode = process.argv[2];
if (!new Set(["serve", "secrets"]).has(mode)) {
  throw new Error("用法：node scripts/edge-env.mjs <serve|secrets> [Supabase CLI 参数]");
}
for (const key of ["OPENROUTER_API_KEY", "OPENROUTER_MODEL"]) {
  if (!config[key]) throw new Error(`.env 中缺少 ${key}`);
}

const tempDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "cijing-edge-secrets-"));
const tempEnv = path.join(tempDirectory, ".env");
try {
  fs.writeFileSync(tempEnv, `OPENROUTER_API_KEY=${JSON.stringify(config.OPENROUTER_API_KEY)}\nOPENROUTER_MODEL=${JSON.stringify(config.OPENROUTER_MODEL)}\n`, { mode: 0o600 });
  const command = mode === "serve"
    ? ["functions", "serve", "--env-file", tempEnv, "--no-verify-jwt", ...process.argv.slice(3)]
    : ["secrets", "set", "--env-file", tempEnv, ...process.argv.slice(3)];
  const result = spawnSync(
    path.join(root, "scripts/supabase.sh"),
    command,
    { cwd: root, stdio: "inherit" },
  );
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
} finally {
  fs.rmSync(tempDirectory, { recursive: true, force: true });
}

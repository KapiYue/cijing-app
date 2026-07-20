import fs from "node:fs";

function parseValue(raw) {
  const value = raw.trim();
  const quotePairs = [["\"", "\""], ["'", "'"], ["“", "”"], ["‘", "’"]];
  if (value.length >= 2 && quotePairs.some(([opening, closing]) => value.startsWith(opening) && value.endsWith(closing))) {
    return value.slice(1, -1);
  }
  return value;
}

export function readEnvFile(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`缺少 ${filePath}，请先复制 .env.example 为 .env 并填写配置`);
  }

  const values = {};
  for (const rawLine of fs.readFileSync(filePath, "utf8").split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const separator = line.indexOf("=");
    if (separator <= 0) continue;
    const key = line.slice(0, separator).trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) continue;
    values[key] = parseValue(line.slice(separator + 1));
  }
  return values;
}

export function loadEnv(filePath) {
  const values = readEnvFile(filePath);
  for (const [key, value] of Object.entries(values)) {
    if (process.env[key] === undefined) process.env[key] = value;
  }
  return values;
}

export function setEnvValue(filePath, key, value) {
  const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/);
  const prefix = `${key}=`;
  const index = lines.findIndex((line) => line.trimStart().startsWith(prefix));
  if (index >= 0) lines[index] = `${key}=${value}`;
  else lines.push(`${key}=${value}`);
  fs.writeFileSync(filePath, `${lines.join("\n").replace(/\n+$/, "")}\n`);
}

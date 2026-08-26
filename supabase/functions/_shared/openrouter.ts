const forbiddenProviders = ["openai/", "anthropic/", "google/"];

function selectedModel(): string {
  const model = Deno.env.get("OPENROUTER_MODEL");
  if (!model) throw new Error("OPENROUTER_MODEL_MISSING");
  if (forbiddenProviders.some((provider) => model.toLowerCase().startsWith(provider))) {
    throw new Error("FORBIDDEN_MODEL_PROVIDER");
  }
  return model;
}

export async function openRouterJSON<T>(options: {
  system: string;
  user: string;
  schemaName: string;
  schema: Record<string, unknown>;
  temperature?: number;
  maxTokens?: number;
}): Promise<T> {
  const apiKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!apiKey) throw new Error("OPENROUTER_API_KEY_MISSING");

  const schemaText = JSON.stringify(options.schema);
  const messages = [
    {
      role: "system",
      content: `${options.system} Return only valid JSON matching this exact JSON Schema; use every required property name exactly as written: ${schemaText}`,
    },
    { role: "user", content: options.user },
  ];

  async function complete(currentMessages: Array<{ role: string; content: string }>): Promise<{ value: unknown; content: string }> {
    const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://cijing.app",
        // Fetch headers must be ByteString-compatible in the Edge runtime.
        "X-Title": "CiJing Vocabulary",
      },
      body: JSON.stringify({
        model: selectedModel(),
        messages: currentMessages,
        temperature: options.temperature ?? 0.35,
        max_tokens: options.maxTokens ?? 2200,
        reasoning: { enabled: false },
        provider: {
          // Reject endpoints that may retain prompts for training or other
          // non-transient collection. The configured production model is not
          // confirmed to be on OpenRouter's ZDR endpoint list, so the stricter
          // `zdr: true` flag would risk making it unavailable.
          data_collection: "deny",
        },
        response_format: {
          type: "json_schema",
          json_schema: { name: options.schemaName, strict: true, schema: options.schema },
        },
      }),
    });
    if (!response.ok) {
      const detail = (await response.text()).slice(0, 1200);
      throw new Error(`OPENROUTER_${response.status}: ${detail}`);
    }
    const payload = await response.json();
    const content = payload?.choices?.[0]?.message?.content;
    if (typeof content !== "string") throw new Error("OPENROUTER_EMPTY_RESPONSE");
    try {
      return { value: JSON.parse(content), content };
    } catch {
      throw new Error("OPENROUTER_INVALID_JSON");
    }
  }

  const first = await complete(messages);
  const firstIssues = schemaIssues(first.value, options.schema);
  if (!firstIssues.length) return first.value as T;

  const corrected = await complete([
    ...messages,
    { role: "assistant", content: first.content },
    {
      role: "user",
      content: `Your previous JSON violated the required schema: ${firstIssues.slice(0, 12).join("; ")}. Rewrite the result now. Use exactly the required keys and types from this JSON Schema, with no extra commentary: ${schemaText}`,
    },
  ]);
  const correctedIssues = schemaIssues(corrected.value, options.schema);
  if (correctedIssues.length) throw new Error(`OPENROUTER_SCHEMA_MISMATCH: ${correctedIssues.slice(0, 12).join("; ")}`);
  return corrected.value as T;
}

function schemaIssues(value: unknown, schema: Record<string, unknown>, path = "$"): string[] {
  const type = schema.type;
  if (type === "object") {
    if (!value || typeof value !== "object" || Array.isArray(value)) return [`${path} must be object`];
    const record = value as Record<string, unknown>;
    const required = Array.isArray(schema.required) ? schema.required as string[] : [];
    const issues = required.filter((key) => !(key in record)).map((key) => `${path}.${key} is required`);
    const properties = schema.properties && typeof schema.properties === "object" ? schema.properties as Record<string, Record<string, unknown>> : {};
    for (const [key, childSchema] of Object.entries(properties)) {
      if (key in record) issues.push(...schemaIssues(record[key], childSchema, `${path}.${key}`));
    }
    return issues;
  }
  if (type === "array") {
    if (!Array.isArray(value)) return [`${path} must be array`];
    const issues: string[] = [];
    if (typeof schema.minItems === "number" && value.length < schema.minItems) issues.push(`${path} needs at least ${schema.minItems} items`);
    if (typeof schema.maxItems === "number" && value.length > schema.maxItems) issues.push(`${path} allows at most ${schema.maxItems} items`);
    if (schema.items && typeof schema.items === "object") {
      value.forEach((item, index) => issues.push(...schemaIssues(item, schema.items as Record<string, unknown>, `${path}[${index}]`)));
    }
    return issues;
  }
  if (type === "string" && typeof value !== "string") return [`${path} must be string`];
  if (type === "number" && typeof value !== "number") return [`${path} must be number`];
  if (type === "integer" && (typeof value !== "number" || !Number.isInteger(value))) return [`${path} must be integer`];
  if (type === "boolean" && typeof value !== "boolean") return [`${path} must be boolean`];
  return [];
}

export async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

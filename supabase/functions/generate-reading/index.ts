import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser } from "../_shared/auth.ts";
import { openRouterJSON, sha256 } from "../_shared/openrouter.ts";

type TargetWord = { id: string; term: string; lemma: string; primary_meaning: string; contextual_meaning?: string };
type ReadingResult = {
  title: string;
  subtitle: string;
  paragraphs: Array<{ english: string; chinese: string }>;
};

const themes = new Set(["daily_life", "travel", "business", "technology", "campus", "workplace", "news", "psychology", "movies", "sports"]);
const styles = new Set(["story", "article", "dialogue", "news"]);
const difficulties = new Set(["beginner", "elementary", "intermediate", "upper_intermediate", "advanced"]);

const readingSchema = {
  type: "object",
  additionalProperties: false,
  required: ["title", "subtitle", "paragraphs"],
  properties: {
    title: { type: "string" },
    subtitle: { type: "string" },
    paragraphs: {
      type: "array", minItems: 3, maxItems: 7,
      items: {
        type: "object", additionalProperties: false, required: ["english", "chinese"],
        properties: { english: { type: "string" }, chinese: { type: "string" } },
      },
    },
  },
};

function wordPrompt(words: TargetWord[]): string {
  return words.map((word, index) => `${index + 1}. ${word.lemma || word.term}: ${word.contextual_meaning || word.primary_meaning}`).join("\n");
}

// 生成次数是事件计数，与"存了几篇短文"是两回事：命中缓存不产生新文章，但仍然
// 是一次成功的生成。计数失败不影响本次生成的结果，只记日志。
async function countGeneration(client: { rpc: (name: string) => PromiseLike<{ error: unknown }> }, userID: string) {
  const { error } = await client.rpc("record_reading_generation");
  if (error) console.error("record_reading_generation failed", userID, error);
}

Deno.serve(async (request) => {
  const preflight = handleOptions(request);
  if (preflight) return preflight;
  if (request.method !== "POST") return jsonResponse({ error: "METHOD_NOT_ALLOWED" }, 405);

  try {
    const { client, user } = await requireUser(request);
    const body = await request.json();
    const theme = themes.has(body.theme) ? body.theme : "daily_life";
    const style = styles.has(body.style) ? body.style : "story";
    const difficulty = difficulties.has(body.difficulty) ? body.difficulty : "intermediate";
    const regenerate = body.regenerate === true;
    const requestedIds = Array.isArray(body.targetWordIds) ? body.targetWordIds.slice(0, 15) : [];

    let query = client.from("words").select("id,term,lemma,primary_meaning,contextual_meaning,status,strength,due_at").neq("status", "ignored");
    if (requestedIds.length) query = query.in("id", requestedIds);
    const { data, error } = await query.limit(40);
    if (error) throw error;

    const candidates = (data ?? []) as Array<TargetWord & { status: string; strength: number; due_at: string }>;
    candidates.sort((a, b) => {
      const rank = (word: typeof a) => word.status === "weak" ? 0 : new Date(word.due_at) <= new Date() && word.status !== "new" ? 1 : word.status === "new" ? 2 : 3;
      return rank(a) - rank(b) || a.strength - b.strength;
    });
    const targetWords = candidates.slice(0, Math.max(5, Math.min(Number(body.wordCount) || 10, 15)));
    if (targetWords.length < 3) return jsonResponse({ error: "NOT_ENOUGH_WORDS", message: "请先收藏至少 3 个单词" }, 400);

    const cacheKey = await sha256(JSON.stringify({ ids: targetWords.map((word) => word.id).sort(), theme, style, difficulty }));
    if (!regenerate) {
      const { data: cached } = await client.from("reading_sessions")
        .select("*").eq("user_id", user.id).eq("cache_key", cacheKey)
        .order("created_at", { ascending: false }).limit(1).maybeSingle();
      // 命中缓存不再复制一行：一篇文章只该有一行，否则"最近的短文"里会冒出
      // 同名条目。生成次数是独立的事件计数，记在 daily_activity.generation_count
      // 上，与文章行数解耦。
      if (cached) {
        await countGeneration(client, user.id);
        return jsonResponse({ data: { ...cached, is_cached: true }, cached: true });
      }
    }

    const targetList = wordPrompt(targetWords);
    const result = await openRouterJSON<ReadingResult>({
      schemaName: "personalized_reading",
      schema: readingSchema,
      temperature: regenerate ? 0.72 : 0.55,
      maxTokens: 5200,
      system: [
        "You write coherent graded English readings for Chinese learners.",
        "Create one natural, engaging multi-paragraph piece; never stitch unrelated example sentences.",
        "Use EVERY target lemma naturally and preserve its spelling as a standalone word (normal inflections are acceptable only when necessary).",
        "Each Chinese paragraph must faithfully translate the corresponding English paragraph.",
        "Do not add markdown, vocabulary lists, exercises, or bracketed annotations.",
      ].join(" "),
      user: `Difficulty: ${difficulty}\nTheme: ${theme}\nStyle: ${style}\nTarget words:\n${targetList}`,
    });

    const row = {
      user_id: user.id,
      title: result.title,
      subtitle: result.subtitle,
      theme,
      style,
      difficulty,
      target_word_ids: targetWords.map((word) => word.id),
      target_terms: targetWords.map((word) => word.lemma || word.term),
      paragraphs: result.paragraphs,
      estimated_minutes: Math.max(3, Math.ceil(result.paragraphs.reduce((sum, paragraph) => sum + paragraph.english.split(/\s+/).length, 0) / 120)),
      cache_key: cacheKey,
      is_cached: false,
    };
    const { data: inserted, error: insertError } = await client.from("reading_sessions").insert(row).select("*").single();
    if (insertError) throw insertError;
    await countGeneration(client, user.id);
    return jsonResponse({ data: inserted, cached: false });
  } catch (error) {
    const message = error instanceof Error ? error.message : "UNKNOWN_ERROR";
    const status = message.startsWith("AUTH_") ? 401 : message.startsWith("OPENROUTER_") ? 502 : 500;
    return jsonResponse({ error: message }, status);
  }
});

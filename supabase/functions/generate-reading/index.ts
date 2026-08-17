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
      // 缓存只用来省掉 LLM 调用，不用来省掉记录：每次生成成功都要是一次独立的
      // 阅读，否则"今天生成了两次、短文计数没动"（既有 completed_at 也让
      // mark_reading_complete 提前 return）。复制内容新开一行，标记 is_cached
      // 让客户端能提示"沿用了上次生成的短文"。
      if (cached) {
        const { data: reused, error: reuseError } = await client.from("reading_sessions").insert({
          user_id: user.id,
          title: cached.title,
          subtitle: cached.subtitle,
          theme: cached.theme,
          style: cached.style,
          difficulty: cached.difficulty,
          target_word_ids: cached.target_word_ids,
          target_terms: cached.target_terms,
          paragraphs: cached.paragraphs,
          estimated_minutes: cached.estimated_minutes,
          cache_key: cacheKey,
          is_cached: true,
        }).select("*").single();
        if (reuseError) throw reuseError;
        return jsonResponse({ data: reused, cached: true });
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
    return jsonResponse({ data: inserted, cached: false });
  } catch (error) {
    const message = error instanceof Error ? error.message : "UNKNOWN_ERROR";
    const status = message.startsWith("AUTH_") ? 401 : message.startsWith("OPENROUTER_") ? 502 : 500;
    return jsonResponse({ error: message }, status);
  }
});

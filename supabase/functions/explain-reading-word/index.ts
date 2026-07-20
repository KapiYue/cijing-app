import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser } from "../_shared/auth.ts";
import { openRouterJSON, sha256 } from "../_shared/openrouter.ts";

const schema = {
  type: "object",
  additionalProperties: false,
  required: ["term", "lemma", "phonetic", "partOfSpeech", "meaning", "contextualMeaning", "sentence"],
  properties: {
    term: { type: "string" }, lemma: { type: "string" }, phonetic: { type: "string" },
    partOfSpeech: { type: "string" }, meaning: { type: "string" }, contextualMeaning: { type: "string" }, sentence: { type: "string" },
  },
};

Deno.serve(async (request) => {
  const preflight = handleOptions(request);
  if (preflight) return preflight;
  try {
    const { client, user } = await requireUser(request);
    const body = await request.json();
    const term = String(body.word ?? "").replace(/^[^A-Za-z'-]+|[^A-Za-z'-]+$/g, "").slice(0, 60);
    const sentence = String(body.sentence ?? "").slice(0, 800);
    if (!term) return jsonResponse({ error: "INVALID_WORD" }, 400);
    const contextHash = await sha256(`reading\n${term.toLowerCase()}\n${sentence.toLowerCase()}`);
    const { data: cached } = await client.from("lexicon_cache").select("result")
      .eq("user_id", user.id).eq("normalized_term", term.toLowerCase()).eq("context_hash", contextHash).maybeSingle();
    if (cached?.result) return jsonResponse({ data: cached.result, cached: true });

    const result = await openRouterJSON<Record<string, string>>({
      schemaName: "reading_word_explanation", schema,
      system: "Explain a word in its sentence for a Chinese English learner. Use Simplified Chinese for meaning fields and General American IPA. Return no markdown.",
      user: `Word: ${term}\nSentence: ${sentence}`,
    });
    await client.from("lexicon_cache").upsert({ user_id: user.id, normalized_term: term.toLowerCase(), context_hash: contextHash, result }, { onConflict: "user_id,normalized_term,context_hash" });
    return jsonResponse({ data: result, cached: false });
  } catch (error) {
    const message = error instanceof Error ? error.message : "UNKNOWN_ERROR";
    return jsonResponse({ error: message }, message.startsWith("AUTH_") ? 401 : 500);
  }
});


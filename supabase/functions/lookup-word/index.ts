import { handleOptions, jsonResponse } from "../_shared/cors.ts";
import { requireUser } from "../_shared/auth.ts";
import { openRouterJSON, sha256 } from "../_shared/openrouter.ts";
import {
  fetchPublicDictionary,
  type DictionaryAttribution,
  type PublicDictionaryEntry,
} from "../_shared/free-dictionary.ts";

type Part = { partOfSpeech: string; meaning: string };
type LookupResult = {
  term: string;
  lemma: string;
  phonetic: string;
  parts: Part[];
  primaryMeaning: string;
  contextualMeaning: string;
  englishDefinition: string;
  exampleEnglish: string;
  exampleChinese: string;
  sentence: string;
  audioUrl?: string | null;
  dictionaryAttribution?: DictionaryAttribution;
};

const lookupSchema = {
  type: "object",
  additionalProperties: false,
  required: ["term", "lemma", "phonetic", "parts", "primaryMeaning", "contextualMeaning", "englishDefinition", "exampleEnglish", "exampleChinese", "sentence"],
  properties: {
    term: { type: "string" },
    lemma: { type: "string" },
    phonetic: { type: "string", description: "General American IPA without slash characters" },
    parts: {
      type: "array",
      minItems: 1,
      maxItems: 4,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["partOfSpeech", "meaning"],
        properties: { partOfSpeech: { type: "string" }, meaning: { type: "string" } },
      },
    },
    primaryMeaning: { type: "string" },
    contextualMeaning: { type: "string" },
    englishDefinition: { type: "string" },
    exampleEnglish: { type: "string" },
    exampleChinese: { type: "string" },
    sentence: { type: "string" },
  },
};

Deno.serve(async (request) => {
  const preflight = handleOptions(request);
  if (preflight) return preflight;
  if (request.method !== "POST") return jsonResponse({ error: "METHOD_NOT_ALLOWED" }, 405);

  try {
    const { client, user } = await requireUser(request);
    const body = await request.json();
    const term = String(body.word ?? "").trim().replace(/^[^A-Za-z'-]+|[^A-Za-z'-]+$/g, "");
    const context = String(body.context ?? "").trim().slice(0, 1800);
    const sentence = String(body.sentence ?? "").trim().slice(0, 600);
    if (!/^[A-Za-z][A-Za-z'-]{0,60}$/.test(term)) {
      return jsonResponse({ error: "INVALID_WORD", message: "请选择一个英文单词" }, 400);
    }

    const normalized = term.toLowerCase();
    const contextHash = await sha256(`${normalized}\n${context.toLowerCase()}`);
    const { data: cached } = await client
      .from("lexicon_cache")
      .select("result,expires_at")
      .eq("user_id", user.id)
      .eq("normalized_term", normalized)
      .eq("context_hash", contextHash)
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();
    if (cached?.result) {
      const cachedResult = cached.result as LookupResult;
      if (cachedResult.dictionaryAttribution) return jsonResponse({ data: cachedResult, cached: true });
      const publicEntry = await fetchPublicDictionary(term);
      const refreshedResult = {
        ...cachedResult,
        audioUrl: publicEntry?.audioUrl ?? cachedResult.audioUrl ?? null,
        ...(publicEntry ? { dictionaryAttribution: publicEntry.attribution } : {}),
      };
      if (publicEntry) {
        await client.from("lexicon_cache").update({ result: refreshedResult })
          .eq("user_id", user.id).eq("normalized_term", normalized).eq("context_hash", contextHash);
      }
      return jsonResponse({ data: refreshedResult, cached: true });
    }

    // A public dictionary is the canonical source for pronunciation and English
    // definitions. The language model only adds Chinese/contextual enrichment.
    const publicEntry = await fetchPublicDictionary(term);

    let result: LookupResult;
    try {
      const enriched = await openRouterJSON<LookupResult>({
        schemaName: "word_lookup",
        schema: lookupSchema,
        system: [
          "You are the lexicographer inside a Chinese English-learning product.",
          "Explain the selected English word accurately and compactly for a Chinese learner.",
          "Treat the supplied public-dictionary entry as the factual reference when present.",
          "Infer the meaning used in the supplied context. Use Simplified Chinese for Chinese fields.",
          "Use General American IPA. The English example must be natural and different from the supplied sentence.",
          "Never include markdown.",
        ].join(" "),
        user: `Selected word: ${term}\nSentence: ${sentence || "(not available)"}\nSurrounding context: ${context || "(not available)"}\nPublic dictionary reference: ${publicEntry ? JSON.stringify(publicEntry) : "(not found)"}`,
      });
      result = {
        ...enriched,
        phonetic: publicEntry?.phonetic || enriched.phonetic,
        englishDefinition: publicEntry?.definition || enriched.englishDefinition,
        exampleEnglish: enriched.exampleEnglish || publicEntry?.example || sentence,
        audioUrl: publicEntry?.audioUrl ?? null,
        ...(publicEntry ? { dictionaryAttribution: publicEntry.attribution } : {}),
      };
    } catch (error) {
      if (!publicEntry) throw error;
      result = publicFallback(publicEntry, term, sentence);
    }

    await client.from("lexicon_cache").upsert({
      user_id: user.id,
      normalized_term: normalized,
      context_hash: contextHash,
      result,
      expires_at: new Date(Date.now() + 90 * 86400_000).toISOString(),
    }, { onConflict: "user_id,normalized_term,context_hash" });

    return jsonResponse({ data: result, cached: false });
  } catch (error) {
    const message = error instanceof Error ? error.message : "UNKNOWN_ERROR";
    const status = message.startsWith("AUTH_") ? 401 : message.startsWith("OPENROUTER_") ? 502 : 500;
    return jsonResponse({ error: message }, status);
  }
});

function publicFallback(entry: PublicDictionaryEntry, term: string, sentence: string): LookupResult {
  const parts = entry.parts.map((item) => ({
    partOfSpeech: item.partOfSpeech,
    meaning: `英文释义：${item.definition}`,
  }));
  return {
    term: entry.term || term,
    lemma: entry.term || term,
    phonetic: entry.phonetic,
    parts,
    primaryMeaning: parts[0]?.meaning ?? `英文释义：${entry.definition}`,
    contextualMeaning: `当前语境可参考：${entry.definition}`,
    englishDefinition: entry.definition,
    exampleEnglish: entry.example || sentence || `${entry.term || term} is used in this context.`,
    exampleChinese: "中文释义暂时不可用，已展示公开词典释义。",
    sentence,
    audioUrl: entry.audioUrl,
    dictionaryAttribution: entry.attribution,
  };
}

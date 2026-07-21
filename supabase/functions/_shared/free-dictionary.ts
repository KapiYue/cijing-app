export type PublicDictionaryPart = {
  partOfSpeech: string;
  definition: string;
  example?: string;
};

export type PublicDictionaryEntry = {
  term: string;
  phonetic: string;
  audioUrl: string | null;
  parts: PublicDictionaryPart[];
  definition: string;
  example: string;
};

type DictionaryDefinition = { definition?: unknown; example?: unknown };
type DictionaryMeaning = { partOfSpeech?: unknown; definitions?: unknown };
type DictionaryPhonetic = { text?: unknown; audio?: unknown };
type DictionaryResponseEntry = {
  word?: unknown;
  phonetic?: unknown;
  phonetics?: unknown;
  meanings?: unknown;
};

/**
 * Reads canonical pronunciation and English definitions from Free Dictionary API.
 * The API and its data are public; callers can fall back to another source when a
 * rare word is not present or the service is unavailable.
 */
export async function fetchPublicDictionary(term: string): Promise<PublicDictionaryEntry | null> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5_000);
  try {
    const response = await fetch(`https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(term)}`, {
      headers: { Accept: "application/json" },
      signal: controller.signal,
    });
    if (!response.ok) return null;
    const payload = await response.json();
    if (!Array.isArray(payload) || !payload.length) return null;

    const entries = payload.filter((item): item is DictionaryResponseEntry => Boolean(item && typeof item === "object"));
    const phonetics = entries.flatMap((entry) => Array.isArray(entry.phonetics) ? entry.phonetics : [])
      .filter((item): item is DictionaryPhonetic => Boolean(item && typeof item === "object"));
    const audioCandidates = phonetics.map((item) => typeof item.audio === "string" ? item.audio.trim() : "").filter(Boolean);
    const audio = audioCandidates.find((value) => /(?:^|[-_/])us(?:[-_.?/]|$)/i.test(value)) ?? audioCandidates[0] ?? "";
    const phonetic = entries.map((entry) => typeof entry.phonetic === "string" ? entry.phonetic : "").find(Boolean)
      ?? phonetics.map((item) => typeof item.text === "string" ? item.text : "").find(Boolean)
      ?? "";

    const parts: PublicDictionaryPart[] = [];
    for (const entry of entries) {
      const meanings = Array.isArray(entry.meanings) ? entry.meanings : [];
      for (const rawMeaning of meanings) {
        if (!rawMeaning || typeof rawMeaning !== "object") continue;
        const meaning = rawMeaning as DictionaryMeaning;
        const definitions = Array.isArray(meaning.definitions) ? meaning.definitions : [];
        const first = definitions.find((item): item is DictionaryDefinition => Boolean(item && typeof item === "object" && typeof (item as DictionaryDefinition).definition === "string"));
        if (!first || typeof first.definition !== "string") continue;
        parts.push({
          partOfSpeech: typeof meaning.partOfSpeech === "string" ? meaning.partOfSpeech : "word",
          definition: first.definition.trim(),
          example: typeof first.example === "string" ? first.example.trim() : undefined,
        });
      }
    }
    if (!parts.length) return null;
    const example = parts.map((item) => item.example ?? "").find(Boolean) ?? "";
    return {
      term: typeof entries[0]?.word === "string" ? entries[0].word : term,
      phonetic: phonetic.replace(/^\/+|\/+$/g, ""),
      audioUrl: audio ? (audio.startsWith("//") ? `https:${audio}` : audio) : null,
      parts: parts.slice(0, 4),
      definition: parts[0].definition,
      example,
    };
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

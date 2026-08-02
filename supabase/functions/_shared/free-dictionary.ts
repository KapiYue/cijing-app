export type PublicDictionaryPart = {
  partOfSpeech: string;
  definition: string;
  example?: string;
};

export type DictionaryLicense = {
  name: string;
  url: string;
};

export type DictionaryAudioAttribution = {
  sourceUrl: string;
  license: DictionaryLicense;
};

export type DictionaryAttribution = {
  provider: "Free Dictionary API";
  providerUrl: "https://dictionaryapi.dev/";
  sourceUrls: string[];
  licenses: DictionaryLicense[];
  audio?: DictionaryAudioAttribution;
};

export type PublicDictionaryEntry = {
  term: string;
  phonetic: string;
  audioUrl: string | null;
  parts: PublicDictionaryPart[];
  definition: string;
  example: string;
  attribution: DictionaryAttribution;
};

type DictionaryDefinition = { definition?: unknown; example?: unknown };
type DictionaryMeaning = { partOfSpeech?: unknown; definitions?: unknown };
type DictionaryLicenseResponse = { name?: unknown; url?: unknown };
type DictionaryPhonetic = { text?: unknown; audio?: unknown; sourceUrl?: unknown; license?: unknown };
type DictionaryResponseEntry = {
  word?: unknown;
  phonetic?: unknown;
  phonetics?: unknown;
  meanings?: unknown;
  sourceUrls?: unknown;
  license?: unknown;
};

/**
 * Reads attributed pronunciation and English definitions from Free Dictionary API.
 * Entries without a traceable source and content license are not used.
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
    const audioCandidates = phonetics
      .map((item) => ({ item, url: typeof item.audio === "string" ? normalizeUrl(item.audio) : "" }))
      .filter((candidate) => candidate.url && audioAttribution(candidate.item));
    const selectedAudio = audioCandidates.find((candidate) => /(?:^|[-_/])us(?:[-_.?/]|$)/i.test(candidate.url))
      ?? audioCandidates[0];
    const phonetic = entries.map((entry) => typeof entry.phonetic === "string" ? entry.phonetic : "").find(Boolean)
      ?? phonetics.map((item) => typeof item.text === "string" ? item.text : "").find(Boolean)
      ?? "";
    const sourceUrls = unique(entries.flatMap((entry) => Array.isArray(entry.sourceUrls) ? entry.sourceUrls : [])
      .filter((value): value is string => typeof value === "string")
      .map(normalizeUrl)
      .filter(Boolean));
    const licenses = uniqueLicenses(entries.map((entry) => parseLicense(entry.license)).filter((license): license is DictionaryLicense => Boolean(license)));
    if (!sourceUrls.length || !licenses.length) return null;

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
      audioUrl: selectedAudio?.url ?? null,
      parts: parts.slice(0, 4),
      definition: parts[0].definition,
      example,
      attribution: {
        provider: "Free Dictionary API",
        providerUrl: "https://dictionaryapi.dev/",
        sourceUrls,
        licenses,
        ...(selectedAudio ? { audio: audioAttribution(selectedAudio.item) ?? undefined } : {}),
      },
    };
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function normalizeUrl(value: string): string {
  const trimmed = value.trim();
  if (trimmed.startsWith("//")) return `https:${trimmed}`;
  return /^https:\/\//i.test(trimmed) ? trimmed : "";
}

function parseLicense(value: unknown): DictionaryLicense | null {
  if (!value || typeof value !== "object") return null;
  const license = value as DictionaryLicenseResponse;
  const name = typeof license.name === "string" ? license.name.trim() : "";
  const url = typeof license.url === "string" ? normalizeUrl(license.url) : "";
  return name && url ? { name, url } : null;
}

function audioAttribution(item: DictionaryPhonetic): DictionaryAudioAttribution | null {
  const sourceUrl = typeof item.sourceUrl === "string" ? normalizeUrl(item.sourceUrl) : "";
  const license = parseLicense(item.license);
  return sourceUrl && license ? { sourceUrl, license } : null;
}

function unique(values: string[]): string[] {
  return [...new Set(values)];
}

function uniqueLicenses(values: DictionaryLicense[]): DictionaryLicense[] {
  return values.filter((license, index) =>
    values.findIndex((candidate) => candidate.name === license.name && candidate.url === license.url) === index
  );
}

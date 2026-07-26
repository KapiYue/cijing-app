(() => {
  function cleanWord(value = "") {
    return String(value).trim().replace(/^[^A-Za-z'-]+|[^A-Za-z'-]+$/g, "");
  }

  function findSentence(context, word) {
    if (!context) return "";
    try {
      const segments = [...new Intl.Segmenter("en", { granularity: "sentence" }).segment(context)];
      return (segments.find((item) => item.segment.toLowerCase().includes(word.toLowerCase()))?.segment || context).trim().slice(0, 600);
    } catch {
      return (context.split(/(?<=[.!?])\s+/).find((part) => part.toLowerCase().includes(word.toLowerCase())) || context).slice(0, 600);
    }
  }

  function formatPhonetic(value = "") {
    const phonetic = String(value).trim().replace(/^\/+|\/+$/g, "").trim();
    return phonetic ? `/${phonetic}/` : "";
  }

  function prepareLookupPayload(payload, privacyMode) {
    if (!privacyMode) return payload;
    return { ...payload, context: "", sentence: "", source_url: null, source_title: null };
  }

  globalThis.CiJingTextUtils = Object.freeze({ cleanWord, findSentence, formatPhonetic, prepareLookupPayload });
})();

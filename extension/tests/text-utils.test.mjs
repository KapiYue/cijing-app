import test from "node:test";
import assert from "node:assert/strict";

await import("../shared/text-utils.js");
const { cleanWord, findSentence, formatPhonetic, prepareLookupPayload } = globalThis.CiJingTextUtils;

test("cleans punctuation while keeping apostrophes", () => assert.equal(cleanWord("“don't,”"), "don't"));
test("finds selected word sentence", () => assert.equal(findSentence("First one. A resilient team adapts quickly. Last one.", "resilient"), "A resilient team adapts quickly."));
test("renders exactly one phonetic slash on each side", () => {
  assert.equal(formatPhonetic("steɪt"), "/steɪt/");
  assert.equal(formatPhonetic("/steɪt/"), "/steɪt/");
  assert.equal(formatPhonetic("//steɪt//"), "/steɪt/");
  assert.equal(formatPhonetic(""), "");
});

test("lookup payload sends only the selected word and current sentence", () => {
  const payload = {
    word: "state",
    context: "State appears in a private page.",
    sentence: "State appears in a private page.",
    source_url: "https://example.com/private",
    source_title: "Private page"
  };
  assert.deepEqual(prepareLookupPayload(payload, true), {
    word: "state",
    context: "",
    sentence: ""
  });
  assert.deepEqual(prepareLookupPayload(payload, false), {
    word: "state",
    context: "State appears in a private page.",
    sentence: "State appears in a private page."
  });
});

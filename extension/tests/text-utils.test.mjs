import test from "node:test";
import assert from "node:assert/strict";

function cleanWord(value = "") { return value.trim().replace(/^[^A-Za-z'-]+|[^A-Za-z'-]+$/g, ""); }
function findSentence(context, word) { return (context.split(/(?<=[.!?])\s+/).find((part) => part.toLowerCase().includes(word.toLowerCase())) || context).slice(0, 600); }

test("cleans punctuation while keeping apostrophes", () => assert.equal(cleanWord("“don't,”"), "don't"));
test("finds selected word sentence", () => assert.equal(findSentence("First one. A resilient team adapts quickly. Last one.", "resilient"), "A resilient team adapts quickly."));


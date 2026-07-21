import * as api from "./shared/api.js";
import { getPreferences } from "./shared/preferences.js";

const OFFSCREEN_PATH = "offscreen/audio.html";

async function ensureAudioDocument() {
  const documentUrl = chrome.runtime.getURL(OFFSCREEN_PATH);
  const contexts = await chrome.runtime.getContexts({ contextTypes: ["OFFSCREEN_DOCUMENT"], documentUrls: [documentUrl] });
  if (contexts.length) return;
  await chrome.offscreen.createDocument({
    url: OFFSCREEN_PATH,
    reasons: ["AUDIO_PLAYBACK"],
    justification: "播放公开词典提供的单词真人发音"
  });
}

async function playPronunciation(url, rate) {
  const parsed = new URL(url);
  const trustedHosts = new Set(["api.dictionaryapi.dev", "ssl.gstatic.com"]);
  if (parsed.protocol !== "https:" || !trustedHosts.has(parsed.hostname)) throw new Error("UNTRUSTED_AUDIO_SOURCE");
  await ensureAudioDocument();
  return chrome.runtime.sendMessage({ target: "cijing-audio", type: "PLAY_AUDIO", url: parsed.href, rate });
}

async function stopPronunciation() {
  const documentUrl = chrome.runtime.getURL(OFFSCREEN_PATH);
  const contexts = await chrome.runtime.getContexts({ contextTypes: ["OFFSCREEN_DOCUMENT"], documentUrls: [documentUrl] });
  if (contexts.length) await chrome.runtime.sendMessage({ target: "cijing-audio", type: "STOP_AUDIO" });
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({ id: "cijing-lookup", title: "用词鲸背单词查询“%s”", contexts: ["selection"] });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === "cijing-lookup" && tab?.id) {
    chrome.tabs.sendMessage(tab.id, { type: "LOOKUP_SELECTED", word: info.selectionText });
  }
});

chrome.commands.onCommand.addListener(async (command) => {
  if (command !== "lookup-selection") return;
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab?.id) chrome.tabs.sendMessage(tab.id, { type: "LOOKUP_SELECTED" });
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  const actions = {
    GET_SESSION: () => api.sessionSummary(),
    SIGN_UP: () => api.signUp(message.email, message.password),
    SIGN_IN: () => api.signIn(message.email, message.password),
    SIGN_OUT: () => api.signOut(),
    LOOKUP_WORD: () => api.lookupWord(message.payload),
    SAVE_WORD: () => api.saveWord(message.payload),
    GET_DASHBOARD: () => api.getDashboard(),
    GET_PREFERENCES: () => getPreferences(),
    PLAY_PRONUNCIATION: () => playPronunciation(message.url, message.rate),
    STOP_PRONUNCIATION: () => stopPronunciation(),
    TEST_CONNECTION: () => api.testConnection(),
    OPEN_LOGIN: () => chrome.action.openPopup()
  };
  const action = actions[message?.type];
  if (!action) return false;
  action().then((data) => sendResponse({ ok: true, data })).catch((error) => sendResponse({ ok: false, error: error.message }));
  return true;
});

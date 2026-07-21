import * as api from "./shared/api.js";
import { getPreferences } from "./shared/preferences.js";

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
    TEST_CONNECTION: () => api.testConnection(),
    OPEN_LOGIN: () => chrome.action.openPopup()
  };
  const action = actions[message?.type];
  if (!action) return false;
  action().then((data) => sendResponse({ ok: true, data })).catch((error) => sendResponse({ ok: false, error: error.message }));
  return true;
});

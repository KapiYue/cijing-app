let player = null;

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.target !== "cijing-audio") return false;
  if (message.type === "STOP_AUDIO") {
    player?.pause();
    player = null;
    sendResponse({ ok: true });
    return false;
  }
  if (message.type !== "PLAY_AUDIO") return false;
  try {
    player?.pause();
    const audio = new Audio(message.url);
    player = audio;
    audio.preload = "auto";
    audio.playbackRate = Math.min(1, Math.max(0.75, Number(message.rate) || 1));
    audio.preservesPitch = true;
    audio.addEventListener("ended", () => { if (player === audio) player = null; }, { once: true });
    audio.play().then(() => sendResponse({ ok: true })).catch((error) => sendResponse({ ok: false, error: error.message }));
  } catch (error) {
    sendResponse({ ok: false, error: error.message });
  }
  return true;
});

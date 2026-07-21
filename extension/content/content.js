(() => {
  const HOST_ID = "cijing-reader-card-host";
  const DEFAULT_PREFERENCES = { autoSave: false, saveContext: true, privacyMode: false, disabledHosts: [], theme: "purple" };
  let preferences = { ...DEFAULT_PREFERENCES };
  let lastSelection = null;
  let requestSerial = 0;

  const escapeHTML = (value = "") => String(value).replace(/[&<>'"]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);
  const cleanWord = (value = "") => value.trim().replace(/^[^A-Za-z'-]+|[^A-Za-z'-]+$/g, "");
  const validWord = (value) => /^[A-Za-z][A-Za-z'-]{0,60}$/.test(value);
  const currentHost = location.hostname.toLowerCase();

  function selectedPayload(forcedWord) {
    const selection = window.getSelection();
    const word = cleanWord(forcedWord || selection?.toString() || "");
    if (!validWord(word)) return null;
    let node = selection?.anchorNode?.nodeType === Node.TEXT_NODE ? selection.anchorNode.parentElement : selection?.anchorNode;
    const container = node?.closest?.("p,li,blockquote,article,section,main,td,figcaption") || node?.parentElement || document.body;
    const context = (container?.innerText || "").replace(/\s+/g, " ").trim().slice(0, 1800);
    const sentence = findSentence(context, word);
    const range = selection?.rangeCount ? selection.getRangeAt(0) : null;
    const rect = range?.getBoundingClientRect();
    return {
      word,
      context,
      sentence,
      source_url: location.href,
      source_title: document.title,
      rect: rect && rect.width ? rect : { left: window.innerWidth / 2, right: window.innerWidth / 2, top: 120, bottom: 140 }
    };
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

  function volumeIcon() {
    return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9v6h4l5 4V5L8 9H4Z"></path><path class="wave" d="M16 8.2a5 5 0 0 1 0 7.6M18.8 5.5a9 9 0 0 1 0 13"></path></svg>';
  }

  function shell(rect) {
    stopPronunciation();
    document.getElementById(HOST_ID)?.remove();
    const host = document.createElement("div");
    host.id = HOST_ID;
    host.style.cssText = "all:initial;position:fixed;z-index:2147483647;left:0;top:0";
    const shadow = host.attachShadow({ mode: "open" });
    shadow.innerHTML = `<style>
      :host{all:initial}.card{--accent:#7651c9;--accent-dark:#5f3faf;--accent-soft:#e9e0f8;position:fixed;width:min(380px,calc(100vw - 16px));max-height:calc(100vh - 16px);overflow:auto;overscroll-behavior:contain;scrollbar-gutter:stable;background:#fffdf8;color:#26212d;border:1px solid color-mix(in srgb,var(--accent) 20%,transparent);border-radius:20px;box-shadow:0 22px 70px rgba(73,47,99,.25);font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC",sans-serif;animation:in .16s ease-out}.card[data-theme="blue"]{--accent:#3977d6;--accent-dark:#275ba9;--accent-soft:#e4efff}.card[data-theme="green"]{--accent:#2d936c;--accent-dark:#207052;--accent-soft:#e0f4eb}.card[data-theme="orange"]{--accent:#d9823d;--accent-dark:#ae6127;--accent-soft:#fff0df}.card[data-theme="rose"]{--accent:#b95579;--accent-dark:#913d5d;--accent-soft:#f9e5ed}.inner{padding:18px}.brand{display:flex;justify-content:space-between;align-items:center;color:var(--accent-dark);font-size:13px;font-weight:750;letter-spacing:.06em}.close{border:0;background:var(--accent-soft);color:var(--accent-dark);width:31px;height:31px;border-radius:50%;cursor:pointer;font-size:18px;line-height:1}.head{display:flex;align-items:center;gap:10px;margin:12px 0 2px;min-width:0}.word{font:700 29px/1.1 Georgia,serif;color:#342448;overflow-wrap:anywhere}.phonetic{color:#817987;font-size:14px}.speak{display:grid;place-items:center;flex:none;border:0;background:var(--accent-soft);color:var(--accent-dark);border-radius:11px;width:38px;height:38px;cursor:pointer}.speak svg,.secondary svg{width:20px;height:20px;fill:currentColor}.speak .wave,.secondary .wave{fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round}.meaning{font-size:18px;font-weight:700;margin:13px 0 4px}.context{background:color-mix(in srgb,var(--accent-soft) 70%,white);border-left:3px solid var(--accent);border-radius:0 11px 11px 0;padding:11px 13px;margin:13px 0;color:#4f3a69}.part{display:flex;gap:8px;margin:6px 0}.pos{flex:none;color:var(--accent-dark);font-weight:700;font-size:13px;padding-top:1px}.definition{color:#6f6875;font-size:14px;margin:9px 0}.example{margin:13px 0 4px;padding-top:12px;border-top:1px solid #eee8f3}.translation{color:#746d7b;margin-top:4px}.footer{display:flex;gap:9px;margin-top:16px}.primary,.secondary{border:0;border-radius:12px;padding:11px 14px;font-size:14px;font-weight:750;cursor:pointer}.primary{flex:1;background:linear-gradient(135deg,var(--accent),var(--accent-dark));color:white}.primary:disabled{opacity:.62}.secondary{display:flex;align-items:center;justify-content:center;gap:6px;background:var(--accent-soft);color:var(--accent-dark)}.loading{padding:32px 0;text-align:center;color:var(--accent-dark)}.dot{display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--accent);margin:0 3px;animation:pulse 1s infinite}.dot:nth-child(2){animation-delay:.15s}.dot:nth-child(3){animation-delay:.3s}.error{background:#fff1ed;color:#9a3f28;border-radius:12px;padding:12px;margin:13px 0}.hint{font-size:12px;color:#817987;margin-top:9px}.login{display:block;text-align:center;background:linear-gradient(135deg,var(--accent),var(--accent-dark));color:#fff;text-decoration:none;border:0;border-radius:12px;padding:11px;margin-top:13px;cursor:pointer;font-weight:700}.privacy{display:inline-flex;align-items:center;gap:5px;color:var(--accent-dark);font-weight:650}@keyframes in{from{opacity:0;transform:translateY(7px) scale(.98)}}@keyframes pulse{0%,100%{opacity:.25}50%{opacity:1}}@media(max-width:330px){.inner{padding:14px}.footer{flex-direction:column}.secondary{width:100%}}
    </style><div class="card" data-theme="${escapeHTML(preferences.theme)}"><div class="inner"><div class="brand"><span>词鲸背单词</span><button class="close" aria-label="关闭">×</button></div><div id="body"></div></div></div>`;
    document.documentElement.appendChild(host);
    const card = shadow.querySelector(".card");
    host.reposition = () => positionCard(card, rect);
    host.reposition();
    shadow.querySelector(".close").onclick = () => { stopPronunciation(); host.remove(); };
    return shadow;
  }

  function positionCard(card, rect) {
    requestAnimationFrame(() => {
      const margin = 8;
      const viewportWidth = Math.max(document.documentElement.clientWidth, window.innerWidth || 0);
      const viewportHeight = Math.max(document.documentElement.clientHeight, window.innerHeight || 0);
      const width = Math.min(380, Math.max(280, viewportWidth - margin * 2));
      card.style.width = `${width}px`;
      card.style.maxHeight = `${Math.max(180, viewportHeight - margin * 2)}px`;
      const height = Math.min(card.scrollHeight, Math.max(180, viewportHeight - margin * 2));
      const left = Math.min(viewportWidth - width - margin, Math.max(margin, rect.left + (rect.right - rect.left - width) / 2));
      const below = viewportHeight - rect.bottom - margin;
      const above = rect.top - margin;
      let top = below >= Math.min(height, 320) || below >= above ? rect.bottom + 8 : rect.top - height - 8;
      top = Math.min(viewportHeight - height - margin, Math.max(margin, top));
      card.style.left = `${Math.max(margin, left)}px`;
      card.style.top = `${Math.max(margin, top)}px`;
      card.style.bottom = "auto";
    });
  }

  function reposition(root) {
    root.host.reposition?.();
  }

  function showLoading(payload) {
    const root = shell(payload.rect);
    root.getElementById("body").innerHTML = `<div class="head"><span class="word">${escapeHTML(payload.word)}</span></div><div class="loading"><span class="dot"></span><span class="dot"></span><span class="dot"></span><div class="hint">正在理解当前语境…</div></div>`;
    reposition(root);
    return root;
  }

  function showError(root, word, message) {
    const auth = message === "AUTH_REQUIRED" || message.includes("AUTH_");
    root.getElementById("body").innerHTML = `<div class="head"><span class="word">${escapeHTML(word)}</span></div><div class="error">${auth ? "登录后即可查询并同步到 iOS App。" : escapeHTML(message || "查询失败，请稍后重试。")}</div>${auth ? '<button class="login" id="login">打开词鲸背单词并登录</button>' : '<button class="login" id="retry">重试</button>'}`;
    root.getElementById("login")?.addEventListener("click", () => {
      document.getElementById(HOST_ID)?.remove();
      chrome.runtime.sendMessage({ type: "OPEN_LOGIN" });
    });
    root.getElementById("retry")?.addEventListener("click", () => lookup(lastSelection));
    reposition(root);
  }

  function showResult(root, payload, result) {
    const data = result.data || result;
    const parts = (data.parts || []).map((item) => `<div class="part"><span class="pos">${escapeHTML(item.partOfSpeech)}</span><span>${escapeHTML(item.meaning)}</span></div>`).join("");
    const privacyHint = preferences.privacyMode
      ? '<span class="privacy">隐私模式 · 未使用网页上下文</span>'
      : preferences.saveContext ? "将同时保存当前句子和页面来源" : "仅保存单词与释义";
    root.getElementById("body").innerHTML = `
      <div class="head"><span class="word">${escapeHTML(data.term || payload.word)}</span><button class="speak" id="speak" aria-label="播放发音" title="播放发音">${volumeIcon()}</button></div>
      <div class="phonetic">/${escapeHTML(data.phonetic || "")}/ · ${escapeHTML(data.lemma || "")}</div>
      <div class="meaning">${escapeHTML(data.primaryMeaning)}</div>${parts}
      ${data.contextualMeaning ? `<div class="context"><strong>此处：</strong>${escapeHTML(data.contextualMeaning)}</div>` : ""}
      <div class="definition">${escapeHTML(data.englishDefinition)}</div>
      <div class="example"><div>${escapeHTML(data.exampleEnglish)}</div><div class="translation">${escapeHTML(data.exampleChinese)}</div></div>
      <div class="footer"><button class="secondary" id="slow">${volumeIcon()}<span>慢速</span></button><button class="primary" id="save">＋ 保存到词库</button></div>
      <div class="hint">${data.audioUrl ? "发音：公开词典真人录音 · " : "发音：Chrome 高质量英文语音 · "}${privacyHint}</div>`;

    const speakWithChrome = async (rate) => {
      speechSynthesis.cancel();
      const utterance = new SpeechSynthesisUtterance(data.term || payload.word);
      utterance.lang = "en-US";
      utterance.rate = rate;
      utterance.pitch = 1;
      utterance.volume = 1;
      const voice = await preferredEnglishVoice();
      if (voice) utterance.voice = voice;
      speechSynthesis.speak(utterance);
    };
    const speak = async (rate) => {
      speechSynthesis.cancel();
      if (!data.audioUrl) {
        speakWithChrome(rate);
        return;
      }
      const response = await chrome.runtime.sendMessage({ type: "PLAY_PRONUNCIATION", url: data.audioUrl, rate: rate < 0.9 ? 0.78 : 1 }).catch(() => null);
      if (!response?.ok) speakWithChrome(rate);
    };
    root.getElementById("speak").onclick = () => speak(0.96);
    root.getElementById("slow").onclick = () => speak(0.72);
    root.getElementById("save").onclick = () => saveWord(root, payload, data, false);
    reposition(root);
    if (preferences.autoSave) saveWord(root, payload, data, true);
  }

  async function saveWord(root, payload, data, automatic) {
    const button = root.getElementById("save");
    if (!button || button.disabled) return;
    button.disabled = true;
    button.textContent = automatic ? "正在自动保存…" : "正在保存…";
    const includeContext = preferences.saveContext && !preferences.privacyMode;
    const saved = await chrome.runtime.sendMessage({ type: "SAVE_WORD", payload: {
      term: data.term || payload.word,
      lemma: data.lemma || data.term || payload.word,
      phonetic: data.phonetic,
      audio_url: data.audioUrl || null,
      parts: data.parts || [],
      primary_meaning: data.primaryMeaning,
      contextual_meaning: data.contextualMeaning,
      english_definition: data.englishDefinition,
      example_en: data.exampleEnglish,
      example_zh: data.exampleChinese,
      context: includeContext ? payload.context : null,
      sentence: includeContext ? (data.sentence || payload.sentence) : null,
      source_url: includeContext ? payload.source_url : null,
      source_title: includeContext ? payload.source_title : null
    }});
    if (saved.ok) {
      button.textContent = automatic ? "✓ 已自动保存" : "✓ 已保存并同步";
      button.style.background = "var(--accent-dark)";
    } else {
      button.disabled = false;
      button.textContent = "保存失败，重试";
      button.title = saved.error;
    }
    reposition(root);
  }

  async function preferredEnglishVoice() {
    let voices = speechSynthesis.getVoices().filter((voice) => /^en(?:-|_)/i.test(voice.lang));
    if (!voices.length) {
      await new Promise((resolve) => {
        const timeout = setTimeout(resolve, 350);
        speechSynthesis.addEventListener("voiceschanged", () => { clearTimeout(timeout); resolve(); }, { once: true });
      });
      voices = speechSynthesis.getVoices().filter((voice) => /^en(?:-|_)/i.test(voice.lang));
    }
    const score = (voice) => {
      const label = `${voice.name} ${voice.voiceURI}`.toLowerCase();
      let value = /^en-US$/i.test(voice.lang) ? 80 : 25;
      if (/google us english|microsoft (aria|jenny|guy)|samantha|ava|allison|siri/.test(label)) value += 60;
      if (voice.localService) value += 14;
      if (/compact|novelty|whisper|zarvox|bells|bad news/.test(label)) value -= 100;
      return value;
    };
    return voices.sort((left, right) => score(right) - score(left))[0] || null;
  }

  function stopPronunciation() {
    speechSynthesis.cancel();
    chrome.runtime.sendMessage({ type: "STOP_PRONUNCIATION" }).catch(() => {});
  }

  async function loadPreferences() {
    const response = await chrome.runtime.sendMessage({ type: "GET_PREFERENCES" }).catch(() => null);
    if (response?.ok) preferences = { ...DEFAULT_PREFERENCES, ...response.data };
    return preferences;
  }

  async function lookup(payload) {
    if (!payload) return;
    await loadPreferences();
    if (preferences.disabledHosts.includes(currentHost)) return;
    lastSelection = payload;
    const serial = ++requestSerial;
    const requestPayload = preferences.privacyMode
      ? { ...payload, context: "", sentence: "", source_url: null, source_title: null }
      : payload;
    const root = showLoading(payload);
    const response = await chrome.runtime.sendMessage({ type: "LOOKUP_WORD", payload: requestPayload });
    if (serial !== requestSerial || !document.getElementById(HOST_ID)) return;
    if (!response?.ok) showError(root, payload.word, response?.error || "查询失败");
    else showResult(root, requestPayload, response.data);
  }

  document.addEventListener("dblclick", (event) => {
    if (event.target?.closest?.(`#${HOST_ID}`)) return;
    setTimeout(() => lookup(selectedPayload()), 0);
  }, true);
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") { stopPronunciation(); document.getElementById(HOST_ID)?.remove(); }
  });
  document.addEventListener("mousedown", (event) => {
    const host = document.getElementById(HOST_ID);
    if (host && event.target !== host && !host.contains(event.target)) { stopPronunciation(); host.remove(); }
  }, true);
  window.addEventListener("resize", () => document.getElementById(HOST_ID)?.reposition?.());
  chrome.runtime.onMessage.addListener((message) => {
    if (message.type === "LOOKUP_SELECTED") lookup(selectedPayload(message.word));
  });
  chrome.storage.onChanged.addListener((changes, areaName) => {
    if (areaName !== "local") return;
    if (changes.cijingSession?.newValue?.access_token) document.getElementById(HOST_ID)?.remove();
    if (changes.cijingPreferences?.newValue) {
      preferences = { ...DEFAULT_PREFERENCES, ...changes.cijingPreferences.newValue };
      const card = document.getElementById(HOST_ID)?.shadowRoot?.querySelector(".card");
      if (card) card.dataset.theme = preferences.theme;
      if (preferences.disabledHosts.includes(currentHost)) document.getElementById(HOST_ID)?.remove();
    }
  });
  loadPreferences();
})();

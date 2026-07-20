(() => {
  const HOST_ID = "cijing-reader-card-host";
  let lastSelection = null;
  let requestSerial = 0;

  const escapeHTML = (value = "") => String(value).replace(/[&<>'"]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);
  const cleanWord = (value = "") => value.trim().replace(/^[^A-Za-z'-]+|[^A-Za-z'-]+$/g, "");
  const validWord = (value) => /^[A-Za-z][A-Za-z'-]{0,60}$/.test(value);

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

  function shell(rect) {
    document.getElementById(HOST_ID)?.remove();
    const host = document.createElement("div");
    host.id = HOST_ID;
    host.style.cssText = "all:initial;position:fixed;z-index:2147483647;left:0;top:0";
    const shadow = host.attachShadow({ mode: "open" });
    shadow.innerHTML = `<style>
      :host{all:initial}.card{position:fixed;width:356px;max-height:min(560px,calc(100vh - 24px));overflow:auto;background:#fffdf8;color:#17201b;border:1px solid rgba(22,68,43,.14);border-radius:20px;box-shadow:0 22px 70px rgba(13,48,31,.24);font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;animation:in .16s ease-out}.inner{padding:18px}.brand{display:flex;justify-content:space-between;align-items:center;color:#46705a;font-size:12px;font-weight:700;letter-spacing:.08em}.close{border:0;background:#edf4ef;color:#365a47;width:27px;height:27px;border-radius:50%;cursor:pointer;font-size:16px}.head{display:flex;align-items:center;gap:9px;margin:12px 0 2px}.word{font:700 28px/1.1 Georgia,serif;color:#143f2a}.phonetic{color:#66756c}.speak{border:0;background:#dff3e6;color:#17653a;border-radius:10px;padding:7px 9px;cursor:pointer}.meaning{font-size:17px;font-weight:650;margin:12px 0 3px}.context{background:#f2f7f3;border-left:3px solid #4da774;border-radius:0 11px 11px 0;padding:10px 12px;margin:12px 0;color:#244c35}.part{display:flex;gap:8px;margin:5px 0}.pos{flex:none;color:#28734a;font-weight:700;font-size:12px;padding-top:2px}.definition{color:#647168;font-size:13px;margin:8px 0}.example{margin:12px 0 4px;padding-top:11px;border-top:1px solid #e8ece9}.translation{color:#67736b;margin-top:3px}.footer{display:flex;gap:9px;margin-top:15px}.primary,.secondary{border:0;border-radius:12px;padding:10px 14px;font-weight:700;cursor:pointer}.primary{flex:1;background:#175f3a;color:white}.primary:disabled{opacity:.55}.secondary{background:#eaf2ed;color:#315f46}.loading{padding:30px 0;text-align:center;color:#47715b}.dot{display:inline-block;width:8px;height:8px;border-radius:50%;background:#2b8b58;margin:0 3px;animation:pulse 1s infinite}.dot:nth-child(2){animation-delay:.15s}.dot:nth-child(3){animation-delay:.3s}.error{background:#fff1ed;color:#9a3f28;border-radius:12px;padding:12px;margin:13px 0}.hint{font-size:12px;color:#78827c;margin-top:8px}.login{display:block;text-align:center;background:#175f3a;color:#fff;text-decoration:none;border-radius:12px;padding:10px;margin-top:13px;cursor:pointer}@keyframes in{from{opacity:0;transform:translateY(7px) scale(.98)}}@keyframes pulse{0%,100%{opacity:.25}50%{opacity:1}}
    </style><div class="card"><div class="inner"><div class="brand"><span>词鲸背单词</span><button class="close" aria-label="关闭">×</button></div><div id="body"></div></div></div>`;
    document.documentElement.appendChild(host);
    const card = shadow.querySelector(".card");
    const width = 356;
    const left = Math.min(window.innerWidth - width - 12, Math.max(12, rect.left + (rect.right - rect.left) / 2 - width / 2));
    const preferBelow = rect.bottom + 580 < window.innerHeight || rect.top < 300;
    card.style.left = `${left}px`;
    card.style.top = preferBelow ? `${Math.min(window.innerHeight - 100, rect.bottom + 10)}px` : "auto";
    if (!preferBelow) card.style.bottom = `${Math.max(12, window.innerHeight - rect.top + 10)}px`;
    shadow.querySelector(".close").onclick = () => host.remove();
    return shadow;
  }

  function showLoading(payload) {
    const root = shell(payload.rect);
    root.getElementById("body").innerHTML = `<div class="head"><span class="word">${escapeHTML(payload.word)}</span></div><div class="loading"><span class="dot"></span><span class="dot"></span><span class="dot"></span><div class="hint">正在理解当前语境…</div></div>`;
    return root;
  }

  function showError(root, word, message) {
    const auth = message === "AUTH_REQUIRED" || message.includes("AUTH_");
    root.getElementById("body").innerHTML = `<div class="head"><span class="word">${escapeHTML(word)}</span></div><div class="error">${auth ? "登录后即可查询并同步到 iOS App。" : escapeHTML(message || "查询失败，请稍后重试。")}</div>${auth ? '<a class="login" id="login">打开词鲸背单词并登录</a>' : '<button class="login" id="retry">重试</button>'}`;
    root.getElementById("login")?.addEventListener("click", () => chrome.runtime.sendMessage({ type: "OPEN_LOGIN" }));
    root.getElementById("retry")?.addEventListener("click", () => lookup(lastSelection));
  }

  function showResult(root, payload, result) {
    const data = result.data || result;
    const parts = (data.parts || []).map((item) => `<div class="part"><span class="pos">${escapeHTML(item.partOfSpeech)}</span><span>${escapeHTML(item.meaning)}</span></div>`).join("");
    root.getElementById("body").innerHTML = `
      <div class="head"><span class="word">${escapeHTML(data.term || payload.word)}</span><button class="speak" id="speak" title="美音发音">▶︎</button></div>
      <div class="phonetic">/${escapeHTML(data.phonetic || "")}/ · ${escapeHTML(data.lemma || "")}</div>
      <div class="meaning">${escapeHTML(data.primaryMeaning)}</div>${parts}
      <div class="context"><strong>此处：</strong>${escapeHTML(data.contextualMeaning)}</div>
      <div class="definition">${escapeHTML(data.englishDefinition)}</div>
      <div class="example"><div>${escapeHTML(data.exampleEnglish)}</div><div class="translation">${escapeHTML(data.exampleChinese)}</div></div>
      <div class="footer"><button class="secondary" id="slow">慢速发音</button><button class="primary" id="save">＋ 保存到词库</button></div>
      <div class="hint">将同时保存当前句子和页面来源</div>`;
    const speak = (rate) => {
      speechSynthesis.cancel();
      const utterance = new SpeechSynthesisUtterance(data.term || payload.word);
      utterance.lang = "en-US"; utterance.rate = rate;
      const voice = speechSynthesis.getVoices().find((item) => item.lang === "en-US");
      if (voice) utterance.voice = voice;
      speechSynthesis.speak(utterance);
    };
    root.getElementById("speak").onclick = () => speak(0.92);
    root.getElementById("slow").onclick = () => speak(0.68);
    root.getElementById("save").onclick = async (event) => {
      const button = event.currentTarget;
      button.disabled = true; button.textContent = "正在保存…";
      const saved = await chrome.runtime.sendMessage({ type: "SAVE_WORD", payload: {
        term: data.term || payload.word, lemma: data.lemma || data.term || payload.word, phonetic: data.phonetic,
        parts: data.parts || [], primary_meaning: data.primaryMeaning, contextual_meaning: data.contextualMeaning,
        english_definition: data.englishDefinition, example_en: data.exampleEnglish, example_zh: data.exampleChinese,
        context: payload.context, sentence: data.sentence || payload.sentence, source_url: payload.source_url, source_title: payload.source_title
      }});
      if (saved.ok) { button.textContent = "✓ 已保存并同步"; button.style.background = "#47715b"; }
      else { button.disabled = false; button.textContent = "保存失败，重试"; button.title = saved.error; }
    };
  }

  async function lookup(payload) {
    if (!payload) return;
    lastSelection = payload;
    const serial = ++requestSerial;
    const root = showLoading(payload);
    const response = await chrome.runtime.sendMessage({ type: "LOOKUP_WORD", payload });
    if (serial !== requestSerial || !document.getElementById(HOST_ID)) return;
    if (!response?.ok) showError(root, payload.word, response?.error);
    else showResult(root, payload, response.data);
  }

  document.addEventListener("dblclick", (event) => {
    if (event.target?.closest?.(`#${HOST_ID}`)) return;
    setTimeout(() => lookup(selectedPayload()), 0);
  }, true);
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") document.getElementById(HOST_ID)?.remove();
  });
  document.addEventListener("mousedown", (event) => {
    const host = document.getElementById(HOST_ID);
    if (host && event.target !== host && !host.contains(event.target)) host.remove();
  }, true);
  chrome.runtime.onMessage.addListener((message) => {
    if (message.type === "LOOKUP_SELECTED") lookup(selectedPayload(message.word));
  });
})();

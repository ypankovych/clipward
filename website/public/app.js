// Clipward website: a working imitation of the app's history popup, plus the small bits
// of page behaviour (clock, feature tabs, latest-release links). Nothing here reads or
// writes the visitor's real clipboard; the demo keeps its own in-memory history.
(() => {
  "use strict";

  const REPO = "ypankovych/clipward";
  const DEMO_CLEAR_SECONDS = 20; // the app's default is 60; shortened so visitors see it happen

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));

  // ---------- Icons (simplified SF Symbols) ----------

  const ICONS = {
    text: '<svg viewBox="0 0 20 20"><path d="M3 5h14M3 9h14M3 13h14M3 17h9" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
    link: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M8.5 11.5a3.5 3.5 0 0 0 5 0l2.5-2.5a3.5 3.5 0 0 0-5-5l-1 1"/><path d="M11.5 8.5a3.5 3.5 0 0 0-5 0L4 11a3.5 3.5 0 0 0 5 5l1-1"/></svg>',
    file: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><path d="M5 2.5h6.5L15 6v11.5H5z"/><path d="M11.5 2.5V6H15"/></svg>',
    rich: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><rect x="3" y="2.5" width="14" height="15" rx="2"/><path d="M6 6.5h8M6 9.5h8M6 12.5h4"/></svg>',
  };

  const iconFor = (item) => {
    if (item.kind === "color") return `<span class="swatch" style="--c:${item.value}"></span>`;
    if (item.kind === "image") return '<span class="thumb"></span>';
    return ICONS[item.kind] || ICONS.text;
  };

  // ---------- History ----------

  let nextId = 1;
  const minutesAgo = (m) => Date.now() - m * 60_000;
  const history = [
    { kind: "text", title: "Let's ship 1.0 on Thursday once QA signs off", app: "Slack", at: minutesAgo(1) },
    { kind: "link", title: "https://github.com/ypankovych/clipward", app: "Safari", at: minutesAgo(6) },
    { kind: "file", title: "Quarterly Report.pdf", app: "Finder", at: minutesAgo(64) },
    { kind: "rich", title: "Meeting notes: hiring plan, Q3 budget, offsite dates", app: "Notes", at: minutesAgo(180) },
  ].map((item) => ({ ...item, id: nextId++, value: item.title }));

  function record(item) {
    const existing = history.findIndex((h) => h.kind === item.kind && h.value === item.value);
    if (existing >= 0) history.splice(existing, 1); // same content moves to the top
    history.unshift({ ...item, id: nextId++, at: Date.now() });
    if (panelOpen()) render();
  }

  function timeAgo(at) {
    const s = Math.max(0, (Date.now() - at) / 1000);
    if (s < 60) return "now";
    if (s < 3600) return `${Math.floor(s / 60)}m ago`;
    if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
    return `${Math.floor(s / 86400)}d ago`;
  }

  // ---------- Panel ----------

  const panel = $("#clipPanel");
  const search = $("#clipSearch");
  const list = $("#clipList");
  const empty = $("#clipEmpty");
  const statusItem = $("#statusItem");
  let visible = [];
  let selected = 0;
  let returnFocus = null;

  const panelOpen = () => !panel.hidden;

  function filtered() {
    const words = search.value.toLowerCase().split(/\s+/).filter(Boolean);
    return history.filter((h) => words.every((w) => `${h.title} ${h.app}`.toLowerCase().includes(w)));
  }

  function render() {
    visible = filtered();
    selected = Math.min(selected, Math.max(visible.length - 1, 0));
    list.innerHTML = visible.map((item, i) => `
      <li class="clip-row" role="option" id="clip-${item.id}" data-index="${i}" aria-selected="${i === selected}">
        <span class="clip-icon" aria-hidden="true">${iconFor(item)}</span>
        <span class="clip-text">
          <span class="clip-title">${escapeHTML(item.title)}</span>
          <span class="clip-sub">${escapeHTML(item.app)} · ${timeAgo(item.at)}</span>
        </span>
        <span class="clip-key" aria-hidden="true">${i < 9 ? `⌘${i + 1}` : ""}</span>
      </li>`).join("");
    empty.hidden = visible.length > 0;
    empty.textContent = history.length ? "No matches" : "Copied items will appear here";
    syncSelection();
  }

  function syncSelection() {
    $$(".clip-row", list).forEach((row, i) => row.setAttribute("aria-selected", String(i === selected)));
    const row = list.children[selected];
    if (row) {
      search.setAttribute("aria-activedescendant", row.id);
      row.scrollIntoView({ block: "nearest" });
    } else {
      search.removeAttribute("aria-activedescendant");
    }
  }

  function openPanel() {
    returnFocus = document.activeElement;
    search.value = "";
    selected = 0;
    panel.hidden = false;
    statusItem.setAttribute("aria-expanded", "true");
    render();
    search.focus({ preventScroll: true });
  }

  function closePanel() {
    if (!panelOpen()) return;
    panel.hidden = true;
    statusItem.setAttribute("aria-expanded", "false");
    if (returnFocus && document.contains(returnFocus)) returnFocus.focus({ preventScroll: true });
  }

  const togglePanel = () => (panelOpen() ? closePanel() : openPanel());

  function move(delta) {
    if (!visible.length) return;
    selected = Math.min(Math.max(selected + delta, 0), visible.length - 1);
    syncSelection();
  }

  function choose(index, plainText) {
    const item = visible[index];
    if (!item) return;
    closePanel();
    paste(item, plainText);
    item.at = Date.now(); // pasting moves it to the top, like the app
    history.splice(history.indexOf(item), 1);
    history.unshift(item);
    startClearCountdown();
  }

  function remove(index) {
    const item = visible[index];
    if (!item) return;
    history.splice(history.indexOf(item), 1);
    render();
  }

  search.addEventListener("input", () => { selected = 0; render(); });

  panel.addEventListener("keydown", (e) => {
    const cmd = e.metaKey || e.ctrlKey;
    if (e.key === "ArrowDown") move(1);
    else if (e.key === "ArrowUp") move(-1);
    else if (e.key === "PageDown") move(8);
    else if (e.key === "PageUp") move(-8);
    else if (e.key === "Enter") choose(selected, e.shiftKey);
    else if (e.key === "Escape") {
      if (search.value) { search.value = ""; render(); } else closePanel();
    } else if (cmd && e.key === "Backspace") remove(selected);
    else if (cmd && /^Digit[1-9]$/.test(e.code)) choose(Number(e.code.slice(5)) - 1, e.shiftKey);
    else return;
    e.preventDefault();
  });

  list.addEventListener("click", (e) => {
    const row = e.target.closest(".clip-row");
    if (row) choose(Number(row.dataset.index), e.shiftKey);
  });
  list.addEventListener("mousemove", (e) => {
    const row = e.target.closest(".clip-row");
    if (row && Number(row.dataset.index) !== selected) { selected = Number(row.dataset.index); syncSelection(); }
  });

  // Close when clicking anywhere outside, like the app's panel losing focus.
  document.addEventListener("mousedown", (e) => {
    if (panelOpen() && !panel.contains(e.target) && !statusItem.contains(e.target)) closePanel();
  });

  statusItem.addEventListener("click", togglePanel);
  $("#openHistory").addEventListener("click", openPanel);

  // ⌥⌘C on a Mac, ⌥⌃C elsewhere. `code` keeps it working in any keyboard layout, as the app does.
  document.addEventListener("keydown", (e) => {
    if (e.altKey && (e.metaKey || e.ctrlKey) && e.code === "KeyC") {
      e.preventDefault();
      togglePanel();
    }
  });

  // ---------- Copying ----------

  $$(".copy").forEach((button) => {
    button.addEventListener("click", () => {
      const { kind, app, value } = button.dataset;
      if (kind === "concealed") {
        notify("Password skipped", "Passwords marked it as concealed, so Clipward didn't record it.");
      } else {
        record({ kind, app, value, title: value });
      }
      button.textContent = "Copied";
      button.classList.add("done");
      setTimeout(() => { button.textContent = "Copy"; button.classList.remove("done"); }, 1200);
    });
  });

  // Text the visitor copies anywhere on the page (⌘C) also lands in the demo history.
  document.addEventListener("copy", (e) => {
    if (panel.contains(e.target)) return;
    const text = String(window.getSelection() || "").trim();
    if (!text) return;
    const kind = /^https?:\/\/\S+$/.test(text) ? "link" : "text";
    record({ kind, app: "Safari", value: text, title: text.replace(/\s+/g, " ").slice(0, 300) });
  });

  // ---------- Pasting into the scratchpad ----------

  const pasteArea = $("#pasteArea");

  function paste(item, plainText) {
    $(".paste-empty", pasteArea)?.remove();
    const line = document.createElement("p");
    const kind = plainText && item.kind !== "image" ? "text" : item.kind;
    line.className = `pasted ${kind} flash`;
    if (kind === "color") line.innerHTML = `<span class="swatch" style="--c:${item.value}"></span>${escapeHTML(item.value)}`;
    else if (kind === "image") line.innerHTML = '<span class="thumb"></span>';
    else line.textContent = item.value;
    pasteArea.append(line);
    pasteArea.scrollTop = pasteArea.scrollHeight;
  }

  // ---------- Auto-clear countdown ----------

  const timerLabel = $("#clearTimer");
  let clearTimer = null;

  function startClearCountdown() {
    clearInterval(clearTimer);
    let remaining = DEMO_CLEAR_SECONDS;
    const tick = () => {
      timerLabel.hidden = false;
      timerLabel.textContent = `Clears in ${remaining}s`;
      if (remaining-- <= 0) {
        clearInterval(clearTimer);
        timerLabel.hidden = true;
        notify("Clipboard cleared", `The pasted item was removed after ${DEMO_CLEAR_SECONDS} seconds. In the app the default is 1 minute.`);
      }
    };
    tick();
    clearTimer = setInterval(tick, 1000);
  }

  // ---------- Notification banner ----------

  const note = $("#notification");
  let noteTimer = null;

  function notify(title, body) {
    $("#notificationTitle").textContent = title;
    $("#notificationBody").textContent = body;
    note.hidden = false;
    clearTimeout(noteTimer);
    noteTimer = setTimeout(() => { note.hidden = true; }, 5000);
  }

  // ---------- Menu bar clock ----------

  const clock = $("#clock");
  const clockFormat = new Intl.DateTimeFormat(undefined, { weekday: "short", day: "numeric", month: "short", hour: "numeric", minute: "2-digit" });
  const updateClock = () => { clock.textContent = clockFormat.format(new Date()).replace(/,/g, ""); };
  updateClock();
  setInterval(updateClock, 15_000);

  // ---------- Feature tabs ----------

  const tabs = $$('.sidebar [role="tab"]');
  function selectTab(tab, focus) {
    tabs.forEach((t) => {
      const on = t === tab;
      t.setAttribute("aria-selected", String(on));
      t.tabIndex = on ? 0 : -1;
      $(`#${t.getAttribute("aria-controls")}`).hidden = !on;
    });
    if (focus) tab.focus();
  }
  tabs.forEach((tab, i) => {
    tab.addEventListener("click", () => selectTab(tab, false));
    tab.addEventListener("keydown", (e) => {
      const step = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 }[e.key];
      if (!step) return;
      e.preventDefault();
      selectTab(tabs[(i + step + tabs.length) % tabs.length], true);
    });
  });

  // ---------- Latest release links ----------

  fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { headers: { Accept: "application/vnd.github+json" } })
    .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
    .then((release) => {
      const dmg = (release.assets || []).find((a) => a.name.endsWith(".dmg"));
      if (!dmg) return;
      ["#downloadHero", "#downloadFile", "#downloadStep", "#downloadBottom"].forEach((id) => { $(id).href = dmg.browser_download_url; });
      $("#dmgName").textContent = dmg.name;
      $("#versionLabel").textContent = `Version ${release.tag_name.replace(/^v/, "")}`;
    })
    .catch(() => { /* links already point at the releases page */ });

  // On touch devices there is no ⌥⌘C, so the intro points at the button instead.
  if (window.matchMedia("(hover: none)").matches) {
    $(".scratch-intro").textContent = "Copy a few things, then tap Open history to bring them back.";
  }

  function escapeHTML(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }
})();

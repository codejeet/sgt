const COMPACT_KEY = "sgt_web_compact";

const appState = {
  ws: null,
  wsAttempts: 0,
  wsReconnectTimer: null,
  cockpit: emptyCockpit(),
  rigs: [],
  lastSnapshotAt: 0,
  lastLogAt: 0,
  focusTarget: "mayor",
  streamFilters: { rig: "all", role: "polecat", query: "" },
  streamFollowAll: true,
  desiredTargets: new Set(),
  streams: new Map(),
  sections: ["overview", "streams", "topology", "dispatch", "logs"],
  topology: {
    renderer: "canvas",
    modeLabel: "Canvas fallback",
    layout: new Map(),
    hoveredId: "",
    selectedId: "",
    gl: null,
    program: null,
    buffers: null,
  },
};

const refs = {
  wsHealth: document.getElementById("wsHealth"),
  connLabel: document.getElementById("connLabel"),
  lastUpdated: document.getElementById("lastUpdated"),
  lastLog: document.getElementById("lastLog"),
  compactBtn: document.getElementById("compactBtn"),
  refreshSnapshotBtn: document.getElementById("refreshSnapshotBtn"),
  navButtons: Array.from(document.querySelectorAll(".nav-btn")),
  sections: new Map(Array.from(document.querySelectorAll(".section")).map((el) => [el.id.replace("section-", ""), el])),
  commandMetrics: document.getElementById("commandMetrics"),
  workerRoster: document.getElementById("workerRoster"),
  workerCountLabel: document.getElementById("workerCountLabel"),
  rigCountLabel: document.getElementById("rigCountLabel"),
  rigMatrix: document.getElementById("rigMatrix"),
  blockerSummary: document.getElementById("blockerSummary"),
  blockerBoard: document.getElementById("blockerBoard"),
  overviewHero: document.getElementById("overviewHero"),
  queueBoard: document.getElementById("queueBoard"),
  streamSummary: document.getElementById("streamSummary"),
  streamRigFilter: document.getElementById("streamRigFilter"),
  streamRoleFilter: document.getElementById("streamRoleFilter"),
  streamQuery: document.getElementById("streamQuery"),
  followAllBtn: document.getElementById("followAllBtn"),
  monitorWallSummary: document.getElementById("monitorWallSummary"),
  focusStream: document.getElementById("focusStream"),
  mayorMonitor: document.getElementById("mayorMonitor"),
  monitorWall: document.getElementById("monitorWall"),
  serverTimeLabel: document.getElementById("serverTimeLabel"),
  topologyMode: document.getElementById("topologyMode"),
  topologyCanvas: document.getElementById("topologyCanvas"),
  topologySummary: document.getElementById("topologySummary"),
  topologyList: document.getElementById("topologyList"),
  logSummary: document.getElementById("logSummary"),
  logViewer: document.getElementById("logViewer"),
  refreshLogsBtn: document.getElementById("refreshLogsBtn"),
  slingForm: document.getElementById("slingForm"),
  dogForm: document.getElementById("dogForm"),
  slingRig: document.getElementById("slingRig"),
  dogRig: document.getElementById("dogRig"),
  slingBtn: document.getElementById("slingBtn"),
  dogBtn: document.getElementById("dogBtn"),
  peekModal: document.getElementById("peekModal"),
  peekTitle: document.getElementById("peekTitle"),
  peekOutput: document.getElementById("peekOutput"),
  peekCloseBtn: document.getElementById("peekCloseBtn"),
  toasts: document.getElementById("toasts"),
};

initialize();

function initialize() {
  setCompact(localStorage.getItem(COMPACT_KEY) === "1");
  bindEvents();
  setupTopologyCanvas();
  loadRigs();
  loadLogs();
  connectWs();
  setInterval(updateClocks, 1000);
}

function bindEvents() {
  refs.compactBtn.addEventListener("click", () => setCompact(!document.body.classList.contains("compact")));
  refs.refreshSnapshotBtn.addEventListener("click", requestSnapshot);
  refs.refreshLogsBtn.addEventListener("click", loadLogs);
  refs.peekCloseBtn.addEventListener("click", closePeek);
  refs.streamRigFilter.addEventListener("change", handleStreamFilterChange);
  refs.streamRoleFilter.addEventListener("change", handleStreamFilterChange);
  refs.streamQuery.addEventListener("input", handleStreamFilterChange);
  refs.followAllBtn.addEventListener("click", toggleFollowAll);
  refs.peekModal.addEventListener("click", (event) => {
    if (event.target === refs.peekModal) closePeek();
  });

  refs.navButtons.forEach((button) => {
    button.addEventListener("click", () => activateSection(button.dataset.section));
  });

  refs.slingForm.addEventListener("submit", handleSlingSubmit);
  refs.dogForm.addEventListener("submit", handleDogSubmit);

  document.addEventListener("keydown", (event) => {
    const target = event.target;
    if (target && ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName)) return;

    const shortcutMap = {
      "1": "overview",
      "2": "streams",
      "3": "topology",
      "4": "dispatch",
      "5": "logs",
    };

    if (shortcutMap[event.key]) {
      activateSection(shortcutMap[event.key]);
      return;
    }

    if (event.key === "c" || event.key === "C") {
      setCompact(!document.body.classList.contains("compact"));
      return;
    }

    if (event.key === "Escape") {
      closePeek();
    }
  });

  window.addEventListener("resize", renderTopology);
  refs.topologyCanvas.addEventListener("mousemove", handleTopologyPointerMove);
  refs.topologyCanvas.addEventListener("mouseleave", () => updateTopologyHover(""));
  refs.topologyCanvas.addEventListener("click", handleTopologyClick);
}

function emptyCockpit() {
  return {
    meta: { serverTime: "", featureFlags: {} },
    agents: [],
    rigs: [],
    workers: [],
    queue: { items: [], summary: { total: 0 } },
    blockers: [],
    logs: { lines: [], total: 0 },
    topology: { nodes: [], edges: [] },
  };
}

function setCompact(on) {
  document.body.classList.toggle("compact", Boolean(on));
  localStorage.setItem(COMPACT_KEY, on ? "1" : "0");
}

function activateSection(name) {
  refs.navButtons.forEach((button) => button.classList.toggle("active", button.dataset.section === name));
  refs.sections.forEach((section, key) => section.classList.toggle("active", key === name));
  const active = refs.sections.get(name);
  if (active) active.scrollIntoView({ behavior: "smooth", block: "start" });
}

function wsUrl() {
  const proto = location.protocol === "https:" ? "wss:" : "ws:";
  return `${proto}//${location.host}`;
}

function connectWs() {
  clearTimeout(appState.wsReconnectTimer);

  try {
    appState.ws = new WebSocket(wsUrl());
  } catch {
    scheduleReconnect();
    return;
  }

  appState.ws.onopen = () => {
    appState.wsAttempts = 0;
    setConnectionState(true);
    requestSnapshot();
  };

  appState.ws.onclose = () => {
    setConnectionState(false);
    scheduleReconnect();
  };

  appState.ws.onerror = () => {
    try {
      appState.ws.close();
    } catch {}
  };

  appState.ws.onmessage = (event) => {
    const message = JSON.parse(event.data);
    handleWsMessage(message);
  };
}

function scheduleReconnect() {
  appState.wsAttempts += 1;
  const base = Math.min(30000, 600 * Math.pow(2, Math.min(appState.wsAttempts, 8)));
  const jitter = 0.55 + Math.random() * 0.7;
  appState.wsReconnectTimer = setTimeout(connectWs, Math.round(base * jitter));
}

function setConnectionState(connected) {
  refs.wsHealth.classList.toggle("connected", connected);
  refs.connLabel.textContent = connected ? "Connected" : "Disconnected";
}

function requestSnapshot() {
  if (!appState.ws || appState.ws.readyState !== WebSocket.OPEN) return;
  appState.ws.send(JSON.stringify({ type: "snapshot/request" }));
}

function handleWsMessage(message) {
  if (message.type === "snapshot" && message.snapshot) {
    appState.cockpit = message.snapshot;
    appState.lastSnapshotAt = Date.now();
    if (!appState.focusTarget || !hasTarget(appState.focusTarget)) {
      appState.focusTarget = preferredFocusTarget();
    }
    syncStreamTargets();
    renderAll();
    return;
  }

  if (message.type === "log" && Array.isArray(message.lines)) {
    appState.lastLogAt = Date.now();
    const lines = message.lines.filter(Boolean);
    if (lines.length > 0) {
      appState.cockpit.logs.lines = [...appState.cockpit.logs.lines, ...lines].slice(-400);
      appState.cockpit.logs.total = appState.cockpit.logs.lines.length;
      appendLogLines(lines);
      refs.logSummary.textContent = `${appState.cockpit.logs.total} lines buffered`;
    }
    return;
  }

  if (message.type === "log_reset") {
    appState.cockpit.logs.lines = [];
    refs.logViewer.innerHTML = "";
    loadLogs();
    return;
  }

  if (message.type && message.type.startsWith("stream/")) {
    handleStreamEvent(message);
  }
}

function handleStreamEvent(message) {
  const target = message.target;
  if (!target) return;
  const existing = appState.streams.get(target) || {
    target,
    content: "",
    state: "opening",
    follow: appState.streamFollowAll,
    lastEventAt: 0,
    session: "",
  };

  if (message.type === "stream/open") {
    existing.state = "live";
    existing.session = message.session || "";
    existing.lastEventAt = Date.now();
  } else if (message.type === "stream/data") {
    existing.state = "live";
    existing.session = message.session || existing.session;
    existing.lastEventAt = Date.now();
    existing.content = message.reset ? message.chunk : `${existing.content}${message.chunk}`;
  } else if (message.type === "stream/stale") {
    existing.state = "stale";
    existing.reason = message.reason || "session-unavailable";
    existing.lastEventAt = Date.now();
  } else if (message.type === "stream/close") {
    existing.state = "closed";
    existing.reason = message.reason || "unsubscribed";
    existing.lastEventAt = Date.now();
  }

  appState.streams.set(target, existing);
  renderStreamDeck();
}

function preferredFocusTarget() {
  const liveWorker = monitorWorkers()[0];
  return liveWorker ? liveWorker.stream.target : "mayor";
}

function syncStreamTargets() {
  const desired = new Set(["mayor"]);
  const workers = monitorWorkers().filter(matchesStreamFilters);

  if (appState.focusTarget) desired.add(appState.focusTarget);
  for (const worker of workers) desired.add(worker.stream.target);

  const previous = appState.desiredTargets;
  appState.desiredTargets = desired;

  for (const target of desired) {
    if (!previous.has(target)) sendWs({ type: "stream/subscribe", target });
  }
  for (const target of previous) {
    if (!desired.has(target)) sendWs({ type: "stream/unsubscribe", target });
  }
}

function sendWs(payload) {
  if (!appState.ws || appState.ws.readyState !== WebSocket.OPEN) return;
  appState.ws.send(JSON.stringify(payload));
}

function hasTarget(target) {
  if (target === "mayor") return true;
  return appState.cockpit.workers.some((worker) => worker.stream && worker.stream.target === target);
}

function renderAll() {
  refs.lastUpdated.textContent = timeLabel(appState.lastSnapshotAt);
  refs.lastLog.textContent = timeLabel(appState.lastLogAt);
  refs.serverTimeLabel.textContent = appState.cockpit.meta.serverTime ? formatIso(appState.cockpit.meta.serverTime) : "waiting";
  renderMetrics();
  renderRoster();
  renderRigs();
  renderBlockers();
  renderQueue();
  renderStreamDeck();
  renderLogs();
  renderTopology();
}

function renderMetrics() {
  const agentsOnline = appState.cockpit.agents.filter((agent) => String(agent.status).startsWith("on")).length;
  const liveWorkers = appState.cockpit.workers.filter((worker) => worker.status === "alive").length;
  const blockedRigs = appState.cockpit.rigs.filter((rig) => rig.blockers > 0).length;
  const staleStreams = Array.from(appState.streams.values()).filter((stream) => stream.state === "stale").length;

  const metrics = [
    {
      label: "Agents Online",
      value: `${agentsOnline}/${appState.cockpit.agents.length || 0}`,
      detail: "Daemon, Mayor, witness, refinery, and support process health.",
    },
    {
      label: "Live Workers",
      value: `${liveWorkers}`,
      detail: `${appState.cockpit.workers.length} tracked workers with issue and branch context.`,
    },
    {
      label: "Open Blockers",
      value: `${appState.cockpit.blockers.length}`,
      detail: blockedRigs ? `${blockedRigs} rigs are acceptance-blocked.` : "No rigs are blocked right now.",
    },
    {
      label: "Queue Pressure",
      value: `${appState.cockpit.queue.summary.total || 0}`,
      detail: staleStreams ? `${staleStreams} subscribed streams are stale.` : "All subscribed streams are fresh.",
    },
  ];

  refs.commandMetrics.innerHTML = metrics.map((metric) => `
    <div class="metric-card">
      <div class="eyebrow">${esc(metric.label)}</div>
      <strong>${esc(metric.value)}</strong>
      <div class="metric-detail">${esc(metric.detail)}</div>
    </div>
  `).join("");
}

function renderRoster() {
  refs.workerCountLabel.textContent = `${appState.cockpit.workers.length} tracked`;

  if (appState.cockpit.workers.length === 0) {
    refs.workerRoster.innerHTML = "";
    return;
  }

  const workers = [...appState.cockpit.workers].sort((left, right) => workerPriority(right) - workerPriority(left));
  refs.workerRoster.innerHTML = workers.map((worker) => {
    const target = worker.stream ? worker.stream.target : worker.name;
    const stateClass = workerStateClass(worker);
    const focusLabel = appState.focusTarget === target ? "Focused" : "Focus";
    return `
      <article class="roster-item">
        <div class="roster-head">
          <div class="roster-title">${esc(worker.name)}</div>
          <span class="state-pill ${stateClass}">${esc(worker.status || "unknown")}</span>
        </div>
        <div class="roster-meta">
          <span>${esc(worker.role)}</span>
          ${worker.rig ? `<span>${esc(worker.rig)}</span>` : ""}
          ${worker.issue ? `<span>#${esc(worker.issue)}</span>` : ""}
          ${worker.branch ? `<span>${esc(worker.branch)}</span>` : ""}
        </div>
        <div class="roster-actions">
          <button class="btn tiny ghost" data-focus-target="${escAttr(target)}">${focusLabel}</button>
          <button class="btn tiny ghost" data-peek-target="${escAttr(target)}">Peek</button>
        </div>
      </article>
    `;
  }).join("");

  refs.workerRoster.querySelectorAll("[data-focus-target]").forEach((button) => {
    button.addEventListener("click", () => {
      appState.focusTarget = button.dataset.focusTarget;
      syncStreamTargets();
      renderStreamDeck();
      activateSection("streams");
    });
  });

  refs.workerRoster.querySelectorAll("[data-peek-target]").forEach((button) => {
    button.addEventListener("click", () => peek(button.dataset.peekTarget));
  });
}

function renderRigs() {
  refs.rigCountLabel.textContent = `${appState.cockpit.rigs.length} rigs`;
  refs.rigMatrix.innerHTML = appState.cockpit.rigs.map((rig) => `
    <article class="rig-item">
      <div class="rig-head">
        <div class="rig-name">${esc(rig.name)}</div>
        <span class="state-pill ${rigStateClass(rig)}">${esc(rig.state || "unknown")}</span>
      </div>
      <div class="rig-meta">
        <span>${rig.activeWorkers || 0} workers</span>
        <span>${rig.blockers || 0} blockers</span>
        <span>${rig.mergeQueue || 0} queue</span>
      </div>
      <div class="subtle">${esc(rig.reason || "No mayor detail available.")}</div>
    </article>
  `).join("");
}

function renderBlockers() {
  refs.blockerSummary.textContent = `${appState.cockpit.blockers.length} open blockers`;
  if (appState.cockpit.blockers.length === 0) {
    refs.blockerBoard.innerHTML = `<div class="empty-state">Acceptance blockers will surface here with evidence and rig ownership.</div>`;
    return;
  }

  refs.blockerBoard.innerHTML = appState.cockpit.blockers.map((blocker) => `
    <article class="blocker-card">
      <div class="queue-head">
        <div class="blocker-title">${esc(blocker.title)}</div>
        <span class="state-pill state-blocked">${esc(blocker.status)}</span>
      </div>
      <div class="blocker-meta">
        <span>${esc(blocker.rig || "unknown rig")}</span>
        <span>${esc(blocker.requester || "unknown reporter")}</span>
        <span>${esc(formatIso(blocker.createdAt))}</span>
      </div>
      <p>${esc(snippet(blocker.evidence || "No evidence body recorded.", 240))}</p>
    </article>
  `).join("");
}

function renderQueue() {
  const items = appState.cockpit.queue.items || [];
  if (items.length === 0) {
    refs.queueBoard.innerHTML = `<div class="empty-state">Merge queue is clear.</div>`;
    return;
  }

  refs.queueBoard.innerHTML = items.map((item) => `
    <article class="queue-item">
      <div class="queue-head">
        <div class="queue-name">${esc(item.name || "queue-item")}</div>
        <span class="state-pill state-active">queued</span>
      </div>
      <div class="queue-meta">
        <span>${esc(item.detail || "No detail")}</span>
      </div>
    </article>
  `).join("");
}

function renderStreamDeck() {
  renderStreamFilters();
  const orderedTargets = Array.from(appState.desiredTargets);
  refs.streamSummary.textContent = `${orderedTargets.length} subscriptions`;
  refs.overviewHero.innerHTML = renderHeroStream("mayor");
  refs.focusStream.innerHTML = renderHeroStream(appState.focusTarget || "mayor");
  refs.mayorMonitor.innerHTML = renderMonitorStream("mayor", { focusable: false });

  const visibleWorkers = monitorWorkers().filter(matchesStreamFilters);
  refs.monitorWallSummary.textContent = `${visibleWorkers.length} panes visible`;
  refs.monitorWall.innerHTML = visibleWorkers.length > 0
    ? visibleWorkers.map((worker) => renderMonitorStream(worker.stream.target, { focusable: true })).join("")
    : `<div class="empty-state">No worker streams match the current monitor filters.</div>`;

  bindStreamActions(refs.focusStream);
  bindStreamActions(refs.overviewHero);
  bindStreamActions(refs.mayorMonitor);
  bindStreamActions(refs.monitorWall);
}

function renderHeroStream(target) {
  const stream = streamFor(target);
  const details = streamDetail(target);
  return `
    <article class="hero-card">
      <div class="stream-head">
        <div class="stream-title">
          <div class="stream-target">${esc(target)}</div>
          <div class="stream-meta">${esc(details)}</div>
          <div class="stream-meta">${esc(streamCaption(stream))}</div>
        </div>
        <div class="stream-actions">
          <span class="state-pill ${streamStateClass(stream)}">${esc(stream.state)}</span>
          <button class="btn tiny ghost" data-follow-toggle="${escAttr(target)}">${stream.follow ? "Tail On" : "Tail Off"}</button>
          <button class="btn tiny ghost" data-peek-target="${escAttr(target)}">Peek</button>
        </div>
      </div>
      <div class="stream-body" data-stream-target="${escAttr(target)}">${esc(stream.content || "Waiting for tmux stream data...")}</div>
    </article>
  `;
}

function renderMonitorStream(target, options = {}) {
  const stream = streamFor(target);
  const details = streamDetail(target);
  return `
    <article class="stream-card">
      <div class="stream-head">
        <div class="stream-title">
          <div class="stream-target">${esc(target)}</div>
          <div class="stream-meta">${esc(details)}</div>
          <div class="stream-meta">${esc(streamCaption(stream))}</div>
        </div>
        <div class="stream-actions">
          <span class="state-pill ${streamStateClass(stream)}">${esc(stream.state)}</span>
          <button class="btn tiny ghost" data-follow-toggle="${escAttr(target)}">${stream.follow ? "Tail On" : "Tail Off"}</button>
          ${options.focusable ? `<button class="btn tiny ghost" data-focus-target="${escAttr(target)}">Focus</button>` : ""}
          <button class="btn tiny ghost" data-peek-target="${escAttr(target)}">Peek</button>
        </div>
      </div>
      <div class="stream-body" data-stream-target="${escAttr(target)}">${esc(stream.content || "Waiting for tmux stream data...")}</div>
    </article>
  `;
}

function bindStreamActions(root) {
  root.querySelectorAll("[data-focus-target]").forEach((button) => {
    button.addEventListener("click", () => {
      appState.focusTarget = button.dataset.focusTarget;
      syncStreamTargets();
      renderStreamDeck();
    });
  });
  root.querySelectorAll("[data-peek-target]").forEach((button) => {
    button.addEventListener("click", () => peek(button.dataset.peekTarget));
  });
  root.querySelectorAll("[data-follow-toggle]").forEach((button) => {
    button.addEventListener("click", () => {
      const stream = streamFor(button.dataset.followToggle);
      stream.follow = !stream.follow;
      appState.streams.set(stream.target, stream);
      renderStreamDeck();
    });
  });
  root.querySelectorAll("[data-stream-target]").forEach((el) => {
    const stream = appState.streams.get(el.dataset.streamTarget);
    if (!stream) return;
    const wasNearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
    if (stream.follow || wasNearBottom) {
      el.scrollTop = el.scrollHeight;
      stream.follow = true;
    }
    el.addEventListener("scroll", () => {
      stream.follow = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
    });
  });
}

function streamFor(target) {
  return appState.streams.get(target) || {
    target,
    content: "",
    state: "opening",
    follow: appState.streamFollowAll,
    lastEventAt: 0,
    session: "",
  };
}

function handleStreamFilterChange() {
  appState.streamFilters = {
    rig: refs.streamRigFilter.value || "all",
    role: refs.streamRoleFilter.value || "polecat",
    query: refs.streamQuery.value.trim().toLowerCase(),
  };
  syncStreamTargets();
  renderStreamDeck();
}

function toggleFollowAll() {
  appState.streamFollowAll = !appState.streamFollowAll;
  for (const stream of appState.streams.values()) {
    stream.follow = appState.streamFollowAll;
  }
  renderStreamDeck();
}

function renderStreamFilters() {
  const rigs = ["all", ...appState.cockpit.rigs.map((rig) => rig.name)];
  refs.streamRigFilter.innerHTML = rigs
    .map((rig) => `<option value="${escAttr(rig)}">${esc(rig === "all" ? "All rigs" : rig)}</option>`)
    .join("");
  if (!rigs.includes(appState.streamFilters.rig)) appState.streamFilters.rig = "all";
  refs.streamRigFilter.value = appState.streamFilters.rig;
  refs.streamRoleFilter.value = appState.streamFilters.role;
  refs.streamQuery.value = appState.streamFilters.query;
  refs.followAllBtn.textContent = appState.streamFollowAll ? "Tail All: On" : "Tail All: Off";
}

function renderLogs() {
  refs.logSummary.textContent = `${appState.cockpit.logs.total || appState.cockpit.logs.lines.length} lines buffered`;
  const nearTail = refs.logViewer.scrollHeight - refs.logViewer.scrollTop - refs.logViewer.clientHeight < 40;
  refs.logViewer.innerHTML = (appState.cockpit.logs.lines || []).map(formatLogLine).join("");
  if (nearTail || !refs.logViewer.dataset.rendered) {
    refs.logViewer.scrollTop = refs.logViewer.scrollHeight;
  }
  refs.logViewer.dataset.rendered = "1";
}

function appendLogLines(lines) {
  const viewer = refs.logViewer;
  const nearTail = viewer.scrollHeight - viewer.scrollTop - viewer.clientHeight < 40;
  viewer.innerHTML += lines.map(formatLogLine).join("");
  if (nearTail) viewer.scrollTop = viewer.scrollHeight;
}

async function loadRigs() {
  try {
    const response = await fetch("/api/rigs");
    appState.rigs = await response.json();
    populateRigSelects();
  } catch {}
}

function populateRigSelects() {
  const options = appState.rigs.map((rig) => `<option value="${escAttr(rig.name)}">${esc(rig.name)}</option>`).join("");
  const placeholder = `<option value="">Select a rig...</option>`;
  refs.slingRig.innerHTML = placeholder + options;
  refs.dogRig.innerHTML = placeholder + options;
}

async function handleSlingSubmit(event) {
  event.preventDefault();
  refs.slingBtn.disabled = true;
  refs.slingBtn.textContent = "Dispatching...";
  try {
    const labels = document.getElementById("slingLabels").value.split(",").map((label) => label.trim()).filter(Boolean);
    const response = await fetch("/api/sling", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        rig: refs.slingRig.value,
        task: document.getElementById("slingTask").value,
        labels,
        convoy: document.getElementById("slingConvoy").value || undefined,
      }),
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Dispatch failed");
    toast("Polecat dispatched.", "success");
    refs.slingForm.reset();
  } catch (error) {
    toast(error.message, "error");
  } finally {
    refs.slingBtn.disabled = false;
    refs.slingBtn.textContent = "Dispatch Polecat";
    populateRigSelects();
  }
}

async function handleDogSubmit(event) {
  event.preventDefault();
  refs.dogBtn.disabled = true;
  refs.dogBtn.textContent = "Dispatching...";
  try {
    const response = await fetch("/api/sling-dog", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        rig: refs.dogRig.value,
        issue: document.getElementById("dogIssue").value.replace("#", ""),
      }),
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Dispatch failed");
    toast("Dog dispatched.", "success");
    refs.dogForm.reset();
  } catch (error) {
    toast(error.message, "error");
  } finally {
    refs.dogBtn.disabled = false;
    refs.dogBtn.textContent = "Dispatch Dog";
    populateRigSelects();
  }
}

async function loadLogs() {
  try {
    const response = await fetch("/api/logs?lines=250");
    const payload = await response.json();
    appState.cockpit.logs.lines = payload.lines || [];
    appState.cockpit.logs.total = appState.cockpit.logs.lines.length;
    appState.lastLogAt = Date.now();
    refs.logViewer.dataset.rendered = "";
    renderLogs();
  } catch {}
}

async function peek(target) {
  refs.peekModal.classList.add("active");
  refs.peekTitle.textContent = `Peek: ${target}`;
  refs.peekOutput.textContent = "Loading...";
  try {
    const response = await fetch(`/api/peek/${encodeURIComponent(target)}`);
    const payload = await response.json();
    refs.peekOutput.textContent = payload.output || payload.error || "No output.";
  } catch (error) {
    refs.peekOutput.textContent = `Error: ${error.message}`;
  }
}

function closePeek() {
  refs.peekModal.classList.remove("active");
}

function renderTopology() {
  const topology = appState.cockpit.topology || { nodes: [], edges: [] };
  const canvas = refs.topologyCanvas;
  const width = canvas.clientWidth || canvas.width;
  const height = canvas.clientHeight || canvas.height;
  const renderState = buildTopologyRenderState(topology, width, height);

  refs.topologyList.innerHTML = renderTopologyFeed(renderState);
  refs.topologySummary.innerHTML = renderTopologySummary(renderState);

  if (renderState.nodes.length === 0) {
    renderTopologyCanvasFallback(renderState, width, height);
    return;
  }

  const renderedWithWebGl = renderTopologyWebGl(renderState, width, height);
  if (!renderedWithWebGl) {
    renderTopologyCanvasFallback(renderState, width, height);
  }
}

function setupTopologyCanvas() {
  detectTopologyMode();
}

function detectTopologyMode() {
  const hasWebGl = Boolean(window.WebGLRenderingContext && document.createElement("canvas").getContext("webgl"));
  appState.topology.renderer = hasWebGl ? "webgl" : "canvas";
  appState.topology.modeLabel = hasWebGl ? "WebGL live topology" : "Canvas fallback";
  refs.topologyMode.textContent = appState.topology.modeLabel;
}

function topologyColor(type, state) {
  if (type === "blocker" || state === "blocked") return "#ff6b6b";
  if (type === "rig") return "#8bf0ff";
  if (type === "queue") return "#f8b84a";
  if (type === "issue") return "#c58fff";
  if (type === "pr") return "#7da8ff";
  if (state === "alive" || state === "active") return "#9df77d";
  return "#7da8ff";
}

function buildTopologyRenderState(topology, width, height) {
  const nodes = Array.isArray(topology.nodes) ? topology.nodes : [];
  const edges = Array.isArray(topology.edges) ? topology.edges : [];
  const layout = appState.topology.layout;
  const nodeMap = new Map(nodes.map((node) => [node.id, node]));
  const rigIds = nodes.filter((node) => node.type === "rig").map((node) => node.id);

  for (const id of Array.from(layout.keys())) {
    if (!nodeMap.has(id)) layout.delete(id);
  }

  const bounds = {
    minX: 30,
    maxX: Math.max(30, width - 30),
    minY: 30,
    maxY: Math.max(30, height - 30),
  };

  nodes.forEach((node) => {
    const anchor = topologyAnchor(node, width, height, rigIds);
    const existing = layout.get(node.id);
    const position = existing || {
      x: anchor.x + ((hashString(node.id) % 23) - 11) * 2.2,
      y: anchor.y + ((hashString(`${node.id}:y`) % 23) - 11) * 1.9,
      vx: 0,
      vy: 0,
    };
    layout.set(node.id, {
      id: node.id,
      ...position,
      anchorX: anchor.x,
      anchorY: anchor.y,
      radius: topologyRadius(node),
      color: topologyColor(node.type, node.state),
      label: node.label || node.id,
      detail: node.detail || "",
      rig: node.rig || "",
      type: node.type || "node",
      state: node.state || "",
    });
  });

  for (let iteration = 0; iteration < 30; iteration += 1) {
    for (let i = 0; i < nodes.length; i += 1) {
      const left = layout.get(nodes[i].id);
      if (!left) continue;
      for (let j = i + 1; j < nodes.length; j += 1) {
        const right = layout.get(nodes[j].id);
        if (!right) continue;
        const dx = left.x - right.x;
        const dy = left.y - right.y;
        const distanceSq = Math.max(dx * dx + dy * dy, 1);
        const distance = Math.sqrt(distanceSq);
        const force = 1600 / distanceSq;
        const pushX = (dx / distance) * force;
        const pushY = (dy / distance) * force;
        left.vx += pushX;
        left.vy += pushY;
        right.vx -= pushX;
        right.vy -= pushY;
      }
    }

    edges.forEach((edge) => {
      const from = layout.get(edge.from);
      const to = layout.get(edge.to);
      if (!from || !to) return;
      const dx = to.x - from.x;
      const dy = to.y - from.y;
      const distance = Math.max(Math.hypot(dx, dy), 1);
      const desired = preferredTopologyEdgeLength(from, to, width, height);
      const pull = (distance - desired) * 0.0034;
      const shiftX = (dx / distance) * pull;
      const shiftY = (dy / distance) * pull;
      from.vx += shiftX;
      from.vy += shiftY;
      to.vx -= shiftX;
      to.vy -= shiftY;
    });

    nodes.forEach((node) => {
      const current = layout.get(node.id);
      if (!current) return;
      current.vx += (current.anchorX - current.x) * 0.018;
      current.vy += (current.anchorY - current.y) * 0.018;
      current.vx *= 0.82;
      current.vy *= 0.82;
      current.x = clamp(current.x + current.vx, bounds.minX, bounds.maxX);
      current.y = clamp(current.y + current.vy, bounds.minY, bounds.maxY);
    });
  }

  const renderNodes = nodes.map((node) => ({ id: node.id, ...layout.get(node.id) }));
  const renderNodeMap = new Map(renderNodes.map((node) => [node.id, node]));
  const renderEdges = edges
    .map((edge) => ({ ...edge, fromNode: renderNodeMap.get(edge.from), toNode: renderNodeMap.get(edge.to) }))
    .filter((edge) => edge.fromNode && edge.toNode);

  const activeId = appState.topology.selectedId || appState.topology.hoveredId || renderNodes[0]?.id || "";
  const activeNode = activeId ? renderNodeMap.get(activeId) : null;

  return {
    width,
    height,
    nodes: renderNodes,
    edges: renderEdges,
    nodeMap: renderNodeMap,
    activeNode,
    activeId: activeNode ? activeNode.id : "",
  };
}

function renderTopologyFeed(renderState) {
  if (renderState.edges.length === 0) {
    return `<div class="empty-state">Relationship edges will appear here once the cockpit snapshot includes linked rigs, workers, blockers, or queue items.</div>`;
  }

  const activeId = renderState.activeId;
  const prioritized = [...renderState.edges].sort((left, right) => {
    const leftScore = left.from === activeId || left.to === activeId ? 1 : 0;
    const rightScore = right.from === activeId || right.to === activeId ? 1 : 0;
    return rightScore - leftScore;
  });

  return prioritized.slice(0, 18).map((edge) => `
    <div class="topology-item">${esc(shortTopologyLabel(renderState.nodeMap.get(edge.from)))} -> ${esc(shortTopologyLabel(renderState.nodeMap.get(edge.to)))} (${esc(edge.type)})</div>
  `).join("");
}

function renderTopologySummary(renderState) {
  if (renderState.nodes.length === 0) {
    return `<strong>No topology yet</strong>Waiting for snapshot nodes and edges from the cockpit backend.`;
  }

  const node = renderState.activeNode;
  if (!node) {
    return `<strong>Live graph ready</strong>${esc(renderState.nodes.length)} nodes, ${esc(renderState.edges.length)} edges. Select a node in the graph to inspect its connected lanes.`;
  }

  const connected = renderState.edges.filter((edge) => edge.from === node.id || edge.to === node.id);
  const detailParts = [node.type];
  if (node.rig) detailParts.push(node.rig);
  if (node.state) detailParts.push(node.state);
  return `
    <strong>${esc(node.label)}</strong>
    ${esc(detailParts.join(" • "))}<br>
    ${esc(node.detail || "No extra detail recorded.")}<br>
    ${esc(connected.length)} linked relationship${connected.length === 1 ? "" : "s"} in the current cockpit snapshot.
  `;
}

function renderTopologyCanvasFallback(renderState, width, height) {
  const canvas = refs.topologyCanvas;
  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.max(1, Math.round(width * dpr));
  canvas.height = Math.max(1, Math.round(height * dpr));
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, width, height);
  refs.topologyMode.textContent = appState.topology.renderer === "webgl" ? "Canvas fallback (WebGL init failed)" : appState.topology.modeLabel;

  drawTopologyBackdrop(ctx, width, height);

  if (renderState.nodes.length === 0) {
    ctx.fillStyle = "#7fa9bc";
    ctx.font = "14px IBM Plex Sans";
    ctx.fillText("Topology data will appear when the cockpit snapshot contains nodes.", 20, 34);
    return;
  }

  renderState.edges.forEach((edge) => {
    const emphasis = edge.from === renderState.activeId || edge.to === renderState.activeId;
    ctx.strokeStyle = emphasis ? "rgba(248, 184, 74, 0.72)" : "rgba(77, 214, 255, 0.24)";
    ctx.lineWidth = emphasis ? 2 : 1.2;
    ctx.beginPath();
    ctx.moveTo(edge.fromNode.x, edge.fromNode.y);
    ctx.lineTo(edge.toNode.x, edge.toNode.y);
    ctx.stroke();
  });

  renderState.nodes.forEach((node) => {
    const selected = node.id === renderState.activeId;
    const hovered = node.id === appState.topology.hoveredId;
    ctx.fillStyle = node.color;
    ctx.shadowBlur = selected || hovered ? 20 : 12;
    ctx.shadowColor = node.color;
    ctx.beginPath();
    ctx.arc(node.x, node.y, node.radius + (selected ? 2 : 0), 0, Math.PI * 2);
    ctx.fill();
    ctx.shadowBlur = 0;
    ctx.fillStyle = "#d9f4ff";
    ctx.font = selected ? "600 12px IBM Plex Sans" : "12px IBM Plex Sans";
    ctx.fillText(node.label, node.x + node.radius + 8, node.y + 4);
  });
}

function renderTopologyWebGl(renderState, width, height) {
  if (appState.topology.renderer !== "webgl") return false;
  const gl = ensureTopologyGl();
  if (!gl) return false;

  refs.topologyMode.textContent = appState.topology.modeLabel;
  const canvas = refs.topologyCanvas;
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.max(1, Math.round(width * dpr));
  canvas.height = Math.max(1, Math.round(height * dpr));
  gl.viewport(0, 0, canvas.width, canvas.height);
  gl.clearColor(0.015, 0.05, 0.08, 1);
  gl.clear(gl.COLOR_BUFFER_BIT);

  const edgeVertices = [];
  const edgeColors = [];
  renderState.edges.forEach((edge) => {
    const emphasis = edge.from === renderState.activeId || edge.to === renderState.activeId;
    const rgba = emphasis ? [0.973, 0.722, 0.29, 0.95] : [0.302, 0.839, 1, 0.24];
    pushGlVertex(edgeVertices, edge.fromNode.x, edge.fromNode.y, width, height);
    pushGlVertex(edgeVertices, edge.toNode.x, edge.toNode.y, width, height);
    edgeColors.push(...rgba, ...rgba);
  });

  const nodeVertices = [];
  const nodeColors = [];
  const nodeSizes = [];
  renderState.nodes.forEach((node) => {
    pushGlVertex(nodeVertices, node.x, node.y, width, height);
    nodeColors.push(...hexToRgb(topologyColor(node.type, node.state)), 1);
    const emphasis = node.id === renderState.activeId ? 5 : node.id === appState.topology.hoveredId ? 3 : 0;
    nodeSizes.push((node.radius + emphasis) * (window.devicePixelRatio || 1));
  });

  const { program, buffers } = appState.topology;
  gl.useProgram(program.handle);

  if (edgeVertices.length > 0) {
    bindGlAttribute(gl, buffers.edgePosition, program.attributes.aPosition, new Float32Array(edgeVertices), 2);
    bindGlAttribute(gl, buffers.edgeColor, program.attributes.aColor, new Float32Array(edgeColors), 4);
    gl.disableVertexAttribArray(program.attributes.aPointSize);
    gl.vertexAttrib1f(program.attributes.aPointSize, 1);
    gl.uniform1f(program.uniforms.uRenderPoints, 0);
    gl.drawArrays(gl.LINES, 0, edgeVertices.length / 2);
  }

  bindGlAttribute(gl, buffers.nodePosition, program.attributes.aPosition, new Float32Array(nodeVertices), 2);
  bindGlAttribute(gl, buffers.nodeColor, program.attributes.aColor, new Float32Array(nodeColors), 4);
  bindGlAttribute(gl, buffers.nodeSize, program.attributes.aPointSize, new Float32Array(nodeSizes), 1);
  gl.uniform1f(program.uniforms.uRenderPoints, 1);
  gl.drawArrays(gl.POINTS, 0, nodeVertices.length / 2);
  return true;
}

function ensureTopologyGl() {
  if (appState.topology.gl) return appState.topology.gl;
  const canvas = refs.topologyCanvas;
  const gl = canvas.getContext("webgl", { antialias: true, alpha: false, preserveDrawingBuffer: false });
  if (!gl) {
    appState.topology.renderer = "canvas";
    appState.topology.modeLabel = "Canvas fallback";
    return null;
  }

  const vertexSource = `
    attribute vec2 aPosition;
    attribute vec4 aColor;
    attribute float aPointSize;
    varying vec4 vColor;
    uniform float uRenderPoints;
    void main() {
      gl_Position = vec4(aPosition, 0.0, 1.0);
      gl_PointSize = max(aPointSize, 1.0);
      vColor = aColor;
    }
  `;
  const fragmentSource = `
    precision mediump float;
    varying vec4 vColor;
    uniform float uRenderPoints;
    void main() {
      if (uRenderPoints > 0.5) {
        vec2 p = gl_PointCoord * 2.0 - 1.0;
        if (dot(p, p) > 1.0) discard;
      }
      gl_FragColor = vColor;
    }
  `;

  const program = createGlProgram(gl, vertexSource, fragmentSource);
  if (!program) {
    appState.topology.renderer = "canvas";
    appState.topology.modeLabel = "Canvas fallback";
    return null;
  }

  appState.topology.gl = gl;
  appState.topology.program = {
    handle: program,
    attributes: {
      aPosition: gl.getAttribLocation(program, "aPosition"),
      aColor: gl.getAttribLocation(program, "aColor"),
      aPointSize: gl.getAttribLocation(program, "aPointSize"),
    },
    uniforms: {
      uRenderPoints: gl.getUniformLocation(program, "uRenderPoints"),
    },
  };
  appState.topology.buffers = {
    edgePosition: gl.createBuffer(),
    edgeColor: gl.createBuffer(),
    nodePosition: gl.createBuffer(),
    nodeColor: gl.createBuffer(),
    nodeSize: gl.createBuffer(),
  };
  gl.useProgram(program);
  gl.enable(gl.BLEND);
  gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
  return gl;
}

function handleTopologyPointerMove(event) {
  const hit = topologyHitTest(event);
  updateTopologyHover(hit ? hit.id : "");
}

function handleTopologyClick(event) {
  const hit = topologyHitTest(event);
  appState.topology.selectedId = hit ? hit.id : "";
  renderTopology();
}

function topologyHitTest(event) {
  const canvas = refs.topologyCanvas;
  const rect = canvas.getBoundingClientRect();
  const x = event.clientX - rect.left;
  const y = event.clientY - rect.top;
  let nearest = null;
  let nearestDistance = 28;

  for (const node of appState.topology.layout.values()) {
    const distance = Math.hypot(node.x - x, node.y - y);
    if (distance < nearestDistance) {
      nearest = node;
      nearestDistance = distance;
    }
  }

  return nearest;
}

function updateTopologyHover(id) {
  if (appState.topology.hoveredId === id) return;
  appState.topology.hoveredId = id;
  renderTopology();
}

function topologyAnchor(node, width, height, rigIds) {
  const rigIndex = node.rig ? rigIds.indexOf(`rig:${node.rig}`) : -1;
  const rigCount = Math.max(rigIds.length, 1);
  const rigX = rigIndex >= 0 ? width * (0.18 + (0.64 * (rigIndex + 0.5)) / rigCount) : width * 0.5;
  const rigY = height * 0.42;

  if (node.id === "mayor") return { x: width * 0.5, y: height * 0.14 };
  if (node.type === "rig") return { x: rigX, y: rigY };
  if (node.type === "polecat" || node.type === "dog") return { x: rigX, y: Math.min(height - 60, rigY + 95) };
  if (node.type === "issue") return { x: rigX - 54, y: Math.min(height - 40, rigY + 182) };
  if (node.type === "pr") return { x: rigX + 56, y: Math.min(height - 40, rigY + 180) };
  if (node.type === "blocker") return { x: rigX, y: Math.max(52, rigY - 112) };
  if (node.type === "queue") return { x: rigX + 96, y: Math.max(60, rigY - 28) };
  return { x: width * 0.5, y: height * 0.5 };
}

function preferredTopologyEdgeLength(from, to, width, height) {
  if (from.type === "rig" || to.type === "rig") return Math.min(width, height) * 0.18;
  if (from.type === "blocker" || to.type === "blocker") return Math.min(width, height) * 0.2;
  return Math.min(width, height) * 0.14;
}

function topologyRadius(node) {
  if (node.type === "mayor" || node.id === "mayor") return 14;
  if (node.type === "rig") return 11;
  if (node.type === "blocker") return 9;
  if (node.type === "queue") return 8;
  return 7;
}

function drawTopologyBackdrop(ctx, width, height) {
  ctx.clearRect(0, 0, width, height);
  const gradient = ctx.createRadialGradient(width * 0.5, height * 0.48, 30, width * 0.5, height * 0.48, Math.max(width, height) * 0.44);
  gradient.addColorStop(0, "rgba(77, 214, 255, 0.12)");
  gradient.addColorStop(1, "rgba(3, 14, 22, 0.98)");
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, width, height);
  ctx.strokeStyle = "rgba(77, 214, 255, 0.08)";
  ctx.lineWidth = 1;
  for (let ring = 1; ring <= 4; ring += 1) {
    ctx.beginPath();
    ctx.arc(width / 2, height / 2, (Math.min(width, height) * ring) / 7, 0, Math.PI * 2);
    ctx.stroke();
  }
}

function shortTopologyLabel(node) {
  return node ? node.label || node.id : "unknown";
}

function pushGlVertex(target, x, y, width, height) {
  target.push((x / width) * 2 - 1, 1 - (y / height) * 2);
}

function bindGlAttribute(gl, buffer, attribute, data, size) {
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
  gl.enableVertexAttribArray(attribute);
  gl.vertexAttribPointer(attribute, size, gl.FLOAT, false, 0, 0);
}

function createGlProgram(gl, vertexSource, fragmentSource) {
  const vertexShader = compileGlShader(gl, gl.VERTEX_SHADER, vertexSource);
  const fragmentShader = compileGlShader(gl, gl.FRAGMENT_SHADER, fragmentSource);
  if (!vertexShader || !fragmentShader) return null;
  const program = gl.createProgram();
  gl.attachShader(program, vertexShader);
  gl.attachShader(program, fragmentShader);
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) return null;
  return program;
}

function compileGlShader(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) return null;
  return shader;
}

function hexToRgb(hex) {
  const value = hex.replace("#", "");
  const normalized = value.length === 3 ? value.split("").map((item) => `${item}${item}`).join("") : value;
  const intValue = Number.parseInt(normalized, 16);
  return [
    ((intValue >> 16) & 255) / 255,
    ((intValue >> 8) & 255) / 255,
    (intValue & 255) / 255,
  ];
}

function hashString(value) {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = ((hash << 5) - hash + value.charCodeAt(index)) | 0;
  }
  return Math.abs(hash);
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function workerPriority(worker) {
  return (worker.status === "alive" ? 20 : 0) + (worker.role === "polecat" ? 8 : 0) + (worker.issue ? 4 : 0);
}

function monitorWorkers() {
  return [...appState.cockpit.workers]
    .filter((worker) => worker.stream && worker.stream.available)
    .sort((left, right) => workerPriority(right) - workerPriority(left));
}

function matchesStreamFilters(worker) {
  if (appState.streamFilters.role !== "all" && worker.role !== appState.streamFilters.role) return false;
  if (appState.streamFilters.rig !== "all" && worker.rig !== appState.streamFilters.rig) return false;
  if (!appState.streamFilters.query) return true;
  const haystack = [worker.name, worker.rig, worker.role, worker.issue, worker.branch].join(" ").toLowerCase();
  return haystack.includes(appState.streamFilters.query);
}

function streamDetail(target) {
  if (target === "mayor") return "Mayor command loop";
  const worker = appState.cockpit.workers.find((item) => item.stream && item.stream.target === target);
  if (!worker) return "Live worker pane";
  const detail = [worker.role];
  if (worker.rig) detail.push(worker.rig);
  if (worker.issue) detail.push(`#${worker.issue}`);
  return detail.join(" • ");
}

function workerStateClass(worker) {
  if (worker.status === "alive") return "state-live";
  if (worker.warning) return "state-warn";
  return "state-bad";
}

function rigStateClass(rig) {
  if (rig.blockers > 0) return "state-blocked";
  if (String(rig.state).includes("hibernat")) return "state-warn";
  if (rig.activeWorkers > 0) return "state-active";
  return "state-good";
}

function streamStateClass(stream) {
  if (stream.state === "live") return "state-live";
  if (stream.state === "stale") return "state-stale";
  if (stream.state === "closed") return "state-bad";
  return "state-active";
}

function streamCaption(stream) {
  if (stream.state === "live") {
    return stream.session ? `Live tmux stream from ${stream.session}` : "Live tmux stream";
  }
  if (stream.state === "stale") {
    return `Stale stream${stream.reason ? `: ${stream.reason}` : ""}`;
  }
  if (stream.state === "closed") {
    return `Closed${stream.reason ? `: ${stream.reason}` : ""}`;
  }
  return "Waiting for stream open";
}

function updateClocks() {
  refs.lastUpdated.textContent = timeLabel(appState.lastSnapshotAt);
  refs.lastLog.textContent = timeLabel(appState.lastLogAt);
}

function timeLabel(timestamp) {
  if (!timestamp) return "--";
  return new Date(timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

function formatIso(iso) {
  if (!iso) return "unknown";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toLocaleString([], {
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function snippet(value, maxLength) {
  if (!value) return "";
  return value.length > maxLength ? `${value.slice(0, maxLength - 1)}...` : value;
}

function formatLogLine(line) {
  const match = line.match(/^\[([^\]]+)\]\s+(\S+)\s*(.*)/);
  if (match) {
    return `<div class="log-line"><span class="timestamp">[${esc(match[1])}]</span> <span class="log-event">${esc(match[2])}</span> ${esc(match[3])}</div>`;
  }
  return `<div class="log-line">${esc(line)}</div>`;
}

function toast(message, type) {
  const node = document.createElement("div");
  node.className = `toast ${type || ""}`;
  node.textContent = message;
  refs.toasts.appendChild(node);
  setTimeout(() => node.remove(), 4000);
}

function esc(value) {
  if (value == null) return "";
  const div = document.createElement("div");
  div.textContent = String(value);
  return div.innerHTML;
}

function escAttr(value) {
  return esc(value).replace(/"/g, "&quot;");
}

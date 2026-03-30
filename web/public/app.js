const COMPACT_KEY = "sgt_web_compact";
const VOICE_MUTE_KEY = "sgt_web_voice_muted";

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
  voiceMuted: true,
  alertIdsSeen: new Set(),
  alertsBootstrapped: false,
  activeAnnouncement: null,
};

const refs = {
  wsHealth: document.getElementById("wsHealth"),
  connLabel: document.getElementById("connLabel"),
  lastUpdated: document.getElementById("lastUpdated"),
  lastLog: document.getElementById("lastLog"),
  voiceMuteBtn: document.getElementById("voiceMuteBtn"),
  voiceStatus: document.getElementById("voiceStatus"),
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
  alertRail: document.getElementById("alertRail"),
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
  setVoiceMuted(localStorage.getItem(VOICE_MUTE_KEY) !== "0");
  bindEvents();
  detectTopologyMode();
  loadRigs();
  loadLogs();
  connectWs();
  setInterval(updateClocks, 1000);
}

function bindEvents() {
  refs.compactBtn.addEventListener("click", () => setCompact(!document.body.classList.contains("compact")));
  refs.refreshSnapshotBtn.addEventListener("click", requestSnapshot);
  refs.voiceMuteBtn.addEventListener("click", () => setVoiceMuted(!appState.voiceMuted));
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
}

function emptyCockpit() {
  return {
    meta: { serverTime: "", featureFlags: {}, voice: {} },
    agents: [],
    rigs: [],
    workers: [],
    queue: { items: [], summary: { total: 0 } },
    blockers: [],
    alerts: [],
    logs: { lines: [], total: 0 },
    topology: { nodes: [], edges: [] },
  };
}

function setCompact(on) {
  document.body.classList.toggle("compact", Boolean(on));
  localStorage.setItem(COMPACT_KEY, on ? "1" : "0");
}

function setVoiceMuted(on) {
  appState.voiceMuted = Boolean(on);
  localStorage.setItem(VOICE_MUTE_KEY, appState.voiceMuted ? "1" : "0");
  refs.voiceMuteBtn.setAttribute("aria-pressed", appState.voiceMuted ? "true" : "false");
  refs.voiceMuteBtn.classList.toggle("active", !appState.voiceMuted);
  updateVoiceStatus();
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
    const newAlerts = diffNewAlerts(message.snapshot.alerts || []);
    appState.cockpit = message.snapshot;
    appState.lastSnapshotAt = Date.now();
    if (!appState.focusTarget || !hasTarget(appState.focusTarget)) {
      appState.focusTarget = preferredFocusTarget();
    }
    syncStreamTargets();
    renderAll();
    maybePlayVoiceAnnouncement(newAlerts);
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
  renderAlerts();
  renderBlockers();
  renderQueue();
  renderStreamDeck();
  renderLogs();
  renderTopology();
}

function renderAlerts() {
  const alerts = appState.cockpit.alerts || [];
  updateVoiceStatus();
  if (alerts.length === 0) {
    refs.alertRail.innerHTML = `<div class="empty-state">Recent blocker transitions and milestone alerts will appear here.</div>`;
    return;
  }

  refs.alertRail.innerHTML = alerts.slice(0, 6).map((alert) => `
    <article class="alert-card alert-${escAttr(alert.severity || "info")}">
      <div class="queue-head">
        <div class="blocker-title">${esc(alert.message || alert.title)}</div>
        <span class="severity-pill ${alertSeverityClass(alert)}">${esc(alert.kind || "event")}</span>
      </div>
      <div class="blocker-meta">
        <span>${esc(alert.rig || "unknown rig")}</span>
        <span>${esc(formatIso(alert.createdAt))}</span>
        <span>${esc(alertVoiceLabel(alert))}</span>
      </div>
    </article>
  `).join("");
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
  const totalAlerts = (appState.cockpit.alerts || []).length;
  refs.blockerSummary.textContent = `${appState.cockpit.blockers.length} open blockers · ${totalAlerts} recent alerts`;
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
        <span>${esc(snippet(blocker.id || "", 26))}</span>
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
  refs.topologyList.innerHTML = (topology.edges || []).slice(0, 16).map((edge) => `
    <div class="topology-item">${esc(edge.from)} -> ${esc(edge.to)} (${esc(edge.type)})</div>
  `).join("");

  const canvas = refs.topologyCanvas;
  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  const width = canvas.clientWidth || canvas.width;
  const height = canvas.clientHeight || canvas.height;
  canvas.width = width * devicePixelRatio;
  canvas.height = height * devicePixelRatio;
  ctx.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
  ctx.clearRect(0, 0, width, height);

  const nodes = topology.nodes || [];
  const edges = topology.edges || [];
  if (nodes.length === 0) {
    ctx.fillStyle = "#7fa9bc";
    ctx.font = "14px IBM Plex Sans";
    ctx.fillText("Topology data will appear when the cockpit snapshot contains nodes.", 20, 34);
    return;
  }

  const positions = new Map();
  const centerX = width / 2;
  const centerY = height / 2;
  const radius = Math.max(120, Math.min(width, height) / 2.8);

  nodes.forEach((node, index) => {
    const angle = (Math.PI * 2 * index) / Math.max(nodes.length, 1) - Math.PI / 2;
    positions.set(node.id, {
      x: centerX + Math.cos(angle) * radius,
      y: centerY + Math.sin(angle) * radius,
      color: topologyColor(node.type, node.state),
    });
  });

  ctx.lineWidth = 1.2;
  edges.forEach((edge) => {
    const from = positions.get(edge.from);
    const to = positions.get(edge.to);
    if (!from || !to) return;
    ctx.strokeStyle = "rgba(77, 214, 255, 0.28)";
    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.lineTo(to.x, to.y);
    ctx.stroke();
  });

  nodes.forEach((node) => {
    const pos = positions.get(node.id);
    if (!pos) return;
    ctx.fillStyle = pos.color;
    ctx.shadowBlur = 18;
    ctx.shadowColor = pos.color;
    ctx.beginPath();
    ctx.arc(pos.x, pos.y, 8, 0, Math.PI * 2);
    ctx.fill();
    ctx.shadowBlur = 0;
    ctx.fillStyle = "#d9f4ff";
    ctx.font = "12px IBM Plex Sans";
    ctx.fillText(node.label || node.id, pos.x + 12, pos.y + 4);
  });
}

function detectTopologyMode() {
  const hasWebGl = Boolean(window.WebGLRenderingContext && document.createElement("canvas").getContext("webgl"));
  refs.topologyMode.textContent = hasWebGl ? "WebGL-ready browser, canvas radar active" : "Canvas fallback";
}

function topologyColor(type, state) {
  if (type === "blocker" || state === "blocked") return "#ff6b6b";
  if (type === "rig") return "#8bf0ff";
  if (type === "queue") return "#f8b84a";
  if (state === "alive" || state === "active") return "#9df77d";
  return "#7da8ff";
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

function diffNewAlerts(alerts) {
  const unseen = [];
  for (const alert of alerts) {
    if (!alert || !alert.id) continue;
    if (!appState.alertIdsSeen.has(alert.id) && appState.alertsBootstrapped) {
      unseen.push(alert);
    }
  }
  appState.alertIdsSeen = new Set(alerts.map((alert) => alert.id).filter(Boolean));
  if (!appState.alertsBootstrapped) {
    appState.alertsBootstrapped = true;
  }
  return unseen;
}

function updateVoiceStatus() {
  const voice = appState.cockpit.meta.voice || {};
  let label = "Muted";
  if (!voice.configured) {
    label = "Unavailable";
  } else if (appState.voiceMuted) {
    label = "Muted";
  } else if (appState.activeAnnouncement) {
    label = "Playing";
  } else {
    label = "Armed";
  }
  refs.voiceStatus.textContent = label;
}

function alertSeverityClass(alert) {
  if (alert.severity === "good") return "state-good";
  if (alert.severity === "warning") return "state-warn";
  if (alert.severity === "critical") return "state-critical";
  return "state-active";
}

function alertVoiceLabel(alert) {
  if (!alert.voice || !alert.voice.enabled) return "Visual only";
  if (alert.voice.eligible) return "Voice ready";
  if (alert.voice.reason === "event-disabled") return "Voice disabled for event";
  if (alert.voice.reason === "rate-limited") return "Voice rate-limited";
  return "Voice unavailable";
}

async function maybePlayVoiceAnnouncement(alerts) {
  if (appState.voiceMuted || appState.activeAnnouncement) {
    updateVoiceStatus();
    return;
  }
  const next = alerts.find((alert) => alert && alert.voice && alert.voice.enabled && alert.voice.eligible);
  if (!next) {
    updateVoiceStatus();
    return;
  }

  const audio = new Audio(`/api/announcements/${encodeURIComponent(next.id)}/audio`);
  appState.activeAnnouncement = audio;
  updateVoiceStatus();

  const clear = () => {
    if (appState.activeAnnouncement === audio) {
      appState.activeAnnouncement = null;
      updateVoiceStatus();
    }
  };

  audio.addEventListener("ended", clear, { once: true });
  audio.addEventListener("error", () => {
    clear();
    toast(`Voice announcement unavailable for ${next.rig || "rig"}.`, "error");
  }, { once: true });

  try {
    await audio.play();
  } catch (error) {
    clear();
    toast(`Voice playback blocked: ${error.message}`, "error");
  }
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

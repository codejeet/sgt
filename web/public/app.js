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
  focusTarget: "president",
  streamFilters: { rig: "all", role: "polecat", query: "" },
  streamFollowAll: true,
  desiredTargets: new Set(),
  streams: new Map(),
  sections: ["streams", "overview", "topology", "dispatch", "logs"],
  voiceMuted: true,
  alertIdsSeen: new Set(),
  alertsBootstrapped: false,
  activeAnnouncement: null,
  topology: {
    mode: "pending",
    renderer: null,
    overlay: null,
    simNodes: [],
    simEdges: [],
    selectedId: "",
    hoverId: "",
    animationFrame: 0,
  },
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
  presidentActivity: document.getElementById("presidentActivity"),
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
  topologyOverlay: document.getElementById("topologyOverlay"),
  topologyFocus: document.getElementById("topologyFocus"),
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
  initializeTopology();
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
      "1": "streams",
      "2": "overview",
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

  window.addEventListener("resize", handleTopologyResize);
}

function initializeTopology() {
  const overlay = refs.topologyOverlay.getContext("2d");
  appState.topology.overlay = overlay;
  initializeTopologyRenderer();
  refs.topologyOverlay.addEventListener("mousemove", handleTopologyPointerMove);
  refs.topologyOverlay.addEventListener("mouseleave", handleTopologyPointerLeave);
  refs.topologyOverlay.addEventListener("click", handleTopologyPointerClick);
  handleTopologyResize();
  kickTopologyLoop();
}

function initializeTopologyRenderer() {
  const canvas = refs.topologyCanvas;
  const gl = canvas.getContext("webgl", { alpha: true, antialias: true });
  if (gl) {
    const renderer = createTopologyWebGlRenderer(gl);
    if (renderer) {
      appState.topology.mode = "webgl";
      appState.topology.renderer = renderer;
      refs.topologyMode.textContent = "WebGL live graph";
      return;
    }
  }

  const ctx = canvas.getContext("2d");
  if (ctx) {
    appState.topology.mode = "canvas";
    appState.topology.renderer = { ctx };
    refs.topologyMode.textContent = "Canvas fallback";
    return;
  }

  appState.topology.mode = "unsupported";
  appState.topology.renderer = null;
  refs.topologyMode.textContent = "Topology unavailable";
}

function handleTopologyResize() {
  const baseWidth = refs.topologyCanvas.clientWidth || refs.topologyCanvas.width || 960;
  const baseHeight = refs.topologyCanvas.clientHeight || 520;
  [refs.topologyCanvas, refs.topologyOverlay].forEach((canvas) => {
    canvas.width = Math.max(1, Math.floor(baseWidth * devicePixelRatio));
    canvas.height = Math.max(1, Math.floor(baseHeight * devicePixelRatio));
  });
  if (appState.topology.mode === "webgl" && appState.topology.renderer && appState.topology.renderer.gl) {
    appState.topology.renderer.gl.viewport(0, 0, refs.topologyCanvas.width, refs.topologyCanvas.height);
  }
  renderTopology();
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
    president: { events: [] },
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
  return liveWorker ? liveWorker.stream.target : rootStreamTarget();
}

function syncStreamTargets() {
  const desired = new Set([rootStreamTarget()]);
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
  if (target === "president" || target === "mayor") return true;
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
  renderPresidentActivity();
  renderQueue();
  renderStreamDeck();
  renderLogs();
  renderTopology();
}

function renderAlerts() {
  const alerts = appState.cockpit.alerts || [];
  updateVoiceStatus();
  if (alerts.length === 0) {
    refs.alertRail.innerHTML = `<div class="empty-state">Recent President incidents, blocker transitions, and milestone alerts will appear here.</div>`;
    return;
  }

  refs.alertRail.innerHTML = alerts.slice(0, 6).map((alert) => `
    <article class="alert-card alert-${escAttr(alert.severity || "info")}">
      <div class="queue-head">
        <div class="blocker-title">${esc(snippet(alert.message || alert.title, 108))}</div>
        <span class="severity-pill ${alertSeverityClass(alert)}">${esc(alert.kind || "event")}</span>
      </div>
      <div class="blocker-meta">
        <span>${esc(alert.rig || "unknown rig")}</span>
        <span>${esc(formatIso(alert.createdAt))}</span>
        <span>${esc(alert.source === "president" ? "President" : "Blocker")}</span>
        <span>${esc(alertVoiceLabel(alert))}</span>
      </div>
      ${(alert.detail || alert.evidence) ? `<p>${esc(snippet(alert.detail || alert.evidence, 140))}</p>` : ""}
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
      detail: "Daemon, President, Mayor, witness, refinery, and support process health.",
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
      <div class="subtle">${esc(rig.reason || "No rig-local mayor detail available.")}</div>
    </article>
  `).join("");
}

function renderBlockers() {
  const totalAlerts = (appState.cockpit.alerts || []).length;
  const presidentEvents = (appState.cockpit.president && appState.cockpit.president.events) || [];
  refs.blockerSummary.textContent = `${appState.cockpit.blockers.length} open blockers · ${totalAlerts} blocker alerts · ${presidentEvents.length} president events`;
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

function renderPresidentActivity() {
  const events = ((appState.cockpit.president && appState.cockpit.president.events) || []).slice(0, 8);
  if (events.length === 0) {
    refs.presidentActivity.innerHTML = `<div class="empty-state">Recent President interventions and operator events will appear here.</div>`;
    return;
  }

  refs.presidentActivity.innerHTML = events.map((event) => `
    <article class="alert-card alert-${escAttr(event.severity || "info")}">
      <div class="queue-head">
        <div class="blocker-title">${esc(presidentEventTitle(event))}</div>
        <span class="severity-pill ${alertSeverityClass(event)}">${esc(event.kind || "president")}</span>
      </div>
      <div class="blocker-meta">
        <span>${esc(event.rig || "cross-rig")}</span>
        <span>${esc(formatIso(event.createdAt))}</span>
        <span>${esc(presidentOutcomeLabel(event))}</span>
      </div>
      <p>${esc(snippet(event.detail || presidentEventDetail(event), 220))}</p>
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

function presidentEventTitle(event) {
  const rig = event.rig || "unknown rig";
  const action = event.action || "acted on";
  const reason = humanizeKebab(event.reason || "unknown reason");
  return `President ${action} mayor/${rig}: ${reason}`;
}

function presidentEventDetail(event) {
  return `${humanizeKebab(event.kind || "incident")} · ${humanizeKebab(event.reason || "unknown reason")}`;
}

function presidentOutcomeLabel(event) {
  if (event.outcome === "suppressed-by-cooldown") return "Suppressed";
  if (event.notify) return "Operator alert";
  return humanizeKebab(event.outcome || "recorded");
}

function renderStreamDeck() {
  renderStreamFilters();
  const orderedTargets = Array.from(appState.desiredTargets);
  refs.streamSummary.textContent = `${orderedTargets.length} subscriptions`;
  refs.overviewHero.innerHTML = renderHeroStream(rootStreamTarget());
  refs.focusStream.innerHTML = renderHeroStream(appState.focusTarget || rootStreamTarget());
  refs.mayorMonitor.innerHTML = renderMonitorStream(rootStreamTarget(), { focusable: false });

  const focusTarget = appState.focusTarget || rootStreamTarget();
  const visibleWorkers = monitorWorkers().filter(matchesStreamFilters);
  const wallWorkers = visibleWorkers.filter((worker) => worker.stream && worker.stream.target !== focusTarget);
  refs.monitorWallSummary.textContent = `${wallWorkers.length} panes visible`;
  refs.monitorWall.innerHTML = wallWorkers.length > 0
    ? wallWorkers.map((worker) => renderMonitorStream(worker.stream.target, { focusable: true })).join("")
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
  const focusLabel = appState.focusTarget === target ? "Focused" : "Focus";
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
          ${options.focusable ? `<button class="btn tiny ghost" data-focus-target="${escAttr(target)}">${focusLabel}</button>` : ""}
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
  buildSimulatedTopology(topology);
  renderTopologySidebar(topology);

  if (appState.topology.mode === "webgl") {
    drawWebGlTopology();
  } else if (appState.topology.mode === "canvas") {
    drawCanvasTopology();
  }
  drawTopologyOverlay();
}

function buildSimulatedTopology(topology) {
  const width = refs.topologyCanvas.clientWidth || 960;
  const height = refs.topologyCanvas.clientHeight || 520;
  const previous = new Map(appState.topology.simNodes.map((node) => [node.id, node]));
  const rigOrder = (appState.cockpit.rigs || []).map((rig) => rig.name);
  const rigCount = Math.max(rigOrder.length, 1);

  appState.topology.simNodes = (topology.nodes || []).map((node, index) => {
    const existing = previous.get(node.id);
    const rigIndex = Math.max(0, rigOrder.indexOf(node.rig || ""));
    const seeded = topologySeed(node.id, rigIndex, width, height, rigCount);
    return {
      ...node,
      radius: topologyRadius(node.type),
      x: existing ? existing.x : seeded.x,
      y: existing ? existing.y : seeded.y,
      vx: existing ? existing.vx : 0,
      vy: existing ? existing.vy : 0,
      anchorX: topologyAnchorX(rigIndex, rigCount, width, node.type),
      anchorY: topologyAnchorY(node.type, height),
      order: index,
    };
  });

  const nodeIds = new Set(appState.topology.simNodes.map((node) => node.id));
  appState.topology.simEdges = (topology.edges || []).filter((edge) => nodeIds.has(edge.from) && nodeIds.has(edge.to));

  if (!appState.topology.selectedId || !nodeIds.has(appState.topology.selectedId)) {
    const preferred = appState.topology.simNodes.find((node) => node.type === "blocker")
      || appState.topology.simNodes.find((node) => node.type === "polecat")
      || appState.topology.simNodes.find((node) => node.type === "rig")
      || appState.topology.simNodes[0];
    appState.topology.selectedId = preferred ? preferred.id : "";
  }
  if (appState.topology.hoverId && !nodeIds.has(appState.topology.hoverId)) {
    appState.topology.hoverId = "";
  }
}

function topologySeed(id, rigIndex, width, height, rigCount) {
  const hash = Array.from(id).reduce((total, ch) => total + ch.charCodeAt(0), 0);
  const baseX = topologyAnchorX(rigIndex, rigCount, width, "");
  const spread = 26 + (hash % 40);
  return {
    x: baseX + Math.cos(hash) * spread,
    y: topologyAnchorY("", height) + Math.sin(hash) * spread,
  };
}

function topologyAnchorX(rigIndex, rigCount, width, type) {
  if (type === "agent" && rigIndex === 0) return width / 2;
  if (rigCount <= 1) return width / 2;
  const gutter = Math.min(120, width * 0.14);
  const usable = Math.max(1, width - gutter * 2);
  return gutter + (usable * (rigIndex + 0.5)) / rigCount;
}

function topologyAnchorY(type, height) {
  if (type === "agent") return height * 0.14;
  if (type === "queue") return height * 0.26;
  if (type === "rig") return height * 0.38;
  if (type === "polecat" || type === "dog") return height * 0.54;
  if (type === "issue" || type === "pr") return height * 0.72;
  if (type === "blocker") return height * 0.84;
  return height * 0.52;
}

function topologyRadius(type) {
  if (type === "rig") return 9;
  if (type === "agent") return 8;
  if (type === "blocker") return 8;
  if (type === "queue") return 7;
  return 6;
}

function kickTopologyLoop() {
  if (appState.topology.animationFrame) return;
  appState.topology.animationFrame = requestAnimationFrame(runTopologyFrame);
}

function runTopologyFrame() {
  appState.topology.animationFrame = 0;
  stepTopologySimulation();
  if (appState.topology.mode === "webgl") {
    drawWebGlTopology();
  } else if (appState.topology.mode === "canvas") {
    drawCanvasTopology();
  }
  drawTopologyOverlay();
  kickTopologyLoop();
}

function stepTopologySimulation() {
  const nodes = appState.topology.simNodes;
  if (nodes.length === 0) return;
  const width = refs.topologyCanvas.clientWidth || 960;
  const height = refs.topologyCanvas.clientHeight || 520;
  const index = new Map(nodes.map((node) => [node.id, node]));

  for (let outer = 0; outer < nodes.length; outer += 1) {
    const left = nodes[outer];
    for (let inner = outer + 1; inner < nodes.length; inner += 1) {
      const right = nodes[inner];
      let dx = right.x - left.x;
      let dy = right.y - left.y;
      const distSq = Math.max(dx * dx + dy * dy, 36);
      const force = 1100 / distSq;
      const dist = Math.sqrt(distSq);
      dx /= dist;
      dy /= dist;
      left.vx -= dx * force;
      left.vy -= dy * force;
      right.vx += dx * force;
      right.vy += dy * force;
    }
  }

  for (const edge of appState.topology.simEdges) {
    const from = index.get(edge.from);
    const to = index.get(edge.to);
    if (!from || !to) continue;
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const dist = Math.max(20, Math.sqrt(dx * dx + dy * dy));
    const target = 70 + (from.type === "rig" || to.type === "rig" ? 26 : 0);
    const force = (dist - target) * 0.0028;
    const nx = dx / dist;
    const ny = dy / dist;
    from.vx += nx * force;
    from.vy += ny * force;
    to.vx -= nx * force;
    to.vy -= ny * force;
  }

  for (const node of nodes) {
    node.vx += (node.anchorX - node.x) * 0.0046;
    node.vy += (node.anchorY - node.y) * 0.0046;
    node.vx *= 0.88;
    node.vy *= 0.88;
    node.x = clamp(node.x + node.vx, node.radius + 14, width - node.radius - 14);
    node.y = clamp(node.y + node.vy, node.radius + 14, height - node.radius - 14);
  }
}

function drawCanvasTopology() {
  const renderer = appState.topology.renderer;
  if (!renderer || !renderer.ctx) return;
  const ctx = renderer.ctx;
  const width = refs.topologyCanvas.clientWidth || 960;
  const height = refs.topologyCanvas.clientHeight || 520;
  ctx.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
  ctx.clearRect(0, 0, width, height);

  if (appState.topology.simNodes.length === 0) {
    ctx.fillStyle = "#7fa9bc";
    ctx.font = "14px IBM Plex Sans";
    ctx.fillText("Topology data will appear when the cockpit snapshot contains nodes.", 20, 34);
    return;
  }

  ctx.lineWidth = 1.15;
  for (const edge of appState.topology.simEdges) {
    const from = appState.topology.simNodes.find((node) => node.id === edge.from);
    const to = appState.topology.simNodes.find((node) => node.id === edge.to);
    if (!from || !to) continue;
    ctx.strokeStyle = edgeTouchesActive(edge) ? "rgba(248, 184, 74, 0.78)" : "rgba(77, 214, 255, 0.22)";
    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.lineTo(to.x, to.y);
    ctx.stroke();
  }

  for (const node of appState.topology.simNodes) {
    ctx.beginPath();
    ctx.fillStyle = topologyColor(node.type, node.state);
    ctx.shadowBlur = node.id === topologyActiveNodeId() ? 24 : 12;
    ctx.shadowColor = ctx.fillStyle;
    ctx.arc(node.x, node.y, node.radius + (node.id === topologyActiveNodeId() ? 2 : 0), 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.shadowBlur = 0;
}

function drawTopologyOverlay() {
  const ctx = appState.topology.overlay;
  if (!ctx) return;
  const width = refs.topologyOverlay.clientWidth || 960;
  const height = refs.topologyOverlay.clientHeight || 520;
  ctx.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
  ctx.clearRect(0, 0, width, height);

  if (appState.topology.simNodes.length === 0) return;

  const activeId = topologyActiveNodeId();
  for (const node of appState.topology.simNodes) {
    if (node.id !== activeId && node.id !== appState.topology.hoverId) continue;
    ctx.strokeStyle = node.id === appState.topology.hoverId ? "rgba(248, 184, 74, 0.95)" : "rgba(77, 214, 255, 0.95)";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(node.x, node.y, node.radius + 8, 0, Math.PI * 2);
    ctx.stroke();
  }

  ctx.font = "12px IBM Plex Sans";
  ctx.fillStyle = "#d9f4ff";
  for (const node of appState.topology.simNodes) {
    if (node.type === "issue" && appState.topology.simNodes.length > 18 && node.id !== activeId) continue;
    ctx.fillText(node.label || node.id, node.x + node.radius + 8, node.y + 4);
  }
}

function drawWebGlTopology() {
  const renderer = appState.topology.renderer;
  if (!renderer || !renderer.gl) return;
  const { gl, program, attributes, uniforms } = renderer;
  gl.clearColor(0.02, 0.07, 0.1, 1);
  gl.clear(gl.COLOR_BUFFER_BIT);
  gl.useProgram(program);
  gl.uniform2f(uniforms.uResolution, refs.topologyCanvas.clientWidth || 960, refs.topologyCanvas.clientHeight || 520);

  const index = new Map(appState.topology.simNodes.map((node) => [node.id, node]));
  const lineVertices = [];
  for (const edge of appState.topology.simEdges) {
    const from = index.get(edge.from);
    const to = index.get(edge.to);
    if (!from || !to) continue;
    const rgba = edgeTouchesActive(edge) ? [0.97, 0.72, 0.29, 0.82] : [0.3, 0.84, 1, 0.18];
    lineVertices.push(from.x, from.y, 1, ...rgba, to.x, to.y, 1, ...rgba);
  }

  if (lineVertices.length > 0) {
    gl.bindBuffer(gl.ARRAY_BUFFER, renderer.lineBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(lineVertices), gl.DYNAMIC_DRAW);
    gl.vertexAttribPointer(attributes.aPosition, 2, gl.FLOAT, false, 28, 0);
    gl.enableVertexAttribArray(attributes.aPosition);
    gl.vertexAttribPointer(attributes.aSize, 1, gl.FLOAT, false, 28, 8);
    gl.enableVertexAttribArray(attributes.aSize);
    gl.vertexAttribPointer(attributes.aColor, 4, gl.FLOAT, false, 28, 12);
    gl.enableVertexAttribArray(attributes.aColor);
    gl.drawArrays(gl.LINES, 0, lineVertices.length / 7);
  }

  const pointVertices = [];
  for (const node of appState.topology.simNodes) {
    const rgba = hexToRgba(topologyColor(node.type, node.state), node.id === topologyActiveNodeId() ? 1 : 0.92);
    pointVertices.push(node.x, node.y, node.radius * devicePixelRatio * (node.id === topologyActiveNodeId() ? 2 : 1.7), ...rgba);
  }
  gl.bindBuffer(gl.ARRAY_BUFFER, renderer.pointBuffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(pointVertices), gl.DYNAMIC_DRAW);
  gl.vertexAttribPointer(attributes.aPosition, 2, gl.FLOAT, false, 28, 0);
  gl.enableVertexAttribArray(attributes.aPosition);
  gl.vertexAttribPointer(attributes.aSize, 1, gl.FLOAT, false, 28, 8);
  gl.enableVertexAttribArray(attributes.aSize);
  gl.vertexAttribPointer(attributes.aColor, 4, gl.FLOAT, false, 28, 12);
  gl.enableVertexAttribArray(attributes.aColor);
  gl.drawArrays(gl.POINTS, 0, pointVertices.length / 7);
}

function renderTopologySidebar(topology) {
  const active = topologyActiveNode();
  if (!active) {
    refs.topologyFocus.innerHTML = `<div class="empty-state">Hover or click a node to inspect its live relationships.</div>`;
    refs.topologyList.innerHTML = "";
    return;
  }

  const relatedEdges = (topology.edges || []).filter((edge) => edge.from === active.id || edge.to === active.id);
  refs.topologyFocus.innerHTML = `
    <div class="topology-focus-title">${esc(active.label || active.id)}</div>
    <div class="topology-focus-meta">${esc([active.type, active.rig, active.state].filter(Boolean).join(" • "))}</div>
    <div class="topology-focus-detail">${esc(topologyNodeDetail(active, relatedEdges.length))}</div>
    ${renderTopologyNodeActions(active)}
  `;
  bindTopologyActions(refs.topologyFocus);

  refs.topologyList.innerHTML = relatedEdges.slice(0, 18).map((edge) => {
    const otherId = edge.from === active.id ? edge.to : edge.from;
    const other = (topology.nodes || []).find((node) => node.id === otherId);
    const activeClass = other && other.id === appState.topology.hoverId ? " active" : "";
    return `<div class="topology-item${activeClass}">${esc(edge.type)}: ${esc(other ? other.label : otherId)}</div>`;
  }).join("") || `<div class="empty-state">No direct relationships for this node yet.</div>`;
}

function topologyNodeDetail(node, edgeCount) {
  const details = [];
  if (node.metadata && node.metadata.role) details.push(node.metadata.role);
  if (node.metadata && node.metadata.title) details.push(node.metadata.title);
  if (node.metadata && node.metadata.detail) details.push(node.metadata.detail);
  if (node.metadata && node.metadata.evidence) details.push(snippet(node.metadata.evidence, 140));
  if (node.metadata && node.metadata.reason) details.push(node.metadata.reason);
  details.push(`${edgeCount} live link${edgeCount === 1 ? "" : "s"}`);
  return details.filter(Boolean).join(" · ");
}

function renderTopologyNodeActions(node) {
  const target = topologyNodeStreamTarget(node);
  if (!target) return "";
  const focusLabel = appState.focusTarget === target ? "Focused" : "Focus";
  return `
    <div class="topology-focus-actions">
      <button class="btn tiny ghost" data-focus-target="${escAttr(target)}">${focusLabel}</button>
      <button class="btn tiny ghost" data-peek-target="${escAttr(target)}">Peek</button>
    </div>
  `;
}

function bindTopologyActions(root) {
  root.querySelectorAll("[data-focus-target]").forEach((button) => {
    button.addEventListener("click", () => {
      appState.focusTarget = button.dataset.focusTarget;
      syncStreamTargets();
      renderStreamDeck();
      activateSection("streams");
    });
  });
  root.querySelectorAll("[data-peek-target]").forEach((button) => {
    button.addEventListener("click", () => peek(button.dataset.peekTarget));
  });
}

function topologyNodeStreamTarget(node) {
  return node && node.metadata && node.metadata.streamTarget ? node.metadata.streamTarget : "";
}

function topologyActiveNodeId() {
  return appState.topology.hoverId || appState.topology.selectedId;
}

function topologyActiveNode() {
  return appState.topology.simNodes.find((node) => node.id === topologyActiveNodeId()) || null;
}

function edgeTouchesActive(edge) {
  const activeId = topologyActiveNodeId();
  return Boolean(activeId && (edge.from === activeId || edge.to === activeId));
}

function handleTopologyPointerMove(event) {
  const point = topologyPointer(event);
  const nearest = findNearestTopologyNode(point.x, point.y);
  const nextId = nearest ? nearest.id : "";
  if (nextId !== appState.topology.hoverId) {
    appState.topology.hoverId = nextId;
    renderTopologySidebar(appState.cockpit.topology || { nodes: [], edges: [] });
  }
}

function handleTopologyPointerLeave() {
  if (appState.topology.hoverId) {
    appState.topology.hoverId = "";
    renderTopologySidebar(appState.cockpit.topology || { nodes: [], edges: [] });
  }
}

function handleTopologyPointerClick(event) {
  const point = topologyPointer(event);
  const nearest = findNearestTopologyNode(point.x, point.y);
  if (nearest) {
    appState.topology.selectedId = nearest.id;
    renderTopologySidebar(appState.cockpit.topology || { nodes: [], edges: [] });
  }
}

function topologyPointer(event) {
  const rect = refs.topologyOverlay.getBoundingClientRect();
  return {
    x: event.clientX - rect.left,
    y: event.clientY - rect.top,
  };
}

function findNearestTopologyNode(x, y) {
  let nearest = null;
  let best = 24;
  for (const node of appState.topology.simNodes) {
    const dist = Math.hypot(node.x - x, node.y - y);
    if (dist <= best) {
      nearest = node;
      best = dist;
    }
  }
  return nearest;
}

function createTopologyWebGlRenderer(gl) {
  const vertexShader = compileShader(gl, gl.VERTEX_SHADER, `
    attribute vec2 aPosition;
    attribute float aSize;
    attribute vec4 aColor;
    uniform vec2 uResolution;
    varying vec4 vColor;
    void main() {
      vec2 zeroToOne = aPosition / uResolution;
      vec2 clip = (zeroToOne * 2.0) - 1.0;
      gl_Position = vec4(clip * vec2(1.0, -1.0), 0.0, 1.0);
      gl_PointSize = aSize;
      vColor = aColor;
    }
  `);
  const fragmentShader = compileShader(gl, gl.FRAGMENT_SHADER, `
    precision mediump float;
    varying vec4 vColor;
    void main() {
      gl_FragColor = vColor;
    }
  `);
  if (!vertexShader || !fragmentShader) return null;
  const program = createProgram(gl, vertexShader, fragmentShader);
  if (!program) return null;
  gl.enable(gl.BLEND);
  gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
  return {
    gl,
    program,
    attributes: {
      aPosition: gl.getAttribLocation(program, "aPosition"),
      aSize: gl.getAttribLocation(program, "aSize"),
      aColor: gl.getAttribLocation(program, "aColor"),
    },
    uniforms: {
      uResolution: gl.getUniformLocation(program, "uResolution"),
    },
    lineBuffer: gl.createBuffer(),
    pointBuffer: gl.createBuffer(),
  };
}

function compileShader(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (gl.getShaderParameter(shader, gl.COMPILE_STATUS)) return shader;
  return null;
}

function createProgram(gl, vertexShader, fragmentShader) {
  const program = gl.createProgram();
  gl.attachShader(program, vertexShader);
  gl.attachShader(program, fragmentShader);
  gl.linkProgram(program);
  if (gl.getProgramParameter(program, gl.LINK_STATUS)) return program;
  return null;
}

function hexToRgba(hex, alpha = 1) {
  const normalized = String(hex || "#63aafc").replace("#", "");
  const safe = normalized.length === 3
    ? normalized.split("").map((part) => `${part}${part}`).join("")
    : normalized.padEnd(6, "0").slice(0, 6);
  return [
    parseInt(safe.slice(0, 2), 16) / 255,
    parseInt(safe.slice(2, 4), 16) / 255,
    parseInt(safe.slice(4, 6), 16) / 255,
    alpha,
  ];
}

function topologyColor(type, state) {
  if (type === "blocker" || state === "blocked") return "#e27070";
  if (type === "issue") return "#63aafc";
  if (type === "pr") return "#ad7cff";
  if (type === "rig") return "#d9a441";
  if (type === "queue") return "#d9a441";
  if (state === "alive" || state === "active") return "#79c66d";
  return "#63aafc";
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
  if (target === "president") return "President supervision loop";
  if (target === "mayor") return "Mayor command loop";
  const worker = appState.cockpit.workers.find((item) => item.stream && item.stream.target === target);
  if (!worker) return "Live worker pane";
  const detail = [worker.role];
  if (worker.rig) detail.push(worker.rig);
  if (worker.issue) detail.push(`#${worker.issue}`);
  return detail.join(" • ");
}

function rootStreamTarget() {
  return (appState.cockpit.agents || []).some((agent) => agent.name === "president") ? "president" : "mayor";
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

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
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

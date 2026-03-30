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
  desiredTargets: new Set(),
  streams: new Map(),
  sections: ["overview", "streams", "topology", "dispatch", "logs"],
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
  focusStream: document.getElementById("focusStream"),
  streamGrid: document.getElementById("streamGrid"),
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
  refs.refreshLogsBtn.addEventListener("click", loadLogs);
  refs.peekCloseBtn.addEventListener("click", closePeek);
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
    follow: true,
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
  const liveWorker = appState.cockpit.workers.find((worker) => worker.stream && worker.stream.available);
  return liveWorker ? liveWorker.stream.target : "mayor";
}

function syncStreamTargets() {
  const desired = new Set(["mayor"]);
  const workers = [...appState.cockpit.workers]
    .filter((worker) => worker.stream && worker.stream.available)
    .sort((left, right) => workerPriority(right) - workerPriority(left));

  if (appState.focusTarget) desired.add(appState.focusTarget);
  for (const worker of workers.slice(0, 4)) desired.add(worker.stream.target);

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
  const orderedTargets = Array.from(appState.desiredTargets);
  refs.streamSummary.textContent = `${orderedTargets.length} subscriptions`;
  refs.overviewHero.innerHTML = renderHeroStream(appState.focusTarget || "mayor");
  refs.focusStream.innerHTML = renderHeroStream(appState.focusTarget || "mayor");

  const others = orderedTargets.filter((target) => target !== appState.focusTarget);
  refs.streamGrid.innerHTML = others.map((target) => renderMiniStream(target)).join("");

  bindStreamActions(refs.focusStream);
  bindStreamActions(refs.streamGrid);
  bindStreamActions(refs.overviewHero);
}

function renderHeroStream(target) {
  const stream = streamFor(target);
  return `
    <article class="hero-card">
      <div class="stream-head">
        <div class="stream-title">
          <div class="stream-target">${esc(target)}</div>
          <div class="stream-meta">${esc(streamCaption(stream))}</div>
        </div>
        <div class="stream-actions">
          <span class="state-pill ${streamStateClass(stream)}">${esc(stream.state)}</span>
          <button class="btn tiny ghost" data-peek-target="${escAttr(target)}">Peek</button>
        </div>
      </div>
      <div class="stream-body" data-stream-target="${escAttr(target)}">${esc(stream.content || "Waiting for tmux stream data...")}</div>
    </article>
  `;
}

function renderMiniStream(target) {
  const stream = streamFor(target);
  return `
    <article class="stream-card">
      <div class="stream-head">
        <div class="stream-title">
          <div class="stream-target">${esc(target)}</div>
          <div class="stream-meta">${esc(streamCaption(stream))}</div>
        </div>
        <div class="stream-actions">
          <span class="state-pill ${streamStateClass(stream)}">${esc(stream.state)}</span>
          <button class="btn tiny ghost" data-focus-target="${escAttr(target)}">Focus</button>
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
    follow: true,
    lastEventAt: 0,
    session: "",
  };
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

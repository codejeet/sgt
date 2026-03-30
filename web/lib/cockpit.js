const path = require('path');
const fs = require('fs');

function readStateFile(filePath) {
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    const state = {};
    for (const line of content.split('\n')) {
      const eq = line.indexOf('=');
      if (eq > 0) {
        state[line.slice(0, eq)] = line.slice(eq + 1);
      }
    }
    return state;
  } catch {
    return null;
  }
}

function readDir(dir) {
  try {
    return fs.readdirSync(dir).filter((entry) => !entry.startsWith('.'));
  } catch {
    return [];
  }
}

function tryReadJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function parseStatus(raw) {
  const result = { agents: [], polecats: [], dogs: [], crew: [], mergeQueue: [] };
  let section = null;

  function setSectionFromHeader(line) {
    if (line.startsWith('=== Agents ===')) return 'agents';
    if (line.startsWith('=== Dogs ===')) return 'dogs';
    if (line.startsWith('=== Crew ===')) return 'crew';
    if (line.startsWith('=== Merge Queue')) return 'mergeQueue';
    if (line.startsWith('=== Polecats ===')) return 'polecats';

    const mh = line.match(/^╭─\s+(.+?)\s+─/);
    if (!mh) return null;
    const title = mh[1].trim();
    if (title === 'Agents') return 'agents';
    if (title === 'Dogs') return 'dogs';
    if (title === 'Crew') return 'crew';
    if (title.startsWith('Merge Queue')) return 'mergeQueue';
    if (title === 'Polecats') return 'polecats';
    return null;
  }

  for (const line of raw.split('\n')) {
    const maybe = setSectionFromHeader(line);
    if (maybe) {
      section = maybe;
      continue;
    }

    if (line.startsWith('»') || line.trim() === '') continue;
    if (line.trim() === 'none' || line.trim() === 'empty') continue;
    if (line.startsWith('1 polecat') || line.includes('polecat(s) tracked')) continue;

    if (section === 'agents') {
      const mLegacy = line.match(/^\s+(\S+):\s+(.+)$/);
      if (mLegacy) {
        result.agents.push({ name: mLegacy[1], status: mLegacy[2].trim() });
        continue;
      }

      const m = line.match(/^\s{2,}([^\s]+)\s{2,}(.+?)\s*$/);
      if (m) {
        const name = m[1].trim();
        const status = m[2].trim();
        if (!(name === 'last' && status.startsWith('heartbeat:'))) {
          result.agents.push({ name, status });
        }
        continue;
      }

      if (line.includes('last heartbeat:')) {
        const hb = line.match(/last heartbeat:\s+(.+)/);
        if (hb && result.agents.length > 0) {
          result.agents[result.agents.length - 1].heartbeat = hb[1].trim();
        }
      }
    } else if (section === 'polecats') {
      const pmLegacy = line.match(/^\s+(\S+)\s+\[(\w+)\]/);
      if (pmLegacy) {
        result.polecats.push({ name: pmLegacy[1], alive: pmLegacy[2] });
        continue;
      }
      if (result.polecats.length > 0) {
        const last = result.polecats[result.polecats.length - 1];
        const kv = line.match(/^\s+(\w+):\s+(.+)/);
        if (kv) {
          last[kv[1]] = kv[2].trim();
          continue;
        }
      }

      const pm = line.match(/^\s{2,}(\S+)\s+(alive|dead)\s{2,}#?(\d+)\s{2,}(.+)$/);
      if (pm) {
        result.polecats.push({
          name: pm[1],
          alive: pm[2],
          issue: `#${pm[3]}`,
          branch: pm[4].trim(),
        });
      }
    } else if (section === 'dogs') {
      const dm = line.match(/^\s+(\S+)\s+\[(\w+)\]\s+—\s+(.+)/);
      if (dm) {
        result.dogs.push({ name: dm[1], alive: dm[2], issue: dm[3] });
        continue;
      }

      const dn = line.match(/^\s{2,}(\S+)\s+(alive|dead)\s{2,}(.+)$/);
      if (dn) result.dogs.push({ name: dn[1], alive: dn[2], issue: dn[3].trim() });
    } else if (section === 'crew') {
      const cm = line.match(/^\s+(\S+)\s+\[(\w+)\]\s+—\s+(.+)/);
      if (cm) {
        result.crew.push({ name: cm[1], status: cm[2], detail: cm[3] });
        continue;
      }

      const cn = line.match(/^\s{2,}(\S+)\s+(\S+)\s{2,}(.+)$/);
      if (cn) result.crew.push({ name: cn[1], status: cn[2], detail: cn[3].trim() });
    } else if (section === 'mergeQueue') {
      const mm = line.match(/^\s+(\S+)\s+—\s+(.+)/);
      if (mm) {
        result.mergeQueue.push({ name: mm[1], detail: mm[2] });
        continue;
      }

      const mn = line.match(/^\s{2,}(\S+)\s{2,}(.+)$/);
      if (mn) result.mergeQueue.push({ name: mn[1], detail: mn[2].trim() });
    }
  }

  return result;
}

function listStateEntries(dir) {
  return readDir(dir)
    .map((name) => {
      const state = readStateFile(path.join(dir, name));
      return state ? { name, ...state } : null;
    })
    .filter(Boolean);
}

function readAcceptanceBlockers(configDir) {
  const blockersDir = path.join(configDir, 'acceptance-blockers');
  return readDir(blockersDir)
    .map((blockerId) => {
      const blockerDir = path.join(blockersDir, blockerId);
      const meta = readStateFile(path.join(blockerDir, 'blocker.env'));
      if (!meta) return null;
      const status = meta.STATUS || 'open';
      if (status !== 'open' && status !== 'needs-followup') return null;
      let evidence = '';
      try {
        evidence = fs.readFileSync(path.join(blockerDir, 'evidence.md'), 'utf8').trim();
      } catch {}
      return {
        id: meta.BLOCKER_ID || blockerId,
        rig: meta.RIG || '',
        status,
        title: meta.TITLE || 'Verified acceptance blocker',
        requester: meta.REQUESTING_AGENT_ID || 'unknown',
        createdAt: meta.CREATED_AT || '',
        updatedAt: meta.LAST_UPDATED_AT || meta.CREATED_AT || '',
        evidence,
      };
    })
    .filter(Boolean)
    .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
}

function mapById(items = []) {
  const mapped = new Map();
  for (const item of items) {
    if (!item || !item.id) continue;
    mapped.set(item.id, item);
  }
  return mapped;
}

function blockerAlertMessage(kind, blocker, context = {}) {
  const rig = blocker.rig || 'unknown rig';
  if (kind === 'blocker-opened') {
    return `${rig} blocker opened: ${blocker.title}`;
  }
  if (kind === 'blocker-followup') {
    return `${rig} blocker needs follow-up: ${blocker.title}`;
  }
  if (kind === 'blocker-resolved') {
    if (context.remainingRigBlockers === 0 && context.remainingTotalBlockers === 0) {
      return `${rig} blocker resolved. All acceptance blockers are clear.`;
    }
    if (context.remainingRigBlockers === 0) {
      return `${rig} blocker resolved. No open blockers remain on this rig.`;
    }
    return `${rig} blocker resolved: ${blocker.title}`;
  }
  return `${rig} blocker updated: ${blocker.title}`;
}

class BlockerAlertTracker {
  constructor({
    now = () => new Date().toISOString(),
    historyLimit = 24,
    voice = {},
  } = {}) {
    this.now = now;
    this.historyLimit = historyLimit;
    this.voice = {
      enabled: Boolean(voice.enabled),
      eventKinds: Array.isArray(voice.eventKinds) ? voice.eventKinds : [],
      rateLimitMs: Number(voice.rateLimitMs) || 0,
      ...voice,
    };
    this.previousBlockers = new Map();
    this.events = [];
    this.primed = false;
    this.lastVoiceAtMs = 0;
  }

  observe(blockers = []) {
    const nextBlockers = mapById(blockers);
    if (!this.primed) {
      this.previousBlockers = nextBlockers;
      this.primed = true;
      return this.listEvents();
    }

    const createdAt = this.now();
    const createdMs = Date.parse(createdAt) || Date.now();
    const rigCounts = new Map();
    for (const blocker of blockers) {
      const key = blocker.rig || '';
      rigCounts.set(key, (rigCounts.get(key) || 0) + 1);
    }

    for (const [id, blocker] of nextBlockers.entries()) {
      const previous = this.previousBlockers.get(id);
      if (!previous) {
        this.pushEvent({
          id: `alert:${id}:opened:${createdAt}`,
          blockerId: id,
          kind: 'blocker-opened',
          severity: 'critical',
          createdAt,
          blocker,
          remainingRigBlockers: rigCounts.get(blocker.rig || '') || 0,
          remainingTotalBlockers: blockers.length,
        }, createdMs);
        continue;
      }
      if (previous.status !== blocker.status) {
        this.pushEvent({
          id: `alert:${id}:status:${createdAt}`,
          blockerId: id,
          kind: blocker.status === 'needs-followup' ? 'blocker-followup' : 'blocker-opened',
          severity: blocker.status === 'needs-followup' ? 'warning' : 'critical',
          createdAt,
          blocker,
          remainingRigBlockers: rigCounts.get(blocker.rig || '') || 0,
          remainingTotalBlockers: blockers.length,
        }, createdMs);
      }
    }

    for (const [id, blocker] of this.previousBlockers.entries()) {
      if (nextBlockers.has(id)) continue;
      this.pushEvent({
        id: `alert:${id}:resolved:${createdAt}`,
        blockerId: id,
        kind: 'blocker-resolved',
        severity: 'good',
        createdAt,
        blocker,
        remainingRigBlockers: rigCounts.get(blocker.rig || '') || 0,
        remainingTotalBlockers: blockers.length,
      }, createdMs);
    }

    this.previousBlockers = nextBlockers;
    this.events = this.events
      .sort((left, right) => String(right.createdAt).localeCompare(String(left.createdAt)))
      .slice(0, this.historyLimit);
    return this.listEvents();
  }

  pushEvent(event, createdMs) {
    const voice = this.computeVoice(event, createdMs);
    this.events.unshift({
      id: event.id,
      blockerId: event.blockerId,
      kind: event.kind,
      severity: event.severity,
      createdAt: event.createdAt,
      rig: event.blocker.rig || '',
      title: event.blocker.title || 'Verified acceptance blocker',
      status: event.blocker.status || '',
      requester: event.blocker.requester || 'unknown',
      message: blockerAlertMessage(event.kind, event.blocker, event),
      evidence: event.blocker.evidence || '',
      voice,
    });
  }

  computeVoice(event, createdMs) {
    const text = blockerAlertMessage(event.kind, event.blocker, event);
    if (!this.voice.enabled) {
      return { enabled: false, eligible: false, reason: 'not-configured', text };
    }
    if (!this.voice.eventKinds.includes(event.kind)) {
      return { enabled: true, eligible: false, reason: 'event-disabled', text };
    }
    if (this.voice.rateLimitMs > 0 && this.lastVoiceAtMs > 0 && createdMs - this.lastVoiceAtMs < this.voice.rateLimitMs) {
      return { enabled: true, eligible: false, reason: 'rate-limited', text };
    }
    this.lastVoiceAtMs = createdMs;
    return { enabled: true, eligible: true, reason: 'ready', text };
  }

  listEvents() {
    return this.events.map((event) => ({ ...event }));
  }

  getEvent(alertId) {
    return this.events.find((event) => event.id === alertId) || null;
  }
}

function readRecentLogLines(logPath, maxLines) {
  try {
    const content = fs.readFileSync(logPath, 'utf8');
    return content
      .split('\n')
      .filter((line) => line.trim())
      .slice(-maxLines);
  } catch {
    return [];
  }
}

function normalizeAgent(agent) {
  const normalized = {
    name: agent.name,
    status: agent.status,
    rig: agent.rig || '',
    heartbeat: agent.heartbeat || null,
  };
  if (agent.lock) normalized.lock = agent.lock;
  if (agent.last_exit) normalized.lastExit = agent.last_exit;
  if (agent.notify_warning) normalized.notifyWarning = agent.notify_warning;
  if (agent.decision_log_warning) normalized.decisionLogWarning = agent.decision_log_warning;
  if (agent.review_watchdog) normalized.reviewWatchdog = agent.review_watchdog;
  return normalized;
}

function normalizeWorker(worker, role) {
  const session = worker.session || '';
  const target = role === 'polecat' ? worker.name : `${role}/${worker.name}`;
  return {
    id: `${role}:${worker.name}`,
    name: worker.name,
    role,
    status: worker.status || worker.alive || 'unknown',
    rig: worker.rig || '',
    issue: worker.issue ? String(worker.issue).replace(/^#/, '') : '',
    branch: worker.branch || '',
    repo: worker.repo || '',
    pr: worker.pr || {},
    warning: worker.warning || '',
    runtime: worker.runtime || null,
    session,
    stream: {
      target,
      available: Boolean(session || role !== 'dog'),
      freshness: session ? 'live' : 'unavailable',
    },
  };
}

function parseQueueDetail(detail = '') {
  const text = String(detail || '');
  const prMatch = text.match(/\bPR#(\d+)\b/i);
  const issueMatch = text.match(/\b(?:issue|issues?)#(\d+)\b/i);
  const rigMatch = text.match(/\b([a-z0-9_-]+)\s*$/i);
  return {
    prNumber: prMatch ? prMatch[1] : '',
    issueNumber: issueMatch ? issueMatch[1] : '',
    rig: rigMatch ? rigMatch[1] : '',
  };
}

function buildTopology(snapshot) {
  const nodeMap = new Map();
  const edgeMap = new Map();

  function addNode(node) {
    if (!node || !node.id) return;
    const existing = nodeMap.get(node.id) || {};
    nodeMap.set(node.id, {
      ...existing,
      ...node,
      metadata: {
        ...(existing.metadata || {}),
        ...(node.metadata || {}),
      },
    });
  }

  function addEdge(edge) {
    if (!edge || !edge.from || !edge.to || !edge.type) return;
    const id = `${edge.from}|${edge.to}|${edge.type}`;
    edgeMap.set(id, {
      id,
      label: edge.type,
      ...edge,
    });
  }

  addNode({
    id: 'agent:mayor',
    type: 'agent',
    label: 'Mayor',
    state: snapshot.agents.some((agent) => agent.name === 'mayor' && String(agent.status).startsWith('on')) ? 'active' : 'idle',
    metadata: {
      role: 'mayor',
    },
  });

  for (const agent of snapshot.agents || []) {
    if (!agent || !agent.name || agent.name === 'mayor') continue;
    const agentId = `agent:${agent.name}`;
    addNode({
      id: agentId,
      type: 'agent',
      label: agent.name,
      state: agent.status || 'unknown',
      rig: agent.rig || '',
      metadata: {
        heartbeat: agent.heartbeat || null,
      },
    });
    if (agent.rig) {
      addEdge({ from: 'agent:mayor', to: `rig:${agent.rig}`, type: 'oversees' });
      addEdge({ from: `rig:${agent.rig}`, to: agentId, type: 'supports' });
    }
  }

  for (const rig of snapshot.rigs || []) {
    const rigId = `rig:${rig.name}`;
    addNode({
      id: rigId,
      type: 'rig',
      label: rig.name,
      state: rig.state || 'unknown',
      rig: rig.name,
      metadata: {
        repo: rig.repo || '',
        blockers: rig.blockers || 0,
        activeWorkers: rig.activeWorkers || 0,
        mergeQueue: rig.mergeQueue || 0,
        hibernationMode: rig.hibernationMode || 'none',
        reason: rig.reason || '',
      },
    });
    addEdge({ from: 'agent:mayor', to: rigId, type: 'oversees' });
  }

  for (const worker of snapshot.workers || []) {
    const rigName = worker.rig || 'unknown';
    const rigId = `rig:${rigName}`;
    const workerNode = `worker:${worker.id}`;
    addNode({
      id: workerNode,
      type: worker.role,
      label: worker.name,
      state: worker.status || 'unknown',
      rig: worker.rig || '',
      metadata: {
        issue: worker.issue || '',
        branch: worker.branch || '',
        repo: worker.repo || '',
        pr: worker.pr || {},
        warning: worker.warning || '',
        session: worker.session || '',
      },
    });
    if (worker.rig) addEdge({ from: rigId, to: workerNode, type: 'runs' });

    if (worker.issue) {
      const issueNode = `issue:${rigName}:${worker.issue}`;
      addNode({
        id: issueNode,
        type: 'issue',
        label: `#${worker.issue}`,
        state: worker.status === 'alive' ? 'active' : 'open',
        rig: worker.rig || '',
        metadata: {
          branch: worker.branch || '',
          worker: worker.name,
        },
      });
      addEdge({ from: rigId, to: issueNode, type: 'tracks' });
      addEdge({ from: workerNode, to: issueNode, type: 'works-on' });
    }

    if (worker.pr && worker.pr.number) {
      const prNode = `pr:${rigName}:${worker.pr.number}`;
      addNode({
        id: prNode,
        type: 'pr',
        label: `PR #${worker.pr.number}`,
        state: worker.pr.state || 'open',
        rig: worker.rig || '',
        metadata: {
          title: worker.pr.title || '',
          worker: worker.name,
        },
      });
      addEdge({ from: workerNode, to: prNode, type: 'owns' });
      if (worker.issue) addEdge({ from: prNode, to: `issue:${rigName}:${worker.issue}`, type: 'resolves' });
    }
  }

  for (const blocker of snapshot.blockers || []) {
    const blockerNode = `blocker:${blocker.id}`;
    addNode({
      id: blockerNode,
      type: 'blocker',
      label: blocker.title,
      state: blocker.status || 'open',
      rig: blocker.rig || '',
      metadata: {
        requester: blocker.requester || '',
        createdAt: blocker.createdAt || '',
        updatedAt: blocker.updatedAt || '',
        evidence: blocker.evidence || '',
      },
    });
    if (blocker.rig) addEdge({ from: `rig:${blocker.rig}`, to: blockerNode, type: 'blocked-by' });
  }

  for (const item of snapshot.queue.items || []) {
    const queueNode = `queue:${item.name}`;
    const parsed = parseQueueDetail(item.detail || '');
    addNode({
      id: queueNode,
      type: 'queue',
      label: item.name,
      state: 'queued',
      rig: parsed.rig || '',
      metadata: {
        detail: item.detail || '',
        prNumber: parsed.prNumber,
        issueNumber: parsed.issueNumber,
      },
    });

    if (parsed.rig) addEdge({ from: `rig:${parsed.rig}`, to: queueNode, type: 'queues' });
    if (parsed.prNumber) {
      const prNode = `pr:${parsed.rig || 'unknown'}:${parsed.prNumber}`;
      addNode({
        id: prNode,
        type: 'pr',
        label: `PR #${parsed.prNumber}`,
        state: 'queued',
        rig: parsed.rig || '',
        metadata: {
          title: item.detail || '',
        },
      });
      addEdge({ from: queueNode, to: prNode, type: 'contains' });
    }
    if (parsed.issueNumber) {
      const issueNode = `issue:${parsed.rig || 'unknown'}:${parsed.issueNumber}`;
      addNode({
        id: issueNode,
        type: 'issue',
        label: `#${parsed.issueNumber}`,
        state: 'queued',
        rig: parsed.rig || '',
      });
      addEdge({ from: queueNode, to: issueNode, type: 'waiting-on' });
    }
  }

  return {
    nodes: Array.from(nodeMap.values()),
    edges: Array.from(edgeMap.values()),
  };
}

function buildRigMap({ rigs, mayorRigs, workers, blockers, mergeQueue }) {
  const rigMap = new Map();

  for (const rig of rigs) {
    rigMap.set(rig.name, {
      name: rig.name,
      repo: rig.repo || '',
      polecats: typeof rig.polecats === 'number' ? rig.polecats : 0,
      witness: rig.witness || '',
      refinery: rig.refinery || '',
      state: 'unknown',
      reason: '',
      hibernationMode: 'none',
      lastMeaningfulAt: '',
      lastWakeAt: '',
      blockers: 0,
      activeWorkers: 0,
      mergeQueue: 0,
    });
  }

  for (const mayorRig of mayorRigs) {
    const existing = rigMap.get(mayorRig.rig) || {
      name: mayorRig.rig,
      repo: '',
      polecats: 0,
      witness: '',
      refinery: '',
      blockers: 0,
      activeWorkers: 0,
      mergeQueue: 0,
    };
    rigMap.set(mayorRig.rig, {
      ...existing,
      state: mayorRig.state || existing.state || 'unknown',
      reason: mayorRig.reason || '',
      hibernationMode: mayorRig.hibernation_mode || 'none',
      lastMeaningfulAt: mayorRig.last_meaningful_at || '',
      lastWakeAt: mayorRig.last_wake_at || '',
    });
  }

  for (const worker of workers) {
    if (!worker.rig) continue;
    const existing = rigMap.get(worker.rig) || {
      name: worker.rig,
      repo: worker.repo || '',
      polecats: worker.role === 'polecat' ? 1 : 0,
      witness: '',
      refinery: '',
      state: 'unknown',
      reason: '',
      hibernationMode: 'none',
      lastMeaningfulAt: '',
      lastWakeAt: '',
      blockers: 0,
      activeWorkers: 0,
      mergeQueue: 0,
    };
    existing.activeWorkers += 1;
    rigMap.set(worker.rig, existing);
  }

  for (const blocker of blockers) {
    if (!blocker.rig) continue;
    const existing = rigMap.get(blocker.rig) || {
      name: blocker.rig,
      repo: '',
      polecats: 0,
      witness: '',
      refinery: '',
      state: 'unknown',
      reason: '',
      hibernationMode: 'none',
      lastMeaningfulAt: '',
      lastWakeAt: '',
      blockers: 0,
      activeWorkers: 0,
      mergeQueue: 0,
    };
    existing.blockers += 1;
    rigMap.set(blocker.rig, existing);
  }

  for (const item of mergeQueue) {
    const detail = `${item.name || ''} ${item.detail || ''}`;
    const match = detail.match(/\b([a-z0-9_-]+)\b$/i);
    if (!match) continue;
    const rig = match[1];
    const existing = rigMap.get(rig);
    if (!existing) continue;
    existing.mergeQueue += 1;
    rigMap.set(rig, existing);
  }

  return Array.from(rigMap.values()).sort((a, b) => a.name.localeCompare(b.name));
}

function buildCockpitSnapshot({
  statusJson,
  statusRaw = '',
  rigs = [],
  blockers = [],
  alerts = [],
  recentLogs = [],
  version = '1',
  voice = {},
}) {
  const fallbackParsed = parseStatus(statusRaw || '');
  const statusData = statusJson || {};
  const agents = Array.isArray(statusData.agents)
    ? statusData.agents.map(normalizeAgent)
    : fallbackParsed.agents.map((agent) => ({
        name: agent.name,
        status: agent.status,
        heartbeat: agent.heartbeat || null,
        rig: '',
      }));

  const polecats = Array.isArray(statusData.polecats)
    ? statusData.polecats.map((worker) => normalizeWorker(worker, 'polecat'))
    : (fallbackParsed.polecats || []).map((worker) =>
        normalizeWorker(
          {
            name: worker.name,
            status: worker.alive,
            issue: String(worker.issue || '').replace(/^#/, ''),
            branch: worker.branch || '',
          },
          'polecat'
        )
      );
  const dogs = Array.isArray(statusData.dogs) ? statusData.dogs.map((worker) => normalizeWorker(worker, 'dog')) : [];
  const workers = [...polecats, ...dogs];
  const mergeQueue = Array.isArray(statusData.merge_queue) ? statusData.merge_queue : fallbackParsed.mergeQueue || [];
  const rigsView = buildRigMap({
    rigs,
    mayorRigs: Array.isArray(statusData.mayor_rigs) ? statusData.mayor_rigs : [],
    workers,
    blockers,
    mergeQueue,
  });

  const snapshot = {
    meta: {
      serverTime: new Date().toISOString(),
      version,
      source: 'sgt-web',
      featureFlags: {
        blockers: true,
        tmuxStreaming: true,
        normalizedSnapshot: true,
        voiceAnnouncements: Boolean(voice.enabled),
      },
      voice: {
        enabled: Boolean(voice.enabled),
        configured: Boolean(voice.configured),
        eventKinds: Array.isArray(voice.eventKinds) ? voice.eventKinds : [],
        rateLimitSeconds: Number(voice.rateLimitSeconds) || 0,
      },
    },
    agents,
    rigs: rigsView,
    workers,
    queue: {
      items: mergeQueue,
      summary: {
        total: mergeQueue.length,
      },
    },
    blockers,
    alerts,
    logs: {
      lines: recentLogs,
      total: recentLogs.length,
    },
  };
  snapshot.topology = buildTopology(snapshot);
  return snapshot;
}

function resolveStreamSession(target, { configDir }) {
  if (!target) return null;
  if (target === 'deacon') return { session: 'sgt-deacon', target };
  if (target === 'mayor') return { session: 'sgt-mayor', target };
  if (target.startsWith('mayor/')) return { session: `sgt-mayor-${target.slice('mayor/'.length)}`, target };
  if (target.startsWith('witness/')) return { session: `sgt-witness-${target.slice('witness/'.length)}`, target };
  if (target.startsWith('refinery/')) return { session: `sgt-refinery-${target.slice('refinery/'.length)}`, target };
  if (target.startsWith('crew/')) return { session: `sgt-crew-${target.slice('crew/'.length)}`, target };
  if (target.startsWith('dog/')) return { session: `sgt-${target.slice('dog/'.length)}`, target };

  const polecatState = readStateFile(path.join(configDir, 'polecats', target));
  if (polecatState && polecatState.SESSION) {
    return { session: polecatState.SESSION, target };
  }

  const dogState = readStateFile(path.join(configDir, 'dogs', target));
  if (dogState && dogState.SESSION) {
    return { session: dogState.SESSION, target: `dog/${target}` };
  }

  return null;
}

function computeStreamDelta(previousContent, nextContent) {
  if (!previousContent) {
    return { changed: true, reset: true, chunk: nextContent };
  }
  if (nextContent === previousContent) {
    return { changed: false, reset: false, chunk: '' };
  }
  if (nextContent.startsWith(previousContent)) {
    return {
      changed: true,
      reset: false,
      chunk: nextContent.slice(previousContent.length),
    };
  }
  return { changed: true, reset: true, chunk: nextContent };
}

class TmuxStreamManager {
  constructor({ captureTarget, send, pollInterval = 1000, staleThresholdMs = 4000, now = () => Date.now() }) {
    this.captureTarget = captureTarget;
    this.send = send;
    this.pollInterval = pollInterval;
    this.staleThresholdMs = staleThresholdMs;
    this.now = now;
    this.targets = new Map();
    this.wsTargets = new Map();
  }

  subscribe(ws, target) {
    if (!target) return;
    let entry = this.targets.get(target);
    let isNew = false;
    if (!entry) {
      isNew = true;
      entry = {
        subscribers: new Set(),
        timer: null,
        lastContent: '',
        lastSuccessAt: 0,
        state: 'opening',
      };
      this.targets.set(target, entry);
    }
    entry.subscribers.add(ws);
    const wsTargets = this.wsTargets.get(ws) || new Set();
    wsTargets.add(target);
    this.wsTargets.set(ws, wsTargets);
    if (isNew) {
      entry.timer = setInterval(() => {
        this.tick(target).catch(() => {});
      }, this.pollInterval);
      this.tick(target).catch(() => {});
    }
  }

  unsubscribe(ws, target) {
    const entry = this.targets.get(target);
    if (!entry) return;
    entry.subscribers.delete(ws);
    const wsTargets = this.wsTargets.get(ws);
    if (wsTargets) {
      wsTargets.delete(target);
      if (wsTargets.size === 0) this.wsTargets.delete(ws);
    }
    if (entry.subscribers.size === 0) {
      clearInterval(entry.timer);
      this.targets.delete(target);
      this.send(null, { type: 'stream/close', target, reason: 'unsubscribed' });
    }
  }

  unsubscribeAll(ws) {
    const targets = this.wsTargets.get(ws);
    if (!targets) return;
    for (const target of Array.from(targets)) {
      this.unsubscribe(ws, target);
    }
  }

  async tick(target) {
    const entry = this.targets.get(target);
    if (!entry) return;
    let capture;
    try {
      capture = await this.captureTarget(target);
    } catch {
      capture = { available: false, reason: 'capture-failed' };
    }

    if (!capture || !capture.available) {
      const nowMs = this.now();
      const isStale = entry.lastSuccessAt > 0 && nowMs - entry.lastSuccessAt >= this.staleThresholdMs;
      if (isStale && entry.state !== 'stale') {
        entry.state = 'stale';
        this.send(entry.subscribers, {
          type: 'stream/stale',
          target,
          reason: capture && capture.reason ? capture.reason : 'session-unavailable',
          at: new Date(nowMs).toISOString(),
        });
      }
      return;
    }

    const delta = computeStreamDelta(entry.lastContent, capture.content);
    const nowMs = this.now();
    entry.lastSuccessAt = nowMs;
    if (entry.state !== 'live') {
      entry.state = 'live';
      this.send(entry.subscribers, {
        type: 'stream/open',
        target,
        session: capture.session || '',
        at: new Date(nowMs).toISOString(),
      });
    }
    if (delta.changed) {
      entry.lastContent = capture.content;
      this.send(entry.subscribers, {
        type: 'stream/data',
        target,
        session: capture.session || '',
        at: new Date(nowMs).toISOString(),
        reset: delta.reset,
        chunk: delta.chunk,
      });
    }
  }
}

module.exports = {
  BlockerAlertTracker,
  TmuxStreamManager,
  buildCockpitSnapshot,
  computeStreamDelta,
  listStateEntries,
  parseStatus,
  readAcceptanceBlockers,
  readDir,
  readRecentLogLines,
  readStateFile,
  resolveStreamSession,
  tryReadJson,
};

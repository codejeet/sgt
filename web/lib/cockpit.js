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
    session,
    stream: {
      target,
      available: Boolean(session || role !== 'dog'),
      freshness: session ? 'live' : 'unavailable',
    },
  };
}

function buildTopology(snapshot) {
  const nodes = [];
  const edges = [];
  const seenNodes = new Map();
  const seenEdges = new Set();

  function upsertNode(node) {
    if (!node || !node.id) return node;
    const existing = seenNodes.get(node.id) || {};
    const merged = { ...existing, ...node };
    seenNodes.set(node.id, merged);
    return merged;
  }

  function addEdge(edge) {
    if (!edge || !edge.from || !edge.to || !edge.type) return;
    const key = `${edge.from}|${edge.to}|${edge.type}`;
    if (seenEdges.has(key)) return;
    seenEdges.add(key);
    edges.push(edge);
  }

  upsertNode({ id: 'mayor', type: 'agent', label: 'Mayor', state: 'active' });
  for (const rig of snapshot.rigs) {
    upsertNode({
      id: `rig:${rig.name}`,
      type: 'rig',
      label: rig.name,
      state: rig.state,
      detail: rig.reason || '',
    });
    addEdge({ from: 'mayor', to: `rig:${rig.name}`, type: 'oversees' });
  }

  for (const worker of snapshot.workers) {
    const workerNode = `worker:${worker.id}`;
    upsertNode({
      id: workerNode,
      type: worker.role,
      label: worker.name,
      state: worker.status,
      rig: worker.rig || '',
      detail: worker.branch || '',
    });
    if (worker.rig) addEdge({ from: `rig:${worker.rig}`, to: workerNode, type: 'runs' });
    if (worker.issue) {
      const issueNode = `issue:${worker.rig || 'unknown'}:${worker.issue}`;
      upsertNode({
        id: issueNode,
        type: 'issue',
        label: `#${worker.issue}`,
        state: worker.status === 'alive' ? 'active' : 'open',
        rig: worker.rig || '',
        detail: worker.branch || '',
      });
      addEdge({ from: workerNode, to: issueNode, type: 'tracks' });
    }
    if (worker.pr && worker.pr.number) {
      const prNode = `pr:${worker.rig || 'unknown'}:${worker.pr.number}`;
      upsertNode({
        id: prNode,
        type: 'pr',
        label: `PR #${worker.pr.number}`,
        state: worker.pr.state || 'open',
        rig: worker.rig || '',
        detail: worker.pr.title || '',
      });
      addEdge({ from: workerNode, to: prNode, type: 'owns' });
      if (worker.issue) {
        addEdge({
          from: prNode,
          to: `issue:${worker.rig || 'unknown'}:${worker.issue}`,
          type: 'addresses',
        });
      }
    }
  }

  for (const blocker of snapshot.blockers) {
    const blockerNode = `blocker:${blocker.id}`;
    upsertNode({
      id: blockerNode,
      type: 'blocker',
      label: blocker.title,
      state: blocker.status,
      rig: blocker.rig || '',
      detail: blocker.requester || '',
    });
    if (blocker.rig) addEdge({ from: `rig:${blocker.rig}`, to: blockerNode, type: 'blocked-by' });
  }

  for (const item of snapshot.queue.items) {
    const queueNode = `queue:${item.name}`;
    const detail = `${item.name || ''} ${item.detail || ''}`;
    const prMatch = detail.match(/PR#(\d+)/i);
    const rigMatch = detail.match(/\b([a-z0-9_-]+)\b$/i);
    upsertNode({
      id: queueNode,
      type: 'queue',
      label: item.name,
      state: 'queued',
      rig: rigMatch ? rigMatch[1] : '',
      detail: item.detail || '',
    });
    if (prMatch) {
      const prNode = `pr:${rigMatch ? rigMatch[1] : 'unknown'}:${prMatch[1]}`;
      upsertNode({
        id: prNode,
        type: 'pr',
        label: `PR #${prMatch[1]}`,
        state: 'queued',
        rig: rigMatch ? rigMatch[1] : '',
        detail: item.detail || '',
      });
      addEdge({ from: queueNode, to: prNode, type: 'queues' });
    }
    if (rigMatch) {
      upsertNode({ id: `rig:${rigMatch[1]}`, type: 'rig', label: rigMatch[1], state: 'active' });
      addEdge({ from: `rig:${rigMatch[1]}`, to: queueNode, type: 'feeds' });
    }
  }

  nodes.push(...Array.from(seenNodes.values()));
  nodes.sort((left, right) => left.id.localeCompare(right.id));
  edges.sort((left, right) => {
    const a = `${left.type}:${left.from}:${left.to}`;
    const b = `${right.type}:${right.from}:${right.to}`;
    return a.localeCompare(b);
  });
  return { nodes, edges };
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
  recentLogs = [],
  version = '1',
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
  TmuxStreamManager,
  buildCockpitSnapshot,
  buildTopology,
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

const express = require('express');
const { WebSocketServer } = require('ws');
const http = require('http');
const path = require('path');
const fs = require('fs');
const { execFile } = require('child_process');

const {
  TmuxStreamManager,
  buildCockpitSnapshot,
  listStateEntries,
  parseStatus,
  readAcceptanceBlockers,
  readRecentLogLines,
  resolveStreamSession,
  tryReadJson,
} = require('./lib/cockpit');

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

const PORT = process.env.SGT_WEB_PORT || 4747;
const SGT_ROOT = process.env.SGT_ROOT || path.join(process.env.HOME, 'sgt');
const SGT_BIN = process.env.SGT_BIN || path.join(SGT_ROOT, 'sgt');
const SGT_CONFIG = path.join(SGT_ROOT, '.sgt');
const SGT_LOG = path.join(SGT_ROOT, 'sgt.log');
const COCKPIT_VERSION = '2026-03-30';
const WS_INTERVAL = 3000;
const WS_PING_INTERVAL = 15000;
const WS_PONG_GRACE = 35000;
const LOG_TAIL_LINES = 120;

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

function runSgt(args) {
  return new Promise((resolve, reject) => {
    execFile(SGT_BIN, args, { timeout: 15000, env: { ...process.env, SGT_ROOT } }, (err, stdout, stderr) => {
      if (err) {
        reject(new Error(stderr || err.message));
      } else {
        resolve(stdout);
      }
    });
  });
}

async function runCommand(command, args) {
  return new Promise((resolve, reject) => {
    execFile(command, args, { timeout: 5000, env: process.env }, (err, stdout, stderr) => {
      if (err) {
        reject(new Error(stderr || err.message));
      } else {
        resolve(stdout);
      }
    });
  });
}

async function readStatusBundle() {
  let statusRaw = '';
  let statusJson = null;

  try {
    statusRaw = await runSgt(['status', '--json']);
    statusJson = JSON.parse(statusRaw);
  } catch {
    statusRaw = await runSgt(['status']);
  }

  return { statusRaw, statusJson };
}

async function readRigs() {
  try {
    const output = await runSgt(['rig', 'list']);
    const rigs = [];
    const lines = output.split('\n');
    for (let i = 0; i < lines.length; i += 1) {
      const match = lines[i].match(/^\s+(\S+)\s+(https?:\/\/.+)$/);
      if (!match) continue;
      const rig = { name: match[1], repo: match[2] };
      if (i + 1 < lines.length) {
        const detail = lines[i + 1].match(/polecats:\s*(\d+)\s+witness:\s*(\w+)\s+refinery:\s*(\w+)/);
        if (detail) {
          rig.polecats = Number(detail[1]);
          rig.witness = detail[2];
          rig.refinery = detail[3];
        }
      }
      rigs.push(rig);
    }
    return rigs;
  } catch {
    return [];
  }
}

async function buildSnapshot() {
  const [{ statusRaw, statusJson }, rigs] = await Promise.all([readStatusBundle(), readRigs()]);
  return buildCockpitSnapshot({
    statusJson,
    statusRaw,
    rigs,
    blockers: readAcceptanceBlockers(SGT_CONFIG),
    recentLogs: readRecentLogLines(SGT_LOG, LOG_TAIL_LINES),
    version: COCKPIT_VERSION,
  });
}

function toLegacyStatusPayload(snapshot) {
  return {
    agents: snapshot.agents.map((agent) => ({
      name: agent.name,
      status: agent.status,
      heartbeat: agent.heartbeat || undefined,
    })),
    polecats: snapshot.workers
      .filter((worker) => worker.role === 'polecat')
      .map((worker) => ({
        name: worker.name,
        alive: worker.status,
        issue: worker.issue ? `#${worker.issue}` : '',
        branch: worker.branch,
        rig: worker.rig,
        pr: worker.pr && worker.pr.number ? `#${worker.pr.number}` : '',
      })),
    dogs: snapshot.workers
      .filter((worker) => worker.role === 'dog')
      .map((worker) => ({
        name: worker.name,
        alive: worker.status,
        issue: worker.issue ? `#${worker.issue}` : '',
        rig: worker.rig,
      })),
    mergeQueue: snapshot.queue.items.map((item) => ({
      name: item.name || '',
      detail: item.detail || '',
    })),
  };
}

function safeSend(ws, obj) {
  if (!ws || ws.readyState !== 1) return;
  try {
    ws.send(JSON.stringify(obj));
  } catch {}
}

function safeSendMany(subscribers, obj) {
  if (!subscribers) return;
  for (const ws of subscribers) {
    safeSend(ws, obj);
  }
}

const streamManager = new TmuxStreamManager({
  send: (subscribers, message) => safeSendMany(subscribers, message),
  captureTarget: async (target) => {
    const resolved = resolveStreamSession(target, { configDir: SGT_CONFIG });
    if (!resolved) {
      return { available: false, reason: 'unknown-target' };
    }
    try {
      const output = await runCommand('tmux', ['capture-pane', '-t', resolved.session, '-p', '-S', '-200']);
      return { available: true, session: resolved.session, content: output };
    } catch {
      return { available: false, reason: 'session-unavailable' };
    }
  },
});

app.get('/api/status', async (req, res) => {
  try {
    const { statusRaw, statusJson } = await readStatusBundle();
    res.json({ raw: statusRaw, parsed: statusJson || parseStatus(statusRaw) });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/cockpit', async (req, res) => {
  try {
    res.json(await buildSnapshot());
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/rigs', async (req, res) => {
  res.json(await readRigs());
});

app.get('/api/polecats', (req, res) => {
  res.json(listStateEntries(path.join(SGT_CONFIG, 'polecats')));
});

app.get('/api/dogs', (req, res) => {
  res.json(listStateEntries(path.join(SGT_CONFIG, 'dogs')));
});

app.get('/api/merge-queue', (req, res) => {
  res.json(listStateEntries(path.join(SGT_CONFIG, 'merge-queue')));
});

app.get('/api/blockers', (req, res) => {
  res.json(readAcceptanceBlockers(SGT_CONFIG));
});

app.get('/api/peek/:target', async (req, res) => {
  try {
    const output = await runSgt(['peek', req.params.target]);
    res.json({ output });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/sling', async (req, res) => {
  const { rig, task, labels, convoy } = req.body;
  if (!rig || !task) {
    res.status(400).json({ error: 'rig and task are required' });
    return;
  }
  const args = ['sling', rig, task];
  if (convoy) args.push('--convoy', convoy);
  if (Array.isArray(labels)) {
    for (const label of labels) {
      args.push('--label', label);
    }
  }
  try {
    res.json({ output: await runSgt(args) });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/sling-dog', async (req, res) => {
  const { rig, issue } = req.body;
  if (!rig || !issue) {
    res.status(400).json({ error: 'rig and issue are required' });
    return;
  }
  try {
    res.json({ output: await runSgt(['dog', rig, issue]) });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/logs', (req, res) => {
  const lines = Number.parseInt(req.query.lines, 10) || 100;
  res.json({ lines: readRecentLogLines(SGT_LOG, lines) });
});

app.get('/api/plan-state/:rig', (req, res) => {
  const planState = tryReadJson(path.join(SGT_CONFIG, 'plan-state', `${req.params.rig}.json`));
  if (!planState) {
    res.status(404).json({ error: 'plan state not found' });
    return;
  }
  res.json(planState);
});

function handleWsMessage(ws, rawMessage) {
  let msg;
  try {
    msg = JSON.parse(rawMessage.toString());
  } catch {
    safeSend(ws, { type: 'error', error: 'invalid-json' });
    return;
  }

  if (msg.type === 'stream/subscribe') {
    if (!msg.target) {
      safeSend(ws, { type: 'error', error: 'stream-target-required' });
      return;
    }
    streamManager.subscribe(ws, msg.target);
    return;
  }

  if (msg.type === 'stream/unsubscribe') {
    if (msg.target) streamManager.unsubscribe(ws, msg.target);
    return;
  }

  if (msg.type === 'snapshot/request') {
    buildSnapshot()
      .then((snapshot) => safeSend(ws, { type: 'snapshot', snapshot }))
      .catch((error) => safeSend(ws, { type: 'error', error: error.message }));
  }
}

wss.on('connection', (ws) => {
  let alive = true;
  let statusInterval = null;
  let pingInterval = null;
  let logWatcher = null;
  let lastPongAt = Date.now();

  safeSend(ws, {
    type: 'hello',
    serverTime: new Date().toISOString(),
    features: {
      normalizedSnapshot: true,
      blockers: true,
      tmuxStreaming: true,
    },
  });

  buildSnapshot()
    .then((snapshot) => {
      safeSend(ws, { type: 'snapshot', snapshot });
      safeSend(ws, {
        type: 'status',
        raw: '',
        parsed: toLegacyStatusPayload(snapshot),
        serverTime: snapshot.meta.serverTime,
      });
    })
    .catch(() => {});

  statusInterval = setInterval(() => {
    if (!alive) return;
    buildSnapshot()
      .then((snapshot) => {
        safeSend(ws, { type: 'snapshot', snapshot });
        safeSend(ws, {
          type: 'status',
          raw: '',
          parsed: toLegacyStatusPayload(snapshot),
          serverTime: snapshot.meta.serverTime,
        });
      })
      .catch(() => {});
  }, WS_INTERVAL);

  ws.on('pong', () => {
    lastPongAt = Date.now();
  });

  pingInterval = setInterval(() => {
    if (ws.readyState !== 1) return;
    if (Date.now() - lastPongAt > WS_PONG_GRACE) {
      try {
        ws.terminate();
      } catch {}
      return;
    }
    try {
      ws.ping();
    } catch {}
  }, WS_PING_INTERVAL);

  try {
    let lastSize = 0;
    try {
      lastSize = fs.statSync(SGT_LOG).size;
    } catch {}

    logWatcher = fs.watchFile(SGT_LOG, { interval: 1000 }, () => {
      try {
        const stat = fs.statSync(SGT_LOG);
        if (stat.size < lastSize) {
          lastSize = 0;
          safeSend(ws, { type: 'log_reset' });
          return;
        }
        if (stat.size > lastSize) {
          const fd = fs.openSync(SGT_LOG, 'r');
          const buf = Buffer.alloc(stat.size - lastSize);
          fs.readSync(fd, buf, 0, buf.length, lastSize);
          fs.closeSync(fd);
          const newLines = buf
            .toString('utf8')
            .split('\n')
            .filter((line) => line.trim());
          if (newLines.length > 0) {
            safeSend(ws, { type: 'log', lines: newLines });
          }
          lastSize = stat.size;
        }
      } catch {}
    });
  } catch {}

  ws.on('message', (message) => handleWsMessage(ws, message));

  ws.on('close', () => {
    alive = false;
    streamManager.unsubscribeAll(ws);
    if (statusInterval) clearInterval(statusInterval);
    if (pingInterval) clearInterval(pingInterval);
    if (logWatcher) fs.unwatchFile(SGT_LOG);
  });

  ws.on('error', () => {
    alive = false;
    streamManager.unsubscribeAll(ws);
  });
});

server.listen(PORT, () => {
  console.log(`SGT Web UI running at http://localhost:${PORT}`);
  console.log(`SGT_ROOT: ${SGT_ROOT}`);
  console.log(`SGT_BIN:  ${SGT_BIN}`);
});

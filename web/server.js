const express = require('express');
const { WebSocketServer } = require('ws');
const http = require('http');
const path = require('path');
const { execFile, spawn } = require('child_process');
const fs = require('fs');

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

const PORT = process.env.SGT_WEB_PORT || 4747;
const SGT_ROOT = process.env.SGT_ROOT || path.join(process.env.HOME, 'sgt');
const SGT_BIN = process.env.SGT_BIN || path.join(SGT_ROOT, 'sgt');
const SGT_CONFIG = path.join(SGT_ROOT, '.sgt');
const SGT_LOG = path.join(SGT_ROOT, 'sgt.log');

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// --- Helpers ---

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
    return fs.readdirSync(dir).filter(f => !f.startsWith('.'));
  } catch {
    return [];
  }
}

// --- API: Status (parsed from sgt status output) ---

app.get('/api/status', async (req, res) => {
  try {
    const output = await runSgt(['status']);
    res.json({ raw: output, parsed: parseStatus(output) });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

function parseStatus(raw) {
  // Supports both legacy (=== Agents ===) and current box-drawing output.
  const result = { agents: [], polecats: [], dogs: [], crew: [], mergeQueue: [] };
  let section = null;

  function setSectionFromHeader(line) {
    // Legacy headers
    if (line.startsWith('=== Agents ===')) return 'agents';
    if (line.startsWith('=== Dogs ===')) return 'dogs';
    if (line.startsWith('=== Crew ===')) return 'crew';
    if (line.startsWith('=== Merge Queue')) return 'mergeQueue';
    if (line.startsWith('=== Polecats ===')) return 'polecats';

    // New headers
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
    if (maybe) { section = maybe; continue; }

    if (line.startsWith('»') || line.trim() === '') continue;
    if (line.trim() === 'none' || line.trim() === 'empty') continue;
    if (line.startsWith('1 polecat') || line.includes('polecat(s) tracked')) continue;

    if (section === 'agents') {
      // Legacy: "  daemon:  on (pid ...)"
      const mLegacy = line.match(/^\s+(\S+):\s+(.+)$/);
      if (mLegacy) {
        result.agents.push({ name: mLegacy[1], status: mLegacy[2].trim() });
        continue;
      }

      // New: "  daemon           on  (pid ...)" or "  witness/sgt      on"
      const m = line.match(/^\s{2,}([^\s]+)\s{2,}(.+?)\s*$/);
      if (m) {
        const name = m[1].trim();
        const status = m[2].trim();
        result.agents.push({ name, status });
        continue;
      }

      if (line.includes('last heartbeat:')) {
        const hb = line.match(/last heartbeat:\s+(.+)/);
        if (hb && result.agents.length > 0) {
          result.agents[result.agents.length - 1].heartbeat = hb[1].trim();
        }
      }

    } else if (section === 'polecats') {
      // Legacy detailed block
      const pmLegacy = line.match(/^\s+(\S+)\s+\[(\w+)\]/);
      if (pmLegacy) {
        result.polecats.push({ name: pmLegacy[1], alive: pmLegacy[2] });
        continue;
      }
      if (result.polecats.length > 0) {
        const last = result.polecats[result.polecats.length - 1];
        const kv = line.match(/^\s+(\w+):\s+(.+)/);
        if (kv) { last[kv[1]] = kv[2].trim(); continue; }
      }

      // New compact polecat line: "  thrembo-voice-ui-b007867c alive  #2  sgt/thrembo-voice-ui-b007867c"
      const pm = line.match(/^\s{2,}(\S+)\s+(alive|dead)\s{2,}#?(\d+)\s{2,}(.+)$/);
      if (pm) {
        result.polecats.push({
          name: pm[1],
          alive: pm[2],
          issue: '#' + pm[3],
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

// --- API: Rigs ---

app.get('/api/rigs', async (req, res) => {
  try {
    const output = await runSgt(['rig', 'list']);
    const rigs = [];
    const lines = output.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const m = lines[i].match(/^\s+(\S+)\s+(https?:\/\/.+)$/);
      if (m) {
        const info = { name: m[1], repo: m[2] };
        if (i + 1 < lines.length) {
          const detail = lines[i + 1].match(/polecats:\s*(\d+)\s+witness:\s*(\w+)\s+refinery:\s*(\w+)/);
          if (detail) {
            info.polecats = parseInt(detail[1]);
            info.witness = detail[2];
            info.refinery = detail[3];
          }
        }
        rigs.push(info);
      }
    }
    res.json(rigs);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- API: Polecats (from state files for richer data) ---

app.get('/api/polecats', (req, res) => {
  const dir = path.join(SGT_CONFIG, 'polecats');
  const polecats = readDir(dir).map(name => {
    const state = readStateFile(path.join(dir, name));
    if (!state) return null;
    return { name, ...state };
  }).filter(Boolean);
  res.json(polecats);
});

// --- API: Dogs ---

app.get('/api/dogs', (req, res) => {
  const dir = path.join(SGT_CONFIG, 'dogs');
  const dogs = readDir(dir).map(name => {
    const state = readStateFile(path.join(dir, name));
    if (!state) return null;
    return { name, ...state };
  }).filter(Boolean);
  res.json(dogs);
});

// --- API: Merge Queue ---

app.get('/api/merge-queue', (req, res) => {
  const dir = path.join(SGT_CONFIG, 'merge-queue');
  const items = readDir(dir).map(name => {
    const state = readStateFile(path.join(dir, name));
    if (!state) return null;
    return { name, ...state };
  }).filter(Boolean);
  res.json(items);
});

// --- API: Peek ---

app.get('/api/peek/:target', async (req, res) => {
  try {
    const output = await runSgt(['peek', req.params.target]);
    res.json({ output });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- API: Sling (dispatch polecat) ---

app.post('/api/sling', async (req, res) => {
  const { rig, task, labels, convoy } = req.body;
  if (!rig || !task) {
    return res.status(400).json({ error: 'rig and task are required' });
  }
  const args = ['sling', rig, task];
  if (convoy) { args.push('--convoy', convoy); }
  if (labels && labels.length) {
    for (const l of labels) { args.push('--label', l); }
  }
  try {
    const output = await runSgt(args);
    res.json({ output });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- API: Sling dog ---

app.post('/api/sling-dog', async (req, res) => {
  const { rig, issue } = req.body;
  if (!rig || !issue) {
    return res.status(400).json({ error: 'rig and issue are required' });
  }
  try {
    const output = await runSgt(['dog', rig, issue]);
    res.json({ output });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- API: Log tail (last N lines) ---

app.get('/api/logs', (req, res) => {
  const lines = parseInt(req.query.lines) || 100;
  try {
    const content = fs.readFileSync(SGT_LOG, 'utf8');
    const allLines = content.split('\n');
    const tail = allLines.slice(Math.max(0, allLines.length - lines));
    res.json({ lines: tail });
  } catch {
    res.json({ lines: [] });
  }
});

// --- WebSocket: Real-time updates ---

const WS_INTERVAL = 3000; // poll every 3 seconds
const WS_PING_INTERVAL = 15000;
const WS_PONG_GRACE = 35000; // if no pong for this long, terminate

wss.on('connection', (ws) => {
  let alive = true;
  let logWatcher = null;
  let statusInterval = null;
  let pingInterval = null;
  let lastPongAt = Date.now();

  // hello + initial status
  safeSend(ws, { type: 'hello', serverTime: new Date().toISOString() });
  sendStatus(ws);

  // Poll status on interval
  statusInterval = setInterval(() => {
    if (alive) sendStatus(ws);
  }, WS_INTERVAL);

  // WS heartbeat (robustness)
  ws.on('pong', () => { lastPongAt = Date.now(); });
  pingInterval = setInterval(() => {
    if (ws.readyState !== 1) return;
    const age = Date.now() - lastPongAt;
    if (age > WS_PONG_GRACE) {
      try { ws.terminate(); } catch {}
      return;
    }
    try { ws.ping(); } catch {}
  }, WS_PING_INTERVAL);

  // Watch log file for changes (handle truncation/rotation)
  try {
    let lastSize = 0;
    try { lastSize = fs.statSync(SGT_LOG).size; } catch {}

    logWatcher = fs.watchFile(SGT_LOG, { interval: 1000 }, () => {
      try {
        const stat = fs.statSync(SGT_LOG);

        // truncation / rotation
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
          const newLines = buf.toString('utf8').split('\n').filter(l => l.trim());
          if (newLines.length > 0) {
            safeSend(ws, { type: 'log', lines: newLines });
          }
          lastSize = stat.size;
        }
      } catch {}
    });
  } catch {}

  ws.on('close', () => {
    alive = false;
    if (statusInterval) clearInterval(statusInterval);
    if (pingInterval) clearInterval(pingInterval);
    if (logWatcher) fs.unwatchFile(SGT_LOG);
  });

  ws.on('error', () => {
    alive = false;
  });
});

function safeSend(ws, obj) {
  if (ws.readyState !== 1) return;
  try { ws.send(JSON.stringify(obj)); } catch {}
}

async function sendStatus(ws) {
  if (ws.readyState !== 1) return;
  try {
    const output = await runSgt(['status']);
    safeSend(ws, { type: 'status', raw: output, parsed: parseStatus(output), serverTime: new Date().toISOString() });
  } catch {}
}

// --- Start ---

server.listen(PORT, () => {
  console.log(`SGT Web UI running at http://localhost:${PORT}`);
  console.log(`SGT_ROOT: ${SGT_ROOT}`);
  console.log(`SGT_BIN:  ${SGT_BIN}`);
});

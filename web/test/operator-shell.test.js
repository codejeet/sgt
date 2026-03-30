const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

test("operator shell html includes cockpit sections and assets", () => {
  const html = fs.readFileSync(path.join(__dirname, "..", "public", "index.html"), "utf8");
  assert.match(html, /<title>SGT SGT Cockpit<\/title>/);
  assert.match(html, /<h1>SGT SGT Cockpit<\/h1>/);
  assert.match(html, /Operator Console/);
  assert.match(html, /Command Status/);
  assert.match(html, /Topology Map/);
  assert.doesNotMatch(html, /Jarvis Cockpit/i);
  assert.doesNotMatch(html, /Command Pulse/);
  assert.doesNotMatch(html, /Topology Radar/);
  assert.match(html, /section-overview/);
  assert.match(html, /section-streams/);
  assert.ok(html.indexOf('id="section-streams"') < html.indexOf('id="section-overview"'));
  assert.match(html, /Live Monitor/);
  assert.match(html, /section-topology/);
  assert.match(html, /section-dispatch/);
  assert.match(html, /section-logs/);
  assert.match(html, /id="streamRigFilter"/);
  assert.match(html, /id="streamRoleFilter"/);
  assert.match(html, /id="mayorMonitor"/);
  assert.match(html, /id="monitorWall"/);
  assert.match(html, /id="alertRail"/);
  assert.match(html, /id="blockerBoard"/);
  assert.match(html, /id="voiceMuteBtn"/);
  assert.match(html, /id="topologyCanvas"/);
  assert.match(html, /id="topologyOverlay"/);
  assert.match(html, /id="topologyFocus"/);
  assert.match(html, /section section-streams active/);
  assert.match(html, /section section-overview/);
  assert.match(html, /section section-topology/);
  assert.match(html, /src="\/app\.js"/);
  assert.match(html, /href="\/styles\.css"/);
});

test("operator shell script consumes snapshot and tmux stream events", () => {
  const script = fs.readFileSync(path.join(__dirname, "..", "public", "app.js"), "utf8");
  assert.match(script, /sections: \["streams", "overview", "topology", "dispatch", "logs"\]/);
  assert.match(script, /"1": "streams"/);
  assert.match(script, /"2": "overview"/);
  assert.match(script, /message\.type === "snapshot"/);
  assert.match(script, /message\.type === "stream\/open"/);
  assert.match(script, /message\.type === "stream\/data"/);
  assert.match(script, /message\.type === "stream\/stale"/);
  assert.match(script, /streamFilters/);
  assert.match(script, /Tail All: On/);
  assert.match(script, /renderMonitorStream/);
  assert.match(script, /matchesStreamFilters/);
  assert.match(script, /maybePlayVoiceAnnouncement/);
  assert.match(script, /renderAlerts/);
  assert.match(script, /renderTopology/);
  assert.match(script, /initializeTopologyRenderer/);
  assert.match(script, /drawWebGlTopology/);
  assert.match(script, /handleTopologyPointerClick/);
  assert.match(script, /renderStreamDeck/);
});

test("operator shell styles reflect the research-backed humanization pass", () => {
  const styles = fs.readFileSync(path.join(__dirname, "..", "public", "styles.css"), "utf8");

  assert.match(styles, /--radius:\s*3px/);
  assert.match(styles, /--blue:\s*#63aafc/i);
  assert.match(styles, /--amber:\s*#d9a441/i);
  assert.match(styles, /--plum:\s*#ad7cff/i);
  assert.match(styles, /\.section-streams\s*\{/);
  assert.match(styles, /\.section-overview\s*\{/);
  assert.match(styles, /\.section-topology\s*\{/);
  assert.match(styles, /border-top:\s*2px solid rgba\(99, 170, 252, 0\.6\)/);
  assert.match(styles, /border-radius:\s*2px/);
  assert.doesNotMatch(styles, /Orbitron/);
  assert.doesNotMatch(styles, /backdrop-filter/);
  assert.doesNotMatch(styles, /999px/);
});

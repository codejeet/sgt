const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

test("operator shell html includes cockpit sections and assets", () => {
  const html = fs.readFileSync(path.join(__dirname, "..", "public", "index.html"), "utf8");
  assert.match(html, /JARVIS Cockpit/);
  assert.match(html, /section-overview/);
  assert.match(html, /section-streams/);
  assert.match(html, /section-topology/);
  assert.match(html, /section-dispatch/);
  assert.match(html, /section-logs/);
  assert.match(html, /id="streamRigFilter"/);
  assert.match(html, /id="streamRoleFilter"/);
  assert.match(html, /id="mayorMonitor"/);
  assert.match(html, /id="monitorWall"/);
  assert.match(html, /id="blockerBoard"/);
  assert.match(html, /id="topologyCanvas"/);
  assert.match(html, /src="\/app\.js"/);
  assert.match(html, /href="\/styles\.css"/);
});

test("operator shell script consumes snapshot and tmux stream events", () => {
  const script = fs.readFileSync(path.join(__dirname, "..", "public", "app.js"), "utf8");
  assert.match(script, /message\.type === "snapshot"/);
  assert.match(script, /message\.type === "stream\/open"/);
  assert.match(script, /message\.type === "stream\/data"/);
  assert.match(script, /message\.type === "stream\/stale"/);
  assert.match(script, /streamFilters/);
  assert.match(script, /Tail All: On/);
  assert.match(script, /renderMonitorStream/);
  assert.match(script, /matchesStreamFilters/);
  assert.match(script, /renderTopology/);
  assert.match(script, /renderStreamDeck/);
});

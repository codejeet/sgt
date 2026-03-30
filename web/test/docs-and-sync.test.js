const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('web docs cover deploy path, config, and latest-main proof entrypoint', () => {
  const readme = fs.readFileSync(path.join(__dirname, '..', 'README.md'), 'utf8');
  const redesignRules = fs.readFileSync(path.join(__dirname, '..', 'docs', 'human-dashboard-redesign-rules.md'), 'utf8');

  assert.match(readme, /\/root\/sgt\/web/);
  assert.match(readme, /web\/scripts\/sync-live-copy\.sh/);
  assert.match(readme, /SGT_WEB_LIVE_DIR/);
  assert.match(readme, /SGT_WEB_PORT/);
  assert.match(readme, /SGT_WEB_ELEVENLABS_API_KEY/);
  assert.match(readme, /SGT_WEB_VOICE_RATE_LIMIT_SECS/);
  assert.match(readme, /WebGL/);
  assert.match(readme, /test_web_cockpit_latest_main_proof\.sh/);
  assert.match(readme, /human-dashboard-redesign-rules\.md/);

  assert.match(redesignRules, /Issue:\s*`#278`/);
  assert.match(redesignRules, /SGT SGT Cockpit/);
  assert.match(redesignRules, /live monitoring the first major section/i);
  assert.match(redesignRules, /reduce gradients/i);
  assert.match(redesignRules, /reduce corner radius/i);
  assert.match(redesignRules, /triadic palette/i);
  assert.match(redesignRules, /sync path to `\/root\/sgt\/web`/);
});

test('sync-live-copy helper defaults to the canonical live target and preserves runtime artifacts', () => {
  const script = fs.readFileSync(path.join(__dirname, '..', 'scripts', 'sync-live-copy.sh'), 'utf8');

  assert.match(script, /SGT_WEB_LIVE_DIR/);
  assert.match(script, /\/root\/sgt\/web/);
  assert.match(script, /--exclude=node_modules\//);
  assert.match(script, /--exclude=package-lock\.json/);
  assert.match(script, /--exclude=webui\.log/);
  assert.match(script, /npm install --prefix "\$TARGET_DIR"/);
});

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  TmuxStreamManager,
  buildCockpitSnapshot,
  computeStreamDelta,
} = require('../lib/cockpit');

test('buildCockpitSnapshot shapes normalized rig, worker, blocker, and topology state', () => {
  const snapshot = buildCockpitSnapshot({
    statusJson: {
      agents: [
        { name: 'daemon', status: 'on' },
        { name: 'mayor', status: 'on', heartbeat: { state: 'ok' } },
      ],
      mayor_rigs: [
        {
          rig: 'sgt',
          state: 'active',
          reason: 'open_issues=1 open_prs=0 active_polecats=1 merge_queue=0 pending_plan_requests=0',
          hibernation_mode: 'none',
        },
      ],
      polecats: [
        {
          name: 'sgt-34784812',
          status: 'alive',
          rig: 'sgt',
          issue: '264',
          branch: 'sgt/sgt-34784812',
          session: 'sgt-sgt-34784812',
          pr: { number: '', state: '', title: '' },
        },
      ],
      dogs: [],
      merge_queue: [{ name: 'sgt-pr264', detail: 'PR#264 sgt' }],
    },
    rigs: [{ name: 'sgt', repo: 'https://github.com/codejeet/sgt', polecats: 1, witness: 'on', refinery: 'on' }],
    blockers: [
      {
        id: 'sgt-acceptance-1',
        rig: 'sgt',
        status: 'open',
        title: 'Acceptance still red',
        requester: 'rigger',
        createdAt: '2026-03-30T06:00:00Z',
        updatedAt: '2026-03-30T06:00:00Z',
        evidence: 'Need more work',
      },
    ],
    recentLogs: ['[2026-03-30T06:00:00Z] MAYOR_START'],
    version: 'test',
  });

  assert.equal(snapshot.meta.featureFlags.tmuxStreaming, true);
  assert.equal(snapshot.rigs.length, 1);
  assert.equal(snapshot.rigs[0].blockers, 1);
  assert.equal(snapshot.rigs[0].activeWorkers, 1);
  assert.equal(snapshot.workers[0].stream.target, 'sgt-34784812');
  assert.equal(snapshot.queue.summary.total, 1);
  assert.equal(snapshot.blockers[0].title, 'Acceptance still red');
  assert.ok(snapshot.topology.nodes.some((node) => node.id === 'rig:sgt'));
  assert.ok(snapshot.topology.edges.some((edge) => edge.from === 'rig:sgt' && edge.type === 'runs'));
});

test('computeStreamDelta emits append-only chunks when possible and reset on divergence', () => {
  assert.deepEqual(computeStreamDelta('', 'abc'), { changed: true, reset: true, chunk: 'abc' });
  assert.deepEqual(computeStreamDelta('abc', 'abcdef'), { changed: true, reset: false, chunk: 'def' });
  assert.deepEqual(computeStreamDelta('abc', 'zbc'), { changed: true, reset: true, chunk: 'zbc' });
  assert.deepEqual(computeStreamDelta('abc', 'abc'), { changed: false, reset: false, chunk: '' });
});

test('TmuxStreamManager emits open, data, stale, and close lifecycle events', async () => {
  const events = [];
  const subscriber = { id: 'ws-1' };
  const payloads = ['one', 'one\ntwo'];
  let captureCount = 0;

  const manager = new TmuxStreamManager({
    pollInterval: 100000,
    staleThresholdMs: 1,
    now: (() => {
      let ts = 1000;
      return () => {
        ts += 10;
        return ts;
      };
    })(),
    captureTarget: async () => {
      captureCount += 1;
      if (captureCount === 1) return { available: true, session: 'sgt-demo', content: payloads[0] };
      if (captureCount === 2) return { available: true, session: 'sgt-demo', content: payloads[1] };
      return { available: false, reason: 'session-missing' };
    },
    send: (subscribers, message) => {
      events.push({
        subscribers: subscribers ? Array.from(subscribers).map((item) => item.id) : [],
        message,
      });
    },
  });

  manager.subscribe(subscriber, 'demo');
  await manager.tick('demo');
  await manager.tick('demo');
  manager.unsubscribe(subscriber, 'demo');

  assert.equal(events[0].message.type, 'stream/open');
  assert.equal(events[1].message.type, 'stream/data');
  assert.equal(events[1].message.reset, true);
  assert.equal(events[2].message.type, 'stream/data');
  assert.equal(events[2].message.reset, false);
  assert.equal(events[2].message.chunk, '\ntwo');
  assert.equal(events[3].message.type, 'stream/stale');
  assert.equal(events[4].message.type, 'stream/close');
});

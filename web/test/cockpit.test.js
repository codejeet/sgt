const test = require('node:test');
const assert = require('node:assert/strict');

const {
  BlockerAlertTracker,
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
    alerts: [
      {
        id: 'alert:1',
        blockerId: 'sgt-acceptance-1',
        kind: 'blocker-opened',
        severity: 'critical',
        createdAt: '2026-03-30T06:00:10Z',
        rig: 'sgt',
        title: 'Acceptance still red',
        message: 'sgt blocker opened: Acceptance still red',
        voice: { enabled: false, eligible: false, reason: 'not-configured' },
      },
    ],
    recentLogs: ['[2026-03-30T06:00:00Z] MAYOR_START'],
    version: 'test',
    voice: {
      enabled: false,
      configured: false,
      eventKinds: ['blocker-resolved'],
      rateLimitSeconds: 90,
    },
  });

  assert.equal(snapshot.meta.featureFlags.tmuxStreaming, true);
  assert.equal(snapshot.meta.featureFlags.voiceAnnouncements, false);
  assert.equal(snapshot.rigs.length, 1);
  assert.equal(snapshot.rigs[0].blockers, 1);
  assert.equal(snapshot.rigs[0].activeWorkers, 1);
  assert.equal(snapshot.workers[0].stream.target, 'sgt-34784812');
  assert.equal(snapshot.queue.summary.total, 1);
  assert.equal(snapshot.blockers[0].title, 'Acceptance still red');
  assert.equal(snapshot.alerts[0].kind, 'blocker-opened');
  assert.ok(snapshot.topology.nodes.some((node) => node.id === 'rig:sgt'));
  assert.ok(snapshot.topology.nodes.some((node) => node.id === 'issue:sgt:264'));
  assert.ok(snapshot.topology.nodes.some((node) => node.id === 'queue:sgt-pr264'));
  assert.ok(snapshot.topology.edges.some((edge) => edge.from === 'rig:sgt' && edge.type === 'runs'));
  assert.ok(snapshot.topology.edges.some((edge) => edge.from === 'queue:sgt-pr264' && edge.type === 'contains'));
  assert.ok(snapshot.topology.edges.some((edge) => edge.from === 'worker:polecat:sgt-34784812' && edge.type === 'works-on'));
});

test('BlockerAlertTracker records blocker opens and resolutions with voice gating', () => {
  const tracker = new BlockerAlertTracker({
    now: (() => {
      const stamps = [
        '2026-03-30T06:00:00Z',
        '2026-03-30T06:01:00Z',
        '2026-03-30T06:02:00Z',
      ];
      let index = 0;
      return () => stamps[index++] || stamps[stamps.length - 1];
    })(),
    voice: {
      enabled: true,
      eventKinds: ['blocker-resolved'],
      rateLimitMs: 0,
    },
  });

  assert.equal(tracker.observe([{ id: 'b1', rig: 'sgt', title: 'Acceptance still red', status: 'open', requester: 'rigger' }]).length, 0);

  const eventsAfterOpen = tracker.observe([
    { id: 'b1', rig: 'sgt', title: 'Acceptance still red', status: 'open', requester: 'rigger' },
    { id: 'b2', rig: 'pmkb', title: 'Smoke test blocked', status: 'open', requester: 'witness' },
  ]);
  assert.equal(eventsAfterOpen[0].kind, 'blocker-opened');
  assert.equal(eventsAfterOpen[0].voice.eligible, false);
  assert.equal(eventsAfterOpen[0].voice.reason, 'event-disabled');

  const eventsAfterResolve = tracker.observe([{ id: 'b2', rig: 'pmkb', title: 'Smoke test blocked', status: 'open', requester: 'witness' }]);
  assert.equal(eventsAfterResolve[0].kind, 'blocker-resolved');
  assert.equal(eventsAfterResolve[0].rig, 'sgt');
  assert.equal(eventsAfterResolve[0].voice.eligible, true);
  assert.match(eventsAfterResolve[0].voice.text, /No open blockers remain on this rig|All acceptance blockers are clear/);
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

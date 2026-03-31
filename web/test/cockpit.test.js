const test = require('node:test');
const assert = require('node:assert/strict');

const {
  BlockerAlertTracker,
  TmuxStreamManager,
  buildCockpitAlerts,
  buildCockpitSnapshot,
  captureStreamTarget,
  computeStreamDelta,
  parsePresidentOperatorEvents,
  resolveMayorLogPath,
  resolveMayorRuntimeDir,
  resolveMayorSessionName,
} = require('../lib/cockpit');

test('buildCockpitSnapshot shapes normalized rig, worker, blocker, and topology state', () => {
  const snapshot = buildCockpitSnapshot({
    statusJson: {
      agents: [
        { name: 'daemon', status: 'on' },
        { name: 'mayor', role: 'mayor', scope: 'global', status: 'on', heartbeat: { state: 'ok' } },
      ],
      president_events: [
        {
          ts: '1775000000',
          created_at: '2026-03-31T22:04:00Z',
          rig: 'sgt',
          kind: 'intervention',
          severity: 'warning',
          notify: true,
          dedupe_key: 'president:sgt:intervention:mayor-heartbeat-stale:refresh',
          overlap_key: 'mayor-health:sgt:mayor-heartbeat-stale',
          action: 'refresh',
          reason: 'mayor-heartbeat-stale',
          outcome: 'intervened',
          cycle_trigger: 'periodic',
          detail: 'heartbeat_age=1200s threshold=720s',
        },
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
          runtime: {
            classification: 'busy-long-running',
            reason_code: 'substantive-child-running',
            summary: 'quiet output but substantive child python3 pid=321 cpu=97 age=840s state=R',
            output_age_seconds: '1200',
            busy_pid: '321',
            busy_comm: 'python3',
            busy_args: 'python3 scripts/example.py',
          },
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
  assert.equal(snapshot.agents[1].role, 'mayor');
  assert.equal(snapshot.agents[1].scope, 'global');
  assert.equal(snapshot.agents[1].stream.target, 'mayor');
  assert.equal(snapshot.rigs.length, 1);
  assert.equal(snapshot.rigs[0].blockers, 1);
  assert.equal(snapshot.rigs[0].activeWorkers, 1);
  assert.equal(snapshot.workers[0].stream.target, 'sgt-34784812');
  assert.equal(snapshot.workers[0].runtime.classification, 'busy-long-running');
  assert.equal(snapshot.workers[0].runtime.busy_comm, 'python3');
  assert.equal(snapshot.queue.summary.total, 1);
  assert.equal(snapshot.blockers[0].title, 'Acceptance still red');
  assert.equal(snapshot.alerts[0].kind, 'blocker-opened');
  assert.equal(snapshot.president.events.length, 1);
  assert.equal(snapshot.president.events[0].notify, true);
  assert.equal(snapshot.president.events[0].action, 'refresh');
  assert.equal(snapshot.president.events[0].reason, 'mayor-heartbeat-stale');
  assert.equal(snapshot.president.events[0].outcome, 'intervened');
  assert.ok(snapshot.topology.nodes.some((node) => node.id === 'rig:sgt'));
  assert.ok(snapshot.topology.nodes.some((node) => node.id === 'issue:sgt:264'));
  assert.ok(snapshot.topology.nodes.some((node) => node.id === 'queue:sgt-pr264'));
  assert.ok(snapshot.topology.edges.some((edge) => edge.from === 'rig:sgt' && edge.type === 'runs'));
  assert.ok(snapshot.topology.edges.some((edge) => edge.from === 'queue:sgt-pr264' && edge.type === 'contains'));
  assert.ok(snapshot.topology.edges.some((edge) => edge.from === 'worker:polecat:sgt-34784812' && edge.type === 'works-on'));
});

test('buildCockpitSnapshot keeps president and rig-local mayor topology nodes directly inspectable', () => {
  const snapshot = buildCockpitSnapshot({
    statusJson: {
      agents: [
        { name: 'president', role: 'president', scope: 'global', status: 'on', heartbeat: { state: 'ok' } },
        { name: 'mayor/alpha', role: 'mayor', scope: 'rig', rig: 'alpha', status: 'on', heartbeat: { state: 'ok' } },
        { name: 'witness/alpha', role: 'witness', scope: 'rig', rig: 'alpha', status: 'on' },
      ],
      mayor_rigs: [{ rig: 'alpha', state: 'active', reason: 'open_issues=1', hibernation_mode: 'none' }],
      polecats: [],
      dogs: [],
      merge_queue: [],
    },
    rigs: [{ name: 'alpha', repo: 'https://github.com/acme/alpha', polecats: 0, witness: 'on', refinery: 'off' }],
    blockers: [],
    alerts: [],
    recentLogs: [],
    version: 'test',
    voice: {},
  });

  const president = snapshot.topology.nodes.find((node) => node.id === 'agent:president');
  const alphaMayor = snapshot.topology.nodes.find((node) => node.id === 'agent:mayor/alpha');
  assert.equal(president.metadata.streamTarget, 'president');
  assert.equal(alphaMayor.metadata.streamTarget, 'mayor/alpha');
  assert.ok(snapshot.topology.edges.some((edge) => edge.from === 'agent:president' && edge.to === 'agent:mayor/alpha' && edge.type === 'supervises'));
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

test('parsePresidentOperatorEvents keeps only the latest actionable President incident per overlap key', () => {
  const alerts = parsePresidentOperatorEvents([
    '[2026-03-31T22:00:00Z] PRESIDENT_OPERATOR_EVENT rig=sgt kind=stalled-purpose severity=warning notify=1 dedupe_key=president:sgt:stalled-purpose:actionable-no-forward-motion:refresh overlap_key=rig-incident:sgt:actionable-no-forward-motion action=refresh reason=actionable-no-forward-motion outcome=intervened detail="old issue"',
    '[2026-03-31T22:01:00Z] PRESIDENT_OPERATOR_EVENT rig=sgt kind=intervention severity=info notify=0 dedupe_key=president:sgt:intervention:actionable-rig-recheck:wake overlap_key=rig-incident:sgt:actionable-no-forward-motion action=wake reason=actionable-rig-recheck outcome=intervened detail="quiet recheck"',
    '[2026-03-31T22:02:00Z] PRESIDENT_INTERVENTION rig=pmkb action=start reason=mayor-session-missing detail="session=off" cycle_trigger="periodic"',
    '[2026-03-31T22:03:00Z] PRESIDENT_OPERATOR_EVENT rig=pmkb kind=intervention severity=warning notify=1 dedupe_key=president:pmkb:intervention:mayor-session-missing:start overlap_key=mayor-health:pmkb:mayor-session-missing action=start reason=mayor-session-missing outcome=suppressed-by-cooldown detail="same incident"',
  ]);

  assert.equal(alerts.length, 2);
  assert.equal(alerts[0].rig, 'pmkb');
  assert.equal(alerts[0].kind, 'intervention');
  assert.equal(alerts[0].message, 'President start mayor/pmkb: mayor session missing');
  assert.equal(alerts[1].rig, 'sgt');
  assert.equal(alerts[1].kind, 'stalled-purpose');
});

test('buildCockpitAlerts merges President alerts with blocker transitions in recency order', () => {
  const alerts = buildCockpitAlerts({
    blockerAlerts: [
      {
        id: 'alert:blocker',
        kind: 'blocker-opened',
        severity: 'critical',
        createdAt: '2026-03-31T22:01:00Z',
        rig: 'sgt',
        message: 'sgt blocker opened: Acceptance still red',
        voice: { enabled: false, eligible: false, reason: 'not-configured' },
      },
    ],
    recentLogs: [
      '[2026-03-31T22:03:00Z] PRESIDENT_OPERATOR_EVENT rig=pmkb kind=escalation severity=critical notify=1 dedupe_key=president:pmkb:escalation:manual-review-needed:refresh overlap_key=president-incident:pmkb:escalation:manual-review-needed action=refresh reason=manual-review-needed outcome=intervened detail="need a human"',
    ],
  });

  assert.equal(alerts.length, 2);
  assert.equal(alerts[0].source, 'president');
  assert.equal(alerts[0].kind, 'escalation');
  assert.equal(alerts[1].id, 'alert:blocker');
});

test('computeStreamDelta emits append-only chunks when possible and reset on divergence', () => {
  assert.deepEqual(computeStreamDelta('', 'abc'), { changed: true, reset: true, chunk: 'abc' });
  assert.deepEqual(computeStreamDelta('abc', 'abcdef'), { changed: true, reset: false, chunk: 'def' });
  assert.deepEqual(computeStreamDelta('abc', 'zbc'), { changed: true, reset: true, chunk: 'zbc' });
  assert.deepEqual(computeStreamDelta('abc', 'abc'), { changed: false, reset: false, chunk: '' });
});

test('resolveMayorLogPath maps shared and per-rig mayor targets to scoped log files', () => {
  assert.equal(resolveMayorLogPath('president', { configDir: '/tmp/.sgt' }), '/tmp/.sgt/president/president-start.log');
  assert.equal(resolveMayorLogPath('mayor', { configDir: '/tmp/.sgt' }), '/tmp/.sgt/mayor-start.log');
  assert.equal(resolveMayorLogPath('mayor/alpha', { configDir: '/tmp/.sgt' }), '/tmp/.sgt/mayors/alpha/mayor-start.log');
  assert.equal(resolveMayorLogPath('witness/alpha', { configDir: '/tmp/.sgt' }), '');
});

test('resolveMayorSessionName and resolveMayorRuntimeDir keep mayor scope explicit', () => {
  assert.equal(resolveMayorSessionName('president'), 'sgt-president');
  assert.equal(resolveMayorSessionName('mayor'), 'sgt-mayor');
  assert.equal(resolveMayorSessionName('mayor/alpha'), 'sgt-mayor-alpha');
  assert.equal(resolveMayorSessionName('witness/alpha'), '');
  assert.equal(resolveMayorRuntimeDir('president', { configDir: '/tmp/.sgt' }), '/tmp/.sgt/president');
  assert.equal(resolveMayorRuntimeDir('mayor', { configDir: '/tmp/.sgt' }), '/tmp/.sgt');
  assert.equal(resolveMayorRuntimeDir('mayor/alpha', { configDir: '/tmp/.sgt' }), '/tmp/.sgt/mayors/alpha');
  assert.equal(resolveMayorRuntimeDir('witness/alpha', { configDir: '/tmp/.sgt' }), '');
});

test('captureStreamTarget falls back to mayor-start.log when the mayor pane is blank or unavailable', async () => {
  const president = await captureStreamTarget('president', {
    configDir: '/tmp/.sgt',
    capturePane: async () => '\n',
    readMayorLog: async (logPath) => `tail:${logPath}`,
  });
  assert.equal(president.available, true);
  assert.equal(president.source, 'mayor-log');
  assert.equal(president.content, 'tail:/tmp/.sgt/president/president-start.log');

  const shared = await captureStreamTarget('mayor', {
    configDir: '/tmp/.sgt',
    capturePane: async () => '\n',
    readMayorLog: async (logPath) => `tail:${logPath}`,
  });
  assert.equal(shared.available, true);
  assert.equal(shared.source, 'mayor-log');
  assert.equal(shared.content, 'tail:/tmp/.sgt/mayor-start.log');

  const perRig = await captureStreamTarget('mayor/alpha', {
    configDir: '/tmp/.sgt',
    capturePane: async () => {
      throw new Error('pane missing');
    },
    readMayorLog: async (logPath) => `tail:${logPath}`,
  });
  assert.equal(perRig.available, true);
  assert.equal(perRig.source, 'mayor-log');
  assert.equal(perRig.content, 'tail:/tmp/.sgt/mayors/alpha/mayor-start.log');
});

test('captureStreamTarget keeps pane content for non-mayor targets and non-blank mayor panes', async () => {
  const witness = await captureStreamTarget('witness/sgt', {
    configDir: '/tmp/.sgt',
    capturePane: async () => 'witness output',
    readMayorLog: async () => {
      throw new Error('should not read mayor log');
    },
  });
  assert.equal(witness.available, true);
  assert.equal(witness.content, 'witness output');
  assert.equal(witness.source, undefined);

  const mayor = await captureStreamTarget('mayor', {
    configDir: '/tmp/.sgt',
    capturePane: async () => 'live mayor pane',
    readMayorLog: async () => {
      throw new Error('should not read mayor log');
    },
  });
  assert.equal(mayor.available, true);
  assert.equal(mayor.content, 'live mayor pane');
  assert.equal(mayor.source, undefined);
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

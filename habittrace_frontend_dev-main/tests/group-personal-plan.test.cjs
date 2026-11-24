const fs = require('node:fs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const Module = require('node:module');
const ts = require('typescript');
require.extensions['.ts'] = (module, filename) => {
  module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS },
  }).outputText, filename);
};
let refreshes = 0;
const originalLoad = Module._load;
Module._load = function(request, ...args) {
  if (request === './supabase') return { supabase: { auth: { getSession: async () => ({ data: { session: { access_token: 'test-token' } } }) } } };
  if (request === './refresh') return { notifyDataChanged() { refreshes++; } };
  return originalLoad.call(this, request, ...args);
};
const { previewGroupPersonalPlan, confirmGroupPersonalPlan } = require('../lib/api.ts');
const { groupDeadlinePassed, formatDue } = require('../lib/group.ts');
Module._load = originalLoad;

test('group deadlines use the creator timezone, across DST and viewer zones', () => {
  const task = { due_date: '2026-11-03', due_time: '12:00:00', due_timezone_name: 'America/Denver' };
  assert.equal(groupDeadlinePassed(task, new Date('2026-11-03T18:59:59Z')), false);
  assert.equal(groupDeadlinePassed(task, new Date('2026-11-03T19:00:00Z')), true);
  assert.equal(groupDeadlinePassed({ ...task, due_date: '2026-10-03' }, new Date('2026-10-03T18:00:00Z')), true);
  assert.match(formatDue(task), /America\/Denver/);
  assert.equal(groupDeadlinePassed({ ...task, due_date: null }), false);
});

test('preview authenticates without announcing a write; only confirmation refreshes data', async () => {
  const calls = [];
  global.fetch = async (url, options) => {
    calls.push({ url, options });
    return new Response(JSON.stringify({ conflicts: [], warnings: [], candidates: [] }), {
      status: 200, headers: { 'content-type': 'application/json' },
    });
  };
  const input = { planned_start: '2099-09-06T16:00:00Z', planned_duration_minutes: 60, timezone_name: 'America/Denver', required_energy: 3, required_focus: 3, current_energy: 2, current_focus: 4 };
  await previewGroupPersonalPlan('group', 'task', input);
  assert.equal(refreshes, 0);
  assert.match(calls[0].url, /\/groups\/group\/tasks\/task\/personal-preview$/);
  assert.equal(calls[0].options.headers.Authorization, 'Bearer test-token');
  assert.deepEqual(JSON.parse(calls[0].options.body), input);
  await confirmGroupPersonalPlan('group', 'task', input);
  assert.equal(refreshes, 1);
  assert.match(calls[1].url, /\/personal-plan$/);
});

test('confirmation failures preserve the error for retry and do not announce a saved plan', async () => {
  global.fetch = async () => new Response(JSON.stringify({ detail: 'Choose another time.' }), {
    status: 409, headers: { 'content-type': 'application/json' },
  });
  const before = refreshes;
  await assert.rejects(confirmGroupPersonalPlan('group', 'task', {}), /409/);
  assert.equal(refreshes, before);
});

const { getGroupPersonalContext, getGroupPersonalReviews, acknowledgeGroupSource,
  shareGroupLinkedCompletion, shareGroupProgress } = require('../lib/api.ts');
const { groupLocalStart, groupBlockInstant, minutesLabel } = require('../lib/group-planning.ts');

test('private reads do not refresh; publication sends only deliberately selected fields', async () => {
  const calls = [];
  global.fetch = async (url, options) => {
    calls.push({ url, options });
    return new Response('{}', { status: 200, headers: { 'content-type': 'application/json' } });
  };
  const before = refreshes;
  await getGroupPersonalContext('g', 't');
  await getGroupPersonalReviews();
  assert.equal(refreshes, before);
  assert.match(calls[0].url, /\/personal-plans$/);
  assert.match(calls[1].url, /\/groups\/personal-review$/);
  assert.equal(calls[0].options.cache, 'no-store');
  await acknowledgeGroupSource('g', 't', 'v2');
  await shareGroupLinkedCompletion('g', 't');
  await shareGroupProgress('g', 't', 'needs_help');
  await shareGroupProgress('g', 't', null);
  assert.equal(refreshes, before + 4);
  assert.deepEqual(calls.slice(2).map(c => JSON.parse(c.options.body)), [
    { expected_source_updated_at: 'v2' }, { confirmed: true },
    { shared_progress: 'needs_help' }, { shared_progress: null },
  ]);
});

test('block retry key, target and source revision survive preview and confirmation', async () => {
  const calls = [];
  global.fetch = async (url, options) => {
    calls.push(JSON.parse(options.body));
    return new Response('{}', { status: 200, headers: { 'content-type': 'application/json' } });
  };
  const input = { block_key: 'stable-key', personal_task_id: 'owned-task', search_days: 31,
    expected_source_updated_at: 'source-v2', planned_start: '2099-09-07T16:00:00Z',
    planned_duration_minutes: 45, timezone_name: 'America/Denver',
    required_energy: 3, required_focus: 4, current_energy: 2, current_focus: 3 };
  await previewGroupPersonalPlan('g', 't', input);
  await confirmGroupPersonalPlan('g', 't', input);
  assert.deepEqual(calls, [input, input]);
});

test('sharing failure does not write another personal outcome', async () => {
  const calls = [];
  global.fetch = async (url) => { calls.push(url); return new Response('{}', { status: 409 }); };
  const before = refreshes;
  await assert.rejects(shareGroupLinkedCompletion('g', 't'), /409/);
  assert.equal(refreshes, before);
  assert.equal(calls.length, 1);
  assert.match(calls[0], /\/linked-completion$/);
});

test('editing legacy block clocks preserves their timezone instant', () => {
  const block = { planned_date: '2026-11-23', planned_start_time: '10:30 AM', timezone_name: 'America/Denver' };
  assert.equal(groupBlockInstant(block).toISOString(), '2026-11-23T17:30:00.000Z');
  assert.equal(groupBlockInstant({ ...block, planned_date: '2026-07-23', planned_start_time: '22:15' }).toISOString(), '2026-07-24T04:15:00.000Z');
  assert.equal(groupBlockInstant({ ...block, planned_start_time: '12:30 AM', timezone_name: 'Asia/Seoul' }).toISOString(), '2026-11-22T15:30:00.000Z');
  assert.throws(() => groupBlockInstant({ ...block, planned_start_time: 'unknown' }), /unreadable/);
});

test('local dates reject DST gaps and repeats; deadline slack has readable units', () => {
  const oldZone = process.env.TZ;
  try {
    process.env.TZ = 'America/Denver';
    assert.equal(groupLocalStart('2026-11-23', '10:30'), '2026-11-23T17:30:00.000Z');
    assert.throws(() => groupLocalStart('2026-03-08', '02:30'), /valid local/);
    assert.throws(() => groupLocalStart('2026-11-01', '01:30'), /repeated/);
  } finally {
    if (oldZone === undefined) delete process.env.TZ; else process.env.TZ = oldZone;
  }
  assert.equal(minutesLabel(1500), '1d 1h');
  assert.equal(minutesLabel(0), '0m');
});

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
const originalLoad = Module._load;
Module._load = function(request, ...args) {
  if (request === './supabase') return { supabase: { auth: { getSession: async () => ({ data: { session: { access_token: 'test-token' } } }) } } };
  if (request === './refresh') return { notifyDataChanged() {} };
  return originalLoad.call(this, request, ...args);
};
const { savePlanOutcome, getDurationRecommendation } = require('../lib/api.ts');
Module._load = originalLoad;
const taskId = '11111111-1111-4111-8111-111111111111';
const calls = [];
global.fetch = async (url, options) => {
  calls.push({ url, ...options, body: JSON.parse(options.body) });
  return new Response(JSON.stringify({ id: 'saved', ...JSON.parse(options.body) }), {
    status: 200, headers: { 'content-type': 'application/json' },
  });
};
test('manual partial outcome preserves measured progress and interruptions in one primary write', async () => {
  calls.length = 0;
  const times = { actual_start_time: '2026-09-05T10:00:00Z', actual_end_time: '2026-09-05T11:00:00Z' };
  await savePlanOutcome(taskId, 'partial', { completion_ratio: .35, interruption_count: 3 }, 'interruption', times);
  assert.equal(calls.length, 1);
  assert.ok(calls[0].url.endsWith('/executions'));
  assert.equal(calls[0].body.completion_ratio, .35);
  assert.equal(calls[0].body.interruption_count, 3);
  assert.equal(calls[0].body.failure_reason, 'interruption');
  assert.equal(calls[0].body.actual_start_time, times.actual_start_time);
  assert.equal(calls[0].body.idempotency_key, taskId);
  assert.equal(calls[0].body.active_minutes, undefined);
});
test('not-started record has no invented timestamps, interruption, or failure reason', async () => {
  calls.length = 0;
  await savePlanOutcome(taskId, 'not_started', { completion_ratio: 0, interruption_count: 0 });
  assert.equal(calls[0].body.actual_start_time, null);
  assert.equal(calls[0].body.actual_end_time, null);
  assert.equal(calls[0].body.stopped_early, false);
  assert.equal(calls[0].body.failure_reason, undefined);
});
test('active completion uses the existing execution and does not create a second AI request', async () => {
  calls.length = 0;
  await savePlanOutcome(taskId, 'completed', { completion_ratio: 1, interruption_count: 2 }, undefined, undefined, 'active-id');
  assert.equal(calls.length, 1);
  assert.ok(calls[0].url.endsWith('/executions/active-id/complete'));
  assert.equal(calls[0].method, 'PATCH');
  assert.equal(calls[0].body.interruption_count, 2);
  assert.equal(calls[0].body.actual_start_time, undefined);
  assert.equal(calls[0].body.actual_end_time, undefined);
});


test('duration suggestion encodes the draft and edit exclusion using authenticated GET', async (t) => {
  const previousFetch = global.fetch;
  t.after(() => { global.fetch = previousFetch; });
  let request;
  global.fetch = async (url, options) => {
    request = { url: new URL(url), options };
    return new Response(JSON.stringify({ available: false, recommended_minutes: null }), {
      status: 200, headers: { 'content-type': 'application/json' },
    });
  };
  const result = await getDurationRecommendation('  Read & write  ', 'Study', 35, taskId);
  assert.equal(result.available, false);
  assert.equal(request.url.pathname, '/analytics/duration-recommendation');
  assert.equal(request.url.searchParams.get('title'), 'Read & write');
  assert.equal(request.url.searchParams.get('category'), 'Study');
  assert.equal(request.url.searchParams.get('planned_minutes'), '35');
  assert.equal(request.url.searchParams.get('exclude_task_id'), taskId);
  assert.equal(request.url.searchParams.has('user_id'), false);
  assert.equal(request.options.headers.Authorization, 'Bearer test-token');
});

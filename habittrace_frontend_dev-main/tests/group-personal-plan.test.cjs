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

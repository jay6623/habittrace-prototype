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
const { savePlanOutcome } = require('../lib/api.ts');
const { buildOutcomeInput, outcomeConfirmation, EMPTY_OUTCOME_DRAFT } = require('../lib/outcome.ts');
const { formatScheduledRange, formatScheduledEnd } = require('../lib/mobile-task.ts');
Module._load = originalLoad;

const taskId = '22222222-2222-4222-8222-222222222222';
const NOW = new Date('2026-10-20T20:30:00');
const draft = (changes) => ({ ...EMPTY_OUTCOME_DRAFT, ...changes });
function build(changes, options = {}) {
  const result = buildOutcomeInput(draft(changes), { now: NOW, ...options });
  assert.equal(result.ok, true, result.error);
  return result.input;
}
let calls = [];
let respond = (body) => new Response(JSON.stringify({ id: 'saved', ...body }), { status: 201, headers: { 'content-type': 'application/json' } });
global.fetch = async (url, options) => {
  const body = JSON.parse(options.body);
  calls.push({ url, method: options.method, body });
  return respond(body);
};

test('scheduled ranges use start + duration, including the user-study example', () => {
  assert.equal(formatScheduledRange('7:15 PM', 45), '7:15 PM – 8:00 PM');
  assert.equal(formatScheduledRange('19:15', 45), '7:15 PM – 8:00 PM');
  assert.equal(formatScheduledRange('11:30 AM', 60), '11:30 AM – 12:30 PM');
  assert.equal(formatScheduledEnd('7:15 PM', 45), '8:00 PM');
});

test('plans that cross midnight are labelled as ending the next day', () => {
  assert.equal(formatScheduledRange('11:30 PM', 45), '11:30 PM – 12:15 AM (next day)');
  assert.equal(formatScheduledRange('10:00 PM', 120), '10:00 PM – 12:00 AM (next day)');
  assert.equal(formatScheduledRange('11:00 PM', 1500), '11:00 PM – 12:00 AM (+2 days)');
  assert.equal(formatScheduledRange('not a time', 30), 'not a time');
});

test('selecting nothing cannot be submitted', () => {
  const result = buildOutcomeInput(draft({}), { now: NOW });
  assert.equal(result.ok, false);
});

test('1. completed + finish time stores only the reported finish, no start', async () => {
  const input = build({ choice: 'completed', finishedAt: '2026-10-20T20:05' });
  assert.equal(input.task_status, 'success');
  assert.equal(input.outcome_status, 'completed');
  assert.equal(input.actual_end_time, new Date('2026-10-20T20:05').toISOString());
  assert.equal(input.actual_start_time, undefined);
  calls = [];
  await savePlanOutcome(taskId, input);
  assert.ok(calls[0].url.endsWith('/executions'));
  assert.equal(calls[0].body.actual_start_time, null);
  assert.equal(calls[0].body.actual_end_time, input.actual_end_time);
  assert.equal(calls[0].body.idempotency_key, taskId); // server de-duplicates repeated submits
});

test('2. completed + blank stores no actual times; the scheduled end is display-only', async () => {
  const input = build({ choice: 'completed' });
  assert.equal(input.actual_end_time, undefined);
  assert.equal(input.actual_end_unknown, true);
  calls = [];
  await savePlanOutcome(taskId, input);
  assert.equal(calls[0].body.actual_start_time, null);
  assert.equal(calls[0].body.actual_end_time, null);
  assert.equal(outcomeConfirmation(input, formatScheduledEnd('7:15 PM', 45)), 'Marked completed · scheduled end 8:00 PM.');
});

test('3. not completed + minutes records minutes only, with an optional reason', async () => {
  const input = build({ choice: 'not_completed', minutesSpent: '20' });
  assert.equal(input.task_status, 'failed');
  assert.equal(input.outcome_status, 'abandoned');
  assert.equal(input.active_minutes, 20);
  assert.equal(input.failure_reason, undefined);
  assert.equal(input.stopped_early, true);
  calls = [];
  await savePlanOutcome(taskId, input);
  assert.equal(calls[0].body.actual_start_time, null);
  assert.equal(calls[0].body.actual_end_time, null);
  assert.equal(build({ choice: 'not_completed', minutesSpent: '0', reason: 'interruption' }).failure_reason, 'interruption');
  assert.equal(build({ choice: 'not_completed', minutesSpent: '0' }).active_minutes, 0);
});

test('4. not completed + blank is an unknown duration, not a confirmed not_started', () => {
  const input = build({ choice: 'not_completed' });
  assert.equal(input.outcome_status, 'abandoned');
  assert.equal(input.active_minutes, null);
  assert.equal(input.stopped_early, false);
  assert.equal(outcomeConfirmation(input, '8:00 PM'), 'Marked not completed.');
});

test('invalid optional details are rejected before any request', () => {
  for (const changes of [
    { choice: 'completed', finishedAt: '2026-10-20T23:00' }, // future
    { choice: 'completed', finishedAt: 'nonsense' },
    { choice: 'not_completed', minutesSpent: '-1' },
    { choice: 'not_completed', minutesSpent: '2.5' },
    { choice: 'not_completed', minutesSpent: '1441' },
  ]) {
    assert.equal(buildOutcomeInput(draft(changes), { now: NOW }).ok, false, JSON.stringify(changes));
  }
});

test('legacy started plan keeps its start; Submit time is never used as the finish', async () => {
  const activeStart = '2026-10-20T19:20:00';
  const blank = build({ choice: 'completed' }, { activeStart });
  assert.equal(blank.actual_end_unknown, true);
  calls = [];
  await savePlanOutcome(taskId, blank, 'active-id');
  assert.ok(calls[0].url.endsWith('/executions/active-id/complete'));
  assert.equal(calls[0].method, 'PATCH');
  assert.equal(calls[0].body.actual_end_time, undefined);
  assert.equal(calls[0].body.actual_end_unknown, true);
  const reported = build({ choice: 'completed', finishedAt: '2026-10-20T20:00' }, { activeStart });
  assert.equal(reported.actual_end_time, new Date('2026-10-20T20:00').toISOString());
  const early = buildOutcomeInput(draft({ choice: 'completed', finishedAt: '2026-10-20T19:00' }), { now: NOW, activeStart });
  assert.equal(early.ok, false);
  assert.equal(build({ choice: 'not_completed', minutesSpent: '5' }, { activeStart }).actual_end_unknown, true);
});

test('API failures reject so the sheet can show an error and keep the selection', async () => {
  const previous = respond;
  respond = () => new Response(JSON.stringify({ detail: 'down' }), { status: 503, headers: { 'content-type': 'application/json' } });
  try {
    await assert.rejects(savePlanOutcome(taskId, build({ choice: 'completed' })));
  } finally {
    respond = previous;
  }
});

test('success and failure keep the existing task_status contract used by analytics', () => {
  assert.equal(build({ choice: 'completed' }).completion_ratio, 1);
  assert.equal(build({ choice: 'not_completed' }).completion_ratio, 0);
  assert.equal(build({ choice: 'completed' }).task_status, 'success');
  assert.equal(build({ choice: 'not_completed', minutesSpent: '30' }).task_status, 'failed');
});

test('unreported interruptions are sent as null (unknown), never as 0', async () => {
  for (const changes of [{ choice: 'completed' }, { choice: 'completed', finishedAt: '2026-10-20T20:05' },
    { choice: 'not_completed' }, { choice: 'not_completed', minutesSpent: '20' }]) {
    const input = build(changes);
    assert.equal(input.interruption_count, null, JSON.stringify(changes));
    calls = [];
    await savePlanOutcome(taskId, input);
    assert.equal(calls[0].body.interruption_count, null);
  }
});

test('an omitted interruption count keeps the legacy default of 0', async () => {
  calls = [];
  await savePlanOutcome(taskId, { task_status: 'success', outcome_status: 'completed', completion_ratio: 1 });
  assert.equal(calls[0].body.interruption_count, 0);
});

test('"I didn\'t start this task" under Not completed records a confirmed not_started', () => {
  const input = build({ choice: 'not_completed', didNotStart: true, minutesSpent: '15', reason: 'low_readiness' });
  assert.equal(input.outcome_status, 'not_started');
  assert.equal(input.task_status, 'failed');
  assert.equal(input.interruption_count, 0);
  assert.equal(input.active_minutes, undefined); // minutes are ignored for a plan never started
  assert.equal(input.actual_end_time, undefined);
  assert.equal(input.failure_reason, 'low_readiness');
  assert.equal(outcomeConfirmation(input, '8:00 PM'), 'Marked not completed · not started.');
  const started = buildOutcomeInput(draft({ choice: 'not_completed', didNotStart: true }), { now: NOW, activeStart: '2026-10-20T19:20:00' });
  assert.equal(started.ok, false); // a recorded start cannot be relabelled as never started
});

test('the not-started checkbox has no effect when Completed is chosen', () => {
  assert.equal(build({ choice: 'completed', didNotStart: true }).outcome_status, 'completed');
});

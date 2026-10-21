const fs = require('node:fs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const ts = require('typescript');
require.extensions['.ts'] = (module, filename) => {
  module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS },
  }).outputText, filename);
};
// Only type imports reach ./api from ./outcome, so no network module is loaded.
const { buildRevisionInput } = require('../lib/outcome.ts');

const NOW = new Date('2026-10-20T21:00:00');
const local = (iso) => {
  const d = new Date(iso);
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
};
const record = (changes = {}) => ({
  actual_start_time: null, actual_end_time: null, active_minutes: null,
  outcome_status: 'abandoned', stopped_early: false, ...changes,
});
const draft = (changes = {}) => ({
  result: 'abandoned', actualStart: '', actualEnd: '', interruptions: '0',
  progress: '', minutesSpent: '', reason: '', ...changes,
});
function revise(d, existing) {
  const built = buildRevisionInput(d, existing, NOW);
  assert.equal(built.ok, true, built.error);
  return built.input;
}

test('both times unknown: editing the reason sends no times, so none are invented', () => {
  const input = revise(draft({ reason: 'interruption' }), record());
  assert.equal(input.failure_reason, 'interruption');
  assert.equal('actual_start_time' in input, false);
  assert.equal('actual_end_time' in input, false);
  assert.equal(input.active_minutes, null);
});

test('finish time only: a completed record keeps its reported finish and no start', () => {
  const end = '2026-10-20T20:05:00.000Z';
  const input = revise(draft({ result: 'completed', actualEnd: local(end) }),
    record({ outcome_status: 'completed', actual_end_time: end }));
  assert.equal(input.actual_end_time, end);
  assert.equal('actual_start_time' in input, false);
  assert.equal(input.completion_ratio, 1);
});

test('legacy start only: the recorded start is kept and the finish stays unknown', () => {
  const start = '2026-10-20T19:20:00.000Z';
  const input = revise(draft({ result: 'completed', actualStart: local(start) }),
    record({ outcome_status: 'completed', actual_start_time: start }));
  assert.equal(input.actual_start_time, start);
  assert.equal('actual_end_time' in input, false);
});

test('both times present: the range is validated and kept', () => {
  const start = '2026-10-20T19:15:00.000Z', end = '2026-10-20T20:00:00.000Z';
  const existing = record({ actual_start_time: start, actual_end_time: end, active_minutes: 30, stopped_early: true });
  const input = revise(draft({ actualStart: local(start), actualEnd: local(end), minutesSpent: '30', reason: 'other' }), existing);
  assert.equal(input.actual_start_time, start);
  assert.equal(input.actual_end_time, end);
  assert.equal(input.active_minutes, 30);
  assert.equal(input.stopped_early, true); // unchanged result keeps the stored flag
  assert.equal(buildRevisionInput(draft({ actualStart: local(end), actualEnd: local(start) }), existing, NOW).ok, false);
  assert.equal(buildRevisionInput(draft({ actualStart: local(start), actualEnd: local(end), minutesSpent: '50' }), existing, NOW).ok, false);
});

test('editing details keeps reported minutes instead of erasing them', () => {
  const input = revise(draft({ minutesSpent: '20', reason: 'low_readiness' }), record({ active_minutes: 20, stopped_early: true }));
  assert.equal(input.active_minutes, 20);
  assert.equal(input.stopped_early, true);
  const completed = revise(draft({ result: 'completed' }), record({ outcome_status: 'completed', active_minutes: 12 }));
  assert.equal(completed.active_minutes, 12);
});

test('failure reason is optional when editing', () => {
  const input = revise(draft({ result: 'partial', progress: '40' }), record({ outcome_status: 'partial' }));
  assert.equal(input.failure_reason, undefined);
  assert.equal(input.completion_ratio, 0.4);
});

test('a saved time can be corrected but never silently erased', () => {
  const start = '2026-10-20T19:20:00.000Z';
  const built = buildRevisionInput(draft({ result: 'completed' }), record({ outcome_status: 'completed', actual_start_time: start }), NOW);
  assert.equal(built.ok, false);
});

test('future times and invalid partial progress are rejected', () => {
  assert.equal(buildRevisionInput(draft({ actualEnd: '2026-10-21T09:00' }), record(), NOW).ok, false);
  assert.equal(buildRevisionInput(draft({ actualStart: '2026-10-21T09:00' }), record(), NOW).ok, false);
  assert.equal(buildRevisionInput(draft({ result: 'partial', progress: '100' }), record(), NOW).ok, false);
});

test('changing to not started clears execution details', () => {
  const input = revise(draft({ result: 'not_started' }), record({ actual_start_time: '2026-10-20T19:20:00.000Z' }));
  assert.equal(input.outcome_status, 'not_started');
  assert.equal(input.interruption_count, 0);
  assert.equal('actual_start_time' in input, false);
});

test('a blank interruption count stays unknown; a stored count is kept', () => {
  assert.equal(revise(draft({ interruptions: '' }), record()).interruption_count, null);
  assert.equal(revise(draft({ interruptions: '3' }), record()).interruption_count, 3);
  assert.equal(revise(draft({ interruptions: '0' }), record()).interruption_count, 0);
  assert.equal(buildRevisionInput(draft({ interruptions: '-1' }), record(), NOW).ok, false);
});

test('historical statuses stay editable without being converted', () => {
  const partial = revise(draft({ result: 'partial', progress: '35', interruptions: '2', reason: 'other' }),
    record({ outcome_status: 'partial', stopped_early: true }));
  assert.equal(partial.outcome_status, 'partial');
  assert.equal(partial.completion_ratio, 0.35);
  assert.equal(partial.stopped_early, true);
  const abandoned = revise(draft({ result: 'abandoned', interruptions: '' }), record({ outcome_status: 'abandoned', stopped_early: true }));
  assert.equal(abandoned.outcome_status, 'abandoned');
  assert.equal(abandoned.stopped_early, true); // legacy flag preserved
  const notStarted = revise(draft({ result: 'not_started', reason: 'low_readiness' }), record({ outcome_status: 'not_started' }));
  assert.equal(notStarted.outcome_status, 'not_started');
  assert.equal(notStarted.failure_reason, 'low_readiness');
});

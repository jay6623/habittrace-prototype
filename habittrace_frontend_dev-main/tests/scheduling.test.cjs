const fs = require('node:fs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const ts = require('typescript');
require.extensions['.ts'] = (module, filename) => {
  module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, filename);
};
const { overlappingTasks, findFreeSlots } = require('../lib/scheduling.ts');
const { taskTimeInMinutes, localDateString, createQuickAddDefaults } = require('../lib/mobile-task.ts');
const { readPreferences } = require('../lib/preferences.ts');
const plan = (id, time, minutes = 30, date = '2026-09-08') => ({ id, planned_start_time: time, planned_duration_min: minutes, planned_date: date, task_status: 'pending' });
test('preserves minute precision and handles noon, midnight, invalid times', () => {
  assert.equal(taskTimeInMinutes('12:05 AM'), 5);
  assert.equal(taskTimeInMinutes('12:45 PM'), 765);
  assert.equal(taskTimeInMinutes('23:59'), 1439);
  assert.equal(taskTimeInMinutes('25:99'), Number.MAX_SAFE_INTEGER);
});
test('detects only real overlaps on the same day', () => {
  const result = overlappingTasks([plan('a','9:15 AM'),plan('b','9:30 AM'),plan('c','10:00 AM'),plan('d','9:15 AM',30,'2026-09-09')]);
  assert.deepEqual([...result].sort(), ['a','b']);
});
test('free times honor buffer, planning hours, current time, and selected task exclusion', () => {
  const selected = plan('a','9:00 AM');
  const slots = findFreeSlots([selected,plan('b','10:00 AM',60)],selected,'09:00','12:00',9*60+1);
  assert.deepEqual(slots, [555,675,690]);
});
test('too-long plans have no invented available times', () => {
  assert.deepEqual(findFreeSlots([],plan('a','09:00',240),'09:00','10:00'), []);
});
test('local day does not use UTC and defaults remain valid near midnight', () => {
  assert.equal(localDateString(new Date(2026,8,8,23,55)), '2026-09-08');
  assert.match(createQuickAddDefaults().plannedTime,/^\d{2}:\d{2}$/);
});
test('preferences reject malformed persisted values', () => {
  assert.deepEqual(readPreferences({ planning_preferences: { defaultDuration: -2, workStart: '99:00' } }), { defaultDuration:30,workStart:'09:00',workEnd:'22:00' });
});

const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const Module = require('node:module');
const ts = require('typescript');
const React = require('react');
const { renderToStaticMarkup } = require('react-dom/server');
const root = path.resolve(__dirname, '..');
for (const ext of ['.ts', '.tsx']) require.extensions[ext] = (module, filename) => module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX } }).outputText, filename);
const originalLoad = Module._load;
let fail = false, writes = [], changed = 0;
const task = { id: 'existing-plan', title: 'Original plan', notes: 'Keep note', planned_date: '2026-05-31', planned_start_time: '11:45 PM', planned_duration_min: 35, task_category: 'Work', importance: 4, energy_level: 2, focus_level: 5, task_status: 'success', total_tasks_today: 7 };
Module._load = function(request, ...args) {
  if (request === '@/lib/api') return { getTasks: async () => [task], updateTask: async (id, payload) => { writes.push({id, payload}); if (fail) throw Error('Unavailable'); changed++; return {...task, ...payload}; } };
  if (request === '@/lib/refresh') return {useDataRefresh() {}};
  if (request === '@/components/ui/toast') return {useToast: () => ({record() {}})};
  if (request === './quick-add-form') return {__esModule: true, default: () => null};
  if (request.startsWith('@/')) return originalLoad.call(this, path.join(root, request.slice(2)), ...args);
  return originalLoad.call(this, request, ...args);
};
const Edit = require('../components/mobile/plan-edit-form.tsx').default;
const Calendar = require('../components/mobile/mobile-calendar.tsx').default;
function renderCalendar(states) {
  const original = React.useState; let index = 0;
  React.useState = (value) => original(Object.hasOwn(states, index) ? states[index++] : (index++, value));
  try { return renderToStaticMarkup(React.createElement(Calendar)); } finally { React.useState = original; }
}
test('calendar edit prefills minute precision, excludes itself and preserves stored readiness/status', async () => {
  let saved;
  const form = Edit({task, onDismiss() {}, onSaved(value) {saved = value;}});
  assert.equal(form.props.initialDraft.plannedTime, '23:45');
  assert.equal(form.props.initialDraft.durationMinutes, 35);
  assert.equal(form.props.excludeTaskId, task.id);
  await form.props.onSubmit({...form.props.initialDraft, title: 'Moved plan', plannedDate: '2026-06-01', plannedTime: '00:15'});
  assert.equal(writes.length, 1);
  assert.equal(writes[0].id, task.id);
  assert.equal(writes[0].payload.planned_start_time, '12:15 AM');
  assert.equal(saved.planned_date, '2026-06-01');
  assert.equal(saved.title, 'Moved plan');
  assert.equal(saved.energy_level, 2);
  assert.equal(saved.focus_level, 5);
  assert.equal(saved.task_status, 'success');
  assert.equal(saved.total_tasks_today, 7);
  assert.equal(task.planned_date, '2026-05-31');
});
test('failed schedule save rejects to the existing error-preserving form and never commits UI state', async () => {
  fail = true; let saved = false;
  const form = Edit({task, onDismiss() {}, onSaved() {saved = true;}});
  const draft = {...form.props.initialDraft, title: 'Unsaved input'};
  await assert.rejects(form.props.onSubmit(draft), /Unavailable/);
  assert.equal(saved, false);
  assert.equal(changed, 1);
  assert.equal(draft.title, 'Unsaved input');
  assert.equal(task.title, 'Original plan');
  fail = false;
});
test('six-week month renders all 42 date buttons including the last row', () => {
  const html = renderCalendar({0:new Date(2026,4,1,12),1:'2026-05-31',3:false});
  assert.equal((html.match(/aria-label="[A-Z][a-z]+ \d+, 2026[^"]*" aria-pressed=/g) || []).length,42);
  assert.match(html,/April 26, 2026/);
  assert.match(html,/June 6, 2026/);
  assert.match(html,/May 31, 2026/);
  assert.doesNotMatch(html,/min-w-\[560px\]/);
  assert.match(html,/No plans yet/);
});
test('selected date plans expose an edit action and a bounded scrolling list', () => {
  const html = renderCalendar({0:new Date(2026,4,1,12),1:'2026-05-31',2:[task],3:false});
  assert.match(html,/aria-label="Edit Original plan"/);
  assert.match(html,/11:45 PM/);
  assert.match(html,/Selected day plans/);
  assert.match(html,/overflow-y-auto/);
  assert.match(html,/1 plan/);
});

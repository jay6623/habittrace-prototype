const fs = require('node:fs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const Module = require('node:module');
const ts = require('typescript');
let renderedChartProps;
let renderedChartType;
for (const ext of ['.ts', '.tsx']) {
  require.extensions[ext] = (module, filename) => {
    module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX },
    }).outputText, filename);
  };
}
const originalLoad = Module._load;
Module._load = function(request, ...args) {
  if (request === './supabase') return { supabase: { auth: { getSession: async () => ({ data: { session: { access_token: 'test-token' } } }) } } };
  if (request === './refresh') return { notifyDataChanged() {} };
  if (request === '@/lib/coach-chart') return require('../lib/coach-chart.ts');
  // The canvas requires a browser. Render its React boundary and test its options/data.
  if (request === 'react-chartjs-2') {
    const React = require('react');
    return Object.fromEntries(['Bar', 'Line'].map(name => [name, props => {
      renderedChartProps = props;
      renderedChartType = name;
      return React.createElement('canvas', {
        role: props.role, 'aria-label': props['aria-label'],
        'data-series': JSON.stringify(props.data),
      });
    }]));
  }
  return originalLoad.call(this, request, ...args);
};
const { streamChatEvents, streamChat, getLatestCoachConversation } = require('../lib/api.ts');
const { isCoachChart, chartSeries, coachChartForDisplay, coachChartTick, coachChartTickLimit } = require('../lib/coach-chart.ts');
const CoachChart = require('../components/coach-chart.tsx').default;
Module._load = originalLoad;
const React = require('react');
const { renderToStaticMarkup } = require('react-dom/server');
const chart = {
  chart_type: 'line', title: 'Study progress', x_axis: 'Date', y_axis: 'Completion rate (%)',
  units: 'percent', period: { start: '2026-10-01', end: '2026-10-03' },
  sample_size: 10, note: 'Recorded outcomes only.', interval_days: 1,
  data: [{ label: '2026-10-01', value: 80, sample_size: 5 }, { label: '2026-10-03', value: 40, sample_size: 5 }],
};

test('schema rejects malformed, empty, nonfinite, and inconsistent charts', () => {
  assert.equal(isCoachChart(chart), true);
  for (const bad of [null, {}, { ...chart, data: [] }, { ...chart, units: 'html' },
    { ...chart, sample_size: 99 }, { ...chart, data: [{ ...chart.data[0], value: NaN }, chart.data[1]] },
    { ...chart, data: [{ ...chart.data[0], value: 101 }, chart.data[1]] }]) {
    assert.equal(isCoachChart(bad), false);
  }
});

test('daily and weekly series leave missing periods null, never zero', () => {
  assert.deepEqual(chartSeries(chart).map(p => p.value), [80, null, 40]);
  const weekly = { ...chart, interval_days: 7, data: [
    { ...chart.data[0], label: '2026-10-05' }, { ...chart.data[1], label: '2026-10-19' },
  ] };
  assert.deepEqual(chartSeries(weekly).map(p => p.value), [80, null, 40]);
});

test('fragmented SSE delivers charts alongside existing tokens and proposals with auth', async () => {
  const wire = `data: ${JSON.stringify({ conversation_id: 'conversation' })}\n\ndata: {"token":"Hi "}\n\ndata: ${JSON.stringify({ chart })}\n\ndata: {"proposal":{"id":"p"}}\n\ndata: {"chart":{"bad":true}}\n\ndata: {"token":"there"}\n\ndata: [DONE]\n\n`;
  let request;
  global.fetch = async (_url, options) => {
    request = options;
    return new Response(new ReadableStream({ start(controller) {
      const bytes = new TextEncoder().encode(wire);
      for (let i = 0; i < bytes.length; i += 13) controller.enqueue(bytes.slice(i, i + 13));
      controller.close();
    } }));
  };
  const events = [];
  for await (const event of streamChatEvents('Review my habits', [])) events.push(event);
  assert.deepEqual(events.map(e => e.type), ['conversation', 'token', 'chart', 'proposal', 'token']);
  assert.deepEqual(events[2].chart, chart);
  assert.equal(request.headers.Authorization, 'Bearer test-token');
  let text = '';
  for await (const token of streamChat('Review my habits', [])) text += token;
  assert.equal(text, 'Hi there');
});

test('restored metadata remains available alongside historical text-only messages', async () => {
  global.fetch = async () => new Response(JSON.stringify({ id: 'conversation', pending_proposals: [], messages: [
    { id: 'old', role: 'assistant', content: 'Old text' },
    { id: 'new', role: 'assistant', content: 'Progress', metadata: { chart } },
  ] }));
  const result = await getLatestCoachConversation();
  assert.equal(result.messages[0].metadata, undefined);
  assert.ok(isCoachChart(result.messages[1].metadata.chart));
});

test('bar and line components render accessible labels, real samples, and safe text', () => {
  for (const chart_type of ['bar', 'line']) {
    const html = renderToStaticMarkup(React.createElement(CoachChart, { chart: { ...chart, chart_type, title: '<script>unsafe</script>' } }));
    assert.ok(html.includes('role="img"'));
    assert.ok(html.includes('View chart data'));
    assert.ok(html.includes('10 plotted observations'));
    assert.ok(html.includes('80%'));
    assert.ok(!html.includes('<script>'));
  }
  assert.equal(renderToStaticMarkup(React.createElement(CoachChart, { chart: { ...chart, data: [] } })), '');
});

const weeklyChart = {
  ...chart, interval_days: 7, focus: 'trend', sample_size: 17,
  period: { start: '2026-08-21', end: '2026-10-19' },
  note: 'Weeks with fewer than 5 outcomes are uncertain; see sample sizes.',
  data: [
    { label: '2026-08-31', value: 0, sample_size: 2, completed: 0 },
    { label: '2026-09-07', value: 71.4, sample_size: 7, completed: 5 },
    { label: '2026-09-14', value: 50, sample_size: 2, completed: 1 },
    { label: '2026-09-28', value: 100, sample_size: 4, completed: 4 },
    { label: '2026-10-05', value: 50, sample_size: 2, completed: 1 },
  ],
};

test('60-day weekly SSE chart accepts small valid samples and preserves a missing week as a gap', async () => {
  global.fetch = async () => new Response(`data: ${JSON.stringify({ chart: weeklyChart })}\n\ndata: [DONE]\n\n`);
  const events = [];
  for await (const event of streamChatEvents('How has my habit completion rate changed over the last 60 days?', [])) events.push(event);
  assert.equal(events.length, 1);
  assert.deepEqual(events[0].chart, weeklyChart);
  assert.deepEqual(chartSeries(events[0].chart).map(p => p.value), [0, 71.4, 50, null, 100, 50]);
  const html = renderToStaticMarkup(React.createElement(CoachChart, { chart: events[0].chart }));
  assert.ok(html.includes('17 plotted observations'));
  assert.ok(html.includes('71.4%'));
  assert.ok(html.includes('5/7 completed'));
  assert.equal(renderedChartType, 'Line');
  assert.equal(renderedChartProps.options.plugins.tooltip.callbacks.label({
    dataIndex: 1, formattedValue: '71.4',
  }), '71.4% (5/7 completed)');
  const gap = chartSeries(events[0].chart)[3];
  assert.equal(gap.value, null);
  assert.equal(gap.completed, null);
});

test('narrow chart axes abbreviate dates and reduce ticks without changing tooltips or values', () => {
  renderToStaticMarkup(React.createElement(CoachChart, { chart: weeklyChart }));
  const { data, options } = renderedChartProps;
  assert.equal(coachChartTick('2026-08-31'), 'Aug 31');
  assert.deepEqual(coachChartTick('2026-08-21 – 2026-10-19'), ['Aug 21', '– Oct 19']);
  assert.equal(coachChartTick('09:00'), '09:00');
  const ticks = options.scales.x.ticks;
  assert.equal(ticks.maxRotation, 0);
  assert.equal(ticks.autoSkip, true);
  assert.equal(ticks.callback.call({ getLabelForValue: i => data.labels[i] }, 0), 'Aug 31');
  assert.equal(data.labels[0], '2026-08-31'); // full tooltip date preserved
  const instance = { options: { scales: { x: { ticks: {} } } } };
  options.onResize(instance, { width: 200, height: 256 });
  assert.equal(instance.options.scales.x.ticks.maxTicksLimit, 2);
  options.onResize(instance, { width: 600, height: 256 });
  assert.equal(instance.options.scales.x.ticks.maxTicksLimit, 6);
  assert.equal(coachChartTickLimit(0), 2);
});

const comparisonChart = {
  ...chart, chart_type: 'bar', focus: 'comparison', interval_days: null,
  title: 'Completion rate by period', x_axis: 'Recorded period', sample_size: 22,
  period: { start: '2026-06-22', end: '2026-10-19' },
  data: [
    { label: '2026-06-22 – 2026-08-20', value: 0, sample_size: 5, completed: 0 },
    { label: '2026-08-21 – 2026-10-19', value: 64.7, sample_size: 17, completed: 11 },
  ],
};

test('two-period comparison streams and restores as bars with completed/total counts', async () => {
  global.fetch = async () => new Response(`data: ${JSON.stringify({ chart: comparisonChart })}\n\ndata: [DONE]\n\n`);
  const events = [];
  for await (const event of streamChatEvents('Compare the last 60 days to the preceding 60 days', [])) events.push(event);
  assert.ok(isCoachChart(events[0].chart));
  global.fetch = async () => new Response(JSON.stringify({ id: 'conversation', pending_proposals: [], messages: [
    { id: 'comparison', role: 'assistant', content: 'Period comparison', metadata: { chart: events[0].chart } },
  ] }));
  const restored = (await getLatestCoachConversation()).messages[0].metadata.chart;
  const html = renderToStaticMarkup(React.createElement(CoachChart, { chart: restored }));
  assert.equal(renderedChartType, 'Bar');
  assert.ok(html.includes('11/17 completed'));
  assert.equal(renderedChartProps.options.plugins.tooltip.callbacks.label({
    dataIndex: 1, formattedValue: '64.7',
  }), '64.7% (11/17 completed)');
  assert.deepEqual(chartSeries(restored), comparisonChart.data);
});

test('historical two-period aggregate lines display as bars without fabricating completed counts', () => {
  const legacy = {
    ...comparisonChart, chart_type: 'line', focus: 'trend', title: 'Completion rate over time',
    data: comparisonChart.data.map(({ label, value, sample_size }) => ({ label, value, sample_size })),
  };
  assert.ok(isCoachChart(legacy));
  assert.equal(coachChartForDisplay(legacy).chart_type, 'bar');
  const html = renderToStaticMarkup(React.createElement(CoachChart, { chart: legacy }));
  assert.equal(renderedChartType, 'Bar');
  assert.ok(html.includes('Completion rate by period'));
  assert.ok(html.includes('n=17'));
  assert.ok(!html.includes('11/17 completed'));
  assert.equal(coachChartForDisplay(weeklyChart).chart_type, 'line');
});

test('completed counts reject inconsistent data but tolerate backend rounding and historical absence', () => {
  assert.ok(isCoachChart(chart));
  assert.equal(isCoachChart({ ...weeklyChart, data: weeklyChart.data.map(p => ({ ...p, completed: 99 })) }), false);
  assert.equal(isCoachChart({ ...weeklyChart, data: weeklyChart.data.map(p => ({ ...p, completed: 0 })) }), false);
  assert.ok(isCoachChart({ ...chart, sample_size: 85, data: [
    { label: 'A', value: 1.2, sample_size: 80, completed: 1 },
    { label: 'B', value: 80, sample_size: 5, completed: 4 },
  ] }));
});

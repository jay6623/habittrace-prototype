const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const ts = require('typescript');

function client() {
  let token = 'first';
  const requests = [];
  const source = ts.transpileModule(fs.readFileSync(path.join(__dirname, '../lib/api.ts'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS },
  }).outputText;
  const exports = {};
  vm.runInNewContext(source, {
    exports, process: { env: {} }, console,
    require(name) {
      if (name === './supabase') return { supabase: { auth: { getSession: async () => ({ data: { session: { access_token: token } } }) } } };
      if (name === './refresh') return { notifyDataChanged() {} };
      return {};
    },
    fetch: async (url, options) => new Promise(resolve => requests.push({ url, options, resolve })),
  });
  return { api: exports, requests, setToken(value) { token = value; } };
}
const tick = () => new Promise(resolve => setImmediate(resolve));
const finish = request => request.resolve({ ok: true, status: 200, json: async () => [] });

test('concurrent identical reads share one request but settled results are not cached', async () => {
  const { api, requests } = client();
  const first = api.getTasks(), second = api.getTasks();
  await tick();
  assert.equal(requests.length, 1);
  finish(requests[0]);
  await Promise.all([first, second]);
  const third = api.getTasks();
  await tick();
  assert.equal(requests.length, 2);
  finish(requests[1]);
  await third;
});

test('different sessions never share an in-flight response', async () => {
  const { api, requests, setToken } = client();
  const first = api.getTasks();
  await tick();
  setToken('second');
  const second = api.getTasks();
  await tick();
  assert.equal(requests.length, 2);
  assert.notEqual(requests[0].options.headers.Authorization, requests[1].options.headers.Authorization);
  requests.forEach(finish);
  await Promise.all([first, second]);
});

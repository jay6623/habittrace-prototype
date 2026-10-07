// Usage: node supabase/tests/task_ai_sync.test.mjs /path/to/pglite/dist/index.js
// Runs against an isolated in-memory PostgreSQL; no production credentials.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const { PGlite } = await import(pathToFileURL(process.argv[2]).href);
const db = new PGlite();
const owner = "11111111-1111-4111-8111-111111111111";
const one = "22222222-2222-4222-8222-222222222222";
const two = "33333333-3333-4333-8333-333333333333";
const legacy = "44444444-4444-4444-8444-444444444444";
const migration = await readFile(new URL("../task_ai_sync_schema.sql", import.meta.url), "utf8");
const primary = await readFile(new URL("../schema.sql", import.meta.url), "utf8");
await db.exec(`
  create schema auth;
  create role anon;
  create role authenticated;
  create role service_role bypassrls;
  create table auth.users(id uuid primary key);
  create function auth.uid() returns uuid language sql as $$ select '${owner}'::uuid $$;
  create function auth.role() returns text language sql as $$
    select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'service_role')
  $$;
  insert into auth.users values ('${owner}');
`);
await db.exec(primary.slice(primary.indexOf("CREATE TABLE IF NOT EXISTS tasks"), primary.indexOf("-- ── Executions")));

async function insert(id, time, duration = 60) {
  return (await db.query(`insert into public.tasks(
    id, user_id, title, task_category, planned_date, planned_start_time,
    planned_duration_min, importance, energy_level, focus_level
  ) values ($1, $2, 'Study', 'Study', '2026-10-07', $3, $4, 3, 3, 3) returning *`,
  [id, owner, time, duration])).rows[0];
}
async function rows(sql, args = []) { return (await db.query(sql, args)).rows; }

// Migration does not manufacture retrospective inputs for existing records.
await insert(legacy, "7:00 AM");
await db.exec(migration);
await db.exec(migration); // Safe to apply again.
assert.equal((await rows("select count(*)::int n from task_ai_sync_jobs"))[0].n, 0);
await db.exec(`update tasks set task_status = 'success' where id = '${legacy}'`);
assert.equal((await rows("select count(*)::int n from task_ai_sync_jobs"))[0].n, 0);

const first = await insert(one, "9:00 AM");
assert.equal(first.ai_sync_status, "pending");
let jobs = await rows("select * from task_ai_sync_jobs order by sequence");
assert.equal(jobs.length, 1);
assert.equal(jobs[0].id, first.ai_plan_input_id);
assert.equal(jobs[0].payload.parent_plan_input_id, null);
assert.equal(jobs[0].payload.daily_planned_minutes, 120);
assert.equal(jobs[0].payload.current_energy, null);
const original = JSON.stringify(jobs[0].payload);

await insert(two, "14:00", 30);
await db.exec(`update tasks set timezone_name = 'America/Denver', planned_start_time = '10:15 AM' where id = '${one}'`);
jobs = await rows("select * from task_ai_sync_jobs where task_id = $1 order by sequence", [one]);
assert.equal(jobs.length, 2);
assert.equal(JSON.stringify(jobs[0].payload), original);
assert.equal(jobs[1].payload.parent_plan_input_id, jobs[0].id);
assert.equal(jobs[1].payload.input_source, "reschedule");
assert.equal(new Date(jobs[1].payload.planned_start).toISOString(), "2026-10-07T16:15:00.000Z");

// Delivery acknowledgment and outcome changes do not create new revisions.
await db.exec(`update tasks set ai_sync_status = 'synced', task_status = 'success' where id = '${one}'`);
assert.equal((await rows("select count(*)::int n from task_ai_sync_jobs where task_id = $1", [one]))[0].n, 2);

// A bad task write must roll back both task and job, never leave half a pair.
await assert.rejects(insert("55555555-5555-4555-8555-555555555555", "25:00"));
assert.equal((await rows("select count(*)::int n from tasks"))[0].n, 3);

// Browser roles can save owned tasks but cannot forge delivery or read jobs.
await db.exec(`
  grant usage on schema public, auth to authenticated;
  grant select, insert, update, delete on tasks to authenticated;
  set request.jwt.claim.role = 'authenticated';
  set role authenticated;
`);
await db.exec(`update tasks set ai_sync_status = 'synced', ai_plan_input_id = gen_random_uuid() where id = '${two}'`);
const protectedTask = (await rows("select * from tasks where id = $1", [two]))[0];
assert.equal(protectedTask.ai_sync_status, "pending");
await assert.rejects(db.query("select * from task_ai_sync_jobs"));
await db.exec("reset role; reset request.jwt.claim.role;");

// Each captured payload is accepted by the AI project's real constraints.
await db.exec(await readFile(new URL("../ai_schema.sql", import.meta.url), "utf8"));
for (const job of await rows("select payload from task_ai_sync_jobs order by sequence")) {
  const keys = Object.keys(job.payload);
  await db.query(`insert into ai_plan_inputs (${keys.join(",")}) values (${keys.map((_, i) => `$${i + 1}`).join(",")})`,
    keys.map((key) => job.payload[key]));
}
assert.equal((await rows("select count(*)::int n from ai_plan_inputs"))[0].n, 3);
await db.close();
console.log("PASS: transactional queue, revisions, timezone, RLS, retry snapshots, and AI schema compatibility");

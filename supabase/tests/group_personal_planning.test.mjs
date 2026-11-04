// Usage: node supabase/tests/group_personal_planning.test.mjs /path/to/pglite/dist/index.js
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const { PGlite } = await import(pathToFileURL(process.argv[2]).href);
const db = new PGlite();
const one = "11111111-1111-4111-8111-111111111111";
const two = "22222222-2222-4222-8222-222222222222";
const group = "33333333-3333-4333-8333-333333333333";
const shared = "44444444-4444-4444-8444-444444444444";
const primary = await readFile(new URL("../schema.sql", import.meta.url), "utf8");
await db.exec(`
  create schema auth;
  create role authenticated;
  create role anon;
  create role service_role bypassrls;
  create table auth.users(id uuid primary key);
  create function auth.uid() returns uuid language sql as $$
    select current_setting('request.jwt.claim.sub', true)::uuid
  $$;
  create function auth.role() returns text language sql as $$ select 'service_role' $$;
  insert into auth.users values ('${one}'), ('${two}');
`);
await db.exec(primary.slice(primary.indexOf("CREATE TABLE IF NOT EXISTS tasks"), primary.indexOf("-- ── Executions")));
await db.exec(await readFile(new URL("../task_ai_sync_schema.sql", import.meta.url), "utf8"));
await db.exec(await readFile(new URL("../group_scheduling_schema.sql", import.meta.url), "utf8"));
const migration = await readFile(new URL("../group_personal_planning_schema.sql", import.meta.url), "utf8");
await db.exec(migration);
await db.exec(migration);
await db.exec(`
  insert into groups (id, owner_id, name, invite_code) values ('${group}', '${one}', 'Team', 'ABCD2345');
  insert into group_members (group_id, user_id) values ('${group}', '${one}'), ('${group}', '${two}');
  insert into group_tasks (id, group_id, created_by, title, estimated_duration_minutes)
    values ('${shared}', '${group}', '${one}', 'Shared work', 60);
  insert into group_task_assignees (group_id, task_id, user_id) values ('${group}', '${shared}', '${one}');
`);
async function insert(user) {
  return (await db.query(`insert into tasks (
    user_id, source_group_task_id, title, task_category, planned_date, planned_start_time,
    planned_duration_min, importance, energy_level, focus_level, ai_plan_details
  ) values ($1, $2, 'My work', 'Study', '2099-09-06', '10:00', 60, 3, 4, 3,
    '{"current_energy":2,"current_focus":4}') returning *`, [user, shared])).rows[0];
}

const task = await insert(one);
assert.equal(task.source_group_task_id, shared);
assert.equal(task.ai_sync_status, "pending");
const jobs = (await db.query("select payload from task_ai_sync_jobs where task_id = $1", [task.id])).rows;
assert.equal(jobs.length, 1);
assert.equal(jobs[0].payload.current_energy, 2);
assert.equal(jobs[0].payload.required_energy, 4);
await assert.rejects(insert(one), /duplicate key/);
await assert.rejects(insert(two), /Only current assigned group members/);

// Both assignees may independently plan the same task, but cannot read each other's plans.
await db.exec(`insert into group_task_assignees (group_id, task_id, user_id) values ('${group}', '${shared}', '${two}')`);
await insert(two);
await db.exec(`
  alter table tasks enable row level security;
  create policy owned_tasks on tasks for all using (user_id = auth.uid()) with check (user_id = auth.uid());
  grant usage on schema public, auth to authenticated;
  grant select, insert, update, delete on tasks to authenticated;
  set request.jwt.claim.sub = '${one}';
  set role authenticated;
`);
assert.equal((await db.query("select count(*)::int n from tasks")).rows[0].n, 1);
await assert.rejects(db.query("select * from group_task_assignees"), /permission denied/);
await db.exec("reset role;");

// Removing membership leaves personal history intact and editable.
await db.exec(`delete from group_members where group_id = '${group}' and user_id = '${one}'`);
await db.query("update tasks set planned_start_time = '11:00' where id = $1", [task.id]);
await assert.rejects(insert(one), /Only current assigned group members/);
await db.exec(`delete from groups where id = '${group}'`);
const remaining = (await db.query("select * from tasks")).rows;
assert.equal(remaining.length, 2);
assert.ok(remaining.every((row) => row.source_group_task_id === null));
await db.close();
console.log("PASS: group links, per-user uniqueness, assignment validation, RLS, AI snapshots, and history preservation");

// node supabase/tests/execution_optional_times.test.mjs /path/to/pglite/dist/index.js
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
const { PGlite } = await import(pathToFileURL(process.argv[2]).href);
const owner = '11111111-1111-4111-8111-111111111111';
async function file(name) { return readFile(new URL('../' + name, import.meta.url), 'utf8'); }

async function database({ optionalTimes }) {
 const db = new PGlite();
 await db.exec(`
  create schema auth; create role anon; create role authenticated; create role service_role bypassrls;
  create table auth.users(id uuid primary key);
  create function auth.uid() returns uuid language sql as $$ select '${owner}'::uuid $$;
  create function auth.role() returns text language sql as $$ select 'service_role' $$;
  insert into auth.users values ('${owner}');
 `);
 const primary = await file('schema.sql');
 await db.exec(primary.slice(primary.indexOf('CREATE TABLE IF NOT EXISTS tasks'), primary.indexOf('-- ── Predictions')));
 await db.exec(await file('task_ai_sync_schema.sql'));
 await db.exec(await file('execution_outcome_sync_schema.sql'));
 if (optionalTimes) {
  await db.exec(await file('execution_optional_times.sql'));
  await db.exec(await file('execution_optional_times.sql')); // repeatable
 }
 await db.exec(await file('ai_schema.sql'));
 await db.exec(await file('ai_outcome_delivery_schema.sql'));
 if (optionalTimes) {
  await db.exec(await file('ai_outcome_nullable_interruptions.sql'));
  await db.exec(await file('ai_outcome_nullable_interruptions.sql')); // repeatable
 }
 return db;
}

const db = await database({ optionalTimes: true });
async function rows(sql, args = []) { return (await db.query(sql, args)).rows; }
async function task() {
 return (await rows(`insert into tasks(user_id,title,task_category,planned_date,planned_start_time,planned_duration_min,importance,energy_level,focus_level)
 values ($1,'Study','Study',current_date + 1,'7:15 PM',45,3,3,3) returning *`,[owner]))[0];
}
async function deliverPlans() {
 for (const job of await rows(`select * from task_ai_sync_jobs where status='pending' order by sequence`)) {
  const keys = Object.keys(job.payload);
  await db.query(`insert into ai_plan_inputs(${keys.join(',')}) values(${keys.map((_,i)=>'$'+(i+1)).join(',')})`,keys.map(k=>job.payload[k]));
  await db.query(`update task_ai_sync_jobs set status='synced' where id=$1`,[job.id]);
 }
}
async function finished(values) {
 const plan = await task();
 const columns = { task_id: plan.id, user_id: owner, interruption_count: null, stopped_early: false, ...values };
 const keys = Object.keys(columns);
 const execution = (await rows(`insert into executions(${keys.join(',')}) values(${keys.map((_,i)=>'$'+(i+1)).join(',')}) returning *`,
  keys.map((k) => columns[k])))[0];
 const job = (await rows('select * from execution_ai_sync_jobs where execution_id=$1',[execution.id]))[0];
 return { plan, execution, job };
}
async function deliver(job) {
 await deliverPlans();
 await rows('select deliver_execution_outcome($1,$2,$3,$4,$5::jsonb,$6) id',
  [owner, job.plan_input_id, job.execution_id, job.sequence, JSON.stringify(job.payload), job.primary_reason_code]);
 return (await rows('select * from ai_plan_outcomes where plan_input_id=$1',[job.plan_input_id]))[0];
}
const completed = { task_status: 'success', outcome_status: 'completed', completion_ratio: 1 };
const notCompleted = { task_status: 'failed', outcome_status: 'abandoned', completion_ratio: 0 };

// 1. Completed + user-reported finish time: end only, no invented start.
const s1 = await finished({ ...completed, actual_end_time: new Date(Date.now() - 60_000).toISOString() });
assert.equal(s1.execution.actual_start_time, null);
assert.notEqual(s1.execution.actual_end_time, null);
assert.equal(s1.job.payload.actual_end, null); // AI project requires a start for an end
assert.equal(s1.job.payload.learning_eligible, true);
assert.equal((await rows('select task_status from tasks where id=$1',[s1.plan.id]))[0].task_status, 'success');
const ai1 = await deliver(s1.job);
assert.equal(ai1.outcome_status, 'completed'); assert.equal(ai1.actual_start, null); assert.equal(ai1.actual_end, null);
assert.equal(s1.execution.interruption_count, null); assert.equal(s1.job.payload.interruption_count, null);
assert.equal(ai1.interruption_count, null); // unknown stays unknown in the AI project

// 2. Completed + blank: no times stored; the scheduled end is a display fallback only.
const s2 = await finished(completed);
assert.equal(s2.execution.actual_start_time, null); assert.equal(s2.execution.actual_end_time, null);
assert.equal((await deliver(s2.job)).outcome_status, 'completed');

// 3. Not completed + reported minutes, no reason: minutes kept, no times invented.
const s3 = await finished({ ...notCompleted, active_minutes: 20, stopped_early: true });
assert.equal(s3.execution.active_minutes, 20); assert.equal(s3.execution.failure_reason, null);
assert.equal(s3.job.primary_reason_code, null);
const ai3 = await deliver(s3.job);
assert.equal(ai3.outcome_status, 'abandoned'); assert.equal(ai3.active_minutes, 20);
assert.equal((await rows('select count(*)::int n from ai_outcome_failure_reasons where outcome_id=$1',[ai3.id]))[0].n, 0);

// 3b. Optional reason still becomes a confirmed AI failure reason.
const s3b = await finished({ ...notCompleted, active_minutes: 0, interruption_count: 0, failure_reason: 'interruption' });
const ai3b = await deliver(s3b.job);
assert.equal((await rows('select reason_code from ai_outcome_failure_reasons where outcome_id=$1',[ai3b.id]))[0].reason_code, 'interruption');
assert.equal(ai3b.active_minutes, 0); // reported zero stays distinct from unknown
assert.equal(ai3b.interruption_count, 0);

// 4. Not completed + blank: unknown duration (null), not a confirmed not_started.
const s4 = await finished(notCompleted);
assert.equal(s4.execution.outcome_status, 'abandoned'); assert.equal(s4.execution.active_minutes, null);
assert.equal((await deliver(s4.job)).active_minutes, null);

// Legacy timer: recorded start kept, finish unknown; the row is no longer active.
const legacyPlan = await task();
const legacy = (await rows(`insert into executions(task_id,user_id,actual_start_time) values($1,$2,clock_timestamp()::text) returning *`,[legacyPlan.id,owner]))[0];
await db.query(`update executions set task_status='success',outcome_status='completed',completion_ratio=1 where id=$1`,[legacy.id]);
const legacyRow = (await rows('select * from executions where id=$1',[legacy.id]))[0];
assert.equal(legacyRow.actual_start_time, legacy.actual_start_time); assert.equal(legacyRow.actual_end_time, null);
const legacyJob = (await rows('select * from execution_ai_sync_jobs where execution_id=$1',[legacy.id]))[0];
assert.equal(legacyJob.payload.learning_eligible, true);
const legacyAi = await deliver(legacyJob);
assert.notEqual(legacyAi.actual_start, null); assert.equal(legacyAi.actual_end, null);
const nextLegacy = await rows(`insert into executions(task_id,user_id,actual_start_time) values($1,$2,clock_timestamp()::text) returning id`,[legacyPlan.id,owner]);
assert.equal(nextLegacy.length, 1); // finished start-only rows do not block the one-active-timer index

// Existing protections are unchanged.
await assert.rejects(finished({ ...completed, actual_end_time: new Date(Date.now() + 3_600_000).toISOString() }));
await assert.rejects(finished({ ...completed, actual_start_time: new Date().toISOString(), actual_end_time: new Date(Date.now() - 3_600_000).toISOString() }));
await assert.rejects(finished({ ...notCompleted, actual_start_time: new Date(Date.now() - 600_000).toISOString(), actual_end_time: new Date().toISOString(), active_minutes: 30 }));
await assert.rejects(finished({ task_status: 'failed', outcome_status: 'not_started', completion_ratio: 0, actual_end_time: new Date().toISOString() }));
await assert.rejects(finished({ ...completed, completion_ratio: 0 }));
const full = await finished({ ...completed, actual_start_time: new Date(Date.now() - 3_600_000).toISOString(), actual_end_time: new Date().toISOString() });
assert.notEqual(full.job.payload.actual_end, null); // complete ranges still reach AI unchanged
const notStarted = await finished({ task_status: 'failed', outcome_status: 'not_started', completion_ratio: 0 });
assert.equal(notStarted.execution.outcome_status, 'not_started');

// Security surface is unchanged: same definer/search_path/ACL, triggers attached, queue hidden.
const securitySql = `select p.proname, p.prosecdef, p.proconfig, coalesce(p.proacl::text,'') acl
 from pg_proc p where p.proname in ('prepare_execution_ai_sync','enqueue_execution_ai_sync') order by 1`;
const triggerSql = `select tgname, tgenabled from pg_trigger where tgrelid='public.executions'::regclass and not tgisinternal order by 1`;
const reference = await database({ optionalTimes: false });
assert.deepEqual(await rows(securitySql), (await reference.query(securitySql)).rows);
assert.deepEqual(await rows(triggerSql), (await reference.query(triggerSql)).rows);
await reference.close();
await db.exec(`grant usage on schema public to authenticated; grant select on executions to authenticated; set role authenticated;`);
await assert.rejects(db.query('select * from execution_ai_sync_jobs'));
await db.exec('reset role;');

// Rollback: the original functions reject new missing-time rows but keep existing rows readable.
await db.exec(await file('execution_outcome_sync_schema.sql'));
await assert.rejects(finished(completed));
assert.equal((await rows('select count(*)::int n from executions where outcome_status is not null and actual_end_time is null'))[0].n >= 4, true);
await db.close();

// Without this migration the deployed trigger rejects time-less completion (why it is required).
const before = await database({ optionalTimes: false });
const plan = (await before.query(`insert into tasks(user_id,title,task_category,planned_date,planned_start_time,planned_duration_min,importance,energy_level,focus_level)
 values ($1,'Study','Study',current_date + 1,'7:15 PM',45,3,3,3) returning id`,[owner])).rows[0];
await assert.rejects(before.query(`insert into executions(task_id,user_id,task_status,outcome_status,completion_ratio) values($1,$2,'success','completed',1)`,[plan.id,owner]), /Invalid actual execution times/);
await before.close();

// AI project migration: existing values survive, NULL needs it, rollback is blocked by NULLs.
const ai = await database({ optionalTimes: false });
await ai.exec(await file('execution_optional_times.sql'));
const aiPlan = (await ai.query(`insert into tasks(user_id,title,task_category,planned_date,planned_start_time,planned_duration_min,importance,energy_level,focus_level)
 values ($1,'Study','Study',current_date + 1,'7:15 PM',45,3,3,3) returning id`,[owner])).rows[0];
for (const job of (await ai.query(`select * from task_ai_sync_jobs where status='pending'`)).rows) {
 const keys = Object.keys(job.payload);
 await ai.query(`insert into ai_plan_inputs(${keys.join(',')}) values(${keys.map((_,i)=>'$'+(i+1)).join(',')})`, keys.map((k) => job.payload[k]));
}
async function aiDeliver(interruptions) {
 const plan = (await ai.query(`insert into tasks(user_id,title,task_category,planned_date,planned_start_time,planned_duration_min,importance,energy_level,focus_level)
  values ($1,'Study','Study',current_date + 1,'7:15 PM',45,3,3,3) returning *`,[owner])).rows[0];
 for (const job of (await ai.query(`select * from task_ai_sync_jobs where status='pending'`)).rows) {
  const keys = Object.keys(job.payload);
  await ai.query(`insert into ai_plan_inputs(${keys.join(',')}) values(${keys.map((_,i)=>'$'+(i+1)).join(',')}) on conflict do nothing`, keys.map((k) => job.payload[k]));
  await ai.query(`update task_ai_sync_jobs set status='synced' where id=$1`,[job.id]);
 }
 const execution = (await ai.query(`insert into executions(task_id,user_id,task_status,outcome_status,completion_ratio,interruption_count,stopped_early)
  values($1,$2,'success','completed',1,$3,false) returning id`,[plan.id, owner, interruptions])).rows[0];
 const job = (await ai.query('select * from execution_ai_sync_jobs where execution_id=$1',[execution.id])).rows[0];
 await ai.query('select deliver_execution_outcome($1,$2,$3,$4,$5::jsonb,$6)',
  [owner, job.plan_input_id, job.execution_id, job.sequence, JSON.stringify(job.payload), null]);
 return (await ai.query('select interruption_count from ai_plan_outcomes where plan_input_id=$1',[job.plan_input_id])).rows[0];
}
assert.equal((await aiDeliver(3)).interruption_count, 3);
await assert.rejects(aiDeliver(null), /null value.*interruption_count/); // without the AI migration a null count cannot be delivered
await ai.exec(await file('ai_outcome_nullable_interruptions.sql'));
await ai.exec(await file('ai_outcome_nullable_interruptions.sql'));
assert.deepEqual((await ai.query('select interruption_count from ai_plan_outcomes order by recorded_at')).rows.map((r) => r.interruption_count), [3]);
assert.equal((await aiDeliver(null)).interruption_count, null);
await assert.rejects(ai.exec('alter table public.ai_plan_outcomes alter column interruption_count set not null'));
await ai.close();
console.log('PASS: optional actual times and nullable interruptions for 4 outcome scenarios, legacy timers, AI delivery, unchanged protections, repeatable apply, rollback');

// node supabase/tests/execution_outcome_sync.test.mjs /path/to/pglite/dist/index.js
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
const { PGlite } = await import(pathToFileURL(process.argv[2]).href);
const db = new PGlite();
const owner = '11111111-1111-4111-8111-111111111111';
const other = '99999999-9999-4999-8999-999999999999';
async function rows(sql, args = []) { return (await db.query(sql, args)).rows; }
async function file(name) { return readFile(new URL('../' + name, import.meta.url), 'utf8'); }
await db.exec(`
 create schema auth; create role anon; create role authenticated; create role service_role bypassrls;
 create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql as $$ select '${owner}'::uuid $$;
 create function auth.role() returns text language sql as $$ select coalesce(nullif(current_setting('request.jwt.claim.role',true),''),'service_role') $$;
 insert into auth.users values ('${owner}');
`);
const primary = await file('schema.sql');
await db.exec(primary.slice(primary.indexOf('CREATE TABLE IF NOT EXISTS tasks'), primary.indexOf('-- ── Predictions')));
await db.exec(await file('task_ai_sync_schema.sql'));
await db.exec(await file('execution_outcome_sync_schema.sql'));
await db.exec(await file('execution_outcome_sync_schema.sql'));
await db.exec(await file('ai_schema.sql'));
await db.exec(await file('ai_outcome_delivery_schema.sql'));
await db.exec(await file('ai_outcome_delivery_schema.sql'));
async function task() {
 return (await rows(`insert into tasks(user_id,title,task_category,planned_date,planned_start_time,planned_duration_min,importance,energy_level,focus_level)
 values ($1,'Study','Study',current_date + 1,'9:00 AM',60,3,3,3) returning *`,[owner]))[0];
}
async function deliverPlans() {
 for(const job of await rows(`select * from task_ai_sync_jobs where status='pending' order by sequence`)) {
  const keys=Object.keys(job.payload);
  await db.query(`insert into ai_plan_inputs(${keys.join(',')}) values(${keys.map((_,i)=>'$'+(i+1)).join(',')})`,keys.map(k=>job.payload[k]));
  await db.query(`update task_ai_sync_jobs set status='synced' where id=$1`,[job.id]);
 }
}
async function deliver(job, reason = job.primary_reason_code, user = owner) {
 return rows('select deliver_execution_outcome($1,$2,$3,$4,$5::jsonb,$6) id',
  [user,job.plan_input_id,job.execution_id,job.sequence,JSON.stringify(job.payload),reason]);
}
const plan = await task();
const execution = (await rows(`insert into executions(task_id,user_id,actual_start_time) values($1,$2,clock_timestamp()::text) returning *`,[plan.id,owner]))[0];
assert.equal((await rows('select count(*)::int n from execution_ai_sync_jobs'))[0].n,0);
assert.equal((await rows('select task_status from tasks where id=$1',[plan.id]))[0].task_status,'pending');
// A plan edit during execution must not move this result to the new snapshot.
await db.query(`update tasks set planned_duration_min=75 where id=$1`,[plan.id]);
await db.query(`update executions set actual_end_time=(actual_start_time::timestamptz + interval '90 seconds')::text,
 task_status='failed',outcome_status='partial',completion_ratio=.35,interruption_count=3,stopped_early=true,failure_reason='interruption' where id=$1`,[execution.id]);
let jobs=await rows('select * from execution_ai_sync_jobs order by sequence');
assert.equal(jobs.length,1);
assert.equal(jobs[0].plan_input_id,plan.ai_plan_input_id);
assert.equal(jobs[0].payload.completion_ratio,.35);
assert.equal(jobs[0].payload.interruption_count,3);
assert.equal(jobs[0].payload.active_minutes,null); // elapsed is not invented focus time
assert.equal(jobs[0].payload.learning_eligible,true);
assert.equal((await rows('select task_status from tasks where id=$1',[plan.id]))[0].task_status,'failed');
await deliverPlans();
await deliver(jobs[0]); await deliver(jobs[0]);
assert.equal((await rows('select count(*)::int n from ai_plan_outcomes'))[0].n,1);
assert.equal((await rows('select reason_code from ai_outcome_failure_reasons'))[0].reason_code,'interruption');
// Failure reason errors roll back outcome, reasons, and version marker together.
await db.query(`update executions set completion_ratio=.60,failure_reason='underestimated_time' where id=$1`,[execution.id]);
jobs=await rows('select * from execution_ai_sync_jobs order by sequence');
await assert.rejects(deliver(jobs[1],'invalid_reason'));
assert.equal(Number((await rows('select completion_ratio from ai_plan_outcomes'))[0].completion_ratio),.35);
assert.equal((await rows('select source_revision from ai_execution_delivery_versions'))[0].source_revision,jobs[0].sequence);
await assert.rejects(deliver(jobs[1],jobs[1].primary_reason_code,other));
await deliver(jobs[1]);
await deliver(jobs[0]); // delayed old request cannot overwrite a correction
assert.equal(Number((await rows('select completion_ratio from ai_plan_outcomes'))[0].completion_ratio),.60);
// A successful correction removes old failure reasons in the same transaction.
await db.query(`update executions set task_status='success',outcome_status='completed',completion_ratio=1,failure_reason=null where id=$1`,[execution.id]);
jobs=await rows('select * from execution_ai_sync_jobs order by sequence');
await deliver(jobs[2]);
assert.equal((await rows('select count(*)::int n from ai_outcome_failure_reasons'))[0].n,0);
// Retrospective correction withdraws a label; old retries cannot resurrect it.
await db.query(`update executions set actual_start_time=(clock_timestamp()-interval '1 day')::text where id=$1`,[execution.id]);
jobs=await rows('select * from execution_ai_sync_jobs order by sequence');
assert.equal(jobs[3].payload.learning_eligible,false);
await deliver(jobs[3]); await deliver(jobs[2]);
assert.equal((await rows('select count(*)::int n from ai_plan_outcomes'))[0].n,0);
// Fixing the incorrect timestamp can restore the latest valid outcome.
await db.query(`update executions set actual_start_time=$2 where id=$1`,[execution.id,execution.actual_start_time]);
jobs=await rows('select * from execution_ai_sync_jobs order by sequence');
await deliver(jobs[4]);
assert.equal((await rows('select outcome_status from ai_plan_outcomes'))[0].outcome_status,'completed');
// Older clients cannot silently leave a stale label after an unknown correction.
await db.query(`update executions set task_status='failed',outcome_status=null,completion_ratio=null,failure_reason='other' where id=$1`,[execution.id]);
jobs=await rows('select * from execution_ai_sync_jobs order by sequence');
assert.equal(jobs[5].payload.learning_eligible,false);
await deliver(jobs[5]);
assert.equal((await rows('select count(*)::int n from ai_plan_outcomes'))[0].n,0);
const noStartPlan = await task();
const noStart = (await rows(`insert into executions(task_id,user_id,task_status,outcome_status,completion_ratio,interruption_count,stopped_early,idempotency_key)
 values($1,$2,'failed','not_started',0,0,false,$1) returning *`,[noStartPlan.id,owner]))[0];
assert.equal(noStart.actual_start_time,null); assert.equal(noStart.actual_end_time,null);
await assert.rejects(db.query(`insert into executions(task_id,user_id,task_status,idempotency_key) values($1,$2,'failed',$1)`,[noStartPlan.id,owner]));
await deliverPlans();
const noStartJob = (await rows('select * from execution_ai_sync_jobs where execution_id=$1',[noStart.id]))[0];
await deliver(noStartJob);
assert.equal((await rows('select actual_start from ai_plan_outcomes where plan_input_id=$1',[noStartPlan.ai_plan_input_id]))[0].actual_start,null);
// Invalid progress and foreign ownership never commit partial primary writes.
await assert.rejects(db.query(`update executions set completion_ratio=.5 where id=$1`,[noStart.id]));
assert.equal((await rows('select completion_ratio from executions where id=$1',[noStart.id]))[0].completion_ratio,'0.00000');
await assert.rejects(db.query(`insert into executions(task_id,user_id) values($1,$2)`,[plan.id,other]));
await db.exec(`grant usage on schema public,auth to authenticated;
 grant select,update on executions to authenticated;
 set request.jwt.claim.role='authenticated';set role authenticated;`);
await assert.rejects(db.query('select * from execution_ai_sync_jobs'));
await assert.rejects(deliver(noStartJob));
await db.query(`update executions set ai_outcome_sync_status='synced',ai_plan_input_id=gen_random_uuid() where id=$1`,[noStart.id]);
assert.equal((await rows('select ai_outcome_sync_status from executions where id=$1',[noStart.id]))[0].ai_outcome_sync_status,'pending');
await db.exec('reset role;reset request.jwt.claim.role;');
await db.close();
console.log('PASS: atomic outcome/reasons, original plan linkage, progress, not-started, idempotency, ownership, RLS, corrections, withdrawal, stale retries');

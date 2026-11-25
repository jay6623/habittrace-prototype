// Isolated PostgreSQL: node supabase/tests/planning_intelligence.test.mjs /path/to/pglite/dist/index.js
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const one='11111111-1111-4111-8111-111111111111',two='22222222-2222-4222-8222-222222222222';
const group='33333333-3333-4333-8333-333333333333',otherGroup='33333333-3333-4333-8333-333333333334';
const a='44444444-4444-4444-8444-444444444444',b='44444444-4444-4444-8444-444444444445',foreign='44444444-4444-4444-8444-444444444446';
await db.exec(`create schema auth;create role authenticated;create role anon;create role service_role bypassrls;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql as $$select current_setting('request.jwt.claim.sub',true)::uuid$$;
create function auth.role() returns text language sql as $$select 'service_role'$$;
insert into auth.users values('${one}'),('${two}');`);
const primary=await readFile(new URL('../schema.sql',import.meta.url),'utf8');
await db.exec(primary.slice(primary.indexOf('CREATE TABLE IF NOT EXISTS tasks'),primary.indexOf('-- ── Executions')));
await db.exec(`create table executions(id uuid primary key default gen_random_uuid(),task_id uuid references tasks(id),user_id uuid,
 task_status text, created_at timestamptz default clock_timestamp());`);
for(const file of ['task_ai_sync_schema.sql','group_scheduling_schema.sql','group_task_completion_schema.sql','group_personal_planning_schema.sql','group_planning_extensions.sql','planning_intelligence_schema.sql']) {
 await db.exec(await readFile(new URL('../'+file,import.meta.url),'utf8'));
}
await db.exec(await readFile(new URL('../planning_intelligence_schema.sql',import.meta.url),'utf8'));
await db.exec(`insert into groups(id,owner_id,name,invite_code) values('${group}','${one}','Team','ABCD2345'),('${otherGroup}','${two}','Other','WXYZ6789');
insert into group_members(group_id,user_id) values('${group}','${one}'),('${group}','${two}');
insert into group_tasks(id,group_id,created_by,title,estimated_duration_minutes,due_date,due_timezone_name) values
('${a}','${group}','${one}','Research',60,'2099-09-09','UTC'),('${b}','${group}','${one}','Draft',60,'2099-09-09','UTC'),('${foreign}','${otherGroup}','${two}','Foreign',60,'2099-09-09','UTC');
insert into group_task_assignees(group_id,task_id,user_id) values('${group}','${a}','${one}');
insert into group_task_dependencies values('${group}','${b}','${a}');`);
await assert.rejects(db.exec(`insert into group_task_dependencies values('${group}','${a}','${b}')`),/cycle/);
await assert.rejects(db.exec(`insert into group_task_dependencies values('${group}','${a}','${foreign}')`),/same group/);
await assert.rejects(db.exec(`insert into group_project_milestones(group_id,title,due_date,completion_criteria,task_ids)
 values('${group}','Draft','2099-09-10','Ready for review',array['${foreign}']::uuid[])`),/same group/);
const src=(await db.query(`insert into tasks(user_id,title,task_category,planned_date,planned_start_time,planned_duration_min,importance,energy_level,focus_level,
source_group_task_id) values($1,'Research','Study','2099-09-06','10:00',60,3,3,3,$2) returning *`,[one,a])).rows[0];
async function compare(source,options,latest=null) {
 const snapshot={...source};delete snapshot.ai_sync_status;
 return (await db.query(`insert into planning_comparisons(user_id,source_task_id,source_snapshot,options,evidence,latest_execution_id)
 values($1,$2,$3,$4,'{"expected_energy":3,"expected_focus":3}',$5) returning id`,[one,source.id,snapshot,options,latest])).rows[0].id;
}
function option(id='split',date='2099-09-06',start='10:00:00Z',length=30) {
 return [{id,available:true,blocks:[{planned_start:`${date}T${start}`,local_date:date,local_time:start.slice(0,5),duration_minutes:length,success_probability:.7,feature_snapshot:{deadline_at:"2099-09-09T23:59:59+00:00"}},
 {planned_start:`${date}T11:00:00Z`,local_date:date,local_time:'11:00',duration_minutes:length,success_probability:.8,feature_snapshot:{deadline_at:"2099-09-09T23:59:59+00:00"}}]}];
}
const c=await compare(src,option());
const applied=(await db.query(`select apply_planning_option($1,$2,'split') result`,[one,c])).rows[0].result;
assert.equal(applied.length,2);assert.equal(applied[0].id,src.id);
assert.equal(applied[0].planned_duration_min+applied[1].planned_duration_min,60);
assert.equal(applied[1].continuation_of_task_id,src.id);
assert.equal(applied[0].ai_plan_details.deadline_at,"2099-09-09T23:59:59+00:00");assert.equal(applied[1].source_group_task_id,a);
assert.notEqual(applied[0].group_block_key,applied[1].group_block_key);
const count=(await db.query('select count(*)::int n from tasks')).rows[0].n;
assert.deepEqual((await db.query(`select apply_planning_option($1,$2,'split') result`,[one,c])).rows[0].result,applied);
assert.equal((await db.query('select count(*)::int n from tasks')).rows[0].n,count);
await assert.rejects(db.query(`select apply_planning_option($1,$2,'buffer')`,[one,c]),/different option/);
await assert.rejects(db.query(`select apply_planning_option($1,$2,'split')`,[two,c]),/not found/);
// A stale source cannot be applied; selection must remain uncommitted.
let source=(await db.query('select * from tasks where id=$1',[src.id])).rows[0];
const stale=await compare(source,option('current','2099-09-07'));
await db.query(`update tasks set planned_start_time='12:00' where id=$1`,[src.id]);
await assert.rejects(db.query(`select apply_planning_option($1,$2,'current')`,[one,stale]),/changed/);
// A conflict in the second block rolls back the first block too.
source=(await db.query('select * from tasks where id=$1',[src.id])).rows[0];
const conflict=await compare(source,option('split','2099-09-06','09:00:00Z'));
await assert.rejects(db.query(`select apply_planning_option($1,$2,'split')`,[one,conflict]),/Schedule changed/);
assert.equal((await db.query('select planned_start_time from tasks where id=$1',[src.id])).rows[0].planned_start_time,'12:00');
assert.equal((await db.query('select selected_at from planning_comparisons where id=$1',[conflict])).rows[0].selected_at,null);
// Partial results remain on the old task; the remaining attempt gets a new row.
await db.query(`update tasks set task_status='failed' where id=$1`,[src.id]);
const execution=(await db.query(`insert into executions(task_id,user_id,task_status) values($1,$2,'failed') returning id`,[src.id,one])).rows[0].id;
source=(await db.query('select * from tasks where id=$1',[src.id])).rows[0];
const continuation=await compare(source,option('current','2099-09-08'),execution);
const next=(await db.query(`select apply_planning_option($1,$2,'current') result`,[one,continuation])).rows[0].result;
assert.notEqual(next[0].id,src.id);
assert.equal((await db.query('select task_status from tasks where id=$1',[src.id])).rows[0].task_status,'failed');
assert.equal((await db.query('select count(*)::int n from executions')).rows[0].n,1);
// Expired comparisons and a newly shortened shared deadline require a fresh review.
source=(await db.query('select * from tasks where id=$1',[src.id])).rows[0];
const expired=await compare(source,option('current','2099-09-08'),execution);
await db.query("update planning_comparisons set shown_at=clock_timestamp()-interval '1 hour' where id=$1",[expired]);
await assert.rejects(db.query(`select apply_planning_option($1,$2,'current')`,[one,expired]),/expired/);
const deadlineChanged=await compare(source,option('current','2099-09-08'),execution);
await db.query("update group_tasks set due_date='2099-09-05' where id=$1",[a]);
await assert.rejects(db.query(`select apply_planning_option($1,$2,'current')`,[one,deadlineChanged]),/deadline changed/);
// Browser roles cannot forge evidence, private comparisons or group forecasts.
await db.exec(`grant usage on schema public,auth to authenticated;set role authenticated;`);
await assert.rejects(db.query('select * from planning_comparisons'),/permission denied/);
await assert.rejects(db.query(`select apply_planning_option($1,$2,'split')`,[one,c]),/permission denied/);
await assert.rejects(db.query('select * from group_task_dependencies'),/permission denied/);
await db.exec('reset role;');
await db.close();
console.log('PASS: migration replay, group boundaries/cycles, private evidence, atomic split/continuation, stale conflicts, retry safety');

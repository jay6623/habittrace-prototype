-- PRIMARY project, after execution_outcome_sync_schema.sql. Repeatable.
-- Makes actual execution times optional for finished outcomes so a plan can be
-- completed without a timer and without inventing timestamps:
--   * both null      -> time unknown (Completed: UI shows the scheduled end as a fallback)
--   * end only       -> user-reported finish time, no observed start
--   * start only     -> legacy timer start whose finish was not reported
--   * both present   -> timer measurement or manually entered range (unchanged checks)
-- Not-started rules, outcome/ratio consistency, AI linkage and RLS are unchanged.
-- No table, column, index or data changes. Rollback: re-run the two function
-- definitions in execution_outcome_sync_schema.sql (rows with missing times then
-- reject further edits until times are supplied; existing rows stay readable).
begin;
create or replace function public.prepare_execution_ai_sync()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  plan_created_at timestamptz;
  planned_start timestamptz;
begin
  if not exists (select 1 from public.tasks t where t.id = new.task_id and t.user_id = new.user_id) then
    raise exception 'Execution task not found' using errcode = '23514';
  end if;
  if tg_op = 'INSERT' then
    select t.ai_plan_input_id into new.ai_plan_input_id from public.tasks t where t.id = new.task_id;
  else
    -- Corrections stay attached to the plan known when execution began, even
    -- if the task was subsequently edited on another device.
    new.ai_plan_input_id := old.ai_plan_input_id;
    if row(new.actual_start_time, new.actual_end_time, new.interruption_count,
           new.stopped_early, new.task_status, new.failure_reason, new.outcome_status,
           new.completion_ratio, new.active_minutes) is not distinct from
       row(old.actual_start_time, old.actual_end_time, old.interruption_count,
           old.stopped_early, old.task_status, old.failure_reason, old.outcome_status,
           old.completion_ratio, old.active_minutes) then
      new.ai_outcome_job_id := old.ai_outcome_job_id;
      new.ai_learning_eligible := old.ai_learning_eligible;
      if coalesce(auth.role(), '') <> 'service_role' then
        new.ai_outcome_sync_status := old.ai_outcome_sync_status;
      end if;
      return new;
    end if;
  end if;
  new.ai_outcome_job_id := null;
  new.ai_learning_eligible := false;
  new.ai_outcome_sync_status := 'unlinked';
  if new.task_status is null then
    if new.outcome_status is not null or new.completion_ratio is not null then
      raise exception 'An unfinished execution cannot have an outcome' using errcode = '23514';
    end if;
    return new;
  end if;
  if new.outcome_status is null then
    -- Old failed records have unknown progress, not an invented zero or 50%.
    -- A correction from a newer client must also withdraw any prior AI label.
    if new.ai_plan_input_id is not null then
      new.ai_outcome_job_id := gen_random_uuid();
      new.ai_outcome_sync_status := 'pending';
    end if;
    return new;
  end if;
  if new.completion_ratio is null
     or (new.outcome_status = 'completed' and (new.task_status <> 'success' or new.completion_ratio <> 1))
     or (new.outcome_status <> 'completed' and new.task_status <> 'failed')
     or (new.outcome_status = 'partial' and not (new.completion_ratio > 0 and new.completion_ratio < 1))
     or (new.outcome_status in ('not_started', 'abandoned') and new.completion_ratio <> 0) then
    raise exception 'Inconsistent outcome and completion ratio' using errcode = '23514';
  end if;
  if new.outcome_status = 'not_started' then
    if new.actual_start_time is not null or new.actual_end_time is not null
       or coalesce(new.active_minutes, 0) <> 0 or new.interruption_count <> 0 or new.stopped_early then
      raise exception 'Not-started outcomes cannot contain execution activity' using errcode = '23514';
    end if;
  else
    -- Actual times are optional: null means unknown, never an invented value. A
    -- start without an end is a legacy timer whose finish was not reported; an
    -- end without a start is a user-reported finish time.
    if (new.actual_end_time is not null
        and new.actual_end_time::timestamptz > clock_timestamp() + interval '5 minutes')
       or (new.actual_start_time is not null and new.actual_end_time is not null and (
         new.actual_end_time::timestamptz < new.actual_start_time::timestamptz
         or new.active_minutes > floor(extract(epoch from
           (new.actual_end_time::timestamptz - new.actual_start_time::timestamptz)) / 60))) then
      raise exception 'Invalid actual execution times' using errcode = '23514';
    end if;
  end if;
  if new.ai_plan_input_id is null then return new; end if;
  select j.created_at, (j.payload->>'planned_start')::timestamptz
    into plan_created_at, planned_start
    from public.task_ai_sync_jobs j where j.id = new.ai_plan_input_id and j.user_id = new.user_id;
  if plan_created_at is null or plan_created_at > coalesce(new.actual_start_time::timestamptz, planned_start) then
    -- Retrospective records remain in the product but do not become training
    -- labels for inputs captured after the execution had already started.
    new.ai_learning_eligible := false;
  else
    new.ai_learning_eligible := true;
  end if;
  new.ai_outcome_job_id := gen_random_uuid();
  new.ai_outcome_sync_status := 'pending';
  return new;
end;
$$;

create or replace function public.enqueue_execution_ai_sync()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.task_status is not null then
    -- Task status, outcome facts, and delivery intent commit together.
    update public.tasks set task_status = new.task_status where id = new.task_id and user_id = new.user_id;
  end if;
  if new.ai_outcome_job_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.ai_outcome_job_id is not distinct from old.ai_outcome_job_id then
    return new;
  end if;
  insert into public.execution_ai_sync_jobs(id, execution_id, task_id, user_id, plan_input_id, payload, primary_reason_code)
  values (new.ai_outcome_job_id, new.id, new.task_id, new.user_id, new.ai_plan_input_id,
    jsonb_build_object(
      'outcome_status', new.outcome_status, 'completion_ratio', new.completion_ratio,
      'actual_start', new.actual_start_time,
      -- The AI project requires actual_start for actual_end; an end-only report stays primary-only.
      'actual_end', case when new.actual_start_time is null then null else new.actual_end_time end,
      'active_minutes', new.active_minutes, 'interruption_count', new.interruption_count,
      'stopped_early', new.stopped_early, 'recorded_at', clock_timestamp()
      , 'learning_eligible', new.ai_learning_eligible
    ), case when new.task_status = 'success' then null else new.failure_reason end);
  return new;
end;
$$;
commit;

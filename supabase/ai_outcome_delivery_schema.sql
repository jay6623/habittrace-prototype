-- AI project, after ai_schema.sql. Backend-only atomic, versioned delivery.
begin;
alter table public.ai_plan_outcomes
  add column if not exists source_execution_id uuid,
  add column if not exists source_revision bigint;

create table if not exists public.ai_execution_delivery_versions (
  plan_input_id uuid primary key references public.ai_plan_inputs(id) on delete cascade,
  source_execution_id uuid not null,
  source_revision bigint not null
);
alter table public.ai_execution_delivery_versions enable row level security;
revoke all on public.ai_execution_delivery_versions from anon, authenticated;

create or replace function public.deliver_execution_outcome(
  p_user_id uuid, p_plan_input_id uuid, p_execution_id uuid, p_revision bigint,
  p_outcome jsonb, p_primary_reason text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  existing public.ai_plan_outcomes%rowtype;
  outcome_id uuid;
  delivered public.ai_execution_delivery_versions%rowtype;
begin
  -- Serialize all deliveries for this plan, including first insert races.
  perform 1 from public.ai_plan_inputs where id = p_plan_input_id and user_id = p_user_id for update;
  if not found then raise exception 'Plan not found' using errcode = '23514'; end if;
  select * into delivered from public.ai_execution_delivery_versions where plan_input_id = p_plan_input_id;
  if found then
    if delivered.source_execution_id <> p_execution_id then
      raise exception 'Plan already has another execution' using errcode = '23514';
    end if;
    if delivered.source_revision >= p_revision then
      return (select id from public.ai_plan_outcomes where plan_input_id = p_plan_input_id);
    end if;
  end if;
  select * into existing from public.ai_plan_outcomes where plan_input_id = p_plan_input_id;
  if found then
    if existing.source_execution_id is not null and existing.source_execution_id <> p_execution_id then
      raise exception 'Plan already has another execution' using errcode = '23514';
    end if;
    if existing.source_revision >= p_revision then return existing.id; end if;
    outcome_id := existing.id;
  else
    outcome_id := gen_random_uuid();
  end if;
  insert into public.ai_execution_delivery_versions(plan_input_id, source_execution_id, source_revision)
  values (p_plan_input_id, p_execution_id, p_revision)
  on conflict (plan_input_id) do update set source_revision = excluded.source_revision;
  if not coalesce((p_outcome->>'learning_eligible')::boolean, true) then
    -- A correction can withdraw an earlier label. Retain the delivery version
    -- so a delayed older request cannot resurrect that withdrawn outcome.
    delete from public.ai_plan_outcomes where plan_input_id = p_plan_input_id;
    return null;
  end if;
  if p_primary_reason is not null and not exists (
    select 1 from public.ai_failure_reason_definitions where code = p_primary_reason and is_active
  ) then raise exception 'Unsupported failure reason' using errcode = '23514'; end if;
  if p_outcome->>'outcome_status' = 'completed' and p_primary_reason is not null then
    raise exception 'Successful outcomes cannot have failure reasons' using errcode = '23514';
  end if;
  delete from public.ai_outcome_failure_reasons r where r.outcome_id = existing.id;
  insert into public.ai_plan_outcomes(
    id, plan_input_id, outcome_status, actual_start, actual_end, active_minutes,
    completion_ratio, interruption_count, stopped_early, recorded_at,
    source_execution_id, source_revision
  ) values (
    outcome_id, p_plan_input_id, p_outcome->>'outcome_status',
    (p_outcome->>'actual_start')::timestamptz, (p_outcome->>'actual_end')::timestamptz,
    (p_outcome->>'active_minutes')::integer, (p_outcome->>'completion_ratio')::numeric,
    (p_outcome->>'interruption_count')::integer, (p_outcome->>'stopped_early')::boolean,
    (p_outcome->>'recorded_at')::timestamptz, p_execution_id, p_revision
  ) on conflict (plan_input_id) do update set
    outcome_status = excluded.outcome_status, actual_start = excluded.actual_start,
    actual_end = excluded.actual_end, active_minutes = excluded.active_minutes,
    completion_ratio = excluded.completion_ratio, interruption_count = excluded.interruption_count,
    stopped_early = excluded.stopped_early, recorded_at = excluded.recorded_at,
    source_execution_id = excluded.source_execution_id, source_revision = excluded.source_revision;
  if p_primary_reason is not null then
    insert into public.ai_outcome_failure_reasons(outcome_id, reason_code, is_primary, user_confirmed, created_at)
    values (outcome_id, p_primary_reason, true, true, (p_outcome->>'recorded_at')::timestamptz);
  end if;
  return outcome_id;
end;
$$;
revoke all on function public.deliver_execution_outcome(uuid, uuid, uuid, bigint, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.deliver_execution_outcome(uuid, uuid, uuid, bigint, jsonb, text)
  to service_role;
commit;

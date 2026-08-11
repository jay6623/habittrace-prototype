-- Read-only checks to run after ai_schema.sql in the AI Supabase project.

-- All nine tables must exist and have RLS enabled.
with expected(table_name) as (
  values
    ('ai_plan_inputs'),
    ('ai_plan_outcomes'),
    ('ai_failure_reason_definitions'),
    ('ai_outcome_failure_reasons'),
    ('ai_model_versions'),
    ('ai_success_predictions'),
    ('ai_failure_predictions'),
    ('ai_time_recommendations'),
    ('ai_time_candidates')
)
select
  e.table_name,
  c.oid is not null and c.relkind in ('r', 'p') as table_exists,
  coalesce(c.relrowsecurity, false) as rls_enabled
from expected e
left join pg_namespace n on n.nspname = 'public'
left join pg_class c on c.relnamespace = n.oid and c.relname = e.table_name
order by e.table_name;

-- Expected result: zero browser policies. FastAPI service_role bypasses RLS.
select schemaname, tablename, policyname, roles, cmd
from pg_policies
where schemaname = 'public' and tablename like 'ai\_%' escape '\'
order by tablename, policyname;

-- Verify the current failure-reason truth vocabulary.
select code, display_name, is_active
from public.ai_failure_reason_definitions
order by code;

select
  count(*) filter (where is_active) = 8
  and count(*) filter (
    where is_active and code not in (
      'low_readiness',
      'schedule_overload',
      'underestimated_time',
      'interruption',
      'unexpected_event',
      'unclear_plan',
      'task_too_difficult',
      'other'
    )
  ) = 0 as active_failure_vocabulary_is_current
from public.ai_failure_reason_definitions;

-- Critical integrity constraints and triggers should all appear here.
select
  conrelid::regclass as table_name,
  conname,
  contype,
  convalidated,
  condeferrable,
  condeferred
from pg_constraint
where conname in (
  'ai_plan_inputs_parent_plan_input_id_fkey',
  'ai_plan_inputs_source_parent_check',
  'ai_plan_outcomes_not_started_consistency',
  'ai_outcome_failure_reasons_user_confirmed_check',
  'ai_time_recommendations_selected_candidate_fkey'
)
order by (conrelid::regclass)::text, conname;

select
  c.relname as table_name,
  t.tgname as trigger_name,
  t.tgenabled,
  t.tgdeferrable,
  t.tginitdeferred
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and not t.tgisinternal
  and t.tgname in (
    'trg_validate_ai_plan_revision_cycle',
    'trg_validate_ai_failure_reason_set',
    'trg_validate_ai_outcome_failure_truth'
  )
order by c.relname, t.tgname;

select tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and indexname in (
    'uq_ai_plan_inputs_single_child',
    'uq_ai_plan_inputs_id_user',
    'uq_ai_primary_failure_reason',
    'uq_ai_production_model_type',
    'uq_ai_time_candidates_id_recommendation',
    'idx_ai_success_predictions_model',
    'idx_ai_failure_predictions_model',
    'idx_ai_time_recommendations_model'
  )
order by tablename, indexname;

-- All anomaly counts must be zero.
with recursive revision_walk(start_id, id, parent_plan_input_id, path, has_cycle) as (
  select p.id, p.id, p.parent_plan_input_id, array[p.id], false
  from public.ai_plan_inputs p

  union all

  select
    w.start_id,
    p.id,
    p.parent_plan_input_id,
    w.path || p.id,
    p.id = any(w.path)
  from revision_walk w
  join public.ai_plan_inputs p on p.id = w.parent_plan_input_id
  where not w.has_cycle
)
select count(*) as revision_cycle_count
from revision_walk
where has_cycle;

select count(*) as invalid_primary_set_count
from (
  select r.outcome_id
  from public.ai_outcome_failure_reasons r
  group by r.outcome_id
  having count(*) filter (where r.is_primary) <> 1
) invalid_sets;

select count(*) as successful_outcome_reason_count
from public.ai_outcome_failure_reasons r
join public.ai_plan_outcomes o on o.id = r.outcome_id
where o.outcome_status = 'completed' and o.completion_ratio >= 0.80;

select count(*) as inactive_reason_assignment_count
from public.ai_outcome_failure_reasons r
join public.ai_failure_reason_definitions d on d.code = r.reason_code
where not d.is_active;

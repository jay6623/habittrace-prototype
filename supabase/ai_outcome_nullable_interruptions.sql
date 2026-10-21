-- AI project, after ai_schema.sql and ai_outcome_delivery_schema.sql. Repeatable.
-- Lets a delivered outcome keep an unreported interruption count as NULL
-- (unknown) instead of a fabricated 0. Existing rows and values are unchanged;
-- the >= 0 check and the not-started consistency check (which requires 0) still
-- apply. interruption_count is never a model feature (see habittrace_ai_v2
-- contracts.FORBIDDEN_FEATURE_COLUMNS).
-- Apply before the primary project can produce outcomes with a null count
-- (i.e. before deploying the backend/frontend that send null).
-- Rollback: only possible while no row is null; NULLs must not be rewritten as 0.
begin;
alter table public.ai_plan_outcomes alter column interruption_count drop not null;
commit;

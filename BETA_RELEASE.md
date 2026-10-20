# HabitTrace Beta release candidate

## Proposed release

- **Version:** `v0.2.0-beta`
- **Candidate commit:** `cb1c5f7` (`Update README.md`), the current `main` and
  `origin/main` tip when this document was prepared.
- **Tag status:** not created. Creating an annotated tag, committing this release
  preparation work, or pushing anything requires maintainer approval.

`0.2.0-beta` is appropriate because this is the first documented beta candidate
after the alpha material, while it introduces backward-sensitive schema work,
AI V2 delivery, planning/outcome flows, groups, Calendar integration, and the
AI Coach. It should not be presented as a stable `1.0` release.

## Changes since Alpha

- Added the Today-first responsive web/PWA workflow, task planning/editing,
  execution outcomes, analytics, personal export, and group capabilities.
- Added durable primary-to-AI V2 plan/outcome delivery with retries and
  correction handling, plus observed-duration recommendations.
- Added AI Coach guardrails, confirmation-gated planning actions, persisted
  conversations/preferences, daily schedules, and optional chart metadata.
- Added optional one-way Google Calendar synchronization and profile/avatar
  support.
- Added this credential-free GitHub Actions validation pipeline.

## Release checklist

- [ ] CI is green for the candidate commit on GitHub.
- [ ] Review all local verification results and resolve any failures below.
- [ ] Back up both Supabase projects and run the read-only SQL in the matrix.
- [ ] Apply only the required migrations, in dependency order, after approval.
- [ ] Deploy backend and frontend using their normal production configuration.
- [ ] Check production `/health` and `/docs` without exposing credentials.
- [ ] Run the documented signed-in acceptance checks with a dedicated test account.
- [ ] Confirm redirects, CORS, Supabase Auth, Google OAuth (if enabled), and
  secret storage in the deployment platform.
- [ ] Commit reviewed release-preparation changes, then create and push an
  annotated `v0.2.0-beta` tag only with approval.
- [ ] Publish release notes that label AI V2 artifacts as synthetic-only.

## Known limitations and release risks

- AI V2's included artifacts are trained and evaluated on synthetic data; they
  are not evidence of real-user predictive accuracy.
- Delivery retries are request-driven, not handled by a background worker.
- Browser sign-in, OAuth, and production database migrations have not been
  verified by this release-preparation change.
- The optional Google Calendar integration is one-way; imports and offline write
  synchronization are not implemented.
- The legacy V1 model artifact/runtime scikit-learn version warning needs a
  separate compatibility decision before broad production reliance.

## Migration matrix

Run read-only checks in the target project's SQL Editor or a read-only database
connection. Queries use catalog metadata and counts only; do not paste service
keys into logs. `to_regclass(...) is not null` means the relation exists.

| Migration | Target / prerequisite | Feature | Repeat safety | Read-only verification | If omitted / recovery |
|---|---|---|---|---|---|
| `schema.sql` | Primary; first | profiles, tasks, executions, predictions, RLS | **Partial**: tables/indexes are guarded, but policies are not dropped first | `select to_regclass('public.tasks'), to_regclass('public.executions'), to_regclass('public.predictions');` | Core app fails. Restore backup; for a new project rerun after correcting conflict. |
| `coach_agent_schema.sql` | Primary; `schema.sql` | coach conversations/messages/preferences/proposals | Generally repeatable (policies are replaced) | `select to_regclass('public.coach_messages'), to_regclass('public.agent_action_proposals');` | Coach persistence fails. Restore backup or drop only newly created empty tables after code rollback. |
| `task_notes.sql` | Primary; `schema.sql` | optional task notes | Idempotent | `select column_name from information_schema.columns where table_schema='public' and table_name='tasks' and column_name='notes';` | Notes are unavailable. `alter table public.tasks drop column notes;` only after backup and code rollback. |
| `task_ai_sync_schema.sql` | Primary; `schema.sql`, before task/AI-sync backend | immutable task snapshots and delivery jobs | Mostly repeatable; triggers/functions are replaced | `select to_regclass('public.task_ai_sync_jobs'), count(*) from public.task_ai_sync_jobs;` | Tasks may save but AI snapshots/delivery fail. Restore backup or remove triggers/jobs/columns only under a reviewed rollback script. |
| `execution_outcome_sync_schema.sql` | Primary; task AI sync after `schema.sql` | outcome fidelity and primary delivery jobs | **Caution**: it drops/recreates the active-execution index | `select to_regclass('public.execution_ai_sync_jobs'), count(*) from public.execution_ai_sync_jobs;` | Outcome sync/corrections fail. Restore backup; rollback must reinstate the prior index/trigger contract. |
| `google_calendar_schema.sql` | Primary; `schema.sql`; optional | encrypted Calendar connection/event links | **Partial**: tables/indexes guarded, policy creation is not | `select to_regclass('public.calendar_connections'), to_regclass('public.calendar_event_links');` | Calendar endpoints cannot persist links. Restore backup or drop empty tables after disabling integration. |
| `group_scheduling_schema.sql` | Primary; `schema.sql`; optional groups | groups, members, shared tasks, assignees | Partially repeatable; includes a data backfill | `select to_regclass('public.groups'), to_regclass('public.group_task_assignees');` | Group scheduling fails. Restore backup; rollback must preserve/copy shared-task data first. |
| `group_announcements_schema.sql` | Primary; group scheduling | announcements and replies | **Partial**: backfills/nullability changes | `select to_regclass('public.group_announcements'), to_regclass('public.group_announcement_replies');` | Announcement UI/API fails. Restore backup or roll back only after exporting affected records. |
| `group_task_completion_schema.sql` | Primary; group scheduling | per-assignee outcome/log time | Idempotent for columns; constraint block guarded | `select column_name from information_schema.columns where table_schema='public' and table_name='group_task_assignees' and column_name in ('outcome','logged_at');` | Group completion state fails. Restore backup or drop columns after code rollback. |
| `group_member_admin_role.sql` | Primary; group scheduling | group admin role constraint | Repeatable but changes a constraint | `select pg_get_constraintdef(oid) from pg_constraint where conrelid='public.group_members'::regclass and conname='group_members_role_check';` | Admin-role behavior is rejected. Reapply previous reviewed constraint or restore backup. |
| `profile_avatar.sql` / `avatars_storage.sql` | Primary; `schema.sql`; optional | avatar URL and Storage bucket policies | Column is idempotent; Storage policy script replaces policies | `select column_name from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='avatar_url';` | Avatar feature fails. Roll back policies/column only after backing up objects. |
| `profile_name_sync.sql` | Primary; `schema.sql`; optional update | signup display-name sync | Trigger/function replacement is repeatable | `select tgname from pg_trigger where tgname='on_auth_user_created';` | New profile names may not sync. Restore prior function/trigger from backup. |
| `ai_schema.sql` | AI Supabase; first | AI inputs/outcomes/reasons/models/predictions/recommendations/schedules | **Partial**: guarded tables but constraints/functions are rebuilt | `select to_regclass('public.ai_plan_inputs'), to_regclass('public.ai_plan_outcomes'), to_regclass('public.ai_model_versions');` then run `verify_ai_schema.sql` | AI V2 writes/reads fail. Restore AI-project backup; use a reviewed downgrade, never drop real AI records ad hoc. |
| `ai_outcome_delivery_schema.sql` | AI Supabase; `ai_schema.sql` | atomic outcome/reason delivery RPC and version locks | Mostly repeatable | `select to_regprocedure('public.deliver_execution_outcome(uuid,uuid,uuid,bigint,jsonb,text)'), to_regclass('public.ai_execution_delivery_versions');` | Primary jobs remain pending; outcomes are not delivered. Restore backup or remove RPC/version table only after backend rollback. |
| `coach_visualization_metadata.sql` | Primary; `coach_agent_schema.sql` | persisted Coach chart metadata | Idempotent | `select column_name from information_schema.columns where table_schema='public' and table_name='coach_messages' and column_name='metadata';` | Chart-bearing Coach responses cannot persist. Restore backup or drop column after disabling feature. |

`verify_ai_schema.sql` is deliberately read-only and should be run after the AI
schema migration; it is not a migration. `supabase/tests/*.test.mjs` are local
PGlite regression tests and are not a substitute for inspecting the target
Supabase projects.

## Required order by enabled feature

1. **Base app:** Primary `schema.sql`.
2. **AI V2 plan/outcome flow:** Primary `task_ai_sync_schema.sql` then
   `execution_outcome_sync_schema.sql`; AI `ai_schema.sql` then
   `ai_outcome_delivery_schema.sql`; run `verify_ai_schema.sql`.
3. **Coach charts:** Primary `coach_agent_schema.sql` then
   `coach_visualization_metadata.sql`.
4. Apply independent optional Primary migrations (`task_notes`, Calendar, groups,
   avatar, profile sync) only when their corresponding product surface is enabled;
   group add-ons follow `group_scheduling_schema.sql`.

# Automatic AI Coach charts

The coach automatically includes one interactive chart in an assistant reply when a selected
analysis tool returns enough recorded evidence. It reuses Chart.js/react-chartjs-2 already in
the frontend. No production dependencies or LLM requests were added.

## Data flow and selection

1. The existing scope guardrail runs before loading user records.
2. Existing semantic tool selection chooses `get_task_performance` or
   `get_failure_patterns`, retaining category/title/date bounds. Tool descriptions guide
   hour grouping for productivity questions, weekday grouping for weekday questions, and
   date grouping for progress/reviews. The same existing scope-selection call also returns
   `visualization_focus` (hour, weekday, trend, comparison, failure, or null), based on the latest question.
   No extra provider request is made. Ordinary conversation should select no tools.
3. The registry validates arguments and injects the authenticated user ID. Existing context
   queries compute outcome summaries. Daily and weekly summaries use the same calculations;
   pending tasks and unknown times never become completed/failed or noon observations.
4. `CoachingVisualizationService` consumes the validated arguments and actual successful
   tool result and the turn's focus. Hour/weekday results become bars. Trends always use
   calendar-week outcomes within the current requested period, even if the tool also retrieves
   previous-period totals. Explicit period comparisons plot categorical bars for the two
   returned periods when both qualify; they never become a two-point aggregate line.
   Failure reasons use recorded counts. Hour/weekday comparative rate groups require five
   outcomes each. Period bars require five per period, consistent completed/failed/rate counts,
   and ordered, adjacent, equal-length windows matching the requested period_days. Weekly descriptive
   trends may include smaller groups if at least two weeks and five total outcomes exist:
   each week's integer counts/rate must reconcile, dates must be unique Mondays in the requested
   period, and the whole series must reconcile with the current-period counts. Small weekly
   samples are explicitly marked uncertain. Failure charts require
   at least two reasons and five recorded reasons in total. Truncated queries produce no chart.
5. Pydantic validates the data-only chart contract. Chart generation errors are isolated from
   successful analytics and coaching. The chart is excluded from serialized LLM tool results.
6. Both existing response paths retain text-token streaming. On successful completion, the
   first eligible chart matching the turn's `visualization_focus` is emitted as
   `data: {"chart": {...}}` before `[DONE]`. Missing focus or insufficient matching data produces
   no chart; a usable trend never substitutes for missing hourly evidence. At most one
   chart per turn prevents overlapping tools from producing duplicates. The per-request
   frontend accumulator associates it with that assistant response.
7. The reusable chart renders inside the assistant bubble, with responsive bar/line canvases,
   tooltips, units, sample sizes, period, theme styles, and an accessible data table. Runtime
   validation applies equally to streamed and restored charts. Missing time buckets become
   null gaps; they are never interpolated or displayed as zero outcomes.
   Axis dates use compact month/day labels, date ranges wrap onto two lines, and the tick limit
   responds to canvas width (2–6 ticks). Full dates remain in tooltips and the data table.
   New percentage points include validated completed/total counts, shown in tooltips and the
   accessible table. Historical messages lacking counts show their original sample sizes;
   completed counts are never inferred from rounded rates. Previously saved two-period lines
   render as bars while retaining their recorded values; no database rewrite is needed.
8. Both response paths pass the same focus to deterministic chart generation and the existing
   coaching prompt. Trend explanations use current-period by_week data; comparison explanations
   use previous/current totals and exact dates. The compare_previous_period retrieval flag does
   not override the question's chart intent. A trend with only one recorded week or a comparison
   missing a sufficiently populated period produces no chart instead of changing dimensions.

## Persistence and migration

Apply `supabase/coach_visualization_metadata.sql` in the **primary project's Supabase SQL
Editor**, after the existing `coach_agent_schema.sql`. It adds only
`coach_messages.metadata jsonb not null default '{}'`. A migration is necessary because
the existing message schema has no structured-content or metadata field. Ownership foreign
keys and RLS policies continue protecting the same rows.

The assistant's text and `metadata.chart` are inserted together. The existing latest-conversation
endpoint returns that metadata; the frontend restores it on the same message after reopening.
Historical text-only messages remain valid. Apply the migration before enabling chart persistence;
an unmigrated database cannot save chart-bearing assistant messages. No database was modified
automatically by this implementation.

## Local commands (PowerShell, repository root)

Use Python 3.11 with the project's existing backend dependencies and configured `.env` files
as described in `README.md`. This session prepared `.venv/py311`; the commands below use
that environment. To recreate it on this machine:

```powershell
& 'C:\Users\paul2\miniconda3\envs\proj2\python.exe' -m venv .venv/py311
.\.venv\py311\Scripts\python.exe -m pip install -r backend\requirements-dev.txt
```

Run the backend:

```powershell
cd backend
..\.venv\py311\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000
```

Run the frontend in another terminal from the repository root:

```powershell
cd habittrace_frontend_dev-main
npm.cmd ci
npm.cmd run dev
```

Backend checks, from `backend`:

```powershell
..\.venv\py311\Scripts\python.exe -m pytest -q tests/test_coaching_visualization.py tests/test_coach_tools.py tests/test_coaching_agent.py tests/test_openai_llm_client.py tests/test_coach_planning_tools.py tests/test_coach_daily_schedule_tools.py tests/test_auth.py
..\.venv\py311\Scripts\python.exe -m ruff check app/schemas/coach_chart.py app/schemas/coach_tools.py app/services/coaching_visualization_service.py app/services/coaching_context_service.py app/services/coach_tool_registry.py app/services/chat_service.py app/services/coach_repository.py tests/test_coaching_visualization.py
```

Frontend checks, from `habittrace_frontend_dev-main`:

```powershell
npm.cmd test
npx.cmd tsc --noEmit
npm.cmd run lint
```

## Limits and manual acceptance

- Visualization intent follows existing semantic tool selection and grouping; there is no
  additional classifier or keyword router. Provider mistakes can select an unsuitable tool.
- Insufficient or inconsistent samples produce text alone; valid small weekly samples can
  appear as explicitly uncertain descriptive points. Rates describe recorded success/failed outcomes, not
  every scheduled task. Planned hour is not proof of actual productivity at that hour.
- Weekly boundary buckets may be partial; the chart labels this explicitly. Missing records,
  unknown times, absent reasons, and omitted small samples are not invented.
- Queries remain bounded at 200 rows. Charts are omitted when that bound is reached; tool
  data notes flag potentially incomplete statistics. Failure reasons show top recorded counts,
  not causal conclusions or all failed tasks.
- Automated frontend tests render the React/chart boundary with a canvas stub. They do not
  test actual canvas painting or hover interaction in a browser. Real Supabase persistence
  and a configured LLM also require a signed-in integration check.

After applying the migration, sign in with recorded outcomes and ask “When am I most
productive?”, “How has my completion rate changed?”, and “Why do I keep missing my habits?”.
Check chart tooltips, mobile width, accessible table, and refresh restoration. “Thank you” and
“Help me stay motivated” should show text alone. “Write Python code for me” should keep the
scope redirect. Confirm scheduling proposals still require explicit confirmation.

## Verification results

- Python 3.11: **133 passed** across the seven backend test files listed above, including
  all 41 visualization cases and existing scope, OpenAI, planning, and auth regressions.
- Frontend `npm.cmd test`: **20 passed**, including ten chart/SSE/rendering tests.
- `npx.cmd tsc --noEmit`: passed.
- Ruff on all changed backend Python files: passed.
- ESLint on `components/coach-chart.tsx`, `components/coach-chat.tsx`, `lib/coach-chart.ts`,
  `lib/api.ts`, and `tests/coach-chart.test.cjs`: passed.
- Full `npm.cmd run lint` remains failing at the existing `components/ui/toast.tsx:115`
  `react-hooks/set-state-in-effect` error, with three existing hook warnings elsewhere.
- `git diff --check`: passed.

Earlier sandboxed test runs had intermittent `WinError 10014` failures inside `asyncio`
socket-pair creation, including existing tests. The current Python 3.11 combined suite passed.
The passing run still emitted existing model-artifact version
warnings (serialized scikit-learn 1.8 artifacts with the repository's pinned 1.9 runtime) and a
Starlette/httpx test-client deprecation warning. No model/dependency constraints were changed.
The SQL migration and signed-in browser acceptance checks were not executed against a live account.

## Live-test regression fixes

The supplied 60-day record (11 successes / 17 outcomes) reproduces intentional suppression in
the old weekly selector: requiring five observations in *every* week left only Sep 7 eligible,
then the two-point minimum rejected the chart before schema validation/SSE emission. The new
weekly check retains the real counts 0/2, 5/7, 1/2, 4/4, 1/2 as rates 0, 71.4, 50, 100, 50.
Sep 21 remains an unobserved gap. Inconsistent counts/rates, omitted populated buckets,
duplicate dates, and truncated results are still rejected. No historical tool-call audit is
stored, so the original live call's exact arguments cannot be recovered from conversation text.

The unrelated productivity chart came from choosing the first usable result without a
question-dimension check. Both response paths now compare each generated chart's typed focus
with the existing scope decision's focus. Hourly evidence stays subject to the original sample
threshold; missing hourly evidence cannot fall back to a trend from another result. Regression
tests exercise both original questions through actual aggregation, validation, SSE, and metadata
persistence, plus frontend decoding/rendering of the sparse weekly series and responsive ticks.

The subsequent analytical issue had a separate cause: the compare_previous_period retrieval
flag took precedence over weekly data, generated two aggregate points as a line, and labeled
them with the same trend focus. Daily observations were also preferred over calendar weeks.
The selector now distinguishes comparison from trend, passes that intent through the registry,
uses weekly data exclusively for trends, and uses bars exclusively for period comparisons.
New tests retrieve complete 60-day current/previous totals in both streaming paths: a trend
still plots only the five recorded current-window weeks, while a comparison plots two bars
covering the two real windows. Tests also cover one-week suppression, insufficient comparison
evidence, validated completed/total counts, null gaps, relevance, and historical chart rendering.

## Files

Created:
- `backend/app/schemas/coach_chart.py`
- `backend/app/services/coaching_visualization_service.py`
- `backend/tests/test_coaching_visualization.py`
- `habittrace_frontend_dev-main/lib/coach-chart.ts`
- `habittrace_frontend_dev-main/components/coach-chart.tsx`
- `habittrace_frontend_dev-main/tests/coach-chart.test.cjs`
- `supabase/coach_visualization_metadata.sql`
- `COACH_VISUALIZATIONS.md`

Modified:
- `backend/app/schemas/coach_tools.py`
- `backend/app/services/coaching_context_service.py`
- `backend/app/services/coach_tool_registry.py`
- `backend/app/services/chat_service.py`
- `backend/app/services/llm_client.py`
- `backend/tests/test_openai_llm_client.py`
- `backend/app/services/coach_repository.py`
- `habittrace_frontend_dev-main/lib/api.ts`
- `habittrace_frontend_dev-main/components/coach-chat.tsx`

# HabitTrace upgrade work log

Branch: `improvement/reliable-planning-ai-v2`. Requested scope: fix audited defects, simplify planning UX, improve and evaluate AI V2, remove unused files, document changes. Do not publish until requested.

## Work checklist

- [x] Remove 11 byte-identical, untracked ` 2` copies (originals retained).
- [x] Reliable task mutations, errors and cross-screen refresh/search.
- [x] Today-first home, Plans view navigation, responsive shell, contextual coach.
- [x] Shared quick add / outcome / accessible dialog and consistent feedback.
- [x] Scheduler local dates, minutes, unavailable predictions, actionable guidance.
- [x] Real saved preferences, honest feature availability, personal task/execution export.
- [x] Group assignment filter and explicit personal-plan copy.
- [x] Analytics empty/error states and supportive language.
- [x] AI V2 baseline audit, data provenance, model comparison/calibration, retrain and tests.
- [ ] Tests, lint, build, visual checks and final report.

## Baseline

Current deployed V2 is `synthetic-baseline-1`, trained on 475 synthetic training examples; test 160. Recorded test ROC AUC 0.7305, Brier 0.2135, log loss 0.6357. These are synthetic results, not real-user accuracy. Failure model has only 176 training rows and some near-random labels.

Public datasets reviewed: [UCI Student Performance](https://www.archive.ics.uci.edu/dataset/320/student%2Bperformance) predicts grades; [BLS ATUS](https://www.bls.gov/tus/data/datafiles-2024.htm) measures time spent. Neither supplies this app's paired plan/completion/confirmed-reason labels, so neither should be relabeled as HabitTrace training truth.

Real exports, if available, must stay local and ignored by Git. Preserve V1 artifacts: V1 routes still use them.

## Implementation progress

- Today home reuses the start/outcome flow on desktop and mobile; responsive five-item navigation and contextual coach dialog.
- Plans page rewritten around server-confirmed writes, shared quick add/edit, task-specific search links, deletion dialog, preserved input after errors.
- Scheduler uses local dates and minute precision; buffered free slots honor persisted planning hours; unavailable/experimental AI is labeled.
- Settings now persist name and planning defaults in authenticated Supabase user metadata. Unsupported notification/theme/delete controls replaced with explicit availability information.
- Added `/account/export` with owner-scoped pagination for personal tasks/executions (scope explicitly excludes group/AI research records).
- Group assignment filter, explicit editable personal copy, shared deletion confirmation; calendar uses shared quick add.
- Analytics distinguishes load errors/empty records and offers actionable, qualified retrospective guidance.
- Removed 10 unreferenced source/default asset files as well as the 11 duplicates. V1 training data/artifacts remain because V1 backend routes depend on them.
- Model comparison: C=0.01/0.1/1 logistic, histogram gradient boosting, sigmoid-calibrated logistic (separate chronological calibration portion inside training). Choose using outer validation Brier/log loss only. Independent per-reason shrinkage and small-class smoothed priors.
- Actual AI DB export (local `/private/tmp/habittrace-ai-upgrade-real`) contains 91 plans, 8 usable outcomes, 3 failed examples / 4 reason labels. Too small for model validation/training promotion. No real data committed.
- Same untouched synthetic test set: baseline Brier .2135475 / log loss .6357207 / AUC .7304987; selected logistic C=.01 Brier .2060274 / log loss .5996835 / AUC .7408887. Paired row bootstrap Brier improvement interval [-.01026, .02682] includes zero. No real-world efficacy claim.
- Training rerun verified: both artifact manifests identify `synthetic-validated-2` and synthetic provenance; the application lifespan successfully loads the artifacts. Fixtures use `input_source=user`, so source cannot be inferred from that column alone. Sidecar synthetic manifest overrides source. Runtime metadata includes training evidence.
- New manual actual-time input for outcomes when timer was not started. Backend schema accepts paired aware actual times, validates chronology/future bounds. Complete retries repair parent task status.

## Verification — 2026-09-08

- Backend: 110 tests passed, including manual actual-time recording and owner-scoped paginated export.
- AI package: 29 tests passed, including validation-only selection, artifact roundtrip, rare-label fallback, and small-sample rejection.
- Frontend time/preferences helpers: 6 tests passed.
- TypeScript (`npx tsc --noEmit`), ESLint (`npm run lint`), and production build (`npm run build`): passed; 23 pages generated.
- Ruff: backend and AI package passed. AI package strict mypy: passed (15 source files).
- Backend mypy: inconclusive. The normal run stalled for over five minutes while reading installed dependencies; fresh-cache and outside-sandbox retries also made no visible progress. Validation processes were stopped. Rerun `.venv/bin/python -m mypy app` from `backend` before release; no type-check success is claimed.
- In-process FastAPI startup/health smoke check: HTTP 200, `ready=true`, V1 and AI V2 models loaded. This checks local configuration/model loading, not live database connectivity or OAuth.
- Existing V1 artifacts emit a scikit-learn version warning (trained on 1.8.0; local runtime 1.9.0). V1 was preserved; version alignment/retraining remains a deployment follow-up, not a validated compatibility guarantee.
- Browser visual/authenticated end-to-end QA remains unverified: the earlier CUA runtime failed to start and no browser/computer tool is available in the continuation session. No authentication bypass or real-data test writes were performed.
- Documentation updated; no commit, push, migration execution, or deployment performed.
- `git diff --check`: passed.

## Manual acceptance checklist

Use a test account; the following actions intentionally create or modify its records.

1. On desktop and phone, open Today → Quick Add. Create a plan at 09:15, edit it in Plans, and check Calendar, Scheduler, and search reflect the saved values.
2. Start a plan and record an outcome. For a different plan without a timer, enter actual start/end times; check partial/failure reasons and reject an end before its start.
3. Save planning hours and buffer in Settings, reload, and verify Scheduler offers minute-accurate free slots within those hours. A too-long activity should have no slot, not overlap another plan.
4. Temporarily disconnect networking while saving a plan. Confirm an error is visible and entered text remains; reconnect and retry.
5. Filter group tasks by assignment. Copy one into a personal plan, edit the proposed details, and confirm it appears only after saving.
6. Check Insights with an empty test account and with completed outcomes. Inspect personal JSON export and verify it excludes another user's tasks and group/AI research records.
7. Open/close the coach with keyboard and mobile touch; check dialog focus and navigation. Ask: “I want to study for 90 minutes tomorrow. Find the best time between 9 AM and 8 PM.” Review the proposal before confirming.

Work stays local on `improvement/reliable-planning-ai-v2`. Complete manual visual checks before deciding whether to merge and deploy.

# HabitTrace AI V2

HabitTrace AI V2 is a standalone Python package for building and validating models from the dedicated AI Supabase schema. It is designed to reduce label leakage, preserve plan-revision lineage, and produce reviewable model artifacts.

The package does not create browser clients, load frontend environment variables, or modify the legacy V1 model directory. Database export is read-only.

## Current scope

- Derive success labels from recorded outcomes instead of storing a duplicated boolean
- Use only information known at planning time as model features
- Use only server-confirmed user failure reasons as targets
- Split data chronologically using label-availability time
- Keep equal timestamps in one partition
- Exclude revision lineages that cross evaluation boundaries
- Train an unweighted logistic-regression baseline for success probability
- Train independent logistic-regression baselines for multi-label failure reasons
- Evaluate probability quality and classification quality
- Save joblib artifacts with manifests and SHA-256 checks
- Export validated snapshots from AI Supabase through a read-only REST client

CatBoost remains an optional dependency for future comparison experiments. There is no LLM coach in this package. The FastAPI time-recommendation service uses success predictions to score candidate slots; AI V2 does not currently train a separate time-ranking model.

## Label policy

The initial success definition is derived at dataset-build time:

```text
outcome_status == "completed" AND completion_ratio >= 0.8
```

It is not stored as a separate database boolean.

Failure targets come only from rows that satisfy the database truth constraints, including `user_confirmed = true`. A reason attached to a successful outcome or an unknown reason definition is rejected.

## Leakage controls

The success and failure datasets use a fixed planning-time feature schema. Actual start/end times, completion ratio, stopped-early state, and failure-reason confirmation timestamps are labels or label-availability metadata, not prediction inputs.

Temporal splitting observes these rules:

- A training row is usable only when `label_available_at` is earlier than the validation boundary.
- A validation row is usable only when `label_available_at` is earlier than the test boundary.
- Failure label availability is the later of outcome creation and user reason confirmation.
- Revisions related across a split boundary are excluded from evaluation.
- `temporal_split_aligned()` keeps feature and target indexes aligned.

## Requirements and installation

Python 3.11 or newer is required.

```powershell
cd habittrace_ai_v2
python -m pip install -e ".[dev]"
```

CatBoost is optional:

```powershell
python -m pip install -e ".[catboost]"
```

## Generate synthetic fixtures

```powershell
python fixtures/generate_synthetic.py --rows 800
```

See `fixtures/README.md` for the fixture contract and safety rules.

## Export a real-data snapshot

The exporter reads `ai_plan_inputs`, `ai_plan_outcomes`, and confirmed failure reasons through Supabase REST. It never writes to the database.

```powershell
python -m habittrace_ai.export_db `
  --env-file ..\backend\.env `
  --outdir data\real
```

It writes:

- `plans.csv`
- `outcomes.csv`
- `failure_reasons.csv`
- `manifest.json`

By default, invalid or empty training snapshots fail closed. `--allow-invalid` is for controlled diagnostics only and must not be used to approve training data.

Review `manifest.json` before training. Never commit real user exports, service-role keys, access tokens, or free-form user notes.

## Train baseline artifacts

Synthetic example:

```powershell
python -m habittrace_ai.train `
  --plans fixtures\synthetic_plans.csv `
  --outcomes fixtures\synthetic_outcomes.csv `
  --failure-reasons fixtures\synthetic_failure_reasons.csv `
  --outdir artifacts\synthetic `
  --model-version synthetic-baseline
```

Real snapshot example:

```powershell
python -m habittrace_ai.train `
  --plans data\real\plans.csv `
  --outcomes data\real\outcomes.csv `
  --failure-reasons data\real\failure_reasons.csv `
  --outdir artifacts\real `
  --model-version real-baseline-001
```

Training writes:

| File | Purpose |
|---|---|
| `success_model.joblib` | Success-probability pipeline |
| `success_model.joblib.manifest.json` | Version, schema, label policy, metrics, data hash, and model hash |
| `failure_reason_model.joblib` | Independent failure-reason models |
| `failure_reason_model.joblib.manifest.json` | Failure artifact metadata and hashes |
| `metrics.json` | Row counts and evaluation output |

## Probability interpretation

The current logistic-regression baseline does not use class weights that intentionally shift the prior. That does not make raw `predict_proba` output production-calibrated.

Before using a model for user-facing recommendations, evaluate it on untouched temporal data with Brier score, log loss, and calibration curves. Fit sigmoid or isotonic calibration separately when validation evidence supports it.

## Artifact safety

Load joblib files only from trusted backend artifact storage. SHA-256 manifests detect accidental corruption and mismatched files, but they are not digital signatures. An attacker who can replace both a model and its manifest can bypass a checksum comparison.

Artifact loading validates model type, feature schema, label policy, manifest fields, and the serialized model hash.

## Tests and static checks

```powershell
python -m pytest -q
python -m ruff check src tests
python -m mypy src
```

The test suite covers label derivation, feature leakage boundaries, timezone handling, temporal splits, revision lineage, exporter quality checks, independent failure probabilities, artifact round trips, and checksum/contract validation.

## Backend integration

The FastAPI backend can load the development baseline from:

```text
../habittrace_ai_v2/artifacts/synthetic
```

Override it with `AI_V2_CODE_DIR` and `AI_V2_ARTIFACTS_DIR` in `backend/.env`. The AI database service-role key belongs only in `backend/.env`; this training package does not need it unless the read-only exporter is explicitly run.

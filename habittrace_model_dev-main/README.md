# HabitTrace V1 ML pipeline

This package contains the legacy planning-time machine-learning pipeline used by the FastAPI `/predict` endpoint.

It trains two scikit-learn models:

1. A binary logistic-regression model for task success probability.
2. A multinomial logistic-regression model for the likely failure reason among failed tasks.

It also supports optional per-user calibration parameters updated from observed outcomes.

## Scope

- Python CLI for train, evaluate, predict, and online personalization updates
- Planning-time feature engineering only
- Saved `joblib` pipelines consumed by the sibling FastAPI backend
- No Supabase client, HTTP server, frontend, or AI V2 schema code

New leakage-safe experiments and AI V2 artifacts live in `../habittrace_ai_v2`.

## Requirements

Python 3.10 or newer is recommended.

```powershell
cd habittrace_model_dev-main
python -m pip install -r requirements.txt
```

## CSV contract

| Column | Required for prediction | Training use |
|---|---:|---|
| `user_id` | No | Optional calibration identity; added as empty when absent |
| `Task Name (Optional)` | No | Never used as a model feature |
| `Category` | Yes | Planning-time feature |
| `Planned Start Date & Time` | Yes | Planning-time date and time features |
| `Planned Duration (mins)` | Yes | Planning-time feature |
| `Importance (1-5)` | Yes | Planning-time feature |
| `Energy Level (1-5)` | Yes | Planning-time feature |
| `Focus Level (1-5)` | Yes | Planning-time feature |
| `Total Tasks Today` | Yes | Planning-time workload feature |
| `Actual Start Time` | No | Parsed for data consistency, not a planning-time feature |
| `Actual End Time` | No | Parsed for data consistency, not a planning-time feature |
| `Interruptions (Count)` | No | Outcome metadata, not a planning-time feature |
| `Stopped Early?` | No | Outcome metadata |
| `Task Status` | Training only | Binary success label |
| `Reason for Failure (If failed)` | Failure training only | Failure-reason label |

Status values equivalent to completed/success are normalized to `completed`; failure equivalents are normalized to `failed`. Skipped and canceled rows are excluded from binary training and evaluation.

Categories are normalized to lowercase and categories with fewer than three rows collapse to `other`. Failure reasons are canonicalized to:

- `start_delay`
- `low_energy`
- `low_focus`
- `interruptions`
- `time_underestimate`
- `schedule_conflict`
- `unexpected_event`
- `other`

Reasons with fewer than five failed examples collapse to `other`.

## CLI

Run all commands from this directory.

### Train

```powershell
python -m ml.cli train --csv path\to\training.csv --outdir artifacts
```

The success model requires at least two completed/failed rows. Failure-model training is skipped when there are not enough failed rows with usable reason labels.

### Evaluate

```powershell
python -m ml.cli evaluate --csv path\to\evaluation.csv --modeldir artifacts
```

Evaluation prefers a chronological 80/20 split by planned start time and falls back to a stratified split when usable timestamps are unavailable. It writes `artifacts/metrics.json` with success AUC, accuracy, log loss, Brier score, calibration-curve points, and failure macro F1/confusion-matrix data when calculable.

### Predict one plan

```powershell
python -m ml.cli predict `
  --modeldir artifacts `
  --failure_probs `
  --input_json '{
    "user_id": "example-user",
    "Category": "work",
    "Planned Start Date & Time": "2026-08-27 14:00:00",
    "Planned Duration (mins)": 30,
    "Importance (1-5)": 4,
    "Energy Level (1-5)": 3,
    "Focus Level (1-5)": 4,
    "Total Tasks Today": 5
  }'
```

Useful options:

- `--top_k N`: maximum number of contribution rows; default is 10
- `--failure_probs`: include failure-class probabilities when a failure artifact exists

The JSON output includes `p_global_success`, `p_personal_success`, `top_contributions`, and optionally `failure_type_probs`.

### Update one user's calibration

```powershell
python -m ml.cli update_personal `
  --modeldir artifacts `
  --user_id example-user `
  --p_global 0.42 `
  --y 1
```

Use `--y 1` for success and `--y 0` for failure. Add `--use_scale` to update both the calibration scale `a` and offset `b`; otherwise only `b` is updated. Small user histories receive stronger regularization toward the global model. The design threshold for considering calibration mature is 30 observed tasks.

## Artifacts

| Path | Created by | Contents |
|---|---|---|
| `artifacts/success_model.joblib` | `train` | Feature builder and binary logistic-regression model |
| `artifacts/failure_model.joblib` | `train`, when labels are sufficient | Feature builder, failure classifier, and label encoder |
| `artifacts/calib_params.json` | `train`/`update_personal` | Per-user calibration parameters |
| `artifacts/metrics.json` | `evaluate` | Evaluation metrics and calibration data |

Only load trusted `joblib` artifacts. A joblib file is executable Python serialization, not a safe interchange format for untrusted downloads.

## Backend integration

The backend defaults to:

```text
../habittrace_model_dev-main/artifacts
```

Override the location with `MODEL_ARTIFACTS_DIR` in `backend/.env` when the directory layout changes.

The API receives the authenticated user identity from Supabase. Do not use a display name as a calibration or ownership key in production.

## Validation status

This V1 package does not currently contain an automated test directory. Before replacing production artifacts, run a representative train/evaluate/predict cycle and validate the backend tests from `../backend`.

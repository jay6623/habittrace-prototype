# Productivity Capstone — ML Pipeline

Scope of design and implementation: **ML model pipeline only** (no backend/frontend).  
This is a Python CLI module that supports success probability prediction, failure reason classification, and user-specific calibration (personalization).

## Data Schema (CSV)

| Column | Description |
|--------|-------------|
| Task Name (Optional) | String, **not used as a feature** |
| Category | String |
| Planned Start Date & Time | datetime |
| Planned Duration (mins) | int |
| Importance (1-5) | int |
| Energy Level (1-5) | int |
| Focus Level (1-5) | int |
| Total Tasks Today | int |
| Actual Start Time | datetime (optional) |
| Actual End Time | datetime (optional) |
| Interruptions (Count) | int (optional) |
| Stopped Early? | bool |
| Task Status | completed / failed / skipped, etc. |
| Reason for Failure (If failed) | start_delay, time_underestimate, etc. |

**USER_ID**: If not present in the CSV, the pipeline assumes a `user_id` column exists. If the value is empty, only the global model is used. Personalization is applied only when `user_id` exists and calibration parameters are available.

**Task Status handling**: `completed` → y_success=1, `failed` → y_success=0.  
**skipped / canceled** are **excluded** from training and evaluation (only binary success/failure is used).

## Installation

```bash
pip install -r requirements.txt
```

## CLI commands

Run from the project root (python -m ml.cli).

### 1. Train Global Model

```bash
python -m ml.cli train --csv PATH_TO_DATA.csv --outdir artifacts
```

- `artifacts/success_model.joblib`: Logistic regression for success + PlanTimeFeatureBuilder  
- `artifacts/failure_model.joblib`: Multinomial logistic regression + encoder
- `artifacts/calib_params.json`: Per-user b_user (and optionally a_user) and n
- 'artifacts/metrics.json' : Metrics saved after evaluation

### 2. Evaluate (print and save metrics)

```bash
python -m ml.cli evaluate --csv PATH_TO_DATA.csv --modeldir artifacts
```

- Split into train/validation based on time (or stratified), then evaluate on validation set 
- Model 1: AUC, accuracy, log-loss, Brier score, calibration curve  
- Model 2: macro F1, confusion matrix  
- result is saved in `artifacts/metrics.json` 

### 3. Predict (single row)

```bash
python -m ml.cli predict --modeldir artifacts --input_json '{
  "user_id": "alice",
  "Category": "work",
  "Planned Start Date & Time": "2025-03-05 14:00:00",
  "Planned Duration (mins)": 30,
  "Importance (1-5)": 4,
  "Energy Level (1-5)": 3,
  "Focus Level (1-5)": 4,
  "Total Tasks Today": 5
}'
```

- `--top_k 10` (default 10): top K feature contributions 
- `--failure_probs`: include failure type probabilities  

Output example:

- `p_global_success`: global success probability 
- `p_personal_success`: personalized probability if user_id and calibration exist, otherwise null 
- `top_contributions`: feature, contribution, value  
- `failure_type_probs`: (optional) probabilities for each failure type


### 4. Personalization Online Update

Update only the calibration for a specific user when new results arrive.

```bash
python -m ml.cli update_personal --modeldir artifacts --user_id alice --p_global 0.42 --y 1
```

- `--y 1`: succes, `--y 0`: fail 
- `--use_scale`: also update a_user (scale) (optional)

## Artifacts

| file | description |
|------|------|
| `artifacts/success_model.joblib` | Logistic regression for success + PlanTimeFeatureBuilder |
| `artifacts/failure_model.joblib` | Multinomial logistic regression + encoder |
| `artifacts/calib_params.json` | Per-user b_user (and optionally a_user) and n |
| `artifacts/metrics.json` | Metrics saved after evaluation |

## Design Summary

- **Model 1**: Uses only planning-time features (Category, planned start time/day, planned duration, importance, energy, focus, total tasks today). L2 logistic regression. Contributions computed as `w_i * x_i` (in scaled feature space).
- **Model 2**: Uses only failed rows. Multinomial logistic regression (softmax) on “Reason for Failure”. Provides top-K contributions for the predicted class.
- **Personalization**: `p_personal = sigmoid(logit(p_global) + b_user)` (optional: `a_user * logit(p_global) + b_user`). Online updates with strong regularization when N is small, or N ≥ 30. Parameters are stored per user in calib_params.json.

- **skipped/canceled**: 학습·평가에서 제외 (성공/실패 이진만 사용).
- **USER_ID**: CSV에 없으면 `user_id` 컬럼을 비우고, 개인화는 해당 사용자 보정이 있을 때만 출력.
- **기여도**: `top_contributions`의 `value`는 **스케일된(표준화된) 입력** 기준이며, `contribution = w_i * x_i` (로지스틱 계수 × 스케일된 값).

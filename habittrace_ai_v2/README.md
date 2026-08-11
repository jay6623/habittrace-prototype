# HabitTrace AI V2

새 AI 전용 테이블에서 만든 학습용 데이터로 모델 구조를 독립적으로 검증하는 패키지입니다.
기존 `habittrace_model_dev-main`이나 FastAPI 런타임과 연결되지 않으며, Supabase client와
환경변수 로딩 코드도 포함하지 않습니다. 따라서 이 폴더에는 `service_role` key가 필요하지
않습니다.

## 현재 범위

- 성공 라벨을 실행 결과에서 동적으로 계산
- 계획 당시 알 수 있던 값만 feature로 변환
- 사용자가 확인한 실패 원인만 multi-label 정답으로 사용
- 무작위 분할 대신 label 가용 시각을 고려한 시간순 train/validation/test 분할
- 같은 시각의 행은 한 partition에 유지하고, 경계를 넘는 revision 계보는 평가에서 제외
- 성공확률 Logistic Regression baseline
- 실패 원인별 독립 Logistic Regression baseline
- 모델 파일과 manifest의 SHA-256 검증

초기 성공 정의는 아래와 같으며 DB에 별도 boolean으로 저장하지 않습니다.

```text
outcome_status == "completed" AND completion_ratio >= 0.8
```

CatBoost, 시간 추천, LLM 코치는 아직 구현 범위가 아닙니다. `catboost`는 나중의 비교 실험을
위한 선택적 dependency로만 선언되어 있습니다.

현재 Logistic Regression은 class weight로 사전확률을 인위적으로 바꾸지 않는 baseline입니다.
그래도 `predict_proba`가 곧바로 운영용 확률이라는 뜻은 아닙니다. 실제 시간 추천에 연결하기
전에는 untouched temporal validation 데이터에서 Brier/log-loss와 calibration curve를 확인하고,
필요하면 sigmoid 또는 isotonic calibration을 별도 학습해야 합니다.

시간순 평가에서 학습 행은 `label_available_at`이 validation 시작 시각보다 이른 경우만,
validation 행은 해당 값이 test 시작 시각보다 이른 경우만 사용됩니다. 실패 원인 데이터의 이
시각은 outcome 기록 시각과 사용자 원인 확인 시각 중 더 늦은 값입니다. X/y는 같은 index를
유지하며 `temporal_split_aligned()`로 함께 나눕니다.

joblib은 신뢰된 backend artifact만 로드해야 합니다. SHA-256 manifest는 우발적인 손상이나
파일 불일치를 탐지하지만, 공격자가 model과 manifest를 함께 바꾸는 상황을 막는 서명은
아닙니다.

## 실행

저장소의 backend 개발 dependency가 설치되어 있다면 바로 검사할 수 있습니다.

```powershell
cd habittrace_ai_v2
python -m pytest -q
python -m ruff check src tests
python -m mypy src
```

## Real-data export

Use the read-only exporter to create a validated snapshot from the AI
Supabase tables. It writes `plans.csv`, `outcomes.csv`, `failure_reasons.csv`,
and `manifest.json` without modifying the database.

```powershell
cd habittrace_ai_v2
python -m habittrace_ai.export_db `
  --env-file ..\backend\.env `
  --outdir data\real
```

Review `data\real\manifest.json` before training with `habittrace_ai.train`.
Keep real snapshots and service-role keys out of the frontend and source control.

별도 가상환경에서는 다음처럼 설치합니다.

```powershell
python -m pip install -e ".[dev]"
```

실제 DB export는 이 패키지 밖의 backend 또는 별도 보안 export 작업이 담당해야 합니다.
원본 DB key, access token, 사용자 메모가 들어간 파일을 이 폴더에 커밋하지 마세요.

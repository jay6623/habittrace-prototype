# Fixtures

테스트는 코드에서 생성한 익명 synthetic DataFrame을 사용합니다. 실제 V2 데이터를 수동으로
검사할 필요가 있을 때만 비식별 fixture를 이 폴더에 두세요.

`generate_synthetic.py`는 파이프라인 개발용 합성 baseline을 생성합니다. 실제 사용자
관측값이 아니므로 제품 성능, 사용자 행동, 연구 결과로 해석하거나 보고하면 안 됩니다.

```powershell
cd habittrace_ai_v2
python fixtures/generate_synthetic.py --rows 800
```

출력 파일:

- `synthetic_plans.csv`
- `synthetic_outcomes.csv`
- `synthetic_failure_reasons.csv`
- `synthetic_manifest.json`

- `ai_plan_inputs`와 `ai_plan_outcomes`는 `plan_input_id`로 연결합니다.
- 실패 원인은 `user_confirmed = true`인 행만 사용합니다.
- 실제 export, 인증 토큰, Supabase key는 커밋하지 않습니다.
- 기존 V1 CSV의 열을 V2 정답으로 간주하거나 억지로 이름만 바꾸지 않습니다.

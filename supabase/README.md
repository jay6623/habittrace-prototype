# Supabase schemas

- `schema.sql`: 기존 HabitTrace V1용 legacy schema
- `ai_schema.sql`: 별도 AI V2 프로젝트용 bootstrap + 무결성 보강 SQL
- `verify_ai_schema.sql`: AI SQL 실행 뒤 상태를 읽기 전용으로 확인하는 query

AI 프로젝트에 이미 9개 table이 있어도 `ai_schema.sql`을 다시 실행해야 새 RLS, constraint,
index, trigger가 적용됩니다. 실행 전에는 Supabase backup을 만들고, transaction이 실패하면
오류를 무시하지 말고 기존 행이 새 제약을 위반하는지 먼저 확인하세요. `CREATE TABLE IF NOT
EXISTS`는 임의의 오래된/부분 schema를 자동 migration하지 않으므로, verification 결과가
모두 기대와 같은지 확인해야 합니다.

FastAPI의 `backend/.env`에만 아래 값을 둡니다.

```text
AI_SUPABASE_URL=...
AI_SUPABASE_SERVICE_ROLE_KEY=...
```

`AI_SUPABASE_SERVICE_ROLE_KEY`를 `NEXT_PUBLIC_` 변수, 프론트엔드 `.env.local`, 브라우저 코드에
넣으면 안 됩니다.


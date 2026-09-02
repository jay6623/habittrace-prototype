# HabitTrace

HabitTrace is a planning and execution-tracking application with a Next.js frontend, a FastAPI API, Supabase authentication and storage, and two machine-learning pipelines.

The desktop experience focuses on scheduling, analytics, patterns, and predictions. The installable mobile PWA focuses on the shortest path through four actions: add a plan, see what is next, start it, and record the outcome.

## Repository layout

```text
habittrace_prototype/
├── backend/                        FastAPI API and Supabase service layer
├── habittrace_frontend_dev-main/  Next.js App Router frontend and mobile PWA
├── habittrace_model_dev-main/     Legacy V1 scikit-learn pipeline and artifacts
├── habittrace_ai_v2/              Leakage-safe AI V2 training package
└── supabase/                       V1 and AI V2 SQL schemas
```

## Current product surfaces

### Desktop web

- Dashboard and plan health
- Task management
- Month and week calendar
- Scheduler and time recommendations
- Analytics and failure patterns
- AI Coach backed by Ollama when configured
- Profile and account settings

### Mobile PWA

- English mobile-first login using the same Supabase account as desktop
- Today view with the active or nearest plan
- Quick Add with date, start time, duration, and optional details
- Idempotent start recording with a server-generated timestamp
- Completed, partially done, not completed, and still-in-progress outcome flows
- Canonical failure-reason buttons for partial and failed outcomes
- Month calendar with date selection and date-prefilled Quick Add
- Account screen opened from the `HT` button, including display-name editing and sign-out
- Web App Manifest, install icons, standalone mode, and a privacy-preserving offline fallback

The current Service Worker does not cache private plan data. Push notifications, offline write synchronization, Apple/Google Calendar synchronization, and native iOS/Android projects are not implemented.

## Architecture

```text
Browser / installed PWA
  │ Supabase session JWT in Authorization: Bearer <token>
  ▼
FastAPI API
  ├── Primary Supabase: Auth, profiles, tasks, executions, predictions
  ├── AI V2 Supabase: immutable plan inputs, outcomes, reasons, predictions
  ├── V1 scikit-learn artifacts
  └── Ollama / Phi-3 Mini for the optional AI Coach
```

User-owned API routes validate the Supabase access token. The backend derives `user_id` from the verified token and filters every task and execution operation by that UUID; client-supplied demo user headers are not accepted.

## Requirements

| Tool | Version | Used by |
|---|---:|---|
| Node.js | 20.9 or newer | Next.js 16 frontend |
| npm | Compatible with the selected Node.js release | Frontend dependencies and scripts |
| Python | 3.10 or newer | FastAPI and V1 ML |
| Python | 3.11 or newer | AI V2 package |
| Supabase | Two projects recommended | Primary application data and isolated AI V2 data |
| Ollama | Optional | Local AI Coach |

## Setup

### 1. Primary Supabase project

1. Create a Supabase project.
2. Run `supabase/schema.sql` in the SQL Editor.
3. Run `supabase/coach_agent_schema.sql` to add persisted coach conversations,
   preferences, and confirmation-gated action proposals.
4. Copy the project URL, anon key, and service-role key from the project API settings.
5. Configure the desired Auth providers and redirect URLs.

`schema.sql` includes the partial unique index that allows only one open execution per task. Existing databases must run the latest schema SQL so concurrent Start requests receive the database-level guarantee.

### 2. AI V2 Supabase project

Use a separate project for AI V2 when possible:

1. Back up an existing database before applying changes.
2. Run `supabase/ai_schema.sql`.
3. Run the read-only checks in `supabase/verify_ai_schema.sql`.
4. Keep the AI service-role key in the backend environment only.

AI V2 tables have RLS enabled without browser policies. They are accessed through the authenticated FastAPI boundary with a backend-only service-role client.

### 3. Backend

```powershell
cd backend
python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

Fill in `backend/.env`:

| Variable | Required | Purpose |
|---|---|---|
| `SUPABASE_URL` | Yes | Primary Supabase project URL |
| `SUPABASE_SERVICE_KEY` | Yes | Primary backend-only service-role key |
| `SUPABASE_ANON_KEY` | Yes | Token verification client |
| `AI_SUPABASE_URL` | For AI V2 | AI Supabase project URL |
| `AI_SUPABASE_SERVICE_ROLE_KEY` | For AI V2 | AI backend-only service-role key |
| `AUTH_SUPABASE_URL` | Optional | Separate token issuer; defaults to `SUPABASE_URL` |
| `AUTH_SUPABASE_ANON_KEY` | Optional | Must be paired with `AUTH_SUPABASE_URL` |
| `FRONTEND_URL` | Yes | Frontend origin; local default is `http://localhost:3000` |
| `CORS_ORIGINS` | Optional | Comma-separated production browser origins |
| `TRUST_FORWARDED_HEADERS` | Production-dependent | Trust reverse-proxy scheme and client IP headers |
| `PROXY_TRUSTED_HOSTS` | Production-dependent | Hosts allowed to supply forwarded headers |
| `API_ROOT_PATH` | Optional | Reverse-proxy path prefix such as `/api` |
| `OLLAMA_CHAT_URL` | Optional | Ollama chat endpoint |
| `OLLAMA_MODEL` | Optional | Ollama model name; default is `phi3` |

Start the API:

```powershell
uvicorn app.main:app --reload --port 8000
```

Verify it:

```powershell
Invoke-RestMethod http://localhost:8000/health
```

Interactive API documentation is available at `http://localhost:8000/docs`.

### 4. Frontend

```powershell
cd habittrace_frontend_dev-main
npm install
```

Create `habittrace_frontend_dev-main/.env.local` manually. Do not commit it.

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-public-key
NEXT_PUBLIC_API_URL=http://localhost:8000
# Optional canonical production origin used by OAuth redirects:
# NEXT_PUBLIC_SITE_URL=https://app.example.com
```

Start the frontend:

```powershell
npm run dev
```

Open `http://localhost:3000`. The root route redirects to login. The primary mobile route is `http://localhost:3000/dashboard/today`.

### 5. Optional AI Coach

```powershell
ollama pull phi3
ollama serve
```

Confirm Ollama is available at `http://localhost:11434/api/tags` before using chat.

The coach is database-aware and English-only. It calculates 30/90-day completion
patterns, category/hour/weekday performance, interruption and duration patterns,
and upcoming schedule conflicts on the backend. Ollama interprets the user's intent
and explains those server-calculated facts; it never writes directly to the database.

Planning requests return up to three ranked, conflict-free time options. A task is
created only after the authenticated user selects an option and confirms the proposal.
Conversations and unexpired proposals are restored after a page refresh. Users can
also save scheduling preferences in chat, for example: `Remember that I prefer to
plan between 9 AM and 6 PM with a 20-minute buffer.`

## Running the stack

Use separate terminals:

```powershell
# Terminal 1
cd backend
uvicorn app.main:app --reload --port 8000

# Terminal 2
cd habittrace_frontend_dev-main
npm run dev

# Optional Terminal 3
ollama serve
```

Do not run `next build` while `next dev` is using the same working tree. On OneDrive, simultaneous cache writes can corrupt `.next/dev`. If the development server reports a missing `build-manifest.json`, stop all frontend dev/build processes, remove only `habittrace_frontend_dev-main/.next`, and restart `npm run dev`. Keeping active development work outside a synchronized folder is the most reliable option.

## Mobile PWA installation

For local functional testing, use `/dashboard/today`. Production installation requires HTTPS.

- Android Chrome: open the HTTPS site and choose **Install app** or **Add to Home screen**.
- iPhone Safari: open the HTTPS site, choose **Share**, then **Add to Home Screen**.

The installed app starts at `/dashboard/today`. Authentication persists through the Supabase browser session. Sign-out is available from the `HT` account button.

## Core API

All routes below except `/health` require a valid Supabase bearer token.

| Method | Endpoint | Purpose |
|---|---|---|
| `GET` | `/health` | Report primary DB, AI DB, Auth, and model readiness |
| `GET` | `/tasks?date=YYYY-MM-DD` | List the signed-in user's tasks, optionally by date |
| `POST` | `/tasks` | Create an owned task |
| `GET` | `/tasks/{task_id}` | Read an owned task |
| `PATCH` | `/tasks/{task_id}` | Update an owned task |
| `DELETE` | `/tasks/{task_id}` | Delete an owned task |
| `GET` | `/executions?active=true` | List active executions |
| `POST` | `/executions/start` | Start a task idempotently using server time |
| `PATCH` | `/executions/{execution_id}/complete` | Complete an execution and synchronize task status |
| `POST` | `/executions` | Record a completed legacy execution |
| `POST` | `/predict` | Run the V1 prediction model |
| `GET` | `/analytics/summary?period=week` | Read aggregated analytics |
| `GET` | `/analytics/plan-health` | Read today's plan health and risks |
| `POST` | `/chat` | Stream AI Coach events over SSE |

AI V2 routes use the `/api/v2/ai` prefix and cover immutable plan snapshots, one outcome per snapshot, confirmed failure reasons, persisted predictions, and ranked time recommendations. See the OpenAPI page for complete request and response contracts.

## Validation

Frontend:

```powershell
cd habittrace_frontend_dev-main
npx tsc --noEmit
npm run lint
npm run build
```

Backend:

```powershell
cd backend
python -m pytest -q
python -m ruff check app tests
```

AI V2:

```powershell
cd habittrace_ai_v2
python -m pytest -q
python -m ruff check src tests
python -m mypy src
```

The V1 model package does not currently include an automated test suite; validate changes with its CLI train, evaluate, and predict commands.

## Component documentation

- `habittrace_frontend_dev-main/README.md`: frontend routes, PWA behavior, scripts, and deployment
- `habittrace_model_dev-main/README.md`: V1 model data contract and CLI
- `habittrace_model_dev-main/README 2.md`: V1 model design and compatibility notes
- `habittrace_ai_v2/README.md`: AI V2 dataset, leakage controls, export, training, and artifacts
- `habittrace_ai_v2/fixtures/README.md`: synthetic fixture policy
- `supabase/README.md`: database schema responsibilities and deployment order

동주 그는 고트예요
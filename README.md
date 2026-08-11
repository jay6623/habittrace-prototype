# HabitTrace

A habit-tracking + ML prediction system. Users log planned tasks; the backend runs a trained scikit-learn model to predict task success probability and the most likely failure reason. An AI Coach (powered by Phi-3 Mini via Ollama) lets users chat about their habits and add tasks via natural language.

---

## Architecture

```
habittrace_combine/
├── habittrace_frontend_dev-main/   # Next.js 16 + TypeScript + Tailwind
├── habittrace_model_dev-main/      # Python ML pipeline + trained artifacts
├── backend/                        # FastAPI backend (wraps ML + Supabase)
└── supabase/schema.sql             # Database schema
```

**Data flow:**

```
Browser (Next.js)
  ↓  REST API calls
FastAPI backend (port 8000)
  ├──→ Supabase (auth + database)
  ├──→ ML model (scikit-learn, .joblib artifacts)
  └──→ Ollama / Phi-3 Mini (local LLM for AI Coach)
```

---

## Prerequisites

Install the following before running the project:

| Tool | Purpose | Install |
|------|---------|---------|
| **Node.js 18+** | Frontend | [nodejs.org](https://nodejs.org) |
| **Python 3.10+** | Backend | [python.org](https://python.org) |
| **Ollama** | Local LLM (AI Coach) | [ollama.com/download](https://ollama.com/download) or `brew install ollama` |

---

## Setup

### 1. Supabase

1. Create a free project at [supabase.com](https://supabase.com)
2. Open **SQL Editor** → paste and run `supabase/schema.sql`
3. Go to **Settings → API** and copy:
   - **Project URL**
   - **anon/public key** (for the frontend)
   - **service_role key** (for the backend — keep secret)
4. (Optional) Enable Google OAuth in **Authentication → Providers**

For AI V2, run `supabase/ai_schema.sql` in the separate AI Supabase project.
That schema enables RLS on all AI tables without browser policies; only the
FastAPI service-role client can access them. Do not put the AI service-role key
in the frontend project.

---

### 2. Backend

```bash
cd backend

# Install dependencies (with conda active, no venv needed)
pip install -r requirements.txt

# Copy and fill in environment variables
cp .env.example .env
# Edit .env — add your Supabase URL and keys
```

**Required `.env` variables:**

| Variable | Where to find |
|---|---|
| `SUPABASE_URL` | Supabase → Settings → API → Project URL |
| `SUPABASE_SERVICE_KEY` | Supabase → Settings → API → service_role (secret) |
| `SUPABASE_ANON_KEY` | Supabase → Settings → API → anon public |
| `AI_SUPABASE_URL` | AI V2 Supabase project URL (backend only) |
| `AI_SUPABASE_SERVICE_ROLE_KEY` | AI V2 service_role key (backend only; never `NEXT_PUBLIC_`) |
| `AUTH_SUPABASE_URL` | Optional token-issuer project URL; defaults to `SUPABASE_URL` |
| `AUTH_SUPABASE_ANON_KEY` | Optional token-issuer anon key; defaults to `SUPABASE_ANON_KEY` |
| `FRONTEND_URL` | Browser origin for your Next.js app (local: `http://localhost:3000`; production: `https://your-app.example.com`) |
| `CORS_ORIGINS` | Optional. Comma-separated allowed origins when you do not want the default list. When set, only these origins are allowed (no automatic `localhost`). |
| `TRUST_FORWARDED_HEADERS` | Set to `true` behind nginx/Caddy/a load balancer so HTTPS and client IP are correct. |
| `PROXY_TRUSTED_HOSTS` | Who may send `X-Forwarded-*` (often `*` on managed hosts). |
| `API_ROOT_PATH` | If the API is mounted under a sub-path (e.g. `/api`), set it here. |

**Start the backend:**

```bash
uvicorn app.main:app --reload --port 8000
```

**Verify it's running:**

```bash
curl http://localhost:8000/health
# Includes V1 DB, AI V2 DB, Auth, and legacy ML readiness flags.
```

> The ML artifacts are loaded automatically from `../habittrace_model_dev-main/artifacts/`. No extra setup needed.

---

### 3. Frontend

```bash
cd habittrace_frontend_dev-main

# Install dependencies
npm install

# Copy and fill in environment variables
cp .env.local.example .env.local
# Edit .env.local with your Supabase keys and backend URL
```

**Required `.env.local` variables:**

| Variable | Value |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase Project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase anon/public key |
| `NEXT_PUBLIC_API_URL` | API base URL (`http://localhost:8000` locally; production: `https://api.example.com`, no trailing slash) |
| `NEXT_PUBLIC_SITE_URL` | Optional. Canonical site origin for OAuth redirects; must match Supabase redirect allowlist. |

**Start the frontend:**

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

---

### 4. AI Coach (Ollama + Phi-3 Mini)

The AI Coach uses Phi-3 Mini running locally via Ollama. Required only for the chat feature.

**Install Ollama:**

```bash
# macOS
brew install ollama

# Or download from https://ollama.com/download
```

**Accept Xcode license if prompted (macOS):**

```bash
sudo xcodebuild -license accept
```

**Download the Phi-3 Mini model (~2.3 GB, one-time):**

```bash
ollama pull phi3
```

**Start Ollama (run this before starting the backend):**

```bash
ollama serve
```

> If you installed the Ollama desktop app, you can also start it from the menu bar instead.

**Verify Ollama is running:**

```bash
curl http://localhost:11434/api/tags
# Should list phi3 in the models
```

---

## Running the Full Stack

Open **3 terminal windows** and run one command in each:

```bash
# Terminal 1 — Ollama (AI Coach)
ollama serve

# Terminal 2 — Backend
cd ~/Desktop/habitTrace_combine/backend
uvicorn app.main:app --reload --port 8000

# Terminal 3 — Frontend
cd ~/Desktop/habitTrace_combine/habittrace_frontend_dev-main
npm run dev
```

Then open [http://localhost:3000](http://localhost:3000).

---

## Production (domain, HTTPS, API URL)

Deploy the Next.js app and FastAPI service on your host(s), both reachable over **HTTPS** so the browser can call the API without mixed-content blocking.

**Frontend**

- Set **`NEXT_PUBLIC_API_URL`** to your deployed API origin (for example `https://api.example.com`). The client strips a trailing slash automatically.
- Set **`NEXT_PUBLIC_SITE_URL`** if the canonical URL must match **Supabase → Authentication → URL Configuration** exactly (for example preview vs production domains). OAuth `redirectTo` values use this when set, otherwise the current browser origin.
- Run `npm run build` and `npm start`, or use your platform’s Next.js integration.

**Backend**

- Set **`FRONTEND_URL`** to your live Next.js origin, or set **`CORS_ORIGINS`** to a comma-separated list of allowed `Origin` values (scheme + host, no path). If `CORS_ORIGINS` is set, it replaces the default list (localhost is not added automatically).
- Enable **`TRUST_FORWARDED_HEADERS=true`** when a reverse proxy terminates TLS. Set **`PROXY_TRUSTED_HOSTS`** appropriately (`*` is common on PaaS where only the platform proxy connects to your process).
- If the API is exposed under a path prefix (for example `https://example.com/api`), set **`API_ROOT_PATH`** (for example `/api`).
- For Ollama behind another host, set **`OLLAMA_CHAT_URL`** and **`OLLAMA_MODEL`** in `backend/.env`.

**Supabase (redirects and callbacks)**

- **Site URL**: your production app origin (for example `https://app.example.com`).
- **Redirect URLs**: include the origins and paths used after Google OAuth (for example `https://app.example.com/**`, plus `/dashboard` and `/onboarding/profile` if you list paths explicitly).

**Interactive API docs**

Use `https://<your-api-host>/docs` in production (same paths as local OpenAPI).

---

## Features

| Feature | Description |
|---------|-------------|
| **Habits** | Add, edit, and track daily tasks with a structured time picker and date navigation |
| **ML Prediction** | Per-task success probability and failure reason from a trained scikit-learn model |
| **Calendar** | Monthly/weekly view of all tasks color-coded by status |
| **Scheduler** | Day timeline with energy/focus sliders and ML predictions |
| **Schedule Checker** | Sidebar showing today's plan health and risk analysis |
| **AI Coach Chat** | Chat with Phi-3 Mini about your habits; type naturally to add tasks (e.g. "I'll study at 9pm tomorrow") |
| **Analytics** | Execution trend charts, failure pattern breakdown, weekly summary |
| **Settings** | Profile editing, notification preferences, data export |

---

## API Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Server + ML + DB status |
| `GET` | `/tasks?date=YYYY-MM-DD` | List tasks for a date |
| `POST` | `/tasks` | Create a new task |
| `PATCH` | `/tasks/{id}` | Update a task |
| `DELETE` | `/tasks/{id}` | Delete a task |
| `POST` | `/predict` | Run ML prediction for a task |
| `GET` | `/analytics/summary?period=week` | Aggregated analytics |
| `GET` | `/analytics/plan-health` | Today's plan health + risks |
| `POST` | `/chat` | AI Coach chat (SSE streaming) |
| `POST` | `/api/v2/ai/plans` | Create an immutable AI plan snapshot or revision (`parent_plan_input_id` + `reschedule`) |
| `GET` | `/api/v2/ai/plans/{plan_input_id}` | Read an owned AI plan snapshot |
| `POST` | `/api/v2/ai/plans/{plan_input_id}/outcome` | Record the plan's single outcome |
| `POST` | `/api/v2/ai/outcomes/{outcome_id}/failure-reasons` | Store user-confirmed failure reasons |
| `GET` | `/api/v2/ai/failure-reasons` | List active failure-reason definitions |
| `GET` | `/api/v2/ai/plans/{plan_input_id}/prediction` | Read the latest persisted prediction without creating a new one |
| `POST` | `/api/v2/ai/predict` | Run the AI V2 success/failure baseline (development artifact) |
| `POST` | `/api/v2/ai/plans/{plan_input_id}/predict` | Run and persist an AI V2 prediction for an owned plan |
| `POST` | `/api/v2/ai/plans/{plan_input_id}/time-recommendations` | Generate conflict-free time candidates scored by success probability |
| `GET` | `/api/v2/ai/time-recommendations/{recommendation_id}` | Read an owned time recommendation |
| `POST` | `/api/v2/ai/time-recommendations/{recommendation_id}/select` | Save the user's selected time candidate |

Local interactive docs: [http://localhost:8000/docs](http://localhost:8000/docs) — in production, use `https://<your-api-host>/docs`.

---

## ML Model Notes

- **Model 1** (`success_model.joblib`): Logistic Regression — predicts P(task completed)
- **Model 2** (`failure_model.joblib`): Multinomial LR — predicts the most likely failure reason (7 classes)
- **Features**: 32 engineered features from planned task data (category, time-of-day, duration, energy, focus, interaction terms)
- **Personalization**: Per-user sigmoid calibration via `calib_params.json` — activates after 30+ tasks logged
- Both models are loaded once at backend startup for fast inference

To retrain:

```bash
cd habittrace_model_dev-main
python -m ml.cli train --csv plan_execution_train_set.csv
```

The model and CSV files above are V1 legacy assets. New AI-only experiments live
in `habittrace_ai_v2/`; they do not connect to Supabase or load service-role
credentials. Its leakage, temporal-split, baseline-model, and artifact tests run
with:

```bash
cd habittrace_ai_v2
python -m pytest -q
python -m ruff check src tests
python -m mypy src
```

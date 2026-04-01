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
| `FRONTEND_URL` | `http://localhost:3000` |

**Start the backend:**

```bash
uvicorn app.main:app --reload --port 8000
```

**Verify it's running:**

```bash
curl http://localhost:8000/health
# → {"status":"ok","ml_models_loaded":true,"supabase_configured":true}
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
| `NEXT_PUBLIC_API_URL` | `http://localhost:8000` |

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

Full interactive docs: [http://localhost:8000/docs](http://localhost:8000/docs)

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

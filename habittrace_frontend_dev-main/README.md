# HabitTrace Frontend

This directory contains the HabitTrace web application and installable mobile PWA.

## Stack

- Next.js 16.1 with the App Router
- React 19
- TypeScript with strict mode
- Tailwind CSS 4
- Supabase Auth in the browser
- Chart.js for desktop analytics
- A dependency-free Service Worker for offline navigation fallback

## Product split

The same Next.js project serves two focused experiences.

### Desktop

Desktop routes retain the full planning and analysis tools:

| Route | Purpose |
|---|---|
| `/dashboard` | Dashboard overview |
| `/dashboard/habits` | Task management and prediction |
| `/dashboard/calendar` | Desktop month/week calendar |
| `/dashboard/scheduler` | Timeline scheduling and recommendations |
| `/dashboard/analytics` | Trends and failure-pattern analytics |
| `/dashboard/integrations` | Google Calendar connection and manual synchronization |
| `/dashboard/group` | Group scheduling: create or join a group by invite code, shared tasks, assignment, and status updates |
| `/dashboard/settings` | Full settings and account controls |

### Mobile PWA

Mobile routes use a lightweight shell without the desktop sidebar, charts, or schedule checker:

| Route | Purpose |
|---|---|
| `/dashboard/today` | Active/next plan, Quick Add, start, and outcome logging |
| `/dashboard/today/calendar` | Month calendar, selected-day agenda, and date-prefilled Quick Add |
| `/dashboard/today/account` | Display name, email, password reset, and sign-out |

The bottom navigation contains only **Today** and **Calendar**. Quick Add remains prominent inside the Today and Calendar screens. The `HT` button opens mobile account management.

## Authentication and data ownership

`app/providers.tsx` restores and observes the Supabase browser session. `lib/api.ts` attaches the current access token to API requests as `Authorization: Bearer <token>`.

Unauthenticated dashboard routes redirect to `/login?next=<original-route>`. After login, the app returns to that safe internal dashboard route. A direct mobile or installed-PWA login defaults to `/dashboard/today`; a direct desktop login defaults to `/dashboard`.

The display name shown on Today is resolved in this order:

1. `user.user_metadata.first_name`
2. The part of the email address before `@`
3. `there`

The display name is not a database ownership key. The backend derives ownership from the verified Supabase user UUID.

## Environment

Create `.env.local` in this directory. It is intentionally ignored by Git.

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-public-key
NEXT_PUBLIC_API_URL=http://localhost:8000
# Optional canonical production origin for OAuth:
# NEXT_PUBLIC_SITE_URL=https://app.example.com
```

Never place a Supabase service-role key in a `NEXT_PUBLIC_` variable or browser code.

`NEXT_PUBLIC_API_URL` defaults to `http://localhost:8000` when omitted. A production browser and API must both use HTTPS to avoid mixed-content blocking.

## Development

Node.js 20.9 or newer is required by Next.js 16.

```powershell
npm install
npm run dev
```

Open `http://localhost:3000`. The root route redirects to `/login`.

The AI Coach requires the backend coach migration at
`../supabase/coach_agent_schema.sql` plus a running Ollama instance. Chat responses,
pending plan proposals, and user scheduling preferences are persisted by the backend;
task creation always requires an explicit confirmation in the coach UI.

Available scripts:

| Command | Purpose |
|---|---|
| `npm run dev` | Start the development server |
| `npm run build` | Create a production build |
| `npm start` | Serve an existing production build |
| `npm run lint` | Run ESLint |

TypeScript can be checked independently:

```powershell
npx tsc --noEmit
```

## Mobile task flow

```text
Sign in → Today → Quick Add → Start → Finish → Select outcome
```

Quick Add creates the existing backend `TaskCreate` shape. Category, importance, energy, and focus receive explicit defaults unless the user opens More options. Mobile outcome choices map safely to the existing data model:

| Mobile choice | V1 task/execution status | AI V2 outcome |
|---|---|---|
| Completed | `success` | `completed` |
| Partially done | `failed` with `stopped_early=true` | `partial` |
| Not completed | `failed` | `abandoned` |
| Still in progress | Open execution and pending task | No final outcome yet |

Partial and failed outcomes use canonical failure-reason codes from `lib/mobile-task.ts`. The UI labels remain separate from the stored codes.

## PWA implementation

- `app/manifest.ts`: app identity, standalone start URL, icons, and Quick Add shortcut
- `components/pwa/service-worker-registration.tsx`: Service Worker registration
- `public/sw.js`: network-first navigation and offline fallback
- `public/offline.html`: English offline screen
- `public/icons/`: 180, 192, 512, and maskable icons

The Service Worker deliberately does not cache authenticated HTML, API responses, or private plan data. Offline navigation displays the fallback page, but creating or updating plans requires a network connection.

Push notifications are not implemented. Adding them requires permission UX, Push API subscriptions, a user-owned subscription table, server-side scheduling and delivery, and `push`/`notificationclick` Service Worker handlers.

## Install testing

For a production-like local check:

```powershell
npm run build
npm start
```

Check:

- `/manifest.webmanifest`
- `/sw.js`
- `/offline.html`
- `/dashboard/today`

Real phone installation requires HTTPS:

- Android Chrome: **Install app** or **Add to Home screen**
- iPhone Safari: **Share** → **Add to Home Screen**

## Development cache troubleshooting

Do not run `npm run build` while `npm run dev` is active in the same working tree. Next.js writes both modes under `.next`, and overlapping operations can produce errors such as:

```text
Persisting failed: Another write batch or compaction is already active
ENOENT ... .next/dev/.../build-manifest.json
```

Recovery:

1. Stop every `next dev`, `next build`, and `next start` process for this frontend.
2. Remove only this directory's generated `.next` folder.
3. Start `npm run dev` again.

On Windows, OneDrive can hold generated files or Turbopack cache entries open. If the problem repeats, keep the active repository outside OneDrive or pause synchronization while developing. Do not delete source directories to repair a Next.js cache error.

## Validation

Run these sequentially so they do not compete for `.next/types`:

```powershell
npx tsc --noEmit
npm run lint
npm run build
```

The build may download the existing Geist fonts through `next/font`, so network access is required when the font cache is cold.

## Deployment

1. Set the public frontend environment variables on the hosting platform.
2. Set `NEXT_PUBLIC_API_URL` to the HTTPS FastAPI origin without a trailing slash.
3. Add the production origin and OAuth return paths to Supabase Auth URL Configuration.
4. Build with `npm run build` and serve with `npm start`, or use a platform's supported Next.js integration.
5. Confirm that `/sw.js` is served with `Cache-Control: no-cache, no-store, must-revalidate` and `Service-Worker-Allowed: /`.

The icons in `public/icons` are current temporary HabitTrace assets and can be replaced in place when final brand artwork is available.

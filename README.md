# parc-ferme

Motorsport prediction league web application where users can predict who wins, get poles, and etc.

Before each Grand Prix, players pick the podium (P1–P3), the pole sitter and the fastest lap. Picks lock when GP qualifying starts. After the race, the results come from the free [OpenF1 API](https://openf1.org), every player is scored (15 points at most per race), and the leaderboard updates live.

## Stack

- **Frontend:** Vue 3 + Vite + TypeScript + Vue Router, a single-page app in `app/`. Folders follow Nuxt's names (`pages/`, `layouts/`, `composables/`), so a later move to Nuxt only replaces `router.ts` and `main.ts`.
- **Backend:** Supabase.
  - Postgres holds the data, and row-level security enforces the rules (picks lock at qualifying, other players' picks stay hidden until then).
  - Two Edge Functions talk to OpenF1: `sync-calendar` and `score-races`.
  - pg_cron runs them on a schedule.
  - Auth handles sign-in with magic links (Google later), and Realtime pushes leaderboard updates.

## Docs

- [`docs/build-plan.html`](docs/build-plan.html): architecture, sign-in flow, data model, scoring rules, setup steps and open risks. Open it in a browser.
- [`design/mockups.html`](design/mockups.html) (mobile) and [`design/desktop.html`](design/desktop.html): the eight screens.

## Project layout

```
app/                          Vue app (Nuxt-style folders)
  pages/  layouts/  components/  composables/
  router.ts                   route list, mirrors pages/
  assets/tokens.css           design tokens from the mockups
supabase/
  config.toml                 local stack config (Auth redirects point at localhost:5173)
  migrations/                 database schema (one init migration so far)
  tests/database/             pgTAP tests for the database rules
  functions/
    sync-calendar/            meetings, sessions and entry lists from OpenF1
    score-races/              fetches results and scores players
      scoring.ts              the scoring rules, a pure function
      scoring.test.ts         Node tests for scoring.ts
docs/  design/                plan and mockups
```

## Running locally

Needs Docker (Rancher Desktop works), Node and the Supabase CLI.

```sh
npm install
mkdir -p supabase/snippets    # already in the repo; Rancher Desktop can't create Studio's mount folder
supabase start                # local Postgres, Auth, Realtime, Studio. First run downloads images.
supabase functions serve      # serves the Edge Functions; restart it after adding a new function
npm run dev                   # http://localhost:5173
```

| Local service | URL |
|---|---|
| App | http://localhost:5173 |
| Studio (tables, SQL) | http://127.0.0.1:54323 |
| Test inbox (magic-link emails) | http://127.0.0.1:54324 |
| API and Edge Functions | http://127.0.0.1:54321 |

Once the pages call Supabase, copy `.env.example` to `.env.local` and fill in the API URL and publishable key from `supabase status`. `.env.local` is gitignored.

### Calling the Edge Functions

Both functions accept only the secret API key, in an `apikey` header, because only pg_cron should call them. Locally, this reads the key without printing it:

```sh
KEY=$(supabase status -o json | python3 -c "import sys,json; print(json.load(sys.stdin)['SECRET_KEY'])")
curl -X POST http://127.0.0.1:54321/functions/v1/sync-calendar -H "apikey: $KEY" -H "content-type: application/json" -d '{}'
curl -X POST http://127.0.0.1:54321/functions/v1/score-races  -H "apikey: $KEY"
```

`sync-calendar` accepts an optional `{"from": "2025-10-02", "to": "2025-10-10"}` body to load a past weekend.

## Tests

```sh
supabase test db        # database rules: lock, entry list, pick visibility, leaderboard (13 checks)
npm run test:scoring    # scoring rules in scoring.ts (4 tests)
npm run build           # type-check and build the frontend
supabase db reset       # rebuild the local database from supabase/migrations/
```

## Progress

Items marked **(you)** are for the project owner: accounts, keys and sign-offs.

### Phase 0 · Setup ✅
- [x] Choose the stack: Vue + Vite + TypeScript + Vue Router, with Nuxt-style folders
- [x] Scaffold the app in `app/` (TypeScript pinned to 6.x)
- [x] `supabase init`, with Auth redirects pointed at `localhost:5173`
- [x] Start the local stack (the `supabase/snippets/` fix for Rancher Desktop)

### Phase 1 · Database ✅
- [x] `init` migration: tables, session-keyed drivers, entry-list foreign keys, views, RLS, new-user trigger, Realtime on `results`
- [x] 13 pgTAP tests (`supabase test db`), schema lint clean
- [x] Move scoring out of the database into `scoring.ts`, stored in a `scores` table
- [ ] Review the migration **(you)**

### Phase 2 · Calendar sync ✅
- [x] `sync-calendar`: 4 weeks of meetings, plus sessions and entry lists for meetings starting within 7 days
- [x] Treat OpenF1's 404 as "no rows yet"
- [x] Run against live OpenF1 data; the `races` view shows the right `lock_at`
- [x] Decide daily over weekly sync **(you)**
- [ ] Look at the synced data in Studio **(you)**

### Phase 3 · Scoring 🟡
- [x] Scoring rules in `scoring.ts`, 4 Node tests (`npm run test:scoring`)
- [x] `score-races`: fetch result, upsert scores, then insert the results row
- [x] Load the 2025 Singapore GP with test picks for 5 players
- [ ] Fix the fastest-lap step that hit the Edge runtime's CPU limit
- [ ] Run `score-races` end to end and compare the points with a hand calculation
- [ ] Check the points **(you)**

### Phase 4 · Scheduling
- [ ] Migration: enable `pg_cron` and `pg_net`
- [ ] Cron job for `sync-calendar`, daily at 06:00 UTC
- [ ] Cron job for `score-races`, every minute but only while `races_unscored` has rows
- [ ] Store `project_url` and `secret_key` in Vault **(you)**
- [ ] Check that the per-minute job only calls `score-races` while a race is waiting for results

### Phase 5 · Frontend
- [ ] Rename the env variable to `VITE_SUPABASE_PUBLISHABLE_KEY`; create `.env.local` **(you)**
- [ ] Sign in, create account, check email, auth callback (magic links)
- [ ] Try signing up and signing in **(you)**
- [ ] Picks screen with the lock countdown
- [ ] Driver picker
- [ ] Picks locked (everyone's picks)
- [ ] Leaderboard with live updates
- [ ] Profile
- [ ] Desktop layouts
- [ ] Click through and compare with the mockups **(you)**
- [ ] Push `feature-build` to GitHub **(you approve)**

### Phase 6 · Going live
- [ ] Create the hosted Supabase project and share the project ref **(you)**
- [ ] Google Cloud OAuth client **(you)**
- [ ] Email provider and domain DNS records (SPF, DKIM) **(you)**
- [ ] Cloudflare Turnstile keys **(you)**
- [ ] Choose frontend hosting **(you)**
- [ ] Decide on invite-only sign-up **(you)**
- [ ] Link the project, push migrations, deploy functions, set up cron jobs (each step approved by you)
- [ ] Add Google sign-in and Turnstile to the frontend
- [ ] Deploy the frontend **(you approve)**
- [ ] Sign up for real and make picks for the next race **(you)**

### Known issues and decisions

- **`score-races` hits the CPU limit.** Its fastest-lap step downloads every lap of the race, about 1,200 rows, and the local Edge runtime reported `CPU time soft limit reached`. The planned fix: fetch the winner's laps, then only laps at least as fast (`lap_duration<=…`).
- **OpenF1 answers 404 when a query has no results**, not an empty list. Both functions treat 404 as "no rows yet".
- **Entry lists are published at different times.** Picks need one, so `sync-calendar` will run daily, not weekly.
- **Drivers are keyed by `(session_key, driver_number)`** because car numbers change between seasons. Norris was #4 in 2025 and is #1 in 2026.
- **TypeScript is pinned to 6.x** because vue-tsc doesn't run on TypeScript 7 yet.
- **Scoring lives in TypeScript** (`scoring.ts`) and is stored in `scores`. The leaderboard is a view over that table.

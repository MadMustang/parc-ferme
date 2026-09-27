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

| Phase | Status |
|---|---|
| 0 · Setup | Done |
| 1 · Database schema, RLS and tests | Done |
| 2 · `sync-calendar` | Done, checked against live OpenF1 data |
| 3 · `score-races` and scoring | Scoring rules tested. The end-to-end run hit the Edge runtime's CPU limit (see below). |
| 4 · Scheduling (pg_cron, Vault) | Not started |
| 5 · Frontend screens | Not started (placeholder pages only) |
| 6 · Going live (hosted project, Google sign-in, email, Turnstile) | Not started |

### Known issues and decisions

- **`score-races` hits the CPU limit.** Its fastest-lap step downloads every lap of the race, about 1,200 rows, and the local Edge runtime reported `CPU time soft limit reached`. The planned fix: fetch the winner's laps, then only laps at least as fast (`lap_duration<=…`).
- **OpenF1 answers 404 when a query has no results**, not an empty list. Both functions treat 404 as "no rows yet".
- **Entry lists are published at different times.** Picks need one, so `sync-calendar` will run daily, not weekly.
- **Drivers are keyed by `(session_key, driver_number)`** because car numbers change between seasons. Norris was #4 in 2025 and is #1 in 2026.
- **TypeScript is pinned to 6.x** because vue-tsc doesn't run on TypeScript 7 yet.
- **Scoring lives in TypeScript** (`scoring.ts`) and is stored in `scores`. The leaderboard is a view over that table.

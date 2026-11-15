# parc-ferme

Motorsport prediction league web application where users can predict who wins, get poles, and etc.

Before each Grand Prix, players pick the podium (P1–P3) and the pole sitter. On a sprint weekend they make a second set of picks for the Sprint. Picks lock when that race's own qualifying starts. After the race, the results come from the free [OpenF1 API](https://openf1.org), every player is scored (13 points at most for a Grand Prix, 8 for a Sprint), and the season's leaderboard updates live.

## Stack

- **Frontend:** Vue 3 + Vite + TypeScript + Vue Router, a single-page app in `app/`. Folders follow Nuxt's names (`pages/`, `layouts/`, `composables/`), so a later move to Nuxt only replaces `router.ts` and `main.ts`.
- **Backend:** Supabase.
  - Postgres holds the data, and row-level security enforces the rules (picks lock at qualifying, other players' picks stay hidden until then).
  - Two Edge Functions do the server work: `sync-calendar` and `score-races`.
  - pg_cron runs them on a schedule.
  - Auth handles sign-in with magic links (Google later), and Realtime pushes leaderboard updates.

### Moving off Supabase later

The backend is split so that each Supabase part can be replaced on its own:

- **The jobs don't know Supabase.** Each function is a `core.ts` with the logic and a short `index.ts` that makes it an Edge Function. A Node server with a scheduler can call the same `core.ts`.
- **One file talks to OpenF1** (`_shared/openf1.ts`). Another data source is another file with the same four functions.
- **One file talks to the database** (`_shared/db.ts`). The `Db` type lists the seven things the jobs need, and `supabaseDb` provides them. Another host needs a second function that returns a `Db`.
- **The schema is plain Postgres** (`…_schema.sql`). Auth, the row-level security policies and Realtime are in a second migration (`…_supabase.sql`).
- **Pages will reach the backend only through composables** (Phase 5), so the frontend has one place to change too.

Supabase itself is open source and can be self-hosted with Docker, which needs no code changes at all.

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
  migrations/
    …_schema.sql              tables and views, plain Postgres
    …_supabase.sql            Auth link, row-level security policies, Realtime
  tests/database/             pgTAP tests for the database rules
  functions/
    _shared/
      openf1.ts               the only file that calls OpenF1
      db.ts                   the only file that calls the database
    sync-calendar/            meetings, sessions and entry lists
      core.ts                 the job
      index.ts                Edge Function entry
    score-races/              fetches results and scores players
      core.ts                 the job
      index.ts                Edge Function entry
      scoring.ts              the scoring rules, a pure function
    **/*.test.ts              Node tests
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
supabase test db        # database rules: lock, sprints, seasons, entry list, pick visibility (19 checks)
npm run test:functions  # scoring rules, the OpenF1 reader and the scoring job (11 tests)
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
- [x] Sprints: the `races` view lists each Grand Prix and each Sprint, with its own lock
- [x] Seasons: the `leaderboard` view has one table per year, with rank, previous rank and last-weekend points
- [x] Cancelled sessions are stored and left out of `races`
- [x] Split the migration into plain Postgres (`…_schema.sql`) and Supabase-only (`…_supabase.sql`)
- [ ] Run `supabase test db` on the real local stack (checked so far in an embedded Postgres, with stand-ins for Auth and pgTAP)
- [ ] Review the migrations **(you)**

### Phase 2 · Calendar sync ✅
- [x] `sync-calendar`: 4 weeks of meetings, plus sessions and entry lists for meetings starting within 7 days
- [x] Treat OpenF1's 404 as "no rows yet"
- [x] Run against live OpenF1 data; the `races` view shows the right `lock_at`
- [x] Decide daily over weekly sync **(you)**
- [ ] Look at the synced data in Studio **(you)**

### Phase 3 · Scoring 🟡
- [x] Scoring rules in `scoring.ts`: 13 points for a Grand Prix, 8 for a Sprint
- [x] `score-races`: fetch result, upsert scores, then insert the results row
- [x] Load the 2025 Singapore GP with test picks for 5 players
- [x] Drop the fastest-lap pick, which also removes the step that hit the Edge runtime's CPU limit
- [x] Split both functions into `core.ts` and `index.ts`, with OpenF1 and the database behind `_shared/`
- [x] Run both jobs against live OpenF1 for the 2026 Singapore sprint weekend (in-memory database) and compare the points with a hand calculation
- [ ] Run `score-races` end to end on the local stack
- [ ] Check the points **(you)**

### Phase 4 · Scheduling
- [ ] Migration: enable `pg_cron` and `pg_net`
- [ ] Cron job for `sync-calendar`, twice a day (OpenF1's free tier is closed around live sessions, so a single daily run can fail)
- [ ] Cron job for `score-races`, every minute but only while `races_unscored` has rows
- [ ] Store `project_url` and `secret_key` in Vault **(you)**
- [ ] Check that the per-minute job only calls `score-races` while a race is waiting for results

### Phase 5 · Frontend
- [ ] Rename the env variable to `VITE_SUPABASE_PUBLISHABLE_KEY`; create `.env.local` **(you)**
- [ ] Composables for the backend (`useAuth`, `usePicks`, `useLeaderboard`); pages never import `supabase-js`
- [ ] Sign in, create account, check email, auth callback (magic links)
- [ ] Try signing up and signing in **(you)**
- [ ] Picks screen with the lock countdown, counted from the server's time
- [ ] Grand Prix / Sprint switch on sprint weekends
- [ ] Driver picker
- [ ] Picks locked (everyone's picks)
- [ ] Results screen: your picks against the result, with the points per pick (needs a mockup first)
- [ ] Leaderboard with live updates and a season switch
- [ ] Error state for a failed save, a form error and an expired link (needs a design rule first)
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

### Later

- **Fastest-lap pick.** Dropped from the first version. To bring it back: add a `fastest_lap` column to `predictions` and `results`, a bonus in `scoring.ts`, and a lookup in `openf1.ts`. Don't download every lap of the race: that is about 1,400 rows, and it hit the Edge runtime's CPU limit. Fetch the winner's laps, then only laps at least as fast (`/laps?session_key=…&lap_duration<=…`, 3 rows in a test).
- **Rescoring after a penalty.** A result is scored once. If a post-race penalty changes the podium, delete the `results` row within 2 days and the next run rescores the race. An automatic second check about a day later would remove this manual step.
- **Private leagues.** There is one leaderboard per season for everyone.

### Known issues and decisions

- **A Sprint scores about half a Grand Prix.** The podium point stays at 1 and the bonuses are halved: 8 points at most against 13.
- **Sprint picks lock at Sprint Qualifying, Grand Prix picks at Qualifying.** A Sprint's pole is the fastest driver in Sprint Qualifying.
- **OpenF1's free tier is closed around live sessions**, from about 30 minutes before to 30 minutes after. Results can't arrive sooner than that, and a calendar sync that lands in that window fails.
- **The display name never falls back to the email.** A new user without a name is called "Player".
- **OpenF1 answers 404 when a query has no results**, not an empty list. Both functions treat 404 as "no rows yet".
- **Entry lists are published at different times.** Picks need one, so `sync-calendar` will run twice a day, not weekly.
- **Drivers are keyed by `(session_key, driver_number)`** because car numbers change between seasons. Norris was #4 in 2025 and is #1 in 2026.
- **TypeScript is pinned to 6.x** because vue-tsc doesn't run on TypeScript 7 yet.
- **Scoring lives in TypeScript** (`scoring.ts`) and is stored in `scores`. The leaderboard is a view over that table, grouped by season.

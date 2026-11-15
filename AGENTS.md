# AGENTS.md

Guidelines for anyone, human or AI agent, who changes this repository. Read this file first.
[`README.md`](README.md) has the setup steps and the progress checklist. [`DESIGN.md`](DESIGN.md) has the visual rules.

## What this is

Parc Fermé is a Formula 1 prediction league. Before each Grand Prix, and each Sprint, players pick the podium (P1–P3) and the pole sitter. Picks lock when that race's own qualifying starts. After the race, results come from the free OpenF1 API, every player is scored, and the season's leaderboard updates. No money is involved.

- **Frontend:** Vue 3, Vite, TypeScript and Vue Router, in `app/`.
- **Backend:** Supabase: Postgres, Auth, Realtime, and two Edge Functions run by pg_cron.
- **Data source:** [OpenF1](https://openf1.org), free tier, non-commercial licence.

## Commands

```sh
npm run dev               # frontend at http://localhost:5173
npm run build             # type-check (vue-tsc) and build the frontend
npm run test:functions    # Node tests for scoring, the OpenF1 reader and the jobs
supabase start            # local Postgres, Auth, Realtime, Studio (needs Docker)
supabase db reset         # rebuild the local database from supabase/migrations/
supabase test db          # pgTAP tests for the database rules
supabase functions serve  # serve the Edge Functions locally
```

Before you call a change done, run the tests for what you touched: `npm run test:functions` for anything in `supabase/functions/`, `supabase test db` for anything in `supabase/migrations/`, and `npm run build` for anything in `app/`. If you could not run one, say so.

## Architecture

The backend must stay easy to move off Supabase, to a self-hosted server that is not serverless. Every Supabase part sits behind one seam. Keep each seam closed.

| Seam | The only file that may cross it | Rule |
|---|---|---|
| OpenF1 | `supabase/functions/_shared/openf1.ts` | No other file calls OpenF1 or knows its URLs and field quirks. |
| Database, from the jobs | `supabase/functions/_shared/db.ts` | Jobs use the `Db` type. Only `supabaseDb` in this file touches the Supabase client. |
| Edge runtime | `supabase/functions/*/index.ts` | Only `index.ts` imports Deno or `@supabase/*`. It parses the request and calls `core.ts`. |
| Supabase in the database | `supabase/migrations/*_supabase.sql` | Auth, row-level security policies and Realtime go here. |
| Backend, from the browser | `app/composables/` | Pages and components never import `@supabase/supabase-js`. |

Rules that follow from this:

- **A job is a `core.ts`.** It takes a `Db` and an F1 provider as arguments and returns a plain object. It has no Deno or Supabase imports, so a Node server with a scheduler can run it unchanged, and a test can pass in fakes.
- **A new database call from a job** is a new method on `Db`, implemented in `supabaseDb`.
- **A new value from OpenF1** is a new or changed function in `openf1.ts`, which returns rows shaped like our tables.
- **The schema migration is plain Postgres.** It must run on any Postgres 15+ with no `auth` schema, no Supabase roles and no extensions.
- **The browser never calls OpenF1.** It reads what the jobs stored in Postgres.
- **Scoring is a pure function** in `supabase/functions/score-races/scoring.ts`. Changing the points is a code change there, not a migration.

Do not add a layer the table above does not list. In particular, do not add an API server, a repository class per table, or a wrapper around the Supabase client in the browser beyond the composables.

## Database

- **Rules that must hold live in the database**, not only in the client: the pick lock, the entry-list foreign keys, one driver per podium place, and who can read whose picks. A modified client must not be able to break them.
- **`races` is the one definition of a race.** It lists each Grand Prix (`kind = 'race'`) and each Sprint (`kind = 'sprint'`) with its `lock_at`. Policies, jobs and the app all read the lock from this view. Do not work out a lock time anywhere else.
- **Views use `security_invoker = on`**, so they follow the same row-level security as the tables.
- **Players write only `predictions` and their own `profiles` row.** Everything else is written by the jobs with the service role and has no write policy.
- **Seasons are `meetings.year`.** Anything that sums or ranks scores groups by year.
- **Drivers are keyed by `(session_key, driver_number)`.** Car numbers change between seasons, so never key a driver by number alone.
- **A results row is the "race is done" signal.** The job writes scores first and the result last. Keep that order.
- **Never show an email.** Display names are visible to every player, so nothing derived from an email may become one.
- **Migrations:** there is no hosted database yet, so the two existing migrations are edited in place and applied with `supabase db reset`. Once a hosted project exists, add a new migration file for every change and never edit an applied one.
- **Every database rule has a pgTAP test** in `supabase/tests/database/`. A changed rule needs a changed or new test.

## Code

- **TypeScript is strict**, with `noUncheckedIndexedAccess`. Do not use `any` to get past the compiler.
- **Write the least code that fully solves the task.** Use what the codebase, the platform and the installed packages already provide before you add anything. Do not add a dependency for a few lines of code.
- **No speculative options, abstractions or configuration.** Add them when a second real use appears.
- **Errors from the database or OpenF1 are thrown, not swallowed.** A failed job run is retried by the next cron run, so a job must be safe to run twice. Use upserts, and write the "done" signal last.
- **OpenF1 answers 404 when nothing matches**, not an empty list. Treat 404 as "no rows yet". Any other error status is a real error.
- **Comments say why, not what.** One line, and only where the code cannot show the reason. Do not delete or shorten an existing comment that you were not asked to change.
- **Mark a known shortcut** with a comment in this form: `shortcut: <the limit>, <when to upgrade>`.
- **Tests:** new logic with a branch or a loop gets a test. Tests run with plain `node --test`, with no test framework. Replace OpenF1 with canned answers and the database with a small fake object, as the existing tests do. No test may call the real OpenF1.
- **Secrets:** only the publishable key goes to the browser, through `VITE_` variables in `.env.local`. The secret key stays on the server. Never commit either.
- **Files in `app/` follow Nuxt's folder names** (`pages/`, `layouts/`, `composables/`, `components/`), and `router.ts` mirrors `pages/` path for path.

## Frontend and design

[`DESIGN.md`](DESIGN.md) is the rule book and the mockups in `design/` are the source of truth. When they disagree, the mockups win, and `DESIGN.md` is updated afterwards. The owner wants the current design kept: do not restyle, and do not add a visual element the mockups do not have without asking.

The rules most often broken:

- **Use the tokens in `app/assets/tokens.css`.** Do not write hex values in components.
- **Colour always means something.** Purple is the best of the weekend, green is open or gained, yellow is locked, red is a position lost. Never use them as decoration. Active and selected states use `--ink`, not a colour.
- **Numbers are always in `--mono`.** Small labels are mono, uppercase and tracked.
- **Team colours come from the stored `team_colour`.** Do not hard-code them.
- **Disabled items are dimmed, not hidden.**
- **Picks save on selection.** There is no save button.
- **Times and countdowns come from the server's time**, because the database decides whether a pick is still allowed.
- **Accessibility is not optional.** Use real buttons, links and `<dialog>`. Every control works from the keyboard and has a visible focus mark. Meaning is never carried by colour alone.
- **Layouts work at 375 px and at 1280 px**, the two sizes of the mockups.

Some states are not designed yet. They are listed under "Not decided yet" in `DESIGN.md`. Ask before you invent one.

## Domain rules

- **Scoring:** 1 point for each picked driver who finishes on the podium, in any position. A Grand Prix adds +4 for the exact P1, +2 for the exact P2, +2 for the exact P3 and 2 for pole, which is 13 at most. A Sprint halves those bonuses, which is 8 at most.
- **Locks:** Grand Prix picks lock when Qualifying starts. Sprint picks lock when Sprint Qualifying starts.
- **Pole** is the fastest driver in that race's qualifying session, not first place on the starting grid.
- **Picks are hidden from other players until the lock**, then visible to every signed-in player.
- **A cancelled session is not a race.** It is stored and left out of `races`.
- **OpenF1 limits:** 3 requests a second and 30 a minute. The free tier is closed from about 30 minutes before a live session to 30 minutes after it.

## Working in this repository

- **Ask before you commit, push, create a branch or change a hosted service.** The owner approves each of these.
- **Stay inside the task.** Do not refactor, rename or reformat code that the task does not touch.
- **Keep the docs true.** A change to behaviour, scoring, the schema or a command also updates `README.md`, `docs/build-plan.html`, and `DESIGN.md` or the mockups when it is visual. Tick the progress checklist in `README.md`.
- **Report what you did not verify.** If Docker or the Supabase CLI is missing, say which checks were not run.
- **Items marked "(you)" in the README belong to the owner**: accounts, keys and sign-offs. Do not do them.

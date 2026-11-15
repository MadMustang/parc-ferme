-- Parc Fermé: calendar from OpenF1, players' picks, and scoring.
-- This file is plain Postgres and runs on any Postgres 15+. Everything that needs Supabase
-- (Auth, row-level security policies, Realtime) is in the next migration.
-- Written by the server jobs: meetings, sessions, drivers, scores, results.
-- Written by players: predictions (own rows, before the lock) and profiles (own display name).

-- ---------------------------------------------------------------------------
-- Calendar, stored as OpenF1 returns it
-- ---------------------------------------------------------------------------

create table public.meetings (
  meeting_key        int primary key,
  meeting_name       text not null,
  circuit_short_name text,
  country_name       text,
  year               int not null,  -- the season
  date_start         timestamptz not null
);

create table public.sessions (
  session_key  int primary key,
  meeting_key  int not null references public.meetings on delete cascade,
  session_name text not null,  -- 'Practice 1', 'Sprint Qualifying', 'Sprint', 'Qualifying', 'Race'
  date_start   timestamptz not null,
  date_end     timestamptz not null,
  is_cancelled boolean not null default false
);
create index sessions_meeting_key_idx on public.sessions (meeting_key);

-- One row per driver per session: car numbers can change between seasons.
create table public.drivers (
  session_key   int references public.sessions on delete cascade,
  driver_number int,
  name_acronym  text not null,
  full_name     text not null,
  team_name     text,
  team_colour   text,  -- hex without '#', as OpenF1 returns it
  primary key (session_key, driver_number)
);

-- ---------------------------------------------------------------------------
-- Players
-- ---------------------------------------------------------------------------

-- The id is the user's id in whatever handles sign-in.
create table public.profiles (
  id           uuid primary key,
  display_name text not null check (char_length(display_name) between 1 and 40)
);

-- A player's picks for one race: a Grand Prix or a Sprint. Every pick must be on that
-- race's entry list.
create table public.predictions (
  user_id     uuid not null references public.profiles on delete cascade,
  session_key int  not null references public.sessions on delete cascade,  -- the Race or Sprint session
  p1          int,
  p2          int,
  p3          int,
  pole        int,
  primary key (user_id, session_key),
  foreign key (session_key, p1)   references public.drivers,
  foreign key (session_key, p2)   references public.drivers,
  foreign key (session_key, p3)   references public.drivers,
  foreign key (session_key, pole) references public.drivers,
  check (p1 <> p2 and p1 <> p3 and p2 <> p3)
);
create index predictions_session_key_idx on public.predictions (session_key);

-- The scored outcome of one race, written once by score-races after the scores below.
-- Its insert is the "race is done" signal: it drops the race from races_unscored,
-- and Realtime tells clients to refetch the leaderboard.
create table public.results (
  session_key int primary key references public.sessions on delete cascade,  -- the Race or Sprint session
  p1          int not null,
  p2          int not null,
  p3          int not null,
  pole        int,
  scored_at   timestamptz not null default now(),
  foreign key (session_key, p1)   references public.drivers,
  foreign key (session_key, p2)   references public.drivers,
  foreign key (session_key, p3)   references public.drivers,
  foreign key (session_key, pole) references public.drivers
);

-- Points per player per race, calculated by score-races (scoring rules live in
-- supabase/functions/score-races/scoring.ts). Written before the results row, so a crash
-- in between just means the next run recalculates and upserts them again.
create table public.scores (
  user_id     uuid not null references public.profiles on delete cascade,
  session_key int  not null references public.sessions on delete cascade,  -- the Race or Sprint session
  points      int  not null check (points >= 0),
  primary key (user_id, session_key)
);

-- ---------------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------------

-- One row per race players can pick for: each Grand Prix ('race') and each Sprint ('sprint').
-- Picks lock when that race's own qualifying starts: 'Qualifying' for the Grand Prix,
-- 'Sprint Qualifying' for the Sprint. A cancelled race is left out.
create view public.races with (security_invoker = on) as
select r.session_key,
       r.meeting_key,
       case r.session_name when 'Race' then 'race' else 'sprint' end as kind,
       m.year,
       m.meeting_name,
       m.circuit_short_name,
       m.country_name,
       q.session_key as quali_session_key,
       q.date_start  as lock_at,
       r.date_start  as race_start,
       r.date_end    as race_end
from public.sessions r
join public.meetings m on m.meeting_key = r.meeting_key
join public.sessions q on q.meeting_key = r.meeting_key
  and q.session_name = case r.session_name when 'Race' then 'Qualifying' else 'Sprint Qualifying' end
where r.session_name in ('Race', 'Sprint')
  and not r.is_cancelled;

-- Races that ended in the last 2 days and have no result yet. The per-minute cron job
-- calls score-races only while this has rows.
create view public.races_unscored with (security_invoker = on) as
select ra.*
from public.races ra
left join public.results res on res.session_key = ra.session_key
where res.session_key is null
  and ra.race_end < now()
  and ra.race_end > now() - interval '2 days';

-- Standings, one table per season (year). Only races with a results row count, so scores
-- left behind by a deleted (corrected) result don't show until the race is rescored.
--   last_points: points from the season's most recent scored weekend (Sprint plus Grand Prix)
--   prev_rank:   the rank before that weekend; null for a player with no earlier score
-- Ties share a rank. They are ordered by total, then by best race.
create view public.leaderboard with (security_invoker = on) as
with scored as (
  select s.user_id, s.points, ra.year, ra.meeting_key, ra.race_start
  from public.scores s
  join public.results r on r.session_key = s.session_key
  join public.races ra on ra.session_key = s.session_key
),
latest as (
  select distinct on (year) year, meeting_key
  from scored
  order by year, race_start desc
),
totals as (
  select sc.year,
         sc.user_id,
         sum(sc.points)::int as total,
         count(*)::int       as races,
         max(sc.points)      as best_race,
         coalesce(sum(sc.points) filter (where sc.meeting_key = l.meeting_key), 0)::int as last_points,
         count(*) filter (where sc.meeting_key <> l.meeting_key) as races_before
  from scored sc
  join latest l on l.year = sc.year
  group by sc.year, sc.user_id
)
select t.year,
       t.user_id,
       pr.display_name,
       t.total,
       t.races,
       t.best_race,
       t.last_points,
       rank() over (partition by t.year order by t.total desc, t.best_race desc)::int as rank,
       case when t.races_before > 0
            then rank() over (partition by t.year order by t.total - t.last_points desc)::int
       end as prev_rank
from totals t
join public.profiles pr on pr.id = t.user_id
order by t.year desc, rank, pr.display_name;

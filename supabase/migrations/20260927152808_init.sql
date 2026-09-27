-- Parc Fermé: calendar from OpenF1, players' picks, and scoring.
-- Written by the Edge Functions (service role): meetings, sessions, drivers, scores, results.
-- Written by players: predictions (own rows, before the lock) and profiles (own display name).

-- ---------------------------------------------------------------------------
-- Calendar, stored as OpenF1 returns it
-- ---------------------------------------------------------------------------

create table public.meetings (
  meeting_key        int primary key,
  meeting_name       text not null,
  circuit_short_name text,
  country_name       text,
  year               int not null,
  date_start         timestamptz not null
);

create table public.sessions (
  session_key  int primary key,
  meeting_key  int not null references public.meetings on delete cascade,
  session_name text not null,  -- 'Practice 1', 'Sprint Qualifying', 'Sprint', 'Qualifying', 'Race'
  date_start   timestamptz not null,
  date_end     timestamptz not null
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

create table public.profiles (
  id           uuid primary key references auth.users on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40)
);

-- A player's picks for one race. Every pick must be on that race's entry list.
create table public.predictions (
  user_id     uuid not null default auth.uid() references public.profiles on delete cascade,
  session_key int  not null references public.sessions on delete cascade,  -- the Race session
  p1          int,
  p2          int,
  p3          int,
  pole        int,
  fastest_lap int,
  primary key (user_id, session_key),
  foreign key (session_key, p1)          references public.drivers,
  foreign key (session_key, p2)          references public.drivers,
  foreign key (session_key, p3)          references public.drivers,
  foreign key (session_key, pole)        references public.drivers,
  foreign key (session_key, fastest_lap) references public.drivers,
  check (p1 <> p2 and p1 <> p3 and p2 <> p3)
);
create index predictions_session_key_idx on public.predictions (session_key);

-- The scored outcome of one race, written once by score-races after the scores below.
-- Its insert is the "race is done" signal: it drops the race from races_unscored,
-- and Realtime tells clients to refetch the leaderboard.
create table public.results (
  session_key int primary key references public.sessions on delete cascade,  -- the Race session
  p1          int not null,
  p2          int not null,
  p3          int not null,
  pole        int,
  fastest_lap int,
  scored_at   timestamptz not null default now(),
  foreign key (session_key, p1)          references public.drivers,
  foreign key (session_key, p2)          references public.drivers,
  foreign key (session_key, p3)          references public.drivers,
  foreign key (session_key, pole)        references public.drivers,
  foreign key (session_key, fastest_lap) references public.drivers
);

-- Points per player per race, calculated by score-races (scoring rules live in
-- supabase/functions/score-races/scoring.ts). Written before the results row, so a crash
-- in between just means the next run recalculates and upserts them again.
create table public.scores (
  user_id     uuid not null references public.profiles on delete cascade,
  session_key int  not null references public.sessions on delete cascade,  -- the Race session
  points      int  not null check (points between 0 and 15),
  primary key (user_id, session_key)
);

-- ---------------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------------

-- One row per Grand Prix. Picks lock when GP qualifying starts; sprint qualifying doesn't count.
create view public.races with (security_invoker = on) as
select r.session_key,
       r.meeting_key,
       m.meeting_name,
       m.circuit_short_name,
       m.country_name,
       q.session_key as quali_session_key,
       q.date_start  as lock_at,
       r.date_start  as race_start,
       r.date_end    as race_end
from public.sessions r
join public.meetings m on m.meeting_key = r.meeting_key
join public.sessions q on q.meeting_key = r.meeting_key and q.session_name = 'Qualifying'
where r.session_name = 'Race';

-- Races that ended in the last 2 days and have no result yet. The per-minute cron job
-- calls score-races only while this has rows.
create view public.races_unscored with (security_invoker = on) as
select ra.*
from public.races ra
left join public.results res on res.session_key = ra.session_key
where res.session_key is null
  and ra.race_end < now()
  and ra.race_end > now() - interval '2 days';

-- Season standings. Only races with a results row count, so scores left behind by a
-- deleted (corrected) result don't show until the race is rescored.
create view public.leaderboard with (security_invoker = on) as
select pr.id as user_id,
       pr.display_name,
       sum(s.points)::int as total,
       count(*)::int      as races,
       max(s.points)      as best_race
from public.scores s
join public.results r on r.session_key = s.session_key
join public.profiles pr on pr.id = s.user_id
group by pr.id, pr.display_name
order by total desc;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.meetings    enable row level security;
alter table public.sessions    enable row level security;
alter table public.drivers     enable row level security;
alter table public.results     enable row level security;
alter table public.scores      enable row level security;
alter table public.profiles    enable row level security;
alter table public.predictions enable row level security;

-- Public F1 data: anyone can read (the sign-in page previews the next race).
-- No write policies, so only the service role (Edge Functions) can write.
create policy "calendar is public" on public.meetings for select to anon, authenticated using (true);
create policy "calendar is public" on public.sessions for select to anon, authenticated using (true);
create policy "calendar is public" on public.drivers  for select to anon, authenticated using (true);
create policy "calendar is public" on public.results  for select to anon, authenticated using (true);
create policy "players can see scores" on public.scores for select to authenticated using (true);

-- Display names show on the leaderboard. Rows are created by the trigger below.
create policy "players can see names" on public.profiles
  for select to authenticated using (true);
create policy "players rename themselves" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Your own picks always; everyone else's once the race has locked.
create policy "read own, or all after lock" on public.predictions
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (select 1 from public.races r
               where r.session_key = predictions.session_key and r.lock_at <= now())
  );

-- Only your own picks, only for a race, only before the lock.
create policy "write own before lock" on public.predictions
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.races r
                where r.session_key = predictions.session_key and now() < r.lock_at)
  );
create policy "change own before lock" on public.predictions
  for update to authenticated
  using (
    user_id = (select auth.uid())
    and exists (select 1 from public.races r
                where r.session_key = predictions.session_key and now() < r.lock_at)
  )
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.races r
                where r.session_key = predictions.session_key and now() < r.lock_at)
  );

-- ---------------------------------------------------------------------------
-- Every new user gets a profile
-- ---------------------------------------------------------------------------

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    left(coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),  -- from Create account
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),     -- from Google
      nullif(split_part(new.email, '@', 1), ''),                    -- fallback
      'Player'
    ), 40)
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Realtime: clients refetch the leaderboard when a result is inserted
-- ---------------------------------------------------------------------------

alter publication supabase_realtime add table public.results;

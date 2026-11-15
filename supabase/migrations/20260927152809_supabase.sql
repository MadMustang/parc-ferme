-- Everything that depends on Supabase: Auth, row-level security policies and Realtime.
-- On another host, replace this file and keep the schema migration as it is.
-- (The policies are plain Postgres. They only need the anon and authenticated roles and
-- an auth.uid() function that returns the signed-in user's id.)

-- ---------------------------------------------------------------------------
-- Players are Supabase Auth users
-- ---------------------------------------------------------------------------

alter table public.profiles
  add constraint profiles_id_fkey foreign key (id) references auth.users on delete cascade;

-- The browser never sends user_id: it is always the signed-in user.
alter table public.predictions alter column user_id set default auth.uid();

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

-- The email is never used as a name: every player can see display names.
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

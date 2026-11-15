-- Checks the rules the app relies on: profiles, sprints, seasons, the pick lock, and the entry list.
-- Run with `supabase test db`. Everything happens inside a transaction that is rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

-- Last season's race, an earlier race this season, a sprint weekend that has just finished,
-- an open race next week, and a cancelled race.
insert into public.meetings (meeting_key, meeting_name, circuit_short_name, country_name, year, date_start) values
  (800, 'Old Grand Prix',       'Old',   'Oldland',   2025, now() - interval '1 year'),
  (850, 'Earlier Grand Prix',   'Early', 'Earlyland', 2026, now() - interval '15 days'),
  (901, 'Test Grand Prix',      'Test',  'Testland',  2026, now() - interval '3 days'),
  (902, 'Next Grand Prix',      'Next',  'Nextland',  2026, now() + interval '1 day'),
  (903, 'Cancelled Grand Prix', 'Gone',  'Goneland',  2026, now() + interval '8 days');
insert into public.sessions (session_key, meeting_key, session_name, date_start, date_end) values
  (8001, 800, 'Qualifying',        now() - interval '1 year',   now() - interval '1 year' + interval '1 hour'),
  (8002, 800, 'Race',              now() - interval '364 days', now() - interval '364 days' + interval '2 hours'),
  (8501, 850, 'Qualifying',        now() - interval '15 days',  now() - interval '15 days' + interval '1 hour'),
  (8502, 850, 'Race',              now() - interval '14 days',  now() - interval '14 days' + interval '2 hours'),
  (9000, 901, 'Sprint Qualifying', now() - interval '2 days',   now() - interval '2 days' + interval '45 minutes'),
  (9003, 901, 'Sprint',            now() - interval '44 hours', now() - interval '43 hours'),
  (9001, 901, 'Qualifying',        now() - interval '1 day',    now() - interval '1 day' + interval '1 hour'),
  (9002, 901, 'Race',              now() - interval '3 hours',  now() - interval '1 hour'),
  (9011, 902, 'Qualifying',        now() + interval '2 days',   now() + interval '2 days 1 hour'),
  (9012, 902, 'Race',              now() + interval '3 days',   now() + interval '3 days 2 hours'),
  (9021, 903, 'Qualifying',        now() + interval '9 days',   now() + interval '9 days 1 hour');
insert into public.sessions (session_key, meeting_key, session_name, date_start, date_end, is_cancelled) values
  (9022, 903, 'Race', now() + interval '10 days', now() + interval '10 days 2 hours', true);
insert into public.drivers (session_key, driver_number, name_acronym, full_name, team_name, team_colour)
select s, d.num, d.acr, d.name, d.team, d.colour
from (values (8002), (8502), (9002), (9003), (9012)) as races(s)
cross join (values
  (1,  'NOR', 'Lando Norris',    'McLaren',         'F47600'),
  (81, 'PIA', 'Oscar Piastri',   'McLaren',         'F47600'),
  (3,  'VER', 'Max Verstappen',  'Red Bull Racing', '4781D7'),
  (16, 'LEC', 'Charles Leclerc', 'Ferrari',         'ED1131'),
  (44, 'HAM', 'Lewis Hamilton',  'Ferrari',         'ED1131'),
  (63, 'RUS', 'George Russell',  'Mercedes',        '00D7B6')
) as d(num, acr, name, team, colour);

-- Players: the trigger creates their profiles.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000001', 'you@example.com',   '{"display_name": "You"}'),
  ('00000000-0000-0000-0000-000000000002', 'sarah@example.com', '{"full_name": "Sarah"}'),
  ('00000000-0000-0000-0000-000000000003', 'kenji@example.com', '{"display_name": "Kenji"}'),
  ('00000000-0000-0000-0000-000000000004', 'maya@example.com',  '{"display_name": "Maya"}'),
  ('00000000-0000-0000-0000-000000000005', 'tomas@example.com', '{"display_name": "Tomás"}'),
  ('00000000-0000-0000-0000-000000000006', 'ayu@example.com',   '{"display_name": "Ayu"}'),
  ('00000000-0000-0000-0000-000000000007', 'partial@example.com', '{}');

select is((select display_name from public.profiles where id = '00000000-0000-0000-0000-000000000002'),
  'Sarah', 'Google full_name becomes the display name');
select is((select display_name from public.profiles where id = '00000000-0000-0000-0000-000000000007'),
  'Player', 'without a name, the display name is "Player", never the email');

select is((select lock_at from public.races where session_key = 9002),
  (select date_start from public.sessions where session_key = 9001),
  'Grand Prix picks lock when GP qualifying starts, not sprint qualifying');
select is((select lock_at from public.races where session_key = 9003),
  (select date_start from public.sessions where session_key = 9000),
  'Sprint picks lock when sprint qualifying starts');
select results_eq(
  $$ select session_key, kind from public.races where meeting_key = 901 order by session_key $$,
  $$ values (9002, 'race'), (9003, 'sprint') $$,
  'a sprint weekend has two races to pick for'
);
select is((select count(*)::int from public.races where meeting_key = 903), 0,
  'a cancelled race is not offered');

-- Picks for the finished race, as in the mockups (written as the table owner, bypassing RLS).
insert into public.predictions (user_id, session_key, p1, p2, p3, pole) values
  ('00000000-0000-0000-0000-000000000001', 9002, 1,  3,  16, 16),
  ('00000000-0000-0000-0000-000000000002', 9002, 1,  16, 3,  1),
  ('00000000-0000-0000-0000-000000000003', 9002, 3,  1,  81, 3),
  ('00000000-0000-0000-0000-000000000004', 9002, 16, 1,  44, 16),
  ('00000000-0000-0000-0000-000000000005', 9002, 1,  81, 63, 1),
  ('00000000-0000-0000-0000-000000000006', 9002, 81, 1,  3,  16),
  ('00000000-0000-0000-0000-000000000007', 9002, 1,  null, null, null);

select is((select count(*)::int from public.races_unscored), 2,
  'a finished sprint and a finished race without results are waiting to be scored');

-- What score-races writes: scores first (points from scoring.ts, tested separately), then the result.
-- A stray score for the unfinished race must not count on the leaderboard.
insert into public.scores (user_id, session_key, points) values
  ('00000000-0000-0000-0000-000000000003', 8002, 13),  -- last season
  ('00000000-0000-0000-0000-000000000001', 8502, 7),   -- earlier this season
  ('00000000-0000-0000-0000-000000000002', 8502, 4),
  ('00000000-0000-0000-0000-000000000001', 9003, 5),   -- the sprint
  ('00000000-0000-0000-0000-000000000002', 9003, 8),
  ('00000000-0000-0000-0000-000000000001', 9002, 7),   -- the Grand Prix
  ('00000000-0000-0000-0000-000000000002', 9002, 13),
  ('00000000-0000-0000-0000-000000000003', 9002, 2),
  ('00000000-0000-0000-0000-000000000001', 9012, 13);
insert into public.results (session_key, p1, p2, p3, pole) values
  (8002, 1, 16, 3, 1), (8502, 1, 16, 3, 1), (9003, 1, 16, 3, 1), (9002, 1, 16, 3, 1);

select is((select count(*)::int from public.races_unscored), 0, 'a scored race stops polling');

-- Before the weekend You led Sarah 7 to 4. Sarah scored 21 over the sprint and the race, You 12.
select results_eq(
  $$ select display_name, total, races, last_points, rank, prev_rank from public.leaderboard where year = 2026 $$,
  $$ values ('Sarah'::text, 25, 3, 21, 1, 2), ('You', 19, 3, 12, 2, 1), ('Kenji', 2, 1, 2, 3, null::int) $$,
  'the leaderboard adds up sprints and races with a result, and shows the move since last weekend'
);
select results_eq(
  $$ select display_name, total from public.leaderboard where year = 2025 $$,
  $$ values ('Kenji'::text, 13) $$,
  'each season has its own leaderboard'
);

select throws_ok(
  $$ insert into public.scores (user_id, session_key, points) values ('00000000-0000-0000-0000-000000000004', 9002, -1) $$,
  '23514', null, 'a score cannot be negative'
);

-- Entry list and podium rules apply to everyone, even the table owner.
select throws_ok(
  $$ insert into public.predictions (user_id, session_key, p1) values ('00000000-0000-0000-0000-000000000002', 9012, 99) $$,
  '23503', null, 'a pick must be on that race''s entry list'
);
select throws_ok(
  $$ insert into public.predictions (user_id, session_key, p1, p2) values ('00000000-0000-0000-0000-000000000002', 9012, 1, 1) $$,
  '23514', null, 'one driver cannot fill two podium places'
);

-- Now act as "You", a signed-in player.
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  $$ insert into public.predictions (session_key, p1) values (9012, 1)
     on conflict (user_id, session_key) do update set p1 = excluded.p1 $$,
  'a player can save picks before the lock'
);
select throws_ok(
  $$ insert into public.predictions (session_key, p1) values (9002, 3)
     on conflict (user_id, session_key) do update set p1 = excluded.p1 $$,
  '42501', null, 'a player cannot change picks after the lock'
);
select throws_ok(
  $$ insert into public.predictions (session_key, p1) values (9003, 3) $$,
  '42501', null, 'a player cannot pick for a sprint after its lock'
);
select throws_ok(
  $$ insert into public.predictions (session_key, p1) values (9022, 1) $$,
  '42501', null, 'a player cannot pick for a cancelled race'
);

-- Now act as Sarah.
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select is((select count(*)::int from public.predictions where session_key = 9012 and user_id <> auth.uid()), 0,
  'other players'' picks are hidden before the lock');
select is((select count(*)::int from public.predictions where session_key = 9002), 7,
  'everyone''s picks are visible after the lock');

reset role;
select * from finish();
rollback;

-- Checks the rules the app relies on: profiles, scoring, the pick lock, and the entry list.
-- Run with `supabase test db`. Everything happens inside a transaction that is rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

-- A locked race that has finished (scored below) and an open race next week.
insert into public.meetings (meeting_key, meeting_name, circuit_short_name, country_name, year, date_start) values
  (901, 'Test Grand Prix', 'Test', 'Testland', 2026, now() - interval '3 days'),
  (902, 'Next Grand Prix', 'Next', 'Nextland', 2026, now() + interval '1 day');
insert into public.sessions (session_key, meeting_key, session_name, date_start, date_end) values
  (9000, 901, 'Sprint Qualifying', now() - interval '2 days',  now() - interval '2 days' + interval '45 minutes'),
  (9001, 901, 'Qualifying',        now() - interval '1 day',   now() - interval '1 day' + interval '1 hour'),
  (9002, 901, 'Race',              now() - interval '3 hours', now() - interval '1 hour'),
  (9011, 902, 'Qualifying',        now() + interval '2 days',  now() + interval '2 days 1 hour'),
  (9012, 902, 'Race',              now() + interval '3 days',  now() + interval '3 days 2 hours');
insert into public.drivers (session_key, driver_number, name_acronym, full_name, team_name, team_colour)
select s, d.num, d.acr, d.name, d.team, d.colour
from (values (9002), (9012)) as races(s)
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
  'partial', 'without a name, the display name falls back to the email');

select is((select lock_at from public.races where session_key = 9002),
  (select date_start from public.sessions where session_key = 9001),
  'picks lock when GP qualifying starts, not sprint qualifying');

-- Picks for the finished race, as in the mockups (written as the table owner, bypassing RLS).
insert into public.predictions (user_id, session_key, p1, p2, p3, pole, fastest_lap) values
  ('00000000-0000-0000-0000-000000000001', 9002, 1,  3,  16, 16, 81),
  ('00000000-0000-0000-0000-000000000002', 9002, 1,  16, 3,  1,  3),
  ('00000000-0000-0000-0000-000000000003', 9002, 3,  1,  81, 3,  1),
  ('00000000-0000-0000-0000-000000000004', 9002, 16, 1,  44, 16, 16),
  ('00000000-0000-0000-0000-000000000005', 9002, 1,  81, 63, 1,  81),
  ('00000000-0000-0000-0000-000000000006', 9002, 81, 1,  3,  16, 1),
  ('00000000-0000-0000-0000-000000000007', 9002, 1,  null, null, null, null);

select is((select count(*)::int from public.races_unscored where session_key = 9002), 1,
  'a finished race without a result is waiting to be scored');

-- Result: NOR, LEC, VER; pole NOR; fastest lap PIA.
insert into public.results (session_key, p1, p2, p3, pole, fastest_lap) values (9002, 1, 16, 3, 1, 81);

select is((select count(*)::int from public.races_unscored), 0, 'a scored race stops polling');

select set_eq(
  $$ select pr.display_name, pp.points from public.prediction_points pp
     join public.profiles pr on pr.id = pp.user_id $$,
  $$ values ('Ayu', 4), ('Kenji', 2), ('Maya', 2), ('Sarah', 13), ('Tomás', 9), ('You', 9), ('partial', 5) $$,
  'points match the hand calculation, and empty picks score 0'
);

select is((select display_name from public.leaderboard limit 1), 'Sarah', 'the leaderboard is ordered by total');

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

-- Now act as Sarah.
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select is((select count(*)::int from public.predictions where session_key = 9012 and user_id <> auth.uid()), 0,
  'other players'' picks are hidden before the lock');
select is((select count(*)::int from public.predictions where session_key = 9002), 7,
  'everyone''s picks are visible after the lock');

reset role;
select * from finish();
rollback;

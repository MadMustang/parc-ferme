// Scores races that have finished but have no result yet (the races_unscored view).
// Called every minute by pg_cron, but only while races_unscored has rows.
// For each race: fetch the result from OpenF1, score every player's picks, upsert scores,
// then insert the results row. That insert is the "done" signal, so it goes last.
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import { scorePicks, type Result } from "./scoring.ts";

const API = "https://api.openf1.org/v1";

type Classified = { position: number | null; driver_number: number };
type Lap = { driver_number: number; lap_duration: number | null };

async function get<T>(path: string): Promise<T[]> {
  const res = await fetch(API + path);
  if (res.status === 404) return []; // OpenF1's answer when nothing matches yet
  if (!res.ok) throw new Error(`OpenF1 ${path} returned ${res.status}`);
  return res.json();
}

async function fetchResult(race: { session_key: number; quali_session_key: number }): Promise<Result | null> {
  const podium = (await get<Classified>(`/session_result?session_key=${race.session_key}&position<=3`))
    .filter((r) => r.position !== null)
    .sort((a, b) => a.position! - b.position!);
  if (podium.length < 3) return null; // not published yet; the next run tries again

  const [pole] = await get<Classified>(`/session_result?session_key=${race.quali_session_key}&position=1`);
  const laps = (await get<Lap>(`/laps?session_key=${race.session_key}`)).filter((l) => l.lap_duration !== null);
  const fastest = laps.reduce<Lap | null>((best, l) => (!best || l.lap_duration! < best.lap_duration! ? l : best), null);

  return {
    p1: podium[0]!.driver_number,
    p2: podium[1]!.driver_number,
    p3: podium[2]!.driver_number,
    pole: pole?.driver_number ?? null,
    fastest_lap: fastest?.driver_number ?? null,
  };
}

export default {
  // Secret key only: this is called by pg_cron, never by the browser.
  fetch: withSupabase({ auth: ["secret"] }, async (_req, ctx) => {
    const db = ctx.supabaseAdmin;
    const { data: pending, error } = await db.from("races_unscored").select("session_key, quali_session_key, meeting_name");
    if (error) throw error;

    const scored: { race: string; players: number }[] = [];
    for (const race of pending ?? []) {
      const result = await fetchResult(race);
      if (!result) continue;

      const { data: predictions, error: pErr } = await db
        .from("predictions")
        .select("user_id, p1, p2, p3, pole, fastest_lap")
        .eq("session_key", race.session_key);
      if (pErr) throw pErr;

      const scores = (predictions ?? []).map((p) => ({
        user_id: p.user_id,
        session_key: race.session_key,
        points: scorePicks(p, result),
      }));
      const { error: sErr } = await db.from("scores").upsert(scores);
      if (sErr) throw sErr;

      const { error: rErr } = await db.from("results").insert({ session_key: race.session_key, ...result });
      if (rErr) throw rErr;

      scored.push({ race: race.meeting_name, players: scores.length });
    }

    return Response.json({ pending: pending?.length ?? 0, scored });
  }),
};

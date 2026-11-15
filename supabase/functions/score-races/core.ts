// Scores races and sprints that have finished but have no result yet (the races_unscored view).
// For each one: fetch the result, score every player's picks, save the scores, then save
// the result. Saving the result is the "done" signal, so it goes last.
// No Deno or Supabase imports: index.ts runs this as an Edge Function, and a plain Node
// server with a scheduler can run it too.
import type { Db } from "../_shared/db.ts";
import { scorePicks, type Result } from "./scoring.ts";

type F1 = { getResult(race: { session_key: number; quali_session_key: number }): Promise<Result | null> };

export async function scoreRaces(db: Db, f1: F1) {
  const pending = await db.unscoredRaces();
  const scored: { race: string; kind: string; players: number }[] = [];
  for (const race of pending) {
    const result = await f1.getResult(race);
    if (!result) continue; // not published yet; the next run tries again

    const scores = (await db.predictions(race.session_key)).map((picks) => ({
      user_id: picks.user_id,
      session_key: race.session_key,
      points: scorePicks(picks, result, race.kind),
    }));
    await db.saveScores(scores);
    await db.saveResult(race.session_key, result);

    scored.push({ race: race.meeting_name, kind: race.kind, players: scores.length });
  }
  return { pending: pending.length, scored };
}

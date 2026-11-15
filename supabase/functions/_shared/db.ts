// Everything the jobs read from and write to the database, in one place.
// `Db` is what the jobs need; `supabaseDb` provides it through the Supabase client.
// On another host, write a second function that returns a `Db` (for example with a
// Postgres driver) and leave the jobs as they are.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Kind, Picks, Result } from "../score-races/scoring.ts";

export type Meeting = { meeting_key: number; meeting_name: string; circuit_short_name: string | null; country_name: string | null; year: number; date_start: string };
export type Session = { session_key: number; meeting_key: number; session_name: string; date_start: string; date_end: string; is_cancelled: boolean };
export type Driver = { session_key: number; driver_number: number; name_acronym: string; full_name: string; team_name: string | null; team_colour: string | null };
export type Race = { session_key: number; quali_session_key: number; kind: Kind; meeting_name: string };
export type Score = { user_id: string; session_key: number; points: number };

export type Db = {
  upsertMeetings(rows: Meeting[]): Promise<void>;
  upsertSessions(rows: Session[]): Promise<void>;
  upsertDrivers(rows: Driver[]): Promise<void>;
  unscoredRaces(): Promise<Race[]>;
  predictions(sessionKey: number): Promise<(Picks & { user_id: string })[]>;
  saveScores(rows: Score[]): Promise<void>;
  saveResult(sessionKey: number, result: Result): Promise<void>;
};

export function supabaseDb(client: SupabaseClient): Db {
  const check = <T>({ data, error }: { data: T; error: unknown }): T => {
    if (error) throw error;
    return data;
  };
  const upsert = async (table: string, rows: object[]) => {
    if (rows.length) check(await client.from(table).upsert(rows));
  };
  return {
    upsertMeetings: (rows) => upsert("meetings", rows),
    upsertSessions: (rows) => upsert("sessions", rows),
    upsertDrivers: (rows) => upsert("drivers", rows),
    unscoredRaces: async () =>
      check(await client.from("races_unscored").select("session_key, quali_session_key, kind, meeting_name")) ?? [],
    predictions: async (sessionKey) =>
      check(await client.from("predictions").select("user_id, p1, p2, p3, pole").eq("session_key", sessionKey)) ?? [],
    saveScores: (rows) => upsert("scores", rows),
    saveResult: async (sessionKey, result) => {
      check(await client.from("results").insert({ session_key: sessionKey, ...result }));
    },
  };
}

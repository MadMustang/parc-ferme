// The only file that talks to OpenF1 (https://openf1.org). It uses nothing but fetch,
// so it runs in Deno and in Node. To change the data source, write another file with
// the same four functions.
import type { Driver, Meeting, Session } from "./db.ts";
import type { Result } from "../score-races/scoring.ts";

const API = "https://api.openf1.org/v1";

async function get<T>(path: string): Promise<T[]> {
  const res = await fetch(API + path);
  if (res.status === 404) return []; // OpenF1's answer when nothing matches yet
  if (!res.ok) throw new Error(`OpenF1 ${path} returned ${res.status}`);
  return res.json();
}

// Meetings that start between two days, each as 'YYYY-MM-DD'.
export async function getMeetings(from: string, to: string): Promise<Meeting[]> {
  const meetings = await get<Meeting>(`/meetings?date_start>=${from}&date_start<=${to}`);
  return meetings.map(({ meeting_key, meeting_name, circuit_short_name, country_name, year, date_start }) =>
    ({ meeting_key, meeting_name, circuit_short_name, country_name, year, date_start }));
}

export async function getSessions(meetingKey: number): Promise<Session[]> {
  const sessions = await get<Session & { is_cancelled: boolean | null }>(`/sessions?meeting_key=${meetingKey}`);
  return sessions.map(({ session_key, meeting_key, session_name, date_start, date_end, is_cancelled }) =>
    ({ session_key, meeting_key, session_name, date_start, date_end, is_cancelled: is_cancelled ?? false }));
}

// The drivers of every session of a meeting. OpenF1 returns some rows twice and some
// without a name, so this keeps one complete row per driver per session.
export async function getEntryList(meetingKey: number): Promise<Driver[]> {
  type Row = Omit<Driver, "name_acronym" | "full_name"> & { name_acronym: string | null; full_name: string | null };
  const unique = new Map<string, Driver>();
  for (const d of await get<Row>(`/drivers?meeting_key=${meetingKey}`)) {
    if (!d.name_acronym || !d.full_name) continue;
    unique.set(`${d.session_key}:${d.driver_number}`, {
      session_key: d.session_key,
      driver_number: d.driver_number,
      name_acronym: d.name_acronym,
      full_name: d.full_name,
      team_name: d.team_name,
      team_colour: d.team_colour,
    });
  }
  return [...unique.values()];
}

// The podium of a race or sprint, and the fastest driver of its qualifying session.
// Null until OpenF1 has published the podium.
export async function getResult(race: { session_key: number; quali_session_key: number }): Promise<Result | null> {
  type Classified = { position: number | null; driver_number: number };
  const podium = (await get<Classified>(`/session_result?session_key=${race.session_key}&position<=3`))
    .filter((r) => r.position !== null)
    .sort((a, b) => a.position! - b.position!);
  if (podium.length < 3) return null;

  const [pole] = await get<Classified>(`/session_result?session_key=${race.quali_session_key}&position=1`);
  return {
    p1: podium[0]!.driver_number,
    p2: podium[1]!.driver_number,
    p3: podium[2]!.driver_number,
    pole: pole?.driver_number ?? null,
  };
}

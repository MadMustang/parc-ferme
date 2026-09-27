// Daily calendar sync (cron: 06:00 UTC). Daily rather than weekly so an entry list that
// OpenF1 publishes late in race week, or a moved session, is picked up within a day.
// 1. Upsert every meeting that starts in the next 4 weeks.
// 2. For a meeting that starts within 7 days, also upsert its sessions and entry list,
//    even if the meeting is already stored, so late time changes are picked up.
//
// Dev only: POST {"from": "2025-10-01", "to": "2025-10-10"} to sync a past window instead.
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

const API = "https://api.openf1.org/v1";
const DAY = 24 * 60 * 60 * 1000;

type Meeting = { meeting_key: number; meeting_name: string; circuit_short_name: string | null; country_name: string | null; year: number; date_start: string };
type Session = { session_key: number; meeting_key: number; session_name: string; date_start: string; date_end: string };
type Driver = { session_key: number; driver_number: number; name_acronym: string | null; full_name: string | null; team_name: string | null; team_colour: string | null };

async function get<T>(path: string): Promise<T[]> {
  const res = await fetch(API + path);
  if (res.status === 404) return []; // OpenF1's answer when nothing matches yet
  if (!res.ok) throw new Error(`OpenF1 ${path} returned ${res.status}`);
  return res.json();
}

const day = (ms: number) => new Date(ms).toISOString().slice(0, 10);

export default {
  // Secret key only: this is called by pg_cron, never by the browser.
  fetch: withSupabase({ auth: ["secret"] }, async (req, ctx) => {
    const db = ctx.supabaseAdmin;
    const body = req.headers.get("content-type")?.includes("json") ? await req.json() : {};
    const from = Date.parse(body.from ?? day(Date.now()));
    const to = body.to ? Date.parse(body.to) : from + 28 * DAY;

    const meetings = await get<Meeting>(`/meetings?date_start>=${day(from)}&date_start<=${day(to)}`);
    const { error: mErr } = await db.from("meetings").upsert(
      meetings.map(({ meeting_key, meeting_name, circuit_short_name, country_name, year, date_start }) =>
        ({ meeting_key, meeting_name, circuit_short_name, country_name, year, date_start })),
    );
    if (mErr) throw mErr;

    const thisWeek = meetings.filter((m) => Date.parse(m.date_start) < from + 7 * DAY);
    let sessionCount = 0;
    let driverCount = 0;
    for (const m of thisWeek) {
      const sessions = await get<Session>(`/sessions?meeting_key=${m.meeting_key}`);
      const { error: sErr } = await db.from("sessions").upsert(
        sessions.map(({ session_key, meeting_key, session_name, date_start, date_end }) =>
          ({ session_key, meeting_key, session_name, date_start, date_end })),
      );
      if (sErr) throw sErr;
      sessionCount += sessions.length;

      // OpenF1 returns some rows twice, and one upsert can't touch the same key twice.
      const drivers = await get<Driver>(`/drivers?meeting_key=${m.meeting_key}`);
      const unique = new Map<string, Driver>();
      for (const d of drivers) {
        if (d.name_acronym && d.full_name) unique.set(`${d.session_key}:${d.driver_number}`, d);
      }
      const { error: dErr } = await db.from("drivers").upsert(
        [...unique.values()].map(({ session_key, driver_number, name_acronym, full_name, team_name, team_colour }) =>
          ({ session_key, driver_number, name_acronym, full_name, team_name, team_colour })),
      );
      if (dErr) throw dErr;
      driverCount += unique.size;
    }

    return Response.json({
      window: [day(from), day(to)],
      meetings: meetings.length,
      synced: thisWeek.map((m) => m.meeting_name),
      sessions: sessionCount,
      drivers: driverCount,
    });
  }),
};

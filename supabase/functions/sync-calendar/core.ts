// Calendar sync. Run it at least once a day, so an entry list that is published late in
// race week, or a moved or cancelled session, is picked up within a day.
// 1. Save every meeting that starts in the next 4 weeks.
// 2. For a meeting that starts within 7 days, also save its sessions and entry list,
//    even if the meeting is already stored, so late changes are picked up.
// `window` replaces "today" and "4 weeks" with fixed days, to load a past weekend.
// No Deno or Supabase imports: index.ts runs this as an Edge Function, and a plain Node
// server with a scheduler can run it too.
import type { Db, Driver, Meeting, Session } from "../_shared/db.ts";

type F1 = {
  getMeetings(from: string, to: string): Promise<Meeting[]>;
  getSessions(meetingKey: number): Promise<Session[]>;
  getEntryList(meetingKey: number): Promise<Driver[]>;
};

const DAY = 24 * 60 * 60 * 1000;
const day = (ms: number) => new Date(ms).toISOString().slice(0, 10);

export async function syncCalendar(db: Db, f1: F1, window: { from?: string; to?: string } = {}) {
  const from = Date.parse(window.from ?? day(Date.now()));
  const to = window.to ? Date.parse(window.to) : from + 28 * DAY;

  const meetings = await f1.getMeetings(day(from), day(to));
  await db.upsertMeetings(meetings);

  const thisWeek = meetings.filter((m) => Date.parse(m.date_start) < from + 7 * DAY);
  let sessionCount = 0;
  let driverCount = 0;
  for (const m of thisWeek) {
    const sessions = await f1.getSessions(m.meeting_key);
    await db.upsertSessions(sessions);
    sessionCount += sessions.length;

    const drivers = await f1.getEntryList(m.meeting_key);
    await db.upsertDrivers(drivers);
    driverCount += drivers.length;
  }

  return {
    window: [day(from), day(to)],
    meetings: meetings.length,
    synced: thisWeek.map((m) => m.meeting_name),
    sessions: sessionCount,
    drivers: driverCount,
  };
}

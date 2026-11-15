// Edge Function entry for sync-calendar. Called by pg_cron. The work is in core.ts.
//
// Dev only: POST {"from": "2025-10-01", "to": "2025-10-10"} to sync a past window instead.
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import { supabaseDb } from "../_shared/db.ts";
import * as openf1 from "../_shared/openf1.ts";
import { syncCalendar } from "./core.ts";

export default {
  // Secret key only: this is called by pg_cron, never by the browser.
  fetch: withSupabase({ auth: ["secret"] }, async (req, ctx) => {
    const window = req.headers.get("content-type")?.includes("json") ? await req.json() : {};
    return Response.json(await syncCalendar(supabaseDb(ctx.supabaseAdmin), openf1, window));
  }),
};

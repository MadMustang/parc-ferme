// Edge Function entry for score-races. Called every minute by pg_cron, but only while
// races_unscored has rows. The work is in core.ts.
import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import { supabaseDb } from "../_shared/db.ts";
import * as openf1 from "../_shared/openf1.ts";
import { scoreRaces } from "./core.ts";

export default {
  // Secret key only: this is called by pg_cron, never by the browser.
  fetch: withSupabase({ auth: ["secret"] }, async (_req, ctx) =>
    Response.json(await scoreRaces(supabaseDb(ctx.supabaseAdmin), openf1))),
};

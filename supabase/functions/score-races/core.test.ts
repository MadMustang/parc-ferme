// Run with `npm run test:functions`. The database and OpenF1 are replaced by small fakes.
import { test } from "node:test";
import assert from "node:assert/strict";
import type { Db } from "../_shared/db.ts";
import { scoreRaces } from "./core.ts";

test("scores a sprint with sprint points, saves the result last, and skips an unpublished race", async () => {
  const calls: unknown[] = [];
  const db = {
    unscoredRaces: async () => [
      { session_key: 9003, quali_session_key: 9000, kind: "sprint", meeting_name: "Test Grand Prix" },
      { session_key: 9002, quali_session_key: 9001, kind: "race", meeting_name: "Test Grand Prix" },
    ],
    predictions: async () => [{ user_id: "sarah", p1: 1, p2: 16, p3: 3, pole: 1 }],
    saveScores: async (rows) => { calls.push(["scores", rows]); },
    saveResult: async (sessionKey, result) => { calls.push(["result", sessionKey, result]); },
  } as Db;
  const result = { p1: 1, p2: 16, p3: 3, pole: 1 };
  const f1 = { getResult: async (race: { session_key: number }) => (race.session_key === 9003 ? result : null) };

  assert.deepEqual(await scoreRaces(db, f1), {
    pending: 2,
    scored: [{ race: "Test Grand Prix", kind: "sprint", players: 1 }],
  });
  assert.deepEqual(calls, [
    ["scores", [{ user_id: "sarah", session_key: 9003, points: 8 }]],
    ["result", 9003, result],
  ]);
});

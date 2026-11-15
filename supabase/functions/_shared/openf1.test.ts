// Run with `npm run test:functions`. OpenF1 is replaced by canned answers, one per URL.
import { afterEach, test } from "node:test";
import assert from "node:assert/strict";
import { getEntryList, getResult } from "./openf1.ts";

const realFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = realFetch; });

// Answers each request with the rows of the first key its URL contains, or 404.
function openf1Answers(answers: Record<string, unknown[] | number>) {
  globalThis.fetch = async (url) => {
    const key = Object.keys(answers).find((k) => String(url).includes(k));
    const answer = key ? answers[key]! : 404;
    return typeof answer === "number" ? new Response("", { status: answer }) : Response.json(answer);
  };
}

const race = { session_key: 9002, quali_session_key: 9001 };

test("getResult reads the podium in finishing order, and pole from qualifying", async () => {
  openf1Answers({
    "session_key=9002": [
      { position: 3, driver_number: 3 },
      { position: 1, driver_number: 1 },
      { position: 2, driver_number: 16 },
    ],
    "session_key=9001": [{ position: 1, driver_number: 81 }],
  });
  assert.deepEqual(await getResult(race), { p1: 1, p2: 16, p3: 3, pole: 81 });
});

test("getResult is null until the whole podium is published", async () => {
  openf1Answers({});  // 404: nothing published
  assert.equal(await getResult(race), null);

  openf1Answers({ "session_key=9002": [{ position: 1, driver_number: 1 }, { position: null, driver_number: 16 }] });
  assert.equal(await getResult(race), null);
});

test("getResult leaves pole empty when qualifying has no result", async () => {
  openf1Answers({
    "session_key=9002": [1, 16, 3].map((driver_number, i) => ({ position: i + 1, driver_number })),
  });
  assert.deepEqual(await getResult(race), { p1: 1, p2: 16, p3: 3, pole: null });
});

test("an OpenF1 error is thrown, not read as 'no result yet'", async () => {
  openf1Answers({ "session_key=9002": 500 });
  await assert.rejects(getResult(race), /returned 500/);
});

test("getEntryList drops repeated rows and rows without a name", async () => {
  const nor = { session_key: 9002, driver_number: 1, name_acronym: "NOR", full_name: "Lando Norris", team_name: "McLaren", team_colour: "F47600" };
  openf1Answers({ "/drivers": [nor, { ...nor, headshot_url: "x" }, { ...nor, driver_number: 99, full_name: null }] });
  assert.deepEqual(await getEntryList(901), [nor]);
});

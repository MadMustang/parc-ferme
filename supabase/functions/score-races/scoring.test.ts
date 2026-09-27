// Run with `npm run test:scoring`. Same example race as the mockups and the database tests.
import { test } from "node:test";
import assert from "node:assert/strict";
import { scorePicks, type Picks } from "./scoring.ts";

const NOR = 1, VER = 3, LEC = 16, PIA = 81, HAM = 44, RUS = 63;
const result = { p1: NOR, p2: LEC, p3: VER, pole: NOR, fastest_lap: PIA };
const picks = (p1: number | null, p2: number | null, p3: number | null, pole: number | null, fastest_lap: number | null): Picks =>
  ({ p1, p2, p3, pole, fastest_lap });

test("matches the hand-calculated example race", () => {
  assert.equal(scorePicks(picks(NOR, VER, LEC, LEC, PIA), result), 9);   // You
  assert.equal(scorePicks(picks(NOR, LEC, VER, NOR, VER), result), 13);  // Sarah
  assert.equal(scorePicks(picks(VER, NOR, PIA, VER, NOR), result), 2);   // Kenji
  assert.equal(scorePicks(picks(LEC, NOR, HAM, LEC, LEC), result), 2);   // Maya
  assert.equal(scorePicks(picks(NOR, PIA, RUS, NOR, PIA), result), 9);   // Tomás
  assert.equal(scorePicks(picks(PIA, NOR, VER, LEC, NOR), result), 4);   // Ayu
});

test("a perfect weekend is 15", () => {
  assert.equal(scorePicks(picks(NOR, LEC, VER, NOR, PIA), result), 15);
});

test("empty picks score nothing", () => {
  assert.equal(scorePicks(picks(null, null, null, null, null), result), 0);
  assert.equal(scorePicks(picks(NOR, null, null, null, null), result), 5);
});

test("a missing pole or fastest lap in the result can't be matched by an empty pick", () => {
  const noExtras = { ...result, pole: null, fastest_lap: null };
  assert.equal(scorePicks(picks(NOR, LEC, VER, null, null), noExtras), 11);
});

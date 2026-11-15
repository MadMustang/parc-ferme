// Run with `npm run test:functions`. Same example race as the mockups and the database tests.
import { test } from "node:test";
import assert from "node:assert/strict";
import { scorePicks, type Picks } from "./scoring.ts";

const NOR = 1, VER = 3, LEC = 16, PIA = 81, HAM = 44, RUS = 63;
const result = { p1: NOR, p2: LEC, p3: VER, pole: NOR };
const picks = (p1: number | null, p2: number | null, p3: number | null, pole: number | null): Picks =>
  ({ p1, p2, p3, pole });

test("matches the hand-calculated example race", () => {
  assert.equal(scorePicks(picks(NOR, VER, LEC, LEC), result, "race"), 7);   // You
  assert.equal(scorePicks(picks(NOR, LEC, VER, NOR), result, "race"), 13);  // Sarah
  assert.equal(scorePicks(picks(VER, NOR, PIA, VER), result, "race"), 2);   // Kenji
  assert.equal(scorePicks(picks(LEC, NOR, HAM, LEC), result, "race"), 2);   // Maya
  assert.equal(scorePicks(picks(NOR, PIA, RUS, NOR), result, "race"), 7);   // Tomás
  assert.equal(scorePicks(picks(PIA, NOR, VER, LEC), result, "race"), 4);   // Ayu
});

test("a perfect Grand Prix is 13, a perfect Sprint is 8", () => {
  assert.equal(scorePicks(picks(NOR, LEC, VER, NOR), result, "race"), 13);
  assert.equal(scorePicks(picks(NOR, LEC, VER, NOR), result, "sprint"), 8);
});

test("a Sprint halves the bonuses but not the podium point", () => {
  assert.equal(scorePicks(picks(NOR, VER, LEC, LEC), result, "sprint"), 5);  // 3 on the podium + exact P1
  assert.equal(scorePicks(picks(PIA, NOR, VER, NOR), result, "sprint"), 4);  // 2 on the podium + exact P3 + pole
});

test("empty picks score nothing", () => {
  assert.equal(scorePicks(picks(null, null, null, null), result, "race"), 0);
  assert.equal(scorePicks(picks(NOR, null, null, null), result, "race"), 5);
});

test("a missing pole in the result can't be matched by an empty pick", () => {
  assert.equal(scorePicks(picks(NOR, LEC, VER, null), { ...result, pole: null }, "race"), 11);
});

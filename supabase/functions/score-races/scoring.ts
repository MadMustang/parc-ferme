// The Parc Fermé scoring rules. A Grand Prix is worth 13 points at most, a Sprint 8:
//   1 per picked driver who finishes on the podium, in any position
//   Grand Prix: +4 for the exact P1, +2 for the exact P2, +2 for the exact P3, 2 for pole
//   Sprint:     +2 for the exact P1, +1 for the exact P2, +1 for the exact P3, 1 for pole
// A Sprint's pole is the fastest driver in Sprint Qualifying.
// Pure function with no Deno or Supabase imports, so it can be tested with plain Node.

export type Kind = "race" | "sprint";

export type Picks = {
  p1: number | null;
  p2: number | null;
  p3: number | null;
  pole: number | null;
};

export type Result = {
  p1: number;
  p2: number;
  p3: number;
  pole: number | null;
};

const BONUS = {
  race: { p1: 4, p2: 2, p3: 2, pole: 2 },
  sprint: { p1: 2, p2: 1, p3: 1, pole: 1 },
};

const hit = (pick: number | null, actual: number | null, points: number) =>
  pick !== null && pick === actual ? points : 0;

export function scorePicks(picks: Picks, result: Result, kind: Kind): number {
  const podium = [result.p1, result.p2, result.p3];
  const onPodium = [picks.p1, picks.p2, picks.p3].filter((d) => d !== null && podium.includes(d)).length;
  const bonus = BONUS[kind];
  return onPodium
    + hit(picks.p1, result.p1, bonus.p1)
    + hit(picks.p2, result.p2, bonus.p2)
    + hit(picks.p3, result.p3, bonus.p3)
    + hit(picks.pole, result.pole, bonus.pole);
}

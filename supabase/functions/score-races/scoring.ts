// The Parc Fermé scoring rules, 15 points at most per race:
//   1 per picked driver who finishes on the podium, in any position
//   +4 for the exact P1, +2 for the exact P2, +2 for the exact P3
//   2 for pole, 2 for fastest lap
// Pure function with no Deno or Supabase imports, so it can be tested with plain Node.

export type Picks = {
  p1: number | null;
  p2: number | null;
  p3: number | null;
  pole: number | null;
  fastest_lap: number | null;
};

export type Result = {
  p1: number;
  p2: number;
  p3: number;
  pole: number | null;
  fastest_lap: number | null;
};

const hit = (pick: number | null, actual: number | null, points: number) =>
  pick !== null && pick === actual ? points : 0;

export function scorePicks(picks: Picks, result: Result): number {
  const podium = [result.p1, result.p2, result.p3];
  const onPodium = [picks.p1, picks.p2, picks.p3].filter((d) => d !== null && podium.includes(d)).length;
  return onPodium
    + hit(picks.p1, result.p1, 4)
    + hit(picks.p2, result.p2, 2)
    + hit(picks.p3, result.p3, 2)
    + hit(picks.pole, result.pole, 2)
    + hit(picks.fastest_lap, result.fastest_lap, 2);
}

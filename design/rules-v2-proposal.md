# 666 — Iteration 2: rules v2 proposal

Built on Iván's written rules (2026-08-26). Method: Monte-Carlo simulator
(greedy heuristic bots, 3000–4000 games per config, cross-checked with two
independently built sims), three analysis agents, three competing design
agents, one red-team pass. Everything below is reproducible:
`design/simulator/sim666.py`, configs in this doc, results in `design/results/`.

## Verdict on the new skeleton

The bones are good: 52 cards, no market-fired instants (correctly cut — they
decided 12% of v1 games), momentum softened to +1 action, free draw on lock,
3–4 players. Two structural problems surfaced:

1. **Flexible basics can stall a competitive table** (see Known issues —
   team decision: ship as-is, document it).
2. **The 12 effect cards and the demonic die were undefined** — and that's
   where both the fun and the breakage live.

## The 12 effect cards

| Card | Qty | Text |
|---|---|---|
| **SMASH** | 3 | Drop an opponent's locked 6 to **5** (it unlocks), then **+1 your lowest unlocked die**. |
| **SHIELD** | 3 | Keep in hand. When an opponent's card hits your dice, reveal: **that entire card is cancelled** (all its effects, for everyone). Reveal after targets are declared, before any roll. |
| **GAMBLE** | 2 | Roll the demonic die on one of your unlocked dice: 1–3 → −1, 4–6 → +2. |
| **REROLL** | 1 | Set one of **your own** unlocked dice — or an opponent's die showing 4–5 — to a demonic-die roll. |
| **PACT** | 3 | Choose one of your unlocked dice — **not your last one** — and roll the demonic die: 4–6 → set it to 6 (locks, normal rewards); 1–3 → set it to 1. The pact roll itself cannot be redone; the resulting die is otherwise normal. |

**Why these five.** All three design agents independently converged on
SMASH-to-5-with-bounty (attacks advance you — kills the v1 "public-goods
trap" where attacking was a losing move) and on SHIELD as a hand interrupt
(the table's own interpretation; 0 blocks in 12,500 sims when pre-placed,
~1.1 blocks/game as an interrupt). All three independently **cut TRADE**
(self-taxed attack = v1's trap; also an edge-case magnet). PACT is the win
of the tournament: it's the only tested luck organ that pulls optimal-play
dominance down into the target band (91.5% → 85%) — it injects swing that
even perfect players must take.

**Why PACT can't target your last die.** Without that clause, **41% of wins
ended on a demonic-die roll** (uncounterable coin-flip finishes). With it:
**15.8%** — the last pip has to be earned where SMASH, SHIELD and minus
plays can contest it. Same reason we rejected the "you win at the start of
your next turn" variant: it photographed beautifully (97% photo finishes)
but broke a declared win in 22% of games and cut comebacks by 8 pp —
seethe, not laughs.

## The demonic die

> **The demonic die is the only die that is ever rolled.** Your own dice are
> never rolled — only set. Whenever a card says "roll" (GAMBLE, REROLL,
> PACT), roll the demonic die.

One sentence, zero new mechanics, and the red die being passed around *is*
the push-your-luck ritual. PACT gives it its moment ("four or more and I
lock… he rolls… THREE").

## Small rulings the text needs (red-team findings)

1. Count your actions **at the start of your turn** (locking mid-turn helps
   next turn).
2. DUAL's minus half is **optional** (you may skip it).
3. **You may always discard a card as an action, and you may always pass**
   (prevents a 5-card hand of unplayable reaction cards from freezing a turn).
4. When the deck runs out, **reshuffle the discard** (happens ~1×/game).
5. Basic split: **17× value 1, 12× value 2** (the brake that holds the pace
   at 8 rounds after the luck cards speed it up).
6. DUAL = +1/−1.

## Numbers (4P, 2000–3000 games/config)

| Metric | v1 (pptx) | **v2 as shipped** (optimal bots) | v2, mixed table proxy |
|---|---|---|---|
| Median rounds (p90) | 12 (18) | 31 (51) | 19 (39) |
| Stalled games (60-round cap) | 0% | 15% | 2.4% |
| Runner-up ≤3 pips | 55% | 27% | — |
| Wins decided by an uncontrollable event | 12% (random SURGE) | **15% (chosen PACT/GAMBLE)** | — |
| Shield blocks ("BLOCKED!") | 0.0 | ~1/game | — |

Optimal bots are the worst case — they exploit the beat-the-leader loop
mercilessly. Real tables sit between the two columns; the team's live games
ended in normal time.

## Known issues, stated honestly

- **Competitive stall (team decision: accepted).** Because every basic card
  can be played as a minus, a table that plays hard can knock back whoever
  approaches the win indefinitely: with optimal bots 15% of games hit the
  60-round cap and the median runs 31 rounds. Casual tables race instead of
  policing and finish fine. If it ever shows up in live play, the tested
  two-line fix is parked here: *minus plays only on dice showing 4–5, max
  one minus play per turn* → median 8 rounds, 0% stalls, 83% photo finishes.
- **Seat bias**: the last seat wins ~31% vs ~18% for the first (open-target
  race structure; every config shows it). Optional setup rule that trims it
  to ~8 pp and costs one round: *deal 2 extra starting cards to the first
  player and 1 to the second (4P); 1 extra to the first player (3P).* For
  class play: rotate who starts across games.
- **PACT feel-bad**: a failed pact sets a die to 1 (~1.2×/game). It's
  opt-in and best aimed at low dice, but watch the table; softening lever =
  "1–3 → set it to 2" (untested).
- The optional **TEMPT/FALSE IDOL module** (demonic die keeps its last face;
  spend an action to challenge it) is flavorful but *widened* the
  optimal-vs-casual gap in sims (94%) — bots exploit it, casuals get taxed.
  Live-test before adopting; not in v2.
- **2P is out of scope** (Iván's 3-or-4 box label is right; v1 sims showed
  58/42 first-player bias at 2P).
- Sim numbers validate the rules **as written here** (the red team caught
  three places where earlier text and sim disagreed; this document is the
  reconciled version).

## Reproduce

```json
{"ruleset":"ivan","smash_to":5,"smash_bounty":1,
 "effects":{"SMASH":3,"SHIELD":3,"GAMBLE":2,"REROLL":1,"PACT":3},
 "basic_split":[17,12]}
```
`python3 design/simulator/sim666.py --config '<json>' --games 4000`

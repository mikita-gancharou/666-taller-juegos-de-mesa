# Baseline simulation — rules v1

3000 games per config, heuristic bots (greedy 1-ply with hand-tuned card values),
seed-fixed. Raw JSON in `baseline.json`. Time proxy: a 4P round ≈ 2 min, so the
15–25 min target ≈ **8–13 rounds**.

## Headline numbers (4 players, smart bots)

| Metric | raw v1 | no instants | flat momentum [3,3,3] | no inst + flat |
|---|---|---|---|---|
| Median rounds | **12** | 17 | 11 | 18 |
| p90 rounds | 18 | 25 | 17 | 26 |
| Lead changes / game | 4.9 | 7.3 | 5.0 | 8.2 |
| Comeback % (winner ≠ leader @ R6) | 59 | 65 | 66 | 68 |
| Runner-up ≤3 pips at end | 55% | 38% | **67%** | 55% |
| **Games decided by an instant** | **12.0%** | 0 | 12.6% | 0 |
| Attack events / game | 23 | **35** | 26 | **41** |
| Stalls (60-round cap) | 0% | 0% | 0% | 0% |
| Reshuffles / game | 0.7 | 1.1 | 0.9 | 1.4 |

Seats (all configs): last seat wins ~30%, first ~21% — **a ~9 pp last-seat
advantage**. Agency check: 1 smart bot vs 3 random wins **60%** (par 25%).
2P is lopsided: first player wins 58.5%.

## What this actually says

1. **Playtest confirmed, quantified: 1 game in 8 is won by a random market
   flip.** SURGE locks the winner's last die in 12% of games. Instants also
   swing ~8 pips/game. Zero decisions involved.
2. **But instants are currently doing a real job: pacing.** Removing them makes
   the game *drag* — 17 median rounds (p90 25 ≈ 45+ min) and the attack
   treadmill takes over (35→41 attack events; lock, get smashed, relock).
   So the fix can't be "just delete them": we must **keep the acceleration,
   return the agency**.
3. **Momentum 2/3/4 is NOT the runaway villain.** Flat [3,3,3] plays nearly the
   same length; comebacks and photo-finishes actually improve slightly. Reason:
   being at 2 locks paints a target on you — the table's SMASHes compensate.
   Momentum is defensible as compensation for being focused down; keep or
   flatten is a tuning choice, not a rescue.
4. **The real fun leak is the treadmill + randomness combo**: 23–41 attack
   events per game means each player is hit ~6–10 times; progress feels erased,
   and the thing that finally ends the game is often a top-decked SURGE.
5. **Seat order needs a fix** (~9 pp advantage to the last seat) and 2P needs
   its own tweak or a "3–4 players" box label.
6. Never stalls with the reshuffle rule; economy holds.

## Fun targets for the iteration (used to judge variants)

- Median 8–13 rounds, p90 ≤ 16, stalls <1%
- Runner-up within ≤3 pips ≥ 60% of games
- Comeback ≥ 40%, lead changes ≥ 3
- Instant-decided games <3%
- Attack events 12–22 per 4P game (take-that present, treadmill capped)
- Smart-vs-random win rate 55–80%
- Seat spread ≤5 pp

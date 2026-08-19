# 666 — Rules v1 (codified)

Codified from the pitch deck (`666_rules 1.pptx`) plus the rulings we had to make
where the deck is silent. This is the baseline for the design iteration.

## Goal

Be the first to lock all three of your dice on 6.

## Setup

1. Each player sets their 3 dice to **3-3-3**.
2. Shuffle the 66-card deck. Deal **3 cards** to each player.
3. Market: deck face down, **3 cards face up** beside it.
4. Roll a d6 for turn order; highest goes first.

*Ruling:* instants revealed during setup are shuffled back; the market starts
with 3 normal cards.

## Turn

Actions per turn depend on **momentum** (your locked dice at turn start):

| Locked | Actions |
|---|---|
| 0 | 2 |
| 1 | 3 |
| 2 | 4 |

Each action is either:

- **DRAW** — take one face-up card from the market (only from the market; the
  slot stays empty until end of turn).
- **PLAY** — play one card from your hand.

Any mix. **Hand limit 5**, discard down at end of turn. **Refill the market to 3
when your turn ends.**

*Rulings:* momentum is computed at turn start (a lock mid-turn doesn't add an
action this turn). When the deck runs out, reshuffle the discard pile.

## Locking

*Ruling:* a die that reaches 6 is **locked automatically**. Locked dice can't be
moved by movement cards, are immune to COLLAPSE, but **can** be attacked by
SMASH and TRADE (drop to 4, unlock). SHIELD on a locked die absorbs the next
SMASH/TRADE.

## The deck (66 cards)

| Card | Qty | Effect |
|---|---|---|
| +1 | 14 | Move one die +1 (any player's; overflow past 6 wasted) |
| +2 | 10 | Move one die +2 |
| −2 | 6 | Move one die −2 (floor 1) |
| DUAL | 6 | +2 one of your dice AND −1 one opponent die |
| SHIELD | 6 | Protect one of your locked 6s from the next SMASH/TRADE |
| SMASH | 5 | Drop a rival's locked 6 by 2 (→4, unlocked) |
| TRADE | 5 | Same as SMASH, then lower one of your own dice by 1 |
| GAMBLE | 4 | Roll d6 on one of your dice: 1-3 → −1, 4-6 → +2 (clamped 1..6) |
| REROLL | 4 | Set any one unlocked die to a random value |
| SURGE *(instant)* | 2 | All dice +1 (locks 5s) |
| COLLAPSE *(instant)* | 2 | All **unlocked** dice −1 |
| FLOOD *(instant)* | 2 | Discard the market, deal 3 new |

**Instants** are double-bordered: the moment one appears in the market it fires
immediately, hits everyone, cannot be held, then is discarded and the refill
continues. In v1 they can only appear during the end-of-turn refill (and FLOOD
chains).

*Note:* the deck slide gives card types but not counts; the counts above are our
working distribution (28/66 = 42% of cards can hurt a rival).

## Playtest report (why we're iterating)

- **The ±1 global instants (SURGE / COLLAPSE) are broken in play.** Global,
  random-timed, zero-decision swings. SURGE can lock dice for everyone at once
  (including handing the leader the win); COLLAPSE burns up to 9–12 pips of
  table progress in one flip and hits trailing players hardest (leaders' locked
  dice are immune) — the opposite of catch-up.
- **The fun is not landing.** Suspicions to test: runaway-leader momentum
  (2/3/4 actions accelerates whoever is already winning), instant-driven
  randomness drowning decisions, SMASH treadmill (lock → smashed → relock)
  feeling like erased progress.

## Known math (to verify by simulation)

- 6 instants / 66 cards ≈ 9% per market flip; with 1–2 flips per turn an
  instant fires roughly every other round at 4 players.
- Pip economy is thin: constructive cards supply ~46 net pips (incl. DUAL and
  GAMBLE EV); 4 players each need 9 pips. Reshuffling the discard is mandatory.
- GAMBLE quirks: on a 1 it's pure upside (50% stay, 50% +2); on a 4 or 5 it's a
  coin-flip lock. On a 4: 50% → 3, 50% → 6.

# Variant knob space (what the simulator can test)

A variant = a JSON config using ONLY these knobs. Anything outside this space
needs new simulator code — propose it as `wish` text, not config.

| Knob | Values | Meaning |
|---|---|---|
| `instants` | `"raw"` | v1: fire on reveal during refill, hit everyone |
| | `"none"` | cut instants; `instant_replacement` adds 6 cards back (default +3 P1, +3 M2) |
| | `"choice"` | revealer decides: SURGE = +1 to two of the revealer's own unlocked dice; COLLAPSE = −2 to one opponent unlocked die of the revealer's choice; FLOOD unchanged |
| | `"omen"` | instant sits face-up; fires (raw effect) at the START of the revealer's NEXT turn; any player may spend 1 action to defuse it |
| | `"personal"` | affects only the revealer's dice (drawing risk) |
| | `"catchup"` | SURGE hits only players with the fewest locks; COLLAPSE only players with the most locks |
| `momentum` | `[a,b,c]` | actions at 0/1/2 locks; v1 = [2,3,4]; e.g. [3,3,3], [3,3,2], [2,3,3] |
| `catchup_bonus` | 0/1 | +1 action when strictly last by progress |
| `lock_mode` | `"auto"` | 6 locks immediately (v1) |
| | `"action"` | locking costs 1 action; an unlocked 6 is attackable by ANY minus-card and COLLAPSE; locked dice still only SMASH/TRADE |
| `market_slots` | 3 / 4 | face-up market size |
| `blind_draw` | bool | may draw top of deck as an action (instants fire on you per mode) |
| `hand_limit` | int | v1 = 5 |
| `deck_overrides` | {card: n} | change counts; keep total 66 (e.g. fewer SMASH, more SHIELD) |
| `max_rounds` | int | stall cap (60) |
| `smash_bounty` | 0/1 | successful SMASH/TRADE also gives the attacker +1 on their lowest unlocked die ("soul harvest" — attacks stop being pip-deletion) |
| `smash_to` | 4/5 | value a smashed 6 drops to (5 = dented, one card to repair; 4 = v1 deleted) |
| `attack_rate_limit` | 0/1 | each player absorbs at most 1 SMASH/TRADE between their own turns |
| `win_delay` | 0/1 | "the ink dries": 3rd lock wins at the START of your next turn — the table gets one last window to break it |
| `shield_hidden` | 0/1 | shields are placed face-down; attackers can't route around them (blocks actually happen) |

Cards: P1(+1)/P2(+2)/M2(−2)/DUAL/SHIELD/SMASH/TRADE/GAMBLE/REROLL/SURGE/COLLAPSE/FLOOD.

Constraints for proposals: deck stays 66 cards; components stay = 66 cards,
13 dice, ~18 tokens, 4 player boards; rules delta must be teachable in one
sentence per change.

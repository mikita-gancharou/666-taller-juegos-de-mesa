# Analysis — three-lens audit + Monte-Carlo (iteration 2)

Sources: rules-lawyer agent, fun-theory agent (built its own 12.5k-game sim),
math agent, plus our simulator baseline (24k games). Raw JSON: `results/analysis-agents-raw.json`.

## The five load-bearing findings

1. **Instants are broken and leader-favoring** — 12% of games won by a random
   SURGE; ~29% of all pip movement has no author; SURGE locks a die for the
   pip-leader in ~90% of fires; COLLAPSE hits trailing players 3× harder than
   leaders. BUT deleting them stretches the game 12→17 rounds: they carry the
   pacing. Fix = keep acceleration, add agency.
2. **Interaction is a losing trap** — deck prints +54/−43 pips per cycle; a lone
   attacker wins 20% (below the 25% par); a pure racer beats tacticians; 43–51%
   of smashes are repaired within one victim turn (treadmill).
3. **SHIELD never triggers** — 0 blocks in 12,500 games. Open information means
   attackers route around it; the "BLOCKED!" moment does not exist.
4. **The best moment in the box is nearly extinct** — GAMBLE on a 4/5 is a
   public coin-flip lock (pure push-your-luck) and fires 0.2×/game because a
   sure +1/+2 always dominates.
5. **Structural holes** — win timing undefined for simultaneous locks (SURGE can
   finish two players at once); last seat wins 30% vs 21% for seat 1; 2P is a
   58/42 coin-weighted race; setup instants contradiction (fires in 60–80% of
   setups by RAW).

## Rules-lawyer findings (by severity)

- **[high] No winner defined for simultaneous third-lock; win timing undefined generally**
  - SURGE fires during the active player's end-of-turn refill and gives +1 to all dice, locking 5s. If two or more players each sit at 2 locked + a 5 (a common endgame state, and the optimal one — see camping exploit), one SURGE completes all of them in the same instant and the rules never say who wins. More generally win timing is unstated: is 'first to lock all three' checked immediately or at end o
  - *Ruling:* Add: 'The game ends the instant any player has 3 locked dice, regardless of whose turn it is; there is no response window. If a single effect locks the third die for several players simultaneously, the winner is the tied player closest in turn order after the active player (active player counts as c
- **[high] SURGE/COLLAPSE are zero-decision, random-timed, LEADER-FAVORING global swings (playtest-confirmed)**
  - Both instants resolve at a random moment (whenever refill flips them) with no input from any player. COLLAPSE only hits unlocked dice, so it burns up to 12 pips of table progress while the leader's locked dice are immune — it is a catch-up mechanic pointed backwards. SURGE gives everyone free pips but is worth most to whoever is closest to winning and can outright END the game (locks 5s) at a mome
  - *Ruling:* Cut SURGE/COLLAPSE, or defang AND telegraph them: a revealed instant stays on its market slot as an 'omen' and resolves at the START of the revealing player's NEXT turn, giving everyone one turn to react. Cap magnitude and add choice: SURGE = 'each player +1 to one die of their choice; this cannot r
- **[high] Runaway leader: the 2/3/4 action ladder is a triple positive-feedback loop**
  - Locking dice simultaneously grants extra actions (2 -> 3 -> 4), makes those dice immune to COLLAPSE and every movement card, and shrinks your attackable surface to 10 cards in 66 (SMASH/TRADE). The first player to lock draws more, plays more, defends better, and fears instants less — momentum compounds exactly when the race should tighten. Concretely: a 1-locked player at 6L-5-5 with 3 actions win
  - *Ruling:* Flatten to 3 actions for everyone, or invert the ladder for built-in catch-up: 4 actions at 0 locked / 3 at 1 / 2 at 2 (thematically: locked dice are spent power). Inverting also widens the endgame response window that the no-interrupt rule currently slams shut. Playtest the inverted ladder first — 
- **[high] Instants during setup: direct rules contradiction that occurs in 60-80% of games**
  - Setup deals 3 cards to each hand plus 3 face-up market cards before any turn exists. Instants 'fire the moment they appear in the market (i.e. during end-of-turn refill)' and 'cannot be held' — but setup is not an end-of-turn refill and hands are dealt face down. Computed exactly: with 6 instants in 66 cards, at least one instant is dealt during setup in 60.1% of 2p, 71.6% of 3p, and 80.2% of 4p g
  - *Ruling:* Add to setup: 'While dealing starting hands and the initial market, set aside any instant that appears and deal a replacement; shuffle the set-aside instants back into the deck before the first turn. Instants never fire during setup and can never be in a player's hand.'
- **[high] Dominant strategy: pure racing — attacks are tempo-negative public goods, so decisions collapse**
  - You need only 9 pips (3-3-3 to 6-6-6) and 30 of 66 cards advance your own dice (+1 x14, +2 x10, DUAL x6). A SMASH costs your card+action to set ONE rival back 2 pips; a +2 advances you the same 2 pips — and in 3-4p, attacking the leader is a public good your other rivals free-ride on (classic multiplayer underinvestment). SMASH x5 and TRADE x5 are stone-dead draws until somebody locks. Solved line
  - *Ruling:* Make interaction tempo-positive: rework TRADE to 'SMASH, then +1 one of your own dice' (attack with upside instead of a self-tax) and use DUAL (self+attack) as the template for future cards; trim +1 to ~10 copies and replace with choice-cards. Alternative: bounty rule — whenever your SMASH/TRADE con
- **[high] SMASH treadmill with no game-end backstop: unbounded length, erased-progress feel**
  - Lock -> smashed to 4 -> spend a card+action relocking -> smashed again; the discard reshuffles, so the 10 SMASH/TRADE effects recur forever. In 3-4p the current leader can absorb multiple smashes per round with only 6 shields in the whole deck; the leader mantle just rotates and NOTHING forces convergence — the 15-25 minute target is unenforceable and every smash reads as deleted progress (playtes
  - *Ruling:* Soften and rate-limit: SMASH drops a locked 6 to 5 instead of 4 (one cheap card to recover, progress dented not deleted), and add 'each player may be targeted by at most one SMASH/TRADE between their own turns.' If the treadmill still drags, make locks permanent and move all interaction to pre-lock 
- **[medium] 'Movement cards' never defined — locked-die immunity scope is exploitable (locked-die-at-5 zombie state)**
  - Locked dice are 'immune to movement cards and COLLAPSE, attackable only by SMASH/TRADE'. Which of GAMBLE, REROLL, -2, DUAL's -1, and TRADE's self-cost are 'movement cards'? Rules-lawyer line: TRADE is one of the two cards permitted to touch locked dice, so pay its self-cost with your OWN locked 6 — creating a 'locked die at 5', a state the rules cannot process (SMASH only targets locked 6s; 'drop 
  - *Ruling:* Replace the immunity sentence with an exhaustive rule: 'A locked die can only be changed by SMASH or by the smash half of TRADE; no other card, roll, or instant may target or alter it. TRADE's self-cost must target one of your own UNLOCKED dice.' Delete the undefined term 'movement cards'.
- **[medium] Inconsistent floors/ceilings: COLLAPSE below 1, +2 overflow, and does 'set to 6' lock?**
  - Only -2 states 'floor 1' and only +1 states 'overflow wasted'. Unstated: COLLAPSE -1 on a die showing 1 (a d6 physically cannot show 0), DUAL's -1 and TRADE's self -1 at 1, and +2/DUAL/SURGE on a 5 (7 is impossible). Locking says a die 'reaching 6 locks' — does a die SET to 6 by REROLL, or CLAMPED to 6 by GAMBLE, count as 'reaching' 6? A lawyer argues a set die never 'reached' anything. Every one 
  - *Ruling:* One global rule replacing all per-card text: 'Dice are always clamped to 1-6; movement beyond either bound is wasted. Any die that shows 6 for any reason immediately locks.'
- **[medium] Instant sequencing during refill underdefined; refill-only trigger is a controllable stall lever**
  - (a) When refill flips 2-3 cards, are they flipped simultaneously or one at a time? If SURGE and COLLAPSE both appear, order changes the outcome (5s that lock first become immune to the COLLAPSE). (b) FLOOD mid-refill: does 'discard market' include cards flipped earlier in this same refill? After FLOOD deals 3, what does 'refill continues' mean when the market is already full? (c) Because instants 
  - *Ruling:* State: 'Refill one empty slot at a time, left to right. Each instant resolves completely before the next card is flipped. FLOOD discards ALL face-up market cards (including any flipped this refill), deals 3 new cards one at a time resolving any instants among them, after which the refill is complete
- **[medium] Kingmaking is written into the card text: '+1 any one die', +2 target unspecified, REROLL 'any unlocked die'**
  - +1 literally reads 'move any one die +1' — 14 copies of a legal tool for advancing an OPPONENT'S die. +2 (10 copies) specifies no target at all. REROLL can be aimed at an opponent's die and, if set-to-6 locks (see clamp finding), can lock a die FOR them. In 3-4p a player with no path to victory can openly crown a winner, and 'boost me now, I boost you next game' collusion is rules-legal. Combined 
  - *Ruling:* Errata all targets: '+1/+2/GAMBLE: one of YOUR dice. -2: one opponent's unlocked die. REROLL: one of YOUR unlocked dice. SHIELD: one of YOUR dice.' If cross-targeting is wanted for politics, keep it only on REROLL and add 'an opponent's die set to 6 this way stops at 5 instead.'
- **[medium] DUAL edge cases: no valid -1 target, mandatory halves, resolution order**
  - '+2 own die AND -1 an opponent die' is undefined when every opposing die is locked (immune) or at 1 (floored): unplayable, or playable for the +2 alone? Must both halves resolve ('AND')? In what order? Is the opponent freely chosen? Does its +2 overflow on your 5, and does its -1 floor at 1? This exact situation occurs in every endgame against a 2-locked leader, i.e. precisely when you most want t
  - *Ruling:* 'DUAL: +2 one of your unlocked dice, then -1 one opponent's unlocked die (you choose the opponent), in that order. A half with no legal target is skipped; the card may be played if at least one half has an effect. Global 1-6 clamp applies.'
- **[medium] TRADE edge cases: legality with no locked rivals, self-cost floor, shield interaction**
  - (a) If no rival has a locked 6, is TRADE playable at all or a dead card (5 copies clogging early hands)? (b) The self-cost 'lower one of your own dice by 1' has no stated floor — if it floors at 1, a die parked at 1 makes TRADE a strictly-better free SMASH (see exploit). (c) If the target's SHIELD absorbs the smash half, is the self-cost still paid, or does the whole card fizzle? (d) Per the immun
  - *Ruling:* 'TRADE may only be played if a rival has a locked 6. Its smash half is subject to SHIELD; the self-cost is paid whether or not the smash was absorbed. The self-cost must reduce one of your own UNLOCKED dice by 1; if all your unlocked dice show 1, you cannot play TRADE.'
- **[medium] Action legality gaps: the 3-draw ceiling, impossible actions, and passing**
  - A 2-locked player has 4 actions but the market holds only 3 cards, so at least one action must be a PLAY; with an emptied market and an empty hand the remaining action is simply impossible and the rules give no answer. Also unstated: may you voluntarily pass an action (matters for hand and timing games)? Must all actions be used? May a card drawn this turn be played this turn? 'You never draw from
  - *Ruling:* 'On each action: DRAW a face-up market card, PLAY a card from hand, or PASS. Unused/impossible actions are lost. Cards drawn this turn may be played this turn. The face-down deck is never drawn from directly.'
- **[medium] GAMBLE: pick the die before or after the roll?**
  - 'Roll d6 on own die: 1-3 -> -1, 4-6 -> +2' never fixes the declaration order. Rolling first and assigning afterwards converts push-your-luck into pure upside: a 4-6 goes onto your 4 or 5 (immediate lock), a 1-3 goes onto a die at 1 where the clamp voids the loss. Note also that even played correctly, GAMBLE on a die at 1 is already risk-free by design (floor voids the -1) — probably fine, but the 
  - *Ruling:* 'Name one of your unlocked dice, THEN roll; the result applies only to that die.'
- **[medium] SHIELD underspecified: target, stacking, visibility, and what exactly it absorbs**
  - Unstated: own dice only, or can you shield an opponent's lock (kingmaking)? Can it be placed on an unlocked die in advance? Can two shields stack on one die? Is it public information? Does it persist while the die unlocks and relocks? Does it absorb the entire TRADE or only the smash half (i.e., does the attacker still pay the self-cost — ties into the TRADE finding)?
  - *Ruling:* 'Play SHIELD face up onto one of YOUR dice, locked or not; maximum one shield per die; it is public. It remains until it absorbs the next SMASH/TRADE that targets that die, then both cards go to the discard. It negates only the smash effect; a TRADE attacker still pays the self-cost.'
- **[low] Hand limit only checked at end of turn — overdrawing is a free filter**
  - During your turn you can draw to 6-8 cards and discard the worst at end of turn, so the limit never constrains any in-turn decision; DRAW is strictly non-negative and the discard churn accelerates reshuffles (bringing SMASH and instants back faster). The end-of-turn sequence itself (discard to 5 vs. market refill/instants) has no stated order — mostly harmless today, but any future card that cares
  - *Ruling:* 'End of turn, in order: 1) discard down to 5 (owner chooses), 2) refill the market, resolving instants.' If overdraw-filtering dominates playtests, tighten to 'you may not DRAW while holding 5 cards.'
- **[low] No-op plays undefined (burning cards for card-cycling)**
  - May you play -2 onto a die at 1, +1 onto a locked 6, or SMASH into a known SHIELD purely to cycle cards into the discard? Legal no-ops interact with the hand limit, the reshuffle clock, and the parked-1 TRADE exploit; illegal no-ops need a definition of 'legal target'.
  - *Ruling:* 'A card may only be played if it can change the game state. Attacking into a SHIELD is a legal play (the shield's destruction is a state change); explicitly skippable halves (DUAL) are exempt.'
- **[low] Discard pile and reshuffle bookkeeping never defined**
  - The rules reference 'reshuffle discard' and instants being 'discarded', but never establish where played cards go, that spent shields join the discard, that shields IN PLAY (sitting on dice) are excluded from a reshuffle, or what happens when a multi-card deal (FLOOD needs 3, deck holds 2) hits deck exhaustion mid-effect.
  - *Ruling:* 'Played cards, resolved instants, and spent shields go face up to a shared discard pile; shields on dice stay in play. Whenever any draw or deal needs a card from an empty deck, reshuffle the discard immediately and continue the effect.'
- **[low] Setup gaps: turn-order ties, direction of play, first-pick advantage**
  - 'd6 for turn order' handles neither ties nor whether high or low wins, and the direction of play is unstated. In a race with an open market, the first player also gets first pick of the strongest opening cards with zero compensation for later seats.
  - *Ruling:* 'Highest roll goes first; tied players reroll; play proceeds clockwise.' If testing confirms a seat-1 edge, compensate later seats (e.g., seats 3-4 start one die at 4).
- **[low] 2-player mode collapses into a pure race**
  - In 2p every multiplayer pressure valve disappears: no dogpile on the leader, the attack-vs-race exchange is symmetric so smashing is pure tempo loss, DUAL has one forced victim, and SURGE/COLLAPSE swings have no political counterweight. Expected 2p meta: both players ignore ~1/3 of the deck and sprint, which fails the fun test hardest at exactly the easiest player count to test.
  - *Ruling:* Ship a 2p variant line: 'In 2-player games, a connecting SMASH/TRADE also grants the attacker +1 to one die' (restores attack tempo), and consider removing SURGE/COLLAPSE from the 2p deck.

## Exploits catalogued

- **5-5-5 SURGE lottery camp** — Never lock voluntarily. Park all three dice at 5 (stop playing +1s, GAMBLE only low dice), hoard pluses, and draw from the market every turn to force refill flips. The moment SURGE flips — at the end of ANYONE'S turn — all three 5s lock simultaneousl *Why degenerate:* Optimal endgame play is to stop playing the race and wait for a 2-in-66 recurring lottery ticket. If two players camp (they will — see burst-lock meta), SURGE ends the game in a simultaneous win the r
- **Leader instant-fishing via market drain** — With 2 dice locked (4 actions), draw all 3 face-up cards every turn regardless of quality and discard the junk at the hand limit. Your end-of-turn refill now flips 3 fresh cards every turn — maximum instant frequency exactly when instants cannot hurt *Why degenerate:* The 'random' global events become a leader-controlled engine: the player the instants already favor also decides how often they fire (a trailing player can conversely starve flips by playing from hand
- **Turtle race: never attack** — Draft and play only +2/+1/DUAL/GAMBLE on yourself; treat SMASH/TRADE as dead cards (they literally are until someone locks, and tempo-negative afterwards); hold at most one SMASH as insurance against a player at 1-2 locks with high dice; otherwise sp *Why degenerate:* In 3-4p attacking is a public good — your card and action, everyone else's benefit — so under-attacking is individually rational and racing dominates. 30 of 66 cards support the sprint. Every turn bec
- **Burst-lock meta, preemptive dogpile, and the spite-stall pact** — Because the third lock wins instantly with no reaction window, visible progress is a target: never lock early. Sit at 5-5-x, then explode — from 6L-5-5 with 3 actions, two +1s win on the spot; opponents' only counter is smashing anyone at 1-2 locks O *Why degenerate:* The game's stated goal (lock dice) is strictly punished when pursued incrementally; correct play is hiding progress at 5s — which feeds the SURGE lottery — while correct counterplay is a preemptive sm
- **Kingmaker pump** — A player with no path to victory spends every action playing '+1 any one die' (x14, rules-legal on opponents' dice), +2 if its unspecified target inherits 'any', REROLLs on an ally's low dice, and SHIELDs onto the chosen leader's locks — openly decid *Why degenerate:* Kingmaking isn't an emergent politics problem here; it is printed on a third of the deck via sloppy targeting text. In 3-4p the player who has already lost, not the contenders, determines the result.
- **Parked-1 free TRADE** — Keep one die at 1 (COLLAPSE and failed GAMBLEs will oblige). Every TRADE now reads 'SMASH a locked 6, pay nothing': assign the -1 self-cost to the die at 1, where the (unstated but implied) floor voids it. Bonus: GAMBLE on that same die is pure upsid *Why degenerate:* Turns the game's only costed attack into a strictly better SMASH through an unstated floor, and rewards deliberately crippling a die in a game that is entirely about raising dice.
- **GAMBLE roll-then-assign** — Announce GAMBLE without naming a die (the text never requires it), roll the d6, then assign the result: 4-6 puts +2 on your 4 or 5 for an instant lock; 1-3 puts -1 on your die at 1 where the clamp voids it. *Why degenerate:* A sequencing hole converts a push-your-luck card into 4 copies of 'flip a coin: lock a die or lose nothing' — strictly better than +1 and better than most +2 plays, with the 'gamble' removed.
- **Overdraw filter** — With 3-4 actions, spend every spare action drawing market cards you don't even want, then discard down to the best 5 at end of turn. You cherry-pick the deck faster than anyone, deny nothing (market refills anyway), and the limit never bites mid-turn *Why degenerate:* The end-of-turn-only hand limit makes DRAW strictly non-negative and removes all hand-management tension — and since actions scale with locks, the leader filters fastest, adding yet another compoundin

## Fun-theory diagnosis

- **Runaway leader in 2p / forced-policing stall in 3-4p (one escalator, two failure modes)**
  - cause: Action escalator 2/3/4 keyed to locked dice, combined with locked dice being immune to 56 of 66 cards. In 2p nobody can police efficiently, so first lock snowballs; in 3-4p the leader is so scary (P(win|2 locks)=0.46 even under full policing, vs 0.25 baseline) that smashing them becomes mandatory, c
  - measurable signature: Sim (greedy bots, 2500 games/config): 2p P(win|first locker)=0.66 and P(win|first to 2 locks)=0.82 (thresholds >0.6/>0.75 CONFIRMED); 2p first-seat win rate 0.62 (turn-order coin flip decides ~12% of matches). 4p: when everyone polices, game length doubles from 6.3 rounds (pure racers) to 13.2 round
- **Policing is a public-goods trap: interacting with the game is a losing strategy**
  - cause: SMASH/TRADE cost the attacker ~2 actions (draw+play) and advance the attacker's own race zero pips; the benefit of stopping the leader is split among all free-riding rivals.
  - measurable signature: Sim: a lone tactical bot among 3 pure racers wins only 20% (below 25% baseline — attacking pays negative); a lone pure racer among 3 policers wins 7% (gets focused, never shields). Confirm threshold: |win(policer) − 1/n| and |win(racer) − 1/n| both > 4pp in opposite directions = strategy landscape i
- **SMASH treadmill: progress is erased, standings don't move, playtime balloons**
  - cause: Smashed 6 drops to 4 and the leader repairs it with a single +2 (holding 3-4 actions); attack and repair are a 1:1 action exchange with zero net displacement.
  - measurable signature: Sim: 43% (4p) to 51% (2p) of smashes are re-locked within the victim's very next turn (threshold >40% CONFIRMED); the eventual winner absorbs 2.1 smashes on average and wins anyway; 10.8 smashes/game inflate 4p to 51 turns ≈ 38-50 min at 45-60s/turn — double the 15-25 min target.
- **Authorless global swings: SURGE/COLLAPSE resolve with literally zero human decisions**
  - cause: Instants fire mid-refill at the end of a turn — cannot be held, timed, aimed, dodged, or responded to; no anticipation window because the deck is face-down until the moment of detonation.
  - measurable signature: Sim 4p: 28.7% of ALL pip movement comes from instants (surge 16.1% + collapse 12.6%) — over a quarter of the game's physics has no author (threshold >15% CONFIRMED); SURGE delivers the game-winning lock in 5.0-7.7% of games (~1 ending in 15 is a coin from the sky); 0.89 surge-locks/game.
- **COLLAPSE is a regressive tax — the game's only 'catch-up' randomness actually catches DOWN**
  - cause: COLLAPSE hits only unlocked dice; leaders have locked (immune) pips while trailers hold everything unlocked, so the bomb lands hardest on last place.
  - measurable signature: Sim 4p: average collapse burn by rank = 1.70 pips (leader) vs 2.48 pips (last place) — each COLLAPSE widens the leader-vs-last gap by ~0.8 pips (threshold: E[gap change|COLLAPSE] > 0 CONFIRMED). Compounded by the escalator: leader nets 1.34 pips per own turn vs 1.03 for last place.
- **Low meaningful-decision density: the race layer plays itself**
  - cause: 30/66 cards are '+X, put it on your lowest die' with no tradeoff; the 3-card market rarely presents a real fork; GAMBLE (EV +0.5) is strictly dominated by +1/+2 so the interesting card is never correct.
  - measurable signature: Sim: a bot that ONLY drafts and plays plus-cards hits 26.7% per-capita wins vs 20% for the full-tactics bot — ignoring every decision layer BEATS engaging with it. Pure racers also expose the dead-market problem: 18% of their actions are dead (nothing improving available) and 10% of whole turns cont
- **Designed climaxes never fire: shields never 'block', gambles never happen, endings arrive as bookkeeping**
  - cause: SHIELD is open information, so attackers simply route around it (pure deterrence, never a reveal); GAMBLE's coin-flip-lock thrill at 5 is dominated by sure locks; the 4-action finisher can jump from 1 lock + low die to victory in one turn with no warning.
  - measurable signature: Sim: shield blocks per game = 0.00 across all 12,500 games while 3.7 shields/game get placed (threshold blocks<0.1 CONFIRMED); GAMBLE-on-a-5 occurs 0.28x/game; photo-finish endings (runner-up at 2 locks, die>=4 at game end) only 11% (2p) / 23% (4p); only 29% of 4p wins were telegraphed a full turn a

### Designed climaxes and how often they actually fire

- The match-point SMASH: ripping the leader's locked 6 off the table the turn before they would win — the 'Devil reneges on the contract' spike, and the game's intended signature interaction. — *Attempted 3.4x/game in 4p (sim), but 43% are repaired within the victim's next turn, so a smash that actually STICKS and*
- GAMBLE on a die at 5: a public coin flip for an instant lock — the purest push-your-luck, lean-in, table-holds-breath beat the design contains. — *0.20-0.28x/game (sim) — nearly extinct, because a sure +1/+2 is always the better play; it only appears as a desperation*
- REROLL drama, both flavors: the hail-mary (own die at 1 rolled into a 6, instant lock) and the backfire comedy (rerolling an opponent's 5 straight into a 6, locking it FOR them). — *Self-jackpot 0.37-0.70x/game; enemy-lock backfire 0.06-0.18x/game (sim). The backfire is the funniest emergent moment in*
- SURGE mass-lock: the bell tolls, every die on the table ticks up, and multiple 5s slam to 6 simultaneously — a shared jackpot/groan. — *SURGE fires 1.3-2.6x/game, but a true mass-lock (2+ dice locking at once) only 0.02-0.18x/game, and in ~5-8% of games it*
- The photo finish: two players at 2 locks each, racing a single unlocked die over the last round — the core race fantasy the title promises. — *23% of 4p games, 17% of 3p, just 11% of 2p (sim). The majority experience is a foregone conclusion; ironically pure-race*
- The SHIELD reveal — 'you smash my 6... BLOCKED.' A designed gotcha with token flourish. — *0.00x/game across 12,500 simulated games. Because shields are open information, attackers route around them; the moment *
- FLOOD chain: the market wipes and re-deals, occasionally chaining into a second flood or detonating a surge — a brief 'whoa' of churn. — *1.1-2.4x/game (sim), but it carries no decision for anyone; pure light show, ~5 seconds of novelty per occurrence.*

### Fun opportunities proposed

- **OMENS ON THE ALTAR — instants stop firing on reveal. A revealed SURGE/COLLAPSE is placed face-up on an 'Altar' space wit** — Converts the game's worst offender (authorless 29%-of-all-movement swings) into its best tension engine: everyone sees the COLLAPSE coming and sprints to lock before midnight, or sees SURGE coming and races to park dice  *(cost: Zero new cards; one Altar space (any card-sized area) + the existing spare d6 as the fuse marker; ~3 sentences of rules.)*
- **SOUL HARVEST — SMASH steals progress instead of deleting it: the victim's locked 6 drops to 4 as before, AND the attacke** — Fixes the confirmed public-goods trap (sole policer wins 20% < 25% baseline) and the treadmill in one line: attacking now advances your own damnation, so policing the leader is profitable instead of martyrdom, games shor *(cost: Errata text on 10 existing cards (5 SMASH, 5 TRADE); zero components; zero added rules overhead. Predicted sim signature)*
- **THE PACT DRAINS YOU — invert the escalator: actions are 3 / 3 / 2 for 0 / 1 / 2 locked dice ('each sealed pact devours p** — Kills both failure modes at once: the 2p snowball (0.66/0.82 first-lock conversion) and the 3-4p mandatory-policing stall, because a 2-lock leader with 2 actions is catchable without table-wide dogpiling. Compresses endi *(cost: Reprint one row on the player board + 1 token; zero new cards. Design risk to watch in sim: sandbagging at 1 lock — miti)*
- **DEAL WITH THE DEVIL — new universal action: draw the top card of the deck FACE DOWN (blind) instead of from the market. ** — Adds the missing opt-in push-your-luck channel (Lazzaro hard fun): blind-drawing is a gamble you author, so instants gain an author to cheer or blame (people fun). Also drains the dead-market problem (racers currently wa *(cost: One rule (~2 sentences); zero components. Synergizes with the Altar variant (blind-drawn instants can skip the Altar and)*
- **THE INK DRIES AT MIDNIGHT — locking your third die no longer wins instantly. You declare 'the contract is signed'; you w** — Manufactures the guaranteed climax the game currently rolls dice for: every single game now ends in a one-round desperation window where the table digs for smashes, held shields finally get their 'BLOCKED!' reveal (curre *(cost: One rule; adds ~1 round of length (offset by Soul Harvest/escalator fixes shortening the midgame). Pairs with a micro-fi)*

## Math audit

- `deck_gross_progress_pips_per_cycle` = **+54**
- `deck_attack_pips_per_cycle` = **-43 raw / ≈-30 realistic**
- `deck_net_pips_per_cycle` = **+11 raw, +17..+24 realistic (0.17-0.36 net pips/card)**
- `pips_demanded` = **18 / 27 / 36 (2/3/4P full); ≈14 / 20 / 25 to actually end the game**
- `reshuffles_per_game` = **2P: 0-1, 3P: ~1 (0-2), 4P: 1-2 (2-3 if attack-heavy)**
- `collapse_burn` = **mid-game 4/6/8 pips (2/3/4P); early 6/9/12; trailer -3 vs leader -1 (3x)**
- `p_instant_per_market_flip` = **6/66 = 9.1%**
- `expected_flips_per_turn` = **~1.25 (range 1-2)**
- `p_instant_per_round_3P` = **≈30% (25-35%)**
- `p_instant_per_round_4P` = **≈38% (32-44%)**
- `gamble_ev_and_lock_by_value` = **EV: v1 +1.0, v2 +0.5, v3 +0.5, v4 +0.5, v5 0.0; P(lock): 0/0/0/50%/50%**
- `reroll_own_ev` = **EV = 3.5-v: +2.5/+1.5/+0.5/-0.5/-1.5 for v=1..5; P(lock)=1/6=16.7%**
- `reroll_offensive_on_opponent_5` = **EV -1.5 for them, but 16.7% backfire LOCKS their die; given no 6, E=-2.0**
- `pips_per_turn_by_actions` = **1.42 / 2.13 / 2.84 at 2/3/4 actions (pessimistic mix: 0.90/1.35/1.80)**
- `runaway_speed_ratio` = **6.0x**
- `compounding_win_path` = **4.6 turns (with 2→3→4 scaling) vs 6.3 turns flat = 28% acceleration for the leader only**
- `p_surge_locks_leader_die` = **55.6% naive; 87.7% (3P) / 92.6% (4P) conditioned on actually leading; instant WIN 1/3 if leader has 2 locks**
- `p_surge_locks_any_die` = **91.2% (3P) / 96.1% (4P); E[dice locked] = 2.0 / 2.7**

### Math conclusions

- The economy is the core problem, not just the instants: the deck prints +54 progress pips but -43 attack pips per cycle (net +11 raw, +17-24 with shields), against a demand of 18-36. Interaction is pure deletion, so the harder players interact, the longer the game grinds — 4P needs ~1.5-2.3 deck cycles (~55-120 player-turns), blowing past the 15-25 min target, while 2P barely reshuffles. The SMASH treadmill (lock → -2 → relock) is mathematically structural: 10 SMASH/TRADE cards erase up to 20 pips/cycle and are the game's ONLY catch-up mechanism.
- Playtest verdict on instants is CONFIRMED numerically. A global instant fires every ~2-3 rounds (30% per round at 3P, 38% at 4P; exactly 6 per deck cycle) with zero player agency. SURGE locks at least one die for the actual pip-leader ~88-93% of the time it fires mid-game and outright WINS the game 1/3 of the time the leader is on 2 locks. COLLAPSE burns 6-12 pips and is regressive: a 0-locked trailer loses 3 pips while a 2-locked leader loses 1. Fix: cut SURGE/COLLAPSE or make them held, targeted, or telegraphed (e.g. visible one round ahead) so they become decisions.
- Runaway leader is real and severe: the 2/3/4 action scaling means the leader's pip rate doubles exactly as their remaining distance shrinks to a third — a 2-locked player closes their last 3 pips 6.0x faster than a fresh player closes 9. Because the only brake is the SMASH treadmill, the game bifurcates into 'leader snowballs in ~5 turns' or 'table gangs up and progress stalemates' — both feel bad. Flatten to 3 actions always, or invert (locked dice cost actions), or make extra actions draw-only.
- The fun seed already in the box is the push-your-luck micro-layer, and it is well-tuned: GAMBLE has a real texture (free +EV at 1, coin-flip lock at 4-5, and the non-obvious fact that gambling a 4 strictly dominates gambling a 5), and REROLL splits into rescue (+EV only at v≤3) vs a trap offensive mode (on an enemy 5 it is dominated by -2 and backfires into a lock 1/6). These personal, chosen risks are where the fun should come from — the global instants are randomness at the wrong layer (unchosen, untimed, table-wide) and drown these decisions out.
- Concrete redesign directions implied by the math: (1) convert SMASH/TRADE toward steal/swap effects that MOVE pips instead of deleting them — this simultaneously fixes the treadmill feel and lifts net supply so 3-4P games fit the time box; (2) trim the attack suite or boost +2/DUAL counts so net pips/cycle reaches ~30+ (one cycle ≈ one 3P game); (3) keep GAMBLE/REROLL and consider more cards in that risk-choice family; (4) any global event should be a held card someone chooses to detonate, so the swing has an author.
#!/usr/bin/env python3
"""666 — Monte-Carlo simulator for rules v1 + variant knobs.

Usage:
  python3 sim666.py --games 3000 --players 4                    # baseline raw
  python3 sim666.py --config '{"instants":"omen"}' --games 3000
  python3 sim666.py --suite baseline --out ../results/baseline.json
  python3 sim666.py --verbose 2 --seed 7                        # narrative logs
  python3 sim666.py --selftest
"""
import argparse
import json
import random
import statistics
import sys

# ---------------------------------------------------------------- config

BASE_DECK = {
    "P1": 14, "P2": 10, "M2": 6, "DUAL": 6, "SHIELD": 6,
    "SMASH": 5, "TRADE": 5, "GAMBLE": 4, "REROLL": 4,
    "SURGE": 2, "COLLAPSE": 2, "FLOOD": 2,
}
INSTANTS = {"SURGE", "COLLAPSE", "FLOOD"}

DEFAULT_CFG = {
    "players": 4,
    # instants: raw | none | choice | omen | catchup | personal
    "instants": "raw",
    # actions by own locked count [0,1,2]
    "momentum": [2, 3, 4],
    # +1 action when strictly last by progress
    "catchup_bonus": 0,
    # lock_mode: auto (6 locks immediately) | action (locking costs 1 action)
    "lock_mode": "auto",
    "market_slots": 3,
    "blind_draw": False,          # allow drawing top of deck as an action
    "hand_limit": 5,
    "deck_overrides": {},         # e.g. {"SMASH": 6}
    "instant_replacement": {"P1": 3, "M2": 3},   # used when instants == "none"
    "max_rounds": 60,
    # --- iteration-2 knobs ---
    "smash_bounty": 0,       # 1: successful SMASH/TRADE also +1 attacker's lowest unlocked die
    "smash_to": 4,           # value a smashed 6 drops to (5 = softer treadmill)
    "attack_rate_limit": 0,  # 1: each player absorbs max 1 SMASH/TRADE between own turns
    "win_delay": 0,          # 1: 3rd lock wins at START of your next turn (one last window)
    "shield_hidden": 0,      # 1: shields are face-down; attackers can't route around them
    # shield_mode: "open" = v1 codified (placed on a die in advance)
    #              "reaction" = played from HAND when attacked, cancels the hit
    "shield_mode": "open",
    # --- ruleset: "v1" (pptx codified) | "ivan" (666 - Rules.docx, 2026-08-26) ---
    "ruleset": "v1",
    "basic_split": [15, 14],      # ivan: counts of B1 (+/-1) and B2 (+/-2), total 29
    "dual_spec": [1, 1],          # ivan: DUAL = +a own / -b opponent
    "effects": {"SMASH": 3, "SHIELD": 3, "GAMBLE": 3, "REROLL": 3},  # ivan: the 12 effect cards
    "lock_free_draw": 0,          # ivan: draw a free card when you lock a die
    "draw_block_at_limit": 0,     # ivan: at 5 cards the draw action is illegal
    "minus_limit": 0,             # >0: max subtract-plays (basic/dual) per turn
    "basic_flexible": 1,          # ivan: 0 = basics are plus-only
    "minus_floor": 1,             # basic/dual minus only on dice >= this value
    "seat_comp": 0,               # 1: seats before the last start with +1 card (4P: seats 0-2)
    "tempt": 0,                   # 1: TEMPT THE DEVIL action (demonic die with memory)
    "dual_minus_floor": 2,        # DUAL's minus half may target dice >= this
    "smash_is_minus": 0,          # 1: SMASH/TRADE counts toward the minus_limit
}

IVAN_DEFAULTS = {
    "momentum": [2, 3, 3],        # +1 action while holding at least one 6
    "lock_free_draw": 1,
    "draw_block_at_limit": 1,
    "instants": "none",
    "shield_mode": "reaction",
    "hand_limit": 5,
}

LOCK_BONUS = 3.5
WIN_SCORE = 100.0
OPP_W = 0.8

# ---------------------------------------------------------------- helpers


def make_cfg(overrides):
    cfg = dict(DEFAULT_CFG)
    ov = dict(overrides or {})
    if ov.get("ruleset") == "ivan":
        base = dict(IVAN_DEFAULTS)
        base.update(ov)
        ov = base
    cfg.update(ov)
    return cfg


def build_deck(cfg):
    if cfg["ruleset"] == "ivan":
        d = {"B1": cfg["basic_split"][0], "B2": cfg["basic_split"][1],
             "DUAL": 11}
        for k, v in cfg["effects"].items():
            d[k] = d.get(k, 0) + v
        deck = []
        for k, v in d.items():
            deck.extend([k] * v)
        assert len(deck) == 52, f"ivan deck must be 52, got {len(deck)}"
        return deck
    d = dict(BASE_DECK)
    d.update(cfg["deck_overrides"])
    if cfg["instants"] == "none":
        removed = sum(d.get(k, 0) for k in INSTANTS)
        for k in INSTANTS:
            d[k] = 0
        added = 0
        for k, v in cfg["instant_replacement"].items():
            d[k] = d.get(k, 0) + v
            added += v
        assert added == removed, "instant replacement must keep deck size"
    deck = []
    for k, v in d.items():
        deck.extend([k] * v)
    return deck


class Player:
    __slots__ = ("i", "dice", "locked", "shield", "hand", "bot",
                 "instant_pips", "attacks_taken", "noimp", "turns",
                 "hits_window")

    def __init__(self, i, bot):
        self.i = i
        self.dice = [3, 3, 3]
        self.locked = [False, False, False]
        self.shield = [False, False, False]
        self.hand = []
        self.bot = bot                      # "smart" | "random"
        self.instant_pips = 0
        self.attacks_taken = 0
        self.noimp = 0
        self.turns = 0
        self.hits_window = 0

    @property
    def locks(self):
        return sum(self.locked)

    def unlocked(self):
        return [k for k in range(3) if not self.locked[k]]

    def progress(self):
        return sum(self.dice) + LOCK_BONUS * self.locks

    def pips_to_win(self):
        return sum(6 - self.dice[k] for k in range(3) if not self.locked[k])


class Game:
    def __init__(self, cfg, bots, seed, log=False):
        self.cfg = cfg
        self.rng = random.Random(seed)
        self.players = [Player(i, b) for i, b in enumerate(bots)]
        self.deck = build_deck(cfg)
        self.rng.shuffle(self.deck)
        self.discard = []
        self.market = []
        self.omens = []          # list of (card, owner_idx)
        self.over = False
        self.winner = None
        self.round = 0
        self.turn_count = 0
        self.lead_changes = 0
        self.leader = None
        self.mid_ranks = None
        self.winner_lock_source = None      # 'play'|'SURGE'|'REROLL'|...
        self.pending_win = {}               # idx -> source (win_delay mode)
        self.win_denied = 0                 # pending wins broken by the table
        self.shield_blocks = 0
        self.gamble_plays = 0
        self.reroll_plays = 0
        self.turn_minus_used = 0
        self.demon_face = 3
        self.turn_tempted = False
        self.tempt_plays = 0
        self.log = [] if log else None
        self.reshuffles = 0
        self._setup()

    # ------------------------------------------------ setup / deck

    def _setup(self):
        held = []
        for p in self.players:
            while len(p.hand) < 3:
                c = self._draw_raw()
                if c in INSTANTS:
                    held.append(c)
                else:
                    p.hand.append(c)
        while len(self.market) < self.cfg["market_slots"]:
            c = self._draw_raw()
            if c in INSTANTS:
                held.append(c)
            else:
                self.market.append(c)
        self.deck.extend(held)
        self.rng.shuffle(self.deck)
        if self.cfg["seat_comp"]:
            n = len(self.players)
            if self.cfg["seat_comp"] == 2:
                extra = [max(0, n - 2 - i) for i in range(n)]
                extra[0] = min(extra[0], 2)
            else:
                extra = [1] * (n - 1) + [0]
            for p, e in zip(self.players, extra):
                for _ in range(e):
                    c = self._draw_raw()
                    if c is not None and c not in INSTANTS:
                        p.hand.append(c)
                    elif c is not None:
                        self.deck.append(c)
                        self.rng.shuffle(self.deck)
        self.leader = None

    def _draw_raw(self):
        if not self.deck:
            if not self.discard:
                return None
            self.deck = self.discard
            self.discard = []
            self.rng.shuffle(self.deck)
            self.reshuffles += 1
        return self.deck.pop()

    def _log(self, msg):
        if self.log is not None:
            self.log.append(msg)

    def _state_str(self):
        parts = []
        for p in self.players:
            ds = ",".join(f"{v}{'L' if l else ''}{'s' if s else ''}"
                          for v, l, s in zip(p.dice, p.locked, p.shield))
            parts.append(f"P{p.i}[{ds}|h{len(p.hand)}]")
        return " ".join(parts)

    # ------------------------------------------------ dice mutation

    def _set_die(self, p, k, v, source):
        v = max(1, min(6, v))
        p.dice[k] = v
        if self.cfg["lock_mode"] == "auto":
            if v == 6 and not p.locked[k]:
                p.locked[k] = True
                self._log(f"    P{p.i} locks die{k} ({source})")
                if (self.cfg["lock_free_draw"]
                        and len(p.hand) < self.cfg["hand_limit"]):
                    c = self._draw_raw()
                    if c is not None:
                        p.hand.append(c)
                        self._log(f"      free draw for locking")
                self._check_win(p, source)
        if v < 6 and p.locked[k]:
            p.locked[k] = False
            p.shield[k] = False
            if p.i in self.pending_win:
                del self.pending_win[p.i]
                self.win_denied += 1
                self._log(f"    P{p.i}'s pending win is BROKEN")

    def _check_win(self, p, source):
        if p.locks == 3 and not self.over:
            if self.cfg["win_delay"]:
                if p.i not in self.pending_win:
                    self.pending_win[p.i] = source
                    self._log(f"    P{p.i} SIGNS THE CONTRACT — wins at next turn start")
            else:
                self.over = True
                self.winner = p.i
                self.winner_lock_source = source

    def _move_die(self, p, k, delta, source):
        if p.locked[k]:
            return 0
        old = p.dice[k]
        self._set_die(p, k, old + delta, source)
        return p.dice[k] - old

    # ------------------------------------------------ instants

    def _resolve_instant(self, card, revealer):
        mode = self.cfg["instants"]
        self._log(f"  !! {card} fires (mode={mode}, revealer P{revealer})")
        if card == "FLOOD":
            self.discard.extend(self.market)
            self.market = []
            return
        if mode == "omen":
            self.omens.append((card, revealer))
            self._log(f"     omen pending: {card} owner P{revealer}")
            return
        self._apply_instant_effect(card, revealer, mode)

    def _apply_instant_effect(self, card, revealer, mode):
        ps = self.players
        if mode == "personal":
            targets = [ps[revealer]]
        elif mode == "catchup":
            if card == "SURGE":
                m = min(p.locks for p in ps)
                targets = [p for p in ps if p.locks == m]
            else:
                m = max(p.locks for p in ps)
                targets = [p for p in ps if p.locks == m]
        elif mode == "choice":
            self._instant_choice(card, revealer)
            return
        else:  # raw / omen firing
            targets = ps
        for p in targets:
            for k in p.unlocked():
                d = self._move_die(p, k, +1 if card == "SURGE" else -1, card)
                p.instant_pips += d
                if self.over:
                    return

    def _instant_choice(self, card, revealer):
        """Revealer decides. SURGE: +1 to two different own unlocked dice.
        COLLAPSE: -2 to one opponent unlocked die."""
        me = self.players[revealer]
        if card == "SURGE":
            picks = sorted(me.unlocked(), key=lambda k: -me.dice[k])[:2]
            for k in picks:
                d = self._move_die(me, k, +1, "SURGE")
                me.instant_pips += d
                if self.over:
                    return
        else:
            best, bk = None, None
            for p in self.players:
                if p.i == revealer:
                    continue
                for k in p.unlocked():
                    key = (p.progress(), p.dice[k])
                    if best is None or key > best:
                        best, bk = key, (p, k)
            if bk:
                p, k = bk
                d = self._move_die(p, k, -2, "COLLAPSE")
                p.instant_pips += d
                p.attacks_taken += 1

    def _fire_omens_for(self, idx):
        due = [o for o in self.omens if o[1] == idx]
        self.omens = [o for o in self.omens if o[1] != idx]
        for card, owner in due:
            self._log(f"  !! omen {card} (owner P{owner}) fires")
            self._apply_instant_effect(card, owner, "raw")
            self.discard.append(card)
            if self.over:
                return

    # ------------------------------------------------ market

    def refill_market(self, revealer):
        guard = 0
        while len(self.market) < self.cfg["market_slots"] and guard < 200:
            guard += 1
            c = self._draw_raw()
            if c is None:
                break
            if c in INSTANTS and self.cfg["instants"] != "none":
                self._resolve_instant(c, revealer)
                if c != "FLOOD" and self.cfg["instants"] != "omen":
                    self.discard.append(c)
                elif c == "FLOOD":
                    self.discard.append(c)
                if self.over:
                    return
            else:
                self.market.append(c)

    # ------------------------------------------------ legal actions

    def legal_actions(self, p):
        acts = []
        for hi, c in enumerate(p.hand):
            acts.extend(self._card_actions(p, hi, c))
        if not (self.cfg["draw_block_at_limit"]
                and len(p.hand) >= self.cfg["hand_limit"]):
            for mi, c in enumerate(self.market):
                acts.append(("draw", mi))
        if self.cfg["blind_draw"] and (self.deck or self.discard):
            acts.append(("blind",))
        if self.cfg["lock_mode"] == "action":
            for k in range(3):
                if p.dice[k] == 6 and not p.locked[k]:
                    acts.append(("lock", k))
        if (self.cfg["tempt"] and not self.turn_tempted
                and p.unlocked()):
            acts.append(("tempt",))
        if self.omens:
            acts.append(("defuse", 0))
        if not acts:
            acts.append(("pass",))
        return acts

    def _card_actions(self, p, hi, c):
        out = []
        opps = [q for q in self.players if q.i != p.i]
        if c in ("B1", "B2"):
            v = 1 if c == "B1" else 2
            for k in p.unlocked():
                if p.dice[k] < 6:
                    out.append(("play", hi, c, ("plus", p.i, k)))
            lim = self.cfg["minus_limit"]
            minus_ok = (self.cfg["basic_flexible"]
                        and (not lim or self.turn_minus_used < lim))
            if minus_ok:
                fl = max(2, self.cfg["minus_floor"])
                for q in opps:
                    for k in q.unlocked():
                        if q.dice[k] >= fl:
                            out.append(("play", hi, c, ("minus", q.i, k)))
        elif c in ("P1", "P2"):
            for k in p.unlocked():
                if p.dice[k] < 6:
                    out.append(("play", hi, c, (p.i, k)))
        elif c == "M2":
            for q in opps:
                for k in q.unlocked():
                    if q.dice[k] > 1:
                        out.append(("play", hi, c, (q.i, k)))
        elif c == "DUAL" and self.cfg["ruleset"] == "ivan":
            own = [k for k in p.unlocked() if p.dice[k] < 6]
            lim = self.cfg["minus_limit"]
            block_minus = lim and self.turn_minus_used >= lim
            fl = max(2, self.cfg["dual_minus_floor"])
            tg = ([] if block_minus else
                  [(q.i, k) for q in opps for k in q.unlocked() if q.dice[k] >= fl])
            if own and tg:
                for k in own[:3]:
                    for t in tg[:6]:
                        out.append(("play", hi, c, (p.i, k), t))
            elif own:
                for k in own[:3]:
                    out.append(("play", hi, c, (p.i, k), None))
        elif c == "DUAL":
            own = [k for k in p.unlocked() if p.dice[k] < 6]
            tg = [(q.i, k) for q in opps for k in q.unlocked() if q.dice[k] > 1]
            if own and tg:
                for k in own[:3]:
                    for t in tg[:6]:
                        out.append(("play", hi, c, (p.i, k), t))
            elif own:                       # opponent part fizzles
                for k in own[:3]:
                    out.append(("play", hi, c, (p.i, k), None))
        elif c == "SHIELD":
            if self.cfg["shield_mode"] == "open":
                for k in range(3):
                    if p.locked[k] and not p.shield[k]:
                        out.append(("play", hi, c, (p.i, k)))
        elif c in ("SMASH", "TRADE"):
            pay = self._trade_pay_die(p) if c == "TRADE" else 0
            if c == "TRADE" and pay is None:
                return out
            lim = self.cfg["attack_rate_limit"]
            if (self.cfg["smash_is_minus"] and self.cfg["minus_limit"]
                    and self.turn_minus_used >= self.cfg["minus_limit"]):
                return out
            for q in opps:
                if lim and q.hits_window >= lim:
                    continue
                for k in range(3):
                    if q.locked[k]:
                        out.append(("play", hi, c, (q.i, k)))
        elif c == "GAMBLE":
            for k in p.unlocked():
                out.append(("play", hi, c, (p.i, k)))
        elif c == "PACT":
            if len(p.unlocked()) >= 2:
                for k in p.unlocked():
                    out.append(("play", hi, c, (p.i, k)))
        elif c == "IDOL":
            for k in p.unlocked():
                if p.dice[k] != self.demon_face:
                    out.append(("play", hi, c, (p.i, k)))
        elif c == "REROLL":
            for k in p.unlocked():
                if p.dice[k] <= 3:
                    out.append(("play", hi, c, (p.i, k)))
            for q in opps:
                for k in q.unlocked():
                    if q.dice[k] >= 4:
                        out.append(("play", hi, c, (q.i, k)))
        return out

    def _wants_block(self, q):
        if q.bot == "random":
            return self.rng.random() < 0.5
        return True

    def _trade_pay_die(self, p):
        cands = [k for k in p.unlocked() if p.dice[k] > 1]
        if cands:
            return min(cands, key=lambda k: p.dice[k])
        lk = [k for k in range(3) if p.locked[k]]
        return lk[0] if lk else None

    # ------------------------------------------------ scoring (smart bot)

    def _gain_lock(self, p, newv, k):
        g = 0.0
        if newv == 6 and not p.locked[k] and self.cfg["lock_mode"] == "auto":
            g += LOCK_BONUS
            if p.locks == 2:
                g += WIN_SCORE
        return g

    def score_action(self, p, a):
        typ = a[0]
        n = self.rng.random() * 0.06
        leader = max((q for q in self.players if q.i != p.i),
                     key=lambda q: q.progress())
        if typ == "pass":
            return 0.01
        if typ == "lock":
            return LOCK_BONUS + (WIN_SCORE if p.locks == 2 else 0) + n
        if typ == "defuse":
            card = self.omens[0][0]
            if card == "COLLAPSE":
                loss = len(p.unlocked())
                return loss * 0.9 - 1.0 + n
            if card == "SURGE":
                oth_gain = sum(1 for k in leader.unlocked() if leader.dice[k] == 5)
                return oth_gain * 2.0 - 1.0 + n
            return 0.2 + n
        if typ == "tempt":
            f = self.demon_face
            p_up = (6 - f) / 6.0
            p_dn = (f - 1) / 6.0
            best = max((p.dice[k] for k in p.unlocked()), default=1)
            bonus = LOCK_BONUS * p_up if best == 5 else 0
            return p_up * 1.0 - p_dn * 1.1 + bonus * 0.5 + n
        if typ == "blind":
            return 0.55 + n
        if typ == "draw":
            c = self.market[a[1]]
            return self._draw_value(p, c, leader) + n
        # play
        c = a[2]
        if c in ("B1", "B2"):
            v = 1 if c == "B1" else 2
            mode, qi, k = a[3]
            q = self.players[qi]
            if mode == "plus":
                delta = min(6, q.dice[k] + v) - q.dice[k]
                return delta + self._gain_lock(q, q.dice[k] + delta, k) + n
            delta = q.dice[k] - max(1, q.dice[k] - v)
            w = OPP_W * (1.3 if qi == leader.i else 0.6)
            return delta * w + n
        if c in ("P1", "P2"):
            _, k = a[3]
            delta = min(6, p.dice[k] + (1 if c == "P1" else 2)) - p.dice[k]
            return delta + self._gain_lock(p, p.dice[k] + delta, k) + n
        if c == "M2":
            qi, k = a[3]
            q = self.players[qi]
            delta = q.dice[k] - max(1, q.dice[k] - 2)
            w = OPP_W * (1.3 if qi == leader.i else 0.6)
            return delta * w + n
        if c == "DUAL":
            up = self.cfg["dual_spec"][0] if self.cfg["ruleset"] == "ivan" else 2
            _, k = a[3]
            delta = min(6, p.dice[k] + up) - p.dice[k]
            v = delta + self._gain_lock(p, p.dice[k] + delta, k)
            if a[4]:
                qi, kk = a[4]
                q = self.players[qi]
                d2 = q.dice[kk] - max(1, q.dice[kk] - 1)
                v += d2 * OPP_W * (1.2 if qi == leader.i else 0.5)
            return v + n
        if c == "SHIELD":
            return 0.9 + 0.9 * p.locks + (1.2 if p.locks == 2 else 0) + n
        if c in ("SMASH", "TRADE"):
            qi, k = a[3]
            q = self.players[qi]
            shielded = q.shield[k] and not self.cfg["shield_hidden"]
            if self.cfg["shield_mode"] == "reaction":
                shielded = False
            if shielded:
                base = 0.8
            else:
                base = (6 - self.cfg["smash_to"]) + LOCK_BONUS
                if q.i in self.pending_win or q.locks == 3:
                    base += 50
                elif q.locks == 2:
                    base += 6
            v = base * OPP_W * (1.4 if qi == leader.i else 0.7)
            if self.cfg["shield_mode"] == "reaction" and len(q.hand) > 0:
                v *= 0.75
            if self.cfg["smash_bounty"]:
                v += 1.2
            if c == "TRADE":
                pk = self._trade_pay_die(p)
                v -= 1 + (LOCK_BONUS if p.locked[pk] else 0)
            return v + n
        if c == "PACT":
            _, k = a[3]
            v0 = p.dice[k]
            win_part = (6 - v0) + LOCK_BONUS + (WIN_SCORE if p.locks == 2 else 0)
            lose_part = (1 - v0)
            return 0.5 * win_part + 0.5 * lose_part + n
        if c == "IDOL":
            _, k = a[3]
            delta = self.demon_face - p.dice[k]
            return delta + self._gain_lock(p, self.demon_face, k) + n
        if c == "GAMBLE":
            _, k = a[3]
            v0 = p.dice[k]
            up = min(6, v0 + 2)
            dn = max(1, v0 - 1)
            ev = 0.5 * (up - v0) + 0.5 * (dn - v0)
            if up == 6:
                ev += 0.5 * (LOCK_BONUS + (WIN_SCORE if p.locks == 2 else 0))
            return ev + n
        if c == "REROLL":
            qi, k = a[3]
            q = self.players[qi]
            ev = 3.5 - q.dice[k]
            lockp = 1 / 6 * (LOCK_BONUS + (WIN_SCORE if q.locks == 2 else 0))
            if qi == p.i:
                return ev + lockp + n
            return -(ev + lockp) * OPP_W * (1.2 if qi == leader.i else 0.6) + n
        return n

    def _draw_value(self, p, c, leader):
        low = [k for k in p.unlocked() if p.dice[k] <= 4]
        v = {"P1": 1.0, "P2": 1.7 if low else 0.9, "M2": 0.8,
             "B1": 1.1, "B2": 1.8 if low else 1.0,
             "PACT": 1.3, "IDOL": 0.9,
             "DUAL": 1.5, "GAMBLE": 0.9, "REROLL": 0.7,
             "SHIELD": (0.5 + 0.9 * p.locks
                        if self.cfg["shield_mode"] == "reaction"
                        else 0.35 + 0.8 * p.locks),
             "SMASH": 0.3 + 1.5 * leader.locks,
             "TRADE": 0.1 + 1.1 * leader.locks}.get(c, 0.5)
        if len(p.hand) >= self.cfg["hand_limit"]:
            v -= 0.4
        return v * 0.62

    # ------------------------------------------------ applying actions

    def apply(self, p, a):
        typ = a[0]
        if typ == "pass":
            return
        if typ == "lock":
            k = a[1]
            p.locked[k] = True
            self._log(f"    P{p.i} spends action to lock die{k}")
            self._check_win(p, "lock-action")
            return
        if typ == "defuse":
            card, owner = self.omens.pop(0)
            self.discard.append(card)
            self._log(f"    P{p.i} defuses omen {card}")
            return
        if typ == "tempt":
            self.turn_tempted = True
            self.tempt_plays += 1
            roll = self.rng.randint(1, 6)
            f = self.demon_face
            self.demon_face = roll
            if roll > f:
                ks = [k for k in p.unlocked() if p.dice[k] < 6]
                if ks:
                    k = max(ks, key=lambda x: p.dice[x])
                    self._move_die(p, k, 1, "TEMPT")
                    self._log(f"    P{p.i} TEMPTS: {roll}>{f}, +1 die{k} -> {p.dice[k]}")
            elif roll < f:
                ks = [k for k in p.unlocked() if p.dice[k] > 1]
                if ks:
                    k = max(ks, key=lambda x: p.dice[x])
                    self._move_die(p, k, -1, "TEMPT")
                    self._log(f"    P{p.i} TEMPTS: {roll}<{f}, -1 die{k} -> {p.dice[k]}")
            else:
                self._log(f"    P{p.i} TEMPTS: {roll}=={f}, nothing")
            return
        if typ == "draw":
            c = self.market.pop(a[1])
            p.hand.append(c)
            self._log(f"    P{p.i} draws {c} from market")
            return
        if typ == "blind":
            c = self._draw_raw()
            if c is None:
                return
            if c in INSTANTS and self.cfg["instants"] != "none":
                self._log(f"    P{p.i} blind-draws {c}!")
                self._resolve_instant(c, p.i)
                if c != "FLOOD" and self.cfg["instants"] != "omen":
                    self.discard.append(c)
                elif c == "FLOOD":
                    self.discard.append(c)
            else:
                p.hand.append(c)
                self._log(f"    P{p.i} blind-draws a card")
            return
        # play
        hi, c = a[1], a[2]
        p.hand.pop(hi)
        self.discard.append(c)
        if c in ("B1", "B2"):
            v = 1 if c == "B1" else 2
            mode, qi, k = a[3]
            q = self.players[qi]
            if mode == "plus":
                self._move_die(q, k, v, "play")
                self._log(f"    P{p.i} plays +{v} on own die{k} -> {q.dice[k]}")
            else:
                self._move_die(q, k, -v, "attack")
                self.turn_minus_used += 1
                q.attacks_taken += 1
                self._log(f"    P{p.i} plays -{v} on P{qi} die{k} -> {q.dice[k]}")
        elif c in ("P1", "P2"):
            _, k = a[3]
            self._move_die(p, k, 1 if c == "P1" else 2, "play")
            self._log(f"    P{p.i} plays {c} on own die{k} -> {p.dice[k]}")
        elif c == "M2":
            qi, k = a[3]
            q = self.players[qi]
            self._move_die(q, k, -2, "attack")
            q.attacks_taken += 1
            self._log(f"    P{p.i} plays -2 on P{qi} die{k} -> {q.dice[k]}")
        elif c == "DUAL" and self.cfg["ruleset"] == "ivan":
            up, dn = self.cfg["dual_spec"]
            _, k = a[3]
            self._move_die(p, k, up, "play")
            msg = f"    P{p.i} DUAL +{up} own die{k} -> {p.dice[k]}"
            if a[4]:
                qi, kk = a[4]
                q = self.players[qi]
                self._move_die(q, kk, -dn, "attack")
                self.turn_minus_used += 1
                q.attacks_taken += 1
                msg += f", -{dn} P{qi} die{kk} -> {q.dice[kk]}"
            self._log(msg)
        elif c == "DUAL":
            _, k = a[3]
            self._move_die(p, k, 2, "play")
            msg = f"    P{p.i} DUAL +2 own die{k} -> {p.dice[k]}"
            if a[4]:
                qi, kk = a[4]
                q = self.players[qi]
                self._move_die(q, kk, -1, "attack")
                q.attacks_taken += 1
                msg += f", -1 P{qi} die{kk} -> {q.dice[kk]}"
            self._log(msg)
        elif c == "SHIELD":
            _, k = a[3]
            p.shield[k] = True
            self._log(f"    P{p.i} shields die{k}")
        elif c in ("SMASH", "TRADE"):
            qi, k = a[3]
            q = self.players[qi]
            q.hits_window += 1
            if self.cfg["smash_is_minus"]:
                self.turn_minus_used += 1
            if (self.cfg["shield_mode"] == "reaction" and "SHIELD" in q.hand
                    and self._wants_block(q)):
                q.hand.remove("SHIELD")
                self.discard.append("SHIELD")
                self.shield_blocks += 1
                self._log(f"    P{p.i} {c} on P{qi} die{k} — SHIELD from hand, BLOCKED!")
                if c == "TRADE":
                    pk = self._trade_pay_die(p)
                    if pk is not None:
                        self._set_die(p, pk, p.dice[pk] - 1, "trade-cost")
                return
            if q.shield[k]:
                q.shield[k] = False
                self._log(f"    P{p.i} {c} on P{qi} die{k} — SHIELD absorbs")
            else:
                self._set_die(q, k, self.cfg["smash_to"], "attack")
                q.attacks_taken += 1
                self._log(f"    P{p.i} {c} P{qi} die{k} -> {q.dice[k]} (unlocked)")
                if self.cfg["smash_bounty"]:
                    low = [kk for kk in p.unlocked() if p.dice[kk] < 6]
                    if low:
                        kk = min(low, key=lambda x: p.dice[x])
                        self._move_die(p, kk, 1, "bounty")
                        self._log(f"      bounty: own die{kk} -> {p.dice[kk]}")
            if c == "TRADE":
                pk = self._trade_pay_die(p)
                if pk is not None:
                    self._set_die(p, pk, p.dice[pk] - 1, "trade-cost")
                    self._log(f"      TRADE cost: own die{pk} -> {p.dice[pk]}")
        elif c == "PACT":
            self.gamble_plays += 1
            _, k = a[3]
            roll = self.rng.randint(1, 6)
            self.demon_face = roll
            if roll >= 4:
                self._set_die(p, k, 6, "PACT")
                self._log(f"    P{p.i} PACT die{k}: roll {roll} -> LOCKED 6")
            else:
                self._set_die(p, k, 1, "PACT")
                self._log(f"    P{p.i} PACT die{k}: roll {roll} -> 1")
        elif c == "IDOL":
            _, k = a[3]
            self._set_die(p, k, self.demon_face, "IDOL")
            self._log(f"    P{p.i} FALSE IDOL: die{k} -> {self.demon_face}")
        elif c == "GAMBLE":
            self.gamble_plays += 1
            _, k = a[3]
            roll = self.rng.randint(1, 6)
            self.demon_face = roll
            delta = 2 if roll >= 4 else -1
            self._move_die(p, k, delta, "GAMBLE")
            self._log(f"    P{p.i} GAMBLE die{k}: roll {roll} -> {p.dice[k]}")
        elif c == "REROLL":
            self.reroll_plays += 1
            qi, k = a[3]
            q = self.players[qi]
            v = self.rng.randint(1, 6)
            self._set_die(q, k, v, "REROLL")
            if qi != p.i:
                q.attacks_taken += 1
            self._log(f"    P{p.i} REROLL P{qi} die{k} -> {v}")

    # ------------------------------------------------ turn / game loop

    def play_turn(self, p):
        p.turns += 1
        self.turn_count += 1
        p.hits_window = 0
        self.turn_minus_used = 0
        self.turn_tempted = False
        if self.cfg["win_delay"] and p.i in self.pending_win:
            if p.locks == 3:
                self.over = True
                self.winner = p.i
                self.winner_lock_source = self.pending_win[p.i]
                self._log(f"  P{p.i} — the ink dries. WIN.")
                return
            del self.pending_win[p.i]
        self._fire_omens_for(p.i)
        if self.over:
            return
        actions = self.cfg["momentum"][min(p.locks, 2)]
        if self.cfg["catchup_bonus"]:
            prog = [q.progress() for q in self.players]
            if p.progress() < min(x for j, x in enumerate(prog) if j != p.i):
                actions += 1
        self._log(f"  P{p.i} turn ({actions} actions) | {self._state_str()}")
        improving = False
        for _ in range(actions):
            if self.over:
                break
            acts = self.legal_actions(p)
            if p.bot == "random":
                a = self.rng.choice(acts)
            else:
                a = max(acts, key=lambda x: self.score_action(p, x))
            if a[0] == "play" and self.score_action(p, a) > 0.4:
                improving = True
            self.apply(p, a)
        if not improving:
            p.noimp += 1
        while len(p.hand) > self.cfg["hand_limit"]:
            leader = max((q for q in self.players if q.i != p.i),
                         key=lambda q: q.progress())
            worst = min(range(len(p.hand)),
                        key=lambda i: self._draw_value(p, p.hand[i], leader))
            self.discard.append(p.hand.pop(worst))
        if not self.over:
            self.refill_market(p.i)

    def run(self):
        while not self.over and self.round < self.cfg["max_rounds"]:
            self.round += 1
            for p in self.players:
                if self.over:
                    break
                self.play_turn(p)
            if self.over:
                break
            lead = max(self.players, key=lambda q: q.progress()).i
            if self.leader is not None and lead != self.leader and self.round > 1:
                self.lead_changes += 1
            self.leader = lead
            if self.round == 6 and self.mid_ranks is None:
                order = sorted(self.players, key=lambda q: -q.progress())
                self.mid_ranks = {q.i: r for r, q in enumerate(order)}
        return self.metrics()

    def metrics(self):
        stalled = self.winner is None
        losers = [p for p in self.players if p.i != self.winner]
        photo = min((p.pips_to_win() for p in losers), default=0)
        comeback = None
        if not stalled and self.mid_ranks is not None:
            comeback = self.mid_ranks.get(self.winner, 0) != 0
        return {
            "rounds": self.round,
            "turns": self.turn_count,
            "winner": self.winner,
            "stalled": stalled,
            "lead_changes": self.lead_changes,
            "comeback": comeback,
            "photo": photo if not stalled else None,
            "instant_decided": self.winner_lock_source in INSTANTS,
            "instant_pips": sum(abs(p.instant_pips) for p in self.players),
            "attacks": sum(p.attacks_taken for p in self.players),
            "noimp_rate": sum(p.noimp for p in self.players) /
                          max(1, sum(p.turns for p in self.players)),
            "reshuffles": self.reshuffles,
            "shield_blocks": self.shield_blocks,
            "gamble_plays": self.gamble_plays,
            "tempt_plays": self.tempt_plays,
            "reroll_plays": self.reroll_plays,
            "win_denied": self.win_denied,
            "win_source": (None if stalled else self.winner_lock_source),
            "winner_bot": (self.players[self.winner].bot
                           if not stalled else None),
            "winner_first_lock": None,
        }


# ---------------------------------------------------------------- batches

def run_batch(cfg_over, games, mix="smart", seed0=1000, players=None):
    cfg = make_cfg(cfg_over)
    if players:
        cfg["players"] = players
    n = cfg["players"]
    out = []
    for g in range(games):
        if mix == "smart":
            bots = ["smart"] * n
        elif mix == "random":
            bots = ["random"] * n
        else:  # mixed: 1 smart rotating seat
            bots = ["random"] * n
            bots[g % n] = "smart"
        game = Game(cfg, bots, seed0 + g)
        m = game.run()
        m["smart_seat"] = bots.index("smart") if "smart" in bots else None
        out.append(m)
    return aggregate(out, cfg, mix)


def aggregate(ms, cfg, mix):
    n = cfg["players"]
    fin = [m for m in ms if not m["stalled"]]
    seatw = [0] * n
    for m in fin:
        seatw[m["winner"]] += 1
    tot = len(fin) or 1
    agg = {
        "cfg": {k: v for k, v in cfg.items() if k != "instant_replacement"},
        "mix": mix,
        "games": len(ms),
        "stall_pct": 100 * (len(ms) - len(fin)) / len(ms),
        "rounds_med": statistics.median(m["rounds"] for m in fin) if fin else None,
        "rounds_p90": (sorted(m["rounds"] for m in fin)[int(len(fin) * .9)]
                       if fin else None),
        "lead_changes": round(statistics.mean(m["lead_changes"] for m in ms), 2),
        "comeback_pct": (round(100 * statistics.mean(
            1 if m["comeback"] else 0 for m in fin
            if m["comeback"] is not None), 1) if fin else None),
        "photo_med": (statistics.median(m["photo"] for m in fin)
                      if fin else None),
        "photo_close_pct": (round(100 * sum(1 for m in fin if m["photo"] <= 3)
                                  / tot, 1) if fin else None),
        "instant_decided_pct": round(100 * sum(
            1 for m in fin if m["instant_decided"]) / tot, 1),
        "instant_pips_mean": round(statistics.mean(
            m["instant_pips"] for m in ms), 1),
        "attacks_mean": round(statistics.mean(m["attacks"] for m in ms), 1),
        "noimp_pct": round(100 * statistics.mean(m["noimp_rate"] for m in ms), 1),
        "reshuffles_mean": round(statistics.mean(m["reshuffles"] for m in ms), 2),
        "blocks_mean": round(statistics.mean(m["shield_blocks"] for m in ms), 2),
        "gamble_mean": round(statistics.mean(m["gamble_plays"] for m in ms), 2),
        "tempt_mean": round(statistics.mean(m["tempt_plays"] for m in ms), 2),
        "reroll_mean": round(statistics.mean(m["reroll_plays"] for m in ms), 2),
        "demonic_mean": round(statistics.mean(
            m["gamble_plays"] + m["reroll_plays"] for m in ms), 2),
        "win_denied_mean": round(statistics.mean(m["win_denied"] for m in ms), 2),
        "win_by_roll_pct": round(100 * sum(
            1 for m in ms if m.get("win_source") in
            ("PACT", "GAMBLE", "REROLL", "TEMPT")) / max(1, len(
                [m for m in ms if not m["stalled"]])), 1),
        "seat_win_pct": [round(100 * w / tot, 1) for w in seatw],
    }
    if mix == "mixed":
        sw = sum(1 for m in fin
                 if m["winner_bot"] == "smart")
        agg["smart_win_pct"] = round(100 * sw / tot, 1)
    return agg


# ---------------------------------------------------------------- suites

SUITES = {
    "baseline": [
        ("raw_4p", {}, 4, "smart"),
        ("raw_3p", {}, 3, "smart"),
        ("raw_2p", {}, 2, "smart"),
        ("no_instants_4p", {"instants": "none"}, 4, "smart"),
        ("flat_momentum_4p", {"momentum": [3, 3, 3]}, 4, "smart"),
        ("no_inst_flat_4p", {"instants": "none", "momentum": [3, 3, 3]}, 4, "smart"),
        ("raw_4p_agency", {}, 4, "mixed"),
        ("raw_4p_random", {}, 4, "random"),
    ],
}


def selftest():
    for g in range(300):
        cfg = make_cfg({"ruleset": "ivan"})
        game = Game(cfg, ["smart"] * 4, 5000 + g)
        game.run()
        cards = (len(game.deck) + len(game.discard) + len(game.market)
                 + sum(len(p.hand) for p in game.players) + len(game.omens))
        assert cards == 52, f"ivan card leak {cards}"
        for p in game.players:
            assert all(1 <= v <= 6 for v in p.dice)
    print("ivan ruleset OK — 300 games, 52 cards conserved")
    modes = ["raw", "none", "choice", "omen", "catchup", "personal"]
    locks = ["auto", "action"]
    total = 0
    for im in modes:
        for lm in locks:
            cfg = make_cfg({"instants": im, "lock_mode": lm,
                            "blind_draw": im == "personal",
                            "shield_mode": "reaction" if lm == "action" else "open",
                            "win_delay": 1 if im == "omen" else 0})
            for g in range(120):
                game = Game(cfg, ["smart"] * 4, 999 + g)
                game.run()
                cards = (len(game.deck) + len(game.discard) + len(game.market)
                         + sum(len(p.hand) for p in game.players)
                         + len(game.omens))
                assert cards == 66, f"card leak {cards} in {im}/{lm}"
                for p in game.players:
                    for k in range(3):
                        assert 1 <= p.dice[k] <= 6
                        if p.locked[k]:
                            assert p.dice[k] == 6
                total += 1
    print(f"selftest OK — {total} games, cards conserved, dice in range")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="{}")
    ap.add_argument("--games", type=int, default=2000)
    ap.add_argument("--players", type=int, default=None)
    ap.add_argument("--mix", default="smart")
    ap.add_argument("--seed", type=int, default=1000)
    ap.add_argument("--suite", default=None)
    ap.add_argument("--out", default=None)
    ap.add_argument("--verbose", type=int, default=0)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        selftest()
        return

    if args.verbose:
        cfg = make_cfg(json.loads(args.config))
        for i in range(args.verbose):
            g = Game(cfg, ["smart"] * cfg["players"], args.seed + i, log=True)
            m = g.run()
            print(f"=== sample game {i} (seed {args.seed + i}) ===")
            print("\n".join(g.log))
            print(json.dumps(m, indent=1))
        return

    if args.suite:
        results = {}
        for name, over, players, mix in SUITES[args.suite]:
            results[name] = run_batch(over, args.games, mix=mix,
                                      seed0=args.seed, players=players)
            print(f"[{name}] done")
        text = json.dumps(results, indent=1)
        if args.out:
            with open(args.out, "w") as f:
                f.write(text)
        print(text)
        return

    res = run_batch(json.loads(args.config), args.games, mix=args.mix,
                    seed0=args.seed, players=args.players)
    print(json.dumps(res, indent=1))


if __name__ == "__main__":
    main()

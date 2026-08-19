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
}

LOCK_BONUS = 3.5
WIN_SCORE = 100.0
OPP_W = 0.8

# ---------------------------------------------------------------- helpers


def make_cfg(overrides):
    cfg = dict(DEFAULT_CFG)
    cfg.update(overrides or {})
    return cfg


def build_deck(cfg):
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
                 "instant_pips", "attacks_taken", "noimp", "turns")

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
                if p.locks == 3 and not self.over:
                    self.over = True
                    self.winner = p.i
                    self.winner_lock_source = source
        if v < 6 and p.locked[k]:
            p.locked[k] = False
            p.shield[k] = False

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
        for mi, c in enumerate(self.market):
            acts.append(("draw", mi))
        if self.cfg["blind_draw"] and (self.deck or self.discard):
            acts.append(("blind",))
        if self.cfg["lock_mode"] == "action":
            for k in range(3):
                if p.dice[k] == 6 and not p.locked[k]:
                    acts.append(("lock", k))
        if self.omens:
            acts.append(("defuse", 0))
        if not acts:
            acts.append(("pass",))
        return acts

    def _card_actions(self, p, hi, c):
        out = []
        opps = [q for q in self.players if q.i != p.i]
        if c in ("P1", "P2"):
            for k in p.unlocked():
                if p.dice[k] < 6:
                    out.append(("play", hi, c, (p.i, k)))
        elif c == "M2":
            for q in opps:
                for k in q.unlocked():
                    if q.dice[k] > 1:
                        out.append(("play", hi, c, (q.i, k)))
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
            for k in range(3):
                if p.locked[k] and not p.shield[k]:
                    out.append(("play", hi, c, (p.i, k)))
        elif c in ("SMASH", "TRADE"):
            pay = self._trade_pay_die(p) if c == "TRADE" else 0
            if c == "TRADE" and pay is None:
                return out
            for q in opps:
                for k in range(3):
                    if q.locked[k]:
                        out.append(("play", hi, c, (q.i, k)))
        elif c == "GAMBLE":
            for k in p.unlocked():
                out.append(("play", hi, c, (p.i, k)))
        elif c == "REROLL":
            for k in p.unlocked():
                if p.dice[k] <= 3:
                    out.append(("play", hi, c, (p.i, k)))
            for q in opps:
                for k in q.unlocked():
                    if q.dice[k] >= 5:
                        out.append(("play", hi, c, (q.i, k)))
        return out

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
        if typ == "blind":
            return 0.55 + n
        if typ == "draw":
            c = self.market[a[1]]
            return self._draw_value(p, c, leader) + n
        # play
        c = a[2]
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
            _, k = a[3]
            delta = min(6, p.dice[k] + 2) - p.dice[k]
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
            if q.shield[k]:
                base = 0.8
            else:
                base = (2 + LOCK_BONUS)
                if q.locks == 3:
                    base += 50            # deny the win (shouldn't happen)
                elif q.locks == 2:
                    base += 6
            v = base * OPP_W * (1.4 if qi == leader.i else 0.7)
            if c == "TRADE":
                pk = self._trade_pay_die(p)
                v -= 1 + (LOCK_BONUS if p.locked[pk] else 0)
            return v + n
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
             "DUAL": 1.5, "GAMBLE": 0.9, "REROLL": 0.7,
             "SHIELD": 0.35 + 0.8 * p.locks,
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
            if p.locks == 3:
                self.over = True
                self.winner = p.i
                self.winner_lock_source = "lock-action"
            return
        if typ == "defuse":
            card, owner = self.omens.pop(0)
            self.discard.append(card)
            self._log(f"    P{p.i} defuses omen {card}")
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
        if c in ("P1", "P2"):
            _, k = a[3]
            self._move_die(p, k, 1 if c == "P1" else 2, "play")
            self._log(f"    P{p.i} plays {c} on own die{k} -> {p.dice[k]}")
        elif c == "M2":
            qi, k = a[3]
            q = self.players[qi]
            self._move_die(q, k, -2, "attack")
            q.attacks_taken += 1
            self._log(f"    P{p.i} plays -2 on P{qi} die{k} -> {q.dice[k]}")
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
            if q.shield[k]:
                q.shield[k] = False
                self._log(f"    P{p.i} {c} on P{qi} die{k} — SHIELD absorbs")
            else:
                self._set_die(q, k, q.dice[k] - 2, "attack")
                q.attacks_taken += 1
                self._log(f"    P{p.i} {c} P{qi} die{k} -> {q.dice[k]} (unlocked)")
            if c == "TRADE":
                pk = self._trade_pay_die(p)
                if pk is not None:
                    self._set_die(p, pk, p.dice[pk] - 1, "trade-cost")
                    self._log(f"      TRADE cost: own die{pk} -> {p.dice[pk]}")
        elif c == "GAMBLE":
            _, k = a[3]
            roll = self.rng.randint(1, 6)
            delta = 2 if roll >= 4 else -1
            self._move_die(p, k, delta, "GAMBLE")
            self._log(f"    P{p.i} GAMBLE die{k}: roll {roll} -> {p.dice[k]}")
        elif c == "REROLL":
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
    modes = ["raw", "none", "choice", "omen", "catchup", "personal"]
    locks = ["auto", "action"]
    total = 0
    for im in modes:
        for lm in locks:
            cfg = make_cfg({"instants": im, "lock_mode": lm,
                            "blind_draw": im == "personal"})
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

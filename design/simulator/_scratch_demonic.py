#!/usr/bin/env python3
"""Scratch: demonic-die face mechanics (TEMPT action + FALSE IDOL card) on sim666.

The demonic die keeps its last-rolled face in the table centre (starts at 3).
GAMBLE/REROLL rolls update the face. Optional rules under test:
  demonic_tempt: 1 -> once per turn, spend an action to roll the demonic die;
                 higher than shown face = +1 any own unlocked die,
                 lower = -1 own highest unlocked die, tie = nothing
                 (tempt_tie "win" -> ties count as higher).
  IDOL card in effects -> set one own unlocked die to the current face.

Usage: python3 _scratch_demonic.py '[["name", {over}], ...]' [games]
"""
import json
import statistics
import sys

sys.path.insert(0, "/home/hub/life/ucheba/666/design/simulator")
import sim666
from sim666 import Game, make_cfg, LOCK_BONUS, WIN_SCORE

BASE = {"ruleset": "ivan", "minus_floor": 4, "minus_limit": 1,
        "smash_to": 5, "smash_bounty": 1, "win_delay": 0,
        "demonic_tempt": 0, "tempt_tie": "push", "demon_start": 3,
        "effects": {"SMASH": 3, "SHIELD": 3, "GAMBLE": 3, "REROLL": 3}}


class DGame(Game):
    def __init__(self, cfg, bots, seed, log=False):
        self.demon_face = cfg.get("demon_start", 3)
        self.tempt_plays = 0
        self.idol_plays = 0
        self.idol_locks = 0
        self.turn_tempt_used = False
        super().__init__(cfg, bots, seed, log)

    # ------------------------------------------------ legality

    def legal_actions(self, p):
        acts = super().legal_actions(p)
        if (self.cfg.get("demonic_tempt") and not self.turn_tempt_used
                and p.unlocked()):
            acts.append(("tempt",))
        return acts

    def _card_actions(self, p, hi, c):
        if c == "IDOL":
            out = []
            f = self.demon_face
            for k in p.unlocked():
                if p.dice[k] != f:
                    out.append(("play", hi, c, (p.i, k)))
            return out
        return super()._card_actions(p, hi, c)

    # ------------------------------------------------ scoring

    def _tempt_probs(self):
        f = self.demon_face
        if self.cfg.get("tempt_tie") == "win":
            return (7 - f) / 6.0, (f - 1) / 6.0
        return (6 - f) / 6.0, (f - 1) / 6.0

    def score_action(self, p, a):
        if a[0] == "tempt":
            up, dn = self._tempt_probs()
            gain = 1.0
            if any(p.dice[k] == 5 for k in p.unlocked()):
                gain += LOCK_BONUS + (WIN_SCORE if p.locks == 2 else 0)
            return up * gain - dn * 1.0 + self.rng.random() * 0.06
        if a[0] == "play" and a[2] == "IDOL":
            _, k = a[3]
            f = self.demon_face
            delta = f - p.dice[k]
            return delta + self._gain_lock(p, f, k) + self.rng.random() * 0.06
        return super().score_action(p, a)

    def _draw_value(self, p, c, leader):
        if c == "IDOL":
            f = self.demon_face
            low = min((p.dice[k] for k in p.unlocked()), default=6)
            v = 0.5 + max(0, f - low) * 0.45
            if len(p.hand) >= self.cfg["hand_limit"]:
                v -= 0.4
            return v * 0.62
        return super()._draw_value(p, c, leader)

    # ------------------------------------------------ applying

    def apply(self, p, a):
        if a[0] == "tempt":
            self.turn_tempt_used = True
            self.tempt_plays += 1
            old = self.demon_face
            roll = self.rng.randint(1, 6)
            self.demon_face = roll
            tie_win = self.cfg.get("tempt_tie") == "win"
            ks = p.unlocked()
            if ks and (roll > old or (tie_win and roll == old)):
                k = max(ks, key=lambda x: (p.dice[x] == 5, p.dice[x]))
                self._move_die(p, k, 1, "TEMPT")
                self._log(f"    P{p.i} TEMPT {old}->{roll}: +1 die{k}")
            elif ks and roll < old:
                k = max(ks, key=lambda x: p.dice[x])
                self._move_die(p, k, -1, "TEMPT")
                self._log(f"    P{p.i} TEMPT {old}->{roll}: -1 die{k}")
            else:
                self._log(f"    P{p.i} TEMPT {old}->{roll}: push")
            return
        if a[0] == "play" and a[2] in ("IDOL", "GAMBLE", "REROLL"):
            hi, c = a[1], a[2]
            p.hand.pop(hi)
            self.discard.append(c)
            if c == "IDOL":
                self.idol_plays += 1
                _, k = a[3]
                f = self.demon_face
                if f == 6:
                    self.idol_locks += 1
                self._set_die(p, k, f, "IDOL")
                self._log(f"    P{p.i} IDOL die{k} -> {f}")
            elif c == "GAMBLE":
                self.gamble_plays += 1
                _, k = a[3]
                roll = self.rng.randint(1, 6)
                self.demon_face = roll
                delta = 2 if roll >= 4 else -1
                self._move_die(p, k, delta, "GAMBLE")
                self._log(f"    P{p.i} GAMBLE die{k}: roll {roll} -> {p.dice[k]}")
            else:
                self.reroll_plays += 1
                qi, k = a[3]
                q = self.players[qi]
                v = self.rng.randint(1, 6)
                self.demon_face = v
                self._set_die(q, k, v, "REROLL")
                if qi != p.i:
                    q.attacks_taken += 1
                self._log(f"    P{p.i} REROLL P{qi} die{k} -> {v}")
            return
        super().apply(p, a)

    def play_turn(self, p):
        self.turn_tempt_used = False
        super().play_turn(p)

    def metrics(self):
        m = super().metrics()
        m["tempt"] = self.tempt_plays
        m["idol"] = self.idol_plays
        m["idol_locks"] = self.idol_locks
        return m


# ---------------------------------------------------------------- driver

def run_batch(cfg_over, games, mix="smart", seed0=1000):
    cfg = make_cfg(cfg_over)
    n = cfg["players"]
    out = []
    for g in range(games):
        if mix == "smart":
            bots = ["smart"] * n
        elif mix == "random":
            bots = ["random"] * n
        else:
            bots = ["random"] * n
            bots[g % n] = "smart"
        game = DGame(cfg, bots, seed0 + g)
        m = game.run()
        m["smart_seat"] = bots.index("smart") if "smart" in bots else None
        out.append(m)
    agg = sim666.aggregate(out, cfg, mix)
    agg["tempt_mean"] = round(statistics.mean(m["tempt"] for m in out), 2)
    agg["idol_mean"] = round(statistics.mean(m["idol"] for m in out), 2)
    agg["idol_locks_mean"] = round(
        statistics.mean(m["idol_locks"] for m in out), 2)
    agg["demonic_all"] = round(agg["demonic_mean"] + agg["tempt_mean"], 2)
    return agg


def row(name, over, games=1200):
    cfg = dict(BASE)
    cfg.update(over)
    a = run_batch(cfg, games, mix="smart", seed0=1000)
    b = run_batch(cfg, games, mix="mixed", seed0=7000)
    spread = max(a["seat_win_pct"]) - min(a["seat_win_pct"])
    print(f"{name:22s} med={a['rounds_med']:>4} p90={a['rounds_p90']:>3} "
          f"stall={a['stall_pct']:4.1f} photo={a['photo_close_pct']:5.1f} "
          f"cb={a['comeback_pct']:5.1f} blk={a['blocks_mean']:4.2f} "
          f"dem={a['demonic_all']:5.2f} tmp={a['tempt_mean']:4.2f} "
          f"idl={a['idol_mean']:4.2f}/{a['idol_locks_mean']:4.2f} "
          f"atk={a['attacks_mean']:4.1f} deny={a['win_denied_mean']:4.2f} "
          f"seat={spread:4.1f} skill={b['smart_win_pct']:5.1f}", flush=True)


if __name__ == "__main__":
    variants = json.loads(sys.argv[1])
    games = int(sys.argv[2]) if len(sys.argv) > 2 else 1200
    for name, over in variants:
        row(name, over, games)

extends RefCounted
## Greedy one-ply bot: scores every legal action (draw / play with every target)
## by simulating the board and averaging over dice outcomes for random cards.

const F := [0.0, 0.0, 1.0, 2.2, 3.6, 5.3, 9.0]   # worth of a die by value (index = value)
const DEMON := [-3, -2, -1, 1, 2, 3]
const HAND_W := [0.55, 0.45, 0.35, 0.25, 0.15]


static func player_value(d: Array) -> float:
	var s := 0.0
	var sixes := 0
	for v in d:
		s += F[v]
		if v == 6:
			sixes += 1
	if sixes == 3:
		s += 1000.0
	elif sixes == 2:
		s += 4.0
	if sixes > 0:
		s += 1.5
	return s


static func evaluate(dice: Array, p: int) -> float:
	var mine := player_value(dice[p])
	var opp_sum := 0.0
	var opp_max := -1.0e9
	for o in 3:
		if o == p:
			continue
		var v := player_value(dice[o])
		opp_sum += v
		opp_max = maxf(opp_max, v)
	return mine - 0.45 * opp_sum - 0.35 * opp_max


static func card_value(c: Dictionary, dice: Array, p: int) -> float:
	match String(c.kind):
		"basic":
			return 2.0 if int(c.value) == 1 else 3.0
		"dual":
			return 3.5
		"smash":
			var v := 3.0
			for o in 3:
				if o != p and (dice[o] as Array).has(6):
					v += 1.5
			return v
		"shield":
			return 4.5 if (dice[p] as Array).has(6) else 2.5
		"gamble":
			return 2.5
		"reroll":
			return 1.5
		"pact":
			return 4.5
	return 1.0


static func hand_utility(hand: Array, dice: Array, p: int) -> float:
	var vals: Array = []
	for c in hand:
		vals.append(card_value(c, dice, p))
	vals.sort()
	vals.reverse()
	var s := 0.0
	for i in vals.size():
		s += float(vals[i]) * float(HAND_W[mini(i, 4)])
	return s


## Defender picks the die whose reduction hurts least.
static func choose_defend_die(d: Array, cands: Array, n: int) -> int:
	var best: int = cands[0]
	var best_loss := 1.0e9
	for i in cands:
		var v: int = d[i]
		var loss: float = float(F[v]) - float(F[maxi(1, v - n)])
		if loss < best_loss - 0.001 or (absf(loss - best_loss) < 0.001 and v < int(d[best])):
			best_loss = loss
			best = i
	return best


static func apply_attack(nd: Array, o: int, n: int) -> void:
	var cands: Array = []
	for d in 3:
		var v: int = nd[o][d]
		if v > 1 and v < 6:
			cands.append(d)
	if cands.is_empty():
		return
	var d2 := choose_defend_die(nd[o], cands, n)
	nd[o][d2] = maxi(1, int(nd[o][d2]) - n)


static func play_options(c: Dictionary, dice: Array, p: int) -> Array:
	var res: Array = []
	var kind := String(c.kind)
	match kind:
		"basic":
			var n: int = c.value
			for d in 3:
				if int(dice[p][d]) < 6:
					var nd: Array = dice.duplicate(true)
					nd[p][d] = mini(6, int(nd[p][d]) + n)
					res.append({"params": {"mode": "self", "die": d}, "ev": evaluate(nd, p)})
			for o in 3:
				if o == p:
					continue
				var nd2: Array = dice.duplicate(true)
				apply_attack(nd2, o, n)
				res.append({"params": {"mode": "rival", "target": o}, "ev": evaluate(nd2, p)})
		"dual":
			for d in 3:
				if int(dice[p][d]) >= 6:
					continue
				for o in 3:
					if o == p:
						continue
					var nd: Array = dice.duplicate(true)
					nd[p][d] = mini(6, int(nd[p][d]) + 1)
					apply_attack(nd, o, 1)
					res.append({"params": {"die": d, "target": o}, "ev": evaluate(nd, p)})
		"smash":
			var base := evaluate(dice, p)
			for o in 3:
				if o == p:
					continue
				for d in 3:
					if int(dice[o][d]) == 6:
						var nd: Array = dice.duplicate(true)
						nd[o][d] = 5
						res.append({"params": {"target": o, "die": d}, "ev": 0.8 * evaluate(nd, p) + 0.2 * base})
		"reroll":
			for d in 3:
				var s := 0.0
				for v in range(1, 7):
					var nd: Array = dice.duplicate(true)
					nd[p][d] = v
					s += evaluate(nd, p)
				res.append({"params": {"target": p, "die": d}, "ev": s / 6.0})
		"pact":
			for d in 3:
				var hi: Array = dice.duplicate(true)
				hi[p][d] = 6
				var lo: Array = dice.duplicate(true)
				lo[p][d] = 1
				res.append({"params": {"target": p, "die": d}, "ev": 0.5 * evaluate(hi, p) + 0.5 * evaluate(lo, p)})
		"gamble":
			var base2 := evaluate(dice, p)
			for o in 3:
				for d in 3:
					var s := 0.0
					for f in DEMON:
						var nd: Array = dice.duplicate(true)
						nd[o][d] = clampi(int(nd[o][d]) + int(f), 1, 6)
						s += evaluate(nd, p)
					var ev := s / 6.0
					if o != p and int(dice[o][d]) == 6:
						ev = 0.8 * ev + 0.2 * base2
					res.append({"params": {"target": o, "die": d}, "ev": ev})
	return res


static func choose(p: int, dice: Array, hand: Array, market: Array) -> Dictionary:
	var best: Dictionary = {"type": "none"}
	var best_score := -1.0e12
	var base_eval := evaluate(dice, p)
	if hand.size() < 5:
		for s in market.size():
			if market[s] == null:
				continue
			var nh: Array = hand.duplicate()
			nh.append(market[s])
			var sc := base_eval + hand_utility(nh, dice, p) + randf() * 0.25
			if sc > best_score:
				best_score = sc
				best = {"type": "draw", "slot": s}
	for i in hand.size():
		var c: Dictionary = hand[i]
		if String(c.kind) == "shield":
			continue
		var nh: Array = hand.duplicate()
		nh.remove_at(i)
		var hu := hand_utility(nh, dice, p)
		var opts := play_options(c, dice, p)
		if opts.is_empty():
			var sc_dud := base_eval + hu - 0.5
			if sc_dud > best_score:
				best_score = sc_dud
				best = {"type": "play", "idx": i, "params": {"dud": true}}
			continue
		for o in opts:
			var sc: float = float(o.ev) + hu + randf() * 0.25
			if sc > best_score:
				best_score = sc
				best = {"type": "play", "idx": i, "params": o.params}
	return best

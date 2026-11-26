extends Node
## Functional test-suite for 666. All UI tests drive the game with real mouse/keyboard
## events pushed into the viewport — the same path a player's clicks take.
##
##   godot --headless --path . res://tests/run_tests.tscn
##   godot --path . res://tests/run_tests.tscn -- --visual        (+ pixel checks, needs a window)
##   ... -- --only=ui_defend                                       (run a subset)
##   ... -- --games=10                                             (more full games)

const MainScene := preload("res://main.tscn")
const BotAI := preload("res://scripts/bot_ai.gd")

var m   # the game (main.gd) under test
var passed := 0
var failed := 0
var fails: Array = []
var test_name := ""
var clicks := 0
var held := 0
var visual := false
var games := 4
var inv_errors: Array = []
var stats := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	visual = args.has("--visual")
	var only := ""
	for a in args:
		if a.begins_with("--only="):
			only = a.substr(7)
		if a.begins_with("--games="):
			games = int(a.substr(8))
	Engine.time_scale = 8.0
	var tests: Array = []
	for md in get_method_list():
		var n: String = md.name
		if n.begins_with("test_"):
			tests.append(n)
	if not visual:
		tests = tests.filter(func(n): return not n.begins_with("test_visual"))
	for t in tests:
		if only != "" and not t.contains(only):
			continue
		test_name = t
		await fresh()
		var before := failed
		var t0 := Time.get_ticks_msec()
		await Callable(self, t).call()
		print("%s  %s  (%.1fs)" % ["PASS" if failed == before else "FAIL", t, (Time.get_ticks_msec() - t0) / 1000.0])
	print("\n==== %d checks passed, %d failed ====" % [passed, failed])
	for k in stats:
		print("  %s: %s" % [k, str(stats[k])])
	for f in fails:
		print("  ✗ " + f)
	if is_instance_valid(m):
		m.queue_free()
	get_tree().quit(0 if failed == 0 else 1)


# ================================================================= helpers

func ok(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		fails.append("%s: %s" % [test_name, msg])
		print("    ✗ " + msg)


func eq(a, b, msg: String) -> void:
	ok(a == b, "%s (got %s, expected %s)" % [msg, str(a), str(b)])


func frames(n: int = 1) -> void:
	for i in n:
		await get_tree().process_frame


func wait_until(cond: Callable, timeout_s: float = 15.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout_s * 1000.0:
			return false
		await get_tree().process_frame
	return true


func fresh() -> void:
	if is_instance_valid(m):
		m.queue_free()
		await frames(2)
	m = MainScene.instantiate()
	m.test_mode = true
	add_child(m)
	clicks = 0
	held = 0
	await frames(2)


const KINDS := {
	"b1": ["basic", 1], "b2": ["basic", 2], "dual": ["dual", 1], "smash": ["smash", 0],
	"shield": ["shield", 0], "gamble": ["gamble", 0], "reroll": ["reroll", 0], "pact": ["pact", 0],
}


func cards(specs: Array) -> Array:
	var res: Array = []
	for s in specs:
		if s == null:
			res.append(null)
		else:
			res.append(m.mk_card(KINDS[s][0], KINDS[s][1]))
	return res


func setup(d: Array, h0: Array, h1: Array = [], h2: Array = [], mk: Array = ["b1", "b2", "dual"], deck_n: int = 20) -> void:
	m.dice = d.duplicate(true)
	m.hands = [cards(h0), cards(h1), cards(h2)]
	m.market = cards(mk)
	m.deck = []
	for i in deck_n:
		m.deck.append(m.mk_card("basic", 1))
	m.discard = []
	m.current = 0
	m.game_over = false
	m.refresh_all()
	await frames(1)


func start_human_turn() -> void:
	m.run_turn(0)
	ok(await wait_until(func(): return m.mode == "turn"), "human turn starts")


func action_done(prev_actions: int) -> bool:
	return await wait_until(func(): return (m.mode == "turn" and m.actions_left < prev_actions) or not m.turn_active)


# ---- input (pushed into the viewport exactly like OS events)

func _push(e: InputEvent) -> void:
	get_viewport().push_input(e, true)


func mv(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.button_mask = held
	_push(e)


func btn(pos: Vector2, pressed: bool, b: int = MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = b
	e.pressed = pressed
	if b == MOUSE_BUTTON_LEFT:
		held = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	e.button_mask = held
	_push(e)


func click(pos: Vector2, b: int = MOUSE_BUTTON_LEFT) -> void:
	clicks += 1
	mv(pos)
	await frames(1)
	btn(pos, true, b)
	await frames(1)
	btn(pos, false, b)
	await frames(2)


func drag(a: Vector2, b: Vector2) -> void:
	clicks += 1
	mv(a)
	await frames(1)
	btn(a, true)
	await frames(1)
	for i in range(1, 9):
		mv(a.lerp(b, i / 8.0))
		await frames(1)
	btn(b, false)
	await frames(2)


func key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	_push(e)
	await frames(1)
	var e2 := InputEventKey.new()
	e2.keycode = k
	e2.pressed = false
	_push(e2)
	await frames(1)


func hand_pos(i: int) -> Vector2:
	return Vector2(m.hand_views[i].position.x + 50.0, m.HAND_Y + 80.0)


func die_pos(o: int, d: int) -> Vector2:
	return m.die_center(o, d)


func panel_pos(o: int) -> Vector2:
	var r: Rect2 = m.PANEL_RECTS[o]
	return r.position + Vector2(r.size.x - 40.0, r.size.y - 30.0)


func market_pos(i: int) -> Vector2:
	return m.MARKET_POS[i] + Vector2(50, 75)


func discard_pos() -> Vector2:
	return m.DISCARD_POS + Vector2(50, 70)


func empty_pos() -> Vector2:
	return Vector2(640, 485)


func target_pos(t: Dictionary) -> Vector2:
	match String(t.kind):
		"die":
			return die_pos(int(t.o), int(t.d))
		"player":
			return panel_pos(int(t.o))
	return discard_pos()


func highlighted() -> Array:
	var res: Array = []
	for o in 3:
		for d in 3:
			if m.die_views[o][d].selectable:
				res.append(Vector2i(o, d))
	return res


func no_highlights(msg: String) -> void:
	var lit: Array = highlighted()
	var hov := false
	for o in 3:
		for d in 3:
			hov = hov or m.die_views[o][d].hover or m.die_views[o][d].preview != ""
	ok(lit.is_empty() and not hov and not m.discard_hl.visible, "%s — no die/discard highlight left (lit: %s)" % [msg, str(lit)])


## Invariants that must hold on every frame, whatever the player does.
func check_frame() -> void:
	for o in 3:
		for d in 3:
			var v: int = m.dice[o][d]
			if v < 1 or v > 6:
				inv_errors.append("die %d/%d out of range: %d" % [o, d, v])
			var dv = m.die_views[o][d]
			if dv.selectable:
				if m.mode != "turn" and m.mode != "defend":
					inv_errors.append("die %d/%d highlighted while mode='%s' (current=%d)" % [o, d, m.mode, m.current])
				else:
					var listed := false
					for t in m.targets:
						if String(t.kind) == "die" and int(t.o) == o and int(t.d) == d:
							listed = true
					if not listed:
						inv_errors.append("die %d/%d highlighted but not a target" % [o, d])
	for p in 3:
		if m.hands[p].size() > 5:
			inv_errors.append("hand %d has %d cards" % [p, m.hands[p].size()])
	if m.mode != "turn" and m.mode != "defend" and m.mode != "busy" and m.sel_idx != -1:
		inv_errors.append("card still selected in mode '%s'" % m.mode)
	if m.mode == "defend" and m.current == 0:
		inv_errors.append("human asked to defend during own turn")


func _on_turn_started(_p: int) -> void:
	var total: int = m.card_total()
	if total != 52:
		inv_errors.append("turn %d: %d cards in play instead of 52" % [m.turn_number, total])


func bump(k: String, n: int = 1) -> void:
	stats[k] = stats.get(k, 0) + n


# ================================================================= RULES

func test_rules_deck_composition() -> void:
	var d: Array = m.build_deck()
	eq(d.size(), 52, "deck size")
	var cnt := {}
	var ids := {}
	for c in d:
		var k := "%s%d" % [c.kind, c.value]
		cnt[k] = cnt.get(k, 0) + 1
		ids[c.id] = true
	eq(cnt.get("basic1", 0), 17, "±1 cards")
	eq(cnt.get("basic2", 0), 12, "±2 cards")
	eq(cnt.get("dual1", 0), 11, "DUAL cards")
	eq(cnt.get("smash0", 0), 3, "SMASH cards")
	eq(cnt.get("shield0", 0), 3, "SHIELD cards")
	eq(cnt.get("gamble0", 0), 2, "GAMBLE cards")
	eq(cnt.get("reroll0", 0), 1, "REROLL cards")
	eq(cnt.get("pact0", 0), 3, "PACT cards")
	eq(ids.size(), 52, "card ids are unique")


func test_rules_clamp_and_lock_bonus() -> void:
	await setup([[5, 2, 3], [3, 3, 3], [3, 3, 3]], ["b1"])
	await m.change_die(0, 0, 3)
	eq(m.dice[0][0], 6, "5+3 is clamped to 6")
	eq(m.hands[0].size(), 2, "locking a 6 gives a free card")
	await m.change_die(0, 1, -3)
	eq(m.dice[0][1], 1, "2−3 is clamped to 1")


func test_rules_no_free_card_with_full_hand() -> void:
	await setup([[5, 3, 3], [3, 3, 3], [3, 3, 3]], ["b1", "b1", "b1", "b1", "b1"])
	await m.change_die(0, 0, 1)
	eq(m.hands[0].size(), 5, "no free card when the hand is full")
	await setup([[5, 3, 3], [3, 3, 3], [3, 3, 3]], ["b1"], [], [], ["b1", "b1", "b1"], 0)
	await m.change_die(0, 0, 1)
	eq(m.hands[0].size(), 1, "no free card when deck and discard are empty")


func test_rules_win_on_666() -> void:
	await setup([[6, 6, 5], [3, 3, 3], [3, 3, 3]], [])
	await m.change_die(0, 2, 1)
	ok(m.game_over, "6·6·6 ends the game")
	await setup([[6, 6, 5], [3, 3, 3], [3, 3, 3]], ["gamble"])
	m.forced_rolls = [2]
	await m.play_card(0, m.hands[0][0], {"target": 0, "die": 2})
	ok(m.game_over, "reaching 6·6·6 through GAMBLE also wins")


func test_rules_smash_and_shield() -> void:
	await setup([[3, 3, 3], [6, 3, 3], [6, 2, 2]], ["smash", "smash"], ["shield"], [])
	await m.play_card(0, m.hands[0][0], {"target": 1, "die": 0})
	eq(m.dice[1][0], 6, "SHIELD keeps the 6")
	eq(m.hands[1].size(), 0, "SHIELD is spent")
	eq(m.discard.size(), 2, "SMASH and SHIELD both go to the discard")
	await m.play_card(0, m.hands[0][0], {"target": 2, "die": 0})
	eq(m.dice[2][0], 5, "SMASH turns 6 into 5")


func test_rules_pact_gamble_reroll() -> void:
	await setup([[3, 4, 2], [5, 2, 3], [3, 3, 3]], ["pact", "pact", "gamble", "gamble", "reroll"])
	m.forced_rolls = [2]
	await m.play_card(0, m.hands[0][0], {"target": 0, "die": 0})
	eq(m.dice[0][0], 6, "PACT positive → 6")
	m.forced_rolls = [-1]
	await m.play_card(0, m.hands[0][0], {"target": 0, "die": 1})
	eq(m.dice[0][1], 1, "PACT negative → 1")
	m.forced_rolls = [3]
	await m.play_card(0, m.hands[0][0], {"target": 1, "die": 0})
	eq(m.dice[1][0], 6, "GAMBLE 5+3 clamps to 6")
	m.forced_rolls = [-3]
	await m.play_card(0, m.hands[0][0], {"target": 1, "die": 1})
	eq(m.dice[1][1], 1, "GAMBLE 2−3 clamps to 1")
	m.forced_rolls = [4]
	await m.play_card(0, m.hands[0][0], {"target": 0, "die": 2})
	eq(m.dice[0][2], 4, "REROLL sets the rolled value")


func test_rules_curse_bot_defends_cheapest() -> void:
	await setup([[3, 3, 3], [2, 5, 6], [1, 1, 6]], ["b2", "b1"])
	await m.play_card(0, m.hands[0][0], {"mode": "rival", "target": 1})
	eq(m.dice[1], [1, 5, 6], "bot sacrifices its cheapest die")
	await m.play_card(0, m.hands[0][0], {"mode": "rival", "target": 2})
	eq(m.dice[2], [1, 1, 6], "nothing can drop → nothing changes")


func test_rules_reshuffle() -> void:
	await setup([[3, 3, 3], [3, 3, 3], [3, 3, 3]], [], [], [], ["b1", "b1", "b1"], 0)
	m.discard = cards(["b1", "b2", "dual", "smash", "pact"])
	var c = m.draw_from_deck()
	ok(c != null, "draw reshuffles the discard")
	eq(m.deck.size(), 4, "rest of the discard is now the deck")
	eq(m.discard.size(), 0, "discard is empty after reshuffle")
	m.deck = []
	ok(m.draw_from_deck() == null, "nothing to draw when deck and discard are empty")


func test_rules_action_count() -> void:
	await setup([[6, 3, 3], [3, 3, 3], [3, 3, 3]], ["b1", "b1"])
	m.run_turn(0)
	await frames(2)
	eq(m.actions_left, 3, "a locked 6 gives 3 actions")
	await fresh()
	await setup([[5, 3, 3], [3, 3, 3], [3, 3, 3]], ["b1", "b1"])
	m.run_turn(0)
	await frames(2)
	eq(m.actions_left, 2, "no 6 → 2 actions")


func test_rules_can_act() -> void:
	await setup([[3, 3, 3], [3, 3, 3], [3, 3, 3]], ["shield", "shield", "shield"])
	ok(m.can_act(0), "only shields but room to draw → can act")
	m.hands[0] = cards(["shield", "shield", "shield", "shield", "shield"])
	ok(not m.can_act(0), "five shields → nothing to do")
	m.hands[0] = cards(["shield", "shield"])
	m.market = [null, null, null]
	ok(not m.can_act(0), "only shields and an empty market → nothing to do")


# ================================================================= UI FLOWS (real clicks)

func test_ui_draw_is_one_click() -> void:
	await setup([[3, 3, 3], [3, 3, 3], [3, 3, 3]], ["b1", "b1", "b1"])
	await start_human_turn()
	clicks = 0
	await click(market_pos(1))
	ok(await action_done(2), "draw executes")
	eq(m.hands[0].size(), 4, "card taken into the hand")
	eq(clicks, 1, "drawing costs exactly one click")
	no_highlights("after draw")


func test_ui_basic_self_two_clicks() -> void:
	await setup([[3, 4, 2], [3, 3, 3], [3, 3, 3]], ["b2", "b1", "b1"])
	await start_human_turn()
	clicks = 0
	await click(hand_pos(0))
	eq(m.sel_idx, 0, "first click selects the card")
	eq(m.targets.size(), 5, "BASIC offers 3 own dice + 2 rivals at once (no YOU/RIVAL dialog)")
	await click(die_pos(0, 1))
	ok(await action_done(2), "play executes")
	eq(m.dice[0][1], 6, "4 + 2 = 6")
	eq(clicks, 2, "BASIC on own die = 2 clicks")
	no_highlights("after BASIC self")


func test_ui_basic_curse_two_clicks() -> void:
	await setup([[3, 3, 3], [3, 5, 6], [1, 1, 1]], ["b1", "b1"])
	await start_human_turn()
	clicks = 0
	await click(hand_pos(0))
	eq(m._player_target(2), -1, "rival with nothing to drop is not offered")
	await click(panel_pos(1))
	ok(await action_done(2), "curse executes")
	eq(m.dice[1], [2, 5, 6], "rival drops its cheapest die")
	eq(clicks, 2, "curse = 2 clicks")


func test_ui_drag_and_drop() -> void:
	await setup([[3, 3, 3], [3, 3, 3], [3, 3, 3]], ["b1", "b2"])
	await start_human_turn()
	clicks = 0
	await drag(hand_pos(1), die_pos(0, 2))
	ok(await action_done(2), "drop executes")
	eq(m.dice[0][2], 5, "dragged ±2 onto own die → 3+2")
	eq(clicks, 1, "drag & drop = one gesture")
	ok(m.drag_ghost == null, "drag ghost removed")
	var before: int = m.hands[0].size()
	await drag(hand_pos(0), empty_pos())
	await frames(3)
	eq(m.hands[0].size(), before, "dropping on nothing plays nothing")
	eq(m.sel_idx, -1, "…and cancels the selection")
	no_highlights("after a cancelled drag")


func test_ui_switch_and_cancel() -> void:
	await setup([[3, 3, 3], [3, 3, 3], [3, 3, 3]], ["b1", "b2", "gamble"])
	await start_human_turn()
	await click(hand_pos(0))
	eq(m.sel_idx, 0, "card 1 selected")
	await click(hand_pos(1))
	eq(m.sel_idx, 1, "clicking another card switches directly")
	await click(hand_pos(1))
	eq(m.sel_idx, -1, "clicking the selected card again cancels")
	await click(hand_pos(2))
	await key(KEY_ESCAPE)
	eq(m.sel_idx, -1, "Esc cancels")
	await click(hand_pos(0))
	await click(empty_pos(), MOUSE_BUTTON_RIGHT)
	eq(m.sel_idx, -1, "right-click cancels")
	await click(hand_pos(0))
	await click(empty_pos())
	eq(m.sel_idx, -1, "click on empty space cancels")
	eq(m.actions_left, 2, "cancelling never spends an action")
	eq(m.hands[0].size(), 3, "…nor a card")
	no_highlights("after cancelling")


func test_ui_single_target_plays_on_one_click() -> void:
	await setup([[3, 3, 3], [6, 3, 3], [2, 2, 2]], ["smash", "b1"])
	await start_human_turn()
	clicks = 0
	await click(hand_pos(0))
	ok(await action_done(2), "SMASH executes")
	eq(m.dice[1][0], 5, "the only locked 6 was smashed")
	eq(clicks, 1, "single target = single click")


func test_ui_dual_one_click_when_forced() -> void:
	await setup([[6, 6, 3], [3, 3, 3], [1, 1, 1]], ["dual", "b1"])
	await start_human_turn()
	clicks = 0
	await click(hand_pos(0))
	ok(await action_done(3), "DUAL executes")
	eq(m.dice[0][2], 4, "+1 went to the only unlocked die")
	eq(m.dice[1][0] + m.dice[1][1] + m.dice[1][2], 8, "−1 went to the only rival who can drop")
	eq(clicks, 1, "fully determined DUAL = 1 click")


func test_ui_dual_full_three_clicks() -> void:
	await setup([[3, 3, 3], [3, 3, 3], [4, 4, 4]], ["dual"])
	await start_human_turn()
	clicks = 0
	await click(hand_pos(0))
	eq(m.sel_stage, 0, "stage 1: own die")
	await click(die_pos(0, 0))
	eq(m.sel_stage, 1, "stage 2: rival")
	eq(m.targets.size(), 2, "both rivals offered")
	no_highlights_except_players()
	await click(panel_pos(2))
	ok(await action_done(2), "DUAL executes")
	eq(m.dice[0][0], 4, "+1 to own die")
	eq(m.dice[2][0] + m.dice[2][1] + m.dice[2][2], 11, "−1 to LILITH")
	eq(clicks, 3, "DUAL with real choices = 3 clicks")


func no_highlights_except_players() -> void:
	ok(highlighted().is_empty(), "stage 2 of DUAL highlights panels, not dice (lit: %s)" % str(highlighted()))


func test_ui_dud_goes_to_discard() -> void:
	await setup([[3, 3, 3], [3, 3, 3], [3, 3, 3]], ["smash", "b1"])
	await start_human_turn()
	ok(m.hand_views[0].dim, "unplayable SMASH is dimmed up front")
	await click(hand_pos(0))
	eq(m.hands[0].size(), 2, "a card without target is not wasted on one click")
	ok(m.discard_hl.visible, "DISCARD is offered as the drop zone")
	await click(discard_pos())
	ok(await action_done(2), "discarding executes")
	eq(m.hands[0].size(), 1, "card left the hand")
	eq(String(m.discard.back().kind), "smash", "card is in the discard")


func test_ui_market_blocked_when_hand_full() -> void:
	await setup([[3, 3, 3], [3, 3, 3], [3, 3, 3]], ["b1", "b1", "b1", "b1", "b1"])
	await start_human_turn()
	ok(m.market_views[0].dim, "market dimmed when the hand is full")
	await click(market_pos(0))
	await frames(3)
	eq(m.hands[0].size(), 5, "no draw beyond 5")
	eq(m.actions_left, 2, "no action spent")


func test_ui_shield_is_not_an_action() -> void:
	await setup([[3, 3, 3], [3, 3, 3], [3, 3, 3]], ["shield", "b1"])
	await start_human_turn()
	ok(m.hand_views[0].dim, "SHIELD is dimmed during your turn")
	await click(hand_pos(0))
	eq(m.sel_idx, -1, "SHIELD can't be selected")
	ok(m.toast_label.text.contains("SHIELD"), "a toast explains why")
	await drag(hand_pos(0), die_pos(0, 0))
	eq(m.hands[0].size(), 2, "SHIELD can't be dragged into play")
	eq(m.actions_left, 2, "no action spent")


func test_ui_board_ignored_outside_your_turn() -> void:
	await setup([[3, 3, 3], [3, 3, 3], [3, 3, 3]], ["b1", "b2"])
	m.current = 1
	await click(hand_pos(0))
	await click(market_pos(0))
	await click(die_pos(0, 0))
	await frames(3)
	eq(m.sel_idx, -1, "no selection outside your turn")
	eq(m.hands[0].size(), 2, "no draw outside your turn")
	no_highlights("outside your turn")


func test_ui_defend_asks_only_when_it_matters() -> void:
	await setup([[3, 5, 6], [3, 3, 3], [3, 3, 3]], [], ["b1"])
	m.current = 1
	m.turn_active = true
	m.play_card(1, m.hands[1][0], {"mode": "rival", "target": 0})
	ok(await wait_until(func(): return m.mode == "defend"), "human is asked which die drops")
	var lit: Array = highlighted()
	lit.sort()
	eq(lit, [Vector2i(0, 0), Vector2i(0, 1)], "only the dice that can drop are lit")
	await click(die_pos(0, 2))
	eq(m.mode, "defend", "clicking a locked 6 is not accepted")
	await click(die_pos(0, 1))
	ok(await wait_until(func(): return m.discard.size() == 1), "curse resolves")
	eq(m.dice[0], [3, 4, 6], "the chosen die dropped")
	no_highlights("after defending")
	await frames(10)
	no_highlights("10 frames after defending")


func test_ui_defend_auto_when_options_equal() -> void:
	await setup([[4, 4, 6], [3, 3, 3], [3, 3, 3]], [], ["b1"])
	m.current = 1
	m.turn_active = true
	var asked := false
	m.play_card(1, m.hands[1][0], {"mode": "rival", "target": 0})
	var t0 := Time.get_ticks_msec()
	while m.discard.size() == 0 and Time.get_ticks_msec() - t0 < 10000:
		asked = asked or m.mode == "defend"
		await frames(1)
	ok(not asked, "no question when both choices give the same result")
	var s: Array = m.dice[0].duplicate()
	s.sort()
	eq(s, [3, 4, 6], "one 4 dropped automatically")


func test_ui_shield_fires_without_dialog() -> void:
	await setup([[6, 3, 3], [3, 3, 3], [3, 3, 3]], ["shield"], ["smash"])
	m.current = 1
	await m.play_card(1, m.hands[1][0], {"target": 0, "die": 0})
	eq(m.dice[0][0], 6, "6 survives")
	eq(m.hands[0].size(), 0, "SHIELD spent automatically")


func test_ui_rules_overlay_blocks_board() -> void:
	await setup([[3, 3, 3], [3, 3, 3], [3, 3, 3]], ["b1"])
	await start_human_turn()
	m.show_rules()
	await frames(2)
	await click(market_pos(0))
	await frames(3)
	eq(m.hands[0].size(), 1, "a click on the rules screen doesn't reach the board")
	ok(not is_instance_valid(m.rules_overlay), "…and closes the rules")
	m.show_rules()
	await frames(2)
	await key(KEY_ESCAPE)
	await frames(2)
	ok(not is_instance_valid(m.rules_overlay), "Esc closes the rules")


func test_ui_hover_preview() -> void:
	await setup([[3, 3, 3], [3, 3, 3], [3, 3, 3]], ["b2", "b1"])
	await start_human_turn()
	mv(hand_pos(0))
	await frames(3)
	ok(m.info_box.visible and m.info_label.text.begins_with("BASIC"), "hovering a card shows its description instantly")
	await click(hand_pos(0))
	mv(die_pos(0, 0))
	await frames(3)
	ok(m.die_views[0][0].hover, "hovered target is emphasised")
	eq(m.die_views[0][0].preview, "3→5", "hovered target previews the result")
	mv(empty_pos())
	await frames(3)
	ok(not m.die_views[0][0].hover, "preview disappears when leaving the die")


func test_ui_cursor_tells_what_is_clickable() -> void:
	await setup([[3, 3, 3], [3, 3, 3], [3, 3, 3]], ["b1", "shield"])
	await start_human_turn()
	mv(hand_pos(0))
	await frames(3)
	eq(m.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND, "hand cursor over a playable card")
	mv(hand_pos(1))
	await frames(3)
	eq(m.mouse_default_cursor_shape, Control.CURSOR_FORBIDDEN, "forbidden cursor over SHIELD")
	mv(market_pos(0))
	await frames(3)
	eq(m.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND, "hand cursor over the market")
	mv(empty_pos())
	await frames(3)
	eq(m.mouse_default_cursor_shape, Control.CURSOR_ARROW, "arrow over empty space")
	await click(hand_pos(0))
	mv(die_pos(0, 1))
	await frames(3)
	eq(m.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND, "hand cursor over a target")


func test_ui_buttons_take_no_focus() -> void:
	m.show_title()
	m.show_rules()
	await frames(2)
	var bad: Array = []
	for b in m.find_children("*", "Button", true, false):
		if b.focus_mode != Control.FOCUS_NONE:
			bad.append(b.text)
	eq(bad, [], "no button keeps keyboard focus (Space/Enter would re-press it)")


func test_ui_turn_passes_automatically() -> void:
	await setup([[3, 3, 3], [3, 3, 3], [3, 3, 3]], ["b1"])
	await start_human_turn()
	await click(market_pos(0))
	ok(await action_done(2), "first action")
	await click(market_pos(1))
	ok(await wait_until(func(): return not m.turn_active), "turn ends after the last action — no END TURN click")
	ok(await wait_until(func(): return m.market.count(null) == 0), "market refilled")


# ================================================================= FULL GAMES

## The human seat is played by the bot brain, but every decision is executed through
## real clicks/drags. Proves the UI can express everything and never gets stuck.
func test_games_ai_through_ui() -> void:
	for g in games:
		await fresh()
		inv_errors = []
		m.turn_started.connect(_on_turn_started)
		m.start_game()
		var stuck := 0
		var t0 := Time.get_ticks_msec()
		while not m.game_over and m.turn_number < 200 and Time.get_ticks_msec() - t0 < 120000:
			check_frame()
			if m.mode == "turn":
				var acts: int = m.actions_left
				var tn: int = m.turn_number
				await ui_execute_bot_choice()
				await frames(3)
				if m.mode == "turn" and m.actions_left == acts and m.turn_number == tn and m.sel_idx == -1:
					stuck += 1
					if stuck > 3:
						ok(false, "game %d: UI action did not execute" % g)
						break
				else:
					stuck = 0
			elif m.mode == "defend":
				var t: Dictionary = m.targets.pick_random()
				bump("defend clicks")
				await click(target_pos(t))
			else:
				await frames(1)
		ok(m.game_over, "game %d finished (turn %d)" % [g, m.turn_number])
		ok(inv_errors.is_empty(), "game %d invariants: %s" % [g, str(inv_errors.slice(0, 5))])
		bump("ai-through-ui games")
		bump("ai-through-ui turns", m.turn_number)


func ui_execute_bot_choice() -> void:
	var act: Dictionary = BotAI.choose(0, m.dice, m.hands[0], m.market)
	if String(act.get("type", "")) == "draw":
		bump("ui draws")
		await click(market_pos(int(act.slot)))
		return
	if String(act.get("type", "")) != "play":
		return
	var idx: int = act.idx
	var card: Dictionary = m.hands[0][idx]
	var want: Dictionary = act.params
	bump("ui plays: " + String(card.kind))
	if randf() < 0.35:
		# drag variant: drop straight on the matching first-stage target
		var ts: Array = m.compute_targets(card, 0)
		var t := _match_target(ts, want, card, 0)
		bump("ui drags")
		await drag(hand_pos(idx), target_pos(t))
	else:
		await click(hand_pos(idx))
	var guard := 0
	while m.mode == "turn" and m.sel_idx >= 0 and guard < 4:
		guard += 1
		var t2 := _match_target(m.targets, want, card, m.sel_stage)
		await click(target_pos(t2))


func _match_target(ts: Array, want: Dictionary, card: Dictionary, stage: int) -> Dictionary:
	for t in ts:
		var p: Dictionary = t.params
		match String(card.kind):
			"basic":
				if p.get("mode") == want.get("mode") and p.get("die", -9) == want.get("die", -9) and p.get("target", -9) == want.get("target", -9):
					return t
			"dual":
				if stage == 0 and p.get("die") == want.get("die"):
					return t
				if stage == 1 and p.get("target") == want.get("target"):
					return t
			_:
				if p.get("dud", false) and want.get("dud", false):
					return t
				if p.get("target", -9) == want.get("target", -9) and p.get("die", -9) == want.get("die", -9):
					return t
	bump("ui fallback targets (bot wanted a pointless target)")
	return ts.pick_random()


## Chaos test: random clicks, drags, right-clicks and Esc everywhere, invariants checked
## after every event. The game must keep going and finish.
func test_games_monkey() -> void:
	for g in games:
		await fresh()
		inv_errors = []
		m.turn_started.connect(_on_turn_started)
		m.start_game()
		var t0 := Time.get_ticks_msec()
		var events := 0
		while not m.game_over and m.turn_number < 150 and Time.get_ticks_msec() - t0 < 150000:
			check_frame()
			if m.mode != "turn" and m.mode != "defend":
				await frames(1)
				continue
			events += 1
			var r := randf()
			if r < 0.30 and m.hand_views.size() > 0:
				await click(hand_pos(randi() % m.hand_views.size()))
			elif r < 0.55 and not m.targets.is_empty():
				await click(target_pos(m.targets.pick_random()))
			elif r < 0.65:
				await click(market_pos(randi() % 3))
			elif r < 0.75 and m.hand_views.size() > 0:
				var dst := Vector2(randf_range(0, 1280), randf_range(0, 720))
				if not m.targets.is_empty() and randf() < 0.5:
					dst = target_pos(m.targets.pick_random())
				await drag(hand_pos(randi() % m.hand_views.size()), dst)
			elif r < 0.80:
				await click(Vector2(randf_range(0, 1280), randf_range(0, 720)), MOUSE_BUTTON_RIGHT)
			elif r < 0.84:
				await key(KEY_ESCAPE)
			else:
				var pos := Vector2(randf_range(0, 1280), randf_range(150, 720))
				# keep the monkey away from RESTART/RULES — those are tested separately
				await click(pos)
			check_frame()
			if is_instance_valid(m.rules_overlay):
				m._close_rules()
		ok(m.game_over, "monkey game %d finished (turn %d, %d events)" % [g, m.turn_number, events])
		ok(inv_errors.is_empty(), "monkey game %d invariants: %s" % [g, str(inv_errors.slice(0, 5))])
		bump("monkey games")
		bump("monkey events", events)


# ================================================================= VISUAL (window only)

func _tone_pixels_around(img: Image, o: int, d: int, tone: Color) -> int:
	var r: Rect2 = m._die_rect(o, d)
	var sx := img.get_width() / 1280.0
	var sy := img.get_height() / 720.0
	var hits := 0
	for y in range(int(r.position.y - 8), int(r.end.y + 8)):
		for x in range(int(r.position.x - 8), int(r.end.x + 8)):
			if r.grow(1).has_point(Vector2(x, y)):
				continue   # ring only, outside the die body
			var c := img.get_pixel(clampi(int(x * sx), 0, img.get_width() - 1), clampi(int(y * sy), 0, img.get_height() - 1))
			# match by hue: the ring pulses (alpha blends it with the dark panel)
			var dh := absf(c.h - tone.h)
			dh = minf(dh, 1.0 - dh)
			if dh < 0.03 and c.s > 0.3 and c.v > 0.15:
				hits += 1
	return hits


## Max ring pixels over several frames (the ring pulses).
func _ring_hits(o: int, d: int, tone: Color, n: int = 12) -> int:
	var best := 0
	for i in n:
		await frames(2)
		var img := get_viewport().get_texture().get_image()
		best = maxi(best, _tone_pixels_around(img, o, d, tone))
	return best


## The reported bug: highlight rings stayed on dice after the choice was made.
func test_visual_no_stale_highlight() -> void:
	await setup([[3, 4, 2], [3, 3, 3], [3, 3, 3]], ["b1", "b1", "b1"])
	await start_human_turn()
	await click(hand_pos(0))
	var lit := await _ring_hits(0, 2, m.TONE_UP)
	ok(lit > 20, "highlight ring is visible while choosing (%d px)" % lit)
	await click(die_pos(0, 0))
	ok(await action_done(2), "play executes")
	var after1 := await _ring_hits(0, 1, m.TONE_UP)
	var after2 := await _ring_hits(0, 2, m.TONE_UP)
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../test_after_pick.png"))
	eq(after1, 0, "no stale ring on the 2nd die after the pick")
	eq(after2, 0, "no stale ring on the 3rd die after the pick")
	# same during a rival's turn (defending)
	await fresh()
	await setup([[3, 5, 2], [3, 3, 3], [3, 3, 3]], [], ["b1"])
	m.current = 1
	m.turn_active = true
	m.play_card(1, m.hands[1][0], {"mode": "rival", "target": 0})
	ok(await wait_until(func(): return m.mode == "defend"), "defend prompt")
	var lit2 := await _ring_hits(0, 1, m.TONE_DOWN)
	ok(lit2 > 20, "defend ring is visible while choosing (%d px)" % lit2)
	await click(die_pos(0, 0))
	ok(await wait_until(func(): return m.discard.size() == 1), "curse resolves")
	var d1 := await _ring_hits(0, 1, m.TONE_DOWN)
	var d2 := await _ring_hits(0, 2, m.TONE_DOWN)
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../test_after_defend.png"))
	eq(d1, 0, "no stale ring on die 2 after defending (rival's turn)")
	eq(d2, 0, "no stale ring on die 3 after defending (rival's turn)")


func _shot(name: String) -> void:
	await frames(6)
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../ux_%s.png" % name))


## Screenshots of the key interaction states, for a human eye.
func test_visual_ux_shots() -> void:
	Engine.time_scale = 1.0
	await setup([[3, 6, 2], [4, 6, 2], [5, 5, 1]], ["b2", "dual", "smash", "shield"], ["b1", "b1"], ["b1"])
	await start_human_turn()
	await frames(30)
	mv(hand_pos(0))
	await _shot("1_turn_hover_card")
	await click(hand_pos(0))
	mv(die_pos(0, 2))
	await _shot("2_basic_hover_own_die")
	mv(panel_pos(2))
	await _shot("3_basic_hover_rival")
	await key(KEY_ESCAPE)
	clicks += 1
	mv(hand_pos(1))
	await frames(1)
	btn(hand_pos(1), true)
	await frames(1)
	for i in range(1, 9):
		mv(hand_pos(1).lerp(die_pos(0, 0) + Vector2(0, 30), i / 8.0))
		await frames(1)
	mv(die_pos(0, 0))
	await _shot("4_dragging_dual")
	btn(die_pos(0, 0), false)
	await _shot("5_dual_pick_rival")
	await key(KEY_ESCAPE)
	await fresh()
	Engine.time_scale = 1.0
	await setup([[3, 4, 2], [3, 3, 3], [3, 3, 3]], ["smash", "b1"])
	await start_human_turn()
	await frames(30)
	await click(hand_pos(0))
	mv(discard_pos())
	await _shot("6_dud_to_discard")
	await fresh()
	Engine.time_scale = 1.0
	await setup([[3, 5, 6], [3, 3, 3], [3, 3, 3]], [], ["b2"])
	m.current = 1
	m.turn_active = true
	m.play_card(1, m.hands[1][0], {"mode": "rival", "target": 0})
	await wait_until(func(): return m.mode == "defend")
	mv(die_pos(0, 1))
	await _shot("7_defend")
	Engine.time_scale = 8.0


## RESTART can be pressed at any moment: kill the game mid-animation many times.
## Any coroutine resuming on a freed instance would print an engine error to stderr.
func test_games_restart_mid_animation() -> void:
	for i in 10:
		await fresh()
		m.autoplay = true
		m.start_game()
		var t0 := Time.get_ticks_msec()
		var stop_at := randf_range(0.3, 4.0) * 1000.0
		while Time.get_ticks_msec() - t0 < stop_at:
			await frames(1)
		m.queue_free()
		await frames(3)
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 2000:
		await frames(1)
	ok(true, "survived 10 mid-game teardowns")

extends Control
## 666 — a satanic turn-based sabotage game with cards and dice.
## Player 0 is the human (bottom), players 1 and 2 are bots (top-left, top-right).
##
## Human input — every click has to carry information:
##   • drag a hand card onto a highlighted target, or click the card and then the target;
##   • a card with exactly one sensible target plays on a single click;
##   • one click on a market card draws it;
##   • clicking another card switches the selection; clicking the card again, empty
##     space, right-click or Esc cancels;
##   • no confirmation dialogs: SHIELD fires by itself, and when a rival curses you the
##     game only asks which die drops if the choice actually changes the result.
## Cards and dice are passive views — all board input goes through _input/_gui_input here.
##
## Command-line user args: `-- --autoplay --fast` runs a bot-only game (for testing).

const CardView = preload("res://scripts/card_view.gd")
const DieView = preload("res://scripts/die_view.gd")
const BotAI = preload("res://scripts/bot_ai.gd")

signal human_input(data: Dictionary)
signal turn_started(p: int)

const NAMES := ["YOU", "AZAZEL", "LILITH"]
const NAME_COLORS := ["#ffd400", "#b388ff", "#ff6b6b"]
const DEMON_FACES := [-3, -2, -1, 1, 2, 3]
const DECK_POS := Vector2(340, 222)
const MARKET_POS := [Vector2(480, 222), Vector2(592, 222), Vector2(704, 222)]
const DISCARD_POS := Vector2(850, 222)
const DEMON_POS := Vector2(1000, 250)
const PLAY_POS := Vector2(575, 150)
const HAND_Y := 560.0
const CARD_SIZE := Vector2(100, 140)
const PANEL_RECTS := [Rect2(30, 470, 290, 230), Rect2(30, 20, 400, 175), Rect2(850, 20, 400, 175)]
const BOT_HAND_SCALE := 0.42
const BOT_HAND_OFFSET := Vector2(270, 62)
const TONE_UP := Color("#46e08a")
const TONE_DOWN := Color("#ff8a3d")
const TONE_RANDOM := Color("#ffd400")
const TONE_DISCARD := Color("#d8d8e0")
const DRAG_START := 10.0
const GHOST_OFFSET := Vector2(16, 12)   # drag ghost sits beside the cursor, not over the target
const GHOST_SCALE := 0.62

# ---------------------------------------------------------------- state
var dice: Array = [[3, 3, 3], [3, 3, 3], [3, 3, 3]]
var hands: Array = [[], [], []]
var deck: Array = []
var discard: Array = []
var market: Array = [null, null, null]
var current: int = -1
var actions_left: int = 0
var game_over: bool = false
var turn_active: bool = false
var started: bool = false
## "" = nothing to do for the human, "turn" = human picks an action,
## "defend" = human picks which die drops, "busy" = input accepted, waiting for the game.
var mode: String = ""
var next_id: int = 0
var autoplay: bool = false
var test_mode: bool = false
var forced_rolls: Array = []   # tests: queued results for the demonic die / rerolls
var pulse_t: float = 0.0
var turn_number: int = 0

# ---------------------------------------------------------------- human input state
var sel_idx: int = -1          # selected hand card
var sel_stage: int = 0         # DUAL: 0 = pick your die, 1 = pick a rival
var sel_die: int = -1          # DUAL: die chosen in stage 0
var targets: Array = []        # [{kind: die|player|discard, o, d, params, tone, preview}]
var hover_target: int = -1
var hover_hand: int = -1
var hover_market: int = -1
var press_idx: int = -1        # hand card under a pressed mouse button (click or drag)
var press_pos: Vector2 = Vector2.ZERO
var dragging: bool = false
var drag_ghost = null
var mouse_pos: Vector2 = Vector2(-1000, -1000)

# ---------------------------------------------------------------- ui
var fx: Control
var panels: Array = []
var panel_styles: Array = []
var action_labels: Array = []
var info_labels: Array = []
var tgt_labels: Array = []
var die_views: Array = [[], [], []]
var hand_roots: Array = [null, null, null]
var hand_views: Array = []
var market_views: Array = []
var deck_view
var discard_view
var discard_hl: Panel
var deck_label: Label
var discard_label: Label
var demon_die
var status_label: Label
var hint_label: Label
var log_label: RichTextLabel
var toast_label: Label
var toast_tween: Tween
var info_box: PanelContainer
var info_label: Label
var rules_overlay: Control
var title_overlay: Control
var win_overlay: Control


func _ready() -> void:
	randomize()
	build_ui()
	if test_mode:
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	autoplay = args.has("--autoplay")
	if args.has("--fast"):
		Engine.time_scale = 12.0
	if args.has("--shots"):
		_take_shots()
	if autoplay:
		started = true
		start_game()
	else:
		show_title()


func _process(delta: float) -> void:
	pulse_t += delta
	_update_hover()
	if dragging and is_instance_valid(drag_ghost):
		drag_ghost.position = mouse_pos + GHOST_OFFSET
	var k := minf(1.0, delta * 16.0)
	for i in hand_views.size():
		var hv = hand_views[i]
		var lift := 0.0
		if i == sel_idx:
			lift = 26.0
		elif i == hover_hand and mode == "turn" and not dragging:
			lift = 16.0
		hv.position.y = lerpf(hv.position.y, HAND_Y - lift, k)
	for i in 3:
		var mv = market_views[i]
		var ml := 8.0 if (i == hover_market and mode == "turn" and hands[0].size() < 5) else 0.0
		mv.position.y = lerpf(mv.position.y, MARKET_POS[i].y - ml, k)
	_update_panels()
	if discard_hl.visible:
		var hot := _valid_hover() and String(targets[hover_target].kind) == "discard"
		discard_hl.modulate.a = 1.0 if hot else 0.45 + 0.4 * sin(pulse_t * 6.0)


func _update_panels() -> void:
	for p in 3:
		var sb: StyleBoxFlat = panel_styles[p]
		var ti := _player_target(p)
		if ti >= 0:
			var col: Color = targets[ti].tone
			var hot := ti == hover_target
			sb.border_color = col
			sb.shadow_color = Color(col, 0.5 if hot else 0.18 + 0.14 * sin(pulse_t * 6.0))
			sb.shadow_size = 20 if hot else 12
		elif p == 0 and mode == "defend":
			sb.border_color = TONE_DOWN
			sb.shadow_color = Color(TONE_DOWN, 0.3 + 0.2 * sin(pulse_t * 6.0))
			sb.shadow_size = 18
		elif p == current and turn_active:
			sb.border_color = Color("#ff2e2e")
			sb.shadow_color = Color(1, 0.1, 0.1, 0.25 + 0.15 * sin(pulse_t * 3.0))
			sb.shadow_size = 16
		else:
			sb.border_color = Color("#2a2a35")
			sb.shadow_size = 0


func _draw() -> void:
	var c := Vector2(640, 330)
	var red := Color(1, 0.15, 0.15, 0.06)
	draw_arc(c, 300, 0, TAU, 128, red, 3.0, true)
	draw_arc(c, 284, 0, TAU, 128, Color(1, 0.15, 0.15, 0.035), 1.5, true)
	var tri := PackedVector2Array()
	for a in [-150.0, -30.0, 90.0, -150.0]:
		tri.append(c + Vector2.from_angle(deg_to_rad(a)) * 300.0)
	draw_polyline(tri, Color(1, 0.15, 0.15, 0.045), 2.0, true)
	var slot := StyleBoxFlat.new()
	slot.draw_center = false
	slot.border_color = Color(1, 1, 1, 0.07)
	slot.set_border_width_all(1)
	slot.set_corner_radius_all(8)
	for pos in [DECK_POS, MARKET_POS[0], MARKET_POS[1], MARKET_POS[2], DISCARD_POS]:
		draw_style_box(slot, Rect2(pos, CARD_SIZE))


# ================================================================= UI BUILD

func build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()

	var title := _label("6 6 6", 52, Color("#ff2e2e"))
	title.position = Vector2(440, 10)
	title.size = Vector2(400, 66)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var sub := _label("A SATANIC SABOTAGE GAME", 11, Color(1, 1, 1, 0.45))
	sub.position = Vector2(440, 74)
	sub.size = Vector2(400, 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	var rules_btn := _button("RULES", 12)
	rules_btn.position = Vector2(545, 100)
	rules_btn.pressed.connect(show_rules)
	add_child(rules_btn)
	var restart_btn := _button("RESTART", 12)
	restart_btn.position = Vector2(640, 100)
	restart_btn.pressed.connect(_restart)
	add_child(restart_btn)

	for p in 3:
		_build_panel(p)

	deck_label = _pile_label("DECK", DECK_POS)
	var ml := _label("MARKET", 11, Color(1, 1, 1, 0.45))
	ml.position = Vector2(480, 202)
	ml.size = Vector2(324, 18)
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(ml)
	discard_label = _pile_label("DISCARD", DISCARD_POS)

	deck_view = CardView.new()
	deck_view.face_up = false
	deck_view.position = DECK_POS
	add_child(deck_view)

	for i in 3:
		var mv = CardView.new()
		mv.position = MARKET_POS[i]
		mv.base_y = MARKET_POS[i].y
		mv.visible = false
		add_child(mv)
		market_views.append(mv)

	discard_view = CardView.new()
	discard_view.position = DISCARD_POS
	discard_view.visible = false
	add_child(discard_view)

	discard_hl = Panel.new()
	discard_hl.position = DISCARD_POS - Vector2(6, 6)
	discard_hl.size = CARD_SIZE + Vector2(12, 12)
	discard_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dsb := StyleBoxFlat.new()
	dsb.draw_center = false
	dsb.border_color = TONE_DISCARD
	dsb.set_border_width_all(3)
	dsb.set_corner_radius_all(11)
	discard_hl.add_theme_stylebox_override("panel", dsb)
	discard_hl.visible = false
	add_child(discard_hl)

	demon_die = DieView.new()
	demon_die.setup(70.0)
	demon_die.demonic = true
	demon_die.value = 0
	demon_die.position = DEMON_POS
	add_child(demon_die)
	var dl := _label("DEMONIC DIE", 11, Color(1, 1, 1, 0.45))
	dl.position = DEMON_POS + Vector2(-25, 80)
	dl.size = Vector2(120, 18)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(dl)
	var df := _label("−3 −2 −1 +1 +2 +3", 10, Color(1, 1, 1, 0.3))
	df.position = DEMON_POS + Vector2(-25, 96)
	df.size = Vector2(120, 16)
	df.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(df)

	status_label = _label("", 17, Color.WHITE)
	status_label.position = Vector2(330, 376)
	status_label.size = Vector2(620, 26)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.clip_text = true
	add_child(status_label)
	hint_label = _label("", 12, Color(1, 1, 1, 0.42))
	hint_label.position = Vector2(330, 404)
	hint_label.size = Vector2(620, 18)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.clip_text = true
	add_child(hint_label)

	var hr := Control.new()
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hr)
	hand_roots[0] = hr

	var lp := Panel.new()
	lp.position = Vector2(960, 395)
	lp.size = Vector2(290, 305)
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color("#101016")
	lsb.border_color = Color("#24242e")
	lsb.set_border_width_all(1)
	lsb.set_corner_radius_all(10)
	lp.add_theme_stylebox_override("panel", lsb)
	add_child(lp)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.position = Vector2(10, 8)
	log_label.size = Vector2(272, 290)
	log_label.add_theme_font_size_override("normal_font_size", 12)
	log_label.add_theme_color_override("default_color", Color(1, 1, 1, 0.8))
	lp.add_child(log_label)

	fx = Control.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx)
	toast_label = _label("", 20, Color("#ffd400"))
	toast_label.position = Vector2(290, 436)
	toast_label.size = Vector2(700, 36)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	toast_label.add_theme_constant_override("outline_size", 6)
	toast_label.modulate.a = 0.0
	fx.add_child(toast_label)

	info_box = PanelContainer.new()
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color("#1a1a22f2")
	isb.border_color = Color("#ff2e2e")
	isb.set_border_width_all(1)
	isb.set_corner_radius_all(6)
	isb.set_content_margin_all(9)
	info_box.add_theme_stylebox_override("panel", isb)
	info_label = _label("", 12, Color(1, 1, 1, 0.92))
	info_box.add_child(info_label)
	info_box.visible = false
	fx.add_child(info_box)


func _build_panel(p: int) -> void:
	var r: Rect2 = PANEL_RECTS[p]
	var pn := Panel.new()
	pn.position = r.position
	pn.size = r.size
	pn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#121219")
	sb.border_color = Color("#2a2a35")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	pn.add_theme_stylebox_override("panel", sb)
	add_child(pn)
	panels.append(pn)
	panel_styles.append(sb)

	var nl := _label(NAMES[p], 20, Color(NAME_COLORS[p]))
	nl.position = Vector2(18, 10)
	pn.add_child(nl)
	var al := _label("", 13, Color("#ff6b6b"))
	al.position = Vector2(r.size.x - 160, 14)
	al.size = Vector2(142, 20)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pn.add_child(al)
	action_labels.append(al)
	var tl := _label("", 15, TONE_DOWN)
	tl.position = Vector2(r.size.x - 250, 12)
	tl.size = Vector2(232, 22)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pn.add_child(tl)
	tgt_labels.append(tl)

	var ds := 72.0 if p == 0 else 64.0
	var sp := 88.0 if p == 0 else 78.0
	var dy := 62.0 if p == 0 else 56.0
	for d in 3:
		var dv = DieView.new()
		dv.setup(ds)
		dv.owner_idx = p
		dv.die_idx = d
		dv.value = 3
		dv.position = Vector2(20 + d * sp, dy)
		pn.add_child(dv)
		die_views[p].append(dv)

	var il := _label("", 12, Color(1, 1, 1, 0.5))
	il.position = Vector2(18, 150 if p == 0 else 138)
	il.size = Vector2(r.size.x - 30, 18)
	pn.add_child(il)
	info_labels.append(il)

	if p != 0:
		var hr := Control.new()
		hr.position = BOT_HAND_OFFSET
		hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pn.add_child(hr)
		hand_roots[p] = hr


func _pile_label(txt: String, pos: Vector2) -> Label:
	var l := _label(txt, 11, Color(1, 1, 1, 0.45))
	l.position = pos + Vector2(0, -20)
	l.size = Vector2(100, 18)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l


func _label(txt: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Buttons never take keyboard focus: otherwise Space/Enter would re-press
## the last clicked button (e.g. RESTART) later in the game.
func _button(txt: String, fs: int) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fs)
	return b


func _make_theme() -> Theme:
	var th := Theme.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
	f.font_weight = 600
	th.default_font = f
	th.default_font_size = 15
	var n := StyleBoxFlat.new()
	n.bg_color = Color("#1a1a22")
	n.border_color = Color("#ff2e2e")
	n.set_border_width_all(2)
	n.set_corner_radius_all(6)
	n.content_margin_left = 16
	n.content_margin_right = 16
	n.content_margin_top = 7
	n.content_margin_bottom = 7
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color("#3d1219")
	var pr := n.duplicate() as StyleBoxFlat
	pr.bg_color = Color("#ff2e2e")
	th.set_stylebox("normal", "Button", n)
	th.set_stylebox("hover", "Button", h)
	th.set_stylebox("pressed", "Button", pr)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color.WHITE)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.BLACK)
	return th


# ================================================================= OVERLAYS

func _make_overlay(alpha: float) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.0, 0.01, alpha)
	bg.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(cc)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_theme_constant_override("separation", 14)
	cc.add_child(vb)
	root.set_meta("vb", vb)
	add_child(root)
	return root


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func show_title() -> void:
	title_overlay = _make_overlay(0.94)
	var vb: VBoxContainer = title_overlay.get_meta("vb")
	var t := _centered(_label("6 6 6", 120, Color("#ff2e2e")))
	vb.add_child(t)
	var tw := t.create_tween().set_loops()
	tw.tween_property(t, "modulate", Color(1, 1, 1, 0.55), 1.2)
	tw.tween_property(t, "modulate", Color.WHITE, 1.2)
	vb.add_child(_centered(_label("A SATANIC TURN-BASED SABOTAGE GAME WITH CARDS AND DICE", 14, Color(1, 1, 1, 0.5))))
	vb.add_child(_centered(_label("You vs AZAZEL & LILITH — be the first to show 6 · 6 · 6", 17, Color.WHITE)))
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	var play := _button("  PLAY  ", 22)
	play.pressed.connect(_start_from_title)
	hb.add_child(play)
	var rules := _button("RULES", 22)
	rules.pressed.connect(show_rules)
	hb.add_child(rules)
	vb.add_child(hb)
	vb.add_child(_centered(_label("or press Enter", 11, Color(1, 1, 1, 0.3))))
	vb.add_child(_centered(_label("Nikita Hancharov · Iván Barbosa", 11, Color(1, 1, 1, 0.3))))


func _start_from_title() -> void:
	if started:
		return
	started = true
	var ov := title_overlay
	var tw := create_tween()
	tw.tween_property(ov, "modulate:a", 0.0, 0.4)
	tw.tween_callback(ov.queue_free)
	start_game()


func show_rules() -> void:
	if is_instance_valid(rules_overlay):
		return
	rules_overlay = _make_overlay(0.95)
	rules_overlay.gui_input.connect(_on_rules_input)
	var vb: VBoxContainer = rules_overlay.get_meta("vb")
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.mouse_filter = Control.MOUSE_FILTER_PASS
	rt.custom_minimum_size = Vector2(800, 520)
	rt.add_theme_font_size_override("normal_font_size", 15)
	rt.text = RULES_TEXT
	vb.add_child(rt)
	vb.add_child(_centered(_label("click anywhere or press Esc to close", 12, Color(1, 1, 1, 0.4))))


func _on_rules_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_close_rules()


func _close_rules() -> void:
	if is_instance_valid(rules_overlay):
		rules_overlay.queue_free()
	rules_overlay = null


const RULES_TEXT := """[center][color=#ff2e2e][font_size=30]666 — RULES[/font_size][/color][/center]
[color=#ffd400]GOAL[/color]  Be the first to have all three of your dice showing [color=#ff2e2e]6[/color] at the same time.

[color=#ffd400]SETUP[/color]  Everyone starts with three dice on 3 and three cards. Three face-up cards form the MARKET.

[color=#ffd400]YOUR TURN[/color]  You have [b]2 actions[/b] ([b]3[/b] while you own a locked 6). Each action is one of:
  • [color=#46e08a]DRAW[/color] — take a card from the market (hand limit 5);
  • [color=#46e08a]PLAY[/color] — play a card from your hand.
You must spend all your actions. The market refills at the end of the turn.

[color=#ffd400]LOCKED 6[/color]  A die that reaches 6 is locked — only effect cards can change it. Locking a die gives you a free card, and +1 action every turn while you own a 6.

[color=#ffd400]CARDS[/color]
  [color=#ffd400]BASIC ±1 / ±2[/color] — raise one of your unlocked dice, OR curse a rival: they lower one of their unlocked dice (they choose).
  [color=#a77bff]DUAL[/color] — +1 to one of your dice AND −1 to a rival (rival chooses).
  [color=#ff4d4d]SMASH[/color] — a rival's locked 6 drops to 5.
  [color=#ff4d4d]REROLL[/color] — reroll one of your dice.
  [color=#ff4d4d]PACT[/color] — pick one of your dice, roll the demonic die: positive → 6, negative → 1.
  [color=#ff4d4d]GAMBLE[/color] — pick any die, roll the demonic die and add the result.
  [color=#ff4d4d]SHIELD[/color] — reaction: blocks an attack on your locked 6 automatically. Costs no action.
Demonic die: −3 −2 −1 +1 +2 +3. Dice values always stay between 1 and 6.

[color=#ffd400]CONTROLS[/color]  Drag a card onto a highlighted target — or click the card, then the target. A card with a single possible target plays on one click. Click a market card to draw. Click the card again, right-click or Esc to cancel."""


func show_win(w: int) -> void:
	turn_active = false
	mode = ""
	clear_selection()
	add_log("\n[color=#ff4040]%s shows 6 · 6 · 6![/color]" % NAMES[w])
	set_status("")
	set_hint("")
	if autoplay:
		print("WINNER: %s after %d turns" % [NAMES[w], turn_number])
		get_tree().quit()
		return
	await wait(1.2)
	win_overlay = _make_overlay(0.88)
	win_overlay.modulate.a = 0.0
	var vb: VBoxContainer = win_overlay.get_meta("vb")
	vb.add_child(_centered(_label("6 6 6", 110, Color("#ff2e2e"))))
	var head := "ETERNAL REST IS YOURS" if w == 0 else "%s ACHIEVES ETERNAL REST" % NAMES[w]
	var subt := "Your rivals suffer eternal punishment in hell." if w == 0 else "You suffer eternal punishment in hell."
	vb.add_child(_centered(_label(head, 34, Color("#ffd400") if w == 0 else Color.WHITE)))
	vb.add_child(_centered(_label(subt, 18, Color(1, 1, 1, 0.6))))
	var again := _button("PLAY AGAIN", 20)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(_restart)
	vb.add_child(again)
	var tw := create_tween()
	tw.tween_property(win_overlay, "modulate:a", 1.0, 0.8)


## Debug: save a few screenshots next to the project (used for visual checks).
func _take_shots() -> void:
	for i in 6:
		await get_tree().create_timer(4.0 if i == 0 else 9.0).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://").path_join("../shot_%d.png" % i))


func _restart() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


# ================================================================= GAME FLOW

func build_deck() -> Array:
	var d: Array = []
	for i in 17:
		d.append(mk_card("basic", 1))
	for i in 12:
		d.append(mk_card("basic", 2))
	for i in 11:
		d.append(mk_card("dual", 1))
	for i in 3:
		d.append(mk_card("smash"))
	for i in 3:
		d.append(mk_card("shield"))
	for i in 2:
		d.append(mk_card("gamble"))
	d.append(mk_card("reroll"))
	for i in 3:
		d.append(mk_card("pact"))
	return d


func mk_card(kind: String, value: int = 0) -> Dictionary:
	next_id += 1
	return {"id": next_id, "kind": kind, "value": value}


func start_game() -> void:
	game_over = false
	turn_number = 0
	dice = [[3, 3, 3], [3, 3, 3], [3, 3, 3]]
	hands = [[], [], []]
	discard = []
	market = [null, null, null]
	deck = build_deck()
	deck.shuffle()
	refresh_all()
	add_log("[color=#ff4040]The ritual begins…[/color]")
	set_status("Rolling for the first player…")
	var first: int = await roll_for_first()
	for p in 3:
		for d in 3:
			dice[p][d] = 3
			die_views[p][d].set_value(3)
			die_views[p][d].punch()
	await wait(0.5)
	set_status("Dealing…")
	for i in 3:
		await deal_to_market(i)
	for r in 3:
		for p in 3:
			await deal_to_hand(p)
	await game_loop(first)


func roll_for_first() -> int:
	var contenders: Array = [0, 1, 2]
	while true:
		var vals := {}
		for p in contenders:
			var v := randi_range(1, 6)
			vals[p] = v
			die_views[p][0].roll_to(v, 0.8)
		await wait(1.0)
		var best := 0
		for p in contenders:
			add_log("%s: rolled %d" % [pn(p), vals[p]])
			best = maxi(best, vals[p])
		var top: Array = []
		for p in contenders:
			if vals[p] == best:
				top.append(p)
		if top.size() == 1:
			add_log("%s starts." % pn(top[0]))
			await wait(0.6)
			return top[0]
		add_log("Tie — roll again!")
		contenders = top
		await wait(0.5)
	return 0


func game_loop(first: int) -> void:
	current = first
	while not game_over:
		await run_turn(current)
		if game_over:
			break
		if autoplay and turn_number > 400:
			print("STALEMATE after %d turns" % turn_number)
			get_tree().quit()
			return
		current = (current + 1) % 3


func run_turn(p: int) -> void:
	current = p
	turn_number += 1
	turn_active = true
	var bonus := has_six(p)
	actions_left = 3 if bonus else 2
	turn_started.emit(p)
	add_log("\n[color=#777]— Turn %d —[/color] %s%s" % [turn_number, pn(p), "  [color=#ff4040]+1 action[/color]" if bonus else ""])
	update_labels()
	if not is_bot(p):
		toast("YOUR TURN")
	await wait(0.25)
	while actions_left > 0 and not game_over:
		if not can_act(p):
			add_log("%s has nothing left to do." % pn(p))
			break
		if is_bot(p):
			await bot_action(p)
		else:
			await human_action()
		if game_over:
			break
		actions_left -= 1
		update_labels()
	turn_active = false
	update_labels()
	if game_over:
		return
	set_status("")
	set_hint("")
	await refill_market()
	await wait(0.15)


func can_act(p: int) -> bool:
	for c in hands[p]:
		if String(c.kind) != "shield":
			return true
	if hands[p].size() < 5:
		for m in market:
			if m != null:
				return true
	return false


# ---------------------------------------------------------------- bots

func bot_action(p: int) -> void:
	set_status("%s is scheming…" % NAMES[p])
	set_hint("")
	await wait(randf_range(0.45, 0.85))
	var act: Dictionary = BotAI.choose(p, dice, hands[p], market)
	match String(act.get("type", "")):
		"draw":
			await do_draw(p, act.slot)
		"play":
			await play_card(p, hands[p][act.idx], act.params)


# ================================================================= HUMAN INPUT

## One human action: the input handlers below validate everything and emit
## exactly one finished action (draw or a fully targeted play).
func human_action() -> void:
	clear_selection()
	mode = "turn"
	update_prompt()
	var data: Dictionary = await human_input
	mode = ""
	clear_selection()
	set_status("")
	set_hint("")
	match String(data.type):
		"draw":
			await do_draw(0, data.slot)
		"play":
			await play_card(0, data.card, data.params)


## A rival cursed the human: ask which die drops — but only if it matters.
func human_defend(attacker: int, cands: Array, n: int) -> int:
	var distinct := {}
	for x in cands:
		distinct[dice[0][x]] = true
	if distinct.size() == 1:
		return cands[0]   # every option gives the same result — no question needed
	clear_selection()
	for x in cands:
		var v: int = dice[0][x]
		targets.append(_t_die(0, x, {"die": x}, TONE_DOWN, "%d→%d" % [v, maxi(1, v - n)]))
	mode = "defend"
	_refresh_target_visuals()
	set_status("%s curses you −%d: pick which of YOUR dice drops" % [NAMES[attacker], n])
	set_hint("Click one of the highlighted dice.")
	var r: Dictionary = await human_input
	mode = ""
	clear_selection()
	set_status("")
	set_hint("")
	return int(r.die)


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		mouse_pos = (event as InputEventMouse).position
	if event is InputEventMouseMotion:
		if press_idx >= 0 and not dragging and mouse_pos.distance_to(press_pos) > DRAG_START:
			_begin_drag()
		return
	var cancel := false
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		cancel = true
	var ke := event as InputEventKey
	if ke and ke.pressed and not ke.echo:
		match ke.keycode:
			KEY_ESCAPE:
				cancel = true
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if is_instance_valid(rules_overlay):
					_close_rules()
					get_viewport().set_input_as_handled()
				elif is_instance_valid(title_overlay) and not started:
					_start_from_title()
					get_viewport().set_input_as_handled()
				elif is_instance_valid(win_overlay):
					_restart()
	if cancel:
		if is_instance_valid(rules_overlay):
			_close_rules()
			get_viewport().set_input_as_handled()
		elif mode == "turn" and (sel_idx >= 0 or dragging or press_idx >= 0):
			cancel_selection()
			get_viewport().set_input_as_handled()


## Left clicks that reach the board (overlays, buttons and the log consume their own).
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	mouse_pos = mb.position
	if mb.pressed:
		_on_press(mb.position)
	else:
		_on_release(mb.position)


func _on_press(pos: Vector2) -> void:
	if _board_blocked():
		return
	if mode == "defend":
		var t := target_at(pos)
		if t >= 0:
			mode = "busy"
			call_deferred("_emit_input", {"type": "defend", "die": int(targets[t].params.die)})
		else:
			toast("Pick one of the highlighted dice.")
		return
	if mode != "turn":
		return
	var h := hand_at(pos)
	if h >= 0:
		press_idx = h
		press_pos = pos
		return
	if sel_idx >= 0:
		var t := target_at(pos)
		if t >= 0:
			_commit_target(t)
			return
	var m := market_at(pos)
	if m >= 0:
		_try_draw(m)
		return
	if sel_idx >= 0:
		cancel_selection()


func _on_release(pos: Vector2) -> void:
	if press_idx < 0:
		return
	var idx := press_idx
	press_idx = -1
	if mode != "turn":
		_end_drag()
		return
	if dragging:
		_end_drag()
		var t := target_at(pos)
		if t >= 0:
			_commit_target(t)
		elif hand_at(pos) != idx:
			cancel_selection()   # dropped on nothing: snap back
		return
	_click_hand(idx)


func _click_hand(i: int) -> void:
	if i == sel_idx:
		cancel_selection()
		return
	var card: Dictionary = hands[0][i]
	if String(card.kind) == "shield":
		cancel_selection()
		toast("SHIELD is a reaction — it blocks the next attack on your 6 by itself.")
		return
	select_card(i)
	if targets.size() == 1 and String(targets[0].kind) != "discard":
		_commit_target(0)   # only one sensible target: no second click needed


func select_card(i: int) -> void:
	sel_idx = i
	sel_stage = 0
	sel_die = -1
	hover_target = -1
	var card: Dictionary = hands[0][i]
	targets = compute_targets(card, 0)
	if String(card.kind) == "dual" and targets.size() == 1 and String(targets[0].kind) == "die":
		sel_die = int(targets[0].params.die)   # only one of your dice can take +1
		sel_stage = 1
		targets = compute_targets(card, 1)
	set_selected(i)
	_refresh_target_visuals()
	update_prompt()


func _commit_target(t: int) -> void:
	if t < 0 or t >= targets.size() or sel_idx < 0:
		return
	var card: Dictionary = hands[0][sel_idx]
	var tg: Dictionary = targets[t]
	if String(card.kind) == "dual" and sel_stage == 0:
		sel_die = int(tg.params.die)
		sel_stage = 1
		hover_target = -1
		targets = compute_targets(card, 1)
		if targets.size() == 1:
			_commit_target(0)
			return
		_refresh_target_visuals()
		update_prompt()
		return
	_emit_action({"type": "play", "card": card, "params": tg.params})


func _try_draw(slot: int) -> void:
	if market[slot] == null:
		return
	if hands[0].size() >= 5:
		toast("Your hand is full (5) — play a card first.")
		return
	_emit_action({"type": "draw", "slot": slot})


func _emit_action(d: Dictionary) -> void:
	mode = "busy"
	_end_drag()
	call_deferred("_emit_input", d)


func _emit_input(d: Dictionary) -> void:
	human_input.emit(d)


func _begin_drag() -> void:
	if mode != "turn" or press_idx < 0 or press_idx >= hands[0].size():
		return
	var card: Dictionary = hands[0][press_idx]
	if String(card.kind) == "shield":
		return
	if sel_idx != press_idx or sel_stage != 0:
		select_card(press_idx)
	dragging = true
	drag_ghost = spawn_card(card, true, mouse_pos + GHOST_OFFSET, GHOST_SCALE)
	drag_ghost.modulate.a = 0.9
	hand_views[press_idx].modulate.a = 0.25


func _end_drag() -> void:
	dragging = false
	if is_instance_valid(drag_ghost):
		drag_ghost.queue_free()
	drag_ghost = null
	for hv in hand_views:
		hv.modulate.a = 1.0


func clear_selection() -> void:
	_end_drag()
	press_idx = -1
	sel_idx = -1
	sel_stage = 0
	sel_die = -1
	targets = []
	hover_target = -1
	set_selected(-1)
	_refresh_target_visuals()
	_refresh_interactivity()


func cancel_selection() -> void:
	clear_selection()
	update_prompt()


# ---------------------------------------------------------------- targets

## Every sensible target of a card for the human. Pointless targets (a rival with
## nothing that can drop, PACT/REROLL on your locked 6, GAMBLE that can only hurt you)
## are left out. A card with no target at all can be thrown on the DISCARD pile.
func compute_targets(card: Dictionary, stage: int = 0) -> Array:
	var res: Array = []
	match String(card.kind):
		"basic":
			var n: int = card.value
			for d in 3:
				var v: int = dice[0][d]
				if v < 6:
					res.append(_t_die(0, d, {"mode": "self", "die": d}, TONE_UP, "%d→%d" % [v, mini(6, v + n)]))
			for o in [1, 2]:
				if droppable(o):
					res.append(_t_player(o, {"mode": "rival", "target": o}, TONE_DOWN, "−%d · THEY PICK THE DIE" % n))
		"dual":
			if stage == 0:
				for d in 3:
					var v: int = dice[0][d]
					if v < 6:
						res.append(_t_die(0, d, {"die": d}, TONE_UP, "%d→%d" % [v, v + 1]))
			else:
				for o in [1, 2]:
					if droppable(o):
						res.append(_t_player(o, {"die": sel_die, "target": o}, TONE_DOWN, "−1 · THEY PICK THE DIE"))
				if res.is_empty():
					res.append(_t_player(1, {"die": sel_die, "target": 1}, TONE_DOWN, "NOTHING TO DROP"))
		"smash":
			for o in [1, 2]:
				for d in 3:
					if dice[o][d] == 6:
						res.append(_t_die(o, d, {"target": o, "die": d}, TONE_DOWN, "6→5"))
		"reroll":
			for d in 3:
				if dice[0][d] < 6:
					res.append(_t_die(0, d, {"target": 0, "die": d}, TONE_RANDOM, "1…6"))
		"pact":
			for d in 3:
				if dice[0][d] < 6:
					res.append(_t_die(0, d, {"target": 0, "die": d}, TONE_RANDOM, "1 or 6"))
		"gamble":
			for o in 3:
				for d in 3:
					var v: int = dice[o][d]
					if (o == 0 and v == 6) or (o != 0 and v == 1):
						continue
					res.append(_t_die(o, d, {"target": o, "die": d}, TONE_RANDOM, "%d…%d" % [maxi(1, v - 3), mini(6, v + 3)]))
	if res.is_empty() and String(card.kind) != "shield":
		res.append({"kind": "discard", "o": -1, "d": -1, "params": {"dud": true}, "tone": TONE_DISCARD, "preview": ""})
	return res


func _t_die(o: int, d: int, params: Dictionary, tone: Color, preview: String) -> Dictionary:
	return {"kind": "die", "o": o, "d": d, "params": params, "tone": tone, "preview": preview}


func _t_player(o: int, params: Dictionary, tone: Color, preview: String) -> Dictionary:
	return {"kind": "player", "o": o, "d": -1, "params": params, "tone": tone, "preview": preview}


func droppable(o: int) -> bool:
	for v in dice[o]:
		if v > 1 and v < 6:
			return true
	return false


func is_dud(card: Dictionary) -> bool:
	var t := compute_targets(card, 0)
	return t.size() == 1 and String(t[0].kind) == "discard"


func target_at(pos: Vector2) -> int:
	for i in targets.size():
		var t: Dictionary = targets[i]
		if String(t.kind) == "die" and _die_rect(int(t.o), int(t.d)).grow(6.0).has_point(pos):
			return i
	for i in targets.size():
		var t: Dictionary = targets[i]
		if String(t.kind) == "player" and (PANEL_RECTS[int(t.o)] as Rect2).has_point(pos):
			return i
		if String(t.kind) == "discard" and Rect2(DISCARD_POS, CARD_SIZE).grow(10.0).has_point(pos):
			return i
	return -1


func hand_at(pos: Vector2) -> int:
	for i in range(hand_views.size() - 1, -1, -1):
		var hv = hand_views[i]
		if Rect2(Vector2(hv.position.x, HAND_Y - 28.0), CARD_SIZE + Vector2(0, 28)).has_point(pos):
			return i
	return -1


func market_at(pos: Vector2) -> int:
	for i in 3:
		if market[i] != null and Rect2(MARKET_POS[i] - Vector2(0, 10), CARD_SIZE + Vector2(0, 10)).has_point(pos):
			return i
	return -1


func _die_rect(o: int, d: int) -> Rect2:
	var dv = die_views[o][d]
	return Rect2((PANEL_RECTS[o] as Rect2).position + dv.position, dv.size)


func _player_target(p: int) -> int:
	for i in targets.size():
		if String(targets[i].kind) == "player" and int(targets[i].o) == p:
			return i
	return -1


func _valid_hover() -> bool:
	return hover_target >= 0 and hover_target < targets.size()


func _board_blocked() -> bool:
	return is_instance_valid(rules_overlay) or is_instance_valid(title_overlay) or is_instance_valid(win_overlay)


func _update_hover() -> void:
	var nh := -1
	var nm := -1
	var nt := -1
	if not _board_blocked():
		nh = hand_at(mouse_pos)
		if nh < 0:
			nm = market_at(mouse_pos)
		if (mode == "turn" or mode == "defend") and not targets.is_empty():
			nt = target_at(mouse_pos)
	hover_hand = nh
	hover_market = nm
	if nt != hover_target:
		hover_target = nt
		_refresh_target_visuals()
	_update_info_box()
	_update_cursor()


## The cursor tells what a click would do, so the player never has to click to find out.
func _update_cursor() -> void:
	var cur := Control.CURSOR_ARROW
	if hover_target >= 0:
		cur = Control.CURSOR_POINTING_HAND
	elif mode == "turn" and not dragging:
		if hover_hand >= 0 and hover_hand < hands[0].size():
			var shield: bool = String(hands[0][hover_hand].kind) == "shield"
			cur = Control.CURSOR_FORBIDDEN if shield else Control.CURSOR_POINTING_HAND
		elif hover_market >= 0:
			cur = Control.CURSOR_FORBIDDEN if hands[0].size() >= 5 else Control.CURSOR_POINTING_HAND
	if mouse_default_cursor_shape != cur:
		mouse_default_cursor_shape = cur


## Push the target list into the views: highlight, tone and hover preview.
func _refresh_target_visuals() -> void:
	for o in 3:
		for d in 3:
			var dv = die_views[o][d]
			dv.selectable = false
			dv.hover = false
			dv.preview = ""
		tgt_labels[o].text = ""
	var has_discard := false
	for i in targets.size():
		var t: Dictionary = targets[i]
		match String(t.kind):
			"die":
				var dv = die_views[int(t.o)][int(t.d)]
				dv.tone = t.tone
				dv.selectable = true
				dv.hover = i == hover_target
				dv.preview = String(t.preview)
			"player":
				var tl: Label = tgt_labels[int(t.o)]
				tl.text = String(t.preview)
				tl.add_theme_color_override("font_color", t.tone)
			"discard":
				has_discard = true
	discard_hl.visible = has_discard


## Dim what can't be used right now, so the player doesn't have to click to find out.
func _refresh_interactivity() -> void:
	var my_turn := mode == "turn"
	var full: bool = hands[0].size() >= 5
	for i in 3:
		market_views[i].dim = my_turn and full
	for i in hand_views.size():
		var dimmed := false
		if my_turn and i < hands[0].size():
			var c: Dictionary = hands[0][i]
			dimmed = String(c.kind) == "shield" or is_dud(c)
		hand_views[i].dim = dimmed


func _update_info_box() -> void:
	var card = null
	var anchor := Vector2.ZERO
	if not dragging:
		if hover_hand >= 0 and hover_hand < hands[0].size() and hover_hand < hand_views.size():
			card = hands[0][hover_hand]
			anchor = Vector2(hand_views[hover_hand].position.x + 50.0, HAND_Y - 34.0)
		elif hover_market >= 0 and market[hover_market] != null:
			card = market[hover_market]
			anchor = Vector2(MARKET_POS[hover_market].x + 50.0, MARKET_POS[hover_market].y - 14.0)
	if card == null:
		info_box.visible = false
		return
	var txt := card_desc(card)
	if info_label.text != txt:
		info_label.text = txt
		info_box.reset_size()
	var sz: Vector2 = info_box.get_combined_minimum_size()
	info_box.size = sz
	info_box.position = Vector2(clampf(anchor.x - sz.x / 2.0, 330.0, 950.0 - sz.x), anchor.y - sz.y)
	info_box.visible = true


func update_prompt() -> void:
	if mode == "turn":
		if sel_idx < 0:
			var acts := "%d action%s left" % [actions_left, "" if actions_left == 1 else "s"]
			if hands[0].size() >= 5:
				set_status("YOUR TURN — %s · hand is full, play a card" % acts)
			else:
				set_status("YOUR TURN — %s" % acts)
			set_hint("Drag a card onto a target, or click the card and then the target · click a market card to draw it")
		else:
			set_status(_sel_prompt())
			set_hint("Click the card again, right-click or Esc to cancel · click another card to switch")
	_refresh_interactivity()


func _sel_prompt() -> String:
	var card: Dictionary = hands[0][sel_idx]
	if targets.size() == 1 and String(targets[0].kind) == "discard":
		return "%s has no target now — drop it on DISCARD to throw it away" % card_name(card)
	match String(card.kind):
		"basic":
			var n: int = card.value
			return "BASIC — your die +%d, or a rival −%d (they pick the die)" % [n, n]
		"dual":
			if sel_stage == 0:
				return "DUAL — pick YOUR die for +1"
			return "DUAL — now pick a RIVAL for −1 (they pick the die)"
		"smash":
			return "SMASH — pick a rival's locked 6"
		"reroll":
			return "REROLL — pick one of your dice"
		"pact":
			return "PACT — pick your die: demonic + makes it 6, − makes it 1"
		"gamble":
			return "GAMBLE — pick any die: the demonic die adds −3…+3"
	return ""


# ================================================================= CARD RESOLUTION

func play_card(p: int, card: Dictionary, params: Dictionary) -> void:
	var idx: int = hands[p].find(card)
	if idx < 0:
		return
	var from := hand_slot(p, idx, hands[p].size())
	if p == 0 and idx < hand_views.size():
		from.y = hand_views[idx].position.y
	var sc := 1.0 if p == 0 else BOT_HAND_SCALE
	hands[p].remove_at(idx)
	refresh_hand(p)
	var v = spawn_card(card, true, from, sc)
	await tween_card(v, PLAY_POS, 1.3, 0.3)
	add_log("%s plays %s" % [pn(p), card_bb(card)])
	await wait(0.35)
	if params.get("dud", false):
		add_log("  …no effect.")
	else:
		await resolve(p, card, params)
	await tween_card(v, DISCARD_POS, 1.0, 0.25)
	v.queue_free()
	discard.append(card)
	update_piles()


func resolve(p: int, card: Dictionary, params: Dictionary) -> void:
	match String(card.kind):
		"basic":
			var n: int = card.value
			if params.mode == "self":
				await change_die(p, params.die, n)
			else:
				await attack(p, params.target, n)
		"dual":
			await change_die(p, params.die, 1)
			if game_over:
				return
			await attack(p, params.target, 1)
		"smash":
			var o: int = params.target
			var d: int = params.die
			if dice[o][d] != 6:
				add_log("  …the target is no longer locked.")
				return
			if await try_shield(o, p, card):
				return
			await set_die(o, d, 5)
		"reroll":
			var d: int = params.die
			var v: int = forced_rolls.pop_front() if not forced_rolls.is_empty() else randi_range(1, 6)
			await die_views[p][d].roll_to(v, 0.7)
			await set_die(p, d, v, false)
		"pact":
			var d: int = params.die
			var face: int = await roll_demon()
			await set_die(p, d, 6 if face > 0 else 1)
		"gamble":
			var o: int = params.target
			var d: int = params.die
			if o != p and dice[o][d] == 6:
				if await try_shield(o, p, card):
					return
			var face: int = await roll_demon()
			await set_die(o, d, clampi(dice[o][d] + face, 1, 6))


func change_die(o: int, d: int, delta: int) -> void:
	var nv := clampi(int(dice[o][d]) + delta, 1, 6)
	await set_die(o, d, nv)


## A rival is cursed with −n: they choose which unlocked die (that can still drop) loses it.
func attack(attacker: int, o: int, n: int) -> void:
	var cands: Array = []
	for d in 3:
		var v: int = dice[o][d]
		if v > 1 and v < 6:
			cands.append(d)
	if cands.is_empty():
		add_log("  …%s has no die that can drop." % pn(o))
		return
	var d: int
	if is_bot(o):
		d = BotAI.choose_defend_die(dice[o], cands, n)
		await wait(0.25)
	else:
		d = await human_defend(attacker, cands, n)
	await change_die(o, d, -n)


func set_die(o: int, d: int, v: int, punch: bool = true) -> void:
	var old: int = dice[o][d]
	dice[o][d] = v
	var view = die_views[o][d]
	view.set_value(v)
	if punch:
		view.punch()
	if v != old:
		var txt := ("+%d" % (v - old)) if v > old else str(v - old)
		float_text(die_center(o, d), txt, TONE_UP if v > old else Color("#ff4d4d"))
		add_log("  %s die %d: %d → %d" % [pn(o), d + 1, old, v])
	else:
		add_log("  %s die %d stays at %d" % [pn(o), d + 1, v])
	update_labels()
	await wait(0.35)
	if v == 6 and old != 6:
		view.lock_burst()
		add_log("  [color=#ff4040]%s LOCKS a 6![/color]" % NAMES[o])
		if check_win(o):
			return
		await free_card(o)
	elif old == 6 and v != 6:
		add_log("  %s loses a locked 6." % pn(o))
	update_labels()


func check_win(o: int) -> bool:
	for d in 3:
		if dice[o][d] != 6:
			return false
	game_over = true
	show_win(o)
	return true


## SHIELD is used automatically — declining it is almost never right, so no dialog.
func try_shield(o: int, attacker: int, card: Dictionary) -> bool:
	var si := -1
	for i in hands[o].size():
		if String(hands[o][i].kind) == "shield":
			si = i
			break
	if si < 0:
		return false
	var sh: Dictionary = hands[o][si]
	var from := hand_slot(o, si, hands[o].size())
	var sc := 1.0 if o == 0 else BOT_HAND_SCALE
	hands[o].remove_at(si)
	refresh_hand(o)
	var v = spawn_card(sh, true, from, sc)
	await tween_card(v, PLAY_POS + Vector2(50, 30), 1.3, 0.3)
	add_log("  [color=#ff4040]%s raises a SHIELD against %s's %s![/color]" % [NAMES[o], NAMES[attacker], card_name(card)])
	toast("YOUR SHIELD BLOCKS IT!" if o == 0 and not is_bot(0) else "%s'S SHIELD!" % NAMES[o])
	await wait(0.6)
	await tween_card(v, DISCARD_POS, 1.0, 0.25)
	v.queue_free()
	discard.append(sh)
	update_piles()
	return true


func roll_demon() -> int:
	var face: int = forced_rolls.pop_front() if not forced_rolls.is_empty() else DEMON_FACES.pick_random()
	await demon_die.roll_to(face, 0.9)
	add_log("  Demonic die: [color=#ff4040]%+d[/color]" % face)
	await wait(0.3)
	return face


# ================================================================= CARD MOVEMENT

func draw_from_deck():
	if deck.is_empty():
		if discard.is_empty():
			return null
		deck = discard.duplicate()
		discard.clear()
		deck.shuffle()
		add_log("[color=#888]Discard pile reshuffled into the deck.[/color]")
	var c = deck.pop_back()
	update_piles()
	return c


func do_draw(p: int, slot: int) -> void:
	var c: Dictionary = market[slot]
	market[slot] = null
	refresh_market()
	var n: int = hands[p].size()
	make_room(p, n + 1)
	var sc := 1.0 if p == 0 else BOT_HAND_SCALE
	var v = spawn_card(c, true, MARKET_POS[slot], 1.0)
	add_log("%s takes %s" % [pn(p), card_bb(c)])
	await tween_card(v, hand_slot(p, n, n + 1), sc, 0.35)
	if p != 0:
		await flip_card(v)
	v.queue_free()
	hands[p].append(c)
	refresh_hand(p)


func deal_to_hand(p: int) -> bool:
	var c = draw_from_deck()
	if c == null:
		return false
	var n: int = hands[p].size()
	make_room(p, n + 1)
	var sc := 1.0 if p == 0 else BOT_HAND_SCALE
	var v = spawn_card(c, false, DECK_POS, 1.0)
	await tween_card(v, hand_slot(p, n, n + 1), sc, 0.22)
	if p == 0:
		await flip_card(v)
	v.queue_free()
	hands[p].append(c)
	refresh_hand(p)
	return true


func free_card(o: int) -> void:
	if hands[o].size() >= 5:
		add_log("  (hand full — no free card)")
		return
	if await deal_to_hand(o):
		add_log("  %s draws a free card." % pn(o))
	else:
		add_log("  (no cards left — no free card)")


func deal_to_market(i: int) -> void:
	var c = draw_from_deck()
	if c == null:
		return
	var v = spawn_card(c, false, DECK_POS, 1.0)
	await tween_card(v, MARKET_POS[i], 1.0, 0.25)
	await flip_card(v)
	v.queue_free()
	market[i] = c
	refresh_market()


func refill_market() -> void:
	for i in 3:
		if market[i] == null:
			await deal_to_market(i)


func spawn_card(card: Dictionary, face_up: bool, pos: Vector2, sc: float):
	var v = CardView.new()
	v.card = card
	v.face_up = face_up
	v.position = pos
	v.scale = Vector2(sc, sc)
	fx.add_child(v)
	return v


func tween_card(v, to: Vector2, sc: float, dur: float) -> void:
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "position", to, dur)
	tw.tween_property(v, "scale", Vector2(sc, sc), dur)
	await tw.finished


func flip_card(v) -> void:
	var w: float = v.size.x * v.scale.x
	var p0: Vector2 = v.position
	var sx: float = v.scale.x
	var tw := create_tween().set_parallel(true)
	tw.tween_property(v, "scale:x", 0.01, 0.1)
	tw.tween_property(v, "position:x", p0.x + w / 2.0, 0.1)
	await tw.finished
	v.face_up = not v.face_up
	v.queue_redraw()
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(v, "scale:x", sx, 0.1)
	tw2.tween_property(v, "position:x", p0.x, 0.1)
	await tw2.finished


func hand_slot(p: int, i: int, n: int) -> Vector2:
	if p == 0:
		var total := n * 112.0 - 12.0
		return Vector2(640.0 - total / 2.0 + i * 112.0, HAND_Y)
	return PANEL_RECTS[p].position + BOT_HAND_OFFSET + Vector2(i * 18.0, 0)


func make_room(p: int, n_new: int) -> void:
	if p != 0:
		return
	for i in hand_views.size():
		var hv = hand_views[i]
		var tw: Tween = hv.create_tween()
		tw.tween_property(hv, "position:x", hand_slot(0, i, n_new).x, 0.2)


func die_center(o: int, d: int) -> Vector2:
	var dv = die_views[o][d]
	return PANEL_RECTS[o].position + dv.position + dv.size / 2.0


# ================================================================= REFRESH

func refresh_all() -> void:
	for p in 3:
		refresh_hand(p)
		for d in 3:
			die_views[p][d].set_value(dice[p][d])
	refresh_market()
	update_piles()
	update_labels()


func refresh_hand(p: int) -> void:
	var root: Control = hand_roots[p]
	for c in root.get_children():
		root.remove_child(c)
		c.queue_free()
	if p == 0:
		hand_views = []
	var n: int = hands[p].size()
	for i in n:
		var cv = CardView.new()
		cv.card = hands[p][i]
		if p == 0:
			cv.face_up = true
			cv.position = hand_slot(0, i, n)
			cv.base_y = HAND_Y
			hand_views.append(cv)
		else:
			cv.face_up = false
			cv.scale = Vector2(BOT_HAND_SCALE, BOT_HAND_SCALE)
			cv.position = Vector2(i * 18.0, 0)
		root.add_child(cv)
	update_labels()


func set_selected(idx: int) -> void:
	for i in hand_views.size():
		hand_views[i].selected = i == idx


func refresh_market() -> void:
	for i in 3:
		var v = market_views[i]
		v.visible = market[i] != null
		if market[i] != null:
			v.card = market[i]
			v.position.y = MARKET_POS[i].y
			v.queue_redraw()


func update_piles() -> void:
	deck_view.visible = not deck.is_empty()
	deck_label.text = "DECK · %d" % deck.size()
	discard_view.visible = not discard.is_empty()
	if not discard.is_empty():
		discard_view.card = discard.back()
		discard_view.queue_redraw()
	discard_label.text = "DISCARD · %d" % discard.size()


func update_labels() -> void:
	for p in 3:
		action_labels[p].text = ("ACTIONS LEFT: %d" % actions_left) if (p == current and turn_active) else ""
		var extra := "   ·   LOCKED 6 → +1 ACTION" if has_six(p) else ""
		info_labels[p].text = "HAND %d/5%s" % [hands[p].size(), extra]


func set_status(t: String) -> void:
	status_label.text = t


func set_hint(t: String) -> void:
	hint_label.text = t


func toast(msg: String) -> void:
	if toast_tween and toast_tween.is_valid():
		toast_tween.kill()
	toast_label.text = msg
	toast_label.modulate.a = 1.0
	toast_tween = create_tween()
	toast_tween.tween_interval(1.4)
	toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.5)


func float_text(pos: Vector2, txt: String, col: Color) -> void:
	var l := _label(txt, 28, col)
	l.position = pos - Vector2(50, 20)
	l.size = Vector2(100, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	fx.add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 50.0, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func add_log(t: String) -> void:
	log_label.append_text(t + "\n")


## Tween-based wait: bound to this node, so a restart mid-animation simply drops the
## coroutine instead of resuming it on a freed instance.
func wait(t: float) -> void:
	var tw := create_tween()
	tw.tween_interval(t)
	await tw.finished


# ================================================================= HELPERS

func is_bot(p: int) -> bool:
	return autoplay or p != 0


func has_six(p: int) -> bool:
	return (dice[p] as Array).has(6)


func card_total() -> int:
	var n := deck.size() + discard.size()
	for c in market:
		if c != null:
			n += 1
	for h in hands:
		n += (h as Array).size()
	return n


func pn(p: int) -> String:
	return "[color=%s]%s[/color]" % [NAME_COLORS[p], NAMES[p]]


func card_name(c: Dictionary) -> String:
	match String(c.kind):
		"basic":
			return "BASIC ±%d" % int(c.value)
		"dual":
			return "DUAL +1/−1"
	return String(c.kind).to_upper()


func card_bb(c: Dictionary) -> String:
	var col := "#ff4d4d"
	if String(c.kind) == "basic":
		col = "#ffd400"
	elif String(c.kind) == "dual":
		col = "#a77bff"
	return "[color=%s]%s[/color]" % [col, card_name(c)]


func card_desc(c: Dictionary) -> String:
	match String(c.kind):
		"basic":
			var n := int(c.value)
			return "BASIC ±%d\n+%d to one of your unlocked dice,\nor a rival drops one of theirs by %d\n(they choose which)." % [n, n, n]
		"dual":
			return "DUAL\n+1 to one of your unlocked dice AND\n−1 to a rival (they choose which)."
		"smash":
			return "SMASH\nA rival's locked 6 drops to 5."
		"shield":
			return "SHIELD · reaction\nBlocks the next attack on your locked 6\nby itself. Costs no action."
		"gamble":
			return "GAMBLE\nPick any die and roll the demonic die:\nthe result (−3…+3) is added to it."
		"reroll":
			return "REROLL\nReroll one of your dice."
		"pact":
			return "PACT\nPick one of your dice, roll the demonic die:\npositive → it becomes 6, negative → 1."
	return ""

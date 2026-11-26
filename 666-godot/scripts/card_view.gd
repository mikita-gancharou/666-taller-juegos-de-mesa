extends Control
## Procedurally drawn card (100x140). Face-up art mimics the printed 666 cards.
## Passive view: main.gd handles all input (click, drag, hover).

const RED := Color("#ff2e2e")
const YELLOW := Color("#ffd400")
const PURPLE := Color("#6d2ed9")
const BODY := Color("#111118")
const EDGE := Color("#2c2c38")
const GREY := Color(1, 1, 1, 0.5)

var card: Dictionary = {}
var face_up: bool = true
var selected: bool = false:
	set(v):
		if v != selected:
			selected = v
			queue_redraw()
var dim: bool = false:
	set(v):
		if v != dim:
			dim = v
			queue_redraw()
var base_y: float = 0.0
var _t: float = 0.0


func _init() -> void:
	size = Vector2(100, 140)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if selected:
		_t += delta
		queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var w := size.x
	var h := size.y
	if not face_up:
		_draw_back(w, h)
		return
	var kind := String(card.get("kind", "basic"))
	var val: int = card.get("value", 1)
	var head := YELLOW
	var head_txt := Color("#111118")
	var foot := Color("#2e2a12")
	if kind == "dual":
		head = PURPLE
		head_txt = Color.WHITE
		foot = Color("#24164a")
	elif kind != "basic":
		head = RED
		head_txt = Color.WHITE
		foot = Color("#4a1418")

	_box(Rect2(0, 0, w, h), BODY, 8, EDGE, 1)
	if kind == "dual":
		draw_colored_polygon(PackedVector2Array([Vector2(1, 90), Vector2(w - 1, 64), Vector2(w - 1, 112), Vector2(1, 112)]), Color("#21131f"))
	_box_top(Rect2(0, 0, w, 22), head, 8)
	_text(_title(kind), Vector2(w / 2.0, 11), 12, head_txt)

	match kind:
		"basic":
			_icon_basic(w, val)
		"dual":
			_icon_dual()
		"smash":
			_icon_smash(w)
		"shield":
			_icon_shield(w)
		"gamble":
			_icon_gamble(w)
		"reroll":
			_icon_reroll(w)
		"pact":
			_icon_pact(w)

	draw_rect(Rect2(0, 112, w, 15), foot)
	_text(_footer(kind, val), Vector2(w / 2.0, 119.5), 7, Color(1, 1, 1, 0.9))
	_text("6 · 6 · 6", Vector2(w / 2.0, 133), 6, Color(1, 1, 1, 0.22))

	if selected:
		var a := 0.6 + 0.4 * sin(_t * 6.0)
		_box_outline(Rect2(-3, -3, w + 6, h + 6), Color(1, 0.83, 0, a), 10, 3)
	if dim:
		_box(Rect2(0, 0, w, h), Color(0, 0, 0, 0.5), 8)


func _draw_back(w: float, h: float) -> void:
	_box(Rect2(0, 0, w, h), Color("#0a0a0e"), 8, EDGE, 1)
	var c := Vector2(w / 2.0, 58)
	draw_arc(c, 28, 0, TAU, 48, RED, 2.0, true)
	draw_arc(c, 24, 0, TAU, 48, Color(1, 0.18, 0.18, 0.45), 1.0, true)
	var tri := PackedVector2Array([
		c + Vector2.from_angle(deg_to_rad(-150)) * 28.0,
		c + Vector2.from_angle(deg_to_rad(-30)) * 28.0,
		c + Vector2.from_angle(deg_to_rad(90)) * 28.0,
		c + Vector2.from_angle(deg_to_rad(-150)) * 28.0,
	])
	draw_polyline(tri, RED, 2.0, true)
	draw_arc(c, 5, 0, TAU, 24, RED, 1.5, true)
	_text("666", Vector2(w / 2.0, 104), 16, RED)


func _icon_basic(w: float, n: int) -> void:
	if n == 1:
		_arrow(Vector2(w / 2.0, 46), 30, 30, true, YELLOW)
		_arrow(Vector2(w / 2.0, 73), 26, 24, false, PURPLE)
	else:
		_arrow(Vector2(w / 2.0 - 10, 44), 26, 26, true, YELLOW)
		_arrow(Vector2(w / 2.0 + 10, 50), 26, 26, true, Color("#c9a800"))
		_arrow(Vector2(w / 2.0 - 10, 76), 24, 22, false, PURPLE)
		_arrow(Vector2(w / 2.0 + 10, 72), 24, 22, false, Color("#5a24b8"))
	_text("±%d" % n, Vector2(w / 2.0, 100), 20, Color.WHITE)


func _icon_dual() -> void:
	_text("YOU", Vector2(22, 46), 8, GREY)
	_arrow(Vector2(44, 46), 16, 18, true, Color("#8a4dff"))
	_text("+1", Vector2(70, 46), 20, Color.WHITE)
	_text("−1", Vector2(30, 88), 20, Color.WHITE)
	_arrow(Vector2(56, 88), 16, 18, false, Color("#8a4dff"))
	_text("RIVAL", Vector2(80, 88), 8, GREY)


func _icon_smash(w: float) -> void:
	var c := Vector2(w / 2.0 - 4, 60)
	_box_outline(Rect2(c - Vector2(19, 19), Vector2(38, 38)), RED, 8, 3)
	for p in [Vector2(-8, -10), Vector2(-8, 0), Vector2(-8, 10), Vector2(8, -10), Vector2(8, 0), Vector2(8, 10)]:
		draw_circle(c + p, 3.2, RED)
	var o := c + Vector2(22, -30)
	draw_polyline(PackedVector2Array([o + Vector2(6, 0), o + Vector2(-2, 10), o + Vector2(5, 10), o + Vector2(-3, 22)]), Color.WHITE, 2.5, true)
	_text("6 → 5", Vector2(w / 2.0, 100), 13, Color.WHITE)


func _icon_shield(w: float) -> void:
	_text("· REACTION ·", Vector2(w / 2.0, 31), 7, RED)
	var cx := w / 2.0
	var pts := PackedVector2Array([
		Vector2(cx, 39), Vector2(cx + 21, 46), Vector2(cx + 19, 70), Vector2(cx, 92),
		Vector2(cx - 19, 70), Vector2(cx - 21, 46), Vector2(cx, 39)])
	draw_polyline(pts, RED, 3.0, true)
	_star(Vector2(cx, 63), 11, 4.5, RED)


func _icon_gamble(w: float) -> void:
	var c := Vector2(w / 2.0, 64)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-19, -14), c + Vector2(-22, -30), c + Vector2(-9, -19)]), RED)
	draw_colored_polygon(PackedVector2Array([c + Vector2(19, -14), c + Vector2(22, -30), c + Vector2(9, -19)]), RED)
	_box_outline(Rect2(c - Vector2(19, 19), Vector2(38, 38)), RED, 8, 3)
	_star(c, 10, 4, RED)
	_text("ROLL THE DEMONIC DIE", Vector2(w / 2.0, 102), 7, GREY)


func _icon_reroll(w: float) -> void:
	var c := Vector2(w / 2.0, 62)
	_box_outline(Rect2(c - Vector2(15, 15), Vector2(30, 30)), RED, 6, 3)
	draw_circle(c + Vector2(-6, -6), 3.2, RED)
	draw_circle(c + Vector2(6, 6), 3.2, RED)
	draw_arc(c, 27, deg_to_rad(-160), deg_to_rad(-40), 20, RED, 3.0, true)
	draw_arc(c, 27, deg_to_rad(20), deg_to_rad(140), 20, RED, 3.0, true)
	_tri(c + Vector2.from_angle(deg_to_rad(-40)) * 27.0, deg_to_rad(50), RED)
	_tri(c + Vector2.from_angle(deg_to_rad(140)) * 27.0, deg_to_rad(230), RED)


func _icon_pact(w: float) -> void:
	var c := Vector2(w / 2.0, 60)
	draw_arc(c, 27, 0, TAU, 48, RED, 2.5, true)
	draw_arc(c, 22, 0, TAU, 48, Color(1, 0.18, 0.18, 0.5), 1.0, true)
	var pts := PackedVector2Array()
	for i in 6:
		var k := (i * 2) % 5
		pts.append(c + Vector2.from_angle(deg_to_rad(-90.0 + 72.0 * k)) * 22.0)
	draw_polyline(pts, RED, 2.0, true)
	_text("+ → 6     − → 1", Vector2(w / 2.0, 100), 10, Color.WHITE)


# ---------------------------------------------------------------- helpers

static func _title(kind: String) -> String:
	return kind.to_upper()


static func _footer(kind: String, val: int) -> String:
	match kind:
		"basic":
			return "YOU +%d · OR · RIVAL −%d" % [val, val]
		"dual":
			return "BOTH AT ONCE"
		"smash":
			return "A RIVAL'S LOCKED 6"
		"shield":
			return "CANCELS AN ATTACK"
		"gamble":
			return "YOURS OR A RIVAL'S"
	return "ONE OF YOUR DICE"


func _text(txt: String, c: Vector2, fs: int, col: Color) -> void:
	var f := get_theme_default_font()
	var base := c.y + (f.get_ascent(fs) - f.get_descent(fs)) / 2.0
	draw_string(f, Vector2(c.x - 100.0, base), txt, HORIZONTAL_ALIGNMENT_CENTER, 200.0, fs, col)


func _box(r: Rect2, col: Color, rad: float, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(rad))
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	draw_style_box(sb, r)


func _box_top(r: Rect2, col: Color, rad: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = int(rad)
	sb.corner_radius_top_right = int(rad)
	draw_style_box(sb, r)


func _box_outline(r: Rect2, col: Color, rad: float, bw: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = col
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(int(rad))
	draw_style_box(sb, r)


func _arrow(c: Vector2, aw: float, ah: float, up: bool, col: Color) -> void:
	var sgn := -1.0 if up else 1.0
	var tip := c + Vector2(0, sgn * ah / 2.0)
	var tail_y := c.y - sgn * ah / 2.0
	var sw := aw * 0.2
	var pts := PackedVector2Array([
		tip, Vector2(c.x + aw / 2.0, c.y), Vector2(c.x + sw, c.y), Vector2(c.x + sw, tail_y),
		Vector2(c.x - sw, tail_y), Vector2(c.x - sw, c.y), Vector2(c.x - aw / 2.0, c.y)])
	draw_colored_polygon(pts, col)


func _star(c: Vector2, r_out: float, r_in: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rad := r_out if i % 2 == 0 else r_in
		pts.append(c + Vector2.from_angle(deg_to_rad(-90.0 + 36.0 * i)) * rad)
	draw_colored_polygon(pts, col)


func _tri(p: Vector2, ang: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		p + Vector2.from_angle(ang) * 7.0,
		p + Vector2.from_angle(ang + 2.4) * 6.0,
		p + Vector2.from_angle(ang - 2.4) * 6.0]), col)

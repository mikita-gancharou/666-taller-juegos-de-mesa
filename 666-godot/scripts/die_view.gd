extends Control
## A d6 (or the demonic die) drawn procedurally, with roll / punch / lock animations.
## Passive view: main.gd handles all input and only toggles the highlight state here.

const DEMON := [-3, -2, -1, 1, 2, 3]
const PIPS := {
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.27, 0.27), Vector2(0.73, 0.73)],
	3: [Vector2(0.27, 0.27), Vector2(0.5, 0.5), Vector2(0.73, 0.73)],
	4: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
	5: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.5, 0.5), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
	6: [Vector2(0.28, 0.24), Vector2(0.28, 0.5), Vector2(0.28, 0.76), Vector2(0.72, 0.24), Vector2(0.72, 0.5), Vector2(0.72, 0.76)],
}

var value: int = 3
var owner_idx: int = 0
var die_idx: int = 0
var demonic: bool = false
# Highlight state. Every change must trigger a redraw: _process only redraws while a
# die is highlighted, so clearing the flag without one left a frozen ring on screen
# (the "dice highlighted outside your turn" bug).
var selectable: bool = false:
	set(v):
		if v != selectable:
			selectable = v
			queue_redraw()
var hover: bool = false:
	set(v):
		if v != hover:
			hover = v
			queue_redraw()
var preview: String = "":
	set(v):
		if v != preview:
			preview = v
			queue_redraw()
var tone: Color = Color("#ffd400"):
	set(v):
		if v != tone:
			tone = v
			queue_redraw()
var burst: float = 0.0
var _t: float = 0.0


func setup(s: float) -> void:
	size = Vector2(s, s)
	custom_minimum_size = size
	pivot_offset = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	if selectable or burst > 0.0 or (value == 6 and not demonic):
		queue_redraw()


func set_value(v: int) -> void:
	value = v
	queue_redraw()


func punch() -> void:
	scale = Vector2(1.35, 1.35)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func lock_burst() -> void:
	burst = 0.01
	var tw := create_tween()
	tw.tween_property(self, "burst", 1.0, 0.7)
	tw.tween_callback(_end_burst)


func _end_burst() -> void:
	burst = 0.0
	queue_redraw()


func roll_to(final: int, dur: float = 0.7) -> void:
	var el := 0.0
	while el < dur:
		value = DEMON.pick_random() if demonic else randi_range(1, 6)
		rotation = randf_range(-0.4, 0.4)
		queue_redraw()
		# Tween (bound to this node) instead of a SceneTree timer: if the scene is
		# restarted mid-roll the coroutine dies with the node instead of erroring.
		var tw := create_tween()
		tw.tween_interval(0.06)
		await tw.finished
		el += 0.06
	rotation = 0.0
	value = final
	queue_redraw()
	punch()


func _draw() -> void:
	var s := size.x
	var r := Rect2(Vector2.ZERO, size)
	if demonic:
		_draw_demonic(s)
		return
	var locked := value == 6
	if locked:
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		for i in 3:
			var g := 3.0 + i * 4.0 + pulse * 3.0
			_box(r.grow(g), Color(1, 0.12, 0.12, 0.08 + 0.05 * pulse), s * 0.2 + g)
	var body := Color("#ff2e2e") if locked else Color("#ece6da")
	var pip := Color("#1a0505") if locked else Color("#15151c")
	_box(r, body, s * 0.18, Color(0, 0, 0, 0.35), 2)
	if PIPS.has(value):
		for pp in PIPS[value]:
			draw_circle(pp * s, s * 0.085, pip)
	if selectable:
		var a := 1.0 if hover else 0.5 + 0.45 * sin(_t * 6.0)
		_box_outline(r.grow(5), Color(tone, a), s * 0.2 + 5, 5 if hover else 3)
		if hover and preview != "":
			_badge(preview, s)
	if burst > 0.0:
		draw_arc(Vector2(s, s) * 0.5, s * 0.5 + burst * s * 0.7, 0, TAU, 48, Color(1, 0.2, 0.2, 1.0 - burst), 4.0, true)


## Small "3→5" style label sitting on the top edge of the die.
func _badge(txt: String, s: float) -> void:
	var f := get_theme_default_font()
	var fs := 13
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16.0
	var rr := Rect2(Vector2((s - w) / 2.0, -12), Vector2(w, 22))
	_box(rr, Color("#111118"), 6, tone, 2)
	var base := rr.position.y + 11.0 + (f.get_ascent(fs) - f.get_descent(fs)) / 2.0
	draw_string(f, Vector2(rr.position.x, base), txt, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color.WHITE)


func _draw_demonic(s: float) -> void:
	var red := Color("#ff2e2e")
	draw_colored_polygon(PackedVector2Array([Vector2(s * 0.10, s * 0.12), Vector2(s * 0.02, -s * 0.20), Vector2(s * 0.34, s * 0.04)]), red)
	draw_colored_polygon(PackedVector2Array([Vector2(s * 0.90, s * 0.12), Vector2(s * 0.98, -s * 0.20), Vector2(s * 0.66, s * 0.04)]), red)
	_box(Rect2(Vector2.ZERO, size), Color("#0a0a0e"), s * 0.18, red, 3)
	var txt := "?" if value == 0 else ("%+d" % value)
	var f := get_theme_default_font()
	var fs := int(s * 0.42)
	var base := s / 2.0 + (f.get_ascent(fs) - f.get_descent(fs)) / 2.0
	draw_string(f, Vector2(0, base), txt, HORIZONTAL_ALIGNMENT_CENTER, s, fs, red)


func _box(r: Rect2, col: Color, rad: float, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(rad))
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	draw_style_box(sb, r)


func _box_outline(r: Rect2, col: Color, rad: float, bw: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = col
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(int(rad))
	draw_style_box(sb, r)

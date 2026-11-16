class_name MenuRow
extends Control
## One line of a menu, drawn by hand so nothing looks like the default theme: a button, a slider
## (0 to 1) or a choice that cycles through words. Keyboard, gamepad (the ui_* actions) and
## mouse all work; hovering takes the focus so there is only ever one highlighted row.

signal activated
signal changed

enum Kind { BUTTON, SLIDER, CHOICE }

const SLIDER_STEP := 0.05

var kind := Kind.BUTTON
var text := ""
var px := 30
var tracking := 6
var weight := 400
var value := 1.0
var choices := PackedStringArray()
var index := 0
var enabled := true
var note := ""  # a small word after a button's text ("MISSION 2" under Continue, later)
var glow := 0.0:
	set(v):
		glow = v
		queue_redraw()
var _dragging := false
var _tween: Tween


static func button(label_text: String, size_px: int = 30, track: int = 6) -> MenuRow:
	var r := MenuRow.new()
	r.text = label_text
	r.px = size_px
	r.tracking = track
	return r


static func slider(label_text: String, start: float) -> MenuRow:
	var r := MenuRow.new()
	r.kind = Kind.SLIDER
	r.text = label_text
	r.px = 24
	r.tracking = 4
	r.value = start
	return r


static func choice(label_text: String, options: PackedStringArray, start: int) -> MenuRow:
	var r := MenuRow.new()
	r.kind = Kind.CHOICE
	r.text = label_text
	r.px = 24
	r.tracking = 4
	r.choices = options
	r.index = start
	return r


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	custom_minimum_size.y = roundf(px * 1.75)
	mouse_entered.connect(func() -> void:
		if enabled:
			grab_focus())
	focus_entered.connect(_glow_to.bind(1.0))
	focus_exited.connect(_glow_to.bind(0.0))
	if has_focus():
		glow = 1.0


func set_enabled(on: bool) -> void:
	enabled = on
	focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW
	queue_redraw()


func _glow_to(target: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "glow", target, 0.16)


func set_value(v: float) -> void:
	value = clampf(v, 0.0, 1.0)
	queue_redraw()
	changed.emit()


func cycle(step: int) -> void:
	if choices.is_empty():
		return
	index = posmod(index + step, choices.size())
	queue_redraw()
	changed.emit()


func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed("ui_accept"):
		_activate()
		accept_event()
	elif kind == Kind.SLIDER and event.is_action_pressed("ui_left", true):
		set_value(snappedf(value - SLIDER_STEP, SLIDER_STEP))
		accept_event()
	elif kind == Kind.SLIDER and event.is_action_pressed("ui_right", true):
		set_value(snappedf(value + SLIDER_STEP, SLIDER_STEP))
		accept_event()
	elif kind == Kind.CHOICE and event.is_action_pressed("ui_left"):
		cycle(-1)
		accept_event()
	elif kind == Kind.CHOICE and event.is_action_pressed("ui_right"):
		cycle(1)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if kind == Kind.SLIDER:
				_dragging = true
				_set_from_x(event.position.x)
			else:
				_activate()
		else:
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x(event.position.x)


func _activate() -> void:
	match kind:
		Kind.BUTTON:
			activated.emit()
		Kind.CHOICE:
			cycle(1)
		Kind.SLIDER:
			pass


func _track() -> Rect2:
	var left := size.x * 0.5
	return Rect2(left, size.y * 0.5, size.x - left - 84.0, 2.0)


func _set_from_x(x: float) -> void:
	var t := _track()
	set_value(snappedf((x - t.position.x) / t.size.x, SLIDER_STEP))


func _draw() -> void:
	var f := MenuStyle.font(weight, tracking)
	var base := MenuStyle.FAINT if not enabled else MenuStyle.DIM.lerp(MenuStyle.BONE, glow)
	var y := (size.y + f.get_ascent(px) - f.get_descent(px)) * 0.5
	var x := 30.0 + glow * 6.0
	if glow > 0.01:
		draw_rect(Rect2(4.0, size.y * 0.5 - px * 0.5, 2.0, px), Color(MenuStyle.BLOOD, glow))
	draw_string(f, Vector2(x, y), text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, base)
	if note != "":
		var w := f.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
		var nf := MenuStyle.font(500, 3)
		draw_string(nf, Vector2(x + w + 22.0, y - 1.0), note.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(px * 0.55), MenuStyle.DIM)
	match kind:
		Kind.SLIDER:
			var t := _track()
			draw_rect(t, Color(MenuStyle.FAINT, 0.9))
			draw_rect(Rect2(t.position, Vector2(t.size.x * value, t.size.y)), MenuStyle.BLOOD.lerp(Color(0.9, 0.3, 0.25), glow * 0.5))
			var kx := t.position.x + t.size.x * value
			draw_circle(Vector2(kx, t.position.y + 1.0), 4.0 + glow * 2.0, MenuStyle.BONE.lerp(MenuStyle.DIM, 1.0 - glow))
			var pf := MenuStyle.font(500, 2)
			draw_string(pf, Vector2(size.x - 24.0 - 52.0, y), "%d" % roundi(value * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, 52.0, int(px * 0.85), base)
		Kind.CHOICE:
			var cf := MenuStyle.font(600, 4)
			var word := choices[index].to_upper() if not choices.is_empty() else ""
			draw_string(cf, Vector2(0, y), word, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 24.0, px, MenuStyle.BONE if glow > 0.5 else MenuStyle.DIM)

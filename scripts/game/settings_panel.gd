class_name SettingsPanel
extends Control
## Settings, as a left-hand column used by the title and the pause menu: volumes for each bus,
## graphics, fullscreen, subtitles, and a page listing the controls read from the game's own
## input bindings. Every change is applied and saved at once (Settings). Back, Esc or the
## gamepad's B closes it; the host listens for `closed`.

signal closed

const WIDTH := 560.0

const ACTION_NAMES := [
	["accelerate", "Throttle"], ["brake", "Brake and reverse"], ["steer_left", "Steer left"],
	["steer_right", "Steer right"], ["handbrake", "Handbrake"], ["boost", "Boost"], ["restart", "Restart"],
	["pause", "Pause"], ["fullscreen", "Fullscreen"], ["quality", "Graphics high or low"], ["mute", "Mute"],
]
const PAD_BUTTONS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_SHOULDER: "Left bumper", JOY_BUTTON_RIGHT_SHOULDER: "Right bumper",
}
const PAD_AXES := {
	JOY_AXIS_TRIGGER_LEFT: "Left trigger", JOY_AXIS_TRIGGER_RIGHT: "Right trigger",
}

var column := VBoxContainer.new()
var first_focus: Control
var on_controls := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.position = Vector2(MenuStyle.MARGIN_X - 30.0, 96.0)
	column.custom_minimum_size.x = WIDTH
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	_build_main()


func _clear() -> void:
	for c in column.get_children():
		column.remove_child(c)
		c.queue_free()


func _heading(text: String) -> void:
	var l := MenuStyle.label(text, 54, MenuStyle.BONE, 300, 10)
	var holder := Control.new()
	holder.custom_minimum_size.y = 70
	holder.add_child(l)
	l.position = Vector2(30, 0)
	column.add_child(holder)
	var rule_holder := Control.new()
	rule_holder.custom_minimum_size.y = 26
	var r := MenuStyle.rule(72)
	r.position = Vector2(30, 8)
	rule_holder.add_child(r)
	column.add_child(rule_holder)


func _section(text: String) -> void:
	var holder := Control.new()
	holder.custom_minimum_size.y = 34
	var l := MenuStyle.label(text, 16, MenuStyle.DIM, 600, 6)
	l.position = Vector2(30, 14)
	holder.add_child(l)
	column.add_child(holder)


func _build_main() -> void:
	on_controls = false
	first_focus = null
	_clear()
	_heading("SETTINGS")
	_section("SOUND")
	for k in Settings.VOLUME_ORDER:
		var row := MenuRow.slider(String(k).capitalize(), Settings.volumes[k])
		row.changed.connect(func() -> void: Settings.set_volume(k, row.value))
		column.add_child(row)
		if first_focus == null:
			first_focus = row
	_section("PICTURE")
	var gfx := MenuRow.choice("Graphics", PackedStringArray(["High", "Low"]), 0 if Settings.high else 1)
	gfx.changed.connect(func() -> void: Settings.set_graphics(gfx.index == 0))
	column.add_child(gfx)
	var fs := MenuRow.choice("Fullscreen", PackedStringArray(["Off", "On"]), 1 if Settings.fullscreen else 0)
	fs.changed.connect(func() -> void: Settings.set_fullscreen(fs.index == 1))
	column.add_child(fs)
	var sub := MenuRow.choice("Subtitles", PackedStringArray(["Off", "On"]), 1 if Settings.subtitles else 0)
	sub.changed.connect(func() -> void: Settings.set_subtitles(sub.index == 1))
	column.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 14
	column.add_child(spacer)
	var ctl := MenuRow.button("Controls", 26, 5)
	ctl.activated.connect(_build_controls)
	column.add_child(ctl)
	var back := MenuRow.button("Back", 26, 5)
	back.activated.connect(close)
	column.add_child(back)
	first_focus.grab_focus.call_deferred()


func _build_controls() -> void:
	on_controls = true
	_clear()
	_heading("CONTROLS")
	var head := GridContainer.new()
	head.columns = 3
	head.add_theme_constant_override("h_separation", 0)
	head.add_theme_constant_override("v_separation", 3)
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 30)
	indent.add_child(head)
	column.add_child(indent)
	for h in ["", "KEYBOARD", "GAMEPAD"]:
		var l := MenuStyle.label(h, 15, MenuStyle.DIM, 600, 6)
		l.custom_minimum_size = Vector2([262.0, 170.0, 160.0][head.get_child_count()], 30)
		head.add_child(l)
	for pair in ACTION_NAMES:
		var name_l := MenuStyle.label(String(pair[1]), 22, MenuStyle.BONE, 500, 2)
		name_l.custom_minimum_size = Vector2(262, 31)
		var kb := MenuStyle.label(_describe(pair[0], false), 22, MenuStyle.DIM, 500, 2)
		var pad := MenuStyle.label(_describe(pair[0], true), 22, MenuStyle.DIM, 500, 2)
		for l in [name_l, kb, pad]:
			head.add_child(l)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	column.add_child(spacer)
	var back := MenuRow.button("Back", 26, 5)
	back.activated.connect(_build_main)
	column.add_child(back)
	back.grab_focus.call_deferred()


## An action's keys, or its gamepad inputs, as words, from InputMap itself.
func _describe(action: String, gamepad: bool) -> String:
	var out := PackedStringArray()
	if not InputMap.has_action(action):
		return ""
	for e in InputMap.action_get_events(action):
		if not gamepad and e is InputEventKey:
			out.append(OS.get_keycode_string(e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode))
		elif gamepad and e is InputEventJoypadButton:
			out.append(PAD_BUTTONS.get(e.button_index, "Button %d" % e.button_index))
		elif gamepad and e is InputEventJoypadMotion:
			if e.axis == JOY_AXIS_LEFT_X:
				out.append("Left stick")
			elif PAD_AXES.has(e.axis):
				out.append(PAD_AXES[e.axis])
	return " / ".join(out) if not out.is_empty() else "-"


func close() -> void:
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if on_controls:
			_build_main()
		else:
			close()

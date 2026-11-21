class_name MapScreen
extends CanvasLayer
## The full map: the whole quarter north-up with the places named, the car and the objective. It stops
## the world while it is up (and gives the pause back if it was already paused). Tab, Esc, P, the
## gamepad's Back or B close it. While it is open it takes the menu keys too (up, down, accept, Tab as
## focus-next), so nothing underneath, such as the pause menu's rows, can act on them.

signal closed

var shade := Control.new()
var view := MapView.new()
var is_open := false
var _was_paused := false
var _opened_frame := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = MenuStyle.LAYER_MAP
	visible = false
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(dim)
	var head := MenuStyle.heading("MAP", 54, 12)
	head.position = Vector2(MenuStyle.MARGIN_X - 30.0, 70.0)
	shade.add_child(head)
	var legend := VBoxContainer.new()
	legend.position = Vector2(MenuStyle.MARGIN_X, 250.0)
	legend.add_theme_constant_override("separation", 14)
	shade.add_child(legend)
	for item in [["YOU", MenuStyle.BONE], ["OBJECTIVE", MapView.AMBER], ["NEXT CALL", MapView.TEAL]]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		var dot := ColorRect.new()
		dot.color = item[1]
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(dot)
		line.add_child(MenuStyle.label(item[0], 15, MenuStyle.DIM, 600, 7))
		legend.add_child(line)
	var hint := MenuStyle.label("TAB  CLOSE", 14, MenuStyle.FAINT, 600, 7)
	hint.position = Vector2(MenuStyle.MARGIN_X, 810.0)
	shade.add_child(hint)
	view.mode = MapView.Mode.FULL
	view.clip_contents = true  # a city that is longer than its frame (the harbour's highway) draws only the frame
	view.position = Vector2(470.0, 70.0)
	view.size = Vector2(1060.0, 760.0)
	shade.add_child(view)


func open(pos: Vector2, angle: float, blips: Array, route: PackedVector2Array = PackedVector2Array()) -> void:
	if is_open:
		return
	is_open = true
	_opened_frame = Engine.get_process_frames()
	_was_paused = get_tree().paused
	get_tree().paused = true
	view.set_state(pos, angle, blips, 0.0, route)
	get_viewport().gui_release_focus()  # the pause menu's row that opened this must not hold the keys
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = _was_paused
	if not _was_paused:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	closed.emit()


const SWALLOWED := ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_focus_next", "ui_focus_prev", "ui_select"]


## `_input` runs before the GUI sees an event, so a focused control underneath never gets it.
func _input(event: InputEvent) -> void:
	if not is_open or Engine.get_process_frames() == _opened_frame:
		return
	if event.is_action_pressed("map") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
		return
	for a in SWALLOWED:
		if event.is_action(a):
			get_viewport().set_input_as_handled()
			return

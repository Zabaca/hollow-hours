class_name CreditsRoll
extends CanvasLayer
## The short credits roll at the end of the story: quiet lines rising on the dark left side of the
## picture, the title first, then who made what (the same lines as the Credits screen), then one last
## line. Any key, click or button skips it. `finished` fires when it has gone off the top or been skipped.

signal finished

const SECONDS := 17.0
const LAST_LINE := "Red got out."

var scroller := Control.new()
var column := VBoxContainer.new()
var playing := false
var elapsed := 0.0
var _travel := 0.0


func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.clip_contents = true
	add_child(root)
	root.add_child(MenuStyle.left_shade())
	root.add_child(scroller)
	column.add_theme_constant_override("separation", 0)
	column.custom_minimum_size.x = 700.0
	scroller.add_child(column)
	_fill()


func _fill() -> void:
	var title := MenuStyle.label("HOLLOW HOURS", 76, MenuStyle.BONE, 300, 16)
	column.add_child(title)
	var r := MenuStyle.rule(96)
	var holder := Control.new()
	holder.custom_minimum_size.y = 90
	r.position = Vector2(6, 22)
	holder.add_child(r)
	column.add_child(holder)
	for pair in CreditsPanel.CREDITS:
		column.add_child(MenuStyle.label(String(pair[0]).to_upper(), 15, MenuStyle.DIM, 600, 7))
		var what := MenuStyle.label(String(pair[1]), 26, MenuStyle.BONE, 400, 2)
		what.custom_minimum_size.y = 56
		column.add_child(what)
	var cast := MenuStyle.label("THE VOICES ON THE RADIO", 15, MenuStyle.DIM, 600, 7)
	column.add_child(cast)
	for who in StoryData.SPEAKERS.values():
		var l := MenuStyle.label(String(who["name"]), 26, who["color"], 400, 2)
		l.custom_minimum_size.y = 40
		column.add_child(l)
	var gap := Control.new()
	gap.custom_minimum_size.y = 160
	column.add_child(gap)
	column.add_child(MenuStyle.label(LAST_LINE, 34, MenuStyle.BONE, 300, 5))


func start() -> void:
	column.reset_size()
	var screen := get_viewport().get_visible_rect().size
	_travel = screen.y + column.size.y + 60.0
	scroller.position = Vector2(MenuStyle.MARGIN_X, screen.y)
	elapsed = 0.0
	playing = true
	visible = true


func skip() -> void:
	if playing:
		_end()


func _end() -> void:
	playing = false
	visible = false
	finished.emit()


func _process(delta: float) -> void:
	if not playing:
		return
	elapsed += delta
	var u := clampf(elapsed / SECONDS, 0.0, 1.0)
	var screen := get_viewport().get_visible_rect().size
	# It stops a little short of leaving, so the last line is left on screen for the fade.
	scroller.position.y = screen.y - u * (_travel - screen.y * 0.45)
	if elapsed >= SECONDS:
		_end()


func _input(event: InputEvent) -> void:
	if playing and elapsed > 1.0 and (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton) and event.is_pressed():
		get_viewport().set_input_as_handled()
		skip()

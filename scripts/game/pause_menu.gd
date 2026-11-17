class_name PauseMenu
extends CanvasLayer
## The pause menu: Resume, Settings, Quit to menu (in the story also Map, and Restart mission while a
## mission is on). Opening it stops the world (the scene tree is
## paused), drops the music and shows the mouse; the menu itself keeps running. Esc, P and the
## gamepad's Start open it (main.gd) and close it (here).

signal resumed
signal quit_to_menu
signal map_requested
signal restart_requested

var audio: AudioMix
var column := VBoxContainer.new()
var shade := Control.new()
var dim := ColorRect.new()
var rows: Array[MenuRow] = []
var settings: SettingsPanel
var is_open := false
var opened_frame := -1
var story := false
var in_mission := false
var settings_row: MenuRow
var map_row: MenuRow
var map_screen: MapScreen  # the full map, which sits above this menu while it is open


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = MenuStyle.LAYER_PAUSE
	visible = false
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	dim.color = Color(0.0, 0.0, 0.0, 0.42)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(dim)
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.0, 0.0, 0.92))
	g.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.0, 0.0)
	gt.fill_to = Vector2(1.0, 0.0)
	var left := TextureRect.new()
	left.texture = gt
	left.stretch_mode = TextureRect.STRETCH_SCALE
	left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.anchor_right = 0.55
	left.offset_right = 0.0
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(left)
	_build_main()


func _build_main() -> void:
	if column.get_parent() != null:
		column.get_parent().remove_child(column)
	for c in column.get_children():
		column.remove_child(c)
		c.queue_free()
	rows.clear()
	column.position = Vector2(MenuStyle.MARGIN_X - 30.0, 96.0)
	column.custom_minimum_size.x = 520.0
	column.add_theme_constant_override("separation", 2)
	shade.add_child(column)
	var title := MenuStyle.label("PAUSED", 64, MenuStyle.BONE, 300, 14)
	column.add_child(_pad(title, 70.0))
	var r := MenuStyle.rule(72)
	r.position = Vector2(30, 6)
	var rh := Control.new()
	rh.custom_minimum_size.y = 34
	rh.add_child(r)
	column.add_child(rh)
	var resume := _row("Resume", resume_game)
	if story:
		map_row = _row("Map", func() -> void: map_requested.emit())
	settings_row = _row("Settings", _open_settings)
	if story and in_mission:
		_row("Restart mission", func() -> void: restart_requested.emit())
	_row("Quit to menu", func() -> void: quit_to_menu.emit())
	if is_open:
		resume.grab_focus.call_deferred()


func _pad(l: Label, height: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size.y = height
	l.position = Vector2(30, 0)
	holder.add_child(l)
	return holder


func _row(text: String, action: Callable) -> MenuRow:
	var row := MenuRow.button(text, 32, 6)
	row.activated.connect(action)
	column.add_child(row)
	rows.append(row)
	return row


func open(mix: AudioMix = null, in_story: bool = false, mission_on: bool = false) -> void:
	if is_open:
		return
	audio = mix
	story = in_story
	in_mission = mission_on
	is_open = true
	opened_frame = Engine.get_process_frames()
	Engine.time_scale = 1.0
	_build_main()
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if audio != null:
		audio.enter_pause()
	if Session.screen == "pause-settings":
		_open_settings.call_deferred()
	if Session.screen.begins_with("pause") and Session.shot_path != "":
		_shot_later()


func _shot_later() -> void:
	await get_tree().create_timer(Session.shot_at, true, false, true).timeout
	Session.save_shot_and_quit(get_tree(), Session.shot_path)


func resume_game() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	resumed.emit()


func _open_settings() -> void:
	if settings != null:
		return
	column.visible = false
	_dim_to(0.72)
	settings = SettingsPanel.new()
	settings.closed.connect(_close_settings)
	shade.add_child(settings)


## The picture goes darker behind a panel full of small text.
func _dim_to(alpha: float) -> void:
	create_tween().tween_property(dim, "color:a", alpha, 0.3)


func _close_settings() -> void:
	settings.queue_free()
	settings = null
	_dim_to(0.42)
	column.visible = true
	settings_row.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open or settings != null or Engine.get_process_frames() == opened_frame or (map_screen != null and map_screen.is_open):
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		resume_game()


## Back from the full map (opened from the Map row): the focus returns to that row.
func focus_map_row() -> void:
	if is_open and map_row != null:
		map_row.grab_focus.call_deferred()

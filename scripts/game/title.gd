extends Control
## The first scene: the title over its key art, with rain, a slow push-in, an occasional flash of
## lightning with thunder, and the tension music underneath. New Game, Continue (greyed until
## there is a save; it says which mission is next), Survive the Night (once the story has been finished),
## Settings, Credits, Quit. Keyboard, gamepad and mouse all work. New Game over a save asks first.
##
## A game flag on the command line (see Session) skips all of this and goes straight into the round.

## The one place the key art is loaded from; slice 6 drops the painted image in here.
const ART_PATH := "res://assets/ui/title_art.png"
const FX_SHADER := preload("res://shaders/title_fx.gdshader")
const FADE_IN := 1.6

var art := TextureRect.new()
var weather := ColorRect.new()
var weather_mat := ShaderMaterial.new()
var column := VBoxContainer.new()
var title_block := Control.new()
var menu_rows: Array[MenuRow] = []
var panel: Control
var focus_after_panel: MenuRow
var save := {}  # the save on disk when the menu was built, {} for none

var flash_amount := 0.0:
	set(v):
		flash_amount = v
		art.modulate = Color(1.0 + v * 1.1, 1.0 + v * 1.25, 1.0 + v * 1.6)
		weather_mat.set_shader_parameter("flash", clampf(v, 0.0, 1.0))
var elapsed := 0.0
var fade := 1.0
var skipped := false
var strike_in := 30.0
var screech_in := 40.0
var rng := RandomNumberGenerator.new()
var shot_taken := false
var music: AudioStreamPlayer
var rain_loop: AudioStreamPlayer
var leaving := false


func _ready() -> void:
	Settings.boot()
	if Session.goes_straight_to_game():
		_enter_game.call_deferred(false)
		return
	Session.parse_args()
	if Session.screen.begins_with("pause") or Session.screen in Session.STORY_SCREENS:
		_enter_game.call_deferred(false)
		return
	InputSetup.ensure()
	rng.randomize()
	get_window().title = "Hollow Hours"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_build_background()
	_build_menu()
	_build_audio()
	fade = 1.0
	if Session.screen != "":
		# A screenshot run does not wait for the opening or leave the lightning to chance.
		elapsed = FADE_IN
		fade = 0.0
		strike_in = 9999.0
		screech_in = 9999.0
		_show_screen(Session.screen)
		if Session.shot_path != "":
			await get_tree().create_timer(Session.shot_at).timeout
			Session.save_shot_and_quit(get_tree(), Session.shot_path)
		return
	get_tree().create_timer(0.35).timeout.connect(_strike.bind(0.12))


func _build_background() -> void:
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(ART_PATH):
		art.texture = load(ART_PATH)
	add_child(art)
	weather.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	weather.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weather_mat.shader = FX_SHADER
	weather.material = weather_mat
	weather_mat.set_shader_parameter("left_width", 0.46)
	weather_mat.set_shader_parameter("left_dark", 0.8)
	add_child(weather)
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	art.pivot_offset = size * 0.5
	weather_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))


func _build_menu() -> void:
	# The title, drawn by the game and never part of the picture: two lines, light and wide.
	title_block.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_block)
	var hollow := MenuStyle.label("HOLLOW", 132, MenuStyle.BONE, 300, 22)
	hollow.position = Vector2(MenuStyle.MARGIN_X, 70)
	var hours := MenuStyle.label("HOURS", 132, MenuStyle.BONE, 300, 22)
	hours.position = Vector2(MenuStyle.MARGIN_X, 188)
	var rule := MenuStyle.rule(96)
	rule.position = Vector2(MenuStyle.MARGIN_X + 4, 352)
	title_block.add_child(hollow)
	title_block.add_child(hours)
	title_block.add_child(rule)

	column.position = Vector2(MenuStyle.MARGIN_X - 30.0, 396.0)
	column.custom_minimum_size.x = 440.0
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	save = SaveStore.load_save(Session.save_path)
	var new_game := _item("New Game", _new_game)
	var cont := _item("Continue", _continue)
	# A finished story has nothing to continue into: Continue is greyed and says so, and Survive the Night
	# (below) is the way to play on.
	var finished := not save.is_empty() and str(save["next"]) == "" and StoryData.closes_story(StoryData.MISSIONS.size() - 1)
	cont.set_enabled(not save.is_empty() and not finished)
	if finished:
		cont.note = "The end"
	elif not save.is_empty() and str(save["next"]) == "":
		cont.note = "Free roam"  # the story so far is done and the rest is still to be built
	elif not save.is_empty():
		cont.note = "Mission %d" % (StoryData.mission_index(str(save["next"])) + 1)
	if (not save.is_empty() and bool(save["ending_seen"])) or SaveStore.survive_unlocked(Session.save_path):
		_item("Survive the Night", _survive)
	_item("Settings", _open_settings)
	_item("Credits", _open_credits)
	_item("Quit", func() -> void: get_tree().quit())
	new_game.grab_focus.call_deferred()


func _item(text: String, action: Callable) -> MenuRow:
	var row := MenuRow.button(text, 32, 8)
	row.activated.connect(action)
	column.add_child(row)
	menu_rows.append(row)
	return row


func _build_audio() -> void:
	music = _player("music_tension", "Music", -10.0, true)
	rain_loop = _player("rain_loop", "Ambience", -13.0, true)
	music.play()
	rain_loop.play()


func _player(file: String, bus: String, db: float, loop: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var path := AudioMix.DIR + file + ".wav"
	if not ResourceLoader.exists(path):
		path = AudioMix.DIR + file + ".mp3"
	p.stream = GM.loop_wav(path) if loop else load(path)
	p.bus = bus
	p.volume_db = db
	add_child(p)
	return p


func _one_shot(file: String, bus: String, db: float, pitch: float = 1.0) -> void:
	var p := _player(file, bus, db, false)
	p.pitch_scale = pitch
	p.finished.connect(p.queue_free)
	p.play()


# ----------------------------------------------------------------------------- weather

func _strike(thunder_after: float = -1.0) -> void:
	var tw := create_tween()
	tw.tween_property(self, "flash_amount", 0.85, 0.03)
	tw.tween_property(self, "flash_amount", 0.15, 0.07)
	tw.tween_property(self, "flash_amount", 1.0, 0.04)
	tw.tween_property(self, "flash_amount", 0.0, 0.7).set_trans(Tween.TRANS_SINE)
	var delay := thunder_after if thunder_after >= 0.0 else rng.randf_range(0.6, 3.0)
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		_one_shot("thunder", "Ambience", -5.0 - delay * 1.5))


func _screech() -> void:
	var files := ["creature_screech_1", "creature_screech_2", "creature_screech_3"]
	_one_shot(files[rng.randi() % files.size()], "SFX", -17.0, rng.randf_range(0.8, 0.95))


func _process(delta: float) -> void:
	elapsed += delta
	if not skipped and not leaving:
		fade = clampf(1.0 - elapsed / FADE_IN, 0.0, 1.0)
	weather_mat.set_shader_parameter("time_s", elapsed)
	weather_mat.set_shader_parameter("fade", fade)
	# The slow push-in: a long breath in and out, with a slight drift, so it never reads as a loop.
	var t := elapsed / 60.0 * TAU
	var s := 1.045 + 0.035 * sin(t - PI * 0.5)
	art.scale = Vector2(s, s)
	art.position = Vector2(-8.0 * sin(t * 0.5), -5.0 * sin(t * 0.37 + 1.0))
	var shown := clampf((elapsed - FADE_IN * 0.55) / 1.8, 0.0, 1.0)
	title_block.modulate.a = shown
	column.modulate.a = clampf((elapsed - FADE_IN * 0.9) / 1.4, 0.0, 1.0)
	strike_in -= delta
	if strike_in <= 0.0:
		strike_in = rng.randf_range(20.0, 40.0)
		_strike()
	screech_in -= delta
	if screech_in <= 0.0:
		screech_in = rng.randf_range(35.0, 75.0)
		_screech()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		Settings.set_fullscreen(DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()
	elif not skipped and elapsed < FADE_IN and (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton) and event.is_pressed():
		skipped = true
		fade = 0.0
		elapsed = maxf(elapsed, FADE_IN)
		get_viewport().set_input_as_handled()


# ----------------------------------------------------------------------------- screens

func _show_screen(name: String) -> void:
	match name:
		"settings", "controls":
			_open_settings()
			if name == "controls":
				(panel as SettingsPanel)._build_controls()
		"credits":
			_open_credits()
		"confirm":
			_open_panel(ConfirmPanel.new(), 0.62)


func _open_panel(p: Control, dark_width: float = 0.62) -> void:
	if panel != null:
		return
	var owner := get_viewport().gui_get_focus_owner()
	focus_after_panel = owner if owner is MenuRow else null
	column.visible = false
	title_block.visible = false
	_darken(dark_width, 0.93)
	panel = p
	add_child(panel)
	panel.closed.connect(_close_panel)


## Widen and deepen the dark left side while a panel is open, so its text never sits on the picture.
func _darken(width: float, amount: float) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float) -> void: weather_mat.set_shader_parameter("left_width", v), float(weather_mat.get_shader_parameter("left_width")), width, 0.35)
	tw.tween_method(func(v: float) -> void: weather_mat.set_shader_parameter("left_dark", v), float(weather_mat.get_shader_parameter("left_dark")), amount, 0.35)


func _open_settings() -> void:
	_open_panel(SettingsPanel.new())


func _open_credits() -> void:
	_open_panel(CreditsPanel.new(), 0.76)


func _close_panel() -> void:
	panel.queue_free()
	panel = null
	column.visible = true
	title_block.visible = true
	_darken(0.46, 0.8)
	(focus_after_panel if focus_after_panel != null else menu_rows[0]).grab_focus.call_deferred()


func _new_game() -> void:
	if save.is_empty():
		_start_story({})
		return
	var ask := ConfirmPanel.new()
	ask.confirmed.connect(func() -> void:
		DirAccess.remove_absolute(Session.save_path)
		_start_story({}))
	_open_panel(ask, 0.62)


func _continue() -> void:
	if not save.is_empty():
		_start_story(save)


func _start_story(from_save: Dictionary) -> void:
	Session.mode = "story"
	Session.continue_save = from_save
	Session.mission_flag = 0
	_enter_game(true)


## Today's round, with its five-minute clock: the old game.
func _survive() -> void:
	Session.mode = "survival"
	Session.continue_save = {}
	Session.mission_flag = 0
	_enter_game(true)


## Into the round. From the menu the screen fades to black and the music goes with it first.
func _enter_game(with_fade: bool) -> void:
	if leaving:
		return
	leaving = true
	if with_fade:
		for row in menu_rows:
			row.focus_mode = Control.FOCUS_NONE
		var tw := create_tween().set_parallel(true)
		tw.tween_method(func(v: float) -> void:
			fade = v
			weather_mat.set_shader_parameter("fade", v), 0.0, 1.0, 0.7)
		tw.tween_property(music, "volume_db", -60.0, 0.7)
		tw.tween_property(rain_loop, "volume_db", -60.0, 0.7)
		await tw.finished
	get_tree().change_scene_to_file(Session.MAIN_SCENE)

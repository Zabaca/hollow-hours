extends Node3D
## Hollow Hours: wires the simulation (GameSim, 120 Hz) to everything you see and hear.
##
## Command line (after `--`): `--demo` lets an autopilot drive; `--shot=/path.png` saves a frame
## and quits after `--shot-at=SECONDS` (default 6) of real time; `--low` starts on the low
## graphics preset; `--no-hud` hides the HUD (for key-art frames); `--story` and `--mission=N` start the
## story (see Session). Example (with a window, not --headless):
##   godot --path . -- --demo --shot=/tmp/hollow.png --shot-at=8

var game: GameSim
var city: City
var gate_view: GateView
var atmos: Atmosphere
var car_view: CarView
var cam: ChaseCamera
var fx: FX
var audio: AudioMix
var hud: Hud
var pause_menu: PauseMenu
var presenter: StoryPresenter  # story mode only
var story_dawn := 0.0
var views := {}  # creature id -> GauntView
var prev_pos := Vector2.ZERO
var prev_angle := 0.0
var demo := false
var no_hud := false
var shot_path := ""
var shot_at := 6.0
var shot_game := -1.0
var shot_speed := -1.0
var audio_log := false
var cam_log := false
var crash_us := 0
var tick_started_us := 0
var tick_no := 0
var debug_cam_side := 0.0  # --cam-side=H: a low camera H metres up, 7 m to the car's left, for looking at how it sits on the road
var debug_gate := ""  # --gate=open|opening: the west gate open from the start, or opening 1.5 s in
var debug_start := PackedFloat64Array()
var debug_drive := Vector2(INF, 0.0)  # --drive=throttle,turn: constant controls instead of the autopilot
var shot_taken := false
var started_ms := 0
var threat := 0.0
var autopilot := Autopilot.new()
var ended := false


func _ready() -> void:
	InputSetup.ensure()
	Settings.boot()
	Session.parse_args()
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--demo":
			demo = true
		elif a == "--low":
			Settings.apply_preset(false)  # for this run only: Settings.saved_high keeps the player's choice
		elif a.begins_with("--shot="):
			shot_path = a.trim_prefix("--shot=")
		elif a == "--no-hud":
			no_hud = true
		elif a == "--cam-log":
			cam_log = true
		elif a == "--audio-log":
			audio_log = true
		elif a.begins_with("--cam-side="):
			debug_cam_side = float(a.trim_prefix("--cam-side="))
		elif a.begins_with("--gate="):
			debug_gate = a.trim_prefix("--gate=")
		elif a.begins_with("--start="):
			# --start=x,y,angle puts the car there (map metres, radians)
			debug_start = a.trim_prefix("--start=").split_floats(",")
		elif a.begins_with("--drive="):
			var dv := a.trim_prefix("--drive=").split_floats(",")
			debug_drive = Vector2(dv[0], dv[1])
		elif a.begins_with("--shot-speed="):
			shot_speed = float(a.trim_prefix("--shot-speed="))
		elif a.begins_with("--shot-game="):
			shot_game = float(a.trim_prefix("--shot-game="))
		elif a.begins_with("--shot-at="):
			shot_at = float(a.trim_prefix("--shot-at="))
	if Session.screen != "":
		shot_path = ""  # --screen=pause takes its own shot, from the pause menu
	get_window().title = "Hollow Hours"
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	game = _make_game()
	if debug_start.size() == 3:
		game.car.body.position = Vector2(debug_start[0], debug_start[1])
		game.car.body.angle = debug_start[2]
	city = City.new()
	add_child(city)
	city.build(CityLayout.DATA)
	gate_view = GateView.new()
	add_child(gate_view)
	gate_view.setup(game.world)
	atmos = Atmosphere.new()
	add_child(atmos)
	car_view = CarView.new()
	add_child(car_view)
	car_view.build()
	cam = ChaseCamera.new()
	cam.world = game.world
	cam.near = 0.1
	cam.far = 600.0
	add_child(cam)
	cam.current = true
	atmos.follow = cam
	fx = FX.new()
	add_child(fx)
	audio = AudioMix.new()
	add_child(audio)
	hud = Hud.new()
	add_child(hud)
	hud.visible = not no_hud
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.resumed.connect(_apply_graphics)
	pause_menu.quit_to_menu.connect(_quit_to_menu)
	if game.story_mode:
		hud.use_story_layout()
		presenter = StoryPresenter.new()
		add_child(presenter)
		presenter.setup(game, not no_hud)
		presenter.save_path = Session.save_path
		presenter.quit_to_menu.connect(_quit_to_menu)
		presenter.world_reset.connect(_reset_views)
		presenter.ending_started.connect(func() -> void: hud.fade_out(2.2))
		# The sky starts where the story is, not at night.
		story_dawn = presenter.dawn_target()
		pause_menu.map_screen = presenter.map_screen
		pause_menu.map_requested.connect(presenter.open_map)
		presenter.map_screen.closed.connect(pause_menu.focus_map_row)
		pause_menu.restart_requested.connect(func() -> void:
			pause_menu.resume_game()
			presenter.restart_mission())
	atmos.lightning.connect(_on_lightning)
	_apply_viewport()
	prev_pos = game.car.body.position
	prev_angle = game.car.body.angle
	fx.fade_to(0.0)
	if debug_gate == "open":
		game.world.gate["open"] = true
		gate_view.set_open(true, true)
	elif debug_gate == "opening":
		get_tree().create_timer(1.5).timeout.connect(func() -> void: gate_view.set_open(true))
	if presenter != null:
		atmos.set_dawn(story_dawn)
		fx.dawn = story_dawn * 0.6
	started_ms = Time.get_ticks_msec()
	if Session.screen.begins_with("pause"):
		# --screen=pause: a frame of the pause menu over the game, for screenshots
		get_tree().create_timer(8.0).timeout.connect(_open_pause)
	elif presenter != null and Session.screen in Session.STORY_SCREENS:
		get_tree().create_timer(3.0).timeout.connect(_story_screen)


## Survival is today's round; story mode is a new story, a Continue (Session.continue_save) or a mission
## started directly (--mission=N).
func _make_game() -> GameSim:
	if Session.mode != "story":
		return GameSim.new(CityLayout.DATA)
	if Session.continue_flag:
		Session.continue_save = SaveStore.load_save(Session.save_path)
	var seed_in := Session.seed_flag if Session.seed_flag >= 0 else randi() % 100000
	var g := GameSim.new(CityLayout.DATA, "bruiser", seed_in, true)
	if Session.mission_flag > 1:
		g.start_story_at(Session.mission_flag - 1)
	elif not Session.continue_save.is_empty():
		g.continue_story(Session.continue_save)
	return g


## The leaves rolling, heard from the gate.
func _gate_leaves_sound() -> void:
	audio.play_at("gate_leaves", gate_view.centre + Vector3(-2.0, 2.0, 0.0), 2.0, 1.0, 140.0)


## --screen=map|fail|complete|ending: open that story screen over the mission, for a screenshot. The ending
## puts the car on the avenue with the gate open and drives it out, as reaching the gate would.
func _story_screen() -> void:
	match Session.screen:
		"map":
			presenter.open_map()
		"fail":
			game.damage(1000.0, "dev")
		"complete":
			presenter.on_event({"type": "mission_complete", "title": "BATTERIES", "id": "batteries", "mission": 0, "final": false})
		"ending":
			game.world.gate["open"] = true
			gate_view.set_open(true, true)
			game.place_car(Vector2(-62.0, 0.0), PI, GameSim.MAX_HULL)
			game.car.body.velocity = Vector2(-14.0, 0.0)
			presenter.radio.clear()  # the mission's opening call is still queued in a run that skips the mission
			game.escape()
			for id in StoryData.ENDING_LINES:
				presenter.on_event({"type": "line", "id": id, "speaker": StoryData.LINES[id]["speaker"], "priority": true})
			presenter.on_event({"type": "escaped"})
	if Session.shot_path != "":
		await get_tree().create_timer(Session.shot_at, true, false, true).timeout
		Session.save_shot_and_quit(get_tree(), Session.shot_path)


func _apply_graphics() -> void:
	atmos.apply_quality()
	_apply_viewport()


func _open_pause() -> void:
	pause_menu.open(audio, presenter != null, presenter != null and game.mission.active())


func _quit_to_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file(Session.TITLE_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if not demo and event.is_action_pressed("pause") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if presenter == null or not presenter.blocks_pause():
			_open_pause()
	elif presenter != null and event.is_action_pressed("map") and not event.is_echo():
		# Opens only: closing is the open map's own business (MapScreen._input), so the key that
		# closes it can never reach this and open it again.
		get_viewport().set_input_as_handled()
		if not presenter.blocks_pause() and not pause_menu.is_open:
			presenter.open_map()


func _apply_viewport() -> void:
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_2X if Settings.msaa else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.set("use_taa", Settings.high)


# ----------------------------------------------------------------------------- input

func _controls(delta: float) -> Dictionary:
	if debug_drive.x != INF:
		return {"throttle": debug_drive.x, "turn": debug_drive.y, "handbrake": false, "boost": false}
	if demo:
		return autopilot.controls(game, delta)
	return {
		"throttle": Input.get_axis("brake", "accelerate"),
		"turn": Input.get_axis("steer_right", "steer_left"),
		"handbrake": Input.is_action_pressed("handbrake"),
		"boost": Input.is_action_pressed("boost"),
	}


func _poll_actions() -> void:
	if demo:
		return
	# In the story a stray key must not throw a mission away: restarting is in the pause menu.
	if presenter == null and Input.is_action_just_pressed("restart"):
		_restart()
	if Input.is_action_just_pressed("fullscreen"):
		Settings.set_fullscreen(DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN)
	if Input.is_action_just_pressed("quality"):
		Settings.set_graphics(not Settings.high)
		_apply_graphics()
	if Input.is_action_just_pressed("mute"):
		audio.toggle_mute()


func _restart() -> void:
	game.reset()
	hud.clear_end()
	hud.show_intro()
	hud.intro_time = 3.0
	_reset_views()


## After the car has been put somewhere new (a restart, a retry, going back to a save): forget the old
## creatures and effects and start the camera over.
func _reset_views() -> void:
	Engine.time_scale = 1.0
	for id in views:
		views[id].queue_free()
	views.clear()
	gate_view.set_open(bool(game.world.gate["open"]), true)
	fx.desat = 0.0
	fx.dawn = 0.0
	fx.fade = 0.6
	fx.fade_to(0.0)
	atmos.set_dawn(0.0)
	cam.inited = false
	prev_pos = game.car.body.position
	prev_angle = game.car.body.angle
	ended = false
	autopilot = Autopilot.new()


# ----------------------------------------------------------------------------- the step

func _physics_process(delta: float) -> void:
	prev_pos = game.car.body.position
	prev_angle = game.car.body.angle
	tick_started_us = Time.get_ticks_usec()
	tick_no += 1
	game.step(delta, _controls(delta))
	for e in game.take_events():
		_on_event(e)
		if presenter != null:
			presenter.on_event(e)
	if presenter == null and not ended and game.phase != GameSim.Phase.PLAYING:
		ended = true
		hud.show_end(game.phase, game)


func _process(delta: float) -> void:
	_poll_actions()
	var car := game.car
	var alpha := Engine.get_physics_interpolation_fraction()
	var pos := prev_pos.lerp(car.body.position, alpha)
	var ang := lerp_angle(prev_angle, car.body.angle, alpha)
	car_view.sync(game, game.world, pos, ang, delta)
	var ending := presenter != null and presenter.ending in ["pullback", "roll", "fade", "done"]
	if ending:
		cam.update_pullback(pos, ang, car_view.ground, presenter.pullback_progress())
		gate_view.track(GM.to3(pos, 1.2))
	else:
		cam.update_camera(delta, pos, ang, car.body.velocity, car_view.ground, car.boosting)
		gate_view.track(Vector3.INF)
	if debug_cam_side > 0.0:
		var side_dir := Vector2.from_angle(ang + PI / 2.0)
		cam.look_at_from_position(GM.to3(pos + side_dir * 7.0, debug_cam_side), GM.to3(pos, 0.7), Vector3.UP)
	_sync_creatures(delta)
	if cam_log and crash_us != 0 and Time.get_ticks_usec() - crash_us < 1800000:
		print("CAMLOG t=%4d ms tick=%d dt=%.4f ts=%.2f speed=%.1f vel_deg=%4.0f car_deg=%4.0f cam_yaw_deg=%4.0f trauma=%.2f fov=%.1f" % [
			(Time.get_ticks_usec() - crash_us) / 1000, tick_no, delta, Engine.time_scale, car.speed(), rad_to_deg(car.body.velocity.angle()),
			rad_to_deg(car.body.angle), rad_to_deg(cam.yaw), cam.trauma, cam.fov])

	var latched := game.pack.latched().size()
	var near := game.pack.nearest_hunter(car)
	var threat_in := clampf(1.0 - near / 45.0, 0.0, 1.0) + float(latched) * 0.35
	threat = clampf(threat_in, 0.0, 1.0)
	audio.update_mix(game, latched, threat, true, delta)
	hud.update_hud(game, latched, delta)
	if presenter != null:
		presenter.update(delta, pos, ang)
	fx.vignette = 0.42 + threat * 0.3
	fx.chroma = maxf(fx.chroma, clampf((car.speed() - 22.0) / 40.0, 0.0, 0.25))
	# Dawn creeps in over the last stretch of the night; in the story the sky lightens a touch with each mission.
	var dawn := clampf((game.time - (GameSim.NIGHT_LENGTH - 45.0)) / 75.0, 0.0, 1.0)
	if presenter != null:
		# Slowly with each mission; first light, once the car is through the gate, comes up in seconds.
		story_dawn = move_toward(story_dawn, presenter.dawn_target(), delta * (0.12 if presenter.ending != "" else 0.04))
		dawn = story_dawn
		audio.hush = move_toward(audio.hush, presenter.hush(), delta * 0.25)
	if absf(dawn - atmos.dawn_amount) > 0.002:
		atmos.set_dawn(dawn)
		fx.dawn = dawn * 0.6

	if shot_path != "" and not shot_taken and ((shot_speed >= 0.0 and car.speed() >= shot_speed and game.time > 5.0) or (shot_game >= 0.0 and game.time >= shot_game) or (shot_game < 0.0 and shot_speed < 0.0 and (Time.get_ticks_msec() - started_ms) / 1000.0 >= shot_at)):
		shot_taken = true
		_take_shot()


func _sync_creatures(delta: float) -> void:
	var seen := {}
	for g in game.pack.gaunts:
		seen[g.id] = true
		if not views.has(g.id):
			var v := GauntView.new()
			add_child(v)
			v.setup(g)
			views[g.id] = v
		(views[g.id] as GauntView).sync(game.world, delta)
	for id in views.keys():
		if not seen.has(id):
			views[id].queue_free()
			views.erase(id)


func _take_shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(shot_path)
	print("shot saved: ", shot_path, " (", err, ")  size ", img.get_size())
	get_tree().quit()


# ----------------------------------------------------------------------------- events

func _on_lightning(delay: float) -> void:
	await get_tree().create_timer(delay, false).timeout
	audio.play("thunder", -4.0 - delay, 1.0, "Ambience")


func _p3(e: Dictionary, h: float = 0.8) -> Vector3:
	return GM.to3(e["pos"], h)


func _on_event(e: Dictionary) -> void:
	match e["type"]:
		"crash":
			var impact: float = e["impact"]
			if cam_log and crash_us == 0:
				crash_us = Time.get_ticks_usec()
				print("CAMLOG crash impact=%.1f tick=%d frame=%d" % [impact, tick_no, Engine.get_frames_drawn()])
			if audio_log:
				_log_crash(impact)
			var at: Vector3 = GM.to3(e["point"], 0.7)
			fx.spark_burst(at, clampf(impact / 18.0, 0.3, 1.0))
			# No hit-stop on a crash: it read as a freeze followed by a burst of movement.
			cam.add_trauma(clampf(impact / 40.0, 0.12, 0.5))
			fx.kick_chroma(clampf(impact / 25.0, 0.1, 0.8))
			if impact > 12.0:
				audio.play("crash-heavy", 0.0, audio.rng.randf_range(0.9, 1.05), "Car", 0.15)
				if impact > 17.0:
					audio.play("glass_break", -4.0, 1.0, "Car", 0.4)
			else:
				audio.play("crash-light", 0.0, audio.rng.randf_range(0.9, 1.1), "Car", 0.1)
			if str(e["kind"]) in ["wall", "building", "fence"]:
				audio.play("metal_scrape", -8.0, audio.rng.randf_range(0.9, 1.1), "Car", 0.6)
		"bump":
			var soft: float = e["impact"]
			audio.play("stomp", clampf(-14.0 + soft * 1.6, -14.0, -4.0), audio.rng.randf_range(0.8, 1.0), "Car", 0.12)
			cam.add_trauma(clampf(soft / 40.0, 0.03, 0.15))
		"hull":
			fx.wash_red(clampf(float(e["amount"]) * 0.025, 0.0, 0.4))
		"latch":
			fx.hit_stop(0.05, 0.1)
			cam.add_trauma(0.9)
			cam.punch_fov(12.0)
			fx.wash_red(0.6)
			fx.claw_scratch()
			fx.kick_chroma(0.9)
			audio.play("sting_latch", -2.0, 1.0, "SFX")
			audio.play("creature_latch", 0.0, audio.rng.randf_range(0.92, 1.05), "SFX")
			audio.play_at(audio.pick(["creature_screech_1", "creature_screech_2", "creature_screech_3"]), _p3(e), 2.0, 1.0, 110.0)
			audio.muffle(0.9)
		"claw":
			cam.add_trauma(0.18)
			audio.play("metal_scrape", -14.0, audio.rng.randf_range(1.1, 1.4), "SFX", 0.35)
		"thrown":
			cam.add_trauma(0.3)
			audio.play_at("creature_thrown", _p3(e), 2.0, audio.rng.randf_range(0.9, 1.1), 90.0)
			audio.play("slam", -6.0, 1.0, "SFX", 0.2)
		"bounce":
			cam.add_trauma(0.3)
			audio.play_at("creature_screech_3", _p3(e), 0.0, 1.0, 90.0)
		"roadkill":
			fx.hit_stop(0.04, 0.1)
			cam.add_trauma(0.4)
			fx.kick_chroma(0.35)
			fx.spark_burst(GM.to3(e["point"], 0.6), 0.4)
			audio.play(audio.pick(["splat-1", "splat-2", "splat-3"]), -1.0, 1.0, "SFX")
			audio.play_at("creature_death", _p3(e), 1.0, 1.0, 90.0)
		"died":
			audio.play_at("creature_death", _p3(e), 0.0, 1.0, 90.0)
		"alert":
			audio.play_at(audio.pick(["creature_screech_1", "creature_screech_2"]), _p3(e), 3.0, 1.0, 130.0, 2.0)
			cam.add_trauma(0.12)
		"leap":
			audio.play_at("creature_pounce", _p3(e), 1.0, audio.rng.randf_range(0.95, 1.1), 90.0)
		"wind":
			if audio.rng.randf() < 0.5:
				audio.play_at("creature_hiss", _p3(e), -2.0, 1.0, 60.0, 0.5)
		"chitter":
			audio.play_at("creature_chitter", _p3(e), -2.0, audio.rng.randf_range(0.9, 1.1), 90.0)
		"freeze":
			audio.play_at("creature_hiss", _p3(e), -5.0, 0.9, 50.0, 0.8)
		"flee":
			audio.play_at("creature_screech_2", _p3(e), -2.0, 1.1, 100.0, 1.5)
		"sputter":
			audio.play("sputter", -3.0, 1.0, "Car", 0.5)
		"boost":
			audio.play("boost", -4.0, 1.0, "Car", 0.5)
			cam.punch_fov(5.0)
		"wrecked":
			fx.hit_stop(0.25, 0.03)
			fx.desat = 0.85
			fx.fade_to(0.45)
			cam.add_trauma(1.0)
			audio.play("wreck", 0.0, 1.0, "Car")
			audio.muffle(1.0)
		"dawn":
			audio.play("thunder", -8.0, 1.0, "Ambience")
		"gate_open":
			gate_view.set_open(true)
			audio.play("gate_klaxon", -4.0, 1.0, "SFX")
			_gate_leaves_sound()
		"gate_closed":
			# A restart or retry has already put the leaves shut (world_reset): no sound for what was not seen.
			if gate_view.open_amount > 0.05:
				_gate_leaves_sound()
			gate_view.set_open(false)


## --audio-log: how long from the start of the physics tick that found the crash to the play()
## call, what the audio driver reports, and whether a sound started during hit-stop advances at
## real speed (its playback position 100 real ms later).
func _log_crash(impact: float) -> void:
	var before := Time.get_ticks_usec()
	var p := audio.play("crash-heavy", 0.0, 1.0, "Car", 0.0)
	var after := Time.get_ticks_usec()
	print("AUDIOLOG tick=%d impact=%.1f tick_to_play_us=%d play_call_us=%d out_latency_ms=%.1f mix_rate=%d next_mix_ms=%.1f time_scale=%.2f" % [
		tick_no, impact, before - tick_started_us, after - before,
		AudioServer.get_output_latency() * 1000.0, int(AudioServer.get_mix_rate()), AudioServer.get_time_to_next_mix() * 1000.0, Engine.time_scale])
	if p != null:
		var t0 := Time.get_ticks_usec()
		await get_tree().create_timer(0.1, true, false, true).timeout
		var real_ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("AUDIOLOG playback_position_after %.1f real ms = %.1f ms (time_scale now %.2f)" % [real_ms, p.get_playback_position() * 1000.0, Engine.time_scale])

extends Node3D
## Hollow Hours: wires the simulation (GameSim, 120 Hz) to everything you see and hear.
##
## Command line (after `--`): `--demo` lets an autopilot drive; `--shot=/path.png` saves a frame
## and quits after `--shot-at=SECONDS` (default 6) of real time; `--low` starts on the low
## graphics preset. Example (with a window, not --headless):
##   godot --path . -- --demo --shot=/tmp/hollow.png --shot-at=8

const DEMO_ROUTE := [
	Vector2(-14, -0.4), Vector2(3, -0.4), Vector2(8, 0.4), Vector2(50, 0.4), Vector2(62, 8), Vector2(62, 42),
	Vector2(40, 44), Vector2(10, 44), Vector2(5.8, 36), Vector2(5.8, 10), Vector2(2, -0.4), Vector2(-30, -0.4),
]

var game: GameSim
var city: City
var atmos: Atmosphere
var car_view: CarView
var cam: ChaseCamera
var fx: FX
var audio: AudioMix
var hud: Hud
var views := {}  # creature id -> GauntView
var prev_pos := Vector2.ZERO
var prev_angle := 0.0
var paused := false
var demo := false
var shot_path := ""
var shot_at := 6.0
var shot_taken := false
var started_ms := 0
var route_i := 0
var threat := 0.0
var ended := false


func _ready() -> void:
	InputSetup.ensure()
	Settings.apply_preset(true)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--demo":
			demo = true
		elif a == "--low":
			Settings.apply_preset(false)
		elif a.begins_with("--shot="):
			shot_path = a.trim_prefix("--shot=")
		elif a.begins_with("--shot-at="):
			shot_at = float(a.trim_prefix("--shot-at="))
	get_window().title = "Hollow Hours"
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	game = GameSim.new(CityLayout.DATA)
	city = City.new()
	add_child(city)
	city.build(CityLayout.DATA)
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
	atmos.lightning.connect(_on_lightning)
	_apply_viewport()
	prev_pos = game.car.body.position
	prev_angle = game.car.body.angle
	fx.fade_to(0.0)
	started_ms = Time.get_ticks_msec()


func _apply_viewport() -> void:
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_2X if Settings.msaa else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.set("use_taa", Settings.high)


# ----------------------------------------------------------------------------- input

func _controls() -> Dictionary:
	if demo:
		return _autopilot()
	return {
		"throttle": Input.get_axis("brake", "accelerate"),
		"turn": Input.get_axis("steer_right", "steer_left"),
		"handbrake": Input.is_action_pressed("handbrake"),
		"boost": Input.is_action_pressed("boost"),
	}


## A pure-pursuit driver round the town, for footage and for checking the game without hands.
func _autopilot() -> Dictionary:
	var car := game.car
	var target: Vector2 = DEMO_ROUTE[route_i]
	if car.body.position.distance_to(target) < 9.0:
		route_i = (route_i + 1) % DEMO_ROUTE.size()
		target = DEMO_ROUTE[route_i]
	var want := (target - car.body.position).angle()
	var err := angle_difference(car.body.angle, want)
	var throttle := 0.9 if absf(err) < 0.5 else 0.45
	return {"throttle": throttle, "turn": clampf(err * 2.4, -1.0, 1.0), "handbrake": false, "boost": false}


func _poll_actions() -> void:
	if Input.is_action_just_pressed("restart"):
		_restart()
	if Input.is_action_just_pressed("pause"):
		paused = not paused
		hud.center.text = "PAUSED" if paused else ""
		hud.sub.text = ""
	if Input.is_action_just_pressed("fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	if Input.is_action_just_pressed("quality"):
		Settings.apply_preset(not Settings.high)
		atmos.apply_quality()
		_apply_viewport()
	if Input.is_action_just_pressed("mute"):
		audio.toggle_mute()


func _restart() -> void:
	Engine.time_scale = 1.0
	game.reset()
	for id in views:
		views[id].queue_free()
	views.clear()
	hud.clear_end()
	hud.show_intro()
	hud.intro_time = 3.0
	fx.desat = 0.0
	fx.dawn = 0.0
	fx.fade = 0.6
	fx.fade_to(0.0)
	atmos.set_dawn(0.0)
	cam.inited = false
	prev_pos = game.car.body.position
	prev_angle = game.car.body.angle
	ended = false
	route_i = 0


# ----------------------------------------------------------------------------- the step

func _physics_process(delta: float) -> void:
	if paused:
		return
	prev_pos = game.car.body.position
	prev_angle = game.car.body.angle
	game.step(delta, _controls())
	for e in game.take_events():
		_on_event(e)
	if not ended and game.phase != GameSim.Phase.PLAYING:
		ended = true
		hud.show_end(game.phase, game)


func _process(delta: float) -> void:
	_poll_actions()
	var car := game.car
	var alpha := Engine.get_physics_interpolation_fraction()
	var pos := prev_pos.lerp(car.body.position, alpha)
	var ang := lerp_angle(prev_angle, car.body.angle, alpha)
	car_view.sync(game, game.world, pos, ang, delta)
	cam.update_camera(delta, pos, ang, car.body.velocity, car_view.ground, car.boosting)
	_sync_creatures(delta)

	var latched := game.pack.latched().size()
	var near := game.pack.nearest_hunter(car)
	var threat_in := clampf(1.0 - near / 45.0, 0.0, 1.0) + float(latched) * 0.35
	threat = clampf(threat_in, 0.0, 1.0)
	audio.update_mix(game, latched, threat, true, delta)
	hud.update_hud(game, latched, delta)
	fx.vignette = 0.42 + threat * 0.3
	fx.chroma = maxf(fx.chroma, clampf((car.speed() - 22.0) / 40.0, 0.0, 0.25))
	# Dawn creeps in over the last stretch of the night.
	var dawn := clampf((game.time - (GameSim.NIGHT_LENGTH - 45.0)) / 75.0, 0.0, 1.0)
	if absf(dawn - atmos.dawn_amount) > 0.002:
		atmos.set_dawn(dawn)
		fx.dawn = dawn * 0.6

	if shot_path != "" and not shot_taken and (Time.get_ticks_msec() - started_ms) / 1000.0 >= shot_at:
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
	await get_tree().create_timer(delay).timeout
	audio.play("thunder", -4.0 - delay, 1.0, "Ambience")


func _p3(e: Dictionary, h: float = 0.8) -> Vector3:
	return GM.to3(e["pos"], h)


func _on_event(e: Dictionary) -> void:
	match e["type"]:
		"crash":
			var impact: float = e["impact"]
			var at: Vector3 = GM.to3(e["point"], 0.7)
			fx.spark_burst(at, clampf(impact / 18.0, 0.3, 1.0))
			cam.add_trauma(clampf(impact / 22.0, 0.25, 1.0))
			if impact > 8.0:
				fx.hit_stop(clampf(0.03 + impact * 0.004, 0.04, 0.12), 0.06)
			fx.kick_chroma(clampf(impact / 25.0, 0.1, 0.8))
			if impact > 12.0:
				audio.play("crash-heavy", 0.0, audio.rng.randf_range(0.9, 1.05), "Car", 0.15)
				if impact > 17.0:
					audio.play("glass_break", -4.0, 1.0, "Car", 0.4)
			else:
				audio.play("crash-light", 0.0, audio.rng.randf_range(0.9, 1.1), "Car", 0.1)
			if str(e["kind"]) in ["wall", "building", "fence"]:
				audio.play("metal_scrape", -8.0, audio.rng.randf_range(0.9, 1.1), "Car", 0.6)
		"hull":
			fx.wash_red(clampf(float(e["amount"]) * 0.025, 0.0, 0.4))
		"latch":
			fx.hit_stop(0.09, 0.03)
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
			fx.hit_stop(0.035, 0.08)
			audio.play_at("creature_thrown", _p3(e), 2.0, audio.rng.randf_range(0.9, 1.1), 90.0)
			audio.play("slam", -6.0, 1.0, "SFX", 0.2)
		"bounce":
			cam.add_trauma(0.3)
			audio.play_at("creature_screech_3", _p3(e), 0.0, 1.0, 90.0)
		"roadkill":
			fx.hit_stop(0.07, 0.05)
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

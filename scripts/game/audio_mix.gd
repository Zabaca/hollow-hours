class_name AudioMix
extends Node
## Every sound. Buses (Master -> SFX, Car, Ambience, Music) are made here at start so no bus
## layout file is needed. Loops: the engine (Roadkill's recording, pitched by revs like Roadkill's
## sound.js), the tyre squeal, wet road, rain, the two music beds crossfaded by threat, footsteps
## and claws. One-shots are positional (AudioStreamPlayer3D) when they belong to a creature.

const DIR := "res://assets/audio/"

var engine: AudioStreamPlayer
var skid: AudioStreamPlayer
var road: AudioStreamPlayer
var rain: AudioStreamPlayer
var roof: AudioStreamPlayer
var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var heart: AudioStreamPlayer
var claws: AudioStreamPlayer
var sfx_bus := -1
var lowpass: AudioEffectLowPassFilter
var duck := 0.0
var threat := 0.0
var muted := false
var cooldowns := {}
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	_buses()
	engine = _loop("engine", "Car", -6.0)
	skid = _loop("skid", "Car", -80.0)
	road = _loop("wet_road_loop", "Car", -80.0)
	rain = _loop("rain_loop", "Ambience", -14.0)
	roof = _loop("rain_roof_loop", "Ambience", -80.0)
	music_a = _loop("music_tension", "Music", -9.0)
	music_b = _loop("music_chase", "Music", -80.0)
	heart = _loop("heartbeat_loop", "Ambience", -80.0)
	claws = _loop("creature_claw_loop", "SFX", -80.0)
	for p in [engine, skid, road, rain, roof, music_a, music_b, heart, claws]:
		(p as AudioStreamPlayer).play()


func _buses() -> void:
	for n in ["SFX", "Car", "Ambience", "Music"]:
		var i := AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(i, n)
		AudioServer.set_bus_send(i, "Master")
	sfx_bus = AudioServer.get_bus_index("SFX")
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.4
	rv.damping = 0.6
	rv.wet = 0.14
	rv.dry = 1.0
	AudioServer.add_bus_effect(sfx_bus, rv)
	lowpass = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 20500.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Car"), lowpass)
	var comp := AudioEffectCompressor.new()
	comp.threshold = -12.0
	comp.ratio = 3.0
	AudioServer.add_bus_effect(0, comp)


func _loop(file: String, bus: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = GM.loop_wav(DIR + file + ".wav")
	p.bus = bus
	p.volume_db = db
	add_child(p)
	return p


func _stream(file: String) -> AudioStream:
	var path := DIR + file + ".wav"
	if not ResourceLoader.exists(path):
		path = DIR + file + ".mp3"
	return load(path)


func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)


## A flat one-shot. `gap` stops the same sound stacking inside that many seconds.
func play(file: String, db: float = 0.0, pitch: float = 1.0, bus: String = "SFX", gap: float = 0.0) -> AudioStreamPlayer:
	if gap > 0.0:
		var now := Time.get_ticks_msec() / 1000.0
		if now - float(cooldowns.get(file, -99.0)) < gap:
			return null
		cooldowns[file] = now
	var p := AudioStreamPlayer.new()
	p.stream = _stream(file)
	p.bus = bus
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


## A one-shot placed in the world, so it pans and fades with distance.
func play_at(file: String, pos: Vector3, db: float = 0.0, pitch: float = 1.0, max_dist: float = 90.0, gap: float = 0.0) -> void:
	if gap > 0.0:
		var now := Time.get_ticks_msec() / 1000.0
		if now - float(cooldowns.get(file, -99.0)) < gap:
			return
		cooldowns[file] = now
	var p := AudioStreamPlayer3D.new()
	p.stream = _stream(file)
	p.bus = "SFX"
	p.volume_db = db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.unit_size = 9.0
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func pick(files: Array) -> String:
	return files[rng.randi() % files.size()]


## Called every frame with the car's state. `latched` is how many creatures are on the car,
## `threat` 0..1 how close the hunt is.
func update_mix(game: GameSim, latched: int, threat_in: float, raining_in: bool, delta: float) -> void:
	var car := game.car
	var speed := car.speed()
	var throttle := absf(float(game.last_controls.get("throttle", 0.0)))
	var revs := clampf(speed / 28.0, 0.0, 1.0) * 0.75 + throttle * 0.25
	var cut := 0.7 if game.sputter > 0.0 else 1.0
	var lift := 1.22 if car.boosting else 1.0
	var level := (0.07 + throttle * 0.04) * (0.25 if game.sputter > 0.0 else 1.0) * (1.15 if car.boosting else 1.0)
	engine.pitch_scale = clampf((0.65 + revs * 1.05) * cut * lift, 0.4, 2.2)
	engine.volume_db = linear_to_db(clampf(level * 7.0, 0.001, 1.3)) - 3.0
	if game.phase == GameSim.Phase.WRECKED:
		engine.volume_db = -80.0
	skid.pitch_scale = 0.9 + clampf(speed / 25.0, 0.0, 1.0) * 0.25
	skid.volume_db = linear_to_db(maxf(car.slide_amount() * 0.42, 0.0001))
	road.volume_db = linear_to_db(maxf(clampf(speed / 30.0, 0.0, 1.0) * 0.35, 0.0001))
	road.pitch_scale = 0.85 + clampf(speed / 40.0, 0.0, 0.4)

	threat = lerpf(threat, threat_in, GM.damp(1.6, delta))
	music_a.volume_db = linear_to_db(maxf((1.0 - threat) * 0.38, 0.0001))
	music_b.volume_db = linear_to_db(maxf(threat * 0.45, 0.0001))
	heart.volume_db = linear_to_db(maxf(clampf((threat - 0.35) * 1.5 + (1.0 - game.hull / GameSim.MAX_HULL) * 0.6, 0.0, 1.0) * 0.55, 0.0001))
	heart.pitch_scale = 0.9 + threat * 0.4
	rain.volume_db = -13.0 if raining_in else -80.0
	roof.volume_db = linear_to_db(maxf(0.05 + latched * 0.0, 0.0001)) - 8.0 if raining_in else -80.0
	claws.volume_db = linear_to_db(0.5) if latched > 0 else -80.0
	claws.pitch_scale = 0.9 + 0.1 * latched

	# Ducking: a landing muffles the car for a moment.
	duck = maxf(0.0, duck - delta * 1.4)
	lowpass.cutoff_hz = lerpf(20500.0, 700.0, clampf(duck, 0.0, 1.0))


func muffle(amount: float = 1.0) -> void:
	duck = maxf(duck, amount)

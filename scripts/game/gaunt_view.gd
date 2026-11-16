class_name GauntView
extends Node3D
## One creature on screen: gaunt.glb with the animations made in Blender (idle, stalk, sprint,
## pounce, latch, thrown, dead), driven by its GauntSim state. Its eyes are a material of their
## own: faint while it lurks, bright when it hunts.

const LOOPING := ["idle", "stalk", "sprint", "latch", "thrown"]

var sim: GauntSim
var model: Node3D
var anim: AnimationPlayer
var current := ""
var eyes: Array = []
var anim_names := {}  # short name -> actual name in the player
var smoothed := Vector3.ZERO
var first := true
var foot_audio: AudioStreamPlayer3D
var foot_kind := ""


func setup(g: GauntSim) -> void:
	sim = g
	var scene: PackedScene = load("res://assets/models/gaunt.glb")
	model = scene.instantiate()
	model.scale = Vector3.ONE * 1.3
	add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.size() > 0:
		anim = players[0]
		for n in anim.get_animation_list():
			var short := String(n).get_slice("/", String(n).get_slice_count("/") - 1)
			anim_names[short] = n
			if short in LOOPING:
				anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_find_eyes(model)
	foot_audio = AudioStreamPlayer3D.new()
	foot_audio.max_distance = 60.0
	foot_audio.unit_size = 7.0
	foot_audio.bus = "SFX"
	add_child(foot_audio)
	play("idle", 1.0)


func _find_eyes(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				if m is StandardMaterial3D and String(m.resource_name) == "eyes":
					var dup := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
					mi.set_surface_override_material(i, dup)
					eyes.append(dup)
	for c in node.get_children():
		_find_eyes(c)


func play(clip: String, speed: float = 1.0, blend: float = 0.15) -> void:
	if anim == null or not anim_names.has(clip):
		return
	if current != clip:
		current = clip
		anim.play(anim_names[clip], blend)
	anim.speed_scale = speed


func sync(world: SimWorld, delta: float) -> void:
	var g := sim
	var ground := world.height_at(g.pos)
	var target := GM.to3(g.pos, ground + g.z)
	if first:
		smoothed = target
		first = false
	# Teleport-like moves (a latch to a moving car, a leap) follow exactly; walking is smoothed.
	if g.state == GauntSim.State.LATCHED or g.state == GauntSim.State.LEAP or g.state == GauntSim.State.THROWN:
		smoothed = target
	else:
		smoothed = smoothed.lerp(target, GM.damp(40.0, delta))
	position = smoothed
	var yaw := g.heading
	var b := Basis.from_euler(Vector3(0.0, yaw, 0.0))
	if g.state == GauntSim.State.THROWN:
		b = b * Basis.from_euler(Vector3(0.0, 0.0, g.tumble)) * Basis.from_euler(Vector3(g.tumble * 0.4, 0.0, 0.0))
	elif g.state == GauntSim.State.LEAP:
		var u := clampf(g.t / PackSim.LEAP_TIME, 0.0, 1.0)
		b = b * Basis.from_euler(Vector3(0.0, 0.0, lerpf(0.25, -0.35, u)))
	basis = b

	var spd := g.vel.length()
	var eye_energy := 0.5
	match g.state:
		GauntSim.State.LURK:
			play("idle", 1.0)
			eye_energy = 0.5
		GauntSim.State.STALK:
			if g.frozen or spd < 0.4:
				play("idle", 0.6)
				eye_energy = 0.15 if g.frozen else 1.2
			else:
				play("stalk", clampf(spd / 3.0, 0.5, 1.6))
				eye_energy = 1.5
		GauntSim.State.HUNT, GauntSim.State.FLEE:
			play("sprint", clampf(spd / 14.0, 0.5, 1.7), 0.1)
			eye_energy = 4.0
		GauntSim.State.WIND:
			if current != "pounce":
				current = ""
				play("pounce", 1.0, 0.1)
			eye_energy = 5.0
		GauntSim.State.LEAP:
			if current != "pounce":
				current = ""
				play("pounce", 1.0, 0.05)
				anim.seek(PackSim.WIND_TIME, true)
			eye_energy = 5.0
		GauntSim.State.LATCHED:
			play("latch", 1.0, 0.05)
			eye_energy = 5.0
		GauntSim.State.THROWN:
			play("thrown", 1.0, 0.05)
			eye_energy = 3.0
		GauntSim.State.DOWN:
			play("dead", 1.0, 0.1)
			eye_energy = 2.0
		GauntSim.State.DEAD:
			play("dead", 1.0, 0.05)
			eye_energy = 0.0
	for m in eyes:
		(m as StandardMaterial3D).emission_energy_multiplier = lerpf((m as StandardMaterial3D).emission_energy_multiplier, eye_energy, GM.damp(10.0, delta))

	# Footsteps: wet claws on the road, louder and faster when it runs.
	var want := ""
	if g.state == GauntSim.State.HUNT or g.state == GauntSim.State.FLEE:
		want = "creature_run_loop"
	elif g.state == GauntSim.State.STALK and not g.frozen and spd > 0.4:
		want = "creature_stalk_loop"
	if want != foot_kind:
		foot_kind = want
		if want == "":
			foot_audio.stop()
		else:
			foot_audio.stream = GM.loop_wav("res://assets/audio/%s.wav" % want)
			foot_audio.play()
	if want != "":
		foot_audio.pitch_scale = clampf(0.85 + spd / 40.0, 0.8, 1.35)
		foot_audio.volume_db = -3.0 if want == "creature_run_loop" else -8.0

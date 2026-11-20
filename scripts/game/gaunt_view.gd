class_name GauntView
extends Node3D
## One creature on screen: gaunt.glb with the animations made in Blender (idle, stalk, sprint,
## pounce, latch, thrown, dead, missed, stunned), driven by its GauntSim state. Its eyes are a material
## of their own: faint while it lurks, bright when it hunts, and they throw the light back (eyeshine)
## whenever a headlight or lamp is on it.
##
## The model is 2.1 m hunched and about 2.4 m long on all fours, true size (scale 1). Where it tumbles
## (thrown, a leap) it turns about its middle, not its feet: PIVOT, in the model's own frame.

const LOOPING := ["idle", "stalk", "sprint", "latch", "thrown"]
const PIVOT := Vector3(0.1, 0.95, 0.0)
## On the car's flank (slots 3 and 4 of PackSim.SLOTS) its crouch would sink into the door: it is held this far back from the car (it faces the car).
const SIDE_SLOT_OFFSET := 0.45

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
var last_state := -1
var glints: Array = []  # two small additive points at the eyes that carry the eyeshine and the wind-up's flare across a dark street
var glow_mat: StandardMaterial3D
var down_clip := "stunned"  # which get-up it plays while DOWN: "missed" after a leap that found nothing, else "stunned"


func setup(g: GauntSim) -> void:
	sim = g
	var scene: PackedScene = load("res://assets/models/gaunt.glb")
	model = scene.instantiate()
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
	_make_glow()
	foot_audio = AudioStreamPlayer3D.new()
	foot_audio.max_distance = 60.0
	foot_audio.unit_size = 7.0
	foot_audio.bus = "SFX"
	add_child(foot_audio)
	play("idle", 1.0)


## Two small camera-facing glints on the head bone, one at each eye: a 2 cm eye is under a pixel at 25 m, so the glint carries the
## eyeshine and the wind-up's flare. Kept tight and dim enough that the body stays readable behind it.
func _make_glow() -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var skel: Skeleton3D = skels[0]
	var idx := skel.find_bone("head")
	if idx < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "head"
	skel.add_child(att)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(0, 0, 0, 1))
	grad.add_point(0.3, Color(0.55, 0.55, 0.55, 1))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	glow_mat = StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.disable_fog = true
	glow_mat.albedo_texture = tex
	glow_mat.albedo_color = Color(0, 0, 0)
	var rest := skel.get_bone_global_rest(idx).affine_inverse()
	for eye_at in [Vector3(0.94, 1.885, -0.037), Vector3(0.938, 1.879, 0.037)]:  # the two eyes in the rest pose, a hair in front of the sockets so the brow does not hide them
		var quad := QuadMesh.new()
		quad.size = Vector2(0.1, 0.1)
		var m := MeshInstance3D.new()
		m.mesh = quad
		m.position = rest * eye_at
		m.material_override = glow_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		att.add_child(m)
		glints.append(m)


func _find_eyes(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				if m is StandardMaterial3D and String(m.resource_name) == "skin":
					# a rim, so a headlight outlines the body and the crouch reads in the dark
					var sk := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
					sk.rim_enabled = true
					sk.rim = 0.55
					sk.rim_tint = 0.4
					mi.set_surface_override_material(i, sk)
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


## Play a one-shot clip stretched or squeezed to last as long as the state does (a stun is as long as its timer).
func play_fitted(clip: String, seconds: float, blend: float = 0.1) -> void:
	if anim == null or not anim_names.has(clip):
		return
	var clip_len := anim.get_animation(anim_names[clip]).length
	play(clip, clip_len / maxf(seconds, 0.1), blend)


func sync(world: SimWorld, delta: float) -> void:
	var g := sim
	if g.state != last_state:
		if g.state == GauntSim.State.DOWN:
			down_clip = "missed" if last_state == GauntSim.State.LEAP else "stunned"
		last_state = g.state
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
	model.position.x = -SIDE_SLOT_OFFSET if (g.state == GauntSim.State.LATCHED and (g.slot == 3 or g.slot == 4)) else 0.0
	# turn about the middle of the body, not the feet
	position = smoothed + Basis.from_euler(Vector3(0.0, yaw, 0.0)) * PIVOT - b * PIVOT

	var spd := g.vel.length()
	var eye_energy := 0.5
	match g.state:
		GauntSim.State.LURK:
			play("idle", 1.0)
			eye_energy = 0.5
		GauntSim.State.STALK:
			if g.frozen or spd < 0.4:
				play("idle", 0.6)
				eye_energy = 1.2  # (a frozen one is in a light: the eyeshine rule below takes over)
			else:
				play("stalk", clampf(spd / 3.0, 0.5, 1.6))
				eye_energy = 1.5
		GauntSim.State.HUNT, GauntSim.State.FLEE:
			play("sprint", clampf(spd / 14.0, 0.5, 1.7), 0.1)
			eye_energy = 4.0
		GauntSim.State.WIND:
			# The tell: the crouch of the pounce clip stretched over the whole wind-up, the eyes flaring.
			if current != "pounce":
				current = ""
				play("pounce", PackSim.WIND_ANIM / PackSim.WIND_TIME, 0.1)
			eye_energy = 9.0
		GauntSim.State.LEAP:
			if current != "pounce":
				current = ""
				play("pounce", 1.0, 0.05)
				anim.seek(PackSim.WIND_ANIM, true)
			eye_energy = 5.0
		GauntSim.State.LATCHED:
			play("latch", 1.0, 0.05)
			eye_energy = 5.0
		GauntSim.State.THROWN:
			play("thrown", 1.0, 0.05)
			eye_energy = 3.0
		GauntSim.State.DOWN:
			# Stunned, not dead: down for the stun's length with its eyes dimmed. The clip (a stagger and skid, a twitch on the ground,
			# the push-up, the get-up) is fitted to it: g.t + g.stun is the whole stun.
			play_fitted(down_clip, g.t + g.stun)
			eye_energy = 0.6
		GauntSim.State.DEAD:
			play("dead", 1.0, 0.05)
			eye_energy = 0.0
	if g.lit and g.state != GauntSim.State.DEAD and g.state != GauntSim.State.DOWN:
		eye_energy = maxf(eye_energy, minf(maxf(eye_energy, 2.0) * 1.5, 4.5))  # eyeshine: they throw the light back (never below the state's own)
	for m in eyes:
		(m as StandardMaterial3D).emission_energy_multiplier = lerpf((m as StandardMaterial3D).emission_energy_multiplier, minf(eye_energy, 6.0), GM.damp(10.0, delta))
	if glow_mat != null and not eyes.is_empty():
		var lvl := clampf((eyes[0] as StandardMaterial3D).emission_energy_multiplier / 6.0, 0.0, 1.0)
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			lvl *= clampf((cam.global_position.distance_to(global_position) - 3.0) / 3.0, 0.0, 1.0)  # not up close: the eye itself is enough
		glow_mat.albedo_color = Color(2.0, 2.0, 1.3) * lvl

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

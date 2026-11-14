class_name CarView
extends Node3D
## The car on screen: bruiser.glb driven by the CarSim's state. Position and heading are
## interpolated between the last two 120 Hz steps; the body rolls and pitches from the
## acceleration, wheels spin and steer, the headlights are real spots that cut the fog, the
## tail lights glow on the wet road, tyres throw spray and slides leave marks.

const WHEEL_R := 0.42
const SKID_POOL := 140

var model: Node3D
var steers := {}  # "FL"/"FR" -> pivot node
var wheels := {}  # "FL".."RR" -> wheel node
var wheel_spin := 0.0
var roll := 0.0
var pitch := 0.0
var ground := 0.0
var prev_vel := Vector2.ZERO
var head_l: SpotLight3D
var head_r: SpotLight3D
var tail: OmniLight3D
var reverse: OmniLight3D
var spray: Array = []
var marks: Array = []  # {node, age}
var mark_i := 0
var mark_mat_base: StandardMaterial3D
var last_mark_pos := [Vector3.ZERO, Vector3.ZERO]
var shell_mats: Array = []
var boost_glow := 0.0


func build() -> void:
	var scene: PackedScene = load("res://assets/models/bruiser.glb")
	model = scene.instantiate()
	add_child(model)
	for k in ["FL", "FR"]:
		steers[k] = model.find_child("steer_" + k, true, false)
	for k in ["FL", "FR", "RL", "RR"]:
		wheels[k] = model.find_child("wheel_" + k, true, false)
	_lights()
	_spray()
	_mark_pool()


func _lights() -> void:
	for sd in [-1.0, 1.0]:
		var s := SpotLight3D.new()
		s.spot_range = 60.0
		s.spot_angle = 30.0
		s.spot_angle_attenuation = 0.75
		s.spot_attenuation = 0.8
		s.light_energy = 14.0
		s.light_color = Color(1.0, 0.95, 0.82)
		s.light_volumetric_fog_energy = 3.5
		s.light_specular = 1.2
		s.shadow_enabled = true
		s.shadow_bias = 0.04
		s.position = Vector3(2.0, 0.78, sd * 0.66)
		model.add_child(s)
		s.basis = Basis.looking_at(Vector3(1.0, -0.075, sd * -0.03), Vector3.UP)
		if sd < 0.0:
			head_l = s
		else:
			head_r = s
	tail = OmniLight3D.new()
	tail.light_color = Color(1.0, 0.1, 0.08)
	tail.light_energy = 0.7
	tail.omni_range = 6.0
	tail.light_volumetric_fog_energy = 1.5
	tail.position = Vector3(-2.15, 0.85, 0.0)
	model.add_child(tail)
	reverse = OmniLight3D.new()
	reverse.light_color = Color(1.0, 1.0, 1.0)
	reverse.light_energy = 0.0
	reverse.omni_range = 7.0
	reverse.position = Vector3(-2.2, 0.8, 0.0)
	model.add_child(reverse)


func _spray() -> void:
	for sd in [-1.0, 1.0]:
		var p := GPUParticles3D.new()
		p.amount = 90
		p.lifetime = 0.8
		p.local_coords = false
		p.emitting = true
		p.position = Vector3(-1.4, 0.2, sd * 0.9)
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.0, 1.0, 0.0)
		pm.spread = 38.0
		pm.initial_velocity_min = 1.2
		pm.initial_velocity_max = 3.2
		pm.gravity = Vector3(0, -7.5, 0)
		pm.scale_min = 0.5
		pm.scale_max = 1.3
		var grad := Gradient.new()
		grad.set_color(0, Color(0.8, 0.85, 0.95, 0.28))
		grad.set_color(1, Color(0.8, 0.85, 0.95, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		pm.color_ramp = gt
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.4, 0.4)
		var m := StandardMaterial3D.new()
		m.albedo_texture = GM.soft_dot()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(0.85, 0.9, 1.0, 0.35)
		q.material = m
		p.draw_pass_1 = q
		p.amount_ratio = 0.0
		model.add_child(p)
		spray.append(p)


func _mark_pool() -> void:
	mark_mat_base = StandardMaterial3D.new()
	mark_mat_base.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark_mat_base.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mark_mat_base.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	mark_mat_base.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in SKID_POOL:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.36, 0.9)
		q.orientation = PlaneMesh.FACE_Y
		mi.mesh = q
		mi.material_override = mark_mat_base.duplicate()
		mi.top_level = true
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		marks.append({"node": mi, "age": 99.0})


func drop_mark(pos: Vector3, yaw_dir: float, strength: float) -> void:
	var m: Dictionary = marks[mark_i]
	mark_i = (mark_i + 1) % SKID_POOL
	var mi: MeshInstance3D = m["node"]
	mi.visible = true
	mi.global_position = Vector3(pos.x, 0.025, pos.z)
	mi.global_rotation = Vector3(0.0, yaw_dir, 0.0)
	m["age"] = 0.0
	m["peak"] = clampf(strength, 0.1, 0.55)


## Update from the sim. `pos`/`angle` are already interpolated; `world` is for ground height.
func sync(game: GameSim, world: SimWorld, pos: Vector2, angle: float, delta: float) -> void:
	var car := game.car
	var h := world.height_at(pos)
	ground = lerpf(ground, h, GM.damp(16.0, delta))
	var speed := car.speed()
	var jitter := 0.004 * sin(Time.get_ticks_msec() * 0.05) * clampf(speed / 20.0, 0.0, 1.0)
	position = GM.to3(pos, ground + jitter)

	# Body motion from acceleration, in the car's own frame.
	var vel := car.body.velocity
	var acc := (vel - prev_vel) / maxf(delta, 1e-4)
	prev_vel = vel
	var fwd := Vector2.from_angle(angle)
	var left := Vector2(-fwd.y, fwd.x)
	var lat := clampf(acc.dot(left), -30.0, 30.0)
	var lon := clampf(acc.dot(fwd), -30.0, 30.0)
	roll = lerpf(roll, clampf(lat * 0.0024, -0.075, 0.075), GM.damp(7.0, delta))
	pitch = lerpf(pitch, clampf(-lon * 0.0016, -0.05, 0.05), GM.damp(6.0, delta))
	basis = Basis.from_euler(Vector3(0.0, angle, 0.0))
	model.basis = Basis.from_euler(Vector3(roll, 0.0, pitch), EULER_ORDER_YXZ)

	# Wheels: spin at ground speed, front ones steer.
	var fwd_speed := vel.dot(fwd)
	wheel_spin -= fwd_speed / WHEEL_R * delta
	for k in wheels:
		var w: Node3D = wheels[k]
		if w != null:
			w.rotation.z = wheel_spin
	for k in steers:
		var s: Node3D = steers[k]
		if s != null:
			s.rotation.y = car.steer

	# Lights.
	tail.light_energy = 2.4 if car.braking else 0.7
	reverse.light_energy = 1.6 if car.drive < 0.0 else 0.0
	var flick := 1.0
	if game.sputter > 0.0:
		flick = 0.35 if int(Time.get_ticks_msec() / 60) % 2 == 0 else 1.0
	head_l.light_energy = 14.0 * flick
	head_r.light_energy = 14.0 * flick

	# Spray off the tyres once moving; marks when the rear tyres slide.
	var ratio := clampf((speed - 5.0) / 20.0, 0.0, 1.0)
	for p in spray:
		(p as GPUParticles3D).amount_ratio = ratio
	for i in [2, 3]:
		var wheel: Dictionary = car.wheels[i]
		if wheel["skidding"]:
			var wp := car.body.to_world(wheel["local"])
			var p3 := GM.to3(wp, 0.0)
			var key: int = int(i) - 2
			if p3.distance_to(last_mark_pos[key]) > 0.5:
				last_mark_pos[key] = p3
				var v := car.body.velocity_at(wp)
				drop_mark(p3, atan2(v.x, -v.y), 0.15 + car.slide_amount() * 0.4)
	for m in marks:
		if float(m["age"]) < 12.0:
			m["age"] = float(m["age"]) + delta
			var a := float(m["age"])
			var mi: MeshInstance3D = m["node"]
			var mat: StandardMaterial3D = mi.material_override
			var fade := clampf(1.0 - a / 12.0, 0.0, 1.0)
			mat.albedo_color = Color(0.0, 0.0, 0.0, float(m["peak"]) * fade)
			if a >= 12.0:
				mi.visible = false

class_name Atmosphere
extends Node3D
## Everything that makes the air: the environment (volumetric fog, glow, SSR, SDFGI, ACES), a dim
## moon, rain that follows the camera, puddle splashes, lightning, and the slow turn to dawn.

signal lightning(delay: float)

const NIGHT_SKY_TOP := Color(0.012, 0.018, 0.034)
const NIGHT_SKY_HORIZON := Color(0.07, 0.06, 0.075)
const DAWN_SKY_TOP := Color(0.18, 0.26, 0.4)
const DAWN_SKY_HORIZON := Color(0.85, 0.6, 0.45)
const NIGHT_FOG := Color(0.07, 0.085, 0.11)
const DAWN_FOG := Color(0.55, 0.5, 0.5)

var env := Environment.new()
var world_env := WorldEnvironment.new()
var sky_mat := ProceduralSkyMaterial.new()
var moon := DirectionalLight3D.new()
var flash := DirectionalLight3D.new()
var rain := GPUParticles3D.new()
var splash := GPUParticles3D.new()
var follow: Node3D
var dawn_amount := 0.0
var strike_timer := 14.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 21
	_make_environment()
	_make_lights()
	_make_rain()
	apply_quality()


func _make_environment() -> void:
	sky_mat.sky_top_color = NIGHT_SKY_TOP
	sky_mat.sky_horizon_color = NIGHT_SKY_HORIZON
	sky_mat.ground_horizon_color = NIGHT_SKY_HORIZON
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.014)
	sky_mat.sky_energy_multiplier = 0.7
	var sky := Sky.new()
	sky.sky_material = sky_mat
	GM.apply(env, {
		"background_mode": Environment.BG_SKY,
		"sky": sky,
		"ambient_light_source": Environment.AMBIENT_SOURCE_SKY,
		"ambient_light_energy": 1.5,
		"reflected_light_source": Environment.REFLECTION_SOURCE_SKY,
		"tonemap_mode": Environment.TONE_MAPPER_ACES,
		"tonemap_exposure": 1.0,
		"tonemap_white": 6.0,
		"fog_enabled": true,
		"fog_light_color": NIGHT_FOG,
		"fog_density": 0.006,
		"fog_sky_affect": 0.6,
		"volumetric_fog_enabled": true,
		"volumetric_fog_density": 0.032,
		"volumetric_fog_albedo": Color(0.72, 0.8, 0.88),
		"volumetric_fog_emission": Color(0.03, 0.04, 0.065),
		"volumetric_fog_emission_energy": 1.0,
		"volumetric_fog_anisotropy": 0.55,
		"volumetric_fog_length": 95.0,
		"volumetric_fog_detail_spread": 2.0,
		"volumetric_fog_gi_inject": 0.4,
		"volumetric_fog_ambient_inject": 0.3,
		"volumetric_fog_sky_affect": 0.5,
		"volumetric_fog_temporal_reprojection_enabled": true,
		"glow_enabled": true,
		"glow_intensity": 0.8,
		"glow_strength": 1.1,
		"glow_bloom": 0.08,
		"glow_hdr_threshold": 0.9,
		"glow_blend_mode": Environment.GLOW_BLEND_MODE_SCREEN,
		"ssr_enabled": true,
		"ssr_max_steps": 64,
		"ssr_fade_in": 0.12,
		"ssr_fade_out": 2.0,
		"ssr_depth_tolerance": 0.25,
		"ssao_enabled": true,
		"ssao_radius": 1.6,
		"ssao_intensity": 2.0,
		"sdfgi_enabled": true,
		"sdfgi_use_occlusion": true,
		"sdfgi_bounce_feedback": 0.35,
		"sdfgi_energy": 1.0,
		"adjustment_enabled": true,
		"adjustment_contrast": 1.08,
		"adjustment_saturation": 0.88,
	})
	world_env.environment = env
	add_child(world_env)


func _make_lights() -> void:
	# A faint cold moon through the cloud: just enough to give the buildings an edge.
	moon.light_color = Color(0.45, 0.55, 0.8)
	moon.light_energy = 0.3
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 90.0
	moon.rotation_degrees = Vector3(-52, 35, 0)
	add_child(moon)
	flash.light_color = Color(0.8, 0.88, 1.0)
	flash.light_energy = 0.0
	flash.shadow_enabled = true
	flash.rotation_degrees = Vector3(-38, -60, 0)
	add_child(flash)


func _make_rain() -> void:
	rain.amount = 5500
	rain.lifetime = 1.1
	rain.preprocess = 1.2
	rain.local_coords = false
	rain.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(26, 0.5, 26)
	pm.direction = Vector3(0.14, -1.0, 0.06)
	pm.spread = 2.5
	pm.initial_velocity_min = 24.0
	pm.initial_velocity_max = 30.0
	pm.gravity = Vector3(0, -6, 0)
	rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.65)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.75, 0.82, 0.95, 0.42)
	q.material = m
	rain.draw_pass_1 = q
	add_child(rain)

	splash.amount = 420
	splash.lifetime = 0.35
	splash.local_coords = false
	splash.visibility_aabb = AABB(Vector3(-30, -2, -30), Vector3(60, 6, 60))
	var sp := ParticleProcessMaterial.new()
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sp.emission_box_extents = Vector3(16, 0.0, 16)
	sp.gravity = Vector3.ZERO
	sp.initial_velocity_min = 0.0
	sp.initial_velocity_max = 0.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.25))
	curve.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	sp.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.8, 0.88, 1.0, 0.3))
	grad.set_color(1, Color(0.8, 0.88, 1.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	sp.color_ramp = gt
	splash.process_material = sp
	var sq := QuadMesh.new()
	sq.size = Vector2(0.2, 0.2)
	sq.orientation = PlaneMesh.FACE_Y
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = GM.soft_dot()
	sm.albedo_color = Color(0.8, 0.88, 1.0, 1.0)
	sq.material = sm
	splash.draw_pass_1 = sq
	add_child(splash)


## Re-read the graphics switches (Settings) into the environment.
func apply_quality() -> void:
	GM.apply(env, {
		"sdfgi_enabled": Settings.sdfgi,
		"ssr_enabled": Settings.ssr,
		"ssao_enabled": Settings.ssao,
		"volumetric_fog_enabled": Settings.volumetric,
	})
	moon.shadow_enabled = Settings.high


## 0 = deep night, 1 = first light. Fades sky, fog, moon and exposure.
func set_dawn(a: float) -> void:
	dawn_amount = clampf(a, 0.0, 1.0)
	sky_mat.sky_top_color = NIGHT_SKY_TOP.lerp(DAWN_SKY_TOP, dawn_amount)
	sky_mat.sky_horizon_color = NIGHT_SKY_HORIZON.lerp(DAWN_SKY_HORIZON, dawn_amount)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.sky_energy_multiplier = lerpf(0.7, 1.4, dawn_amount)
	env.fog_light_color = NIGHT_FOG.lerp(DAWN_FOG, dawn_amount)
	env.set("volumetric_fog_density", lerpf(0.032, 0.011, dawn_amount))
	env.fog_density = lerpf(0.006, 0.0035, dawn_amount)
	env.set("volumetric_fog_emission", Color(0.03, 0.04, 0.065).lerp(Color(0.3, 0.26, 0.24), dawn_amount))
	moon.light_energy = lerpf(0.3, 0.9, dawn_amount)
	moon.light_color = Color(0.45, 0.55, 0.8).lerp(Color(1.0, 0.82, 0.65), dawn_amount)
	env.set("ambient_light_energy", lerpf(1.5, 2.2, dawn_amount))


func _process(delta: float) -> void:
	if follow != null:
		var p := follow.global_position
		rain.global_position = Vector3(p.x, 18.0, p.z)
		splash.global_position = Vector3(p.x, 0.04, p.z)
	strike_timer -= delta
	if strike_timer <= 0.0 and dawn_amount < 0.5:
		strike_timer = rng.randf_range(22.0, 48.0)
		strike()


## A lightning flash (the whole city in cold white for a blink), then thunder after `delay`.
func strike() -> void:
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 5.0, 0.03)
	tw.tween_property(flash, "light_energy", 0.4, 0.07)
	tw.tween_property(flash, "light_energy", 6.5, 0.04)
	tw.tween_property(flash, "light_energy", 0.0, 0.6)
	var sky_tw := create_tween()
	sky_tw.tween_property(sky_mat, "sky_energy_multiplier", 4.0, 0.04)
	sky_tw.tween_property(sky_mat, "sky_energy_multiplier", lerpf(0.7, 1.4, dawn_amount), 0.7)
	lightning.emit(rng.randf_range(0.5, 3.5))

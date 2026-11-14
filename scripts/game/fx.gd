class_name FX
extends Node
## Game feel: hit-stop, spark bursts, and the screen effects (red wash, claw scratches, chromatic
## aberration, vignette, grain, fades) drawn by shaders/screen_fx.gdshader over the 3D view.
## Camera shake lives on the ChaseCamera; main.gd asks for all of it when something lands.

const SCREEN_SHADER := preload("res://shaders/screen_fx.gdshader")

var layer := CanvasLayer.new()
var rect := ColorRect.new()
var mat := ShaderMaterial.new()
var sparks: Array = []
var spark_i := 0
var stop_token := 0

# Eased screen state: each decays toward its resting value.
var red := 0.0
var scratches := 0.0
var chroma := 0.0
var desat := 0.0
var vignette := 0.45
var fade := 1.0  # starts black and fades in
var fade_target := 0.0
var dawn := 0.0
var scratch_seed := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer.layer = 10
	add_child(layer)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat.shader = SCREEN_SHADER
	rect.material = mat
	layer.add_child(rect)
	_make_sparks()


func _make_sparks() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -16, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.5, 1.0))
	grad.set_color(1, Color(1.0, 0.25, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.22)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1, 1)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.6, 0.2)
	m.emission_energy_multiplier = 5.0
	q.material = m
	for i in 8:
		var p := GPUParticles3D.new()
		p.amount = 36
		p.lifetime = 0.55
		p.one_shot = true
		p.explosiveness = 1.0
		p.emitting = false
		p.local_coords = false
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		p.process_material = pm
		p.draw_pass_1 = q
		p.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 12, 16))
		add_child(p)
		sparks.append(p)


## A burst of sparks at a world position. `amount` 0..1 scales the count of the burst.
func spark_burst(pos: Vector3, amount: float = 1.0) -> void:
	var p: GPUParticles3D = sparks[spark_i]
	spark_i = (spark_i + 1) % sparks.size()
	p.global_position = pos
	p.amount = int(clampf(amount, 0.2, 1.0) * 36)
	p.restart()
	p.emitting = true


## Freeze the game for `duration` real seconds (to a crawl rather than a full stop, so the
## camera shake and the particles still breathe). Overlapping calls extend rather than stack.
func hit_stop(duration: float, scale: float = 0.04) -> void:
	stop_token += 1
	var mine := stop_token
	Engine.time_scale = scale
	var timer := get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(func() -> void:
		if mine == stop_token:
			Engine.time_scale = 1.0)


func wash_red(amount: float) -> void:
	red = minf(1.0, red + amount)


func claw_scratch() -> void:
	scratches = 1.0
	scratch_seed = randf_range(-1.0, 1.0)


func kick_chroma(amount: float) -> void:
	chroma = minf(1.0, chroma + amount)


func fade_to(value: float) -> void:
	fade_target = value


func _process(delta: float) -> void:
	# Real-time decay, not game time, so the hit-stop crawl does not freeze the effects.
	var rd := delta / maxf(Engine.time_scale, 0.001)
	red = maxf(0.0, red - rd * 0.9)
	scratches = maxf(0.0, scratches - rd * 0.45)
	chroma = maxf(0.0, chroma - rd * 2.2)
	fade = move_toward(fade, fade_target, rd * 0.7)
	mat.set_shader_parameter("red", red)
	mat.set_shader_parameter("scratches", scratches)
	mat.set_shader_parameter("chroma", chroma)
	mat.set_shader_parameter("desat", desat)
	mat.set_shader_parameter("vignette", vignette)
	mat.set_shader_parameter("fade", fade)
	mat.set_shader_parameter("dawn", dawn)
	mat.set_shader_parameter("seed", scratch_seed)

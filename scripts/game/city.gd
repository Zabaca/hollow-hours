class_name City
extends Node3D
## The city as the player sees it: city.glb from Blender, restyled for rain (wet asphalt shader,
## lower roughness everywhere), plus every light the layout lists (live lamps, the gas station,
## burning barrels, wrecks with a headlamp still on) and the fire particles.

const GROUND_SHADER := preload("res://shaders/wet_ground.gdshader")
const KEEP_AS_IS := ["lit_", "neon_", "headlamp", "lamp_head", "beacon", "fire", "tail_red"]

var layout: Dictionary
var lights: Array = []  # {node, base, flicker, off_t}
var noise_tex: ImageTexture
var ground_mats := {}
var time := 0.0
var rng := RandomNumberGenerator.new()


func build(layout_data: Dictionary, model_path: String) -> void:
	layout = layout_data
	rng.seed = 5
	noise_tex = _make_noise()
	var scene: PackedScene = load(model_path)
	var root := scene.instantiate()
	root.name = "CityMesh"
	add_child(root)
	_restyle(root)
	_add_lights()
	_add_fires()


func _make_noise() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.012
	n.fractal_octaves = 3
	n.seed = 13
	var img := n.get_seamless_image(256, 256)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _ground_material(kind: String) -> ShaderMaterial:
	if ground_mats.has(kind):
		return ground_mats[kind]
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	m.set_shader_parameter("noise_tex", noise_tex)
	if kind == "asphalt":
		m.set_shader_parameter("base_color", Color(0.12, 0.125, 0.14))
		m.set_shader_parameter("puddle_amount", 0.62)
		m.set_shader_parameter("base_rough", 0.5)
	else:
		m.set_shader_parameter("base_color", Color(0.2, 0.21, 0.22))
		m.set_shader_parameter("puddle_amount", 0.38)
		m.set_shader_parameter("base_rough", 0.6)
		m.set_shader_parameter("ripple_strength", 0.4)
	ground_mats[kind] = m
	return m


func _restyle(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var mesh := mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i)
				if m == null:
					continue
				var mname := String(m.resource_name)
				if mname == "asphalt":
					mi.set_surface_override_material(i, _ground_material("asphalt"))
				elif mname == "sidewalk":
					mi.set_surface_override_material(i, _ground_material("sidewalk"))
				elif m is StandardMaterial3D:
					var keep := false
					for k in KEEP_AS_IS:
						if mname.begins_with(k):
							keep = true
					var sm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
					if mname.begins_with("lit_"):
						# Lit windows were blowing out into white slabs under bloom.
						sm.emission_energy_multiplier *= 0.45
					if not keep:
						# Rain on everything: shinier, and glass that actually reflects.
						sm.roughness = clampf(sm.roughness * 0.72, 0.04, 1.0)
						if mname == "glass" or mname == "shopglass":
							sm.metallic = 0.85
							sm.roughness = 0.05
					mi.set_surface_override_material(i, sm)
	for c in node.get_children():
		_restyle(c)


func _add_lights() -> void:
	for l in layout["lights"]:
		var pos := Vector3(float(l["x"]), float(l["z"]), -float(l["y"]))
		var col := Color(l["color"][0], l["color"][1], l["color"][2])
		var energy := float(l["energy"])
		var node: Light3D
		if l["kind"] == "spot":
			var s := SpotLight3D.new()
			s.spot_range = float(l["range"])
			s.spot_angle = float(l["angle"])
			s.spot_attenuation = 0.9
			s.shadow_enabled = true
			var dir := Vector3(float(l["dx"]), -0.03, -float(l["dy"])).normalized()
			s.position = pos
			add_child(s)
			s.basis = Basis.looking_at(dir, Vector3.UP)
			node = s
			energy *= 0.7
		else:
			var o := OmniLight3D.new()
			o.omni_range = float(l["range"])
			o.omni_attenuation = 1.4
			o.position = pos
			add_child(o)
			node = o
			energy *= 0.6
		node.light_color = col
		node.light_energy = energy
		node.light_volumetric_fog_energy = float(l["fog"])
		node.light_specular = 1.0
		node.distance_fade_enabled = true
		node.distance_fade_begin = 70.0
		node.distance_fade_length = 25.0
		lights.append({"node": node, "base": energy, "flicker": float(l["flicker"]), "off_t": 0.0, "phase": rng.randf() * 10.0})


func _add_fires() -> void:
	for f in layout["fires"]:
		var p := GPUParticles3D.new()
		p.position = Vector3(float(f["x"]), 1.0, -float(f["y"]))
		p.amount = 36
		p.lifetime = 0.9
		p.local_coords = false
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.18
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 14.0
		pm.initial_velocity_min = 1.2
		pm.initial_velocity_max = 2.4
		pm.gravity = Vector3(0, 0.6, 0)
		pm.scale_min = 0.5
		pm.scale_max = 1.2
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.75, 0.3, 0.9))
		grad.set_color(1, Color(0.6, 0.1, 0.0, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		pm.color_ramp = gt
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.4, 0.4)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = GM.soft_dot()
		mat.albedo_color = Color(1, 0.6, 0.25, 1)
		q.material = mat
		p.draw_pass_1 = q
		add_child(p)


func _process(delta: float) -> void:
	time += delta
	for l in lights:
		var node: Light3D = l["node"]
		var f: float = l["flicker"]
		if f <= 0.0:
			continue
		# A failing lamp: now and then it drops almost out for a fraction of a second, with a
		# constant tremble in between.
		if l["off_t"] > 0.0:
			l["off_t"] = float(l["off_t"]) - delta
			node.light_energy = float(l["base"]) * 0.06
		else:
			var tremble := 1.0 - f * 0.25 * (0.5 + 0.5 * sin(time * 31.0 + float(l["phase"])))
			node.light_energy = float(l["base"]) * tremble
			if rng.randf() < f * 0.9 * delta:
				l["off_t"] = rng.randf_range(0.05, 0.25)

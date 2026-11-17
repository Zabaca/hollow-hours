class_name GateView
extends Node3D
## The west gate as the player sees it. Blender builds the gap in the wall, the piers (outside the sim's
## wall) and the road outside (tools/blender/city.py); this draws what moves: two steel leaves that roll
## apart along the wall's inner face, the lamps on the piers (red while it is shut, flashing amber as it opens, green once it
## is open) and the cordon's two searchlights beyond the wall, which sweep the wall until the gate opens
## and then hold on the gap. `track` points them at something else (the car, in the ending).

const LEAF_W := 4.1
const LEAF_H := 4.2
const OPEN_SECONDS := 3.6
const LAMP_LIGHT := 0.22  # share of the lamp glass's brightness thrown as light
const SLIDE := 6.1  # metres each leaf rolls out from its closed place
const RAIL_X := 0.16  # the leaves hang this far in from the gate's x: on the wall's inner face, in front of the piers

var open_amount := 0.0
var target_open := false
var centre := Vector3.ZERO
var half_width := 4.0
var leaves: Array = []  # [{node, side}]
var lamps: Array = []  # [{mesh, light}]
var units: Array = []  # [{head, light, base}]
var _time := 0.0
var _track := Vector3.INF


## Build the leaves, lamps and searchlights where the world's gate record puts them, in the gate's state now.
func setup(world: SimWorld) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the leaves finish closing under the fail menu, not frozen part way
	var g: Dictionary = world.gate
	centre = GM.to3(g["pos"])
	half_width = float(g["width"]) * 0.5
	_build_leaves()
	_build_lamps()
	_build_searchlights()
	set_open(bool(g["open"]), true)


## Open or shut it. `instant` is for setting it up in a state (a retry, a new scene).
func set_open(on: bool, instant: bool = false) -> void:
	target_open = on
	if instant:
		open_amount = 1.0 if on else 0.0
		_pose()


## Hold the searchlights on a world point (null-like Vector3.INF lets them go back to their sweep).
func track(p: Vector3) -> void:
	_track = p


func _steel(color: Color, metal: float = 0.8, rough: float = 0.45) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	return m


func _box(size: Vector3, mat: Material, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = at
	return mi


func _build_leaves() -> void:
	var steel := _steel(Color(0.13, 0.14, 0.15))
	var stripe := _steel(Color(0.62, 0.48, 0.09), 0.2, 0.6)
	for side in [-1, 1]:
		var leaf := Node3D.new()
		leaf.position = centre + Vector3(RAIL_X, 0.0, 0.0)
		add_child(leaf)
		leaf.add_child(_box(Vector3(0.2, LEAF_H, LEAF_W), steel, Vector3(0.0, LEAF_H * 0.5 + 0.1, 0.0)))
		for k in 3:
			leaf.add_child(_box(Vector3(0.24, 0.16, LEAF_W - 0.2), stripe, Vector3(-0.02, 0.8 + k * 1.3, 0.0)))
		for k in 5:
			leaf.add_child(_box(Vector3(0.3, LEAF_H, 0.1), steel, Vector3(0.05, LEAF_H * 0.5 + 0.1, -LEAF_W * 0.5 + 0.4 + k * (LEAF_W - 0.8) / 4.0)))
		leaves.append({"node": leaf, "side": side})


func _build_lamps() -> void:
	for side in [-1, 1]:
		var mesh := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.24
		s.height = 0.48
		mesh.mesh = s
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.1, 0.08)
		mesh.material_override = m
		mesh.position = centre + Vector3(0.3, 4.9, side * (half_width + 0.7))
		add_child(mesh)
		var light := OmniLight3D.new()
		light.omni_range = 8.0
		light.light_energy = 0.35
		light.light_color = Color(1.0, 0.1, 0.08)
		light.shadow_enabled = false
		light.position = mesh.position + Vector3(1.5, 0.0, 0.0)
		add_child(light)
		lamps.append({"mesh": mesh, "light": light, "mat": m})


func _build_searchlights() -> void:
	var body := _steel(Color(0.1, 0.11, 0.12), 0.5, 0.6)
	for side in [-1, 1]:
		var unit := Node3D.new()
		unit.position = centre + Vector3(-27.0, 0.0, side * 16.0)
		add_child(unit)
		unit.add_child(_box(Vector3(1.8, 1.0, 1.4), body, Vector3(0.0, 0.5, 0.0)))
		unit.add_child(_box(Vector3(0.3, 1.2, 0.3), body, Vector3(0.0, 1.5, 0.0)))
		var head := Node3D.new()
		head.position = Vector3(0.0, 2.3, 0.0)
		unit.add_child(head)
		var can := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.5
		cyl.bottom_radius = 0.42
		cyl.height = 1.3
		can.mesh = cyl
		can.material_override = body
		can.rotation.z = PI / 2.0
		can.position = Vector3(0.5, 0.0, 0.0)
		head.add_child(can)
		var lens := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.44
		disc.bottom_radius = 0.44
		disc.height = 0.05
		lens.mesh = disc
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = Color(1.0, 0.96, 0.86)
		lens.material_override = lm
		lens.rotation.z = PI / 2.0
		lens.position = Vector3(1.16, 0.0, 0.0)
		head.add_child(lens)
		var spot := SpotLight3D.new()
		spot.spot_angle = 7.5
		spot.spot_attenuation = 0.6
		spot.spot_range = 150.0
		spot.light_energy = 6.0
		spot.light_color = Color(1.0, 0.95, 0.84)
		spot.light_volumetric_fog_energy = 0.7
		spot.shadow_enabled = false
		# A SpotLight3D shines down its own -Z: turn it to the head's +X (the head is aimed with look_at).
		spot.rotation.y = -PI / 2.0
		spot.position = Vector3(1.2, 0.0, 0.0)
		head.add_child(spot)
		units.append({"head": head, "side": side, "unit": unit})


func _process(delta: float) -> void:
	_time += delta
	var step := delta / OPEN_SECONDS
	open_amount = move_toward(open_amount, 1.0 if target_open else 0.0, step)
	_pose()
	_aim(delta)


func _pose() -> void:
	var e := open_amount * open_amount * (3.0 - 2.0 * open_amount)
	for l in leaves:
		var side: int = l["side"]
		# Each leaf closes over its half of the gap and rolls outward as it opens.
		l["node"].position.z = centre.z + side * (LEAF_W * 0.5 - 0.05 + SLIDE * e)
	var moving := open_amount > 0.001 and open_amount < 0.999
	for lp in lamps:
		var col: Color
		var energy := 2.4
		if moving:
			var on := int(_time * 4.0) % 2 == 0
			col = Color(1.0, 0.55, 0.05)
			energy = 3.2 if on else 0.2
		elif open_amount >= 0.999:
			col = Color(0.1, 1.0, 0.35)
		else:
			col = Color(1.0, 0.1, 0.08)
			energy = 1.4 + 1.0 * (0.5 + 0.5 * sin(_time * 2.0))
		lp["mat"].albedo_color = col * (energy / 2.4 if energy < 2.4 else 1.0)
		lp["light"].light_color = col
		lp["light"].light_energy = energy * LAMP_LIGHT  # the glass is bright; the light it throws on the piers is not


func _aim(delta: float) -> void:
	for u in units:
		var head: Node3D = u["head"]
		var side: int = u["side"]
		var target: Vector3
		if _track != Vector3.INF:
			target = _track
		elif target_open:
			target = centre + Vector3(2.0, 0.5, side * 0.6)
		else:
			# Shut: the beams walk along the wall, one each way, never quite meeting.
			var sweep := sin(_time * 0.35 + (0.0 if side < 0 else 2.2)) * 18.0
			target = centre + Vector3(1.5, 0.5, sweep)
		var dir := target - head.global_position
		if dir.length() < 0.1:
			continue
		# The head's +X is the beam: aim it with looking_at (which points -Z) turned a quarter round.
		var want := Quaternion(Basis.looking_at(dir.normalized(), Vector3.UP) * Basis(Vector3.UP, PI / 2.0))
		var now := Quaternion(head.global_transform.basis.orthonormalized())
		head.global_transform.basis = Basis(now.slerp(want, GM.damp(2.2, delta)))

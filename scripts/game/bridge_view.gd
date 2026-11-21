class_name BridgeView
extends Node3D
## The harbour city's lift bridge as the player sees it. Blender builds the towers, the beam and the road's edges (tools/blender/
## harbour.py) and two pieces that move: the deck (`lift_deck`, hung 13.2 m up between the towers) and its cables (`lift_cables`).
## This lowers the deck onto the road and stretches the cables with it, raises it again, and runs the four warning lamps on the
## towers (red while it is up, flashing amber while it moves, green once it is down). The sim's colliders follow separately
## (SimWorld.set_lift); this is only what is drawn.

const LOWER_SECONDS := 9.0
const RAISE_SECONDS := 6.0
const LAMP_LIGHT := 0.35

var down_amount := 0.0  # 0 raised, 1 down
var target_down := false
var centre := Vector3.ZERO
var deck: Node3D
var cables: Node3D
var drop := 13.2  # how far the deck comes down
var top := 23.2  # where the cables hang from
var lamps: Array = []  # [{mesh, light, mat}]
var _time := 0.0


## `city` holds the model; `layout` is the city's layout (its lift bridge record says where and how big).
func setup(city: Node, layout: Dictionary) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var rec: Dictionary = {}
	for b in layout.get("bridges", []):
		if str(b.get("kind", "")) == "lift":
			rec = b
	if rec.is_empty():
		return
	drop = float(rec.get("deck_up_z", drop))
	top = float(rec.get("cable_top_z", top))
	centre = GM.to3(Vector2(float(rec["x"]), float(rec["y"])), 0.0)
	deck = city.find_child("lift_deck", true, false)
	cables = city.find_child("lift_cables", true, false)
	var half_len := float(rec["length"]) * 0.5
	var half_w := float(rec["width"]) * 0.5
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			var at := Vector2(float(rec["x"]) + sx * (half_len - 1.5), float(rec["y"]) + sy * (half_w - 1.9))
			_build_lamp(GM.to3(at, 5.0))
	set_down(false, true)


func _build_lamp(at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.3
	s.height = 0.6
	mesh.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.1, 0.08)
	mesh.material_override = m
	mesh.position = at
	add_child(mesh)
	var light := OmniLight3D.new()
	light.omni_range = 12.0
	light.light_energy = 0.4
	light.light_color = Color(1.0, 0.1, 0.08)
	light.shadow_enabled = false
	light.position = at
	add_child(light)
	lamps.append({"mesh": mesh, "light": light, "mat": m})


## Lower or raise it. `instant` is for setting it up in a state (a retry, a new scene).
func set_down(on: bool, instant: bool = false) -> void:
	target_down = on
	if instant:
		down_amount = 1.0 if on else 0.0
		_pose()


func _process(delta: float) -> void:
	_time += delta
	var seconds := LOWER_SECONDS if target_down else RAISE_SECONDS
	down_amount = move_toward(down_amount, 1.0 if target_down else 0.0, delta / seconds)
	_pose()


func moving() -> bool:
	return down_amount > 0.001 and down_amount < 0.999


func _pose() -> void:
	var e := down_amount * down_amount * (3.0 - 2.0 * down_amount)
	if deck != null:
		deck.position.y = -drop * e
	if cables != null:
		var sy := 1.0 + e * drop / (top - drop)
		cables.scale = Vector3(1.0, sy, 1.0)
		cables.position.y = top * (1.0 - sy)
	for lp in lamps:
		var col: Color
		var energy := 2.4
		if moving():
			col = Color(1.0, 0.55, 0.05)
			energy = 3.2 if int(_time * 4.0) % 2 == 0 else 0.2
		elif down_amount >= 0.999:
			col = Color(0.1, 1.0, 0.35)
		else:
			col = Color(1.0, 0.1, 0.08)
			energy = 1.4 + 1.0 * (0.5 + 0.5 * sin(_time * 2.0))
		lp["mat"].albedo_color = col * (energy / 2.4 if energy < 2.4 else 1.0)
		lp["light"].light_color = col
		lp["light"].light_energy = energy * LAMP_LIGHT

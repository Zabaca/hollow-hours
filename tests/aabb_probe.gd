extends Node
## Prints the car model's bounds against the sim's collision box (4 x 2 m, centre at the origin).
##   godot --headless --path . res://tests/aabb_probe.tscn

func _ready() -> void:
	var m: Node3D = (load("res://assets/models/bruiser.glb") as PackedScene).instantiate()
	add_child(m)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var box := mi.global_transform * mi.get_aabb()
		lo = lo.min(box.position)
		hi = hi.max(box.end)
	print("model x %.2f .. %.2f (collider -2.00 .. 2.00)   z %.2f .. %.2f (collider -1.00 .. 1.00)" % [lo.x, hi.x, lo.z, hi.z])
	get_tree().quit()

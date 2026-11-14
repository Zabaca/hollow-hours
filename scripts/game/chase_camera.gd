class_name ChaseCamera
extends Camera3D
## The third-person camera: behind and above the car, following its heading late and its
## velocity a little, so a drift shows the slide. Speed widens the field of view, trauma shakes it,
## and it pulls in rather than sit inside a building.

var yaw := 0.0
var trauma := 0.0
var fov_punch := 0.0
var boost_amount := 0.0
var dist := 8.6
var time := 0.0
var world: SimWorld
var inited := false


func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


func punch_fov(deg: float) -> void:
	fov_punch = maxf(fov_punch, deg)


func update_camera(delta: float, car_pos: Vector2, car_angle: float, car_vel: Vector2, ground: float, boosting: bool) -> void:
	time += delta
	var speed := car_vel.length()
	var want := car_angle
	if speed > 6.0:
		want = lerp_angle(car_angle, car_vel.angle(), 0.45)
	if not inited:
		yaw = want
		inited = true
	yaw = lerp_angle(yaw, want, GM.damp(3.4, delta))
	boost_amount = lerpf(boost_amount, 1.0 if boosting else 0.0, GM.damp(4.0, delta))
	var d := dist + clampf(speed * 0.06, 0.0, 2.0)
	var fwd := Vector3(cos(yaw), 0.0, -sin(yaw))
	var focus := GM.to3(car_pos, ground + 1.1) + fwd * 2.6
	var cam_pos := focus - fwd * (d + 2.6) + Vector3(0.0, 3.5 + clampf(speed * 0.02, 0.0, 0.8), 0.0)
	cam_pos = _clear_of_buildings(GM.to3(car_pos, ground + 1.2), cam_pos)
	look_at_from_position(cam_pos, focus, Vector3.UP)

	trauma = maxf(0.0, trauma - delta * 0.9)
	fov_punch = maxf(0.0, fov_punch - delta * 14.0)
	var shake := trauma * trauma
	if shake > 0.0001:
		var t := time
		rotate_object_local(Vector3.RIGHT, shake * 0.05 * (sin(t * 47.0) * 0.6 + sin(t * 83.0 + 1.3) * 0.4))
		rotate_object_local(Vector3.UP, shake * 0.05 * (sin(t * 41.0 + 2.1) * 0.6 + sin(t * 71.0) * 0.4))
		rotate_object_local(Vector3.BACK, shake * 0.04 * sin(t * 53.0 + 0.7))
		global_position += global_transform.basis.x * shake * 0.18 * sin(t * 61.0) + global_transform.basis.y * shake * 0.18 * sin(t * 67.0 + 1.0)
	fov = 66.0 + clampf(speed * 0.28, 0.0, 9.0) + boost_amount * 7.0 + fov_punch


## Slide the camera toward the car until it is out of every building box.
func _clear_of_buildings(from: Vector3, to: Vector3) -> Vector3:
	if world == null:
		return to
	var p := to
	for i in 8:
		var inside := false
		var m := GM.from3(p)
		for b in world.boxes:
			if b["kind"] == "wreck" or b["kind"] == "prop":
				continue
			if m.x > b["x0"] - 0.4 and m.x < b["x1"] + 0.4 and m.y > b["y0"] - 0.4 and m.y < b["y1"] + 0.4 and p.y < 40.0:
				inside = true
				break
		if not inside:
			return p
		p = from.lerp(p, 0.8)
	return p

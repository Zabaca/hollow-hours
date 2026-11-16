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
var pull := 1.0  # how much of the way from the car to the wanted spot the camera is allowed


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
	cam_pos = _pull_in(GM.to3(car_pos, ground + 1.8), cam_pos, delta)
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


const PAD := 0.45  # the camera is a small ball: this far from any solid
const MIN_DIST := 1.4  # never closer to the car than this, however tight
const LIFT := 2.6  # extra height when squeezed, to look down over the car


## How high a collider stands (the sim's boxes are plan-view only).
static func box_height(kind: String) -> float:
	match kind:
		"wreck":
			return 2.4
		"prop":
			return 1.4
		"fence":
			return 1.9
	return 90.0


## Where along from -> to (0..1) a ball of radius `pad` first meets one of the world's boxes;
## 1.0 when the way is clear. A box the start is already inside is skipped.
static func clear_fraction(world: SimWorld, from: Vector3, to: Vector3, pad: float) -> float:
	var d := to - from
	var best := 1.0
	for b in world.boxes:
		var lo := Vector3(float(b["x0"]) - pad, -pad, -float(b["y1"]) - pad)
		var hi := Vector3(float(b["x1"]) + pad, box_height(String(b["kind"])) + pad, -float(b["y0"]) + pad)
		var tmin := 0.0
		var tmax := 1.0
		var miss := false
		for axis in 3:
			var o: float = from[axis]
			var dir: float = d[axis]
			if absf(dir) < 1e-9:
				if o < lo[axis] or o > hi[axis]:
					miss = true
					break
			else:
				var t1: float = (lo[axis] - o) / dir
				var t2: float = (hi[axis] - o) / dir
				if t1 > t2:
					var tmp := t1
					t1 = t2
					t2 = tmp
				tmin = maxf(tmin, t1)
				tmax = minf(tmax, t2)
				if tmin > tmax:
					miss = true
					break
		if miss or tmin <= 0.0:
			continue  # no hit, or the start is inside this box
		best = minf(best, tmin)
	return best


## Pull the wanted camera position in so it is never inside or behind a wall: quickly when a
## wall comes between, slowly back out when it clears. When squeezed it also rises a little.
func _pull_in(pivot: Vector3, wanted: Vector3, delta: float) -> Vector3:
	if world == null:
		return wanted
	var length := pivot.distance_to(wanted)
	var target := clampf(clear_fraction(world, pivot, wanted, PAD), MIN_DIST / maxf(length, 0.01), 1.0)
	if target < pull:
		pull = lerpf(pull, target, GM.damp(20.0, delta))
		# Fast, but never further out than the wall allows (the pad is the slack).
		pull = minf(pull, target + 0.3 / maxf(length, 0.01))
	else:
		pull = lerpf(pull, target, GM.damp(1.6, delta))
	var pos := pivot.lerp(wanted, pull)
	pos.y += (1.0 - pull) * LIFT
	return pos

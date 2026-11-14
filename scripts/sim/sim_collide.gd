class_name SimCollide
extends RefCounted
## The car's collisions, ported 1:1 from Roadkill's body.js keepInBox and world.js
## collideCarWithBox, circleVsBox and the tree branch of driveCar. Boxes are
## {"x0","y0","x1","y1"} dictionaries (axis aligned, map metres); the arena is
## {"left","right","bottom","top"}.

## Keep a body inside an axis-aligned box of immovable walls. Returns the hardest hit as
## {"impact": m/s into the wall (0 when none), "point": Vector2}.
static func keep_in_box(car: CarSim, box: Dictionary, bounce: float = 0.4) -> Dictionary:
	var body := car.body
	var hardest := {"impact": 0.0, "point": body.position}
	var walls := [
		[Vector2(1, 0), float(box["left"])],
		[Vector2(-1, 0), -float(box["right"])],
		[Vector2(0, 1), float(box["bottom"])],
		[Vector2(0, -1), -float(box["top"])],
	]
	# Repeat so a corner touching two walls settles against both.
	for _round in 3:
		for wall in walls:
			var normal: Vector2 = wall[0]
			var offset: float = wall[1]
			var contact := car.deepest(normal)
			var depth := offset - contact.dot(normal)
			if depth <= 0.0:
				continue
			body.position += normal * depth
			var point := contact + normal * depth
			var approach := body.velocity_at(point).dot(normal)
			if approach >= 0.0:
				continue
			var lever := (point - body.position).cross(normal)
			var restitution := bounce if approach < -0.5 else 0.0
			var magnitude := (-(1.0 + restitution) * approach) / (1.0 / body.mass + (lever * lever) / body.inertia)
			body.apply_impulse(normal * magnitude, point)
			if -approach > hardest["impact"]:
				hardest["impact"] = -approach
				hardest["point"] = point
	return hardest


## Push the car out of an axis-aligned box along the axis it overlaps least, of the box's two
## and the car's two (separating axes). Contact is the car's deepest point (a box face) or the
## box's deepest corner (a car face), the middle of a flush face. Returns the hardest hit as
## {"impact": m/s, "point": Vector2}.
static func car_vs_box(car: CarSim, box: Dictionary, bounce: float = 0.3) -> Dictionary:
	var body := car.body
	var hardest := {"impact": 0.0, "point": body.position}
	var x0: float = box["x0"]
	var y0: float = box["y0"]
	var x1: float = box["x1"]
	var y1: float = box["y1"]
	var box_corners := [Vector2(x0, y0), Vector2(x1, y0), Vector2(x0, y1), Vector2(x1, y1)]
	for _round in 2:
		var corners := car.corners()
		var forward := Vector2(1, 0).rotated(body.angle)
		var best := {}
		var axes := [
			[Vector2(1, 0), true],
			[Vector2(0, 1), true],
			[forward, false],
			[Vector2(-forward.y, forward.x), false],
		]
		for entry in axes:
			var axis: Vector2 = entry[0]
			var box_axis: bool = entry[1]
			var a_max := -INF
			var a_min := INF
			for p in corners:
				var d: float = p.dot(axis)
				a_max = maxf(a_max, d)
				a_min = minf(a_min, d)
			var b_max := -INF
			var b_min := INF
			for q in box_corners:
				var d2: float = q.dot(axis)
				b_max = maxf(b_max, d2)
				b_min = minf(b_min, d2)
			var below := a_max - b_min  # car pushed toward -axis
			var above := b_max - a_min  # car pushed toward +axis
			if below <= 0.0 or above <= 0.0:
				return hardest
			var depth := minf(below, above)
			if best.is_empty() or depth < float(best["depth"]):
				best = {"depth": depth, "normal": (-axis if below < above else axis), "box_axis": box_axis}
		var depth_b: float = best["depth"]
		var normal: Vector2 = best["normal"]
		var box_axis_b: bool = best["box_axis"]
		# Where they touch: the corners of each inside the other (edges included), else the
		# deepest point along the normal, the middle of a flush face.
		var eps := 1e-6
		var inside: Array = []
		for p in corners:
			if p.x >= x0 - eps and p.x <= x1 + eps and p.y >= y0 - eps and p.y <= y1 + eps:
				inside.append(p)
		for q in box_corners:
			var l := body.to_local(q)
			if absf(l.x) <= car.half_length + eps and absf(l.y) <= car.half_width + eps:
				inside.append(q)
		var point: Vector2
		if inside.size() > 0:
			point = _middle(inside)
		else:
			point = _extreme(corners if box_axis_b else box_corners, normal, box_axis_b)
		body.position += normal * depth_b
		var approach := body.velocity_at(point).dot(normal)
		if approach >= 0.0:
			continue
		var lever := (point - body.position).cross(normal)
		var j := (-(1.0 + bounce) * approach) / (1.0 / body.mass + (lever * lever) / body.inertia)
		body.apply_impulse(normal * j, point)
		if -approach > hardest["impact"]:
			hardest["impact"] = -approach
			hardest["point"] = point
	return hardest


static func _middle(points: Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in points:
		sum += p
	return sum / float(points.size())


static func _extreme(points: Array, normal: Vector2, use_min: bool) -> Vector2:
	var reach: Array = []
	var most := INF if use_min else -INF
	for p in points:
		var r: float = p.dot(normal)
		reach.append(r)
		most = minf(most, r) if use_min else maxf(most, r)
	var picked: Array = []
	for i in points.size():
		if absf(reach[i] - most) < 1e-6:
			picked.append(points[i])
	return _middle(picked)


## Closest point between a circle and the car's oriented box. Returns {} for no contact, else
## {"normal": from car to circle, "depth", "point"}.
static func circle_vs_car(car: CarSim, center: Vector2, radius: float) -> Dictionary:
	var body := car.body
	var local := body.to_local(center)
	var closest := Vector2(clampf(local.x, -car.half_length, car.half_length), clampf(local.y, -car.half_width, car.half_width))
	var d := local - closest
	var dist := d.length()
	var normal_local: Vector2
	var depth: float
	if dist > 1e-9:
		if dist >= radius:
			return {}
		normal_local = d / dist
		depth = radius - dist
	else:
		# Centre inside the box: leave by the nearest face.
		var dx := car.half_length - absf(local.x)
		var dy := car.half_width - absf(local.y)
		if dx < dy:
			normal_local = Vector2(signf(local.x) if local.x != 0.0 else 1.0, 0.0)
		else:
			normal_local = Vector2(0.0, signf(local.y) if local.y != 0.0 else 1.0)
		depth = minf(dx, dy) + radius
	return {"normal": normal_local.rotated(body.angle), "depth": depth, "point": body.to_world(closest)}


## A car against an immovable round post or tree: world.js's tree branch of driveCar.
## Returns the approach speed (m/s, 0 when none).
static func car_vs_circle(car: CarSim, center: Vector2, radius: float) -> Dictionary:
	var hit := circle_vs_car(car, center, radius)
	var none := {"impact": 0.0, "point": car.body.position}
	if hit.is_empty():
		return none
	var body := car.body
	var normal: Vector2 = hit["normal"]
	var depth: float = hit["depth"]
	body.position -= normal * depth
	var point: Vector2 = Vector2(hit["point"]) - normal * depth
	var speed := body.velocity_at(point).dot(normal)
	if speed <= 0.0:
		return none
	var arm := (point - body.position).cross(normal)
	var j := (1.35 * speed) / (1.0 / body.mass + (arm * arm) / body.inertia)
	body.apply_impulse(-normal * j, point)
	return {"impact": speed, "point": point}

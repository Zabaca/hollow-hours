class_name SimWorld
extends RefCounted
## The city as the simulation sees it: axis-aligned boxes (buildings, wrecks, props), round posts
## (lamps, trees, hydrants), the arena walls and the raised sidewalk blocks. Built from the
## generated CityLayout.DATA. Pure logic, no nodes, so the headless tests can run it.

var arena := {"left": -70.0, "right": 70.0, "bottom": -54.0, "top": 54.0}
var boxes: Array = []  # {x0,y0,x1,y1,kind}
var posts: Array = []  # {x,y,r,kind}
var blocks: Array = []  # {x0,y0,x1,y1}: raised sidewalk slabs
var lights: Array = []  # layout lights: {x,y,z,energy,range,kind,...}
var spawns: Array = []  # Vector2 hiding places for the creatures
var player_start := {"x": -30.0, "y": -2.5, "angle": 0.0}
## The way out of the quarter: a gap in the west wall at the avenue's end. `pos` is the middle of
## the gap on the wall line, `dir` points out of the quarter. Shut, the arena wall holds the car as
## everywhere else; open, the wall lets a car in the gap's width through (the story's escape moves
## it the rest of the way). The layout's own "gate" record ({x, y, width}) overrides the default.
var gate := {"pos": Vector2(-70.0, 0.0), "dir": Vector2(-1.0, 0.0), "width": 10.0, "open": false}


static func from_layout(data: Dictionary) -> SimWorld:
	var w := SimWorld.new()
	var a: Dictionary = data["arena"]
	w.arena = {"left": float(a["left"]), "right": float(a["right"]), "bottom": float(a["bottom"]), "top": float(a["top"])}
	for b in data["boxes"]:
		w.boxes.append({"x0": float(b["x0"]), "y0": float(b["y0"]), "x1": float(b["x1"]), "y1": float(b["y1"]), "kind": b["kind"]})
	for p in data["posts"]:
		w.posts.append({"x": float(p["x"]), "y": float(p["y"]), "r": float(p["r"]), "kind": p["kind"]})
	for b in data["blocks"]:
		w.blocks.append({"x0": float(b["x0"]), "y0": float(b["y0"]), "x1": float(b["x1"]), "y1": float(b["y1"])})
	for l in data["lights"]:
		w.lights.append(l)
	for s in data["creature_spawns"]:
		w.spawns.append(Vector2(float(s["x"]), float(s["y"])))
	var ps: Dictionary = data["player_start"]
	w.player_start = {"x": float(ps["x"]), "y": float(ps["y"]), "angle": float(ps["angle"])}
	if data.has("gate"):
		var g: Dictionary = data["gate"]
		w.gate["pos"] = Vector2(float(g["x"]), float(g["y"]))
		w.gate["width"] = float(g["width"])
	else:
		w.gate["pos"] = Vector2(w.arena["left"], 0.0)
	return w


## Height of the ground under a map point: the sidewalk blocks sit a little above the road.
func height_at(p: Vector2) -> float:
	for b in blocks:
		if p.x > b["x0"] and p.x < b["x1"] and p.y > b["y0"] and p.y < b["y1"]:
			return 0.12
	return 0.0


## The hardest hit this step as {"impact", "point", "kind"}: the car against the arena wall,
## posts and boxes, in the order world.js driveCar does it.
func collide_car(car: CarSim, min_impact: float = 6.0) -> Array:
	var hits: Array = []
	var box := arena
	if gate["open"] and absf(car.body.position.y - gate["pos"].y) <= float(gate["width"]) * 0.5 - car.hit_half_width:
		box = arena.duplicate()
		box["left"] = float(arena["left"]) - 60.0
	var wall := SimCollide.keep_in_box(car, box, 0.35)
	if wall["impact"] > min_impact:
		hits.append({"impact": wall["impact"], "point": wall["point"], "kind": "wall"})
	var at := car.body.position
	var r := Vector2(car.half_length, car.half_width).length() + 0.1
	for p in posts:
		if absf(p["x"] - at.x) > r + p["r"] or absf(p["y"] - at.y) > r + p["r"]:
			continue
		var hit := SimCollide.car_vs_circle(car, Vector2(p["x"], p["y"]), p["r"])
		if hit["impact"] > min_impact:
			hits.append({"impact": hit["impact"], "point": hit["point"], "kind": p["kind"]})
	for b in boxes:
		if b["x1"] < at.x - r or b["x0"] > at.x + r or b["y1"] < at.y - r or b["y0"] > at.y + r:
			continue
		var hb := SimCollide.car_vs_box(car, b, 0.3)
		if hb["impact"] > min_impact:
			hits.append({"impact": hb["impact"], "point": hb["point"], "kind": b["kind"]})
	return hits


## Push a circle out of walls, boxes and posts. Returns the corrected position; `normal_out`
## (a one-element array) receives the last push direction, zero when nothing touched.
func resolve_circle(pos: Vector2, radius: float, normal_out: Array = []) -> Vector2:
	var p := pos
	var last := Vector2.ZERO
	var left: float = arena["left"] + radius
	var right: float = arena["right"] - radius
	var bottom: float = arena["bottom"] + radius
	var top: float = arena["top"] - radius
	if p.x < left:
		p.x = left
		last = Vector2(1, 0)
	elif p.x > right:
		p.x = right
		last = Vector2(-1, 0)
	if p.y < bottom:
		p.y = bottom
		last = Vector2(0, 1)
	elif p.y > top:
		p.y = top
		last = Vector2(0, -1)
	for b in boxes:
		if p.x < b["x0"] - radius or p.x > b["x1"] + radius or p.y < b["y0"] - radius or p.y > b["y1"] + radius:
			continue
		var cx := clampf(p.x, b["x0"], b["x1"])
		var cy := clampf(p.y, b["y0"], b["y1"])
		var d := p - Vector2(cx, cy)
		var dist := d.length()
		if dist >= radius:
			continue
		if dist > 1e-6:
			var n := d / dist
			p += n * (radius - dist)
			last = n
		else:
			# Centre inside the box: leave by the nearest face.
			var dl: float = p.x - b["x0"]
			var dr: float = b["x1"] - p.x
			var db: float = p.y - b["y0"]
			var dt: float = b["y1"] - p.y
			var m := minf(minf(dl, dr), minf(db, dt))
			if m == dl:
				p.x = b["x0"] - radius
				last = Vector2(-1, 0)
			elif m == dr:
				p.x = b["x1"] + radius
				last = Vector2(1, 0)
			elif m == db:
				p.y = b["y0"] - radius
				last = Vector2(0, -1)
			else:
				p.y = b["y1"] + radius
				last = Vector2(0, 1)
	for q in posts:
		var dq := p - Vector2(q["x"], q["y"])
		var lim: float = q["r"] + radius
		var dl2 := dq.length()
		if dl2 < lim and dl2 > 1e-6:
			var nq := dq / dl2
			p += nq * (lim - dl2)
			last = nq
	if normal_out.size() > 0:
		normal_out[0] = last
	else:
		normal_out.append(last)
	return p


## True if the straight line between two map points is clear of buildings, wrecks and props.
func line_clear(a: Vector2, b: Vector2, pad: float = 0.0) -> bool:
	var d := b - a
	for box in boxes:
		# Slab test against the box grown by `pad`.
		var tmin := 0.0
		var tmax := 1.0
		var ok := true
		for axis in 2:
			var o: float = a.x if axis == 0 else a.y
			var dir: float = d.x if axis == 0 else d.y
			var lo: float = (box["x0"] if axis == 0 else box["y0"]) - pad
			var hi: float = (box["x1"] if axis == 0 else box["y1"]) + pad
			if absf(dir) < 1e-9:
				if o < lo or o > hi:
					ok = false
					break
			else:
				var t1 := (lo - o) / dir
				var t2 := (hi - o) / dir
				if t1 > t2:
					var tmp := t1
					t1 = t2
					t2 = tmp
				tmin = maxf(tmin, t1)
				tmax = minf(tmax, t2)
				if tmin > tmax:
					ok = false
					break
		if ok:
			return false
	return true


## True when a map point is lit: in a pool of one of the layout's lights (lamps, the gas station).
func is_lit(p: Vector2) -> bool:
	for l in lights:
		if l["kind"] != "omni":
			continue
		if float(l["energy"]) < 3.5:
			continue
		if p.distance_to(Vector2(float(l["x"]), float(l["y"]))) < 6.5:
			return true
	return false

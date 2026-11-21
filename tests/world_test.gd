extends Node
## Headless checks that the simulation looks only at what is near, so a bigger city costs no more per
## step, and that the near-only answers are the whole-city loops' answers:
##
##   godot --headless --path . res://tests/world_test.tscn
##
##  - SimWorld's bucketed queries (the car's collisions, pushing a creature out of walls, line of sight,
##    is a point lit, the ground's height, how far a wall is) and the camera's wall test give the same
##    answers as the loops over every box that they replaced (copied below as the reference), on the
##    quarter and on a synthetic larger city, a long thin one included;
##  - the path grid built from the obstacles has the same solid cells as testing every cell against every box;
##  - what a query and a step cost does not grow with the city (rough timings are printed);
##  - the pack follows the car: newcomers 60 to 120 m away, ahead, out of the light; stragglers dropped;
##  - LayoutCheck accepts the layouts and names what is wrong with a broken one; streets are read from the roads.
##
## Fixed seeds, no window.

const DT := 1.0 / 120.0

var failures := 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 21
	_test_layout_check()
	_test_streets()
	_test_autopilot_reads_the_city()
	_test_same_answers(CityLayout.DATA, "the quarter", 3000)
	_test_same_answers(SyntheticCity.grid(6, 6), "a city three times as wide and tall (6 by 6 blocks)", 1500)
	_test_same_answers(SyntheticCity.grid(20, 1, true), "a long thin city with a 1.2 km barrier", 1500)
	_test_nav_same_cells()
	_test_cost_does_not_grow()
	_test_pack_follows()
	_test_stragglers()
	_test_goal_leans_the_spawn()
	print("")
	print("world_test: %d failed" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, name: String, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL "), name, ("  " + detail) if detail != "" else "")
	if not ok:
		failures += 1


# ----------------------------------------------------------------------------- layouts and streets


func _test_layout_check() -> void:
	_check(LayoutCheck.problems(CityLayout.DATA).is_empty(), "the quarter's layout is the shape a city must have", str(LayoutCheck.problems(CityLayout.DATA)))
	_check(LayoutCheck.problems(SyntheticCity.grid(6, 6)).is_empty() and LayoutCheck.problems(SyntheticCity.grid(20, 1, true)).is_empty(), "and so are the synthetic cities", str(LayoutCheck.problems(SyntheticCity.grid(6, 6))) + str(LayoutCheck.problems(SyntheticCity.grid(20, 1, true))))
	var no_roads := SyntheticCity.grid(2, 2)
	no_roads.erase("roads")
	_check("no 'roads'" in LayoutCheck.problems(no_roads), "a layout without roads is named as such")
	var bad := SyntheticCity.grid(2, 2)
	bad["boxes"].append({"x0": 5.0, "y0": 0.0, "x1": 4.0, "y1": 1.0, "kind": "building"})
	bad["boxes"].append({"x0": 0.0, "y0": 0.0, "x1": 1.0, "y1": 1.0, "kind": "castle"})
	bad["roads"].append({"axis": "z", "c": 0.0, "width": 14.0, "from": 0.0, "to": 10.0})
	bad["creature_spawns"].append({"x": 9999.0, "y": 0.0})
	bad["gate"] = {"x": 3.0, "y": 0.0, "width": 8.0}
	var found := "\n".join(LayoutCheck.problems(bad))
	_check("has no area" in found and "castle" in found and "runs along 'z'" in found and "outside the arena" in found and "not on the arena's" in found, "a broken layout has each fault named", found.replace("\n", "; "))


func _test_streets() -> void:
	var w := SimWorld.from_layout(CityLayout.DATA)
	var st := w.street_stretch(StoryData.place_pos("pharmacy"))
	_check(not st.is_empty() and st["road"]["axis"] == "x" and is_equal_approx(float(st["lo"]), -70.0) and is_equal_approx(float(st["hi"]), -7.0) and st["lo_wall"] and not st["hi_wall"], "the street at the pharmacy is the avenue from the west wall to the central junction", str(st))
	_check(w.road_at(Vector2(-30.0, -30.0)).is_empty(), "a point in a block is on no street")
	var cross := w.street_stretch(Vector2(0.0, 30.0))
	_check(not cross.is_empty() and cross["road"]["axis"] == "y" and is_equal_approx(float(cross["lo"]), 7.0) and not cross["lo_wall"] and is_equal_approx(float(cross["hi"]), 54.0) and cross["hi_wall"], "a cross street runs from the avenue's edge to the wall (the street beyond is that end's corner)", str(cross))
	var junction := w.road_at(Vector2(0.0, 0.0))
	_check(not junction.is_empty() and float(junction["to"]) - float(junction["from"]) == 140.0, "at a junction the longer street answers")
	var big := SimWorld.from_layout(SyntheticCity.grid(6, 6))
	var mid := big.street_stretch(Vector2(-100.0, 0.0))
	_check(not mid.is_empty() and mid["road"]["axis"] == "x" and is_equal_approx(float(mid["lo"]), -121.0) and is_equal_approx(float(mid["hi"]), -71.0) and not mid["lo_wall"] and not mid["hi_wall"], "a street in a larger city runs between the near edges of the cross streets either side", str(mid))


func _test_autopilot_reads_the_city() -> void:
	var pilot := Autopilot.new()
	var w := SimWorld.from_layout(CityLayout.DATA)
	var st := pilot._street(w, StoryData.place_pos("pharmacy"))
	# These were once written into the autopilot as the avenue's coordinates: -66 to -10, turning at -60 and -26, y = 0.
	_check(st["axis"] == "x" and is_equal_approx(float(st["lo"]), -66.0) and is_equal_approx(float(st["hi"]), -10.0) and is_equal_approx(float(st["run_lo"]), -60.0) and is_equal_approx(float(st["run_hi"]), -26.0) and is_equal_approx(float(st["c"]), 0.0) and is_equal_approx(float(st["half"]), 7.0), "the kill step's run, read from the layout's roads, is the one that was written in as the avenue's coordinates", str(st))
	var big := SimWorld.from_layout(SyntheticCity.grid(6, 6))
	var other := pilot._street(big, Vector2(0.0, 70.0))  # on the north-south street through the middle of a larger city
	_check(not other.is_empty() and other["axis"] == "y" and is_equal_approx(float(other["c"]), 0.0) and float(other["run_hi"]) > float(other["run_lo"]), "and in a larger city it finds the street at any place", str(other))
	_check(pilot._street(w, Vector2(-30.0, -30.0)).is_empty(), "a place that is on no street has none")
	# In a city it has no hints for, the autopilot does not drive the quarter's route.
	var sim := GameSim.new(SyntheticCity.grid(3, 3), "bruiser", 2, false, "synthetic")
	var c := pilot.controls(sim, DT)
	_check(c["throttle"] == 0.0 and pilot.hints.is_empty(), "in a city it has no demo route for it sits still instead of driving another city's route", str(c))
	# And its notion of room to swerve follows the arena, not a fixed box.
	_check(pilot._inside_arena(big, Vector2(150.0, 100.0)) and not pilot._inside_arena(big, Vector2(196.0, 0.0)) and not pilot._inside_arena(w, Vector2(150.0, 0.0)), "its room to swerve follows the city's own arena")


# ----------------------------------------------------------------------------- the same answers


## The loops over every box that SimWorld's queries replaced, as they were.
class Ref:
	static func resolve(w: SimWorld, pos: Vector2, radius: float, normal_out: Array) -> Vector2:
		var p := pos
		var last := Vector2.ZERO
		var left: float = w.arena["left"] + radius
		var right: float = w.arena["right"] - radius
		var bottom: float = w.arena["bottom"] + radius
		var top: float = w.arena["top"] - radius
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
		for b in w.boxes:
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
		for q in w.posts:
			var dq := p - Vector2(q["x"], q["y"])
			var lim: float = q["r"] + radius
			var dl2 := dq.length()
			if dl2 < lim and dl2 > 1e-6:
				var nq := dq / dl2
				p += nq * (lim - dl2)
				last = nq
		normal_out.append(last)
		return p

	static func line_clear(w: SimWorld, a: Vector2, b: Vector2, pad: float) -> bool:
		var d := b - a
		for box in w.boxes:
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

	static func is_lit(w: SimWorld, p: Vector2) -> bool:
		for l in w.lights:
			if l["kind"] != "omni":
				continue
			if float(l["energy"]) < 3.5:
				continue
			if p.distance_to(Vector2(float(l["x"]), float(l["y"]))) < 6.5:
				return true
		return false

	static func height_at(w: SimWorld, p: Vector2) -> float:
		for b in w.blocks:
			if p.x > b["x0"] and p.x < b["x1"] and p.y > b["y0"] and p.y < b["y1"]:
				return 0.12
		return 0.0

	static func wall_gap(w: SimWorld, p: Vector2) -> float:
		var best := INF
		for b in w.boxes:
			var dx := maxf(maxf(float(b["x0"]) - p.x, 0.0), p.x - float(b["x1"]))
			var dy := maxf(maxf(float(b["y0"]) - p.y, 0.0), p.y - float(b["y1"]))
			best = minf(best, Vector2(dx, dy).length())
		return best

	static func collide_car(w: SimWorld, car: CarSim, min_impact: float) -> Array:
		var hits: Array = []
		var box := w.arena
		if w.gate["open"] and w.in_gap(car):
			box = w.arena.duplicate()
			box["left"] = float(w.arena["left"]) - 60.0
		var wall := SimCollide.keep_in_box(car, box, 0.35)
		if wall["impact"] > min_impact:
			hits.append({"impact": wall["impact"], "point": wall["point"], "kind": "wall"})
		var at := car.body.position
		var r := Vector2(car.half_length, car.half_width).length() + 0.1
		for p in w.posts:
			if absf(p["x"] - at.x) > r + p["r"] or absf(p["y"] - at.y) > r + p["r"]:
				continue
			var hit := SimCollide.car_vs_circle(car, Vector2(p["x"], p["y"]), p["r"])
			if hit["impact"] > min_impact:
				hits.append({"impact": hit["impact"], "point": hit["point"], "kind": p["kind"]})
		for b in w.boxes:
			if b["x1"] < at.x - r or b["x0"] > at.x + r or b["y1"] < at.y - r or b["y0"] > at.y + r:
				continue
			var hb := SimCollide.car_vs_box(car, b, 0.3)
			if hb["impact"] > min_impact:
				hits.append({"impact": hb["impact"], "point": hb["point"], "kind": b["kind"]})
		return hits

	## The camera's wall test as it was: every box copied, the perimeter added, every one tested.
	static func clear_fraction(w: SimWorld, from: Vector3, to: Vector3, pad: float) -> float:
		var d := to - from
		var best := 1.0
		var boxes: Array = w.boxes.duplicate()
		var a: Dictionary = w.arena
		var far := 400.0
		if w.gate["open"]:
			var g: Dictionary = w.gate
			var half := float(g["width"]) * 0.5
			boxes.append({"x0": -far, "y0": float(g["pos"].y) + half, "x1": a["left"], "y1": far, "kind": "perimeter"})
			boxes.append({"x0": -far, "y0": -far, "x1": a["left"], "y1": float(g["pos"].y) - half, "kind": "perimeter"})
		else:
			boxes.append({"x0": -far, "y0": -far, "x1": a["left"], "y1": far, "kind": "perimeter"})
		boxes.append({"x0": a["right"], "y0": -far, "x1": far, "y1": far, "kind": "perimeter"})
		boxes.append({"x0": -far, "y0": -far, "x1": far, "y1": a["bottom"], "kind": "perimeter"})
		boxes.append({"x0": -far, "y0": a["top"], "x1": far, "y1": far, "kind": "perimeter"})
		for b in boxes:
			var lo := Vector3(float(b["x0"]) - pad, -pad, -float(b["y1"]) - pad)
			var hi := Vector3(float(b["x1"]) + pad, ChaseCamera.box_height(String(b["kind"])) + pad, -float(b["y0"]) + pad)
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
				continue
			best = minf(best, tmin)
		return best


func _rand_in(a: Dictionary, margin: float = 0.0) -> Vector2:
	return Vector2(rng.randf_range(float(a["left"]) - margin, float(a["right"]) + margin), rng.randf_range(float(a["bottom"]) - margin, float(a["top"]) + margin))


## A car with a given pose, the same two times over.
func _cars(layout: Dictionary, pos: Vector2, angle: float, vel: Vector2, spin: float) -> Array:
	var out: Array = []
	for i in 2:
		var c := GameSim.new(layout).car
		c.body.position = pos
		c.body.angle = angle
		c.body.velocity = vel
		c.body.angular_velocity = spin
		out.append(c)
	return out


func _test_same_answers(layout: Dictionary, what: String, samples: int) -> void:
	var w := SimWorld.from_layout(layout)
	var a: Dictionary = w.arena
	# Pushing a circle out of walls, boxes and posts.
	var bad := 0
	var touched := 0
	var first := ""
	for i in samples:
		var p := _rand_in(a, 3.0)
		var r: float = [0.3, 0.55, 1.0][i % 3]
		var n_new := []
		var n_old := []
		var got := w.resolve_circle(p, r, n_new)
		var want := Ref.resolve(w, p, r, n_old)
		if got != want or n_new != n_old:
			bad += 1
			if first == "":
				first = "at %s r=%.2f: %s %s but the loops say %s %s" % [str(p), r, str(got), str(n_new), str(want), str(n_old)]
		if n_old[0] != Vector2.ZERO:
			touched += 1
	_check(bad == 0 and touched > 0, "%s: pushing a creature out of a wall gives the loops' answer (%d points, %d touching)" % [what, samples, touched], "differ=%d %s" % [bad, first])
	# Line of sight, with several pads, short and long.
	bad = 0
	var blocked := 0
	for i in samples:
		var p := _rand_in(a)
		var len_: float = [6.0, 25.0, 60.0, 160.0][i % 4]
		var q := p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.5, 1.0) * len_
		var pad: float = [0.0, 0.3, 0.6, 1.6, 2.0][i % 5]
		var got2 := w.line_clear(p, q, pad)
		if got2 != Ref.line_clear(w, p, q, pad):
			bad += 1
		if not got2:
			blocked += 1
	_check(bad == 0 and blocked > samples / 20 and blocked < samples * 19 / 20, "%s: line of sight gives the loops' answer (%d lines, %d blocked)" % [what, samples, blocked], "differ=%d" % bad)
	# Lit, ground height, distance to a wall.
	bad = 0
	var lit := 0
	var raised := 0
	for i in samples:
		var p := _rand_in(a, 2.0)
		var l := w.is_lit(p)
		if l != Ref.is_lit(w, p):
			bad += 1
		if l:
			lit += 1
		var h := w.height_at(p)
		if h != Ref.height_at(w, p):
			bad += 1
		if h > 0.0:
			raised += 1
		var gap := Ref.wall_gap(w, p)
		var got3 := w.wall_gap(p, 8.0)
		if not ((gap <= 8.0 and is_equal_approx(got3, gap)) or (gap > 8.0 and got3 == INF)):
			bad += 1
	_check(bad == 0 and lit > 0 and raised > 0, "%s: lit, ground height and distance to a wall give the loops' answers" % what, "differ=%d lit=%d raised=%d" % [bad, lit, raised])
	# The car's collisions: the same hits, and the same car afterwards.
	bad = 0
	var hit_count := 0
	for i in samples / 3:
		var pos := _rand_in(a)
		var angle := rng.randf() * TAU
		var vel := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 25.0)
		var cars := _cars(layout, pos, angle, vel, rng.randf_range(-1.0, 1.0))
		var min_impact: float = [GameSim.BUMP, GameSim.CRASH][i % 2]
		w.gate["open"] = (i % 7) == 0
		var got4 := w.collide_car(cars[0], min_impact)
		var want4 := Ref.collide_car(w, cars[1], min_impact)
		hit_count += want4.size()
		if got4 != want4 or cars[0].body.position != cars[1].body.position or cars[0].body.velocity != cars[1].body.velocity or cars[0].body.angle != cars[1].body.angle:
			bad += 1
	w.gate["open"] = false
	_check(bad == 0 and hit_count > 10, "%s: the car's collisions give the loops' hits and leave the car as they did (%d cars, %d hits)" % [what, samples / 3, hit_count], "differ=%d" % bad)
	# The camera.
	bad = 0
	var cut := 0
	for i in samples / 3:
		var p := _rand_in(a, 12.0)
		p.x = clampf(p.x, -350.0, 350.0)  # (the camera's old perimeter boxes reached only 400 m: they were wrong beyond that)
		var from := Vector3(p.x, rng.randf_range(0.5, 6.0), -p.y)
		var to := from + Vector3(rng.randf_range(-14.0, 14.0), rng.randf_range(-2.0, 4.0), rng.randf_range(-14.0, 14.0))
		w.gate["open"] = (i % 5) == 0
		var got5 := ChaseCamera.clear_fraction(w, from, to, 0.45)
		var want5 := Ref.clear_fraction(w, from, to, 0.45)
		if not is_equal_approx(got5, want5):
			bad += 1
		if want5 < 1.0:
			cut += 1
	w.gate["open"] = false
	_check(bad == 0 and cut > 0, "%s: the camera's wall test gives the loops' answer (%d views, %d pulled in)" % [what, samples / 3, cut], "differ=%d" % bad)


# ----------------------------------------------------------------------------- the path grid


## The grid as it was built: every cell tested against every box and post.
func _solid_cells_by_loops(world: SimWorld, clearance: float) -> Dictionary:
	var a: Dictionary = world.arena
	var origin := Vector2(a["left"], a["bottom"])
	var size := Vector2i(int(ceil((a["right"] - a["left"]) / NavGrid.CELL)), int(ceil((a["top"] - a["bottom"]) / NavGrid.CELL)))
	var solid := {}
	for ix in size.x:
		for iy in size.y:
			var c := origin + Vector2((ix + 0.5) * NavGrid.CELL, (iy + 0.5) * NavGrid.CELL)
			var blocked := false
			for b in world.boxes:
				if c.x > b["x0"] - clearance - NavGrid.CELL * 0.4 and c.x < b["x1"] + clearance + NavGrid.CELL * 0.4 and c.y > b["y0"] - clearance - NavGrid.CELL * 0.4 and c.y < b["y1"] + clearance + NavGrid.CELL * 0.4:
					blocked = true
					break
			if not blocked:
				for p in world.posts:
					if c.distance_to(Vector2(p["x"], p["y"])) < float(p["r"]) + clearance + NavGrid.CELL * 0.3:
						blocked = true
						break
			if blocked:
				solid[Vector2i(ix, iy)] = true
	return solid


func _test_nav_same_cells() -> void:
	for entry in [[CityLayout.DATA, "the quarter"], [SyntheticCity.grid(3, 3), "a 3 by 3 city"]]:
		var w := SimWorld.from_layout(entry[0])
		for clearance in [0.75, Autopilot.CAR_CLEARANCE]:
			var nav := NavGrid.new(w, clearance)
			var want := _solid_cells_by_loops(w, clearance)
			var bad := 0
			var solid := 0
			for ix in nav.size.x:
				for iy in nav.size.y:
					var is_solid := nav.astar.is_point_solid(Vector2i(ix, iy))
					if is_solid != want.has(Vector2i(ix, iy)):
						bad += 1
					if is_solid:
						solid += 1
			_check(bad == 0 and solid > 100, "%s: the path grid built from the obstacles has the loops' solid cells (clearance %.2f, %d solid of %d)" % [entry[1], clearance, solid, nav.size.x * nav.size.y], "differ=%d" % bad)


# ----------------------------------------------------------------------------- cost


func _micros(f: Callable, n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		f.call(i)
	return float(Time.get_ticks_usec() - t0) / float(n)


## Per-query cost on a city: the same fixed-size queries (a 40 m line, a creature's push, a lit test) at
## random places, so only the city's size changes.
func _query_costs(layout: Dictionary) -> Dictionary:
	var w := SimWorld.from_layout(layout)
	var a: Dictionary = w.arena
	var pts: Array = []
	var ends: Array = []
	for i in 400:
		var p := _rand_in(a)
		pts.append(p)
		ends.append(p + Vector2.from_angle(rng.randf() * TAU) * 40.0)
	var car := GameSim.new(layout).car
	var n := 1600
	return {
		"line": _micros(func(i: int) -> void: w.line_clear(pts[i % 400], ends[i % 400], 0.6), n),
		"push": _micros(func(i: int) -> void: w.resolve_circle(pts[i % 400], 0.6), n),
		"lit": _micros(func(i: int) -> void: w.is_lit(pts[i % 400]), n),
		"car": _micros(func(i: int) -> void:
			car.body.position = pts[i % 400]
			w.collide_car(car), n),
	}


func _step_cost(layout: Dictionary, seconds: float) -> float:
	var sim := GameSim.new(layout, "bruiser", 5)
	sim.pack.set_size(5)
	var t0 := Time.get_ticks_usec()
	var n := int(seconds / DT)
	for i in n:
		sim.step(DT, {"throttle": 0.6, "turn": 0.25 * sin(i * 0.002), "handbrake": false, "boost": false})
		sim.take_events()
	return float(Time.get_ticks_usec() - t0) / float(n)


func _test_cost_does_not_grow() -> void:
	var small := SyntheticCity.grid(2, 2)
	var big := SyntheticCity.grid(6, 6)
	var thin := SyntheticCity.grid(24, 1, true)
	var cs := _query_costs(small)
	var cb := _query_costs(big)
	var ct := _query_costs(thin)
	var worst := 0.0
	for k in cs:
		worst = maxf(worst, maxf(float(cb[k]) / float(cs[k]), float(ct[k]) / float(cs[k])))
	_check(worst < 3.0, "a query costs about the same in a city 9 times the area and in a 1.5 km one (the worst ratio to the quarter-sized city %.2f)" % worst, "per query in microseconds, small/big/thin: " + ", ".join(cs.keys().map(func(k: String) -> String: return "%s %.1f/%.1f/%.1f" % [k, cs[k], cb[k], ct[k]])))
	var t0 := Time.get_ticks_msec()
	var w_small := SimWorld.from_layout(small)
	var nav_small := NavGrid.new(w_small, Autopilot.CAR_CLEARANCE)
	var ms_small := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var w_big := SimWorld.from_layout(big)
	var nav_big := NavGrid.new(w_big, Autopilot.CAR_CLEARANCE)
	var ms_big := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var w_thin := SimWorld.from_layout(thin)
	var nav_thin := NavGrid.new(w_thin, Autopilot.CAR_CLEARANCE)
	var ms_thin := Time.get_ticks_msec() - t0
	_check(ms_big < 1500 and ms_thin < 1500, "the world and its path grid build fast (%d ms for the quarter-sized city, %d ms for 9 times the area, %d ms for the 1.5 km one: %d, %d and %d cells)" % [ms_small, ms_big, ms_thin, nav_small.size.x * nav_small.size.y, nav_big.size.x * nav_big.size.y, nav_thin.size.x * nav_thin.size.y])
	var ss := _step_cost(small, 20.0)
	var sb := _step_cost(big, 20.0)
	var st := _step_cost(thin, 20.0)
	_check(sb < ss * 2.0 and st < ss * 2.0, "a step with a full pack costs no more in the big cities (%.0f microseconds a step in the quarter-sized city, %.0f in 9 times the area, %.0f in the 1.5 km one)" % [ss, sb, st])
	_check(true, "timing, for the report: the quarter's own step is %.0f microseconds" % _step_cost(CityLayout.DATA, 20.0))


# ----------------------------------------------------------------------------- the pack follows


## A car that drives east along the long thin city at 14 m/s, moved by hand so only the pack is under test.
func _follow_run(seconds: float) -> Dictionary:
	var layout := SyntheticCity.grid(24, 1)
	var sim := GameSim.new(layout, "bruiser", 9)
	var a: Dictionary = sim.world.arena
	var y := (float(a["bottom"]) + float(a["top"])) * 0.5
	sim.car.body.position = Vector2(float(a["left"]) + 30.0, y)
	sim.car.body.angle = 0.0
	sim.pack.reset_pack(sim.car, 4, false)
	sim.pack.set_size(4)
	sim.pack.take_events()  # (the pack as placed at the start, and the game's own first three, are not newcomers)
	var spawned: Array = []  # [{pos, car, lit, in_cone}] at the moment each newcomer appeared
	var worst := 0.0
	for i in int(seconds / DT):
		sim.car.body.position += Vector2(14.0 * DT, 0.0)
		sim.car.body.velocity = Vector2(14.0, 0.0)
		sim.pack.step(DT, sim.car)
		for e in sim.pack.take_events():
			if e["type"] == "spawn":
				spawned.append({"pos": e["pos"], "car": sim.car.body.position, "lit": sim.world.is_lit(e["pos"]), "cone": sim.pack.in_cone(sim.car, e["pos"])})
		if i % 120 == 0 and i > 0:
			for g in sim.pack.gaunts:
				if g.alive():
					worst = maxf(worst, g.pos.distance_to(sim.car.body.position))
	return {"sim": sim, "spawned": spawned, "worst": worst}


func _test_pack_follows() -> void:
	var run := _follow_run(80.0)
	var sim: GameSim = run["sim"]
	var travelled: float = sim.car.body.position.x - (float(sim.world.arena["left"]) + 30.0)
	var spawned: Array = run["spawned"]
	var newcomers: Array = spawned
	var in_band := 0
	var ahead := 0
	var unlit := 0
	for s in newcomers:
		var d: float = (s["pos"] as Vector2).distance_to(s["car"])
		if d >= 57.0 and d <= 123.0:  # the hiding place is 60 to 120 m out, and jittered by up to 1.2 m each way
			in_band += 1
		if (s["pos"] as Vector2).x > (s["car"] as Vector2).x:
			ahead += 1
		if not s["lit"] and not s["cone"]:
			unlit += 1
	var n := newcomers.size()
	_check(travelled > 1000.0 and n >= 6, "a drive down the 1.5 km city: %.0f m in 80 s, %d creatures came in after the first four" % [travelled, n])
	_check(in_band == n, "the newcomers appear 60 to 120 m from the car", "%d of %d" % [in_band, n])
	_check(ahead == n, "and ahead of it", "%d of %d" % [ahead, n])
	_check(unlit == n, "out of its light and the lamps", "%d of %d" % [unlit, n])
	var far := 0.0
	var alive := 0
	for g in sim.pack.gaunts:
		if g.alive():
			alive += 1
			far = maxf(far, g.pos.distance_to(sim.car.body.position))
	_check(alive >= 3 and far <= 150.0 + 20.0 and float(run["worst"]) <= 150.0 + 20.0, "the pack is still there (three or four, one may be down and not yet replaced), all within about 150 m of the car after the drive (furthest now %.0f m, furthest at any second %.0f m)" % [far, float(run["worst"])])


func _test_stragglers() -> void:
	var sim := GameSim.new(SyntheticCity.grid(24, 1), "bruiser", 3)
	var a: Dictionary = sim.world.arena
	var y := (float(a["bottom"]) + float(a["top"])) * 0.5
	sim.car.body.position = Vector2(0.0, y)
	sim.car.body.velocity = Vector2(15.0, 0.0)
	sim.pack.gaunts.clear()
	sim.pack.set_size(4)
	var lurker_far := sim.pack.place_hunting(Vector2(-200.0, y), sim.car)  # a hunter far behind stays
	var lurker_near := sim.pack.place_hunting(Vector2(-100.0, y), sim.car)
	lurker_near.set_state(GauntSim.State.LURK)
	lurker_near.alert = false
	var left_behind := sim.pack.place_hunting(Vector2(-200.0, y + 3.0), sim.car)
	left_behind.set_state(GauntSim.State.LURK)
	left_behind.alert = false
	var ahead_far := sim.pack.place_hunting(Vector2(220.0, y), sim.car)  # far but ahead: stays
	ahead_far.set_state(GauntSim.State.LURK)
	ahead_far.alert = false
	sim.pack.step(DT, sim.car)
	var ids: Array = sim.pack.gaunts.map(func(g: GauntSim) -> int: return g.id)
	_check(left_behind.id not in ids, "a lurker left 200 m behind is dropped")
	_check(lurker_far.id in ids and lurker_near.id in ids and ahead_far.id in ids, "a hunter far behind, a lurker 100 m behind and one far ahead stay")
	var count := 0
	for g in sim.pack.gaunts:
		if g.alive():
			count += 1
	_check(count == 4, "and its replacement is placed at once, the pack never short", "alive=%d" % count)
	var newest: GauntSim = sim.pack.gaunts[-1]
	var d := newest.pos.distance_to(sim.car.body.position)
	_check(newest.pos.x > sim.car.body.position.x and d > 57.0 and d < 123.0, "ahead of the car, 60 to 120 m out", "%.0f m at x=%.0f" % [d, newest.pos.x])


func _test_goal_leans_the_spawn() -> void:
	var sim := GameSim.new(SyntheticCity.grid(6, 6), "bruiser", 4)
	sim.pack.gaunts.clear()
	sim.pack.goal = sim.car.body.position + Vector2(0.0, 300.0)  # due north, though the car faces east and sits still
	sim.car.body.angle = 0.0
	sim.car.body.velocity = Vector2.ZERO
	var heading := sim.pack.heading_of(sim.car)
	_check(heading.y > 0.4 and heading.x > 0.6, "a car that faces east with its goal due north is heading north-east", str(heading))
	var ok := 0
	for i in 30:
		var g := sim.pack.spawn_one(sim.car)
		var rel := g.pos - sim.car.body.position
		if rel.normalized().dot(heading) > 0.3 and rel.length() > 57.0 and rel.length() < 123.0:
			ok += 1
		sim.pack.gaunts.clear()
	_check(ok == 30, "so newcomers come in toward where it is going", "%d of 30" % ok)

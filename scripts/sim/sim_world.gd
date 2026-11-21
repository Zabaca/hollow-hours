class_name SimWorld
extends RefCounted
## A city as the simulation sees it: axis-aligned boxes (buildings, wrecks, props), round posts
## (lamps, trees, hydrants), the arena walls and the raised sidewalk blocks. Built from a city's
## layout dictionary (CityLayout.DATA for the quarter; Cities.layout(id) hands out each city's).
## Pure logic, no nodes, so the headless tests can run it.
##
## THE LAYOUT, the data a city must be in. tools/blender/city.py writes the quarter's as
## scripts/game/city_layout.gd; every city script writes the same shape and Cities registers it.
## LayoutCheck.problems(layout) lists what is wrong with one. All lengths are metres on the map's own
## plane (x east, y north), everything is axis aligned (the car's collisions, ported from Roadkill,
## need walls square to the map), and nothing assumes a size or a roughly square city: a long thin one
## (a 1.2 km highway) is as good as a block.
##
##   arena            {left, right, bottom, top}. The walled rectangle; the car is kept inside it.
##   boxes            [{x0, y0, x1, y1, kind}]  solid rectangles, x0 < x1 and y0 < y1. kind is one of
##                    building, wreck, prop, fence (what the camera and the map draw them as).
##   posts            [{x, y, r, kind}]  solid circles: lamps, trees, hydrants.
##   blocks           [{x0, y0, x1, y1}]  raised sidewalk slabs, a little above the road.
##   roads            [{axis, c, width, from, to}]  the streets. `axis` is "x" or "y", the direction the
##                    road runs along; `c` is its centre line on the other axis (a road along x at y = c);
##                    `from` and `to` bound it along its own axis. The map draws them and the autopilot
##                    finds the street at a place from them.
##   lights           [{x, y, z, color, energy, range, flicker, kind, ...}]  kind "omni" with energy
##                    3.5 or more lights the ground within 6.5 m for the creatures (is_lit).
##   lamps, wrecks    what the view draws (lamp posts, parked cars); the sim reads neither.
##   creature_spawns  [{x, y}]  the hiding places the pack's director picks from, inside the arena and
##                    clear of everything; a city wants them spread so the car always has some 60 to
##                    120 m away in the direction it is going.
##   fires            [{x, y}]  burning barrels (the view's light and flame).
##   ambush_spots     [{id, x, y, count, near}]  optional: where `count` creatures wait in the dark beside a roadblock, a
##                    squeeze or a bridge. The story arms the ones on a leg's route (effect `ambush`); an armed spot
##                    places its creatures, already hunting, when the car comes within the release distance.
##   bridges          [{id, kind, ..., closers: [{x0,y0,x1,y1}]}]  optional: a `lift` bridge's `closers` are boxes (also in
##                    `boxes`) that shut its road while it is raised; set_lift(true) takes them out, set_lift(false) puts them back.
##   stalled_hunters  [{x, y, release}]  optional: a creature waiting in a stalled car at (x, y), placed (already
##                    hunting) when the car comes within `release` metres. The story arms them (effect `stalled`).
##   player_start     {x, y, angle}  where Survive the Night begins.
##   gate             {x, y, width[, side]}  the way out: a gap in the wall, centred on an arena
##                    edge. `side` ("west", "east", "south", "north") is read from which edge it sits
##                    on when absent. Optional: a city with no way out has none.
##
## Questions are answered from buckets: the boxes, posts, lights and blocks are sorted into square
## cells of CELL metres once, and every query looks only at the cells it touches, so what a query
## costs depends on what is near, not on the size of the city. The answers are the same as looping
## over every box (tests/world_test.gd checks that on the quarter). The arrays below are kept public for
## the tests and the views; a change to them after from_layout needs reindex().

const CELL := 16.0
const LIT_RADIUS := 6.5
const LIT_ENERGY := 3.5
const GATE_REACH := 60.0  # how far past its wall an open gate lets a car in the gap's width go

var arena := {"left": -70.0, "right": 70.0, "bottom": -54.0, "top": 54.0}
var boxes: Array = []  # {x0,y0,x1,y1,kind}
var posts: Array = []  # {x,y,r,kind}
var blocks: Array = []  # {x0,y0,x1,y1}: raised sidewalk slabs
var roads: Array = []  # {axis,c,width,from,to}
var lights: Array = []  # layout lights: {x,y,z,energy,range,kind,...}
var spawns: Array = []  # Vector2 hiding places for the creatures
var ambush_spots: Array = []  # [{id, pos: Vector2, count}] (the layout's ambush_spots)
var lift_closers: Array = []  # [{x0,y0,x1,y1}] the lift bridge's colliders, in `boxes` while it is raised
var lift_down := false
var stalled: Array = []  # [{pos: Vector2, release: float}] creatures waiting in stalled cars (the layout's stalled_hunters)
var player_start := {"x": -30.0, "y": -2.5, "angle": 0.0}
## The way out: a gap in an arena wall (the quarter's is at the avenue's west end). `pos` is the middle
## of the gap on the wall line, `dir` points out of the city, `edge` names the arena side it is in
## ("left", "right", "bottom" or "top"). Shut, the arena wall holds the car as everywhere else; open,
## the wall lets a car in the gap's width through (the story's escape moves it the rest of the way).
## The layout's own "gate" record ({x, y, width}) overrides the default; `has_gate` is false when the
## layout has none.
var gate := {"pos": Vector2(-70.0, 0.0), "dir": Vector2(-1.0, 0.0), "edge": "left", "width": 10.0, "open": false}
var has_gate := true

var _origin := Vector2.ZERO
var _nx := 1
var _ny := 1
var _box_cells: Array = []  # per cell, the indices of the boxes touching it
var _post_cells: Array = []
var _block_cells: Array = []
var _lit_cells: Array = []  # per cell, indices into _lit
var _lit: Array = []  # Vector2: the lights that count for is_lit
var _box_seen := PackedInt32Array()
var _post_seen := PackedInt32Array()
var _stamp := 0
var _perimeter := {}


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
	for r in data.get("roads", []):
		w.roads.append({"axis": str(r["axis"]), "c": float(r["c"]), "width": float(r["width"]), "from": float(r["from"]), "to": float(r["to"])})
	for l in data["lights"]:
		w.lights.append(l)
	for s in data["creature_spawns"]:
		w.spawns.append(Vector2(float(s["x"]), float(s["y"])))
	for sp in data.get("ambush_spots", []):
		w.ambush_spots.append({"id": str(sp["id"]), "pos": Vector2(float(sp["x"]), float(sp["y"])), "count": int(sp["count"])})
	for br in data.get("bridges", []):
		if str(br.get("kind", "")) == "lift":
			for c in br.get("closers", []):
				w.lift_closers.append({"x0": float(c["x0"]), "y0": float(c["y0"]), "x1": float(c["x1"]), "y1": float(c["y1"])})
	for h in data.get("stalled_hunters", []):
		w.stalled.append({"pos": Vector2(float(h["x"]), float(h["y"])), "release": float(h["release"])})
	var ps: Dictionary = data["player_start"]
	w.player_start = {"x": float(ps["x"]), "y": float(ps["y"]), "angle": float(ps["angle"])}
	if data.has("gate"):
		var g: Dictionary = data["gate"]
		w._set_gate(Vector2(float(g["x"]), float(g["y"])), float(g["width"]), gate_side(data["arena"], g))
	else:
		w.has_gate = false
		w._set_gate(Vector2(w.arena["left"], 0.0), float(w.gate["width"]), "west")
	w.reindex()
	return w


## Which arena wall a gate record is in ("west", "east", "south" or "north"): the record's own `side`,
## else the edge its position is nearest to.
static func gate_side(arena_rec: Dictionary, rec: Dictionary) -> String:
	var side := str(rec.get("side", ""))
	if side != "":
		return side
	var x := float(rec["x"])
	var y := float(rec["y"])
	var best := absf(x - float(arena_rec["left"]))
	side = "west"
	for cand in [["east", absf(x - float(arena_rec["right"]))], ["south", absf(y - float(arena_rec["bottom"]))], ["north", absf(y - float(arena_rec["top"]))]]:
		if cand[1] < best:
			best = cand[1]
			side = cand[0]
	return side


func _set_gate(pos: Vector2, width: float, side: String) -> void:
	gate["pos"] = pos
	gate["width"] = width
	match side:
		"east":
			gate["dir"] = Vector2(1.0, 0.0)
			gate["edge"] = "right"
		"south":
			gate["dir"] = Vector2(0.0, -1.0)
			gate["edge"] = "bottom"
		"north":
			gate["dir"] = Vector2(0.0, 1.0)
			gate["edge"] = "top"
		_:
			gate["dir"] = Vector2(-1.0, 0.0)
			gate["edge"] = "left"


# ----------------------------------------------------------------------------- the buckets


## Lower the lift bridge (its closing colliders leave `boxes`) or raise it (they come back). False and nothing to do in a
## city without one. The caller rebuilds any path grid it holds (GameSim.set_bridge does).
func set_lift(down: bool) -> void:
	if down == lift_down or lift_closers.is_empty():
		return
	lift_down = down
	if down:
		var keep: Array = []
		for b in boxes:
			var is_closer := false
			for c in lift_closers:
				if is_equal_approx(b["x0"], c["x0"]) and is_equal_approx(b["y0"], c["y0"]) and is_equal_approx(b["x1"], c["x1"]) and is_equal_approx(b["y1"], c["y1"]):
					is_closer = true
			if not is_closer:
				keep.append(b)
		boxes = keep
	else:
		for c in lift_closers:
			boxes.append({"x0": c["x0"], "y0": c["y0"], "x1": c["x1"], "y1": c["y1"], "kind": "fence"})
	reindex()


## Sort the boxes, posts, lights and blocks into cells again. from_layout does it; call it after
## changing the arrays.
func reindex() -> void:
	_origin = Vector2(float(arena["left"]), float(arena["bottom"]))
	_nx = maxi(1, int(ceil((float(arena["right"]) - float(arena["left"])) / CELL)))
	_ny = maxi(1, int(ceil((float(arena["top"]) - float(arena["bottom"])) / CELL)))
	_box_cells = _empty_cells()
	_post_cells = _empty_cells()
	_block_cells = _empty_cells()
	_lit_cells = _empty_cells()
	_lit = []
	_perimeter = {}
	for i in boxes.size():
		var b: Dictionary = boxes[i]
		_put(_box_cells, i, b["x0"], b["y0"], b["x1"], b["y1"])
	for i in posts.size():
		var p: Dictionary = posts[i]
		_put(_post_cells, i, p["x"] - p["r"], p["y"] - p["r"], p["x"] + p["r"], p["y"] + p["r"])
	for i in blocks.size():
		var k: Dictionary = blocks[i]
		_put(_block_cells, i, k["x0"], k["y0"], k["x1"], k["y1"])
	for l in lights:
		if l["kind"] != "omni" or float(l["energy"]) < LIT_ENERGY:
			continue
		var at := Vector2(float(l["x"]), float(l["y"]))
		_put(_lit_cells, _lit.size(), at.x, at.y, at.x, at.y)
		_lit.append(at)
	_box_seen = PackedInt32Array()
	_box_seen.resize(boxes.size())
	_post_seen = PackedInt32Array()
	_post_seen.resize(posts.size())
	_stamp = 0


func _empty_cells() -> Array:
	var out: Array = []
	out.resize(_nx * _ny)
	for i in out.size():
		out[i] = PackedInt32Array()
	return out


func _cx(x: float) -> int:
	return clampi(int(floor((x - _origin.x) / CELL)), 0, _nx - 1)


func _cy(y: float) -> int:
	return clampi(int(floor((y - _origin.y) / CELL)), 0, _ny - 1)


func _put(cells: Array, index: int, x0: float, y0: float, x1: float, y1: float) -> void:
	for cy in range(_cy(y0), _cy(y1) + 1):
		for cx in range(_cx(x0), _cx(x1) + 1):
			var cell: PackedInt32Array = cells[cy * _nx + cx]
			cell.append(index)
			cells[cy * _nx + cx] = cell  # (a packed array is a value: store the grown one back)


## The boxes touching the cells a rectangle covers (each once), in index order, so a loop over them
## does what a loop over every box does, for the ones that matter.
func _boxes_in(x0: float, y0: float, x1: float, y1: float) -> PackedInt32Array:
	_stamp += 1
	var out := PackedInt32Array()
	for cy in range(_cy(y0), _cy(y1) + 1):
		for cx in range(_cx(x0), _cx(x1) + 1):
			for i in (_box_cells[cy * _nx + cx] as PackedInt32Array):
				if _box_seen[i] != _stamp:
					_box_seen[i] = _stamp
					out.append(i)
	out.sort()
	return out


func _posts_in(x0: float, y0: float, x1: float, y1: float) -> PackedInt32Array:
	_stamp += 1
	var out := PackedInt32Array()
	for cy in range(_cy(y0), _cy(y1) + 1):
		for cx in range(_cx(x0), _cx(x1) + 1):
			for i in (_post_cells[cy * _nx + cx] as PackedInt32Array):
				if _post_seen[i] != _stamp:
					_post_seen[i] = _stamp
					out.append(i)
	out.sort()
	return out


## `cands` (sorted indices) with the indices in `more` that come after `after` added, still sorted.
static func _merge_after(cands: PackedInt32Array, more: PackedInt32Array, after: int) -> PackedInt32Array:
	var out := cands
	for m in more:
		if m > after and not out.has(m):
			out.append(m)
	out.sort()
	return out


## Height of the ground under a map point: the sidewalk blocks sit a little above the road.
func height_at(p: Vector2) -> float:
	for i in (_block_cells[_cy(p.y) * _nx + _cx(p.x)] as PackedInt32Array):
		var b: Dictionary = blocks[i]
		if p.x > b["x0"] and p.x < b["x1"] and p.y > b["y0"] and p.y < b["y1"]:
			return 0.12
	return 0.0


# ----------------------------------------------------------------------------- the gate


## Is the car lined up with the gate's gap: its centre within the gap's width less its own half width.
func in_gap(car: CarSim) -> bool:
	var d: Vector2 = gate["dir"]
	var off := absf(car.body.position.y - gate["pos"].y) if absf(d.x) > 0.5 else absf(car.body.position.x - gate["pos"].x)
	return off <= float(gate["width"]) * 0.5 - car.hit_half_width


## The arena with the open gate's wall pushed back GATE_REACH metres (the gap's width only: the
## caller checks in_gap).
func _arena_through_gate() -> Dictionary:
	var box := arena.duplicate()
	var d: Vector2 = gate["dir"]
	box[gate["edge"]] = float(arena[gate["edge"]]) + (d.x + d.y) * GATE_REACH
	return box


## The perimeter wall as camera boxes just outside the arena, reaching `far` metres out, with the
## gate's gap cut in its wall when it is open. The wall is not one of the boxes.
func perimeter_boxes(far: float = 400.0) -> Array:
	var key := "%s%s" % [far, gate["open"] and has_gate]
	if _perimeter.has(key):
		return _perimeter[key]
	var a := arena
	var lo_x: float = float(a["left"]) - far
	var hi_x: float = float(a["right"]) + far
	var lo_y: float = float(a["bottom"]) - far
	var hi_y: float = float(a["top"]) + far
	var walls := {
		"left": {"x0": lo_x, "y0": lo_y, "x1": a["left"], "y1": hi_y, "kind": "perimeter"},
		"right": {"x0": a["right"], "y0": lo_y, "x1": hi_x, "y1": hi_y, "kind": "perimeter"},
		"bottom": {"x0": lo_x, "y0": lo_y, "x1": hi_x, "y1": a["bottom"], "kind": "perimeter"},
		"top": {"x0": lo_x, "y0": a["top"], "x1": hi_x, "y1": hi_y, "kind": "perimeter"},
	}
	var out: Array = []
	for edge in walls:
		var wall: Dictionary = walls[edge]
		if not (gate["open"] and has_gate and edge == gate["edge"]):
			out.append(wall)
			continue
		# The wall with the gap cut out of it: two pieces, either side of the gate's width.
		var half := float(gate["width"]) * 0.5
		var at: Vector2 = gate["pos"]
		if edge == "left" or edge == "right":
			out.append(wall.merged({"y1": at.y - half}, true))
			out.append(wall.merged({"y0": at.y + half}, true))
		else:
			out.append(wall.merged({"x1": at.x - half}, true))
			out.append(wall.merged({"x0": at.x + half}, true))
	_perimeter[key] = out
	return out


# ----------------------------------------------------------------------------- the questions


## The hardest hit this step as {"impact", "point", "kind"}: the car against the arena wall,
## posts and boxes, in the order world.js driveCar does it.
func collide_car(car: CarSim, min_impact: float = 6.0) -> Array:
	var hits: Array = []
	var box := arena
	if gate["open"] and has_gate and in_gap(car):
		box = _arena_through_gate()
	var wall := SimCollide.keep_in_box(car, box, 0.35)
	if wall["impact"] > min_impact:
		hits.append({"impact": wall["impact"], "point": wall["point"], "kind": "wall"})
	var at := car.body.position
	var r := Vector2(car.half_length, car.half_width).length() + 0.1
	for i in _posts_in(at.x - r, at.y - r, at.x + r, at.y + r):
		var p: Dictionary = posts[i]
		if absf(p["x"] - at.x) > r + p["r"] or absf(p["y"] - at.y) > r + p["r"]:
			continue
		var hit := SimCollide.car_vs_circle(car, Vector2(p["x"], p["y"]), p["r"])
		if hit["impact"] > min_impact:
			hits.append({"impact": hit["impact"], "point": hit["point"], "kind": p["kind"]})
	for i in _boxes_in(at.x - r, at.y - r, at.x + r, at.y + r):
		var b: Dictionary = boxes[i]
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
	# The circle meets only what is within `reach` of where it stands; a push moves it, so once it has moved
	# a couple of metres (or jumped out of the middle of a box) the cells round its new place are added,
	# for the boxes still to come in index order. That keeps the loops' answer exactly, as far as a push goes.
	var reach := radius + 3.0
	var centre := p
	var cands := _boxes_in(p.x - reach, p.y - reach, p.x + reach, p.y + reach)
	var j := 0
	while j < cands.size():
		var i := cands[j]
		j += 1
		var b: Dictionary = boxes[i]
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
		if p.distance_to(centre) > 2.0:
			centre = p
			cands = _merge_after(cands, _boxes_in(p.x - reach, p.y - reach, p.x + reach, p.y + reach), i)
	centre = p
	cands = _posts_in(p.x - reach, p.y - reach, p.x + reach, p.y + reach)
	j = 0
	while j < cands.size():
		var i := cands[j]
		j += 1
		var q: Dictionary = posts[i]
		var dq := p - Vector2(q["x"], q["y"])
		var lim: float = q["r"] + radius
		var dl2 := dq.length()
		if dl2 < lim and dl2 > 1e-6:
			var nq := dq / dl2
			p += nq * (lim - dl2)
			last = nq
			if p.distance_to(centre) > 2.0:
				centre = p
				cands = _merge_after(cands, _posts_in(p.x - reach, p.y - reach, p.x + reach, p.y + reach), i)
	if normal_out.size() > 0:
		normal_out[0] = last
	else:
		normal_out.append(last)
	return p


## Does the segment a to b, grown by `pad`, meet this box? (The slab test.)
static func _segment_meets(box: Dictionary, a: Vector2, d: Vector2, pad: float) -> bool:
	var tmin := 0.0
	var tmax := 1.0
	for axis in 2:
		var o: float = a.x if axis == 0 else a.y
		var dir: float = d.x if axis == 0 else d.y
		var lo: float = (box["x0"] if axis == 0 else box["y0"]) - pad
		var hi: float = (box["x1"] if axis == 0 else box["y1"]) + pad
		if absf(dir) < 1e-9:
			if o < lo or o > hi:
				return false
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
				return false
	return true


## True if the straight line between two map points is clear of buildings, wrecks and props.
## It walks the cells along the line (and `pad` either side of it), nearest the start first, and
## stops at the first thing in the way.
func line_clear(a: Vector2, b: Vector2, pad: float = 0.0) -> bool:
	var d := b - a
	var n := maxi(1, int(ceil(d.length() / (CELL * 0.5))))
	var half := pad + CELL * 0.25  # samples are at most CELL/2 apart, so no point of the line is further than CELL/4 from one
	_stamp += 1
	var last := Vector4i(-1, -1, -1, -1)
	for s in n + 1:
		var p := a + d * (float(s) / n)
		var range4 := Vector4i(_cx(p.x - half), _cy(p.y - half), _cx(p.x + half), _cy(p.y + half))
		if range4 == last:
			continue
		last = range4
		for cy in range(range4.y, range4.w + 1):
			for cx in range(range4.x, range4.z + 1):
				for i in (_box_cells[cy * _nx + cx] as PackedInt32Array):
					if _box_seen[i] == _stamp:
						continue
					_box_seen[i] = _stamp
					if _segment_meets(boxes[i], a, d, pad):
						return false
	return true


## The indices of the boxes a ball of radius `pad` sweeping from a to b could meet (a superset: the
## caller tests them exactly), each once. For the camera's wall test.
func boxes_along(a: Vector2, b: Vector2, pad: float) -> PackedInt32Array:
	var d := b - a
	var n := maxi(1, int(ceil(d.length() / (CELL * 0.5))))
	var half := pad + CELL * 0.25
	_stamp += 1
	var out := PackedInt32Array()
	var last := Vector4i(-1, -1, -1, -1)
	for s in n + 1:
		var p := a + d * (float(s) / n)
		var range4 := Vector4i(_cx(p.x - half), _cy(p.y - half), _cx(p.x + half), _cy(p.y + half))
		if range4 == last:
			continue
		last = range4
		for cy in range(range4.y, range4.w + 1):
			for cx in range(range4.x, range4.z + 1):
				for i in (_box_cells[cy * _nx + cx] as PackedInt32Array):
					if _box_seen[i] != _stamp:
						_box_seen[i] = _stamp
						out.append(i)
	return out


## How far a point is from the nearest building, wreck or prop (0 inside one): the distance when it is
## within `within` metres, else INF.
func wall_gap(p: Vector2, within: float = 8.0) -> float:
	var best := INF
	for i in _boxes_in(p.x - within, p.y - within, p.x + within, p.y + within):
		var b: Dictionary = boxes[i]
		var dx := maxf(maxf(float(b["x0"]) - p.x, 0.0), p.x - float(b["x1"]))
		var dy := maxf(maxf(float(b["y0"]) - p.y, 0.0), p.y - float(b["y1"]))
		best = minf(best, Vector2(dx, dy).length())
	return best if best <= within else INF


## True when a map point is lit: in a pool of one of the layout's lights (lamps, the gas station).
func is_lit(p: Vector2) -> bool:
	for cy in range(_cy(p.y - LIT_RADIUS), _cy(p.y + LIT_RADIUS) + 1):
		for cx in range(_cx(p.x - LIT_RADIUS), _cx(p.x + LIT_RADIUS) + 1):
			for i in (_lit_cells[cy * _nx + cx] as PackedInt32Array):
				if p.distance_to(_lit[i]) < LIT_RADIUS:
					return true
	return false


# ----------------------------------------------------------------------------- streets


## The road whose strip holds a map point, as its layout record, or {} when the point is on none. Where
## two cross (a junction) the one running along the longer stretch wins.
func road_at(p: Vector2) -> Dictionary:
	var best := {}
	var best_len := -1.0
	for r in roads:
		var along: float = p.x if r["axis"] == "x" else p.y
		var across: float = p.y if r["axis"] == "x" else p.x
		if along < r["from"] or along > r["to"] or absf(across - r["c"]) > r["width"] * 0.5:
			continue
		var length: float = r["to"] - r["from"]
		if length > best_len:
			best_len = length
			best = r
	return best


## The stretch of a road the point is on, between the walls or the cross streets either side of it:
## {road, lo, hi, lo_wall, hi_wall}: distances along the road's own axis, and whether each end is an
## arena wall (true) or the near edge of a cross street (false). A cross street within one road width
## of the road's end is that end's corner, not a junction, so the stretch runs on to the wall. {} when
## the point is on no road.
func street_stretch(p: Vector2) -> Dictionary:
	var road := road_at(p)
	if road.is_empty():
		return {}
	var here: float = p.x if road["axis"] == "x" else p.y
	var lo: float = road["from"]
	var hi: float = road["to"]
	var lo_wall := true
	var hi_wall := true
	var w: float = road["width"]
	for o in roads:
		if o["axis"] == road["axis"]:
			continue
		var at: float = o["c"]
		# It must cross this road, and stand clear of its ends.
		if at < road["from"] + w or at > road["to"] - w:
			continue
		if o["from"] > road["c"] + w * 0.5 or o["to"] < road["c"] - w * 0.5:
			continue
		var edge_lo: float = at - o["width"] * 0.5
		var edge_hi: float = at + o["width"] * 0.5
		if edge_hi <= here and edge_hi > lo:
			lo = edge_hi
			lo_wall = false
		elif edge_lo >= here and edge_lo < hi:
			hi = edge_lo
			hi_wall = false
	return {"road": road, "lo": lo, "hi": hi, "lo_wall": lo_wall, "hi_wall": hi_wall}

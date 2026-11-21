class_name LayoutCheck
extends RefCounted
## Is a city's layout the shape SimWorld, the map, the camera and the autopilot expect? The shape is
## written at the top of scripts/sim/sim_world.gd. problems() returns one sentence for each thing wrong
## with it, empty for a good one, so a city's generator (or its test) can assert the list is empty:
##
##   var bad := LayoutCheck.problems(MyCityLayout.DATA)
##   assert(bad.is_empty(), "\n".join(bad))

const BOX_KINDS := ["building", "wreck", "prop", "fence"]
const KEYS := ["arena", "boxes", "posts", "blocks", "roads", "lights", "creature_spawns", "fires", "player_start"]
const MIN_GATE_WIDTH := 6.0  # the car is 2.1 m wide and has to line up with the gap


static func problems(layout: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for k in KEYS:
		if not layout.has(k):
			out.append("no '%s'" % k)
	if not out.is_empty():
		return out
	var a: Dictionary = layout["arena"]
	for k in ["left", "right", "bottom", "top"]:
		if not a.has(k):
			out.append("the arena has no '%s'" % k)
	if not out.is_empty():
		return out
	if not (float(a["left"]) < float(a["right"]) and float(a["bottom"]) < float(a["top"])):
		out.append("the arena is empty (left < right and bottom < top)")
		return out
	var boxes: Array = layout["boxes"]
	for i in boxes.size():
		var b: Dictionary = boxes[i]
		if not (float(b["x0"]) < float(b["x1"]) and float(b["y0"]) < float(b["y1"])):
			out.append("box %d has no area (x0 < x1 and y0 < y1)" % i)
		if str(b["kind"]) not in BOX_KINDS:
			out.append("box %d is of kind '%s' (one of %s)" % [i, b["kind"], str(BOX_KINDS)])
	for i in layout["posts"].size():
		if float(layout["posts"][i]["r"]) <= 0.0:
			out.append("post %d has no radius" % i)
	for i in layout["blocks"].size():
		var k: Dictionary = layout["blocks"][i]
		if not (float(k["x0"]) < float(k["x1"]) and float(k["y0"]) < float(k["y1"])):
			out.append("block %d has no area" % i)
	for i in layout["roads"].size():
		var r: Dictionary = layout["roads"][i]
		if str(r["axis"]) not in ["x", "y"]:
			out.append("road %d runs along '%s' (x or y)" % [i, r["axis"]])
			continue
		if float(r["width"]) <= 0.0 or float(r["from"]) >= float(r["to"]):
			out.append("road %d has no width or no length (width > 0, from < to)" % i)
		# The centre line must be inside the arena across its axis, and the road inside along it.
		var lo: float = a["bottom"] if r["axis"] == "x" else a["left"]
		var hi: float = a["top"] if r["axis"] == "x" else a["right"]
		var end_lo: float = a["left"] if r["axis"] == "x" else a["bottom"]
		var end_hi: float = a["right"] if r["axis"] == "x" else a["top"]
		if float(r["c"]) < lo or float(r["c"]) > hi:
			out.append("road %d's centre line is outside the arena" % i)
		if float(r["from"]) < end_lo - 0.01 or float(r["to"]) > end_hi + 0.01:
			out.append("road %d runs outside the arena" % i)
	if layout["creature_spawns"].is_empty():
		out.append("no creature spawns")
	for i in layout["creature_spawns"].size():
		var s: Dictionary = layout["creature_spawns"][i]
		var at := Vector2(float(s["x"]), float(s["y"]))
		if not _in(a, at):
			out.append("creature spawn %d is outside the arena" % i)
		elif _in_a_box(boxes, at):
			out.append("creature spawn %d is inside a box" % i)
	var ps: Dictionary = layout["player_start"]
	var start := Vector2(float(ps["x"]), float(ps["y"]))
	if not _in(a, start) or _in_a_box(boxes, start):
		out.append("player_start is outside the arena or inside a box")
	if layout.has("gate"):
		var g: Dictionary = layout["gate"]
		var side := SimWorld.gate_side(a, g)
		var edges := {"west": a["left"], "east": a["right"], "south": a["bottom"], "north": a["top"]}
		if not edges.has(side):
			out.append("the gate's side '%s' is not west, east, south or north" % side)
		else:
			var off := absf(float(g["x"]) - float(edges[side])) if side in ["west", "east"] else absf(float(g["y"]) - float(edges[side]))
			if off > 0.5:
				out.append("the gate is not on the arena's %s edge" % side)
		if float(g["width"]) < MIN_GATE_WIDTH:
			out.append("the gate is %.1f m wide (at least %.1f for the car to line up)" % [float(g["width"]), MIN_GATE_WIDTH])
	return out


static func _in(a: Dictionary, p: Vector2) -> bool:
	return p.x >= float(a["left"]) and p.x <= float(a["right"]) and p.y >= float(a["bottom"]) and p.y <= float(a["top"])


static func _in_a_box(boxes: Array, p: Vector2) -> bool:
	for b in boxes:
		if p.x > float(b["x0"]) and p.x < float(b["x1"]) and p.y > float(b["y0"]) and p.y < float(b["y1"]):
			return true
	return false

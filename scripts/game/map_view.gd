class_name MapView
extends Control
## A city drawn from its layout, at two sizes. RADAR is the round, car-up one in the corner
## (about 120 m across): the buildings and wrecks, the car at the centre, the objective as an amber
## blip pinned to the rim with its distance when it is further than the edge, a mission start as a
## teal blip. FULL is the whole city north-up with the places named. No Gaunts on either: seeing
## them would undo the stalking.

enum Mode { RADAR, FULL }

const AMBER := Color(1.0, 0.68, 0.2)
const TEAL := Color(0.22, 0.88, 0.82)
const BUILDING := Color(0.3, 0.33, 0.37)
const WRECK := Color(0.3, 0.22, 0.21)
const ROAD := Color(0.085, 0.09, 0.1)
const RADAR_RANGE := 60.0  # metres from the centre to the rim, crawling
const RADAR_RANGE_FAST := 110.0  # and flat out, in a city that widens it (Cities.route_grid is not empty)
const RADAR_FAST_SPEED := 40.0  # m/s at which it is as wide as it gets
const RIM_STEPS := 40
const TERRAIN_SIZE := 120.0  # a box this long on either side is the ground a long road is cut through: the full map leaves it out

var mode: int = Mode.RADAR
var car_pos := Vector2.ZERO
var car_angle := 0.0
var blips: Array = []  # [{kind: objective|start, pos}]
var route := PackedVector2Array()  # the way to the objective, as a polyline in map metres (empty: none)
var radar_range := RADAR_RANGE
var city := Cities.QUARTER
var data: Dictionary = Cities.layout(Cities.QUARTER)  # the city's layout: its arena, roads, boxes and gate
var _rim := PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in RIM_STEPS:
		_rim.append(Vector2.from_angle(TAU * i / RIM_STEPS))


## Draw another city: its layout, and the places the story keeps in it.
func set_city(id: String) -> void:
	city = id
	data = Cities.layout(id)
	queue_redraw()


func set_state(pos: Vector2, angle: float, new_blips: Array, speed: float = 0.0, new_route: PackedVector2Array = PackedVector2Array()) -> void:
	car_pos = pos
	car_angle = angle
	blips = new_blips
	route = new_route
	# The radar reaches further the faster the car goes (in the cities that show routes): a driver at 140 km/h needs to see
	# the next turn sooner. It eases toward its range rather than snapping to it.
	var want := RADAR_RANGE
	if not Cities.route_grid(city).is_empty():
		want = lerpf(RADAR_RANGE, RADAR_RANGE_FAST, clampf((speed - 4.0) / (RADAR_FAST_SPEED - 4.0), 0.0, 1.0))
	radar_range = lerpf(radar_range, want, 0.06)
	queue_redraw()


# ----------------------------------------------------------------------------- projection

## The part of the arena the full map shows: the layout's `map_frame` when it has one (the harbour city's
## frames the city and the highway's first stretch, not the whole 1.6 km), else the arena.
func _frame() -> Dictionary:
	return data.get("map_frame", data["arena"])


func _scale() -> float:
	if mode == Mode.RADAR:
		return minf(size.x, size.y) * 0.5 / radar_range
	var a: Dictionary = _frame()
	return minf(size.x / (float(a["right"]) - float(a["left"])), size.y / (float(a["top"]) - float(a["bottom"])))


## Map metres to a point in this control.
func to_screen(p: Vector2) -> Vector2:
	var k := _scale()
	if mode == Mode.RADAR:
		var d := p - car_pos
		var h := Vector2.from_angle(car_angle)
		var right := Vector2(h.y, -h.x)
		return size * 0.5 + Vector2(d.dot(right), -d.dot(h)) * k
	var a: Dictionary = _frame()
	var w := (float(a["right"]) - float(a["left"])) * k
	var ht := (float(a["top"]) - float(a["bottom"])) * k
	var origin := (size - Vector2(w, ht)) * 0.5
	return origin + Vector2(p.x - float(a["left"]), float(a["top"]) - p.y) * k


# ----------------------------------------------------------------------------- drawing

func _draw() -> void:
	if mode == Mode.RADAR:
		_draw_radar()
	else:
		_draw_full()


func _box_poly(b: Dictionary) -> PackedVector2Array:
	return PackedVector2Array([
		to_screen(Vector2(b["x0"], b["y0"])), to_screen(Vector2(b["x1"], b["y0"])),
		to_screen(Vector2(b["x1"], b["y1"])), to_screen(Vector2(b["x0"], b["y1"])),
	])


## The roads as rectangles in map metres, cut to the arena.
func _road_boxes() -> Array:
	var a: Dictionary = data["arena"]
	var out: Array = []
	for r in data.get("roads", []):
		var half: float = float(r["width"]) * 0.5
		var c: float = r["c"]
		if r["axis"] == "x":
			out.append({"x0": maxf(r["from"], a["left"]), "y0": maxf(c - half, a["bottom"]), "x1": minf(r["to"], a["right"]), "y1": minf(c + half, a["top"])})
		else:
			out.append({"x0": maxf(c - half, a["left"]), "y0": maxf(r["from"], a["bottom"]), "x1": minf(c + half, a["right"]), "y1": minf(r["to"], a["top"])})
	return out


func _draw_radar() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	draw_circle(c, r, Color(0.0, 0.0, 0.0, 0.58))
	var circle := PackedVector2Array()
	for p in _rim:
		circle.append(c + p * (r - 1.0))
	for rd in _road_boxes():
		var rp := _clip(_box_poly(rd), circle)
		if _area(rp) > 1.0:
			draw_colored_polygon(rp, ROAD)
	for b in data["boxes"]:
		var kind: String = b["kind"]
		if kind != "building" and kind != "wreck":
			continue
		if absf(float(b["x0"] + b["x1"]) * 0.5 - car_pos.x) > radar_range * 1.6 or absf(float(b["y0"] + b["y1"]) * 0.5 - car_pos.y) > radar_range * 1.6:
			continue
		var poly := _clip(_box_poly(b), circle)
		if _area(poly) > 1.0:
			draw_colored_polygon(poly, Color(BUILDING, 0.72) if kind == "building" else Color(WRECK, 0.85))
	_draw_route(c, r - 2.0)
	draw_arc(c, r - 1.0, 0.0, TAU, 64, Color(MenuStyle.BONE, 0.42), 2.0, true)
	# North, so a turning car still knows where it is.
	var north := to_screen(car_pos + Vector2(0.0, 1.0)) - c
	var nd := north.normalized() if north.length() > 0.01 else Vector2.UP
	draw_string(MenuStyle.font(600, 2), c + nd * (r - 17.0) - Vector2(5.0, -5.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(MenuStyle.BONE, 0.55))
	for bl in blips:
		_draw_radar_blip(c, r, bl)
	var car := PackedVector2Array([c + Vector2(0.0, -8.0), c + Vector2(5.5, 6.0), c + Vector2(0.0, 3.0), c + Vector2(-5.5, 6.0)])
	draw_colored_polygon(car, MenuStyle.BONE)


## The route to the objective, a faint amber line along the streets. On the radar (`radius` > 0) each segment is cut
## to the circle; on the full map the view's own clip does it.
func _draw_route(centre: Vector2, radius: float) -> void:
	if route.size() < 2:
		return
	var col := Color(AMBER, 0.62)
	for k in range(1, route.size()):
		var a := to_screen(route[k - 1])
		var b := to_screen(route[k])
		if radius > 0.0:
			var seg := _segment_in_circle(a, b, centre, radius)
			if seg.is_empty():
				continue
			a = seg[0]
			b = seg[1]
		draw_line(a, b, col, 2.5 if radius <= 0.0 else 2.0, true)


## The part of segment a-b inside the circle, as [from, to], or [] when none of it is.
func _segment_in_circle(a: Vector2, b: Vector2, centre: Vector2, radius: float) -> Array:
	var d := b - a
	var f := a - centre
	var qa := d.dot(d)
	if qa < 0.000001:
		return [a, b] if f.length() <= radius else []
	var qb := 2.0 * f.dot(d)
	var qc := f.dot(f) - radius * radius
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return []
	var root := sqrt(disc)
	var t0 := clampf((-qb - root) / (2.0 * qa), 0.0, 1.0)
	var t1 := clampf((-qb + root) / (2.0 * qa), 0.0, 1.0)
	if t1 <= t0:
		return []
	return [a + d * t0, a + d * t1]


func _draw_radar_blip(c: Vector2, r: float, bl: Dictionary) -> void:
	var col: Color = TEAL if bl["kind"] == "start" else AMBER
	var at := to_screen(bl["pos"])
	var off := at - c
	if off.length() <= r - 9.0:
		draw_circle(at, 7.0, Color(col, 0.28))
		draw_arc(at, 7.0, 0.0, TAU, 20, col, 2.0, true)
		draw_circle(at, 2.5, col)
		return
	var dir := off.normalized()
	var tip := c + dir * (r - 3.0)
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * 12.0 + side * 6.5, tip - dir * 12.0 - side * 6.5]), col)
	var metres := int(roundf(car_pos.distance_to(bl["pos"])))
	var label_at := c + dir * (r - 30.0)
	draw_string(MenuStyle.font(600, 1), label_at + Vector2(-16.0, 5.0), "%d m" % metres, HORIZONTAL_ALIGNMENT_CENTER, 32.0, 13, Color(col, 0.95))


func _draw_full() -> void:
	var a: Dictionary = _frame()
	var tl := to_screen(Vector2(a["left"], a["top"]))
	var br := to_screen(Vector2(a["right"], a["bottom"]))
	var rect := Rect2(tl, br - tl)
	draw_rect(rect, Color(0.03, 0.033, 0.038, 1.0))
	for rd in _road_boxes():
		draw_colored_polygon(_box_poly(rd), ROAD)
	draw_rect(rect, Color(MenuStyle.BONE, 0.28), false, 2.0)
	# The gap in the wall where the gate is, from the layout's gate record.
	if data.has("gate"):
		var gr: Dictionary = data["gate"]
		var gw: float = float(gr["width"])
		var side := SimWorld.gate_side(a, gr)
		var along := Vector2(0.0, 1.0) if side in ["west", "east"] else Vector2(1.0, 0.0)  # the wall's direction on the map
		var gpos := Vector2(float(gr["x"]), float(gr["y"]))
		var g0 := to_screen(gpos - along * gw * 0.5)
		var g1 := to_screen(gpos + along * gw * 0.5)
		var tick := Vector2(7.0, 0.0) if side in ["west", "east"] else Vector2(0.0, 7.0)  # across it, on the screen
		draw_line(g0, g1, Color(0.03, 0.033, 0.038, 1.0), 4.0)
		draw_line(g0 - tick, g0 + tick, Color(MenuStyle.BONE, 0.5), 2.0)
		draw_line(g1 - tick, g1 + tick, Color(MenuStyle.BONE, 0.5), 2.0)
	for b in data["boxes"]:
		if float(b["x0"]) > float(a["right"]) or float(b["x1"]) < float(a["left"]):
			continue
		if float(b["x1"]) - float(b["x0"]) > TERRAIN_SIZE or float(b["y1"]) - float(b["y0"]) > TERRAIN_SIZE:
			continue  # solid ground beside a highway, not a building
		var kind: String = b["kind"]
		if kind == "building":
			draw_colored_polygon(_box_poly(b), Color(BUILDING, 0.8))
		elif kind == "wreck":
			draw_colored_polygon(_box_poly(b), Color(WRECK, 0.9))
		elif kind == "fence":
			var p := _box_poly(b)  # corners: (x0,y0) (x1,y0) (x1,y1) (x0,y1)
			var thin_in_x: bool = absf(float(b["x1"]) - float(b["x0"])) < absf(float(b["y1"]) - float(b["y0"]))
			var from: Vector2 = (p[0] + p[1]) * 0.5 if thin_in_x else (p[0] + p[3]) * 0.5
			var to: Vector2 = (p[3] + p[2]) * 0.5 if thin_in_x else (p[1] + p[2]) * 0.5
			draw_line(from, to, Color(MenuStyle.DIM, 0.5), 1.5)
	_draw_route(Vector2.ZERO, 0.0)
	var named := {}
	for bl in blips:
		named[bl["place"]] = TEAL if bl["kind"] == "start" else AMBER
	for id in StoryData.PLACES:
		var pl: Dictionary = StoryData.PLACES[id]
		if pl["label"] == "" or pl["city"] != city:
			continue
		if float(pl["pos"].x) > float(a["right"]):
			continue  # on the highway, off the framed part
		var at := to_screen(pl["pos"])
		var col: Color = named.get(id, MenuStyle.DIM)
		var f := MenuStyle.font(600, 3)
		var txt := String(pl["label"]).to_upper()
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15).x
		var lx := at.x - w * 0.5
		var ly := at.y + 5.0
		if id == "west_gate":
			lx = at.x - w - 12.0
		elif pl["marker"]:
			ly += 22.0  # below the spot, so its blip and the car do not sit on the name
		if id == "lift_gate":
			lx = at.x + 12.0  # the far bank's gate is on the left edge: its name goes inside
		if ly > br.y - 6.0:
			ly = at.y - 12.0  # a place on the bottom road: its name above it, not under the frame's edge
		if id == "lift_gate":
			ly = at.y - 42.0  # and above the control house's name, which is a little to its right
		draw_string(f, Vector2(lx, ly), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, col if named.has(id) else Color(MenuStyle.BONE, 0.7))
	for bl in blips:
		var col: Color = TEAL if bl["kind"] == "start" else AMBER
		var at := to_screen(bl["pos"])
		at = Vector2(clampf(at.x, tl.x + 12.0, br.x - 12.0), clampf(at.y, tl.y + 12.0, br.y - 12.0))
		draw_circle(at, 11.0, Color(col, 0.22))
		draw_arc(at, 11.0, 0.0, TAU, 24, col, 2.0, true)
		draw_circle(at, 3.0, col)
	var me := to_screen(car_pos)
	var away := not Rect2(tl, br - tl).has_point(me)
	if away:
		# Out along the highway, off the framed part: pinned to the frame's edge, with how far it is.
		me = Vector2(clampf(me.x, tl.x + 14.0, br.x - 14.0), clampf(me.y, tl.y + 14.0, br.y - 14.0))
		draw_string(MenuStyle.font(600, 1), me + Vector2(-166.0, -16.0), "%d m OUT" % int(roundf(car_pos.x - float(a["right"]))), HORIZONTAL_ALIGNMENT_RIGHT, 150.0, 13, Color(MenuStyle.BONE, 0.9))
	var h := Vector2.from_angle(car_angle)
	var fwd := Vector2(h.x, -h.y)
	var side := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([me + fwd * 11.0, me - fwd * 8.0 + side * 7.0, me - fwd * 4.0, me - fwd * 8.0 - side * 7.0]), MenuStyle.BONE)


## The area of a polygon (a clipped sliver can have none, and the canvas refuses to fill it).
func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


## Sutherland-Hodgman: the part of `poly` inside the convex polygon `clip`.
func _clip(poly: PackedVector2Array, clip: PackedVector2Array) -> PackedVector2Array:
	var out := poly
	var n := clip.size()
	for i in n:
		if out.is_empty():
			break
		var a := clip[i]
		var b := clip[(i + 1) % n]
		var input := out
		out = PackedVector2Array()
		var prev := input[input.size() - 1]
		for cur in input:
			var in_cur := _side(a, b, cur) >= 0.0
			var in_prev := _side(a, b, prev) >= 0.0
			if in_cur:
				if not in_prev:
					out.append(_cross(a, b, prev, cur))
				out.append(cur)
			elif in_prev:
				out.append(_cross(a, b, prev, cur))
			prev = cur
	return out


func _side(a: Vector2, b: Vector2, p: Vector2) -> float:
	return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)


func _cross(a: Vector2, b: Vector2, p: Vector2, q: Vector2) -> Vector2:
	var d1 := _side(a, b, p)
	var d2 := _side(a, b, q)
	return p + (q - p) * (d1 / (d1 - d2))

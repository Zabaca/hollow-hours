class_name SyntheticCity
extends RefCounted
## Layouts for the tests that need a city other than the quarter: the same shape as CityLayout.DATA (see the top of
## scripts/sim/sim_world.gd), built from a street plan like the quarter's, at any size. Uses nothing but plain data, so
## tests/cost_probe.gd can run it against an older checkout.


## A city built like the quarter's street plan: roads every 64 m east to west and every 48 m north to south. `cols` by `rows` blocks of
## 50 by 34 m between 14 m streets, four buildings, a wreck, props, lamps and two hiding places in each, the
## arena 6 m beyond the outer roads (cols = rows = 2 is the quarter's size), the gate in the west wall.
## `barrier` adds one 1.2 km box along the middle (a highway's concrete barrier).
static func grid(cols: int, rows: int, barrier: bool = false) -> Dictionary:
	var xs: Array = []
	for k in cols + 1:
		xs.append((k - cols / 2.0) * 64.0)
	var ys: Array = []
	for k in rows + 1:
		ys.append((k - rows / 2.0) * 48.0)
	var arena := {"left": xs[0] - 6.0, "right": xs[-1] + 6.0, "bottom": ys[0] - 6.0, "top": ys[-1] + 6.0}
	var boxes: Array = []
	var posts: Array = []
	var blocks: Array = []
	var lights: Array = []
	var spawns: Array = []
	var roads: Array = []
	for x in xs:
		roads.append({"axis": "y", "c": x, "width": 14.0, "from": arena["bottom"], "to": arena["top"]})
	for y in ys:
		roads.append({"axis": "x", "c": y, "width": 14.0, "from": arena["left"], "to": arena["right"]})
	for i in cols:
		for j in rows:
			var x0: float = xs[i] + 7.0
			var x1: float = xs[i + 1] - 7.0
			var y0: float = ys[j] + 7.0
			var y1: float = ys[j + 1] - 7.0
			blocks.append({"x0": x0 - 3.0, "y0": y0 - 3.0, "x1": x1 + 3.0, "y1": y1 + 3.0})
			var mx := (x0 + x1) * 0.5
			var my := (y0 + y1) * 0.5
			boxes.append({"x0": x0, "y0": y0, "x1": mx - 1.5, "y1": my - 1.5, "kind": "building"})
			boxes.append({"x0": mx + 1.5, "y0": y0, "x1": x1, "y1": my - 1.5, "kind": "building"})
			boxes.append({"x0": x0, "y0": my + 1.5, "x1": mx - 1.5, "y1": y1, "kind": "building"})
			boxes.append({"x0": mx + 1.5, "y0": my + 1.5, "x1": x1, "y1": y1, "kind": "building"})
			boxes.append({"x0": mx - 0.9, "y0": y0 - 3.0, "x1": mx + 0.9, "y1": y0 - 1.0, "kind": "wreck"})
			boxes.append({"x0": x0 + 2.0, "y0": my - 0.3, "x1": x0 + 3.0, "y1": my + 0.3, "kind": "prop"})
			posts.append({"x": x0 - 1.5, "y": y0 - 1.5, "r": 0.25, "kind": "lamp"})
			posts.append({"x": x1 + 1.5, "y": y1 + 1.5, "r": 0.4, "kind": "tree"})
			lights.append({"x": x0 - 1.5, "y": y0 - 1.5, "z": 6.0, "energy": 8.0, "range": 12.0, "kind": "omni"})
			lights.append({"x": x1 + 1.5, "y": y1 + 1.5, "z": 6.0, "energy": 2.0, "range": 12.0, "kind": "omni"})
			spawns.append({"x": x0 - 1.5, "y": my})
			spawns.append({"x": x1 + 1.5, "y": my})
	if barrier:
		var at: float = (ys[0] + ys[-1]) * 0.5
		boxes.append({"x0": arena["left"] + 40.0, "y0": at + 5.5, "x1": arena["left"] + 1240.0, "y1": at + 5.8, "kind": "fence"})
	return {
		"arena": arena, "boxes": boxes, "posts": posts, "blocks": blocks, "roads": roads, "lights": lights,
		"lamps": [], "wrecks": [], "creature_spawns": spawns, "fires": [],
		"player_start": {"x": xs[0], "y": (ys[0] + ys[-1]) * 0.5 - 2.5, "angle": 0.0},
		"gate": {"x": arena["left"], "y": (ys[0] + ys[-1]) * 0.5, "width": 8.0},
	}

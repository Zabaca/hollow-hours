extends Node
## What the simulation costs per query and per step, in the quarter and in synthetic cities (SyntheticCity), and how
## long the world and its path grid take to build. A probe: it prints and asserts nothing (world_test asserts that the
## cost does not grow with the city). It uses only calls that older checkouts have too, so the same file run in an older
## worktree gives the "before" numbers.
##
##   godot --headless --path . res://tests/cost_probe.tscn

const DT := 1.0 / 120.0

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 3
	var cities := [
		["the quarter (140 by 108 m)", CityLayout.DATA],
		["quarter-sized grid", SyntheticCity.grid(2, 2)],
		["3 times as wide and tall (396 by 300 m)", SyntheticCity.grid(6, 6)],
		["1.5 km long and thin (1300 by 60 m)", SyntheticCity.grid(20, 1, true)],
	]
	for c in cities:
		var layout: Dictionary = c[1]
		var t0 := Time.get_ticks_usec()
		var world := SimWorld.from_layout(layout)
		var t1 := Time.get_ticks_usec()
		var nav := NavGrid.new(world, 2.4)
		var t2 := Time.get_ticks_usec()
		var q := _queries(world, layout)
		var step := _step(layout)
		print("%-42s world %6.1f ms, car grid %6.1f ms (%d cells) | us per query: line %5.1f push %5.1f lit %5.1f car %5.1f | us per step with a pack of 5: %5.1f" % [
			c[0], (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, nav.size.x * nav.size.y, q["line"], q["push"], q["lit"], q["car"], step])
	get_tree().quit(0)


func _micros(f: Callable, n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		f.call(i)
	return float(Time.get_ticks_usec() - t0) / float(n)


func _queries(w: SimWorld, layout: Dictionary) -> Dictionary:
	var a: Dictionary = w.arena
	var pts: Array = []
	var ends: Array = []
	for i in 400:
		var p := Vector2(rng.randf_range(float(a["left"]), float(a["right"])), rng.randf_range(float(a["bottom"]), float(a["top"])))
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


func _step(layout: Dictionary) -> float:
	var sim := GameSim.new(layout, "bruiser", 5)
	sim.pack.set_size(5)
	var n := int(20.0 / DT)
	var t0 := Time.get_ticks_usec()
	for i in n:
		sim.step(DT, {"throttle": 0.6, "turn": 0.25 * sin(i * 0.002), "handbrake": false, "boost": false})
		sim.take_events()
	return float(Time.get_ticks_usec() - t0) / float(n)

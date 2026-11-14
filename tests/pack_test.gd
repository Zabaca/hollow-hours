extends Node
## Headless behaviour checks for the creatures and the rules around them (GameSim).
##
##   godot --headless --path . res://tests/pack_test.tscn
##
## These are scripted scenarios with a fixed seed, not a balance test: a stationary car gets
## found, a clinging creature is shaken off by a hard slide, a creature in the car's path is run
## down, nothing walks through a building, and the pathing finds a way round one.

const DT := 1.0 / 120.0

var failures := 0


func _ready() -> void:
	_test_found_when_still()
	_test_shake_off()
	_test_run_down()
	_test_no_wall_walking()
	_test_nav_round_building()
	_test_dawn()
	print("")
	print("pack_test: %d failed" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, name: String, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL "), name, ("  " + detail) if detail != "" else "")
	if not ok:
		failures += 1


func _sim(seed_in: int = 7) -> GameSim:
	return GameSim.new(CityLayout.DATA, "bruiser", seed_in)


func _run(sim: GameSim, seconds: float, controls: Dictionary, tally: Dictionary = {}) -> void:
	for i in int(seconds / DT):
		sim.step(DT, controls)
		for e in sim.take_events():
			var k: String = e["type"]
			tally[k] = int(tally.get(k, 0)) + 1


func _test_found_when_still() -> void:
	var sim := _sim()
	var tally := {}
	_run(sim, 150.0, {"throttle": 0.0, "turn": 0.0, "handbrake": false, "boost": false}, tally)
	_check(int(tally.get("latch", 0)) > 0 and sim.hull < GameSim.MAX_HULL, "a parked car is found and torn at", "latches=%d hull=%.0f phase=%d" % [int(tally.get("latch", 0)), sim.hull, sim.phase])


func _test_shake_off() -> void:
	var sim := _sim()
	sim.pack.gaunts.clear()
	var g := GauntSim.new()
	g.id = 99
	g.slot = 0
	g.state = GauntSim.State.LATCHED
	sim.pack.gaunts.append(g)
	sim.car.body.velocity = Vector2(14, 0)
	var tally := {}
	_run(sim, 4.0, {"throttle": 1.0, "turn": 1.0, "handbrake": true, "boost": false}, tally)
	_check(g.state != GauntSim.State.LATCHED, "a handbrake slide throws a clinging creature off", "state=%d thrown_events=%d" % [g.state, int(tally.get("thrown", 0))])
	var sim2 := _sim()
	sim2.pack.gaunts.clear()
	var g2 := GauntSim.new()
	g2.id = 98
	g2.slot = 0
	g2.state = GauntSim.State.LATCHED
	sim2.pack.gaunts.append(g2)
	sim2.car.body.velocity = Vector2(20, 0)
	_run(sim2, 4.0, {"throttle": 1.0, "turn": 0.0, "handbrake": false, "boost": false})
	_check(g2.state == GauntSim.State.LATCHED, "driving straight does not shake it off")
	_check(sim2.hull < GameSim.MAX_HULL, "a clinging creature costs hull", "hull=%.1f" % sim2.hull)


func _test_run_down() -> void:
	var sim := _sim()
	sim.pack.gaunts.clear()
	var g := GauntSim.new()
	g.id = 50
	g.state = GauntSim.State.DOWN
	g.stun = 30.0
	g.pos = Vector2(-22.0, -2.5)
	sim.pack.gaunts.append(g)
	sim.car.body.velocity = Vector2(20, 0)
	var tally := {}
	_run(sim, 1.5, {"throttle": 1.0, "turn": 0.0, "handbrake": false, "boost": false}, tally)
	_check(g.state == GauntSim.State.DEAD and int(tally.get("roadkill", 0)) == 1, "a fast car runs a creature down", "state=%d roadkills=%d kills=%d" % [g.state, int(tally.get("roadkill", 0)), sim.kills])


func _test_no_wall_walking() -> void:
	var sim := _sim(3)
	var inside := 0
	var steps := int(100.0 / DT)
	for i in steps:
		var t := i * DT
		var turn := sin(t * 0.4) * 0.6
		sim.step(DT, {"throttle": 0.7, "turn": turn, "handbrake": false, "boost": false})
		sim.take_events()
		if i % 6 == 0:
			for g in sim.pack.gaunts:
				if g.state == GauntSim.State.LATCHED or g.state == GauntSim.State.LEAP or g.state == GauntSim.State.THROWN:
					continue
				for b in sim.world.boxes:
					if g.pos.x > b["x0"] + 0.1 and g.pos.x < b["x1"] - 0.1 and g.pos.y > b["y0"] + 0.1 and g.pos.y < b["y1"] - 0.1:
						inside += 1
	_check(inside == 0, "creatures stay out of buildings", "samples inside a building: %d" % inside)


func _test_nav_round_building() -> void:
	var sim := _sim()
	var from := Vector2(-44.0, 24.0)  # inside the NW tower's lot edge
	var a := Vector2(-60.0, 24.0)  # on the west road
	var b := Vector2(-3.0, 24.0)  # on the central road, the tower block between
	_check(not sim.world.line_clear(a, b), "the line between the roads is blocked by buildings")
	var path := sim.nav.path(a, b)
	_check(path.size() > 4, "the grid finds a way round them", "waypoints=%d" % path.size())
	var clear := true
	for i in range(path.size() - 1):
		if not sim.world.line_clear(path[i], path[i + 1], 0.3):
			clear = false
	_check(clear, "every leg of that route is clear of buildings")
	if from.x > 0:
		pass


func _test_dawn() -> void:
	var sim := _sim()
	var tally := {}
	sim.time = GameSim.NIGHT_LENGTH - 0.05
	_run(sim, 12.0, {"throttle": 0.0, "turn": 0.0, "handbrake": false, "boost": false}, tally)
	var any_alive := false
	for g in sim.pack.gaunts:
		if g.alive():
			any_alive = true
	_check(sim.phase == GameSim.Phase.DAWN or sim.phase == GameSim.Phase.WRECKED, "the night ends at first light", "phase=%d" % sim.phase)
	_check(int(tally.get("dawn", 0)) == 1 and not any_alive, "the survivors flee at dawn", "dawn events=%d alive=%s" % [int(tally.get("dawn", 0)), any_alive])

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
	_test_pounce_is_readable()
	_test_pounce_can_be_beaten()
	_test_throw_off_takes_a_few_seconds()
	_test_scraping_rakes_one_off()
	_test_thrown_is_clear_and_safe()
	_test_rundown_needs_the_cars_speed()
	_test_camera_pull()
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
	sim2.car.body.position = Vector2(-30, 0.3)  # the gap between the van and the bus
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


func _test_camera_pull() -> void:
	var sim := _sim()
	var w := sim.world
	# The NW tower stands at x -54..-34, y 10..38; a camera behind a car at the south wall of
	# the dark block, looking through it, must be pulled in; an open street must not.
	var car := Vector3(-44.0, 1.8, -8.0)  # in the street south of the tower
	var behind_wall := Vector3(-44.0, 4.0, -30.0)  # north of it, inside the tower's footprint beyond
	var through := ChaseCamera.clear_fraction(w, car, behind_wall, 0.45)
	_check(through < 1.0, "a camera ray through a building is stopped", "fraction=%.2f" % through)
	var open := ChaseCamera.clear_fraction(w, Vector3(-30.0, 1.8, 0.0), Vector3(-10.0, 4.0, 0.0), 0.45)
	_check(open == 1.0, "an open street is not", "fraction=%.2f" % open)
	# A parked wreck is low: a camera at head height is stopped by it, one high above passes over.
	var low := ChaseCamera.clear_fraction(w, Vector3(13.5, 1.0, -10.0), Vector3(13.5, 1.0, -20.0), 0.45)
	var high := ChaseCamera.clear_fraction(w, Vector3(13.5, 6.0, -10.0), Vector3(13.5, 6.0, -20.0), 0.45)
	_check(low < 1.0 and high == 1.0, "a low camera is stopped by a wreck and a high one passes over", "low=%.2f high=%.2f" % [low, high])
	# The perimeter wall is not a box in the layout: a camera behind a car at the west edge
	# must still be stopped by it (it used to end up outside, looking at the wall's far side).
	var edge := ChaseCamera.clear_fraction(w, Vector3(-66.0, 1.8, 0.0), Vector3(-80.0, 4.0, 0.0), 0.45)
	_check(edge < 1.0, "a camera behind the west edge is stopped by the perimeter wall", "fraction=%.2f" % edge)


# ----------------------------------------------------------------------------- the encounter loop

var _enc: GameSim


## A clean world with one hunting creature ahead of a car on the avenue, going `kmh`.
func _enc_setup(seed_in: int, kmh: float, side: float) -> Array:
	if _enc == null:
		_enc = GameSim.new(CityLayout.DATA, "bruiser", seed_in)
	_enc.seed_value = seed_in
	_enc.reset()
	_enc.pack.director_on = false
	_enc.pack.gaunts.clear()
	var v := kmh / 3.6
	_enc.place_car(Vector2(-66.0, 0.0), 0.0, GameSim.MAX_HULL)
	_enc.car.body.velocity = Vector2(v, 0.0)
	var g := _enc.pack.place_hunting(Vector2(-66.0 + 14.0 + v * 0.55, side * 6.5), _enc.car)
	_enc.events.clear()
	return [_enc, g]


## Run one pounce: `dodge` is "" (carry on), "swerve" (away, a beat after the wind-up starts) or "brake".
## Returns the events of interest: {windup_t, leap_t, latched, missed}.
func _enc_run(seed_in: int, kmh: float, dodge: String) -> Dictionary:
	var side := 1.0 if seed_in % 2 == 0 else -1.0
	var setup := _enc_setup(seed_in, kmh, side)
	var sim: GameSim = setup[0]
	var v := kmh / 3.6
	var out := {"windup_t": -1.0, "leap_t": -1.0, "latched": false, "missed": false}
	var t := 0.0
	while t < 4.0 and sim.car.body.position.x < -14.0:
		var since: float = (t - out["windup_t"]) if out["windup_t"] >= 0.0 else -1.0
		var c := {"throttle": clampf((v - sim.car.body.velocity.x) * 0.35, -1.0, 1.0), "turn": clampf(angle_difference(sim.car.body.angle, 0.0) * 2.0, -1.0, 1.0), "handbrake": false, "boost": false}
		if since >= 0.3 and since < 1.0:
			if dodge == "swerve":
				c["turn"] = -side
			elif dodge == "brake":
				c["throttle"] = -1.0
		sim.step(DT, c)
		t += DT
		for e in sim.take_events():
			match e["type"]:
				"pounce_windup":
					out["windup_t"] = t
				"leap":
					out["leap_t"] = t
				"latch":
					out["latched"] = true
				"pounce_missed":
					out["missed"] = true
		if out["latched"] or out["missed"]:
			break
	return out


func _test_pounce_is_readable() -> void:
	var early := 0
	var gaps: Array = []
	for i in 20:
		var r := _enc_run(500 + i, 20.0, "")
		if r["windup_t"] >= 0.0 and r["leap_t"] >= 0.0:
			gaps.append(r["leap_t"] - r["windup_t"])
		if r["leap_t"] >= 0.0 and r["windup_t"] < 0.0:
			early += 1
	gaps.sort()
	_check(gaps.size() >= 15 and early == 0 and gaps[0] >= PackSim.WIND_TIME - 0.02, "every pounce announces itself and waits the whole wind-up before it leaves the ground", "n=%d shortest wind-up %.2f s (need %.2f)" % [gaps.size(), gaps[0] if gaps.size() > 0 else -1.0, PackSim.WIND_TIME])


func _latch_rate(kmh: float, dodge: String, n: int = 50) -> float:
	var leaps := 0
	var latches := 0
	for i in n:
		var r := _enc_run(600 + i, kmh, dodge)
		if r["leap_t"] >= 0.0:
			leaps += 1
			if r["latched"]:
				latches += 1
	return float(latches) / maxf(float(leaps), 1.0)


func _test_pounce_can_be_beaten() -> void:
	var still := _latch_rate(0.0, "")
	var slow := _latch_rate(20.0, "")
	var straight_fast := _latch_rate(60.0, "")
	var swerve := _latch_rate(60.0, "swerve")
	var swerve_mid := _latch_rate(40.0, "swerve")
	var brake := _latch_rate(60.0, "brake")
	_check(still > 0.85, "a stopped car is latched nearly every time", "%.0f%%" % (still * 100.0))
	_check(slow > 0.7, "a slow one on most pounces", "%.0f%%" % (slow * 100.0))
	_check(swerve < 0.3 and swerve_mid < 0.4, "an alert driver who swerves in the window is latched under a third of the time at speed", "60 km/h %.0f%%, 40 km/h %.0f%%" % [swerve * 100.0, swerve_mid * 100.0])
	_check(brake < 0.4, "braking hard in the window beats it too", "%.0f%%" % (brake * 100.0))
	_check(swerve < straight_fast * 0.5, "and the dodge is worth far more than driving straight on", "straight %.0f%% vs swerve %.0f%%" % [straight_fast * 100.0, swerve * 100.0])
	# A miss: lands, is stunned, and gets up.
	var seen_miss := false
	var recovered := false
	for i in 30:
		var setup := _enc_setup(700 + i, 60.0, 1.0)
		var sim: GameSim = setup[0]
		var g: GauntSim = setup[1]
		var since := -1.0
		for k in int(4.0 / DT):
			var c := {"throttle": 0.5, "turn": 0.0, "handbrake": false, "boost": false}
			if g.state == GauntSim.State.WIND:
				since = maxf(since, 0.0)
			if since >= 0.0:
				since += DT
			if since > 0.3 and since < 1.0:
				c["turn"] = -1.0
			sim.step(DT, c)
			for e in sim.take_events():
				if e["type"] == "pounce_missed":
					seen_miss = true
				if e["type"] == "recovered" and seen_miss:
					recovered = true
			if recovered:
				break
		if recovered:
			break
	_check(seen_miss and recovered, "a missed pounce lands, tumbles and the creature gets up again")


## Time for a creature on the roof to let go while the driver does one thing; 99 if it never does.
func _shake_time(kmh: float, how: String) -> float:
	var setup := _enc_setup(800, kmh, 1.0)
	var sim: GameSim = setup[0]
	sim.pack.gaunts.clear()
	var g := GauntSim.new()
	g.id = 77
	g.slot = 0
	g.state = GauntSim.State.LATCHED
	g.stamina = PackSim.GRIP
	g.pos = sim.car.body.to_world(PackSim.SLOTS[0]["local"])
	sim.pack.gaunts.append(g)
	var t := 0.0
	var v := kmh / 3.6
	while t < 10.0:
		var flip := 1.0 if int(t / 0.6) % 2 == 0 else -1.0
		var c := {"throttle": 0.7, "turn": 0.0, "handbrake": false, "boost": false}
		if how == "swerve":
			c["turn"] = flip
		elif how == "slide":
			c["turn"] = flip
			c["handbrake"] = true
		else:
			c["turn"] = clampf(angle_difference(sim.car.body.angle, 0.0) * 2.0, -1.0, 1.0)
		if sim.car.body.position.x > 40.0 or absf(sim.car.body.position.y) > 6.0:
			sim.car.body.position = Vector2(-60.0, 0.0)
			sim.car.body.angle = 0.0
		sim.step(DT, c)
		t += DT
		sim.take_events()
		if g.state != GauntSim.State.LATCHED:
			return t
	return 99.0


func _test_throw_off_takes_a_few_seconds() -> void:
	var slide_slow := _shake_time(20.0, "slide")
	var slide_fast := _shake_time(50.0, "slide")
	var swerve_mid := _shake_time(40.0, "swerve")
	var swerve_slow := _shake_time(20.0, "swerve")
	var straight := _shake_time(40.0, "straight")
	_check(slide_slow < 2.0 and slide_fast < 1.5, "a handbrake slide throws it off in 1 to 2 seconds, even at a crawl", "20 km/h %.1f s, 50 km/h %.1f s" % [slide_slow, slide_fast])
	_check(swerve_mid < 3.0 and swerve_slow < 3.5, "hard swerves do it in about 1 to 3 seconds", "40 km/h %.1f s, 20 km/h %.1f s" % [swerve_mid, swerve_slow])
	_check(straight >= 99.0, "driving straight on never does")
	# The grip shows as progress.
	var setup := _enc_setup(801, 40.0, 1.0)
	var sim: GameSim = setup[0]
	sim.pack.gaunts.clear()
	var g := GauntSim.new()
	g.id = 78
	g.slot = 0
	g.state = GauntSim.State.LATCHED
	g.stamina = PackSim.GRIP
	g.pos = sim.car.body.to_world(PackSim.SLOTS[0]["local"])
	sim.pack.gaunts.append(g)
	var p0 := sim.pack.shake_progress()
	for i in 40:
		sim.step(DT, {"throttle": 0.7, "turn": 1.0, "handbrake": true, "boost": false})
	var p1 := sim.pack.shake_progress()
	_check(is_equal_approx(p0, 0.0) and p1 > 0.15, "shaking shows as progress on the bar", "%.2f then %.2f" % [p0, p1])


func _test_scraping_rakes_one_off() -> void:
	var setup := _enc_setup(810, 30.0, 1.0)
	var sim: GameSim = setup[0]
	sim.pack.gaunts.clear()
	var g := GauntSim.new()
	g.id = 79
	g.slot = 3  # the left side
	g.state = GauntSim.State.LATCHED
	g.stamina = PackSim.GRIP
	g.pos = sim.car.body.to_world(PackSim.SLOTS[3]["local"])
	sim.pack.gaunts.append(g)
	var far := GauntSim.new()
	far.id = 80
	far.slot = 4  # the right side
	far.state = GauntSim.State.LATCHED
	far.stamina = PackSim.GRIP
	far.pos = sim.car.body.to_world(PackSim.SLOTS[4]["local"])
	sim.pack.gaunts.append(far)
	var hit_at: Vector2 = g.pos + Vector2(0.0, 0.3)
	sim.pack.scrape(sim.car, hit_at, 4.0)
	_check(g.state == GauntSim.State.THROWN and far.state == GauntSim.State.LATCHED, "scraping the car's side against something rakes off the one clinging there and leaves the other")


func _test_thrown_is_clear_and_safe() -> void:
	var cleared := 0
	var worst_lateral := INF
	for i in 20:
		var setup := _enc_setup(900 + i, 40.0, 1.0)
		var sim: GameSim = setup[0]
		sim.pack.gaunts.clear()
		var g := GauntSim.new()
		g.id = 90
		g.slot = 0
		g.state = GauntSim.State.LATCHED
		g.stamina = 0.01
		g.pos = sim.car.body.to_world(PackSim.SLOTS[0]["local"])
		sim.pack.gaunts.append(g)
		var landed_at := Vector2.ZERO
		var car_at := Vector2.ZERO
		var died := false
		for k in int(3.0 / DT):
			sim.step(DT, {"throttle": 0.6, "turn": 1.0 if k < 20 else 0.0, "handbrake": k < 20, "boost": false})
			for e in sim.take_events():
				if e["type"] == "stunned":
					landed_at = e["pos"]
					car_at = sim.car.body.position
				if e["type"] in ["roadkill", "died"]:
					died = true
		if landed_at != Vector2.ZERO:
			# Distance from the car's line (its heading through where it was at the throw) when it landed.
			var lateral := absf((landed_at - car_at).cross(Vector2.from_angle(sim.car.body.angle)))
			worst_lateral = minf(worst_lateral, lateral)
		if not died and g.state in [GauntSim.State.DOWN, GauntSim.State.HUNT, GauntSim.State.THROWN, GauntSim.State.STALK]:
			cleared += 1
	_check(cleared == 20, "a creature shaken off is never killed by the car afterwards (20 of 20 survive)", "survived=%d" % cleared)
	# Stunned and not to be crushed by a slow roll; but a fast one still runs it down.
	for case in [[6.0, false], [8.0, false], [11.0, true]]:
		var sim := _enc_setup(950, 0.0, 1.0)[0] as GameSim
		sim.pack.gaunts.clear()
		var g := GauntSim.new()
		g.id = 91
		g.state = GauntSim.State.DOWN
		g.stun = 30.0
		g.pos = Vector2(-60.0, 0.0)
		sim.pack.gaunts.append(g)
		sim.place_car(Vector2(-67.0, 0.0), 0.0, GameSim.MAX_HULL)
		sim.car.body.velocity = Vector2(float(case[0]), 0.0)
		for k in int(1.5 / DT):
			sim.step(DT, {"throttle": clampf((float(case[0]) - sim.car.body.velocity.x) * 0.5, 0.0, 1.0), "turn": 0.0, "handbrake": false, "boost": false})
			sim.take_events()
		_check((g.state == GauntSim.State.DEAD) == bool(case[1]), "a stunned creature run over at %d km/h %s" % [int(float(case[0]) * 3.6), "dies" if case[1] else "is only shoved aside"], "state=%d" % g.state)
	# It cannot take hold again for a few seconds, even if it is touching a slow car.
	var s2 := _enc_setup(960, 0.0, 1.0)[0] as GameSim
	s2.pack.gaunts.clear()
	var h := s2.pack.place_hunting(s2.car.body.position + Vector2(2.6, 0.0), s2.car)
	h.cooldown = PackSim.RELATCH_LOCK
	h.vel = Vector2(-4.0, 0.0)
	for k in int(1.0 / DT):
		s2.step(DT, {"throttle": 0.0, "turn": 0.0, "handbrake": false, "boost": false})
		s2.take_events()
		h.cooldown = maxf(h.cooldown, 2.0)
	_check(h.state != GauntSim.State.LATCHED, "a creature that was just thrown cannot take hold again straight away")


func _test_rundown_needs_the_cars_speed() -> void:
	# A creature sprinting at a stopped or crawling car is not killed by touching it: it is the car's speed that counts.
	var killed_slow := 0
	var killed_fast := 0
	for kmh in [0.0, 15.0, 40.0]:
		for i in 10:
			var setup := _enc_setup(1000 + i, float(kmh), 1.0)
			var sim: GameSim = setup[0]
			sim.pack.gaunts.clear()
			var g := sim.pack.place_hunting(sim.car.body.position + Vector2(8.0, 0.0), sim.car)
			g.cooldown = 99.0  # no pounce: it just runs at the car
			for k in int(1.5 / DT):
				sim.step(DT, {"throttle": clampf((float(kmh) / 3.6 - sim.car.body.velocity.x) * 0.4, 0.0, 1.0), "turn": 0.0, "handbrake": false, "boost": false})
				sim.take_events()
			if g.state == GauntSim.State.DEAD:
				if kmh < 25.0:
					killed_slow += 1
				else:
					killed_fast += 1
	_check(killed_slow == 0, "a creature that runs into a stopped or crawling car is not killed by it", "killed slow=%d" % killed_slow)
	_check(killed_fast >= 8, "but a car doing 40 km/h kills one it meets", "killed fast=%d of 10" % killed_fast)

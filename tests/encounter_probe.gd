extends Node
## Measures the encounter loop headless, with scripted human-like drivers (not the autopilot):
##   1. the latch rate per pounce at 0, 20, 40, 60 and 80 km/h for a driver who holds a straight line, one who
##      wanders, and one who reacts to the wind-up (swerve, brake or boost after a reaction time);
##   2. how long it takes to throw one off, and with what inputs, at crawling to fast speeds;
##   3. what kills a just-thrown creature, and at what closing speed.
##
##   godot --headless --path . res://tests/encounter_probe.tscn            (all of it)
##   godot --headless --path . res://tests/encounter_probe.tscn -- pounce   (or: throw, thrown)
##
## It prints tables; it asserts nothing (pack_test pins the rules). Fixed seeds, so a run is repeatable.

const DT := 1.0 / 120.0
const KMH := 1.0 / 3.6
const TRIALS := 80
const REACT := 0.3  # seconds from the wind-up starting to the driver's hand moving

var part := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	part = args[0] if args.size() > 0 else ""
	if part in ["", "pounce"]:
		_pounce_table()
	if part in ["", "throw"]:
		_throw_table()
	if part in ["", "thrown"]:
		_thrown_table()
	get_tree().quit()


var _sim: GameSim


## A clean world with nothing hunting. One GameSim is reused (building its path grid is the slow part).
func _fresh(seed_in: int) -> GameSim:
	if _sim == null:
		_sim = GameSim.new(CityLayout.DATA, "bruiser", seed_in)
	_sim.seed_value = seed_in
	_sim.reset()
	_sim.pack.director_on = false
	_sim.pack.gaunts.clear()
	_sim.events.clear()
	return _sim


# ----------------------------------------------------------------------------- the driver

## What a person does. `t` is seconds since the trial began; `since_wind` seconds since a creature began its
## wind-up (-1 before). Returns the controls.
func _drive(sim: GameSim, profile: String, target: float, t: float, since_wind: float, side: float) -> Dictionary:
	var car := sim.car
	var fwd_speed := car.body.velocity.dot(car.forward())
	var throttle := clampf((target - fwd_speed) * 0.35, -1.0, 1.0)
	if target < 0.5:
		throttle = clampf(-fwd_speed * 0.5, -1.0, 0.0)
	var turn := 0.0
	var brake := false
	var boost := false
	match profile:
		"straight":
			turn = clampf(angle_difference(car.body.angle, 0.0) * 2.0, -1.0, 1.0)  # holds the road
		"wander":
			turn = clampf(angle_difference(car.body.angle, 0.0) * 2.0 + sin(t * 3.1) * 0.35, -1.0, 1.0)
		"swerve", "brake", "boost":
			turn = clampf(angle_difference(car.body.angle, 0.0) * 2.0, -1.0, 1.0)
			if since_wind >= REACT and since_wind < REACT + 0.7:
				if profile == "swerve":
					turn = -side  # away from the side it is coming from
				elif profile == "brake":
					throttle = -1.0
				else:
					boost = true
					throttle = 1.0
	return {"throttle": throttle, "turn": turn, "handbrake": brake, "boost": boost}


# ----------------------------------------------------------------------------- pounces

## One creature placed in the road ahead, hunting. Returns {leaps, latches, kills, misses, thrown}.
func _pounce_trial(kmh: float, profile: String, seed_in: int) -> Dictionary:
	var sim := _fresh(seed_in)
	var side := 1.0 if seed_in % 2 == 0 else -1.0
	var v: float = kmh * KMH
	sim.place_car(Vector2(-66.0, 0.0), 0.0, GameSim.MAX_HULL)
	sim.car.body.velocity = Vector2(v, 0.0)
	var ahead := 14.0 + v * 0.55
	var g := sim.pack.place_hunting(Vector2(-66.0 + ahead, side * 6.5), sim.car)
	sim.events.clear()
	var out := {"leaps": 0, "latches": 0, "kills": 0, "misses": 0, "thrown": 0}
	var since_wind := -1.0
	var t := 0.0
	var settle := 0.0
	while t < 4.0 and sim.car.body.position.x < -14.0:
		if g.state == GauntSim.State.WIND and since_wind < 0.0:
			since_wind = 0.0
		elif since_wind >= 0.0:
			since_wind += DT
		sim.step(DT, _drive(sim, profile, v, t, since_wind, side))
		t += DT
		for e in sim.take_events():
			match e["type"]:
				"leap":
					out["leaps"] += 1
				"latch":
					out["latches"] += 1
				"roadkill":
					out["kills"] += 1
				"land":
					if bool(e.get("missed", false)):
						out["misses"] += 1
				"thrown":
					out["thrown"] += 1
		if out["latches"] > 0 or out["kills"] > 0:
			break
		if out["leaps"] > 0 and g.state != GauntSim.State.LEAP and g.state != GauntSim.State.WIND:
			settle += DT
			if settle > 0.6:
				break
	out["pounced"] = out["leaps"] > 0 or out["latches"] > 0
	return out


func _pounce_table() -> void:
	print("")
	print("POUNCES: one hunting creature ahead and to one side, %d trials per cell" % TRIALS)
	print("  latch% = latched per pounce that left the ground; pounced = trials where it pounced at all; killed = run down first")
	print("  %-8s %-9s %8s %8s %8s %8s" % ["km/h", "driver", "pounced", "leaps", "latch%", "killed"])
	for kmh in [0.0, 20.0, 40.0, 60.0, 80.0]:
		for profile in ["straight", "wander", "swerve", "brake", "boost"]:
			if kmh == 0.0 and profile != "straight":
				continue
			var pounced := 0
			var leaps := 0
			var latches := 0
			var kills := 0
			for i in TRIALS:
				var r := _pounce_trial(kmh, profile, 100 + i)
				pounced += 1 if r["pounced"] else 0
				leaps += int(r["leaps"])
				latches += int(r["latches"])
				kills += int(r["kills"])
			var rate := (100.0 * latches / leaps) if leaps > 0 else -1.0
			print("  %-8d %-9s %7d%% %8d %7s%% %7d%%" % [int(kmh), profile, int(100.0 * pounced / TRIALS), leaps, ("%d" % int(rate)) if rate >= 0.0 else "-", int(100.0 * kills / TRIALS)])


# ----------------------------------------------------------------------------- throwing one off

## A creature already on the car; the driver does one thing until it lets go. Returns seconds (cap 10).
func _throw_trial(kmh: float, how: String, seed_in: int) -> float:
	var sim := _fresh(seed_in)
	var v: float = kmh * KMH
	sim.place_car(Vector2(-66.0, 0.0), 0.0, GameSim.MAX_HULL)
	sim.car.body.velocity = Vector2(v, 0.0)
	var g := GauntSim.new()
	g.id = 1
	g.slot = 0
	g.state = GauntSim.State.LATCHED
	g.stamina = 3.0
	g.pos = sim.car.body.to_world(PackSim.SLOTS[0]["local"])
	sim.pack.gaunts.append(g)
	var t := 0.0
	while t < 10.0:
		var c := {"throttle": 0.7, "turn": 0.0, "handbrake": false, "boost": false}
		var phase := int(t / 0.6) % 2
		var flip := 1.0 if phase == 0 else -1.0
		match how:
			"drive straight":
				c["turn"] = clampf(angle_difference(sim.car.body.angle, 0.0) * 2.0, -1.0, 1.0)
			"hard swerves":
				c["turn"] = flip
			"slide":
				c["turn"] = flip
				c["handbrake"] = true
			"swerve + boost":
				c["turn"] = flip
				c["boost"] = true
		# Keep clear of the end of the road: turn back when it nears the arena, and hold the speed.
		if sim.car.body.position.x > 40.0 or absf(sim.car.body.position.y) > 6.0 or absf(sim.car.body.position.x) > 62.0:
			sim.car.body.position = Vector2(-60.0, 0.0)
			sim.car.body.angle = 0.0
		if v < 1.0 and how != "drive straight":
			c["throttle"] = 0.5
		sim.step(DT, c)
		t += DT
		sim.take_events()
		if g.state != GauntSim.State.LATCHED:
			return t
	return 99.0


func _throw_table() -> void:
	print("")
	print("THROWING ONE OFF: a creature latched on the roof, %d trials per cell, seconds until it lets go (99 = never, in 10 s)" % 30)
	print("  %-8s %-16s %8s %8s %8s" % ["km/h", "driver does", "median", "worst", "never%"])
	for kmh in [5.0, 20.0, 40.0, 60.0]:
		for how in ["drive straight", "hard swerves", "slide", "swerve + boost"]:
			var times: Array = []
			for i in 30:
				times.append(_throw_trial(kmh, how, 200 + i))
			times.sort()
			var never := 0
			for x in times:
				if x >= 99.0:
					never += 1
			var finite: Array = times.filter(func(x): return x < 99.0)
			var worst := "%.1f" % finite.back() if not finite.is_empty() else "-"
			var med := "%.1f" % times[times.size() / 2] if times[times.size() / 2] < 99.0 else "never"
			print("  %-8d %-16s %8s %8s %7d%%" % [int(kmh), how, med, worst, int(100.0 * never / times.size())])


# ----------------------------------------------------------------------------- what kills a thrown creature

func _thrown_table() -> void:
	print("")
	print("JUST THROWN: a creature shaken off by a slide, then the driver carries straight on for 6 s")
	print("  killed = thrown creatures run down afterwards; closing = the car's speed along the hit when it died (km/h); wait = seconds from the throw")
	print("  %-8s %8s %8s %12s %10s %10s %12s" % ["km/h", "thrown", "killed", "closing (min-max)", "wait (s)", "latch again", "earliest (s)"])
	for kmh in [10.0, 20.0, 40.0, 60.0]:
		var thrown := 0
		var killed := 0
		var relatch := 0
		var earliest := INF
		var cl_min := INF
		var cl_max := 0.0
		var waits: Array = []
		for i in 40:
			var sim := _fresh(300 + i)
			var v: float = kmh * KMH
			sim.place_car(Vector2(-66.0, 0.0), 0.0, GameSim.MAX_HULL)
			sim.car.body.velocity = Vector2(v, 0.0)
			var g := GauntSim.new()
			g.id = 1
			g.slot = 0
			g.state = GauntSim.State.LATCHED
			g.stamina = 0.05  # about to let go
			g.pos = sim.car.body.to_world(PackSim.SLOTS[0]["local"])
			sim.pack.gaunts.append(g)
			var t := 0.0
			var t_thrown := -1.0
			var done := false
			while t < 8.0 and not done:
				var c := {"throttle": 0.6 if v > 1.0 else 0.0, "turn": clampf(angle_difference(sim.car.body.angle, 0.0) * 2.0, -1.0, 1.0), "handbrake": t < 0.4, "boost": false}
				if t < 0.4:
					c["turn"] = 1.0
				sim.step(DT, c)
				t += DT
				for e in sim.take_events():
					match e["type"]:
						"thrown":
							if t_thrown < 0.0:
								t_thrown = t
								thrown += 1
						"roadkill":
							if t_thrown >= 0.0:
								killed += 1
								done = true
								var sp: float = e["speed"] * 3.6
								cl_min = minf(cl_min, sp)
								cl_max = maxf(cl_max, sp)
								waits.append(t - t_thrown)
						"died":
							if t_thrown >= 0.0:
								killed += 1
								done = true
								waits.append(t - t_thrown)
						"latch":
							if t_thrown >= 0.0:
								relatch += 1
								earliest = minf(earliest, t - t_thrown)
								done = true
				if sim.car.body.position.x > 40.0:
					break
		var wait_txt := "-"
		if not waits.is_empty():
			waits.sort()
			wait_txt = "%.1f-%.1f" % [waits[0], waits.back()]
		print("  %-8d %8d %8d %12s %10s %10d %12s" % [int(kmh), thrown, killed, ("%d-%d" % [int(cl_min), int(cl_max)]) if killed > 0 and cl_min < INF else "-", wait_txt, relatch, ("%.1f" % earliest) if earliest < INF else "-"])

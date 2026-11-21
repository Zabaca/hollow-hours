extends Node
## Headless behaviour checks for the story: the three missions, their fail states, checkpoints,
## the save and the pack's story hooks, all through the seam pack_test uses (step GameSim, read
## its events), plus the autopilot playing the whole story start to finish.
##
##   godot --headless --path . res://tests/mission_test.tscn
##
## Fixed seeds, no window. Tests that are not about the pack switch its director off and clear it,
## so nothing but what the story places hunts the car.

const DT := 1.0 / 120.0
const IDLE := {"throttle": 0.0, "turn": 0.0, "handbrake": false, "boost": false}
const DIR := "user://mission_test"
const MIN_LEG := 89.0  # m: "about 90"; the gas station to the pharmacy is 90.0

var failures := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_clean()
	_test_script()
	_test_places()
	_test_legs()
	_test_cities_and_chapters()
	_test_new_game()
	_test_start_story_at()
	_test_hold()
	_test_alarm()
	_test_run_down_count()
	_test_hunters_not_in_the_car()
	_test_wreck_fails_each_mission()
	_test_shutter()
	_test_gate_timer()
	_test_retry_from_checkpoint()
	_test_retry_before_checkpoint()
	_test_restart_mission()
	_test_complete_and_save()
	_test_missions_in_order()
	_test_continue_and_revert()
	_test_save_file()
	_test_save_across_chapters()
	_test_gate_trigger()
	_test_gate_needs_the_gap()
	_test_camera_through_the_gap()
	_test_escape_keeps_the_speed()
	_test_restart_closes_the_gate()
	_test_open_gate_gap()
	_test_no_dawn_clock()
	_test_pack_hooks()
	_test_whole_story_driven()
	_clean()
	print("")
	print("mission_test: %d failed" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, name: String, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL "), name, ("  " + detail) if detail != "" else "")
	if not ok:
		failures += 1


func _clean() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


# ----------------------------------------------------------------------------- helpers


## A story sim with nothing hunting: the director off and the pack cleared.
func _quiet(sim: GameSim) -> GameSim:
	sim.pack.director_on = false
	sim.pack.gaunts.clear()
	return sim


func _story(seed_in: int = 7) -> GameSim:
	return _quiet(GameSim.new(CityLayout.DATA, "bruiser", seed_in, true))


func _save_at(next_id: String) -> Dictionary:
	var done: Array = []
	for m in StoryData.MISSIONS:
		if m["id"] == next_id:
			break
		done.append(m["id"])
	return {
		"version": SaveStore.VERSION, "saved_at": 0, "next": next_id, "done": done, "ending_seen": false,
		"totals": {"kills": 0, "wrecks": 0, "seconds": 0.0},
	}


## Continue at the given mission (as a player who has finished the ones before it).
func _continued(next_id: String, seed_in: int = 7) -> GameSim:
	var sim := GameSim.new(CityLayout.DATA, "bruiser", seed_in, true)
	sim.continue_story(_save_at(next_id))
	return _quiet(sim)


func _at(sim: GameSim, place: String, angle: float = 0.0) -> void:
	sim.place_car(StoryData.place_pos(place), angle, sim.hull)


## Step `seconds` with the given controls; every event that came out, in order.
func _run(sim: GameSim, seconds: float, controls: Dictionary = IDLE) -> Array:
	var out: Array = []
	for i in int(round(seconds / DT)):
		sim.step(DT, controls)
		out.append_array(sim.take_events())
	return out


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e): return e["type"] == type)


func _has(events: Array, type: String) -> bool:
	return not _of(events, type).is_empty()


func _lines(events: Array) -> Array:
	return _of(events, "line").map(func(e): return e["id"])


## Mission 1 up to just after the box is loaded (the checkpoint), by placing the car and waiting.
func _load_box(sim: GameSim) -> Array:
	var out: Array = []
	_at(sim, "motel")
	out.append_array(_run(sim, 0.1))
	out.append_array(_run(sim, 4.2))
	return out


## Mission 3 (continued) up to the checkpoint at the hotel; returns the events.
func _pick_up_both(sim: GameSim) -> Array:
	var out: Array = []
	_at(sim, "hut")
	out.append_array(_run(sim, 0.1))
	_at(sim, "hotel")
	out.append_array(_run(sim, 4.2))
	return out


# ----------------------------------------------------------------------------- the script and the places


func _test_script() -> void:
	var n := 0
	var chars := 0
	var bad_cue := 0
	for id in StoryData.LINES:
		n += 1
		chars += String(StoryData.LINES[id]["text"]).length()
		var sub := StoryData.subtitle(id)
		if sub.contains("[") or sub.contains("]") or sub == "" or sub != sub.strip_edges():
			bad_cue += 1
	_check(n == 21, "the radio script has 21 lines", "lines=%d" % n)
	_check(chars <= 1500, "the script stays inside the voice generator's 1,500 character limit", "chars with cue words=%d" % chars)
	_check(bad_cue == 0, "every subtitle is the text without its cue words")
	var missing: Array = []
	for id in StoryData.line_ids_used():
		if not StoryData.LINES.has(id):
			missing.append(id)
	_check(missing.is_empty(), "every line the missions name exists", str(missing))
	var speakers_ok := true
	for id in StoryData.LINES:
		if not StoryData.SPEAKERS.has(StoryData.LINES[id]["speaker"]):
			speakers_ok = false
	_check(speakers_ok, "every line has one of the three speakers")
	var unused: Array = []
	var used := StoryData.line_ids_used()
	for id in StoryData.LINES:
		if id not in used:
			unused.append(id)
	_check(unused.is_empty(), "every line is used by a mission or a fail reason", str(unused))
	_check(StoryData.reading_time("wrecked") >= 2.0, "a subtitle is up for at least two seconds")


func _test_places() -> void:
	var sim := _story()
	var w := sim.world
	var bad: Array = []
	var unreachable: Array = []
	var start: Vector2 = StoryData.place_pos("safe_start")
	for id in StoryData.PLACES:
		var pl: Dictionary = StoryData.PLACES[id]
		if not pl["marker"] or pl["city"] != sim.city_id:
			continue  # (a place in another city is checked against that city)
		var p: Vector2 = pl["pos"]
		if p.x < w.arena["left"] or p.x > w.arena["right"] or p.y < w.arena["bottom"] or p.y > w.arena["top"]:
			bad.append(id + ": outside the arena")
		# Clear of every building, wreck and post by the car's length (its widest reach).
		var clearance := 2.3
		for b in w.boxes:
			var dx := maxf(maxf(b["x0"] - p.x, 0.0), p.x - b["x1"])
			var dy := maxf(maxf(b["y0"] - p.y, 0.0), p.y - b["y1"])
			if Vector2(dx, dy).length() < clearance:
				bad.append("%s: %.1f m from a %s" % [id, Vector2(dx, dy).length(), b["kind"]])
		for q in w.posts:
			if p.distance_to(Vector2(q["x"], q["y"])) - q["r"] < clearance:
				bad.append("%s: too near a %s" % [id, q["kind"]])
		var path := sim.nav.path(start, p)
		if path.is_empty():
			unreachable.append(id)
	_check(bad.is_empty(), "every place is in the arena and clear of buildings, wrecks and posts", str(bad))
	_check(unreachable.is_empty(), "every place is reachable on the path grid from the safe start", str(unreachable))
	var apart := true
	for id in ["hut", "shop"]:
		if start.distance_to(StoryData.place_pos(id)) <= StoryData.place_radius(id):
			apart = false
	_check(apart, "the safe start is outside every mission start marker")
	_check(CityLayout.DATA.has("gate") and w.gate["pos"].is_equal_approx(StoryData.place_pos("west_gate")), "the layout's gate record is where the story's West Gate is", str(w.gate["pos"]))
	var gate_rec: Dictionary = CityLayout.DATA["gate"]
	_check(is_equal_approx(float(gate_rec["x"]), float(w.arena["left"])) and float(gate_rec["width"]) >= 2.0 * 1.06 + 4.0, "and it sits in the west wall with room for the car to line up", str(gate_rec))


## Every leg of the story is a real cross-town drive: from a mission's start to its first step and from each
## step's place to the next, about 90 m or more in a straight line (the hotel, pharmacy and gate are buildings
## that cannot move, which is why the missions alternate sides of town; see StoryData.PLACES).
func _test_legs() -> void:
	var short: Array = []
	var shortest := INF
	for m in StoryData.MISSIONS:
		if m["city"] != Cities.QUARTER:
			continue  # (a later chapter's legs are long drives, measured on its own city's path grid)
		var at_id: String = StoryData.start_place_id(m)
		for s in m["steps"]:
			if not s.has("place") or s["place"] == at_id:
				continue  # a hold at the place just reached is not a leg
			var d := StoryData.place_pos(at_id).distance_to(StoryData.place_pos(s["place"]))
			shortest = minf(shortest, d)
			if d < MIN_LEG:
				short.append("%s: %s to %s %.0f m" % [m["id"], at_id, s["place"], d])
			at_id = s["place"]
	_check(short.is_empty(), "every leg of every mission is at least %d m in a straight line" % int(MIN_LEG), "shortest=%.1f short=%s" % [shortest, str(short)])


# ----------------------------------------------------------------------------- starting, holding, counting


func _test_new_game() -> void:
	var sim := GameSim.new(CityLayout.DATA, "bruiser", 7, true)
	var e := sim.take_events()
	var started := _of(e, "mission_started")
	var obj := _of(e, "objective")
	_check(started.size() == 1 and started[0]["number"] == 1 and started[0]["title"] == "BATTERIES", "a new story starts mission 1")
	_check(obj.size() == 1 and obj[0]["kind"] == "reach" and obj[0]["place"] == "motel" and String(obj[0]["text"]) != "", "its first objective is to reach the motel office", str(obj))
	_check(_lines(e) == ["bat_call_1", "bat_call_2"], "its first two lines are Vera's call", str(_lines(e)))
	_check(sim.mission.objective_text() == obj[0]["text"] and sim.hull == GameSim.MAX_HULL, "the objective reads back and the hull is full")
	var blip: Array = sim.mission.blips()
	_check(blip.size() == 1 and blip[0]["kind"] == "objective" and blip[0]["place"] == "motel", "the motel office is the objective's blip")
	var safe: Dictionary = StoryData.PLACES["safe_start"]
	var nearest := INF
	for g in sim.pack.gaunts:
		nearest = minf(nearest, g.pos.distance_to(safe["pos"]))
	_check(sim.car.body.position.distance_to(safe["pos"]) < 0.5 and sim.pack.gaunts.size() == 3 and nearest >= 40.0, "the car starts at the safe start with three Gaunts well away from it", "nearest=%.1f" % nearest)


func _test_start_story_at() -> void:
	for i in 3:
		var sim := GameSim.new(CityLayout.DATA, "bruiser", 7, true)
		sim.start_story_at(i)
		var e := sim.take_events()
		var started := _of(e, "mission_started")
		var start_id: String = StoryData.MISSIONS[i]["start"]
		var at: Vector2 = StoryData.place_pos(start_id if start_id != "" else "safe_start")
		_check(started.size() >= 1 and started.back()["number"] == i + 1 and sim.car.body.position.distance_to(at) < 0.5, "a developer flag starts mission %d directly, with the car at its start" % (i + 1), str(started.size()))
		_check(sim.mission.objective()["kind"] == "reach" or sim.mission.objective()["kind"] == "hold", "and its first objective is up")


func _test_hold() -> void:
	var sim := _story()
	sim.take_events()
	_at(sim, "motel")
	var e := _run(sim, 0.1)
	_check(_lines(e) == ["bat_shop"] and sim.mission.hold_progress() >= 0.0, "reaching the motel office starts the hold and plays its line", str(_lines(e)))
	var filling := _of(e, "hold")
	e = _run(sim, 2.0)
	var p1: float = sim.mission.hold_progress()
	_check(absf(p1 - 0.5) < 0.05, "the hold fills while the car is inside the marker and still", "progress=%.3f" % p1)
	_check(filling.size() == 1 and filling[0]["state"] == "filling", "and reports it filling", str(filling))
	# Out of the marker: it pauses rather than resetting.
	sim.place_car(Vector2(46.0, -20.0), 0.0, sim.hull)
	e = _run(sim, 1.5)
	_check(absf(sim.mission.hold_progress() - p1) < 0.002, "the hold pauses outside the marker", "progress=%.3f" % sim.mission.hold_progress())
	_check(_of(e, "hold").size() >= 1 and _of(e, "hold")[0]["state"] == "paused", "and reports it paused")
	# Inside but moving: still paused.
	_at(sim, "motel")
	sim.car.body.velocity = Vector2(8.0, 0.0)
	_run(sim, 0.05)
	_check(absf(sim.mission.hold_progress() - p1) < 0.002, "the hold does not fill while the car is moving", "progress=%.3f" % sim.mission.hold_progress())
	# Still and inside: it picks up where it left off and finishes in the rest of the four seconds.
	_at(sim, "motel")
	e = _run(sim, 1.6)
	_check(not _has(e, "checkpoint"), "it has not finished before four seconds are held")
	e = _run(sim, 0.7)
	var cp := _of(e, "checkpoint")
	_check(cp.size() == 1 and "bat_loaded" in _lines(e), "four seconds held loads the box: a checkpoint and Vera's line", str(_lines(e)))
	_check(sim.mission.objective_text().contains("hotel"), "and the next objective is the hotel", sim.mission.objective_text())


func _test_alarm() -> void:
	var sim := GameSim.new(CityLayout.DATA, "bruiser", 7, true)
	sim.take_events()
	var before := sim.pack.alive_count()
	_at(sim, "motel")
	var e := _run(sim, 0.1)
	var alarm_early := "bat_alarm" in _lines(e)
	e = _run(sim, 1.5)
	_check(not alarm_early and "bat_alarm" in _lines(e), "the motel's alarm sounds once the loading has begun")
	e.append_array(_run(sim, 2.0))
	_check(before == 3 and sim.pack.alive_count() == 4, "and a fourth Gaunt joins the three", "before=%d after=%d" % [before, sim.pack.alive_count()])


func _kill_one(sim: GameSim) -> Array:
	# A stunned creature in the car's path, run over at speed (the pack test's recipe).
	sim.place_car(Vector2(-30.0, -2.5), 0.0, sim.hull)
	sim.car.body.velocity = Vector2(20.0, 0.0)
	var g := GauntSim.new()
	g.id = 500 + sim.pack.next_id
	sim.pack.next_id += 1
	g.state = GauntSim.State.DOWN
	g.stun = 30.0
	g.pos = Vector2(-22.0, -2.5)
	sim.pack.gaunts.append(g)
	return _run(sim, 0.8, {"throttle": 1.0, "turn": 0.0, "handbrake": false, "boost": false})


func _test_run_down_count() -> void:
	var sim := _continued("pharmacist")
	sim.take_events()
	# A creature run down before the step begins does not count towards it.
	_at(sim, "shop", -PI / 2.0)
	var e := _run(sim, 0.1)
	_check(_lines(e) == ["ph_call_1", "ph_call_2"], "mission 2 starts at the gas station with Teo's call and Vera's", str(_lines(e)))
	_kill_one(sim)
	var kills_before := sim.kills
	sim.pack.gaunts.clear()
	_at(sim, "pharmacy")
	e = _run(sim, 0.1)
	var o: Dictionary = sim.mission.objective()
	_check(kills_before == 1 and o["kind"] == "kill" and o["remaining"] == 2, "the run-down step counts from its own start", "objective=%s" % str(o))
	_check("ph_door" in _lines(e), "Teo's shutter line plays")
	var hunters := 0
	var near := true
	for g in sim.pack.gaunts:
		if g.attacking() and g.alert:
			hunters += 1
		if g.pos.distance_to(StoryData.place_pos("pharmacy")) > 14.0:
			near = false
	_check(hunters == 1 and sim.pack.gaunts.size() == 1 and near, "the first Gaunt is placed at the pharmacy, already hunting, down the avenue to the west", "hunters=%d total=%d" % [hunters, sim.pack.gaunts.size()])
	var first_x: float = (sim.pack.gaunts[0] as GauntSim).pos.x
	_check(first_x < StoryData.place_pos("pharmacy").x - 8.0, "on the side a car arriving from the east is driving towards", "x=%.1f" % first_x)
	_run(sim, 9.2)
	_check(sim.pack.gaunts.size() == 2, "and the second joins it nine seconds later", "n=%d" % sim.pack.gaunts.size())
	sim.pack.gaunts.clear()
	_kill_one(sim)
	_check(sim.mission.objective()["remaining"] == 1, "one run down leaves one to go")
	e = _kill_one(sim)
	_check(sim.mission.objective()["kind"] == "hold" and sim.mission.objective_text().contains("Teo"), "two run down ends the step", sim.mission.objective_text())
	_check("ph_cleared" in _lines(e), "and Teo says to stop by the door", str(_lines(e)))


# ----------------------------------------------------------------------------- failing


func _test_wreck_fails_each_mission() -> void:
	for id in ["batteries", "pharmacist", "west_gate"]:
		var sim := _story() if id == "batteries" else _continued(id)
		sim.take_events()
		if id != "batteries":
			_at(sim, StoryData.MISSIONS[StoryData.mission_index(id)]["start"])
			_run(sim, 0.1)
		sim.damage(1000.0, "test")
		var e := _run(sim, 0.1)
		var failed := _of(e, "mission_failed")
		_check(failed.size() == 1 and failed[0]["reason"] == "wrecked" and failed[0]["id"] == id, "a wreck fails %s with its reason" % id, str(failed))
		_check("wrecked" in _lines(e) and _of(e, "line").back()["priority"], "and Vera's call jumps the queue")
		_check(sim.mission.objective().is_empty(), "the objective is gone while it waits for a retry")


func _test_shutter() -> void:
	var sim := _continued("pharmacist")
	sim.take_events()
	_at(sim, "shop", -PI / 2.0)
	_run(sim, 0.1)
	var t: Array = sim.mission.timers_left()
	_check(t.size() == 1 and t[0]["id"] == "shutter" and absf(t[0]["left"] - StoryData.SHUTTER_SECONDS) < 0.5, "the shutter timer starts at the call, at three minutes", str(t))
	var e := _run(sim, 59.0)
	_check(absf(sim.mission.timers_left()[0]["left"] - (StoryData.SHUTTER_SECONDS - 59.1)) < 1.0, "it counts down in simulated time", str(sim.mission.timers_left()))
	e.append_array(_run(sim, 59.0))
	e.append_array(_run(sim, StoryData.SHUTTER_SECONDS - 120.0))
	_check(not _has(e, "mission_failed"), "the mission holds until the last second", str(sim.mission.timers_left()))
	e = _run(sim, 3.0)
	var failed := _of(e, "mission_failed")
	_check(failed.size() == 1 and failed[0]["reason"] == "shutter" and "ph_failed" in _lines(e), "the shutter gives way at 3:00 and Teo screams", str(failed))
	_check(sim.phase == GameSim.Phase.PLAYING, "a timed-out mission does not wreck the car")


func _test_gate_timer() -> void:
	var sim := _continued("west_gate")
	sim.take_events()
	_at(sim, "hut", PI / 2.0)
	var e := _run(sim, 0.1)
	_check(_lines(e) == ["gate_call_1", "gate_call_2"], "mission 3 starts at the park hut with Ruck's call and Vera's", str(_lines(e)))
	e = _pick_up_both(sim)
	_check(_has(e, "checkpoint") and "gate_aboard" in _lines(e), "Vera and Teo aboard is a checkpoint and Ruck's warning", str(_lines(e)))
	_check(sim.mission.objective()["kind"] == "survive", "then sixty seconds of staying alive")
	e = _run(sim, 59.0)
	_check(not _has(e, "gate_open") and not sim.world.gate["open"], "the gate stays shut for sixty seconds")
	e = _run(sim, 2.0)
	_check(_has(e, "gate_open") and "gate_open" in _lines(e) and sim.world.gate["open"], "then it opens, with Ruck's line")
	_check(sim.mission.objective()["kind"] == "gate" and sim.mission.timers_left()[0]["id"] == "gate", "and the objective is the gate, on a timer")
	e = _run(sim, 18.0)
	_check(not _has(e, "mission_failed"), "the car has twenty seconds")
	e = _run(sim, 2.5)
	var failed := _of(e, "mission_failed")
	_check(failed.size() == 1 and failed[0]["reason"] == "gate" and "gate_failed" in _lines(e) and _has(e, "gate_closed"), "the gate closes on a car that is too late", str(failed))
	_check(not sim.world.gate["open"], "the gate is shut again")


func _test_retry_from_checkpoint() -> void:
	var sim := _continued("west_gate")
	sim.take_events()
	_at(sim, "hut", PI / 2.0)
	_run(sim, 0.1)
	_at(sim, "hotel", PI / 2.0)
	sim.damage(70.0, "test")  # hull 30 when the checkpoint is taken
	_run(sim, 4.2)
	var cp_pos: Vector2 = sim.car.body.position
	var cp_hull := sim.hull
	_run(sim, 5.0)
	sim.damage(1000.0, "test")
	var wreck := _run(sim, 0.1)
	_check(sim.phase == GameSim.Phase.WRECKED and _has(wreck, "mission_failed"), "wrecked after the checkpoint")
	sim.retry_mission()
	var e := sim.take_events()
	_check(sim.phase == GameSim.Phase.PLAYING and sim.hull >= 60.0 and cp_hull < 60.0, "retry brings the car back with at least 60 hull", "hull=%.0f (was %.0f at the checkpoint)" % [sim.hull, cp_hull])
	_check(sim.car.body.position.distance_to(cp_pos) < 0.5 and sim.car.speed() < 0.1, "at the checkpoint's place, at rest", "at %s, checkpoint %s" % [str(sim.car.body.position), str(cp_pos)])
	_check(sim.mission.objective()["kind"] == "survive" and not sim.mission.timers_left().size() > 0, "on the step after the checkpoint")
	var retry := _of(e, "retry")
	_check(retry.size() == 1 and retry[0]["to"] == "checkpoint", "and says so", str(retry))
	var far := true
	var alerted := true
	for g in sim.pack.gaunts:
		if g.pos.distance_to(sim.car.body.position) < 40.0:
			far = false
		if not g.alert:
			alerted = false
	_check(sim.pack.gaunts.size() == 6 and far and alerted, "with a fresh pack of six, alerted, away from the car", "n=%d far=%s alerted=%s" % [sim.pack.gaunts.size(), far, alerted])
	# And the mission carries on from there: sixty seconds, then the gate.
	sim.pack.gaunts.clear()  # the six would have the idle car; the point is the mission's course
	e = _run(sim, 61.0)
	_check(_has(e, "gate_open"), "the retried run plays on to the gate opening")


func _test_retry_before_checkpoint() -> void:
	var sim := _story()
	sim.take_events()
	_at(sim, "motel")
	_run(sim, 0.5)
	sim.damage(1000.0, "test")
	_run(sim, 0.1)
	sim.retry_mission()
	var e := sim.take_events()
	var safe: Dictionary = StoryData.PLACES["safe_start"]
	_check(_has(e, "mission_started") and sim.mission.objective()["place"] == "motel" and sim.mission.objective()["kind"] == "reach", "before the first checkpoint a retry restarts the mission", str(_of(e, "retry")))
	_check(sim.car.body.position.distance_to(safe["pos"]) < 0.5 and sim.hull == GameSim.MAX_HULL, "at the safe start with a full hull")


func _test_restart_mission() -> void:
	var sim := _continued("pharmacist")
	sim.take_events()
	_at(sim, "shop", -PI / 2.0)
	_run(sim, 30.0)
	_at(sim, "pharmacy")
	_run(sim, 0.1)
	_check(sim.mission.objective()["kind"] == "kill", "mid-mission, on the run-down step")
	sim.damage(40.0, "test")
	sim.restart_mission()
	var e := sim.take_events()
	var start: Vector2 = StoryData.place_pos("shop")
	_check(_has(e, "mission_started") and sim.mission.objective()["kind"] == "reach" and sim.mission.objective()["place"] == "pharmacy", "restart starts the mission over", str(_lines(e)))
	_check(sim.car.body.position.distance_to(start) < 0.5 and sim.hull == GameSim.MAX_HULL, "the car at the mission's start with a full hull")
	_check(absf(sim.mission.timers_left()[0]["left"] - StoryData.SHUTTER_SECONDS) < 0.5, "and the shutter timer back at its full time")


# ----------------------------------------------------------------------------- completing, saving, order


func _test_complete_and_save() -> void:
	var sim := _story()
	sim.take_events()
	var e := _load_box(sim)
	_at(sim, "hotel", PI / 2.0)
	e.append_array(_run(sim, 3.3))
	var done := _of(e, "mission_complete")
	_check(done.size() == 1 and done[0]["id"] == "batteries" and not done[0]["final"] and "bat_done" in _lines(e), "delivering the box completes Batteries, with Vera's closing call", str(done))
	var prio := {}
	for l in _of(e, "line"):
		prio[l["id"]] = l["priority"]
	_check(prio.get("bat_done") == true and prio.get("bat_loaded") == false, "the closing call jumps the radio queue, a mid-mission line does not", str(prio))
	var saves := _of(e, "save")
	_check(saves.size() == 1 and saves[0]["data"]["next"] == "pharmacist" and saves[0]["data"]["done"] == ["batteries"], "and asks for a save naming the next mission", str(saves))
	_check(sim.mission.blips().size() == 1 and sim.mission.blips()[0]["kind"] == "start" and sim.mission.blips()[0]["place"] == "shop", "back in free roam with the gas station lit as a start")
	var path := DIR + "/round_trip.json"
	var wrote := SaveStore.write_save(saves[0]["data"], path)
	var back := SaveStore.load_save(path)
	_check(wrote and not back.is_empty() and back["next"] == "pharmacist" and back["done"] == ["batteries"] and back["version"] == SaveStore.VERSION, "the save written to a file reads back to the same next mission", str(back))
	_check(not FileAccess.file_exists(path + ".tmp"), "no temporary file is left behind")
	var sim2 := GameSim.new(CityLayout.DATA, "bruiser", 7, true)
	sim2.continue_story(back)
	var e2 := sim2.take_events()
	var roam := _of(e2, "roam")
	_check(roam.size() == 1 and roam[0]["next"] == "pharmacist" and sim2.mission.blips()[0]["place"] == "shop", "Continue from it lights mission 2's start")


func _test_missions_in_order() -> void:
	var sim := _story()
	sim.take_events()
	_at(sim, "shop", -PI / 2.0)
	var e := _run(sim, 1.0)
	_check(not _has(e, "mission_started") and sim.mission.objective()["place"] == "motel", "mission 2 cannot start before mission 1 is done")
	var sim2 := _continued("west_gate")
	sim2.take_events()
	_at(sim2, "shop", -PI / 2.0)
	e = _run(sim2, 1.0)
	_check(not _has(e, "mission_started"), "nor can mission 3 start at mission 2's marker")
	_at(sim2, "hut", PI / 2.0)
	e = _run(sim2, 0.2)
	_check(_of(e, "mission_started").size() == 1 and _of(e, "mission_started")[0]["number"] == 3, "but its own does")


func _test_continue_and_revert() -> void:
	var sim := _story()
	sim.take_events()
	_load_box(sim)
	_at(sim, "hotel", PI / 2.0)
	_run(sim, 3.3)
	sim.damage(1000.0, "test")
	var e := _run(sim, 0.1)
	_check(_has(e, "roam_wrecked") and sim.phase == GameSim.Phase.WRECKED, "wrecked in free roam is reported")
	var totals_before: Dictionary = sim.mission.save_data()["totals"]
	sim.revert_to_save()
	e = sim.take_events()
	var totals_after: Dictionary = sim.mission.save_data()["totals"]
	_check(totals_before["wrecks"] == 1 and totals_after == totals_before, "the wreck, the time and the kills still count after going back", "%s -> %s" % [str(totals_before), str(totals_after)])
	var safe: Dictionary = StoryData.PLACES["safe_start"]
	_check(sim.phase == GameSim.Phase.PLAYING and sim.hull == GameSim.MAX_HULL and sim.car.body.position.distance_to(safe["pos"]) < 0.5, "back to the last save: the safe start, a full hull")
	_check(sim.mission.blips()[0]["kind"] == "start" and sim.mission.blips()[0]["place"] == "shop", "with mission 2's start lit", str(_of(e, "roam")))
	# Before any save there is nothing to go back to but a new game.
	var fresh := _story()
	fresh.take_events()
	fresh.damage(1000.0, "test")
	_run(fresh, 0.1)
	fresh.revert_to_save()
	_check(fresh.mission.objective()["kind"] == "reach" and fresh.mission.objective()["place"] == "motel", "before the first save a wreck means a new game")
	_check(sim.mission.dawn_amount() > fresh.mission.dawn_amount(), "the sky has lightened a touch since the first mission", "%.2f vs %.2f" % [sim.mission.dawn_amount(), fresh.mission.dawn_amount()])


# ----------------------------------------------------------------------------- files


func _test_save_file() -> void:
	var path := DIR + "/damaged.json"
	_check(SaveStore.load_save(DIR + "/none.json").is_empty(), "a missing save counts as no save")
	var cases := {
		"garbage": "not json {",
		"an array": "[1, 2, 3]",
		"an unknown version": '{"version": 99, "next": "pharmacist", "done": ["batteries"], "ending_seen": false, "totals": {"kills": 0, "wrecks": 0, "seconds": 0}}',
		"the wrong next mission": '{"version": 1, "next": "west_gate", "done": ["batteries"], "ending_seen": false, "totals": {"kills": 0, "wrecks": 0, "seconds": 0}}',
		"missions out of order": '{"version": 1, "next": "west_gate", "done": ["pharmacist"], "ending_seen": false, "totals": {"kills": 0, "wrecks": 0, "seconds": 0}}',
		"no totals": '{"version": 1, "next": "pharmacist", "done": ["batteries"], "ending_seen": false}',
	}
	for name in cases:
		_clean()
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(cases[name])
		f.close()
		var d := SaveStore.load_save(path)
		var aside := _files_starting(DIR, "damaged.json.bad")
		_check(d.is_empty() and aside.size() == 1 and not FileAccess.file_exists(path), "a save with %s reads as no save and is kept aside" % name, str(aside))
		if aside.size() == 1:
			var kept := FileAccess.open(DIR + "/" + aside[0], FileAccess.READ)
			_check(kept != null and kept.get_as_text() == cases[name], "and the damaged file is kept as it was")
	_clean()
	var ok := _save_at("pharmacist")
	ok["totals"] = {"kills": 7, "wrecks": 2, "seconds": 311.5}
	SaveStore.write_save(ok, path)
	var back := SaveStore.load_save(path)
	_check(back["totals"]["kills"] == 7 and back["totals"]["seconds"] == 311.5 and back["done"] == ["batteries"], "a good save round trips with its totals")
	var all := _save_at("")
	all["done"] = ["batteries", "pharmacist", "west_gate"]
	all["ending_seen"] = true
	SaveStore.write_save(all, path)
	back = SaveStore.load_save(path)
	_check(not back.is_empty() and back["next"] == "" and back["ending_seen"] == true, "and so does a finished story")
	# Overwriting an existing save replaces it whole.
	SaveStore.write_save(ok, path)
	_check(SaveStore.load_save(path)["next"] == "pharmacist", "a second write replaces the first")


# ----------------------------------------------------------------------------- cities and chapters


## The story as it will be with a second chapter: today's three missions, then three in another city.
func _two_chapters() -> Array:
	var out: Array = StoryData.MISSIONS.duplicate()
	for k in 3:
		out.append({"id": "later_%d" % (k + 1), "title": "LATER %d" % (k + 1), "city": "harbour", "start": "", "dawn": 0.3, "begin": {}, "end": {}, "steps": []})
	return out


func _test_cities_and_chapters() -> void:
	var unknown: Array = []
	var elsewhere: Array = []
	for id in StoryData.PLACES:
		if not Cities.has(StoryData.PLACES[id]["city"]):
			unknown.append(id)
	for m in StoryData.MISSIONS:
		if not Cities.has(m["city"]):
			unknown.append(m["id"])
		var named: Array = [StoryData.start_place_id(m)]
		for s in m["steps"]:
			if s.has("place"):
				named.append(s["place"])
		for pid in named:
			if StoryData.place_city(pid) != m["city"]:
				elsewhere.append("%s: %s is in %s" % [m["id"], pid, StoryData.place_city(pid)])
	_check(unknown.is_empty(), "every place and every mission names a city the game has", str(unknown))
	_check(elsewhere.is_empty(), "and every place a mission uses is in the mission's own city", str(elsewhere))
	_check(StoryData.safe_start_id(Cities.QUARTER) == "safe_start" and StoryData.start_place_id(StoryData.MISSIONS[0]) == "safe_start" and StoryData.start_place_id(StoryData.MISSIONS[1]) == "shop", "a mission with no start place starts at its city's safe start")
	_check(Cities.layout(Cities.QUARTER) == CityLayout.DATA and Cities.model_path(Cities.QUARTER).ends_with("city.glb") and not Cities.has("nowhere"), "the registry hands out the quarter's layout and model")
	var ch := StoryData.chapters()
	_check(ch.size() == 1 and ch[0] == {"city": Cities.QUARTER, "first": 0, "last": 2}, "today's story is one chapter in the quarter", str(ch))
	var story := _two_chapters()
	ch = StoryData.chapters(story)
	_check(ch.size() == 2 and ch[0] == {"city": "quarter", "first": 0, "last": 2} and ch[1] == {"city": "harbour", "first": 3, "last": 5}, "a story with three missions in a second city is two chapters", str(ch))
	_check(StoryData.ends_chapter(2, story) and not StoryData.ends_chapter(3, story) and StoryData.ends_chapter(5, story) and StoryData.ends_chapter(2), "the third mission ends a chapter in both stories, the sixth ends the story")
	_check(StoryData.city_after(0, story) == "quarter" and StoryData.city_after(2, story) == "quarter" and StoryData.city_after(3, story) == "harbour" and StoryData.city_after(6, story) == "harbour" and StoryData.city_after(3) == "quarter", "the city a player is in follows the next mission, the last one's when the story is over")
	_check(StoryData.mission_city(4, story) == "harbour", "a mission's city is read from its row")


func _test_save_across_chapters() -> void:
	var story := _two_chapters()
	var path := DIR + "/chapters.json"
	var three := ["batteries", "pharmacist", "west_gate"]
	var finished := {"version": SaveStore.VERSION, "saved_at": 0, "next": "", "done": three, "ending_seen": true, "totals": {"kills": 4, "wrecks": 1, "seconds": 600.0}}
	_check(SaveStore.valid_save(finished) and SaveStore.upgraded(finished) == finished, "a save that finished the story is good as it is while the story has three missions")
	_check(SaveStore.valid_save(finished, story), "and once a second chapter exists it is still a good save, not a damaged one")
	var up := SaveStore.upgraded(finished, story)
	_check(up["next"] == "later_1" and up["done"] == three and up["ending_seen"] == true and up["totals"]["kills"] == 4, "it reads as chapter 2 next: the next mission is chapter 2's first, and what was done, seen and counted stays", str(up))
	_check(SaveStore.city_of(finished, story) == "harbour" and SaveStore.city_of(up, story) == "harbour", "so Continue would open the second city")
	_check(SaveStore.city_of(_save_at("pharmacist")) == "quarter" and SaveStore.city_of(_save_at("pharmacist"), story) == "quarter", "a save in the middle of chapter 1 still opens the quarter")
	# Saves a chapter-2 story writes.
	var mid := {"version": SaveStore.VERSION, "saved_at": 0, "next": "later_2", "done": three + ["later_1"], "ending_seen": true, "totals": {"kills": 0, "wrecks": 0, "seconds": 0.0}}
	var over := {"version": SaveStore.VERSION, "saved_at": 0, "next": "", "done": three + ["later_1", "later_2", "later_3"], "ending_seen": true, "totals": {"kills": 0, "wrecks": 0, "seconds": 0.0}}
	_check(SaveStore.valid_save(mid, story) and SaveStore.valid_save(over, story), "a save between chapter 2's missions and one at the end of the story are good")
	_check(SaveStore.city_of(mid, story) == "harbour" and SaveStore.city_of(over, story) == "harbour", "and both are in the second city")
	_check(not SaveStore.valid_save(mid) and not SaveStore.valid_save(over), "against today's three missions they are not (they name missions that do not exist)")
	# What is still damaged.
	var cases := {
		"empty next after one mission": {"next": "", "done": ["batteries"], "ending_seen": true},
		"empty next in the middle of chapter 1": {"next": "", "done": ["batteries", "pharmacist"], "ending_seen": true},
		"empty next, chapter 1 done, its ending never seen": {"next": "", "done": three, "ending_seen": false},
		"the wrong next after chapter 1": {"next": "later_3", "done": three, "ending_seen": true},
		"empty next with nothing done": {"next": "", "done": [], "ending_seen": true},
		"missions out of order": {"next": "later_1", "done": ["batteries", "west_gate", "pharmacist"], "ending_seen": true},
	}
	for name in cases:
		var d: Dictionary = {"version": SaveStore.VERSION, "saved_at": 0, "totals": {"kills": 0, "wrecks": 0, "seconds": 0.0}}
		d.merge(cases[name])
		_check(not SaveStore.valid_save(d, story), "a save with %s is still damaged with a second chapter" % name)
	# Through the file: the upgrade is made on loading, the file is not set aside.
	_clean()
	SaveStore.write_save(finished, path)
	var back := SaveStore.load_save(path, story)
	_check(back["next"] == "later_1" and FileAccess.file_exists(path) and _files_starting(DIR, "chapters.json.bad").is_empty(), "a finished save on disk loads as chapter 2 next and stays where it is")
	_check(SaveStore.load_save(path)["next"] == "", "and read against today's story it is as it was written")
	SaveStore.write_save(up, path)
	_check(SaveStore.load_save(path, story)["next"] == "later_1", "an upgraded save, written back, loads the same")
	_clean()


func _files_starting(dir: String, prefix: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.begins_with(prefix):
			out.append(f)
	return out


# ----------------------------------------------------------------------------- the gate and the night


## Mission 3 up to the gate opening, a car ready on the avenue facing the gate.
func _gate_open_sim() -> GameSim:
	var sim := _continued("west_gate")
	sim.take_events()
	_pick_up_both(sim)
	_run(sim, 61.0)
	return sim


func _toward_gate(sim: GameSim, seconds: float) -> Array:
	sim.place_car(Vector2(-45.0, 0.0), PI, GameSim.MAX_HULL)
	sim.car.body.velocity = Vector2(-15.0, 0.0)
	return _run(sim, seconds, {"throttle": 1.0, "turn": 0.0, "handbrake": false, "boost": false})


func _test_gate_trigger() -> void:
	var sim := _gate_open_sim()
	_check(sim.world.gate["open"], "the gate is open")
	var e := _toward_gate(sim, 3.0)
	_check(_has(e, "escaped") and sim.phase == GameSim.Phase.ESCAPED, "reaching the gate while it is open is the escape", "phase=%d" % sim.phase)
	_check(_has(e, "mission_complete") and _of(e, "mission_complete")[0]["final"] and "end_vera" in _lines(e) and "end_ruck" in _lines(e), "the last mission completes with Vera's and Ruck's closing lines", str(_lines(e)))
	_check(not _has(e, "story_complete") and not _has(e, "save"), "the story is not over, and nothing is saved, until the car has rolled out")
	var ending_prio := true
	for l in _of(e, "line"):
		if l["id"] in ["end_vera", "end_ruck"] and not l["priority"]:
			ending_prio = false
	_check(ending_prio, "and the closing lines jump the radio queue")
	var midway := GameSim.new(CityLayout.DATA, "bruiser", 7, true)
	midway.continue_story(sim.mission.last_save)
	_check(midway.mission.objective()["kind"] == "start" and midway.mission.objective()["place"] == "hut", "quitting during the roll-out resumes at mission 3's start, not in an empty roam")
	e = _run(sim, GameSim.ESCAPE_MAX_TIME + 0.5)
	var saves := _of(e, "save")
	_check(_has(e, "story_complete") and saves.size() == 1 and saves[0]["data"]["ending_seen"] == true and saves[0]["data"]["next"] == "", "the story completes and asks for a final save", str(_of(e, "story_complete")))
	var rest: Vector2 = sim.car.body.position
	_check(absf(rest.x - (float(sim.world.arena["left"]) - GameSim.ESCAPE_DISTANCE)) < 0.5 and absf(rest.y) < 0.5 and sim.car.speed() < 0.1, "the car has gone out through the gate to its resting place on the road outside", "at %s v=%.2f" % [str(rest), sim.car.speed()])
	var fled := true
	for g in sim.pack.gaunts:
		if g.alive():
			fled = false
	_check(fled, "the survivors flee")
	# With the gate shut the wall holds, and nothing ends.
	var shut := _continued("west_gate")
	shut.take_events()
	_pick_up_both(shut)
	e = _toward_gate(shut, 4.0)
	_check(not _has(e, "escaped") and shut.phase == GameSim.Phase.PLAYING and shut.car.body.position.x >= shut.world.arena["left"], "with the gate shut the wall holds the car", "x=%.1f" % shut.car.body.position.x)
	_check(_has(e, "crash") and shut.hull < GameSim.MAX_HULL, "and the car pays for it")


func _test_open_gate_gap() -> void:
	# The gap in the wall itself, without the story: open, a car in its width goes through;
	# a car beside it, or a shut gate, is held.
	var open := GameSim.new(CityLayout.DATA, "bruiser", 7)
	open.pack.gaunts.clear()
	open.pack.director_on = false
	open.world.gate["open"] = true
	open.place_car(Vector2(-60.0, 0.0), PI, GameSim.MAX_HULL)
	open.car.body.velocity = Vector2(-15.0, 0.0)
	_run(open, 3.0, {"throttle": 1.0, "turn": 0.0, "handbrake": false, "boost": false})
	_check(open.car.body.position.x < -75.0 and open.hull == GameSim.MAX_HULL, "an open gate lets a car through its gap", "x=%.1f" % open.car.body.position.x)
	var beside := GameSim.new(CityLayout.DATA, "bruiser", 7)
	beside.pack.gaunts.clear()
	beside.pack.director_on = false
	beside.world.gate["open"] = true
	beside.place_car(Vector2(-60.0, 20.0), PI, GameSim.MAX_HULL)
	beside.car.body.velocity = Vector2(-15.0, 0.0)
	_run(beside, 3.0, {"throttle": 1.0, "turn": 0.0, "handbrake": false, "boost": false})
	_check(beside.car.body.position.x >= -70.0, "but the wall beside the gap holds", "x=%.1f" % beside.car.body.position.x)


func _test_gate_needs_the_gap() -> void:
	var sim := _gate_open_sim()
	# Inside the 6 m trigger radius but 4.5 m off the gate's centre line: beside the gap, not in it.
	sim.place_car(Vector2(-67.0, 4.5), PI, GameSim.MAX_HULL)
	sim.car.body.velocity = Vector2(-10.0, 0.0)
	var e := _run(sim, 1.5, {"throttle": 1.0, "turn": 0.0, "handbrake": false, "boost": false})
	_check(not _has(e, "escaped") and sim.phase == GameSim.Phase.PLAYING and sim.car.body.position.x >= sim.world.arena["left"], "beside the gap the trigger does not fire and the wall holds", "x=%.1f y=%.1f" % [sim.car.body.position.x, sim.car.body.position.y])
	sim.place_car(Vector2(-67.0, 2.0), PI, GameSim.MAX_HULL)
	sim.car.body.velocity = Vector2(-10.0, 0.0)
	e = _run(sim, 0.5, {"throttle": 1.0, "turn": 0.0, "handbrake": false, "boost": false})
	_check(_has(e, "escaped"), "lined up with the gap it does")


## Crossing the gate must not change how fast the car is going: the roll-out starts at its own speed.
func _test_escape_keeps_the_speed() -> void:
	for v0 in [30.0, 14.0, 6.0, 0.5]:
		var sim := _story()
		sim.take_events()
		sim.world.gate["open"] = true
		sim.place_car(Vector2(-66.0, 0.5), PI, GameSim.MAX_HULL)
		sim.car.body.velocity = Vector2(-v0, 0.0)
		sim.escape()
		var worst := 0.0
		var prev := sim.car.speed()
		var first := -1.0
		for i in int(round((GameSim.ESCAPE_MAX_TIME + 0.5) / DT)):
			sim.step(DT, IDLE)
			sim.take_events()
			var v := sim.car.speed()
			if first < 0.0:
				first = v
			worst = maxf(worst, absf(v - prev))
			prev = v
		var rest: Vector2 = sim.car.body.position
		_check(absf(first - v0) < v0 * 0.08 + 0.3 and worst < 0.5, "a car crossing the gate at %d m/s rolls on at that speed, no snap" % int(v0), "first step %.1f, worst change per step %.2f m/s" % [first, worst])
		_check(absf(rest.x - (float(sim.world.arena["left"]) - GameSim.ESCAPE_DISTANCE)) < 0.5 and sim.car.speed() < 0.1 and sim.escape_time <= GameSim.ESCAPE_MAX_TIME, "and still comes to rest on the road outside", "rest %s after %.1f s" % [str(rest), sim.escape_time])


func _test_camera_through_the_gap() -> void:
	var sim := _story()
	var from := Vector3(-66.0, 1.8, 0.0)
	var to := Vector3(-80.0, 4.0, 0.0)  # outside the wall, straight through the gate
	var shut := ChaseCamera.clear_fraction(sim.world, from, to, 0.45)
	sim.world.gate["open"] = true
	var open := ChaseCamera.clear_fraction(sim.world, from, to, 0.45)
	var beside := ChaseCamera.clear_fraction(sim.world, Vector3(-66.0, 1.8, -12.0), Vector3(-80.0, 4.0, -12.0), 0.45)
	_check(shut < 1.0 and open == 1.0 and beside < 1.0, "the chase camera sees through an open gate and not through the wall beside it", "shut=%.2f open=%.2f beside=%.2f" % [shut, open, beside])


func _test_restart_closes_the_gate() -> void:
	var sim := _gate_open_sim()
	sim.restart_mission()
	var e := sim.take_events()
	_check(_has(e, "gate_closed") and not sim.world.gate["open"], "restarting a mission with the gate open says it shut")
	var late := _gate_open_sim()
	var e2 := _run(late, 21.0)
	_check(_has(e2, "gate_closed") and _of(e2, "gate_closed").size() == 1, "a failed run says it once")


func _test_hunters_not_in_the_car() -> void:
	var worst := INF
	for seed_in in [1, 2, 3, 4, 5, 6, 7, 8]:
		var sim := _continued("pharmacist", seed_in)
		sim.take_events()
		_at(sim, "shop", -PI / 2.0)
		_run(sim, 0.1)
		# The car pulls up on the ring side nearest a bearing the old code could have picked.
		sim.place_car(StoryData.place_pos("pharmacy") + Vector2(4.0, 0.5), PI, GameSim.MAX_HULL)
		_run(sim, 0.01)
		for g in sim.pack.gaunts:
			worst = minf(worst, g.pos.distance_to(sim.car.body.position))
		_check(sim.pack.gaunts.size() == 1, "seed %d: one hunter to begin with" % seed_in, "n=%d" % sim.pack.gaunts.size())
		_run(sim, 9.01)
		var newest: GauntSim = sim.pack.gaunts.back()
		worst = minf(worst, newest.pos.distance_to(sim.car.body.position))
		_check(sim.pack.gaunts.size() == 2, "seed %d: the second arrives" % seed_in, "n=%d" % sim.pack.gaunts.size())
	_check(worst >= 4.5, "the pharmacy hunters never appear inside or on top of the car", "nearest=%.1f m" % worst)
	# Placed where the car can reach them: out in the street, not pinned against the tower's wall.
	var tight := 0
	for seed_in in [1, 2, 3, 4, 5, 6, 7, 8]:
		var sim := _continued("pharmacist", seed_in)
		sim.take_events()
		_at(sim, "shop", -PI / 2.0)
		_run(sim, 0.1)
		_at(sim, "pharmacy")
		_run(sim, 0.1)
		for g in sim.pack.gaunts:
			if sim.world.wall_gap(g.pos, MissionSim.WALL_GAP) < MissionSim.WALL_GAP - 1.5:
				tight += 1
	_check(tight == 0, "and they stand clear of the walls, where the car can get at them", "against a wall=%d" % tight)


func _test_no_dawn_clock() -> void:
	var sim := _story()
	sim.take_events()
	var e := _run(sim, GameSim.NIGHT_LENGTH + 10.0)
	_check(not _has(e, "dawn") and sim.phase == GameSim.Phase.PLAYING, "story mode has no dawn clock", "time=%.0f phase=%d" % [sim.time, sim.phase])
	var survival := GameSim.new(CityLayout.DATA, "bruiser", 7)
	_check(survival.mission == null and not survival.story_mode, "and Survive the Night is the same game without a story")


# ----------------------------------------------------------------------------- the pack's story hooks


func _lurker(sim: GameSim, p: Vector2) -> GauntSim:
	var g := GauntSim.new()
	g.id = sim.pack.next_id
	sim.pack.next_id += 1
	g.pos = p
	g.state = GauntSim.State.LURK
	sim.pack.gaunts.append(g)
	return g


func _test_pack_hooks() -> void:
	var sim := GameSim.new(CityLayout.DATA, "bruiser", 7)
	sim.pack.gaunts.clear()
	sim.pack.director_on = false
	var near := _lurker(sim, Vector2(-30.0, 0.0))
	var far := _lurker(sim, Vector2(30.0, 0.0))
	var n := sim.pack.alert_near(Vector2(-60.0, 0.0), 50.0)
	_check(n == 1 and near.alert and near.state == GauntSim.State.STALK and not far.alert and far.state == GauntSim.State.LURK, "an alert reaches only the Gaunts inside its radius", "n=%d" % n)
	_check(sim.pack.alert_all() == 2 and far.alert, "and alerting all reaches every one")
	sim.pack.gaunts.clear()
	var g := sim.pack.place_hunting(Vector2(10.0, 12.0), sim.car)
	_check(sim.pack.gaunts.size() == 1 and g.state == GauntSim.State.HUNT and g.alert and g.pos.distance_to(Vector2(10.0, 12.0)) < 3.0, "a Gaunt can be placed at a point, already hunting", "state=%d at %s" % [g.state, str(g.pos)])
	# The pack's size is the story's to set: the director fills up to it and stops.
	var sized := GameSim.new(CityLayout.DATA, "bruiser", 7)
	sized.pack.gaunts.clear()
	sized.pack.set_size(5)
	for i in int(40.0 / DT):
		sized.pack.step(DT, sized.car)
	_check(sized.pack.alive_count() == 5, "the director holds the pack at a size set from outside", "alive=%d" % sized.pack.alive_count())
	sized.pack.set_size(6)
	sized.pack.alert_all()
	for i in int(10.0 / DT):
		sized.pack.step(DT, sized.car)
	var all_alert := true
	for o in sized.pack.gaunts:
		if o.alive() and o.state == GauntSim.State.STALK and not o.alert:
			all_alert = false
	_check(sized.pack.alive_count() == 6 and all_alert, "a bigger size brings more in, alerted after an alert-all", "alive=%d" % sized.pack.alive_count())
	var quiet := GameSim.new(CityLayout.DATA, "bruiser", 7)
	quiet.pack.gaunts.clear()
	quiet.pack.director_on = false
	for i in int(20.0 / DT):
		quiet.pack.step(DT, quiet.car)
	_check(quiet.pack.alive_count() == 0, "with the director off nothing is spawned")


# ----------------------------------------------------------------------------- the whole story, driven


func _test_whole_story_driven() -> void:
	for seed_in in [7, 3]:
		_drive_story(seed_in, false)
	# The guard against a story that cannot be finished: the creatures the story places are LIVE (they pounce,
	# take hold and have to be run down), the director is off and the hull is held at full, so only the timers
	# and the missions' own steps can stop the autopilot. It must finish every mission inside its timers with
	# room to spare. (This is what the stunned route check above cannot see.)
	for seed_in in [7, 3, 11, 1, 4]:
		_drive_story(seed_in, true)


func _drive_story(seed_in: int, live: bool) -> void:
	var sim := _story(seed_in)
	var pilot := Autopilot.new()
	var log: Array = []
	var failed := false
	var complete := false
	var marks := {}
	var left := 0.0
	var shutter_margin := -1.0
	var latches := 0
	var steps := int(600.0 / DT)
	for i in steps:
		if live:
			sim.hull = GameSim.MAX_HULL
			var tl := sim.mission.timers_left()
			if not tl.is_empty() and tl[0]["id"] == "shutter":
				left = float(tl[0]["left"])
		else:
			# The route check: the creatures the story places lie where they are (stunned: they cannot pounce or
			# take hold, and can be run down at speed), so it proves each mission can be finished by driving.
			for g in sim.pack.gaunts:
				if g.alive() and g.state != GauntSim.State.DOWN:
					g.set_state(GauntSim.State.DOWN)
				g.stun = 999.0
		sim.step(DT, pilot.controls(sim, DT))
		for e in sim.take_events():
			match e["type"]:
				"mission_complete":
					log.append(e["id"])
					marks[e["id"]] = int(sim.time)
				"mission_failed":
					failed = true
					print("  failed: ", e["id"], " ", e["reason"], " at ", int(sim.time))
				"timer":
					if e["state"] == "stop" and e["id"] == "shutter":
						shutter_margin = left
				"latch":
					latches += 1
				"story_complete":
					complete = true
		if complete or failed:
			break
	var what := "with the creatures lying stunned" if not live else "with the story's creatures live and the hull held"
	_check(log == ["batteries", "pharmacist", "west_gate"] and complete and not failed, "seed %d: the autopilot drives all three missions to the end %s" % [seed_in, what], "log=%s t=%.0f latches=%d" % [str(marks), sim.time, latches])
	_check(sim.time < 600.0, "within ten simulated minutes", "t=%.0f hull=%.0f kills=%d" % [sim.time, sim.hull, sim.kills])
	if live:
		_check(shutter_margin >= 15.0, "seed %d: and with the shutter still holding for at least 15 s to spare" % seed_in, "margin %.0f s of %.0f" % [shutter_margin, StoryData.SHUTTER_SECONDS])

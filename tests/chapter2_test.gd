extends Node
## Headless checks on the rest of chapter 2 in the harbour city: Dead Convoy, Floodlights and The Lift Bridge up to
## the control house. Every leg is a long drive by road, the ambushes sit on the legs and spring only within range,
## the floodlights timer fails and retries as it should, Continue puts the car at each mission's start, the radar
## widens and the route is there, and the autopilot drives all of it.
##
##   godot --headless --path . res://tests/chapter2_test.tscn
##
## Fixed seeds, no window.

const DT := 1.0 / 120.0
const MIN_LEG := 300.0  # m by road (option 04)
const MIN_BRIDGE_RUN := 450.0  # the run to the lift bridge
const CHAPTER := ["dead_convoy", "floodlights", "lift_bridge"]

var failures := 0


func _ready() -> void:
	_test_legs()
	_test_ambushes()
	_test_floodlights()
	_test_floodlights_dim()
	_test_bridge_view()
	_test_continue_places()
	_test_radar_and_route()
	_test_lift_bridge_crossing()
	_test_legacy_save()
	_test_autopilot_chapter()
	print("")
	print("chapter2_test: %d failed" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, name: String, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL "), name, ("  " + detail) if detail != "" else "")
	if not ok:
		failures += 1


func _sim(seed_in: int = 7) -> GameSim:
	var g := GameSim.new(Cities.layout(Cities.HARBOUR), "bruiser", seed_in, true, Cities.HARBOUR)
	return g


func _idle(sim: GameSim, seconds: float) -> void:
	for i in int(seconds / DT):
		sim.step(DT, {"throttle": 0.0, "turn": 0.0, "handbrake": false, "boost": false})
		sim.take_events()


func _length(path: PackedVector2Array) -> float:
	var n := 0.0
	for i in range(1, path.size()):
		n += path[i].distance_to(path[i - 1])
	return n


func _near_path(path: PackedVector2Array, p: Vector2, d: float) -> bool:
	for i in range(1, path.size()):
		var ab := path[i] - path[i - 1]
		var t := clampf((p - path[i - 1]).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if p.distance_to(path[i - 1] + ab * t) <= d:
			return true
	return false


# ----------------------------------------------------------------------------- the legs

## The places a mission visits in order, from its start place, with consecutive repeats (a hold at the place just reached)
## taken out: its legs are the drives between them.
func _legs_of(m: Dictionary) -> Array:
	var places: Array = [StoryData.start_place_id(m)]
	for s in m["steps"]:
		if s.has("place") and s["place"] != places[-1]:
			places.append(s["place"])
	var out: Array = []
	for i in range(1, places.size()):
		out.append([places[i - 1], places[i]])
	return out


func _test_legs() -> void:
	var sim := _sim()
	var layout: Dictionary = Cities.layout(Cities.HARBOUR)
	var short: Array = []
	var unrouted: Array = []
	var quiet: Array = []
	var count := 0
	var table: Array = []
	for id in CHAPTER:
		var m: Dictionary = StoryData.MISSIONS[StoryData.mission_index(id)]
		for leg in _legs_of(m):
			if StoryData.PLACES[leg[1]].get("needs_bridge", false):
				continue  # the crossing: the bridge is down for it (tested below)
			count += 1
			var path := sim.route_to(StoryData.place_pos(leg[0]), StoryData.place_pos(leg[1]))
			var len := _length(path)
			table.append("%s %s to %s %.0f m" % [id, leg[0], leg[1], len])
			if path.is_empty():
				unrouted.append("%s: %s to %s" % [id, leg[0], leg[1]])
				continue
			var need := MIN_BRIDGE_RUN if leg[1] == "control_house" else MIN_LEG
			if len < need:
				short.append("%s: %s to %s %.0f m (needs %.0f)" % [id, leg[0], leg[1], len, need])
			# Every leg's way crosses a roadblock or a bridge.
			var crosses := false
			for rb in layout["roadblocks"]:
				var at := Vector2(float(rb["pos"]), float(rb["c"])) if rb["axis"] == "x" else Vector2(float(rb["c"]), float(rb["pos"]))
				if _near_path(path, at, 9.0):
					crosses = true
			for br in layout["bridges"]:
				if _near_path(path, Vector2(float(br["x"]), float(br["y"])), 6.0):
					crosses = true
			if not crosses:
				quiet.append("%s: %s to %s" % [id, leg[0], leg[1]])
	print("  legs: ", "; ".join(table))
	_check(count >= 7 and unrouted.is_empty(), "every chapter 2 leg has a route on the car's path grid", "%d legs, no route: %s" % [count, str(unrouted)])
	_check(short.is_empty(), "every leg is at least 300 m by road, and the run to the lift bridge at least 450", str(short))
	_check(quiet.is_empty(), "and every leg's way crosses a roadblock or a bridge", str(quiet))
	# Every place a chapter 2 mission uses is reachable from the highway checkpoint on that grid.
	var lost: Array = []
	for pid in StoryData.PLACES:
		if pid != "highway_start" and not StoryData.PLACES[pid].get("needs_bridge", false) and StoryData.PLACES[pid]["city"] == Cities.HARBOUR and sim.route_to(StoryData.place_pos("highway_start"), StoryData.place_pos(pid)).is_empty():
			lost.append(pid)
	_check(lost.is_empty(), "and every chapter 2 place is reachable by road", str(lost))
	# The checker's own planned legs (the generator's plan) agree with the story's places.
	var plan_ok := true
	for leg in Cities.layout(Cities.HARBOUR)["planned_legs"]:
		var a: Dictionary = Cities.layout(Cities.HARBOUR)["places"][leg["a"]]
		if leg["a"] in StoryData.PLACES and Vector2(float(a["x"]), float(a["y"])).distance_to(StoryData.place_pos(leg["a"])) > 20.0:
			plan_ok = false
	_check(plan_ok, "and the story's places are where the generator planned them")


# ----------------------------------------------------------------------------- ambushes

func _test_ambushes() -> void:
	var sim := _sim()
	var a := StoryData.place_pos("convoy_call")
	var b := StoryData.place_pos("ruck_truck")
	var route := sim.route_to(a, b)
	var picks := sim.ambushes_on(route, 2, 35.0)
	_check(picks.size() >= 1 and picks.size() <= 2, "a leg has one or two ambushes", "%d" % picks.size())
	var ok := true
	for p in picks:
		if not _near_path(route, p["pos"], 16.0) or p["pos"].distance_to(a) < 55.0 or p["pos"].distance_to(b) < 25.0:
			ok = false
	_check(ok, "each beside the route, not at its ends")
	var apart := picks.size() < 2 or (picks[0]["pos"] as Vector2).distance_to(picks[1]["pos"]) > 40.0
	_check(apart, "and apart from each other")
	var layout_ids: Array = Cities.layout(Cities.HARBOUR)["ambush_spots"].map(func(s: Dictionary) -> String: return s["id"])
	_check("bridge_0" in layout_ids and "rb_avenue_east" in layout_ids, "the layout has ambush spots at squeezes, roadblocks and bridges", str(layout_ids.size()))
	# They spring within range, and only then.
	var g := _sim()
	g.start_story_at(4)
	g.pack.director_on = false
	g.pack.gaunts.clear()
	_check(g.mission.mission_data()["id"] == "dead_convoy" and g.pack.stalled.size() >= 1, "Dead Convoy arms its leg's ambushes when it begins", "armed=%d" % g.pack.stalled.size())
	var first: Dictionary = g.pack.stalled[0]
	var spot: Vector2 = first["pos"]
	g.place_car(spot + Vector2(StoryData.AMBUSH_RELEASE + 8.0, 0.0), PI, GameSim.MAX_HULL)
	_idle(g, 1.0)
	_check(g.pack.gaunts.is_empty(), "nothing springs while the car is outside the release distance")
	var armed_before := g.pack.stalled.size()
	g.place_car(spot + Vector2(StoryData.AMBUSH_RELEASE - 8.0, 0.0), PI, GameSim.MAX_HULL)
	_idle(g, 0.1)
	_check(g.pack.gaunts.size() == int(first["count"]) and g.pack.stalled.size() == armed_before - 1, "and within it the spot's creatures are placed, hunting, once", "gaunts=%d" % g.pack.gaunts.size())
	_check(g.pack.gaunts.all(func(x: GauntSim) -> bool: return x.pos.distance_to(spot) < 6.0), "round the spot")
	_idle(g, 0.5)
	_check(g.pack.gaunts.size() == int(first["count"]), "and not again")
	# The quarter has none.
	var q := GameSim.new(CityLayout.DATA, "bruiser", 7, true)
	_check(q.route_to(Vector2(0, 0), Vector2(30, 0)).is_empty() and q.world.ambush_spots.is_empty() and q.pack.stalled.is_empty(), "the quarter has no route grid and no ambush spots: chapter 1 is as it was")


# ----------------------------------------------------------------------------- the floodlights

func _test_floodlights() -> void:
	var g := _sim()
	g.start_story_at(5)
	g.pack.director_on = false
	g.pack.gaunts.clear()
	g.pack.stalled = []
	var t: Array = g.mission.timers_left()
	_check(g.mission.mission_data()["id"] == "floodlights" and t.size() == 1 and t[0]["id"] == "floodlights" and is_equal_approx(float(t[0]["total"]), StoryData.FLOODLIGHT_SECONDS), "Floodlights starts its timer with the call", str(t))
	# Time runs out: the mission fails with its reason and its line.
	g.mission.timers["floodlights"]["left"] = 0.01
	var events: Array = []
	for i in 6:
		g.step(DT, {"throttle": 0.0, "turn": 0.0, "handbrake": false, "boost": false})
		events.append_array(g.take_events())
	var failed: Array = events.filter(func(e: Dictionary) -> bool: return e["type"] == "mission_failed")
	var lines: Array = events.filter(func(e: Dictionary) -> bool: return e["type"] == "line").map(func(e: Dictionary) -> String: return e["id"])
	_check(failed.size() == 1 and failed[0]["reason"] == "floodlights" and "fl_failed" in lines, "when it runs out the floodlights fail the mission, with Teo's cry", str(failed))
	_check(failed[0]["text"] == StoryData.REASONS["floodlights"]["text"], "and the fail screen says why")
	# A retry from the checkpoint at the depot brings back the time that was left then.
	var h := _sim()
	h.start_story_at(5)
	h.pack.director_on = false
	h.pack.gaunts.clear()
	h.pack.stalled = []
	for pid in ["fuel_depot"]:
		h.place_car(StoryData.place_pos(pid), PI, GameSim.MAX_HULL)
		_idle(h, 4.6)
	_check(h.mission.checkpoint.has("timers") and not h.mission.checkpoint["timers"].is_empty(), "the checkpoint at the depot keeps the timer", str(h.mission.checkpoint.get("step")))
	var at_cp := float(h.mission.timers["floodlights"]["left"])
	h.mission.timers["floodlights"]["left"] = 0.01
	_idle(h, 0.1)
	_check(h.mission.state == MissionSim.State.FAILED, "the timer runs out after it")
	h.retry_mission()
	h.take_events()
	var back: Array = h.mission.timers_left()
	_check(back.size() == 1 and absf(float(back[0]["left"]) - at_cp) < 1.0, "and a retry restores the time that was left at the checkpoint, not a fresh clock and not none", "%s vs %.1f" % [str(back), at_cp])
	# Finishing the last generator stops the timer and completes the mission.
	var f := _sim()
	f.start_story_at(5)
	f.pack.director_on = false
	f.pack.gaunts.clear()
	f.pack.stalled = []
	var evs: Array = []
	for pid in ["fuel_depot", "fuel_depot", "post_north", "post_centre_west", "post_east"]:
		f.place_car(StoryData.place_pos(pid), PI, GameSim.MAX_HULL)
		for i in int(4.6 / DT):
			f.step(DT, {"throttle": 0.0, "turn": 0.0, "handbrake": false, "boost": false})
			evs.append_array(f.take_events())
	var done: Array = evs.filter(func(e: Dictionary) -> bool: return e["type"] == "mission_complete")
	var said: Array = evs.filter(func(e: Dictionary) -> bool: return e["type"] == "line").map(func(e: Dictionary) -> String: return e["id"])
	_check(done.size() == 1 and done[0]["id"] == "floodlights" and not done[0]["final"], "the third generator completes Floodlights", str(done))
	_check(said.has("fl_loaded") and said.has("fl_post_1") and said.has("fl_post_2") and said.has("fl_done"), "with a line at each generator and the last one at the end", str(said))
	_check(f.mission.timers_left().is_empty(), "and the timer is stopped")


## The field hospital's floodlights are tagged in the layout; the city dims them by their tag's level.
func _test_floodlights_dim() -> void:
	var city := City.new()
	add_child(city)
	city.build(Cities.layout(Cities.HARBOUR), Cities.model_path(Cities.HARBOUR))
	var tagged: Array = city.lights.filter(func(l: Dictionary) -> bool: return l["tag"] == "hospital_flood")
	_check(tagged.size() == 4, "the city knows the four floodlights by their tag", "%d" % tagged.size())
	var full := float(tagged[0]["node"].light_energy)
	city.tag_levels["hospital_flood"] = 0.5
	city._process(0.016)
	var half := float(tagged[0]["node"].light_energy)
	city.tag_levels["hospital_flood"] = 0.0
	city._process(0.016)
	var out := float(tagged[0]["node"].light_energy)
	_check(half < full * 0.6 and half > 0.0 and out == 0.0, "and dims them with the level, to nothing at zero", "%.2f, %.2f, %.2f" % [full, half, out])
	var others_ok := city.lights.filter(func(l: Dictionary) -> bool: return l["tag"] != "hospital_flood" and l["flicker"] <= 0.0).all(func(l: Dictionary) -> bool: return float(l["node"].light_energy) > 0.0)
	_check(others_ok, "no other light goes out with them")
	city.queue_free()


## The lift bridge on screen: its deck and cables are pieces of the model, the deck comes down onto the road level and the
## cables stretch with it; the harbour city has a bridge to draw and so no west gate's leaves, the quarter the reverse.
func _test_bridge_view() -> void:
	var city := City.new()
	add_child(city)
	city.build(Cities.layout(Cities.HARBOUR), Cities.model_path(Cities.HARBOUR))
	var view := BridgeView.new()
	add_child(view)
	view.setup(city, Cities.layout(Cities.HARBOUR))
	_check(view.deck != null and view.cables != null and view.lamps.size() == 4, "the model has the lift bridge's deck and cables as pieces of their own, and the view has four lamps")
	var up_y := view.deck.position.y
	view.set_down(true, true)
	var rec: Dictionary = Cities.layout(Cities.HARBOUR)["bridges"].filter(func(b: Dictionary) -> bool: return b["kind"] == "lift")[0]
	_check(is_equal_approx(up_y, 0.0) and absf(view.deck.position.y + float(rec["deck_up_z"])) < 0.01, "lowered, the deck has come down by exactly its height above the road", "%.2f" % view.deck.position.y)
	var deck_top: float = float(rec["deck_up_z"]) + view.deck.position.y
	var cable_len: float = (float(rec["cable_top_z"]) - float(rec["deck_up_z"])) * view.cables.scale.y
	_check(absf(deck_top) < 0.01 and absf(float(rec["cable_top_z"]) - deck_top - cable_len) < 0.01, "and the cables reach from the beam down to it", "%.2f" % cable_len)
	view.set_down(false, true)
	_check(is_equal_approx(view.deck.position.y, 0.0) and is_equal_approx(view.cables.scale.y, 1.0), "raised, both are back where the model has them")
	view.set_down(true)
	view._process(1.0)
	_check(view.moving() and view.down_amount > 0.0 and view.down_amount < 0.2, "coming down takes nine seconds", "%.2f after one" % view.down_amount)
	_check(not _sim().world.lift_closers.is_empty() and GameSim.new(CityLayout.DATA, "bruiser", 1, true).world.lift_closers.is_empty(), "the harbour city has a lift bridge and the quarter none, which is how the game picks the bridge's view or the gate's")
	view.queue_free()
	city.queue_free()


# ----------------------------------------------------------------------------- Continue and the radar

func _test_continue_places() -> void:
	var cases := {"dead_convoy": "convoy_call", "floodlights": "field_hospital", "lift_bridge": "field_hospital"}
	for id in cases:
		var done: Array = []
		for m in StoryData.MISSIONS:
			if m["id"] == id:
				break
			done.append(m["id"])
		var sim := _sim()
		sim.continue_story({"version": SaveStore.VERSION, "saved_at": 0, "next": id, "done": done, "ending_seen": true, "totals": {"kills": 0, "wrecks": 0, "seconds": 0.0}})
		_check(sim.car.body.position.distance_to(StoryData.place_pos(cases[id])) < 0.1, "Continue with %s next puts the car at %s, the mission's start" % [id, cases[id]])
		_idle(sim, 0.1)
		_check(sim.mission.active() and sim.mission.mission_data()["id"] == id, "and the mission begins there")


func _test_radar_and_route() -> void:
	var view := MapView.new()
	view.size = Vector2(240, 240)
	add_child(view)
	view.set_city(Cities.HARBOUR)
	for i in 120:
		view.set_state(Vector2.ZERO, 0.0, [], 0.0)
	var slow := view.radar_range
	for i in 120:
		view.set_state(Vector2.ZERO, 0.0, [], 45.0)
	var fast := view.radar_range
	_check(absf(slow - MapView.RADAR_RANGE) < 1.0 and absf(fast - MapView.RADAR_RANGE_FAST) < 1.0, "the radar reaches about 60 m crawling and about 110 m flat out in the harbour city", "%.1f and %.1f" % [slow, fast])
	view.set_city(Cities.QUARTER)
	view.radar_range = MapView.RADAR_RANGE
	for i in 120:
		view.set_state(Vector2.ZERO, 0.0, [], 45.0)
	_check(absf(view.radar_range - MapView.RADAR_RANGE) < 0.01, "and in the quarter it stays at 60 m: chapter 1 is as it was")
	view.queue_free()
	var sim := _sim()
	sim.start_story_at(4)
	var route := sim.route_to(sim.car.body.position, StoryData.place_pos("ruck_truck"))
	_check(route.size() >= 3 and route[0].distance_to(sim.car.body.position) < 3.0 and route[-1].distance_to(StoryData.place_pos("ruck_truck")) < 3.0, "the route line runs from the car to the objective along the streets", "%d points, %.0f m" % [route.size(), _length(route)])
	var clear := true
	for i in range(1, route.size()):
		if not sim.world.line_clear(route[i - 1], route[i], 0.9):
			clear = false
	_check(clear and route.size() <= 80, "it is short enough to draw and every stretch of it is drivable", "%d points" % route.size())


# ----------------------------------------------------------------------------- the bridge and the end

func _quiet(sim: GameSim) -> void:
	sim.pack.director_on = false
	sim.pack.gaunts.clear()
	sim.pack.stalled = []
	sim.take_events()


func _run_for(sim: GameSim, seconds: float, events: Array) -> void:
	for i in int(seconds / DT):
		sim.step(DT, {"throttle": 0.0, "turn": 0.0, "handbrake": false, "boost": false})
		events.append_array(sim.take_events())


func _types(events: Array) -> Array:
	return events.map(func(e: Dictionary) -> String: return e["type"])


func _lines(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == "line").map(func(e: Dictionary) -> String: return e["id"])


## The hold at the control house: the bridge stays up while Teo works, comes down when it ends (its colliders leave the
## world and the road opens), the timer starts, and it all goes back if the bridge lifts again.
func _test_lift_bridge_crossing() -> void:
	var sim := _sim()
	sim.start_story_at(6)
	_quiet(sim)
	var events: Array = []
	sim.place_car(StoryData.place_pos("field_hospital"), PI, GameSim.MAX_HULL)
	_run_for(sim, 4.6, events)
	sim.place_car(StoryData.place_pos("control_house"), PI, GameSim.MAX_HULL)
	_run_for(sim, 6.0, events)
	_check(sim.mission.step_data()["id"] == "work" and not sim.world.lift_down, "holding at the control house the bridge is still up", str(sim.mission.step_data().get("id")))
	_check(sim.route_to(StoryData.place_pos("control_house"), StoryData.place_pos("lift_gate")).is_empty(), "and there is no road from the control house to the far bank (its colliders shut it)")
	var boxes_up := sim.world.boxes.size()
	_run_for(sim, 10.0, events)
	var types := _types(events)
	_check(sim.mission.step_data()["id"] == "cross" and sim.world.lift_down and types.has("bridge") and types.has("gate_open"), "the hold ends: the bridge comes down and the gate opens", str(sim.mission.step_data().get("id")))
	_check(sim.world.boxes.size() == boxes_up - 2, "the two colliders that shut the bridge's road are gone", "%d to %d" % [boxes_up, sim.world.boxes.size()])
	var route := sim.route_to(StoryData.place_pos("control_house"), StoryData.place_pos("lift_gate"))
	_check(route.size() >= 2 and _length(route) < 140.0, "and the way to the far bank's gate is open, about 83 m", "%.0f m" % _length(route))
	_check("lb_down" in _lines(events) and sim.mission.timers_left().size() == 1 and sim.mission.timers_left()[0]["id"] == "bridge", "with Teo's call and a short timer", str(sim.mission.timers_left()))
	var cp: Dictionary = sim.mission.checkpoint
	_check(not cp.is_empty() and int(cp["step"]) == 3, "the hold's end is a checkpoint, at the crossing")
	# The timer runs out: the bridge rises, the gate shuts, the mission fails with its line.
	sim.mission.timers["bridge"]["left"] = 0.01
	var more: Array = []
	_run_for(sim, 0.2, more)
	var failed: Array = more.filter(func(e: Dictionary) -> bool: return e["type"] == "mission_failed")
	_check(failed.size() == 1 and failed[0]["reason"] == "bridge" and "lb_failed" in _lines(more), "when it runs out the bridge lifts again and the mission fails", str(failed))
	_check(not sim.world.lift_down and _types(more).has("gate_closed") and sim.world.boxes.size() == boxes_up, "the colliders come back and the gate shuts")
	# Retry: back at the control house, the bridge comes down again and the timer starts again.
	var retry_events: Array = []
	sim.retry_mission()
	retry_events.append_array(sim.take_events())
	_run_for(sim, 0.1, retry_events)
	_check(sim.mission.step_data()["id"] == "cross" and sim.world.lift_down and sim.mission.timers_left().size() == 1 and float(sim.mission.timers_left()[0]["left"]) > 40.0, "a retry begins at the crossing with the bridge down and a fresh timer", str(sim.mission.timers_left()))
	# Crossing: the car in the gate's gap while it is open is the escape; the story is over.
	var end_events: Array = []
	sim.place_car(Vector2(-195.0, -144.0), PI, GameSim.MAX_HULL)
	sim.car.body.velocity = Vector2(-12.0, 0.0)
	_run_for(sim, 0.2, end_events)
	var done: Array = end_events.filter(func(e: Dictionary) -> bool: return e["type"] == "mission_complete")
	_check(_types(end_events).has("escaped") and done.size() == 1 and done[0]["id"] == "lift_bridge" and done[0]["final"] == true, "reaching the far bank's gate while the bridge is down is the escape, and the last mission's end", str(done))
	_check(_lines(end_events) == ["lb_end_1", "lb_end_2"] and sim.mission.timers_left().is_empty(), "with the closing lines, and the timer stopped", str(_lines(end_events)))
	_run_for(sim, GameSim.ESCAPE_MAX_TIME + 0.5, end_events)
	var saves: Array = end_events.filter(func(e: Dictionary) -> bool: return e["type"] == "save")
	_check(_types(end_events).has("story_complete") and not _types(end_events).has("chapter_complete") and saves.size() == 1, "once the car is at rest the story completes and asks for a save", str(_types(end_events).filter(func(t: String) -> bool: return t in ["story_complete", "chapter_complete", "save"])))
	var d: Dictionary = saves[0]["data"]
	_check(d["done"].size() == 7 and d["next"] == "" and d["ending_seen"] == true and d["finished"] == true and SaveStore.valid_save(d) and SaveStore.upgraded(d) == d, "a save with every mission done, ending seen and finished: good as it is", str(d.get("finished")))
	_check(sim.car.body.position.x < sim.world.arena["left"] - 20.0, "the car is out on the road beyond the far bank's gate", str(sim.car.body.position))


## A save made when The Lift Bridge was only built as far as the control house (free roam after it: seven done, nothing
## next, no finished flag) loads as that mission still to play, not as the story over.
func _test_legacy_save() -> void:
	var old := {"version": SaveStore.VERSION, "saved_at": 0, "next": "", "done": StoryData.MISSIONS.map(func(m: Dictionary) -> String: return m["id"]), "ending_seen": true, "totals": {"kills": 3, "wrecks": 0, "seconds": 900.0}}
	var path := "user://chapter2_test_save.json"
	SaveStore.write_save(old, path)
	var back := SaveStore.load_save(path)
	_check(not back.is_empty() and back["next"] == "lift_bridge" and back["done"].size() == 6 and back["totals"]["kills"] == 3, "a save from before the bridge came down loads as The Lift Bridge next, with what was done kept", str(back.get("next")))
	_check(SaveStore.city_of(back) == Cities.HARBOUR and FileAccess.file_exists(path), "in the harbour city, and the file is not set aside")
	var sim := _sim()
	sim.continue_story(back)
	_check(sim.car.body.position.distance_to(StoryData.place_pos("field_hospital")) < 0.1, "and Continue puts the car at the hospital, where it starts")
	var fin := old.duplicate(true)
	fin["finished"] = true
	_check(SaveStore.upgraded(fin) == fin, "while a save that says it is finished stays finished")
	DirAccess.remove_absolute(path)


# ----------------------------------------------------------------------------- the autopilot drives it

## The autopilot plays each chapter 2 mission in turn, from The Long Road's end to the control house, with the pack and
## the ambushes off (the route: legs through the squeezes and over the bridges, holds at each place, the floodlights timer
## with time to spare). With the ambushes live and the hull held (the director off, as chapter 1's guard has it) it must still
## finish Dead Convoy: the first mission's leg and hold, with creatures at the barricades. (It is slower than a driver where
## creatures cling to it in a squeeze, and does not finish Floodlights inside its timer that way: see docs/follow-ups.md.)
func _test_autopilot_chapter() -> void:
	var quiet := _drive_chapter(1, false, 3)
	_check(quiet["ok"], "seed 1: the autopilot drives Dead Convoy, Floodlights and The Lift Bridge with the pack off", str(quiet))
	var spare: float = float(quiet.get("spare", 0.0))
	_check(spare >= 0.2 * StoryData.FLOODLIGHT_SECONDS, "with the floodlights timer having at least a fifth of its time to spare", "spare %.0f s of %.0f" % [spare, StoryData.FLOODLIGHT_SECONDS])
	for seed_in in [1, 3, 4]:
		var live := _drive_chapter(seed_in, true, 1)
		_check(live["ok"] and live["t"] < 450.0, "seed %d: and Dead Convoy with the ambushes live, the hull held" % seed_in, str(live))


func _drive_chapter(seed_in: int, live: bool, missions: int) -> Dictionary:
	var sim := _sim(seed_in)
	sim.start_story_at(4)
	sim.pack.director_on = false
	sim.pack.gaunts.clear()
	if not live:
		sim.pack.stalled = []
	var pilot := Autopilot.new()
	var out := {"ok": false, "log": [], "t": 0.0, "spare": 0.0, "latches": 0, "failed": ""}
	var at := {}
	for i in int(1100.0 / DT):
		if live:
			sim.hull = GameSim.MAX_HULL
		else:
			sim.pack.stalled = []  # the ambushes are part of the mission: with the pack off they are disarmed too
		sim.step(DT, pilot.controls(sim, DT))
		for e in sim.take_events():
			match e["type"]:
				"mission_complete":
					(out["log"] as Array).append("%s@%d" % [e["id"], int(sim.time)])
				"mission_failed":
					out["failed"] = "%s (%s) at %d s, car %s" % [e["id"], e["reason"], int(sim.time), str(sim.car.body.position.round())]
					out["t"] = sim.time
					return out
				"latch":
					out["latches"] += 1
				"timer":
					if e["state"] == "stop" and e["id"] == "floodlights":
						out["spare"] = float(at.get("left", 0.0))
		for tl in sim.mission.timers_left():
			if tl["id"] == "floodlights":
				at["left"] = tl["left"]
		if (out["log"] as Array).size() >= missions:
			out["ok"] = true
			break
	out["t"] = sim.time
	return out

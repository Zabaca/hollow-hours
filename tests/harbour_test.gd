extends Node
## Headless checks on the harbour city, chapter 2's map (tools/blender/harbour.py): its layout is a good one,
## the model is there, every story place is clear of everything and reachable by road from the highway checkpoint,
## the highway is a drive of at least a kilometre, the dev flags put the game there, and the chapter boundary
## and Continue land in it.
##
##   godot --headless --path . res://tests/harbour_test.tscn
##
## Fixed seeds, no window.

const DT := 1.0 / 120.0
const CAR_GRID := {"clearance": 1.0, "cell": 1.0}  # the autopilot's own grid for the harbour (Autopilot.HINTS)
const MIN_HIGHWAY := 1000.0  # m by road, checkpoint to the city (option 05)
const CAR_CLEARANCE := 1.5  # a place is this far from every box, so the car (1.06 m a side) fits in its marker

var failures := 0


func _ready() -> void:
	_test_layout()
	_test_registry_and_model()
	_test_places()
	_test_roads()
	_test_dev_flags()
	_test_chapter_two_starts_on_the_highway()
	_test_stalled_hunters()
	_test_long_road_driven()
	_test_after_the_long_road()
	print("")
	print("harbour_test: %d failed" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, name: String, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL "), name, ("  " + detail) if detail != "" else "")
	if not ok:
		failures += 1


func _sim(seed_in: int = 7) -> GameSim:
	return GameSim.new(Cities.layout(Cities.HARBOUR), "bruiser", seed_in, true, Cities.HARBOUR)


# ----------------------------------------------------------------------------- the layout and the model

func _test_layout() -> void:
	var lay: Dictionary = HarbourLayout.DATA
	var bad := LayoutCheck.problems(lay)
	_check(bad.is_empty(), "the harbour city's layout is the shape the simulation, map, camera and autopilot expect", "\n".join(bad))
	var a: Dictionary = lay["arena"]
	_check(float(a["right"]) - float(a["left"]) > 1500.0 and float(a["top"]) - float(a["bottom"]) < 320.0, "its arena is one long rectangle: the city and the highway running out of it", str(a))
	_check(lay.has("gate") and SimWorld.gate_side(a, lay["gate"]) == "west", "it has a way out in the west wall, the lift bridge's far end", str(lay.get("gate")))
	_check(lay["blocks"].size() == 36, "the city is 36 blocks", "blocks=%d" % lay["blocks"].size())
	var w := SimWorld.from_layout(lay)
	_check(w.spawns.size() >= 100, "with hiding places spread for the pack's director", "spawns=%d" % w.spawns.size())
	var kinds := {}
	for b in lay["boxes"]:
		kinds[b["kind"]] = true
	_check(kinds.keys().all(func(k: String) -> bool: return k in LayoutCheck.BOX_KINDS), "and every box is of a kind the map and the camera know", str(kinds.keys()))
	_check(lay["bridges"].any(func(b: Dictionary) -> bool: return b["id"] == "lift_bridge" and b["up"] == true and b["closers"].size() == 2), "the lift bridge is raised: two colliders close its road", "")


func _test_registry_and_model() -> void:
	_check(Cities.has(Cities.HARBOUR) and Cities.layout(Cities.HARBOUR) == HarbourLayout.DATA and Cities.model_path(Cities.HARBOUR).ends_with("harbour_city.glb"), "the registry hands out the harbour city's layout and model")
	_check(ResourceLoader.exists(Cities.model_path(Cities.HARBOUR)), "the model is imported")
	var scene: PackedScene = load(Cities.model_path(Cities.HARBOUR))
	var root := scene.instantiate()
	var blocks := 0
	var chunks := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			if String(n.name).begins_with("blk_"):
				blocks += 1
			elif String(n.name).begins_with("hw_"):
				chunks += 1
		stack.append_array(n.get_children())
	root.free()
	_check(blocks == 36 and chunks >= 12, "the model is one piece per block and one per 100 m of highway, so the renderer can skip what the fog hides", "blocks=%d highway chunks=%d" % [blocks, chunks])


# ----------------------------------------------------------------------------- places, roads and legs

## Places clear of every box and post by the car's reach, inside the arena, reachable by road from the checkpoint.
func _test_places() -> void:
	var sim := _sim()
	var w := sim.world
	var grid := NavGrid.new(w, float(CAR_GRID["clearance"]), float(CAR_GRID["cell"]))
	var start: Vector2 = StoryData.place_pos("highway_start")
	var lowered := _sim()
	lowered.set_bridge(true)
	var open_grid := NavGrid.new(lowered.world, float(CAR_GRID["clearance"]), float(CAR_GRID["cell"]))
	var bad: Array = []
	var unreachable: Array = []
	for id in StoryData.PLACES:
		var pl: Dictionary = StoryData.PLACES[id]
		if pl["city"] != Cities.HARBOUR:
			continue
		var p: Vector2 = pl["pos"]
		if p.x < w.arena["left"] or p.x > w.arena["right"] or p.y < w.arena["bottom"] or p.y > w.arena["top"]:
			bad.append(id + ": outside the arena")
		for b in w.boxes:
			var dx := maxf(maxf(b["x0"] - p.x, 0.0), p.x - b["x1"])
			var dy := maxf(maxf(b["y0"] - p.y, 0.0), p.y - b["y1"])
			if Vector2(dx, dy).length() < CAR_CLEARANCE:
				bad.append("%s: %.1f m from a %s" % [id, Vector2(dx, dy).length(), b["kind"]])
		for q in w.posts:
			if p.distance_to(Vector2(q["x"], q["y"])) - q["r"] < CAR_CLEARANCE:
				bad.append("%s: too near a %s" % [id, q["kind"]])
		var from: NavGrid = grid
		if pl.get("needs_bridge", false):
			from = open_grid  # a place past the lift bridge is reachable once the bridge is down
		if from.path(start, p).is_empty():
			unreachable.append(id)
	_check(bad.is_empty(), "every harbour place is in the arena and clear of boxes and posts", str(bad))
	_check(unreachable.is_empty(), "and reachable on the car's path grid from the highway checkpoint", str(unreachable))
	# The planned places the next slices use are in the layout too, and reachable.
	var missing: Array = []
	for name in HarbourLayout.DATA["places"]:
		var pp: Dictionary = HarbourLayout.DATA["places"][name]
		if grid.path(start, Vector2(float(pp["x"]), float(pp["y"]))).is_empty():
			missing.append(name)
	_check(missing.is_empty(), "so is every place the city's layout names (the chapter's later missions use them)", str(missing))
	# The highway.
	var path := grid.path(start, StoryData.place_pos("convoy_call"))
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i].distance_to(path[i - 1])
	_check(length >= MIN_HIGHWAY, "the highway leg is at least a kilometre by road, checkpoint to the city", "%.0f m" % length)
	_check(start.distance_to(Vector2(float(w.arena["left"]), 0.0)) > 1500.0, "and the checkpoint is at the far end of the map")
	# The squeezes the pack's grid sees only partly: the car's grid sees every 4 m gap.
	var narrow := grid.path(Vector2(1244.5, 8.5), Vector2(1100.0, 8.5))
	_check(not narrow.is_empty(), "the car's grid routes through the toll lanes")
	var coarse := NavGrid.new(w, Autopilot.CAR_CLEARANCE)
	_check(coarse.path(start, StoryData.place_pos("convoy_call")).is_empty(), "which the quarter's 2 m grid with its wide berth cannot: that is why the harbour has its own")


func _test_roads() -> void:
	var lay: Dictionary = HarbourLayout.DATA
	var narrowest := INF
	for r in lay["roads"]:
		narrowest = minf(narrowest, float(r["width"]))
	var quarter_narrowest := INF
	for r in CityLayout.DATA["roads"]:
		quarter_narrowest = minf(quarter_narrowest, float(r["width"]))
	_check(narrowest >= quarter_narrowest and narrowest >= 14.0, "every road is at least as wide as the quarter's", "harbour %.1f m, quarter %.1f m" % [narrowest, quarter_narrowest])
	var gaps: Array = []
	for rb in lay["roadblocks"]:
		if rb["gap"] != null:
			gaps.append(float(rb["gap"]["width"]))
	_check(gaps.size() >= 10 and gaps.min() >= 4.0, "every roadblock squeeze is at least 4 m, as wide as the burned bus's chicane", "%d squeezes, narrowest %.1f m" % [gaps.size(), gaps.min()])


# ----------------------------------------------------------------------------- flags, the boundary and Continue

func _test_dev_flags() -> void:
	Session.reset()
	Session.apply_args(["--mission=4", "--seed=3"])
	_check(Session.mode == "story" and Session.mission_flag == 4, "--mission=4 starts The Long Road")
	_check(StoryData.mission_city(Session.mission_flag - 1) == Cities.HARBOUR, "which is in the harbour city")
	Session.reset()
	Session.apply_args(["--city=harbour"])
	_check(Session.city == Cities.HARBOUR, "--city=harbour loads the harbour city")
	Session.reset()
	Session.apply_args(["--city=nowhere"])
	_check(Session.city == "", "and an unknown city is ignored")
	Session.reset()
	Session.apply_args(["--screen=chapter"])
	_check(Session.mode == "story" and Session.screen == "chapter", "--screen=chapter shows the next chapter's card")
	Session.reset()


func _test_chapter_two_starts_on_the_highway() -> void:
	var sim := _sim()
	sim.start_story_at(3)
	_check(sim.mission.active() and sim.mission.mission_data()["id"] == "long_road", "mission 4 begins at once in the harbour city")
	_check(sim.car.body.position.distance_to(StoryData.place_pos("highway_start")) < 0.1 and absf(angle_difference(sim.car.body.angle, PI)) < 0.01, "with the car at the highway checkpoint, facing west, down the road")
	_check(sim.mission.objective()["place"] == "toll_plaza", "and the first objective is the toll plaza")
	# Continue from a chapter 1 save lands there.
	var save := {"version": SaveStore.VERSION, "saved_at": 0, "next": "long_road", "done": ["batteries", "pharmacist", "west_gate"], "ending_seen": true, "totals": {"kills": 0, "wrecks": 0, "seconds": 0.0}}
	_check(SaveStore.valid_save(save) and SaveStore.city_of(save) == Cities.HARBOUR, "a chapter 1 save is a good save and Continue opens the harbour city")
	var cont := _sim()
	cont.continue_story(save)
	_check(cont.mission.active() and cont.car.body.position.distance_to(StoryData.place_pos("highway_start")) < 0.1, "where The Long Road starts on the highway")


# ----------------------------------------------------------------------------- The Long Road

func _step_for(sim: GameSim, seconds: float, controls: Dictionary = {"throttle": 0.0, "turn": 0.0, "handbrake": false, "boost": false}) -> void:
	for i in int(seconds / DT):
		sim.step(DT, controls)
		sim.take_events()


## The creatures in stalled cars: armed by the mission, each placed (hunting) only when the car comes within its
## release distance, once, and gone when the mission ends.
func _test_stalled_hunters() -> void:
	var list: Array = HarbourLayout.DATA["stalled_hunters"]
	_check(list.size() >= 4 and list.size() <= 12, "the layout puts a handful of creatures in stalled cars along the highway", "%d" % list.size())
	var spaced := true
	var xs: Array = list.map(func(h: Dictionary) -> float: return float(h["x"]))
	xs.sort()
	for i in range(1, xs.size()):
		if xs[i] - xs[i - 1] < 60.0:
			spaced = false
	_check(spaced, "one at a time, at least 60 m apart, not a crowd")
	var first: Dictionary = list[0]
	var at := Vector2(float(first["x"]), float(first["y"]))
	var rel := float(first["release"])
	var sim := _sim()
	sim.start_story_at(3)
	sim.pack.director_on = false
	sim.pack.gaunts.clear()
	_check(sim.pack.stalled.size() == list.size(), "The Long Road arms them when it begins", "armed=%d" % sim.pack.stalled.size())
	# The nearest hunter to the car's start is the first to go off; hold the car where it can be placed against it.
	var nearest := at
	for h in list:
		if Vector2(float(h["x"]), float(h["y"])).distance_to(sim.car.body.position) < nearest.distance_to(sim.car.body.position):
			nearest = Vector2(float(h["x"]), float(h["y"]))
	var near_rel := rel
	for h in list:
		if Vector2(float(h["x"]), float(h["y"])) == nearest:
			near_rel = float(h["release"])
	sim.place_car(nearest + Vector2(near_rel + 6.0, 0.0), PI, GameSim.MAX_HULL)
	_step_for(sim, 1.0)
	_check(sim.pack.gaunts.is_empty() and sim.pack.stalled.size() == list.size(), "none is released while the car is outside its distance")
	sim.place_car(nearest + Vector2(near_rel - 6.0, 0.0), PI, GameSim.MAX_HULL)
	_step_for(sim, 0.1)
	_check(sim.pack.gaunts.size() == 1 and sim.pack.stalled.size() == list.size() - 1, "and exactly that one is, once the car is within it, already hunting", "gaunts=%d armed=%d" % [sim.pack.gaunts.size(), sim.pack.stalled.size()])
	_check(sim.pack.gaunts[0].pos.distance_to(nearest) < 4.0, "bursting out of its own car")
	_step_for(sim, 0.5)
	_check(sim.pack.gaunts.size() == 1, "and not again")
	# Free roam arms a few ambush spots in the city (never the highway's), not the highway's stalled creatures.
	var roam := _sim()
	roam.continue_story({"version": SaveStore.VERSION, "saved_at": 0, "next": "", "done": StoryData.MISSIONS.map(func(m: Dictionary) -> String: return m["id"]), "ending_seen": true, "totals": {"kills": 0, "wrecks": 0, "seconds": 0.0}})
	var in_city := roam.pack.stalled.all(func(h: Dictionary) -> bool: return (h["pos"] as Vector2).x < 200.0)
	_check(roam.pack.stalled.size() == StoryData.AMBUSH_ROAM and in_city, "free roam arms a few of the city's ambush spots at random, and none of the highway's creatures", "armed=%d" % roam.pack.stalled.size())


## The autopilot drives the whole of The Long Road: with the pack off (the route: toll lanes, the jam's free lane, the
## truck stop's squeeze, all on its own 1 m grid), and with the creatures live and the hull held (the guard against a
## road that cannot be finished).
func _test_long_road_driven() -> void:
	for seed_in in [1, 2]:
		var r := _drive_long_road(seed_in, false)
		_check(r["done"] and r["time"] < 150.0, "seed %d: the autopilot drives The Long Road to the east ring road with the pack off" % seed_in, "t=%.0f hull=%.0f crashes=%d marks=%s" % [r["time"], r["hull"], r["crashes"], str(r["marks"])])
	for seed_in in [1, 3, 4]:
		var r := _drive_long_road(seed_in, true)
		_check(r["done"] and r["time"] < 280.0, "seed %d: and with the creatures in the stalled cars and the pack live, the hull held" % seed_in, "t=%.0f latches=%d crashes=%d marks=%s" % [r["time"], r["latches"], r["crashes"], str(r["marks"])])


func _drive_long_road(seed_in: int, live: bool) -> Dictionary:
	var sim := _sim(seed_in)
	sim.start_story_at(3)
	if not live:
		sim.pack.director_on = false
		sim.pack.gaunts.clear()
		sim.pack.stalled = []
	var pilot := Autopilot.new()
	var out := {"done": false, "time": 0.0, "hull": 0.0, "crashes": 0, "latches": 0, "marks": []}
	for i in int(300.0 / DT):
		if live:
			sim.hull = GameSim.MAX_HULL
		sim.step(DT, pilot.controls(sim, DT))
		for e in sim.take_events():
			match e["type"]:
				"crash":
					out["crashes"] += 1
				"latch":
					out["latches"] += 1
				"objective":
					(out["marks"] as Array).append(int(sim.time))
				"mission_complete":
					out["done"] = true
				"mission_failed":
					out["time"] = sim.time
					return out
		if out["done"]:
			break
	out["time"] = sim.time
	out["hull"] = sim.hull
	return out


## When the last step is reached the mission is complete and the story goes straight on: Dead Convoy begins at the east
## ring road (the car is inside its start marker), with the save written for it.
func _test_after_the_long_road() -> void:
	var sim := _sim()
	sim.start_story_at(3)
	sim.pack.director_on = false
	sim.pack.gaunts.clear()
	sim.pack.stalled = []
	sim.take_events()
	var events: Array = []
	# Reach each step's place in turn.
	for pid in ["toll_plaza", "jam", "truck_stop", "convoy_call"]:
		sim.place_car(StoryData.place_pos(pid), PI, GameSim.MAX_HULL)
		for i in 3:
			sim.step(DT, {"throttle": 0.0, "turn": 0.0, "handbrake": false, "boost": false})
			events.append_array(sim.take_events())
	var done: Array = events.filter(func(e: Dictionary) -> bool: return e["type"] == "mission_complete")
	var types: Array = events.map(func(e: Dictionary) -> String: return e["type"])
	_check(done.size() == 1 and done[0]["id"] == "long_road" and done[0]["final"] == false and done[0]["chapter_end"] == false, "reaching the east ring road completes The Long Road, which ends neither the story nor a chapter", str(done))
	_check(not ("story_complete" in types) and not ("chapter_complete" in types) and not ("escaped" in types), "so there is no ending")
	var lines: Array = events.filter(func(e: Dictionary) -> bool: return e["type"] == "line").map(func(e: Dictionary) -> String: return e["id"])
	_check(lines.slice(0, 3) == ["lr_jam", "lr_overpass", "lr_done"], "with its three calls along the way and the closing one at the end", str(lines))
	var saves: Array = events.filter(func(e: Dictionary) -> bool: return e["type"] == "save")
	_check(saves.size() == 1 and saves[0]["data"]["done"].size() == 4 and saves[0]["data"]["next"] == "dead_convoy" and SaveStore.valid_save(saves[0]["data"]), "it saves with four missions done and Dead Convoy next, a good save", str(saves.size()))
	_check(sim.mission.active() and sim.mission.mission_data()["id"] == "dead_convoy" and "dc_call_1" in lines, "and Dead Convoy begins at once, where the car stands")
	# A wreck in that mission goes back to that save, in the harbour city, at Dead Convoy's start.
	sim.damage(1000.0, "dev")
	_step_for(sim, 0.1)
	sim.revert_to_save()
	_step_for(sim, 0.05)
	_check(sim.city_id == Cities.HARBOUR and sim.mission.active() and sim.car.body.position.distance_to(StoryData.place_pos("convoy_call")) < 0.1, "a wreck there goes back to that save in the harbour city (Continue puts the car at the mission's start, not at the far end of the highway)")
	# A save from when the story ended at The Long Road reads as Dead Convoy next, not as damaged.
	var old := {"version": SaveStore.VERSION, "saved_at": 0, "next": "", "done": ["batteries", "pharmacist", "west_gate", "long_road"], "ending_seen": true, "totals": {"kills": 0, "wrecks": 0, "seconds": 0.0}}
	_check(SaveStore.valid_save(old) and SaveStore.upgraded(old)["next"] == "dead_convoy" and SaveStore.city_of(old) == Cities.HARBOUR, "a save from when The Long Road was the last built mission is a good save, with Dead Convoy next")

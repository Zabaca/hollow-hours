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
		if grid.path(start, p).is_empty():
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

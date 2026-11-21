extends Node
## Headless checks for the story on screen: the presenter and its views, driven through mission event
## sequences by stepping a story GameSim and handing it the events, the way main.gd does. It checks the
## objective line, the hold bar, the timers, the subtitles and their order, the cards, the radar and the
## map, the fail menu's three choices (retry, restart, quit), the save it writes, and the title's
## Continue and Start over. It writes only under user://, never the player's save.
##
##   godot --headless --path . res://tests/presenter_test.tscn

const DT := 1.0 / 120.0
const SAVE := "user://presenter_test_save.json"
const IDLE := {"throttle": 0.0, "turn": 0.0, "handbrake": false, "boost": false}

var failures := 0
var resets := 0
var quits := 0


func _ready() -> void:
	InputSetup.ensure()
	Session.save_path = SAVE
	_clean()
	_test_radio_order()
	_test_map_view()
	_test_gate_view()
	_test_gate_piers_outside_the_wall()
	_test_car_rests_on_the_road_after_the_escape()
	_test_flags_never_touch_the_players_save()
	_test_mission_start_on_screen()
	_test_hold_and_timer()
	_test_subtitles_setting()
	_test_fail_menu_retry_from_checkpoint()
	_test_fail_menu_without_checkpoint_restart_and_quit()
	_test_complete_saves_and_roams()
	_test_wreck_in_roam_goes_back()
	await _test_pause_menu_rows()
	await _test_subtitle_under_fail_menu()
	_test_full_map()
	_test_title_continue()
	_test_unlock_outlives_the_save()
	_test_ending_returns_to_the_title()
	_test_chapter_ending_cuts_to_the_next_city()
	_test_gate_open_line_does_not_play_after_the_closing_lines()
	_clean()
	print("")
	print("presenter_test: %d failed" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, name: String, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL "), name, ("  " + detail) if detail != "" else "")
	if not ok:
		failures += 1


func _clean() -> void:
	for f in DirAccess.open("user://").get_files():
		if f.begins_with("presenter_test_save"):
			DirAccess.remove_absolute("user://" + f)


# ----------------------------------------------------------------------------- harness

class Rig:
	var game: GameSim
	var presenter: StoryPresenter
	var parent: Node


func _rig(next_id: String = "", seed_in: int = 7) -> Rig:
	var r := Rig.new()
	r.parent = Node.new()
	r.parent.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(r.parent)
	r.game = GameSim.new(CityLayout.DATA, "bruiser", seed_in, true)
	if next_id != "":
		r.game.continue_story(_save_at(next_id))
	r.game.pack.director_on = false
	r.game.pack.gaunts.clear()
	r.presenter = StoryPresenter.new()
	r.parent.add_child(r.presenter)
	r.presenter.setup(r.game)
	r.presenter.save_path = SAVE
	r.presenter.world_reset.connect(func() -> void: resets += 1)
	r.presenter.quit_to_menu.connect(func() -> void: quits += 1)
	_feed(r)
	return r


func _drop(r: Rig) -> void:
	get_tree().paused = false
	r.parent.queue_free()


func _save_at(next_id: String) -> Dictionary:
	var done: Array = []
	for m in StoryData.MISSIONS:
		if m["id"] == next_id:
			break
		done.append(m["id"])
	return {"version": SaveStore.VERSION, "saved_at": 0, "next": next_id, "done": done, "ending_seen": false, "totals": {"kills": 0, "wrecks": 0, "seconds": 0.0}}


## Hand the presenter whatever the game has said, and a frame's update.
func _feed(r: Rig, delta: float = DT) -> void:
	for e in r.game.take_events():
		r.presenter.on_event(e)
	var car := r.game.car
	r.presenter.update(delta, car.body.position, car.body.angle)
	r.presenter.hud._process(0.0)  # the HUD reads the radio on its own, every frame


func _run(r: Rig, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		r.game.step(DT, IDLE)
		r.presenter.radio.advance(DT)
		_feed(r)


func _at(r: Rig, place: String) -> void:
	r.game.place_car(StoryData.place_pos(place), 0.0, r.game.hull)


# ----------------------------------------------------------------------------- the pieces

## The radio, as the presenter hands it the sim's line events: one at a time, a priority line ahead of
## the ordinary ones waiting but never before an earlier priority line, and the line speaking is not cut.
func _test_radio_order() -> void:
	var r := _rig()
	var radio := r.presenter.radio
	radio.clear()
	_until_quiet(radio)
	var line := func(id: String, priority: bool) -> void:
		r.presenter.on_event({"type": "line", "id": id, "speaker": StoryData.LINES[id]["speaker"], "priority": priority})
	line.call("bat_call_1", false)
	_listen(r)
	_check(radio.current_subtitle().get("id", "") == "bat_call_1", "a line is up once the call has opened")
	line.call("bat_shop", false)
	line.call("wrecked", true)
	line.call("ph_failed", true)
	line.call("bat_loaded", false)
	_check(radio.current_subtitle()["id"] == "bat_call_1", "the line speaking is never cut off")
	var order: Array = []
	for i in 400:
		radio.advance(0.5)
		var id: String = radio.current_subtitle().get("id", "")
		if id != "" and (order.is_empty() or order.back() != id):
			order.append(id)
	_check(order == ["bat_call_1", "wrecked", "ph_failed", "bat_shop", "bat_loaded"], "priority lines jump the queue but keep their order, one at a time", str(order))
	_drop(r)


## Step the radio to the end of whatever it is doing.
func _until_quiet(radio: Radio) -> void:
	for i in 400:
		if not radio.is_busy():
			return
		radio.advance(0.5)


## A frame's worth of the radio: past its opening squelch into the first line, then the presenter reads it.
func _listen(r: Rig) -> void:
	r.presenter.radio.advance(1.0)
	_feed(r)


func _test_gate_view() -> void:
	var world := SimWorld.from_layout(CityLayout.DATA)
	var gv := GateView.new()
	add_child(gv)
	gv.setup(world)
	var shut_z: float = gv.leaves[1]["node"].position.z
	_check(gv.leaves.size() == 2 and gv.units.size() == 2 and gv.lamps.size() == 2, "the gate has two leaves, two lamps and two searchlights")
	_check(gv.lamps[0]["light"].light_color.r > 0.9 and gv.lamps[0]["light"].light_color.g < 0.3, "its lamps are red while it is shut")
	gv.set_open(true)
	gv._process(GateView.OPEN_SECONDS * 0.5)
	_check(absf(gv.lamps[0]["light"].light_color.g - 0.55) < 0.05, "amber while it opens")
	gv._process(GateView.OPEN_SECONDS)
	var open_z: float = gv.leaves[1]["node"].position.z
	_check(absf(open_z - shut_z) > GateView.SLIDE * 0.95 and gv.lamps[0]["light"].light_color.g > 0.9 and gv.lamps[0]["light"].light_color.r < 0.2, "the leaves roll apart and the lamps go green", "moved %.1f m" % absf(open_z - shut_z))
	gv.set_open(false)
	gv._process(GateView.OPEN_SECONDS * 1.1)
	_check(absf(gv.leaves[1]["node"].position.z - shut_z) < 0.01, "and it shuts again")
	gv.free()
	var gate_x: float = world.gate["pos"].x
	var wall_ok := true
	var gv2 := GateView.new()
	add_child(gv2)
	gv2.setup(world)
	for l in gv2.leaves:
		var lx: float = l["node"].position.x
		# GM maps map x to Godot x; the leaves hang on the wall's inner face, at or just inside the gate's x.
		if lx < gate_x or lx > gate_x + 0.5:
			wall_ok = false
	for lp in gv2.lamps:
		if lp["mesh"].position.x < gate_x:
			wall_ok = false
	_check(wall_ok, "the leaves and lamps hang on the wall's inner face, not behind it", "gate x=%.1f" % gate_x)
	gv2.free()


## After the escape the car is at rest on the road outside: the view sits on the ground, level, and no
## part of it hovers above the asphalt or sinks below it.
func _test_car_rests_on_the_road_after_the_escape() -> void:
	var game := GameSim.new(CityLayout.DATA, "bruiser", 7, true)
	game.pack.director_on = false
	game.pack.gaunts.clear()
	game.world.gate["open"] = true
	game.place_car(Vector2(-66.0, 0.5), PI, GameSim.MAX_HULL)
	game.car.body.velocity = Vector2(-20.0, 0.0)
	game.escape()
	var view := CarView.new()
	add_child(view)
	view.build()
	for i in int((GameSim.ESCAPE_MAX_TIME + 1.0) / DT):
		game.step(DT, IDLE)
		game.take_events()
		if i % 2 == 0:
			view.sync(game, game.world, game.car.body.position, game.car.body.angle, DT * 2.0)
	for i in 120:
		view.sync(game, game.world, game.car.body.position, game.car.body.angle, 1.0 / 60.0)
	var lowest := INF
	var stack: Array = [view]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.mesh != null:
			var box: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).mesh.get_aabb()
			lowest = minf(lowest, box.position.y)
	_check(absf(view.position.y) < 0.02 and absf(view.roll) < 0.003 and absf(view.pitch) < 0.003, "the car view rests on the road, level", "y=%.3f roll=%.4f pitch=%.4f" % [view.position.y, view.roll, view.pitch])
	# The model's tyres reach 0.175 m below its origin whenever it is driven (the bruiser mesh), so it sits in the
	# road's skin rather than above it; what matters here is that nothing hovers.
	_check(lowest > -0.25 and lowest < 0.05, "and its lowest point (the tyres) is at road level, not hovering", "lowest=%.3f m" % lowest)
	view.queue_free()


## Nothing of the gate's frame may stand inside the arena: the sim has no collider for it. Scans the city
## mesh for anything tall near the gate that is east of the wall line.
func _test_gate_piers_outside_the_wall() -> void:
	var scene: PackedScene = load("res://assets/models/city.glb")
	var root := scene.instantiate()
	add_child(root)
	var inside := 0
	var piers := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not n is MeshInstance3D or n.mesh == null:
			continue
		var mi: MeshInstance3D = n
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var w := xf * v
				var map := GM.from3(w)
				if absf(map.y) < 8.0 and map.x < -66.0 and map.x > -73.0 and w.y > 5.0:
					piers += 1
					if map.x > -70.0 + 0.001:
						inside += 1
	_check(piers > 20 and inside == 0, "the gate's piers and lintel are there and none of them reaches into the arena past the wall line", "frame vertices=%d inside=%d" % [piers, inside])
	root.queue_free()


## A story run started by a flag must write its save somewhere that is not the player's: an earlier
## screenshot run overwrote a real save. (Session.apply_args takes the argument list so this can be checked.)
func _test_flags_never_touch_the_players_save() -> void:
	var kept := Session.save_path
	var real := SaveStore.SAVE_PATH
	var cases := [
		["--story"], ["--mission=2"], ["--screen=ending"], ["--screen=map", "--mission=1"], ["--screen=fail"],
		["--screen=complete"], ["--continue"], ["--mission=3", "--gate=open", "--seed=4"],
	]
	var bad: Array = []
	for args in cases:
		Session.reset()
		Session.apply_args(args)
		if Session.save_path == real or SaveStore.unlocks_path(Session.save_path) == SaveStore.unlocks_path(real) or Session.save_path != Session.SCRATCH_SAVE_PATH:
			bad.append(args)
	_check(bad.is_empty(), "every story flag defaults to the scratch save, never the player's", str(bad))
	Session.reset()
	Session.apply_args(["--mission=2", "--save=user://elsewhere.json"])
	_check(Session.save_path == "user://elsewhere.json", "and --save= still chooses the path")
	Session.reset()
	Session.apply_args(["--demo", "--shot-at=3"])
	_check(Session.mode == "survival" and Session.save_path == real, "while the old round's flags leave the real path alone (it writes no save)")
	Session.reset()
	Session.apply_args(["--city=quarter"])
	_check(Session.city == Cities.QUARTER, "--city= names the city to load")
	Session.reset()
	Session.apply_args(["--city=nowhere"])
	_check(Session.city == "", "and a city the game does not have is ignored")
	Session.reset()
	Session.save_path = kept


func _test_map_view() -> void:
	var radar := MapView.new()
	add_child(radar)
	radar.size = Vector2(200, 200)
	var pos := Vector2(10.0, -2.0)
	radar.set_state(pos, PI / 2.0, [])  # facing north
	var centre := radar.to_screen(pos)
	var ahead := radar.to_screen(pos + Vector2(0.0, 10.0))
	var right := radar.to_screen(pos + Vector2(10.0, 0.0))
	_check(centre.is_equal_approx(Vector2(100, 100)) and ahead.y < centre.y and is_equal_approx(ahead.x, centre.x), "the radar puts the car at the centre and what is ahead of it above", "ahead=%s" % str(ahead))
	_check(right.x > centre.x, "and what is on its right on the right")
	radar.set_state(pos, 0.0, [])  # now facing east: north is on its left
	_check(radar.to_screen(pos + Vector2(0.0, 10.0)).x < 100.0, "turning the car turns the radar")
	var roads := radar._road_boxes()
	_check(radar.city == Cities.QUARTER and roads.size() == CityLayout.DATA["roads"].size() and roads.size() == 6, "the map draws the roads its city's layout lists", str(roads.size()))
	var avenue: Dictionary = roads.filter(func(r: Dictionary) -> bool: return is_equal_approx(float(r["y0"]), -7.0) and is_equal_approx(float(r["y1"]), 7.0))[0]
	_check(is_equal_approx(float(avenue["x0"]), -70.0) and is_equal_approx(float(avenue["x1"]), 70.0), "the avenue runs the width of the quarter")
	var full := MapView.new()
	full.mode = MapView.Mode.FULL
	full.size = Vector2(1000, 760)
	_check(full.to_screen(Vector2(0.0, 30.0)).y < full.to_screen(Vector2(0.0, -30.0)).y and full.to_screen(Vector2(30.0, 0.0)).x > full.to_screen(Vector2(-30.0, 0.0)).x, "the full map is north-up")
	var poly := radar._clip(PackedVector2Array([Vector2(-50, -50), Vector2(300, -50), Vector2(300, 300), Vector2(-50, 300)]), PackedVector2Array([Vector2(50, 0), Vector2(150, 0), Vector2(150, 100), Vector2(50, 100)]))
	var inside := true
	for p in poly:
		if p.x < 49.9 or p.x > 150.1 or p.y < -0.1 or p.y > 100.1:
			inside = false
	_check(poly.size() >= 3 and inside, "a building crossing the radar's edge is cut to it")
	radar.free()
	full.free()


# ----------------------------------------------------------------------------- a mission on screen

func _test_mission_start_on_screen() -> void:
	var r := _rig()
	var h := r.presenter.hud
	_listen(r)
	_check(h.objective_label.text == "Drive to the motel office on the north road" and h.objective_label.visible, "the objective line shows the first step", h.objective_label.text)
	_check(h.radar.city == r.game.city_id and r.presenter.map_screen.view.city == r.game.city_id and r.game.city_id == Cities.QUARTER, "the radar and the full map draw the city the game is in")
	_check(h.card_kicker.text == "MISSION 1" and h.card_title.text == "BATTERIES", "a title card opens the mission", "%s / %s" % [h.card_kicker.text, h.card_title.text])
	_check(r.presenter.radio.current_subtitle()["id"] == "bat_call_1" and h.subtitle_panel.visible and h.speaker_label.text == "VERA" and h.subtitle_label.text.replace("\n", " ").begins_with("Red car on the avenue."), "Vera's call is subtitled with her name", h.subtitle_label.text)
	var blips: Array = h.radar.blips
	_check(blips.size() == 1 and blips[0]["kind"] == "objective" and blips[0]["place"] == "motel", "the motel office is the radar's amber blip")
	_check(r.presenter.markers.shown() == 1, "and has a marker in the world")
	_check(not h.hold_back.visible and not h.timer_row.visible, "no hold bar or timer yet")
	_check(is_equal_approx(r.presenter.dawn_target(), 0.0), "the sky is at its darkest for mission 1")
	_drop(r)


func _test_hold_and_timer() -> void:
	var r := _rig()
	var h := r.presenter.hud
	_at(r, "motel")
	_run(r, 2.0)
	_check(h.objective_label.text.begins_with("Hold still") and h.hold_back.visible, "at the motel office the hold bar appears")
	var share := h.hold_fill.size.x / h.hold_back.custom_minimum_size.x
	_check(absf(share - 0.5) < 0.08, "and fills with the hold", "share=%.2f" % share)
	r.game.place_car(Vector2(46.0, -20.0), 0.0, 100.0)
	_run(r, 1.0)
	_check(absf(h.hold_fill.size.x / h.hold_back.custom_minimum_size.x - share) < 0.01, "leaving the marker pauses it, it does not reset")
	_drop(r)
	var r2 := _rig("pharmacist")
	_at(r2, "shop")
	_run(r2, 3.0)
	var t: Control = r2.presenter.hud.timer_row
	_check(t.visible and r2.presenter.hud.timer_name.text == "SHUTTER" and r2.presenter.hud.timer_value.text == "2:57", "mission 2 shows the shutter timer", r2.presenter.hud.timer_value.text)
	_check(r2.presenter.hud.card_title.text == "THE PHARMACIST", "and its card")
	_run(r2, 100.0)
	_check(r2.presenter.hud.timer_value.text == "1:17", "which counts down in play", r2.presenter.hud.timer_value.text)
	_at(r2, "pharmacy")
	_run(r2, 0.2)
	_check(r2.presenter.hud.objective_label.text.contains("(2 to go)"), "the run-down step counts what is left", r2.presenter.hud.objective_label.text)
	_drop(r2)


func _test_subtitles_setting() -> void:
	var r := _rig()
	_listen(r)
	_check(r.presenter.hud.subtitle_panel.visible, "subtitles are on by default")
	var kept := Settings.subtitles
	Settings.subtitles = false
	_feed(r)
	_check(not r.presenter.hud.subtitle_panel.visible, "the Subtitles setting hides them at once, mid-line")
	Settings.subtitles = true
	_feed(r)
	_check(r.presenter.hud.subtitle_panel.visible, "and shows them again")
	Settings.subtitles = kept
	_drop(r)


# ----------------------------------------------------------------------------- failing

func _wreck(r: Rig) -> void:
	r.game.damage(1000.0, "test")
	_run(r, 0.1)


func _test_fail_menu_retry_from_checkpoint() -> void:
	resets = 0
	quits = 0
	var r := _rig()
	_at(r, "motel")
	_run(r, 4.4)  # the box is loaded: a checkpoint
	_check(r.presenter.has_checkpoint and r.presenter.hud.notice_label.text == "CHECKPOINT", "the checkpoint is announced")
	r.game.damage(60.0, "test")
	_wreck(r)
	_check(not r.presenter.fail_menu.is_open, "the wreck is seen for a moment before the menu")
	_feed(r, 1.6)
	var fm := r.presenter.fail_menu
	_check(fm.is_open and get_tree().paused and fm.reason_label.text == "The car was wrecked.", "then MISSION FAILED, with the reason, and the world stops")
	_check(fm.rows.size() == 3 and fm.rows[0].text == "Retry from checkpoint" and fm.rows[1].text == "Restart mission" and fm.rows[2].text == "Quit to menu", "offering retry from the checkpoint, restart and quit")
	_check(r.presenter.radio.process_mode == Node.PROCESS_MODE_ALWAYS, "the radio keeps running under the fail menu, for the wreck's call")
	var after: Array = []
	for i in 80:
		r.presenter.radio.advance(1.0)
		var id: String = r.presenter.radio.current_subtitle().get("id", "")
		if id != "" and (after.is_empty() or after.back() != id):
			after.append(id)
	_check(after.back() == "wrecked" and after.size() <= 2, "the failed mission drops the calls still waiting: only Vera's wreck call plays after the line speaking", str(after))
	fm.rows[0].activated.emit()
	_check(not fm.is_open and not get_tree().paused and resets == 1, "retry closes the menu, starts the world again and resets the views")
	_check(r.presenter.radio.process_mode == Node.PROCESS_MODE_PAUSABLE, "and the radio pauses with the world again")
	_check(r.game.phase == GameSim.Phase.PLAYING and r.game.hull >= 60.0 and r.game.car.body.position.distance_to(StoryData.place_pos("motel")) < 1.0, "the car is back at the checkpoint with at least 60 hull", "hull=%.0f" % r.game.hull)
	_feed(r)
	_check(r.presenter.hud.objective_label.text.begins_with("Take the box to the hotel"), "on the step after it", r.presenter.hud.objective_label.text)
	_check(r.presenter.radio.current_subtitle().is_empty() and r.presenter.radio.queued_ids().is_empty(), "and the radio is cleared: no old call plays after the retry")
	_drop(r)


func _test_fail_menu_without_checkpoint_restart_and_quit() -> void:
	resets = 0
	quits = 0
	var r := _rig()
	_wreck(r)
	_feed(r, 1.6)
	var fm := r.presenter.fail_menu
	_check(fm.is_open and fm.rows[0].text == "Retry mission", "before a checkpoint the first choice is just Retry mission")
	fm.rows[0].activated.emit()
	_feed(r)
	_check(r.presenter.hud.objective_label.text.begins_with("Drive to the motel office") and r.game.hull == GameSim.MAX_HULL and resets == 1, "and it starts the mission over")
	r.game.damage(1000.0, "test")
	_run(r, 0.1)
	_feed(r, 1.6)
	fm.rows[1].activated.emit()
	_feed(r)
	_check(not fm.is_open and not get_tree().paused and resets == 2 and r.presenter.hud.objective_label.text.begins_with("Drive to the motel office"), "Restart mission does the same", "resets=%d" % resets)
	r.game.damage(1000.0, "test")
	_run(r, 0.1)
	_feed(r, 1.6)
	fm.rows[2].activated.emit()
	_check(quits == 1 and not get_tree().paused and not fm.is_open, "Quit to menu leaves and gives the world back")
	_drop(r)
	# A timed-out mission fails sooner, with its own reason.
	var r2 := _rig("pharmacist")
	_at(r2, "shop")
	_run(r2, StoryData.SHUTTER_SECONDS + 1.0)
	_feed(r2, 1.0)
	_check(r2.presenter.fail_menu.is_open and r2.presenter.fail_menu.reason_label.text.begins_with("The shutter gave way"), "the shutter running out says why")
	r2.presenter.fail_menu.close()
	_drop(r2)


# ----------------------------------------------------------------------------- completing and free roam

func _test_complete_saves_and_roams() -> void:
	var r := _rig()
	_at(r, "motel")
	_run(r, 4.4)
	_at(r, "hotel")
	_run(r, 3.4)
	var h := r.presenter.hud
	_check(h.card_kicker.text == "MISSION COMPLETE" and h.card_title.text == "BATTERIES", "completing a mission shows its card")
	var saved := SaveStore.load_save(SAVE)
	_check(not saved.is_empty() and saved["next"] == "pharmacist" and saved["done"] == ["batteries"], "and writes the save", str(saved))
	_check(h.objective_label.text == "Drive to the gas station for the next call", "free roam says where the next call is", h.objective_label.text)
	_check(h.radar.blips.size() == 1 and h.radar.blips[0]["kind"] == "start" and r.presenter.markers.shown() == 1, "the next start is a teal blip and a marker")
	_check(r.presenter.dawn_target() > 0.0, "the sky has lightened a touch")
	_drop(r)


func _test_wreck_in_roam_goes_back() -> void:
	resets = 0
	var r := _rig("pharmacist")
	_run(r, 0.1)
	r.game.damage(1000.0, "test")
	_run(r, 0.1)
	_check(r.presenter.hud.card_title.text == "WRECKED", "a wreck in free roam says so")
	_feed(r, 3.0)
	_check(resets == 1 and r.game.phase == GameSim.Phase.PLAYING and r.game.hull == GameSim.MAX_HULL, "and puts the car back at the last save")
	_drop(r)


# ----------------------------------------------------------------------------- menus

func _test_pause_menu_rows() -> void:
	var texts := func(pm: PauseMenu) -> Array:
		return pm.rows.map(func(row: MenuRow) -> String: return row.text)
	var pm := PauseMenu.new()
	add_child(pm)
	pm.open(null, false, false)
	await get_tree().process_frame
	_check(texts.call(pm) == ["Resume", "Settings", "Quit to menu"], "the pause menu in the old round is unchanged", str(texts.call(pm)))
	pm.resume_game()
	pm.open(null, true, true)
	await get_tree().process_frame
	_check(texts.call(pm) == ["Resume", "Map", "Settings", "Restart mission", "Quit to menu"], "in a mission it adds Map and Restart mission", str(texts.call(pm)))
	var asked := [0, 0]
	pm.map_requested.connect(func() -> void: asked[0] += 1)
	pm.restart_requested.connect(func() -> void: asked[1] += 1)
	pm.rows[1].activated.emit()
	pm.rows[3].activated.emit()
	_check(asked == [1, 1], "and the rows ask for the map and for a restart")
	pm.resume_game()
	pm.open(null, true, false)
	await get_tree().process_frame
	_check(texts.call(pm) == ["Resume", "Map", "Settings", "Quit to menu"], "in free roam there is no Restart mission", str(texts.call(pm)))
	pm.resume_game()
	await get_tree().process_frame
	pm.free()


func _test_full_map() -> void:
	var r := _rig()
	var p := r.presenter
	p.open_map()
	_check(p.map_screen.is_open and get_tree().paused and p.blocks_pause() and p.map_screen.view.mode == MapView.Mode.FULL, "the full map opens and stops the world")
	_check(p.map_screen.view.blips.size() == 1 and p.map_screen.view.blips[0]["place"] == "motel", "with the objective on it")
	p.map_screen.close()
	_check(not p.map_screen.is_open and not get_tree().paused and not p.blocks_pause(), "and closing it gives the world back")
	_drop(r)


## The fail menu pauses the tree. The wreck call must still be subtitled: that needs a HUD that keeps
## running while paused, which a test rig whose parent is Always cannot show, so this one is Pausable.
func _test_subtitle_under_fail_menu() -> void:
	var r := _rig()
	r.parent.process_mode = Node.PROCESS_MODE_PAUSABLE
	r.presenter.radio.clear()
	_until_quiet(r.presenter.radio)
	r.presenter.hud.set_subtitle({})
	_wreck(r)
	_feed(r, 1.6)
	_check(r.presenter.fail_menu.is_open and get_tree().paused, "the fail menu is up and the world is paused")
	var shown := false
	for i in 60:
		await get_tree().create_timer(0.1, true, false, true).timeout
		if r.presenter.hud.subtitle_panel.visible and r.presenter.hud.speaker_label.text == "VERA":
			shown = true
			break
	_check(shown, "Vera's wreck call is subtitled under the fail menu", r.presenter.hud.speaker_label.text)
	r.presenter.fail_menu.close()
	_drop(r)


func _test_unlock_outlives_the_save() -> void:
	_clean()
	_check(not SaveStore.survive_unlocked(SAVE), "Survive the Night is locked before the story is finished")
	var r := _rig("west_gate")
	r.presenter.on_event({"type": "story_complete"})
	_check(SaveStore.survive_unlocked(SAVE), "finishing the story unlocks it")
	_drop(r)
	# Starting over takes the save away; the unlock stays, so the title still offers it.
	_check(SaveStore.load_save(SAVE).is_empty(), "with no save on disk")
	var rows := _title_rows()
	_check("Survive the Night:on" in rows and rows[1] == "Continue:off", "the title still offers Survive the Night", str(rows))

## The end of chapter 1: the same ending up to the pull-back, then no credits: it fades to black, shows the card
## "Chapter 2, The next night" and asks main.gd to load the next city. Nothing returns to the title.
func _test_chapter_ending_cuts_to_the_next_city() -> void:
	quits = 0
	var r := _rig("west_gate")
	var p := r.presenter
	var changed: Array = []
	p.chapter_changed.connect(func(save: Dictionary) -> void: changed.append(save))
	var before := p.hud.card_title.text
	p.on_event({"type": "mission_complete", "title": "WEST GATE", "id": "west_gate", "mission": 2, "final": false, "chapter_end": true})
	_check(p.hud.card_title.text == before, "the third mission shows no completion card: its ending is the chapter's")
	p.on_event({"type": "escaped"})
	p.on_event({"type": "chapter_complete", "next": "long_road", "city": "harbour"})
	_check(p.ending == "pullback" and SaveStore.survive_unlocked(SAVE), "once the car has stopped the camera draws back, and Survive the Night is unlocked")
	p.update(StoryPresenter.PULLBACK_SECONDS + 0.1, Vector2.ZERO, 0.0)
	_check(p.ending == "chapter_fade" and not p.credits_roll.playing and p.blocks_pause() and p.in_ending_view(), "then no credits: the screen fades to black, and nothing can be opened over it")
	p.update(StoryPresenter.FADE_SECONDS * 0.5, Vector2.ZERO, 0.0)
	_check(p._black.color.a > 0.3 and not p.chapter_card.visible and changed.is_empty(), "it goes dark first, with no card yet")
	p.update(StoryPresenter.FADE_SECONDS, Vector2.ZERO, 0.0)
	_check(p.ending == "chapter_card" and p.chapter_card.visible and p._card_kicker.text == "CHAPTER 2" and p._card_title.text == "THE NEXT NIGHT", "then the card: Chapter 2, The next night", "%s / %s" % [p._card_kicker.text, p._card_title.text])
	p.update(StoryPresenter.CARD_FADE_IN + 0.2, Vector2.ZERO, 0.0)
	_check(p._card_title.modulate.a > 0.99 and changed.is_empty(), "the card fades in and stays up")
	p.update(StoryPresenter.CARD_HOLD + 0.2, Vector2.ZERO, 0.0)
	_check(changed.size() == 1 and p.ending == "done" and quits == 0, "and then the next city is asked for, once, and the game does not go back to the title", "changed=%d quits=%d" % [changed.size(), quits])
	p.update(1.0, Vector2.ZERO, 0.0)
	_check(changed.size() == 1, "only once")
	_drop(r)
	_clean()


## The ending: the car goes through the gate (first light), stops (the camera draws back), the credits
## roll, it fades to black and the title comes back. Nothing is a card and nothing waits on a key.
func _test_ending_returns_to_the_title() -> void:
	quits = 0
	var r := _rig("west_gate")
	var p := r.presenter
	_check(p.ending == "" and p.dawn_target() < 1.0, "before the gate the night is not over")
	p.radio.say("gate_call_2")  # a stale ordinary call still queued when the car reaches the gate
	for id in StoryData.ENDING_LINES:
		p.on_event({"type": "line", "id": id, "speaker": StoryData.LINES[id]["speaker"], "priority": true})
	p.on_event({"type": "mission_complete", "title": "WEST GATE", "id": "west_gate", "mission": 2, "final": true})
	_check(p.hud.card_kicker.text != "MISSION COMPLETE", "the last mission shows no completion card")
	var started := [0]
	p.ending_started.connect(func() -> void: started[0] += 1)
	p.on_event({"type": "escaped"})
	_check(p.ending == "rollout" and started[0] == 1 and is_equal_approx(p.dawn_target(), 1.0), "driving out of the gate starts the ending and brings first light")
	_check("gate_call_2" not in p.radio.queued_ids() and "end_vera" not in p.radio.queued_ids(), "the stale call is dropped, and the closing lines wait for the car to stop", str(p.radio.queued_ids()))
	p.on_event({"type": "story_complete"})
	_check(p.ending == "pullback" and is_equal_approx(p.pullback_progress(), 0.0), "once the car has stopped the camera starts to draw back")
	_check(p.radio.queued_ids() == ["end_vera", "end_ruck"] or p.radio.current.get("id", "") == "end_vera", "and then Vera and Ruck speak, in that order", str(p.radio.queued_ids()))
	_check(p.blocks_pause() == false, "pausing is still allowed during the pull-back")
	_check(SaveStore.survive_unlocked(SAVE), "and Survive the Night is unlocked")
	p.update(StoryPresenter.PULLBACK_SECONDS * 0.5, Vector2.ZERO, 0.0)
	_check(absf(p.pullback_progress() - 0.5) < 0.01 and not p.credits_roll.playing, "half way through the pull-back, no credits yet")
	p.update(StoryPresenter.PULLBACK_SECONDS * 0.6, Vector2.ZERO, 0.0)
	_check(p.ending == "roll" and p.credits_roll.playing and p.blocks_pause(), "then the credits roll, and nothing can be opened over them")
	p.credits_roll.elapsed = CreditsRoll.SECONDS - 0.01
	p.credits_roll._process(0.1)
	_check(p.ending == "fade" and not p.credits_roll.playing and p.blocks_pause(), "when they end it fades to black, still unpausable")
	_check(p.credits_roll.visible and is_equal_approx(p.pullback_progress(), 1.0), "the last credit line stays up through the fade, and the camera holds its place")
	p.update(StoryPresenter.FADE_SECONDS * 0.5, Vector2.ZERO, 0.0)
	_check(quits == 0 and p._black.color.a > 0.3, "the screen goes dark first", "alpha=%.2f" % p._black.color.a)
	p.update(StoryPresenter.FADE_SECONDS, Vector2.ZERO, 0.0)
	p.update(1.0, Vector2.ZERO, 0.0)
	_check(quits == 1 and p._black.color.a >= 0.99 and p.blocks_pause() and is_equal_approx(p.pullback_progress(), 1.0), "and then it returns to the title, once", "quits=%d" % quits)
	p.update(1.0, Vector2.ZERO, 0.0)
	_check(quits == 1, "and only once")
	_drop(r)
	# A finished story has nothing to continue into: the title greys Continue and offers Survive the Night.
	var done := _save_at("")
	done["done"] = ["batteries", "pharmacist", "west_gate"]
	done["ending_seen"] = true
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(done))
	f.close()
	var rows := _title_rows()
	_check(rows[1] == "Continue:on" and "Survive the Night:on" in rows, "after chapter 1's ending Continue is lit (chapter 2 is next) and Survive the Night is offered", str(rows))
	done["done"] = ["batteries", "pharmacist", "west_gate", "long_road"]
	f = FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(done))
	f.close()
	var roam_title := _make_title()
	_check(roam_title.menu_rows[1].enabled and roam_title.menu_rows[1].note == "Free roam", "once The Long Road is done, with nothing after it yet, Continue says Free roam", roam_title.menu_rows[1].note)
	roam_title.queue_free()


## The reviewer's sequence: the gate opens (Ruck's "Gate's open" is queued behind the opening squelch), the
## car reaches it at once and the escape fires. The ordinary line must not play after the closing lines.
func _test_gate_open_line_does_not_play_after_the_closing_lines() -> void:
	var r := _rig("west_gate")
	var p := r.presenter
	p.radio.clear()
	_until_quiet(p.radio)
	p.on_event({"type": "line", "id": "gate_open", "speaker": "ruck", "priority": false})
	_check(p.radio.queued_ids() == ["gate_open"], "the gate's own line is queued behind the squelch")
	for id in StoryData.ENDING_LINES:
		p.on_event({"type": "line", "id": id, "speaker": StoryData.LINES[id]["speaker"], "priority": true})
	p.on_event({"type": "escaped"})
	p.on_event({"type": "story_complete"})
	var played: Array = []
	for i in 600:
		p.radio.advance(0.5)
		var id: String = p.radio.current_subtitle().get("id", "")
		if id != "" and (played.is_empty() or played.back() != id):
			played.append(id)
	_check(played == ["end_vera", "end_ruck"], "only the closing lines play, in order, and never Gate's open after them", str(played))
	_drop(r)


func _test_title_continue() -> void:
	_clean()
	var plain := _title_rows()
	_check(plain[1] == "Continue:off" and plain.size() == 5, "with no save Continue is greyed and there is no Survive the Night", str(plain))
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(_save_at("pharmacist")))
	f.close()
	var title := _make_title()
	var rows: Array = title.menu_rows
	_check(rows[1].enabled and rows[1].note == "Mission 2", "with a save Continue is lit and says which mission is next", rows[1].note)
	_check(title.save["next"] == "pharmacist" and not "Survive the Night" in title.menu_rows.map(func(x: MenuRow) -> String: return x.text), "and Survive the Night is not offered yet")
	rows[0].activated.emit()
	_check(title.panel is ConfirmPanel, "New Game over a save asks Start over? first")
	title.panel.closed.emit()
	_check(title.panel == null and FileAccess.file_exists(SAVE), "Cancel keeps the save and returns to the menu")
	title.queue_free()
	var done := _save_at("")
	done["done"] = ["batteries", "pharmacist", "west_gate"]
	done["ending_seen"] = true
	f = FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(done))
	f.close()
	var after := _title_rows()
	_check("Survive the Night:on" in after and after[1] == "Continue:on", "after chapter 1's ending the old round is offered as Survive the Night, and Continue goes on to chapter 2", str(after))


func _make_title() -> Control:
	var t: Control = load("res://scenes/title.tscn").instantiate()
	add_child(t)
	return t


func _title_rows() -> Array:
	var t := _make_title()
	var out: Array = t.menu_rows.map(func(x: MenuRow) -> String: return "%s:%s" % [x.text, "on" if x.enabled else "off"])
	t.queue_free()
	return out

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
	_test_mission_start_on_screen()
	_test_hold_and_timer()
	_test_subtitles_setting()
	_test_fail_menu_retry_from_checkpoint()
	_test_fail_menu_without_checkpoint_restart_and_quit()
	_test_complete_saves_and_roams()
	_test_wreck_in_roam_goes_back()
	await _test_pause_menu_rows()
	_test_full_map()
	_test_title_continue()
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
	line.call("end_vera", true)
	line.call("end_ruck", true)
	line.call("bat_loaded", false)
	_check(radio.current_subtitle()["id"] == "bat_call_1", "the line speaking is never cut off")
	var order: Array = []
	for i in 400:
		radio.advance(0.5)
		var id: String = radio.current_subtitle().get("id", "")
		if id != "" and (order.is_empty() or order.back() != id):
			order.append(id)
	_check(order == ["bat_call_1", "end_vera", "end_ruck", "bat_shop", "bat_loaded"], "priority lines jump the queue but keep their order, one at a time", str(order))
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
	_check(h.objective_label.text == "Drive to the 24-hour shop at the gas station" and h.objective_label.visible, "the objective line shows the first step", h.objective_label.text)
	_check(h.card_kicker.text == "MISSION 1" and h.card_title.text == "BATTERIES", "a title card opens the mission", "%s / %s" % [h.card_kicker.text, h.card_title.text])
	_check(r.presenter.radio.current_subtitle()["id"] == "bat_call_1" and h.subtitle_panel.visible and h.speaker_label.text == "VERA" and h.subtitle_label.text.replace("\n", " ").begins_with("Red car on the avenue."), "Vera's call is subtitled with her name", h.subtitle_label.text)
	var blips: Array = h.radar.blips
	_check(blips.size() == 1 and blips[0]["kind"] == "objective" and blips[0]["place"] == "shop", "the shop is the radar's amber blip")
	_check(r.presenter.markers.shown() == 1, "and has a marker in the world")
	_check(not h.hold_back.visible and not h.timer_row.visible, "no hold bar or timer yet")
	_check(is_equal_approx(r.presenter.dawn_target(), 0.0), "the sky is at its darkest for mission 1")
	_drop(r)


func _test_hold_and_timer() -> void:
	var r := _rig()
	var h := r.presenter.hud
	_at(r, "shop")
	_run(r, 2.0)
	_check(h.objective_label.text.begins_with("Hold still") and h.hold_back.visible, "at the shop the hold bar appears")
	var share := h.hold_fill.size.x / h.hold_back.custom_minimum_size.x
	_check(absf(share - 0.5) < 0.08, "and fills with the hold", "share=%.2f" % share)
	r.game.place_car(Vector2(46.0, -20.0), 0.0, 100.0)
	_run(r, 1.0)
	_check(absf(h.hold_fill.size.x / h.hold_back.custom_minimum_size.x - share) < 0.01, "leaving the marker pauses it, it does not reset")
	_drop(r)
	var r2 := _rig("pharmacist")
	_at(r2, "hut")
	_run(r2, 3.0)
	var t: Control = r2.presenter.hud.timer_row
	_check(t.visible and r2.presenter.hud.timer_name.text == "SHUTTER" and r2.presenter.hud.timer_value.text == "1:57", "mission 2 shows the shutter timer", r2.presenter.hud.timer_value.text)
	_check(r2.presenter.hud.card_title.text == "THE PHARMACIST", "and its card")
	_run(r2, 100.0)
	_check(r2.presenter.hud.timer_value.text == "0:17", "which counts down in play", r2.presenter.hud.timer_value.text)
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
	_at(r, "shop")
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
	_check(r.game.phase == GameSim.Phase.PLAYING and r.game.hull >= 60.0 and r.game.car.body.position.distance_to(StoryData.place_pos("shop")) < 1.0, "the car is back at the checkpoint with at least 60 hull", "hull=%.0f" % r.game.hull)
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
	_check(r.presenter.hud.objective_label.text.begins_with("Drive to the 24-hour shop") and r.game.hull == GameSim.MAX_HULL and resets == 1, "and it starts the mission over")
	r.game.damage(1000.0, "test")
	_run(r, 0.1)
	_feed(r, 1.6)
	fm.rows[1].activated.emit()
	_feed(r)
	_check(not fm.is_open and not get_tree().paused and resets == 2 and r.presenter.hud.objective_label.text.begins_with("Drive to the 24-hour shop"), "Restart mission does the same", "resets=%d" % resets)
	r.game.damage(1000.0, "test")
	_run(r, 0.1)
	_feed(r, 1.6)
	fm.rows[2].activated.emit()
	_check(quits == 1 and not get_tree().paused and not fm.is_open, "Quit to menu leaves and gives the world back")
	_drop(r)
	# A timed-out mission fails sooner, with its own reason.
	var r2 := _rig("pharmacist")
	_at(r2, "hut")
	_run(r2, 121.0)
	_feed(r2, 1.0)
	_check(r2.presenter.fail_menu.is_open and r2.presenter.fail_menu.reason_label.text.begins_with("The shutter gave way"), "the shutter running out says why")
	r2.presenter.fail_menu.close()
	_drop(r2)


# ----------------------------------------------------------------------------- completing and free roam

func _test_complete_saves_and_roams() -> void:
	var r := _rig()
	_at(r, "shop")
	_run(r, 4.4)
	_at(r, "hotel")
	_run(r, 3.4)
	var h := r.presenter.hud
	_check(h.card_kicker.text == "MISSION COMPLETE" and h.card_title.text == "BATTERIES", "completing a mission shows its card")
	var saved := SaveStore.load_save(SAVE)
	_check(not saved.is_empty() and saved["next"] == "pharmacist" and saved["done"] == ["batteries"], "and writes the save", str(saved))
	_check(h.objective_label.text == "Drive to the park hut for the next call", "free roam says where the next call is", h.objective_label.text)
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
	p.toggle_map()
	_check(p.map_screen.is_open and get_tree().paused and p.blocks_pause() and p.map_screen.view.mode == MapView.Mode.FULL, "Tab opens the full map and stops the world")
	_check(p.map_screen.view.blips.size() == 1 and p.map_screen.view.blips[0]["place"] == "shop", "with the objective on it")
	p.toggle_map()
	_check(not p.map_screen.is_open and not get_tree().paused and not p.blocks_pause(), "and Tab closes it again")
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
	_check("Survive the Night:on" in after and after[1] == "Continue:on", "after the ending the old round is offered as Survive the Night", str(after))


func _make_title() -> Control:
	var t: Control = load("res://scenes/title.tscn").instantiate()
	add_child(t)
	return t


func _title_rows() -> Array:
	var t := _make_title()
	var out: Array = t.menu_rows.map(func(x: MenuRow) -> String: return "%s:%s" % [x.text, "on" if x.enabled else "off"])
	t.queue_free()
	return out

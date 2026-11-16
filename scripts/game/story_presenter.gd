class_name StoryPresenter
extends Node
## Shows the story: it reads GameSim's mission events and queries (MissionSim) and drives the views, the
## way main.gd does for the creatures. It owns the StoryHud (objective, hold bar, timers, subtitles,
## cards, radar), the world markers, the fail menu and the full map; it writes the save when the story
## asks for one; and it is what calls retry, restart and the revert to the last save.
##
## main.gd gives it each event (`on_event`) and each frame (`update`), stops stepping while the fail menu
## or the map holds the scene tree paused, and resets its own views on `world_reset`.
##
## The radio (Radio) takes every "line" event, plays it and says what to subtitle; the HUD shows
## `radio.current_subtitle()` every frame. A retry or restart clears it, and a failed mission drops the
## ordinary lines still waiting, so no stale call plays after a retry.

signal quit_to_menu
signal world_reset  # a retry, restart or revert moved the car: reset the camera, the creature views, the effects

const FAIL_DELAY_WRECKED := 1.4  # seconds to see the wreck before the menu
const FAIL_DELAY := 0.6
const REVERT_DELAY := 2.8  # a wreck in free roam: seconds before it goes back to the last save
const ENDING_SECONDS := 9.0

var game: GameSim
var hud: StoryHud
var fail_menu: FailMenu
var map_screen: MapScreen
var markers: MarkerView
var radio: Radio
var save_path := SaveStore.SAVE_PATH
var has_checkpoint := false
var fail_text := ""
var _fail_in := -1.0
var _revert_in := -1.0
var _end_in := -1.0
var _blips_key := ""


func setup(g: GameSim, with_hud: bool = true) -> void:
	game = g
	hud = StoryHud.new()
	add_child(hud)
	hud.show_hud(with_hud)
	markers = MarkerView.new()
	add_child(markers)
	fail_menu = FailMenu.new()
	add_child(fail_menu)
	fail_menu.retry.connect(_on_retry)
	fail_menu.restart.connect(_on_restart)
	fail_menu.quit_to_menu.connect(_on_quit)
	map_screen = MapScreen.new()
	add_child(map_screen)
	radio = Radio.new()
	add_child(radio)


## True while something the presenter shows holds the world still: no pause menu on top of it.
func blocks_pause() -> bool:
	return fail_menu.is_open or map_screen.is_open


func dawn_target() -> float:
	return game.mission.dawn_amount()


# ----------------------------------------------------------------------------- events

func on_event(e: Dictionary) -> void:
	match e["type"]:
		"mission_started":
			has_checkpoint = false
			_fail_in = -1.0
			hud.show_card("Mission %d" % int(e["number"]), String(e["title"]))
		"line":
			radio.on_event(e)
		"checkpoint":
			has_checkpoint = true
			hud.notice("Checkpoint")
		"gate_open":
			hud.notice("The gate is open")
		"mission_complete":
			hud.show_card("Mission complete", String(e["title"]))
		"mission_failed":
			radio.drop_ordinary()
			fail_text = String(e["text"])
			_fail_in = FAIL_DELAY_WRECKED if e["reason"] == "wrecked" else FAIL_DELAY
		"save":
			SaveStore.write_save(e["data"], save_path)
		"roam_wrecked":
			_revert_in = REVERT_DELAY
			hud.show_card("", "Wrecked", "Back to where you last saved", 1.6)
		"retry", "roam":
			radio.clear()
			hud.hide_card()
		"story_complete":
			_end_in = ENDING_SECONDS
			hud.show_card("The end", "First light", "", ENDING_SECONDS - 3.0)


# ----------------------------------------------------------------------------- every frame

## `pos` and `angle` are the car's (interpolated) place on the map.
func update(delta: float, pos: Vector2, angle: float) -> void:
	var m := game.mission
	var o := m.objective()
	var text := ""
	if not o.is_empty():
		text = _objective_text(o)
	hud.set_objective(text)
	hud.set_subtitle(radio.current_subtitle())
	hud.set_hold(m.hold_progress())
	hud.set_timers(m.timers_left())
	var blips := m.blips()
	hud.set_radar(pos, angle, blips)
	var key := ""
	for bl in blips:
		key += "%s:%s;" % [bl["place"], bl["kind"]]
	if key != _blips_key:
		_blips_key = key
		markers.show_blips(blips)
	if _fail_in >= 0.0:
		_fail_in -= delta
		if _fail_in < 0.0:
			# The wreck's call plays on under the menu; it is the one thing that does.
			radio.process_mode = Node.PROCESS_MODE_ALWAYS
			fail_menu.open(fail_text, has_checkpoint)
	if _revert_in >= 0.0:
		_revert_in -= delta
		if _revert_in < 0.0:
			game.revert_to_save()
			_after_reset()
	if _end_in >= 0.0:
		_end_in -= delta
		if _end_in < 0.0:
			quit_to_menu.emit()


func _objective_text(o: Dictionary) -> String:
	if o["kind"] == "start":
		return "Drive to %s for the next call" % StoryData.PLACES[o["place"]]["name"]
	var text: String = o["text"]
	if o["kind"] == "kill":
		text += "  (%d to go)" % int(o["remaining"])
	return text


# ----------------------------------------------------------------------------- the menus' choices

func _on_retry() -> void:
	game.retry_mission()
	_after_reset()


func _on_restart() -> void:
	game.restart_mission()
	_after_reset()


func _on_quit() -> void:
	radio.process_mode = Node.PROCESS_MODE_PAUSABLE
	quit_to_menu.emit()


## Restart the mission from the pause menu (the row exists only in a mission).
func restart_mission() -> void:
	_on_restart()


func _after_reset() -> void:
	_fail_in = -1.0
	_revert_in = -1.0
	radio.process_mode = Node.PROCESS_MODE_PAUSABLE
	hud.hide_card()
	world_reset.emit()


# ----------------------------------------------------------------------------- the map

func open_map() -> void:
	map_screen.open(game.car.body.position, game.car.body.angle, game.mission.blips())


func toggle_map() -> void:
	if map_screen.is_open:
		map_screen.close()
	elif not fail_menu.is_open:
		open_map()

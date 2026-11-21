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
signal ending_started  # the car is through the gate: first light, the HUD gives way
signal world_reset  # a retry, restart or revert moved the car: reset the camera, the creature views, the effects
signal chapter_changed(save: Dictionary)  # the chapter's card has been shown: load the next chapter's city from this save

const FAIL_DELAY_WRECKED := 1.4  # seconds to see the wreck before the menu
const FAIL_DELAY := 0.6
const REVERT_DELAY := 2.8  # a wreck in free roam: seconds before it goes back to the last save
const PULLBACK_SECONDS := 11.0  # the slow pull-back from the stopped car
const FADE_SECONDS := 2.6  # to black, after the credits
const CARD_HOLD := 3.4  # how long the next chapter's card stays up, once it has faded in
const CARD_FADE_IN := 0.9
const ROUTE_EVERY := 1.0  # seconds between the route line being worked out again

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
## The ending, in order: "" (not yet), "rollout" (the car rolls out of the gate), "pullback" (it has
## stopped; the camera draws back), then either "roll" (the credits), "fade" (to black) and back to the
## title; or, at the end of a chapter that is not the story's, "chapter_fade" (to black), "chapter_card"
## (the next chapter's card) and then `chapter_changed`, which main.gd answers by loading the next city.
var ending := ""
var chapter_card := CanvasLayer.new()
var _card_kicker: Label
var _card_title: Label
var _chapter_next := ""  # the id of the next chapter's first mission while a chapter ending plays
var credits_roll: CreditsRoll
var blackout := CanvasLayer.new()
var _black := ColorRect.new()
var _ending_t := 0.0
var _held_lines: Array = []  # the closing lines, until the story completes
var _blips_key := ""
var route := PackedVector2Array()  # the way to the objective, for the radar and the map (cities that show one)
var _route_in := 0.0
var _route_for := Vector2.INF


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
	hud.radar.set_city(game.city_id)
	map_screen.view.set_city(game.city_id)
	credits_roll = CreditsRoll.new()
	add_child(credits_roll)
	credits_roll.finished.connect(_on_roll_finished)
	blackout.layer = MenuStyle.LAYER_BLACKOUT
	blackout.process_mode = Node.PROCESS_MODE_ALWAYS
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blackout.add_child(_black)
	add_child(blackout)
	# The next chapter's card, over the black (its own layer: the HUD has faded out by then).
	chapter_card.layer = MenuStyle.LAYER_BLACKOUT + 1
	chapter_card.process_mode = Node.PROCESS_MODE_ALWAYS
	chapter_card.visible = false
	var cbox := VBoxContainer.new()
	cbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cbox.alignment = BoxContainer.ALIGNMENT_CENTER
	cbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_kicker = MenuStyle.label("", 22, MenuStyle.DIM, 600, 12)
	_card_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_title = MenuStyle.label("", 72, MenuStyle.BONE, 300, 14)
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cbox.add_child(_card_kicker)
	cbox.add_child(_card_title)
	chapter_card.add_child(cbox)
	add_child(chapter_card)
	radio = Radio.new()
	add_child(radio)
	hud.subtitle_source = radio


## True while something the presenter shows holds the world still: no pause menu on top of it.
func blocks_pause() -> bool:
	# Nothing opens over the credits, the fade or the way back to the title.
	return fail_menu.is_open or map_screen.is_open or ending in ["roll", "fade", "chapter_fade", "chapter_card", "done"]


## Is the ending's own view up (the camera draws back from the stopped car)?
func in_ending_view() -> bool:
	return ending in ["pullback", "roll", "fade", "chapter_fade", "chapter_card", "done"]


## How light the sky should be: the mission's own, and first light in full once the car is through the gate.
func dawn_target() -> float:
	return 1.0 if ending != "" else game.mission.dawn_amount()


## 0 to 1 over the pull-back (and 1 after it): the camera draws back along it.
func pullback_progress() -> float:
	if ending == "pullback":
		return clampf(_ending_t / PULLBACK_SECONDS, 0.0, 1.0)
	return 1.0 if ending in ["roll", "fade", "chapter_fade", "chapter_card", "done"] else 0.0


## How far the music has been hushed for the ending, 0 to 1.
func hush() -> float:
	return 0.0 if ending == "" else (1.0 if ending != "rollout" else 0.4)


# ----------------------------------------------------------------------------- events

func on_event(e: Dictionary) -> void:
	match e["type"]:
		"mission_started":
			has_checkpoint = false
			_fail_in = -1.0
			hud.show_card("Mission %d" % int(e["number"]), String(e["title"]))
		"line":
			# The closing lines wait for the car to stop: first light, a quiet moment, then Vera and Ruck.
			if String(e["id"]) in StoryData.ENDING_LINES and not _ending_over():
				_held_lines.append(e)
			else:
				radio.on_event(e)
		"checkpoint":
			has_checkpoint = true
			hud.notice("Checkpoint")
		"gate_open":
			hud.notice("The gate is open")
		"escaped":
			radio.drop_ordinary()  # nothing stale plays into the ending; the held closing lines are not in the queue
			ending = "rollout"
			_ending_t = 0.0
			hud.fade_out(2.2)
			hud.hide_card()
			ending_started.emit()
		"mission_complete":
			# The last mission of the story or of a chapter has its ending, not a card.
			if not bool(e.get("final", false)) and not bool(e.get("chapter_end", false)):
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
			_held_lines = []
			radio.clear()
			hud.hide_card()
		"chapter_complete":
			SaveStore.unlock_survive(save_path)  # escaping the quarter unlocks Survive the Night, as before
			_chapter_next = String(e["next"])
			ending = "pullback"
			_ending_t = 0.0
			for held in _held_lines:
				radio.on_event(held)
			_held_lines = []
		"story_complete":
			SaveStore.unlock_survive(save_path)  # outlives the save: starting over must not hide Survive the Night
			ending = "pullback"
			_ending_t = 0.0
			for held in _held_lines:
				radio.on_event(held)
			_held_lines = []


# ----------------------------------------------------------------------------- every frame

## `pos` and `angle` are the car's (interpolated) place on the map.
func update(delta: float, pos: Vector2, angle: float) -> void:
	var m := game.mission
	var o := m.objective()
	var text := ""
	if not o.is_empty():
		text = _objective_text(o)
	hud.set_objective(text)
	hud.set_hold(m.hold_progress())
	hud.set_timers(m.timers_left())
	var blips := m.blips()
	_update_route(delta, blips)
	hud.set_radar(pos, angle, blips, game.car.speed(), route)
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
	_step_ending(delta)


## The route to the objective (or to the next mission's start), recomputed about once a second and at once when the
## objective moves. The car's own path grid answers; the quarter has none.
func _update_route(delta: float, blips: Array) -> void:
	if blips.is_empty() or game.route_nav() == null:
		route = PackedVector2Array()
		_route_for = Vector2.INF
		return
	var goal: Vector2 = blips[0]["pos"]
	_route_in -= delta
	if _route_in <= 0.0 or goal != _route_for:
		_route_in = ROUTE_EVERY
		_route_for = goal
		route = game.route_to(game.car.body.position, goal)


func _ending_over() -> bool:
	return ending in ["pullback", "roll", "fade", "chapter_fade", "chapter_card", "done"]


func _step_ending(delta: float) -> void:
	match ending:
		"pullback":
			_ending_t += delta
			if _ending_t >= PULLBACK_SECONDS:
				if _chapter_next != "":
					ending = "chapter_fade"
					_ending_t = 0.0
				else:
					ending = "roll"
					credits_roll.start()
		"chapter_fade":
			_ending_t += delta
			_black.color.a = clampf(_ending_t / FADE_SECONDS, 0.0, 1.0)
			if _ending_t >= FADE_SECONDS + 0.4:
				begin_chapter_card()
		"chapter_card":
			_ending_t += delta
			var a := clampf(_ending_t / CARD_FADE_IN, 0.0, 1.0)
			_card_kicker.modulate.a = a
			_card_title.modulate.a = a
			if _ending_t >= CARD_FADE_IN + CARD_HOLD:
				ending = "done"
				chapter_changed.emit(game.mission.last_save.duplicate(true))
		"fade":
			_ending_t += delta
			_black.color.a = clampf(_ending_t / FADE_SECONDS, 0.0, 1.0)
			if _ending_t >= FADE_SECONDS + 0.6:
				ending = "done"
				quit_to_menu.emit()


## Show the next chapter's card over black (the ending does this after its fade; --screen=chapter jumps here).
func begin_chapter_card() -> void:
	if _chapter_next == "":
		_chapter_next = String(StoryData.MISSIONS[3]["id"])
	var n := StoryData.mission_index(_chapter_next)
	var number := 2
	var chapters := StoryData.chapters()
	for i in chapters.size():
		if n >= int(chapters[i]["first"]) and n <= int(chapters[i]["last"]):
			number = i + 1
	ending = "chapter_card"
	_ending_t = 0.0
	_black.color.a = 1.0
	_card_kicker.text = "CHAPTER %d" % number
	_card_title.text = String(StoryData.CHAPTER_TITLES[clampi(number - 1, 0, StoryData.CHAPTER_TITLES.size() - 1)]).to_upper()
	_card_kicker.modulate.a = 0.0
	_card_title.modulate.a = 0.0
	chapter_card.visible = true


func _on_roll_finished() -> void:
	if ending == "roll":
		ending = "fade"
		_ending_t = 0.0


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
	var blips: Array = game.mission.blips()
	_update_route(1.0, blips)  # fresh when the map opens
	map_screen.open(game.car.body.position, game.car.body.angle, blips, route)

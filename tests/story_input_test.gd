extends SceneTree
## Drives the story's map and menus with real key and gamepad events, frame by frame, the way a player's
## input arrives: Tab and Back open and close the full map in play, and with the map opened from the pause
## menu the rows underneath do not act on Tab, Down or Enter. Needs real time (about 20 s):
##
##   godot --headless --path . --script res://tests/story_input_test.gd
##
## It keeps its settings and save in files of its own under user://.

const SETTINGS_FILE := "user://settings_story_input_test.json"
const SAVE_FILE := "user://save_story_input_test.json"

var fails := 0
var main: Node
var presenter: StoryPresenter


func ck(ok: bool, name: String, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL "), name, "  ", detail)
	if not ok:
		fails += 1


func _key_event(code: int, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	return e


func _joy_event(btn: int, down: bool) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	e.pressed = down
	return e


## A press arrives at the start of a frame, before _process, and is held a few frames, as from a device.
func _tap(down: InputEvent, up: InputEvent) -> void:
	await process_frame
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	for i in 4:
		await process_frame
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	for i in 4:
		await process_frame


func key(code: int) -> void:
	await _tap(_key_event(code, true), _key_event(code, false))


func joy(btn: int) -> void:
	await _tap(_joy_event(btn, true), _joy_event(btn, false))


func focused_text() -> String:
	var f := root.gui_get_focus_owner()
	return (f as MenuRow).text if f is MenuRow else "<none>"


func _initialize() -> void:
	Settings.file_path = SETTINGS_FILE
	Session.save_path = SAVE_FILE
	var title: Node = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	run.call_deferred()


func run() -> void:
	await create_timer(0.6).timeout
	await key(KEY_SPACE)
	await key(KEY_ENTER)  # New Game
	await create_timer(2.5).timeout
	main = current_scene
	ck(main.name == "Main" and main.presenter != null, "New Game enters the story", str(main.name))
	presenter = main.presenter
	await create_timer(0.5).timeout

	await key(KEY_TAB)
	ck(presenter.map_screen.is_open and paused, "Tab opens the map in play")
	await key(KEY_TAB)
	ck(not presenter.map_screen.is_open and not paused, "Tab closes it, and it stays closed", "open=%s paused=%s" % [presenter.map_screen.is_open, paused])
	await joy(JOY_BUTTON_BACK)
	ck(presenter.map_screen.is_open, "the gamepad's Back opens it")
	await joy(JOY_BUTTON_BACK)
	ck(not presenter.map_screen.is_open and not paused, "and closes it, and it stays closed")
	await key(KEY_TAB)
	await key(KEY_ESCAPE)
	ck(not presenter.map_screen.is_open and not main.pause_menu.is_open and not paused, "Esc closes the map without opening the pause menu")

	await key(KEY_ESCAPE)
	ck(main.pause_menu.is_open and focused_text() == "Resume", "Esc opens the pause menu", focused_text())
	await key(KEY_DOWN)
	ck(focused_text() == "Map", "Down reaches the Map row", focused_text())
	await key(KEY_ENTER)
	ck(presenter.map_screen.is_open and main.pause_menu.is_open, "Enter on it opens the map over the pause menu")
	await key(KEY_DOWN)
	await key(KEY_DOWN)
	await key(KEY_ENTER)
	ck(presenter.map_screen.is_open and main.pause_menu.is_open and current_scene == main, "Down and Enter under the map do not act on the pause menu's rows", "scene=%s" % current_scene.name)
	await key(KEY_TAB)
	ck(not presenter.map_screen.is_open and main.pause_menu.is_open and paused, "Tab closes the map and leaves the pause menu up")
	await create_timer(0.2).timeout
	ck(focused_text() == "Map", "and the focus is back on the Map row", focused_text())
	await key(KEY_ENTER)
	await joy(JOY_BUTTON_B)
	ck(not presenter.map_screen.is_open and main.pause_menu.is_open, "B closes the map too")
	await key(KEY_ENTER)
	await joy(JOY_BUTTON_BACK)
	ck(not presenter.map_screen.is_open and main.pause_menu.is_open, "and so does Back")
	await key(KEY_ENTER)
	await key(KEY_ESCAPE)
	ck(not presenter.map_screen.is_open and main.pause_menu.is_open, "Esc closes the map and not the pause menu under it")
	await key(KEY_ESCAPE)
	ck(not main.pause_menu.is_open and not paused, "and Esc again resumes")

	for p in [SETTINGS_FILE, SETTINGS_FILE + ".tmp", SAVE_FILE, SAVE_FILE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	print("story_input_test: %d failed" % fails)
	quit(fails)

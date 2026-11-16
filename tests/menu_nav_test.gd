extends SceneTree
## Drives the real menus with gamepad and keyboard events, from the title into the round, through
## the pause menu and back to the title. Needs real time (about 15 s); run from anywhere:
##
##   godot --headless --path . --script res://tests/menu_nav_test.gd
##
## It keeps its settings in its own file under user://, never the player's.

var fails := 0


func ck(ok: bool, name: String, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL "), name, "  ", detail)
	if not ok:
		fails += 1


func press_joy(btn: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await create_timer(0.12).timeout
	var r := InputEventJoypadButton.new()
	r.button_index = btn
	r.pressed = false
	Input.parse_input_event(r)
	Input.flush_buffered_events()
	await create_timer(0.12).timeout


func press_key(code: int) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await create_timer(0.12).timeout
	var r := InputEventKey.new()
	r.physical_keycode = code
	r.keycode = code
	r.pressed = false
	Input.parse_input_event(r)
	Input.flush_buffered_events()
	await create_timer(0.12).timeout


func focused_text() -> String:
	var f := root.gui_get_focus_owner()
	return (f as MenuRow).text if f is MenuRow else "<none: %s>" % [f]


const SETTINGS_FILE := "user://settings_nav_test.json"


func _initialize() -> void:
	Settings.file_path = SETTINGS_FILE
	var title: Node = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	run.call_deferred()


func run() -> void:
	await create_timer(0.6).timeout
	await press_key(KEY_SPACE)  # skips the fade; also checks it does not activate a row
	ck(current_scene.name == "Title", "title is up", str(current_scene.name))
	ck(focused_text() == "New Game", "New Game is focused first", focused_text())
	await press_joy(JOY_BUTTON_DPAD_DOWN)
	ck(focused_text() == "Settings", "dpad down skips the greyed Continue", focused_text())
	await press_joy(JOY_BUTTON_DPAD_DOWN)
	ck(focused_text() == "Credits", "dpad down again", focused_text())
	await press_joy(JOY_BUTTON_DPAD_UP)
	await press_joy(JOY_BUTTON_A)
	await press_key(KEY_ENTER)
	await create_timer(0.3).timeout
	ck(focused_text() == "Master", "A opens Settings, first slider focused", focused_text())
	var master: MenuRow = root.gui_get_focus_owner()
	await press_joy(JOY_BUTTON_DPAD_LEFT)
	ck(is_equal_approx(master.value, 0.95) and is_equal_approx(Settings.volumes["master"], 0.95), "dpad left lowers the slider and the setting", "%.2f" % master.value)
	await press_joy(JOY_BUTTON_DPAD_RIGHT)
	ck(is_equal_approx(master.value, 1.0), "dpad right raises it", "%.2f" % master.value)
	await press_key(KEY_DOWN)
	ck(focused_text() == "Music", "keyboard down moves to the next slider", focused_text())
	for i in 5:
		await press_key(KEY_DOWN)
	ck(focused_text() == "Graphics", "keyboard reaches Graphics", focused_text())
	await press_key(KEY_ENTER)
	ck(Settings.high == false, "Enter on Graphics switches to Low and saves", str(Settings.high))
	await press_key(KEY_ENTER)
	ck(Settings.high == true, "Enter again switches back to High", str(Settings.high))
	await press_joy(JOY_BUTTON_B)
	await create_timer(0.3).timeout
	ck(focused_text() == "Settings", "B closes Settings and returns to its row", focused_text())
	await press_joy(JOY_BUTTON_DPAD_UP)
	await press_joy(JOY_BUTTON_DPAD_UP)
	ck(focused_text() == "New Game", "back at New Game", focused_text())
	await press_joy(JOY_BUTTON_A)
	await create_timer(2.5).timeout
	ck(current_scene.name == "Main", "New Game enters the round", str(current_scene.name))
	await create_timer(1.0).timeout
	ck(not paused, "not paused in play")
	await press_joy(JOY_BUTTON_START)
	ck(paused, "Start pauses the game")
	ck(focused_text() == "Resume", "Resume focused", focused_text())
	await press_joy(JOY_BUTTON_START)
	ck(not paused, "Start again resumes (and does not reopen)")
	await create_timer(0.3).timeout
	ck(not paused, "still playing a moment later")
	await press_key(KEY_ESCAPE)
	ck(paused, "Esc pauses")
	await press_joy(JOY_BUTTON_DPAD_DOWN)
	await press_joy(JOY_BUTTON_A)
	await create_timer(0.3).timeout
	ck(focused_text() == "Master", "Settings opens inside pause", focused_text())
	await press_key(KEY_ESCAPE)
	await create_timer(0.2).timeout
	ck(paused and focused_text() == "Settings", "Esc closes settings only, still paused", focused_text())
	await press_joy(JOY_BUTTON_DPAD_DOWN)
	ck(focused_text() == "Quit to menu", "down to Quit to menu", focused_text())
	await press_joy(JOY_BUTTON_A)
	await create_timer(1.5).timeout
	ck(current_scene.name == "Title" and not paused, "Quit to menu returns to the title, unpaused", "%s paused=%s" % [current_scene.name, paused])
	for p in [SETTINGS_FILE, SETTINGS_FILE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	print("menu_nav_test: %d failed" % fails)
	quit(fails)

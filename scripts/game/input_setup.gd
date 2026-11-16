class_name InputSetup
extends RefCounted
## The controls, made in code so no project.godot input block has to be kept in step. Also gives the
## menus' accept and cancel actions the gamepad's A and B.

static func ensure() -> void:
	_action("accelerate", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_action("brake", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_action("steer_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_action("steer_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_action("handbrake", [_key(KEY_SPACE), _button(JOY_BUTTON_A)])
	_action("boost", [_key(KEY_SHIFT), _button(JOY_BUTTON_X)])
	_action("restart", [_key(KEY_R), _button(JOY_BUTTON_Y)])
	_action("pause", [_key(KEY_ESCAPE), _key(KEY_P), _button(JOY_BUTTON_START)])
	_action("fullscreen", [_key(KEY_F11)])
	_action("quality", [_key(KEY_F3)])
	_action("mute", [_key(KEY_M)])
	# The menus: this engine build leaves the gamepad's A and B off ui_accept and ui_cancel.
	_action("ui_accept", [_button(JOY_BUTTON_A)])
	_action("ui_cancel", [_button(JOY_BUTTON_B)])


static func _action(name: String, events: Array) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.2)
	for e in events:
		InputMap.action_add_event(name, e)


static func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _axis(axis: int, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


static func _button(index: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = index
	return e

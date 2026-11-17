class_name FailMenu
extends CanvasLayer
## "MISSION FAILED", the reason, and the choices: Retry from checkpoint (just "Retry mission" before the
## first checkpoint, where it restarts), Restart mission, Quit to menu. It stops the world (the scene
## tree is paused) while it is up. The presenter listens to the three signals.

signal retry
signal restart
signal quit_to_menu

var shade := Control.new()
var column := VBoxContainer.new()
var reason_label: Label
var rows: Array[MenuRow] = []
var is_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = MenuStyle.LAYER_FAIL
	visible = false
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(dim)
	shade.add_child(MenuStyle.left_shade())
	column.position = Vector2(MenuStyle.MARGIN_X - 30.0, 96.0)
	column.custom_minimum_size.x = 640.0
	column.add_theme_constant_override("separation", 2)
	shade.add_child(column)
	column.add_child(MenuStyle.heading("MISSION FAILED", 60, 12))
	reason_label = MenuStyle.label("", 24, MenuStyle.DIM, 500, 2)
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.custom_minimum_size = Vector2(560.0, 0.0)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 30)
	pad.add_theme_constant_override("margin_bottom", 26)
	pad.add_child(reason_label)
	column.add_child(pad)
	_row("Retry from checkpoint", func() -> void: _choose(retry))
	_row("Restart mission", func() -> void: _choose(restart))
	_row("Quit to menu", func() -> void: _choose(quit_to_menu))


func _row(text: String, action: Callable) -> MenuRow:
	var row := MenuRow.button(text, 32, 6)
	row.activated.connect(action)
	column.add_child(row)
	rows.append(row)
	return row


## Show it, with the reason and whether there is a checkpoint to go back to.
func open(reason: String, has_checkpoint: bool) -> void:
	reason_label.text = reason
	rows[0].text = "Retry from checkpoint" if has_checkpoint else "Retry mission"
	rows[0].queue_redraw()
	is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rows[0].grab_focus.call_deferred()


func close() -> void:
	is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _choose(sig: Signal) -> void:
	if not is_open:
		return
	close()
	sig.emit()

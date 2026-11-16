class_name ConfirmPanel
extends Control
## A question with two answers, as a left-hand column like Settings and Credits: "Start over?" before
## New Game replaces a save. Cancel is focused first; Back, Esc or B also cancels.

signal confirmed
signal closed

var heading_text := "Start over?"
var body := "This replaces your saved progress."
var yes_text := "Start over"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.position = Vector2(MenuStyle.MARGIN_X - 30.0, 96.0)
	col.custom_minimum_size.x = 640.0
	col.add_theme_constant_override("separation", 2)
	add_child(col)
	col.add_child(MenuStyle.heading(heading_text.to_upper(), 64, 14))
	var text := MenuStyle.label(body, 24, MenuStyle.DIM, 500, 2)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(560.0, 0.0)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 30)
	pad.add_theme_constant_override("margin_bottom", 26)
	pad.add_child(text)
	col.add_child(pad)
	var yes := MenuRow.button(yes_text, 32, 6)
	yes.activated.connect(func() -> void: confirmed.emit())
	col.add_child(yes)
	var no := MenuRow.button("Cancel", 32, 6)
	no.activated.connect(func() -> void: closed.emit())
	col.add_child(no)
	no.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		closed.emit()

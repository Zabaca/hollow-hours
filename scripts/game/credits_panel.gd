class_name CreditsPanel
extends Control
## Who made what, and the licence notices the game has to carry. Back, Esc or B closes it.

signal closed

const CREDITS := [
	["Made by", "Zabaca"],
	["Car handling", "Ported from Roadkill's car.js"],
	["Recordings", "Roadkill's engine, impact and wreck sounds"],
	["The city and the creature", "Modelled and animated in Blender for this game"],
	["Sound and music", "Generated with ElevenLabs"],
	["Engine", "Godot 4"],
	["Display face", "Cormorant, by the Cormorant Project Authors"],
]

const LICENCES := "Godot Engine. Copyright (c) 2014-present Godot Engine contributors. Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur. Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.\n\nCormorant. Copyright 2015 the Cormorant Project Authors (github.com/CatharsisFonts/Cormorant). Licensed under the SIL Open Font License, Version 1.1, https://scripts.sil.org/OFL"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outer := VBoxContainer.new()
	outer.position = Vector2(MenuStyle.MARGIN_X - 30.0, 96.0)
	outer.add_theme_constant_override("separation", 0)
	add_child(outer)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 30)
	outer.add_child(pad)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 880.0
	col.add_theme_constant_override("separation", 0)
	pad.add_child(col)
	var title := MenuStyle.label("CREDITS", 54, MenuStyle.BONE, 300, 10)
	title.custom_minimum_size.y = 70
	col.add_child(title)
	var rule_holder := Control.new()
	rule_holder.custom_minimum_size.y = 30
	var r := MenuStyle.rule(72)
	r.position = Vector2(0, 8)
	rule_holder.add_child(r)
	col.add_child(rule_holder)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)
	for pair in CREDITS:
		var who := MenuStyle.label(String(pair[0]).to_upper(), 16, MenuStyle.DIM, 600, 5)
		who.custom_minimum_size = Vector2(350, 34)
		who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var what := MenuStyle.label(pair[1], 23, MenuStyle.BONE, 500, 2)
		what.custom_minimum_size = Vector2(560, 34)
		grid.add_child(who)
		grid.add_child(what)
	var gap := Control.new()
	gap.custom_minimum_size.y = 20
	col.add_child(gap)
	var lic := MenuStyle.label(LICENCES, 14, Color(0.44, 0.47, 0.5), 500, 1)
	lic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lic.custom_minimum_size.x = 880
	col.add_child(lic)
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 16
	outer.add_child(gap2)
	var back := MenuRow.button("Back", 26, 5)
	back.activated.connect(func() -> void: closed.emit())
	outer.add_child(back)
	back.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		closed.emit()

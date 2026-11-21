class_name StoryHud
extends CanvasLayer
## What the story puts on screen, in the title's menu face: the objective at the top with its hold
## bar and timers, subtitles above the bottom edge, the mission cards, and the radar beside the hull
## and boost bars. A plain view: StoryPresenter tells it what to show; it keeps no story state.

const AMBER := MapView.AMBER
const RADAR_SIZE := 200.0

var root := Control.new()
var kicker := Label.new()
var objective_label := Label.new()
var hold_back := ColorRect.new()
var hold_fill := ColorRect.new()
var timer_row := HBoxContainer.new()
var timer_name := Label.new()
var timer_value := Label.new()
var notice_label := Label.new()
var card := Control.new()
var card_kicker: Label
var card_title: Label
var card_rule: ColorRect
var card_sub: Label
## Subtitles sit on a layer above the menus, so the wreck call stays readable under the fail menu.
var subtitle_layer := CanvasLayer.new()
var subtitle_panel := PanelContainer.new()
var speaker_label := Label.new()
var subtitle_label := Label.new()
var radar := MapView.new()

var _card_tween: Tween
var _notice_tween: Tween
var _objective_tween: Tween
## Where the subtitle comes from (the radio, which runs under the fail menu). Read every frame, here and not
## in the presenter, because this node keeps running while the tree is paused and the presenter does not.
var subtitle_source: Object
var _timer_low := false
var _subtitle_id := ""


func _ready() -> void:
	layer = MenuStyle.LAYER_STORY_HUD
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_objective()
	_build_card()
	_build_subtitles()
	radar.mode = MapView.Mode.RADAR
	radar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	radar.offset_left = 36.0
	radar.offset_right = 36.0 + RADAR_SIZE
	radar.offset_top = -36.0 - RADAR_SIZE
	radar.offset_bottom = -36.0
	root.add_child(radar)


func _process(_delta: float) -> void:
	if subtitle_source != null:
		set_subtitle(subtitle_source.current_subtitle())


## The ending: the objective, radar and bars go quietly.
func fade_out(seconds: float) -> void:
	MenuStyle.fade_out(self, root, seconds)


## Show or hide the whole HUD (the --no-hud flag).
func show_hud(on: bool) -> void:
	root.visible = on
	subtitle_layer.visible = on


func _text(l: Label, px: int, color: Color, weight: int, tracking: int) -> void:
	l.add_theme_font_override("font", MenuStyle.font(weight, tracking))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_objective() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	col.offset_left = -420.0
	col.offset_right = 420.0
	col.offset_top = 22.0
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	kicker.text = "OBJECTIVE"
	_text(kicker, 14, Color(MenuStyle.BONE, 0.62), 700, 9)
	col.add_child(kicker)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.custom_minimum_size.x = 840.0
	_text(objective_label, 28, MenuStyle.BONE, 600, 3)
	col.add_child(objective_label)
	var bar_holder := CenterContainer.new()
	bar_holder.custom_minimum_size.y = 14.0
	bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hold_back.color = Color(1, 1, 1, 0.13)
	hold_back.custom_minimum_size = Vector2(380.0, 4.0)
	hold_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hold_fill.color = AMBER
	hold_fill.position = Vector2.ZERO
	hold_fill.size = Vector2(0.0, 4.0)
	hold_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hold_back.add_child(hold_fill)
	bar_holder.add_child(hold_back)
	col.add_child(bar_holder)
	hold_back.visible = false
	timer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	timer_row.add_theme_constant_override("separation", 16)
	timer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text(timer_name, 14, Color(MenuStyle.DIM, 0.95), 600, 8)
	_text(timer_value, 40, MenuStyle.BONE, 400, 5)
	timer_row.add_child(timer_name)
	timer_row.add_child(timer_value)
	col.add_child(timer_row)
	timer_row.visible = false
	notice_label.text = ""
	_text(notice_label, 15, Color(MenuStyle.BONE, 0.85), 600, 9)
	col.add_child(notice_label)
	kicker.visible = false
	objective_label.visible = false


func _build_card() -> void:
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.modulate.a = 0.0
	root.add_child(card)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.62), Color(0, 0, 0, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var band := TextureRect.new()
	band.texture = gt
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.anchor_left = 0.0
	band.anchor_right = 1.0
	band.anchor_top = 0.5
	band.anchor_bottom = 0.5
	band.offset_left = 0.0
	band.offset_right = 0.0
	band.offset_top = -200.0
	band.offset_bottom = 160.0
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(band)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.offset_left = -700.0
	col.offset_right = 700.0
	col.offset_top = -130.0
	col.offset_bottom = 110.0
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	card_kicker = Label.new()
	_text(card_kicker, 20, Color(MenuStyle.BONE, 0.8), 600, 16)
	col.add_child(card_kicker)
	card_title = Label.new()
	_text(card_title, 92, MenuStyle.BONE, 300, 18)
	col.add_child(card_title)
	var rule_holder := CenterContainer.new()
	rule_holder.custom_minimum_size.y = 26.0
	rule_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_rule = MenuStyle.rule(96.0)
	rule_holder.add_child(card_rule)
	col.add_child(rule_holder)
	card_sub = Label.new()
	_text(card_sub, 22, Color(MenuStyle.BONE, 0.7), 400, 3)
	col.add_child(card_sub)


func _build_subtitles() -> void:
	subtitle_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	subtitle_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	subtitle_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	subtitle_panel.offset_top = -104.0
	subtitle_panel.offset_bottom = -104.0
	subtitle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.content_margin_left = 30.0
	sb.content_margin_right = 30.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 14.0
	subtitle_panel.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_panel.add_child(col)
	_text(speaker_label, 15, MenuStyle.DIM, 700, 8)
	col.add_child(speaker_label)
	_text(subtitle_label, 26, MenuStyle.BONE, 500, 1)
	col.add_child(subtitle_label)
	subtitle_layer.layer = MenuStyle.LAYER_SUBTITLES
	subtitle_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(subtitle_layer)
	subtitle_layer.add_child(subtitle_panel)
	subtitle_panel.visible = false


# ----------------------------------------------------------------------------- what to show

func set_objective(text: String) -> void:
	var show := text != ""
	kicker.visible = show
	objective_label.visible = show
	if objective_label.text != text:
		objective_label.text = text
		if show:
			if _objective_tween != null:
				_objective_tween.kill()
			objective_label.modulate = Color(1.6, 1.45, 1.2)
			_objective_tween = create_tween()
			_objective_tween.tween_property(objective_label, "modulate", Color.WHITE, 1.1)


## Progress 0..1 of a hold, or a negative number for none.
func set_hold(progress: float) -> void:
	hold_back.visible = progress >= 0.0
	hold_fill.size.x = hold_back.custom_minimum_size.x * clampf(progress, 0.0, 1.0)


## Running timers: [{id, label, left}]. The first is shown.
func set_timers(list: Array) -> void:
	timer_row.visible = not list.is_empty()
	if list.is_empty():
		_timer_low = false
		return
	var left: float = list[0]["left"]
	timer_name.text = String(list[0]["label"])
	timer_value.text = "%d:%02d" % [int(left) / 60, int(left) % 60]
	_timer_low = left < 20.0
	timer_value.add_theme_color_override("font_color", MenuStyle.BONE if not _timer_low else Color(1.0, 0.3, 0.26).lerp(MenuStyle.BONE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)))


## Show the radio's line now ({} for none; Radio.current_subtitle()): its speaker in their own colour,
## wrapped text. Called every frame, so the Subtitles setting takes effect at once; the text is
## only rebuilt when the line changes.
func set_subtitle(cur: Dictionary) -> void:
	if cur.is_empty() or not Settings.subtitles:
		subtitle_panel.visible = false
		return
	if String(cur["id"]) != _subtitle_id:
		_subtitle_id = String(cur["id"])
		speaker_label.text = String(cur["name"]).to_upper()
		speaker_label.add_theme_color_override("font_color", cur["color"])
		subtitle_label.text = _wrap(cur["text"], MenuStyle.font(500, 1), 26, 820.0)
		subtitle_panel.visible = true
		subtitle_panel.reset_size()
	elif not subtitle_panel.visible:
		subtitle_panel.visible = true
		subtitle_panel.reset_size()


## Break `text` into lines no wider than `max_w` pixels (a Label that wraps itself sizes badly inside a container).
func _wrap(text: String, f: Font, px: int, max_w: float) -> String:
	var lines: Array = []
	var line := ""
	for word in text.split(" "):
		var tryline: String = word if line == "" else line + " " + word
		if line != "" and f.get_string_size(tryline, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x > max_w:
			lines.append(line)
			line = word
		else:
			line = tryline
	lines.append(line)
	return "\n".join(lines)


func notice(text: String) -> void:
	notice_label.text = text.to_upper()
	if _notice_tween != null:
		_notice_tween.kill()
	notice_label.modulate.a = 1.0
	_notice_tween = create_tween()
	_notice_tween.tween_interval(1.8)
	_notice_tween.tween_property(notice_label, "modulate:a", 0.0, 0.9)


## A card across the middle of the screen: a small line over a large one, fading in and out.
func show_card(top: String, title: String, below: String = "", seconds: float = 3.4) -> void:
	card_kicker.text = top.to_upper()
	card_title.text = title.to_upper()
	card_sub.text = below
	if _card_tween != null:
		_card_tween.kill()
	card.modulate.a = 0.0
	_card_tween = create_tween()
	_card_tween.tween_property(card, "modulate:a", 1.0, 0.55)
	_card_tween.tween_interval(seconds)
	_card_tween.tween_property(card, "modulate:a", 0.0, 1.0)


func hide_card() -> void:
	if _card_tween != null:
		_card_tween.kill()
	card.modulate.a = 0.0


func set_radar(pos: Vector2, angle: float, blips: Array, speed: float = 0.0, route: PackedVector2Array = PackedVector2Array()) -> void:
	radar.set_state(pos, angle, blips, speed, route)

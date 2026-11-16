class_name Hud
extends CanvasLayer
## A sparse HUD: first-light countdown, hull and boost bars, speed, the intro card and the end
## screens, all in the menus' face (MenuStyle). Everything is made in code so there are no scene
## resources to keep in step.

const BAR_WIDTH := 258.0
const BAR_HEIGHT := 6.0
const HULL_COLOR := Color(0.8, 0.2, 0.17, 0.95)
const BOOST_COLOR := Color(0.86, 0.88, 0.84, 0.9)

var root := Control.new()
var timer_label := Label.new()
var speed_label := Label.new()
var unit_label := Label.new()
var kills_label := Label.new()
var hull_back := ColorRect.new()
var hull_fill := ColorRect.new()
var boost_back := ColorRect.new()
var boost_fill := ColorRect.new()
var center := Label.new()
var sub := Label.new()
var hint := Label.new()
var warn := Label.new()
var intro_time := 7.0
var story := false
var hull_label := Label.new()
var boost_label := Label.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_label(timer_label, 26, Color(MenuStyle.BONE, 0.9), 500, 7)
	timer_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	timer_label.offset_top = 22
	timer_label.offset_left = -200
	timer_label.offset_right = 200
	timer_label.offset_bottom = 66
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_label(speed_label, 56, Color(MenuStyle.BONE, 0.95), 400, 2)
	speed_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	speed_label.offset_left = -240
	speed_label.offset_top = -108
	speed_label.offset_right = -36
	speed_label.offset_bottom = -44
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label(unit_label, 14, Color(MenuStyle.BONE, 0.72), 600, 8)
	unit_label.text = "KM/H"
	unit_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	unit_label.offset_left = -240
	unit_label.offset_top = -50
	unit_label.offset_right = -36
	unit_label.offset_bottom = -28
	unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_label(kills_label, 14, Color(MenuStyle.BONE, 0.72), 600, 7)
	kills_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	kills_label.offset_left = -340
	kills_label.offset_top = -26
	kills_label.offset_right = -36
	kills_label.offset_bottom = -4
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	for pair in [[hull_back, hull_fill, 0], [boost_back, boost_fill, 1]]:
		var back: ColorRect = pair[0]
		var fill: ColorRect = pair[1]
		back.color = Color(1.0, 1.0, 1.0, 0.12)
		back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		back.offset_left = 36
		back.offset_right = 36 + BAR_WIDTH + 2.0
		back.offset_top = -64 + int(pair[2]) * 34
		back.offset_bottom = -64 + int(pair[2]) * 34 + BAR_HEIGHT + 2.0
		fill.position = Vector2(1, 1)
		fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
		back.add_child(fill)
		root.add_child(back)
	hull_fill.color = HULL_COLOR
	boost_fill.color = BOOST_COLOR
	var hl := hull_label
	_label(hl, 14, Color(MenuStyle.BONE, 0.72), 600, 7)
	hl.text = "HULL"
	hl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hl.offset_left = 36
	hl.offset_right = 200
	hl.offset_top = -88
	hl.offset_bottom = -66
	root.add_child(hl)
	var bl := boost_label
	_label(bl, 14, Color(MenuStyle.BONE, 0.72), 600, 7)
	bl.text = "BOOST"
	bl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bl.offset_left = 36
	bl.offset_right = 200
	bl.offset_top = -54
	bl.offset_bottom = -32
	root.add_child(bl)

	_label(center, 64, MenuStyle.BONE, 300, 14)
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.offset_left = -600
	center.offset_right = 600
	center.offset_top = -120
	center.offset_bottom = -30
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(sub, 24, Color(MenuStyle.BONE, 0.85), 400, 3)
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sub.offset_left = -600
	sub.offset_right = 600
	sub.offset_top = -20
	sub.offset_bottom = 100
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(hint, 17, Color(MenuStyle.BONE, 0.62), 500, 2)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -640
	hint.offset_right = 640
	hint.offset_top = -190
	hint.offset_bottom = -140
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(warn, 20, Color(0.95, 0.3, 0.25, 0.95), 600, 6)
	warn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	warn.offset_left = -300
	warn.offset_right = 300
	warn.offset_top = 64
	warn.offset_bottom = 104
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for l in [timer_label, speed_label, unit_label, kills_label, center, sub, hint, warn]:
		root.add_child(l)
	show_intro()


func _label(l: Label, size: int, color: Color, weight: int = 400, tracking: int = 2) -> void:
	l.add_theme_font_override("font", MenuStyle.font(weight, tracking))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


## The story's HUD: the first-light countdown and the intro card give way to the objective and radar
## (StoryHud), and the hull and boost bars move to the right of the radar in the corner.
func use_story_layout() -> void:
	story = true
	timer_label.visible = false
	kills_label.visible = false
	intro_time = 0.0
	center.text = ""
	sub.text = ""
	hint.text = ""
	warn.offset_top = 176  # below the objective, its hold bar and the timers
	warn.offset_bottom = 216
	var shift := StoryHud.RADAR_SIZE + 26.0
	for c in [hull_back, boost_back]:
		c.offset_left += shift
		c.offset_right += shift
	for c in [hull_label, boost_label]:
		c.offset_left += shift
		c.offset_right += shift


func show_intro() -> void:
	center.text = "HOLLOW HOURS"
	sub.text = "Survive until first light."
	hint.text = "W / S  throttle and brake     A / D  steer     SPACE  handbrake     SHIFT  boost\nThrow them off with a slide. Run them down. Stay out of the dark."
	intro_time = 7.0


func update_hud(game: GameSim, latched: int, delta: float) -> void:
	var left := maxf(0.0, GameSim.NIGHT_LENGTH - game.time)
	if game.phase == GameSim.Phase.DAWN:
		timer_label.text = "FIRST LIGHT"
	else:
		timer_label.text = "FIRST LIGHT IN  %d:%02d" % [int(left) / 60, int(left) % 60]
	speed_label.text = "%d" % int(game.car.speed() * 3.6)
	kills_label.text = "RUN DOWN  %d" % game.kills
	hull_fill.size.x = BAR_WIDTH * clampf(game.hull / GameSim.MAX_HULL, 0.0, 1.0)
	boost_fill.size.x = BAR_WIDTH * clampf(game.gauge, 0.0, 1.0)
	boost_fill.color = BOOST_COLOR if not game.dry else Color(0.5, 0.5, 0.52, 0.7)
	hull_fill.color = HULL_COLOR if game.hull > 30.0 else Color(1.0, 0.14, 0.1, 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.015))
	warn.text = "SOMETHING IS ON THE CAR" if latched > 0 else ""
	if intro_time > 0.0 and not story:
		intro_time -= delta
		var a := clampf(intro_time / 2.0, 0.0, 1.0)
		center.modulate.a = a
		sub.modulate.a = a
		hint.modulate.a = a
		if intro_time <= 0.0 and game.phase == GameSim.Phase.PLAYING:
			center.text = ""
			sub.text = ""
			hint.text = ""
			center.modulate.a = 1.0
			sub.modulate.a = 1.0
			hint.modulate.a = 1.0


func show_end(phase: int, game: GameSim) -> void:
	center.modulate.a = 1.0
	sub.modulate.a = 1.0
	hint.modulate.a = 1.0
	intro_time = 0.0
	if phase == GameSim.Phase.WRECKED:
		center.text = "WRECKED"
		sub.text = "They have it.  You lasted %d:%02d and ran down %d." % [int(game.time) / 60, int(game.time) % 60, game.kills]
	else:
		center.text = "FIRST LIGHT"
		sub.text = "You made it.  Hull %d%%,  %d run down." % [int(game.hull), game.kills]
	hint.text = "R  to go again"


func clear_end() -> void:
	center.text = ""
	sub.text = ""
	hint.text = ""

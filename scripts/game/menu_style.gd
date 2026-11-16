class_name MenuStyle
extends RefCounted
## The look of every menu: one light display face (Cormorant, SIL Open Font License, in
## assets/fonts/) set wide and quiet, bone-coloured on black, with a single dried-blood accent.
## Menus are laid out for the project's 1600 by 900 canvas; the window scales it.

const FONT_PATH := "res://assets/fonts/Cormorant.ttf"
const BONE := Color(0.89, 0.9, 0.87)
const DIM := Color(0.52, 0.55, 0.58)
const FAINT := Color(0.32, 0.34, 0.37)
const BLOOD := Color(0.72, 0.14, 0.11)
const MARGIN_X := 104.0
## The OpenType "wght" axis tag, as the text server wants it.
const WGHT := 2003265652
## "liga", switched off: the face ties letter pairs like TT together, which looks wrong at wide spacing.
const LIGA := 1818847073
## "lnum": lining figures, so 100 reads as a number and not as old-style letters.
const LNUM := 1819178349

static var _fonts := {}


## Cormorant at a weight (300 light to 700 bold) and a letter-spacing in pixels.
static func font(weight: int, tracking: int) -> Font:
	var key := weight * 1000 + tracking
	if _fonts.has(key):
		return _fonts[key]
	var f := FontVariation.new()
	f.base_font = load(FONT_PATH)
	f.variation_opentype = {WGHT: float(weight)}
	f.opentype_features = {LIGA: 0, LNUM: 1}
	f.spacing_glyph = tracking
	_fonts[key] = f
	return f


## A plain, non-interactive label in the menu face.
static func label(text: String, px: int, color: Color, weight: int = 400, tracking: int = 4) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight, tracking))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A thin rule in the accent colour.
static func rule(width: float, alpha: float = 0.9) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(BLOOD.r, BLOOD.g, BLOOD.b, alpha)
	r.custom_minimum_size = Vector2(width, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## The dark left side of a screen that carries a menu: black at the left edge fading out by 55% of the width.
static func left_shade() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.0, 0.0, 0.92))
	g.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.0, 0.0)
	gt.fill_to = Vector2(1.0, 0.0)
	var left := TextureRect.new()
	left.texture = gt
	left.stretch_mode = TextureRect.STRETCH_SCALE
	left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.anchor_right = 0.55
	left.offset_right = 0.0
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return left


## A screen heading: the title in the display face over the short accent rule.
static func heading(text: String, px: int = 64, tracking: int = 14) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	var title := label(text, px, BONE, 300, tracking)
	title.custom_minimum_size.y = 70
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 30)
	pad.add_child(title)
	col.add_child(pad)
	var holder := Control.new()
	holder.custom_minimum_size.y = 34
	var r := rule(72)
	r.position = Vector2(30, 6)
	holder.add_child(r)
	col.add_child(holder)
	return col

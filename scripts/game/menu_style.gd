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

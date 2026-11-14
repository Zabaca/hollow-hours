class_name Settings
extends RefCounted
## Graphics switches. F3 flips between High and Low at run time (Main.gd applies them).

static var high := true
static var sdfgi := true
static var ssr := true
static var volumetric := true
static var ssao := true
static var msaa := true

static func apply_preset(is_high: bool) -> void:
	high = is_high
	sdfgi = is_high
	ssr = is_high
	ssao = is_high
	volumetric = true
	msaa = is_high

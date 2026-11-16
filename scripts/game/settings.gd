class_name Settings
extends RefCounted
## Graphics switches (F3 flips High and Low at run time; main.gd applies them) and the player's
## settings: volumes per bus, graphics, fullscreen and subtitles. The player's settings live as
## JSON in the data folder, are loaded once at start (`boot`) and saved whenever one changes.

const VERSION := 1
## Setting key -> audio bus. Master is bus 0; the others are made by AudioMix.ensure_buses.
const VOLUME_BUSES := {
	"master": "Master", "music": "Music", "effects": "SFX", "car": "Car", "ambience": "Ambience", "voice": "Voice",
}
const VOLUME_ORDER := ["master", "music", "effects", "car", "ambience", "voice"]

## The preset in force (F3, Graphics in Settings, or the --low flag for one run).
static var high := true
## The player's own choice, the one a saved file holds. Differs from `high` only while a
## run-time override such as --low is in force, so the override never reaches the file.
static var saved_high := true
static var sdfgi := true
static var ssr := true
static var volumetric := true
static var ssao := true
static var msaa := true

static var volumes := {"master": 1.0, "music": 1.0, "effects": 1.0, "car": 1.0, "ambience": 1.0, "voice": 1.0}
static var fullscreen := false
static var subtitles := true
static var booted := false
## Where they are kept; tests point it somewhere of their own.
static var file_path := "user://settings.json"


static func apply_preset(is_high: bool) -> void:
	high = is_high
	sdfgi = is_high
	ssr = is_high
	ssao = is_high
	volumetric = true
	msaa = is_high


## Load the saved settings and apply them, once per run. Safe to call from every scene.
static func boot() -> void:
	if booted:
		return
	booted = true
	AudioMix.ensure_buses()
	load_file()
	apply_all()


static func defaults() -> void:
	for k in volumes:
		volumes[k] = 1.0
	apply_preset(true)
	saved_high = true
	fullscreen = false
	subtitles = true


static func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"volumes": volumes.duplicate(),
		"graphics": "high" if saved_high else "low",
		"fullscreen": fullscreen,
		"subtitles": subtitles,
	}


## Read settings from a dictionary; anything missing or of the wrong type keeps its default.
static func from_dict(d: Dictionary) -> void:
	defaults()
	var v: Variant = d.get("volumes", {})
	if v is Dictionary:
		for k in volumes:
			var x: Variant = (v as Dictionary).get(k)
			if x is float or x is int:
				volumes[k] = clampf(float(x), 0.0, 1.0)
	var g: Variant = d.get("graphics")
	if g is String and g == "low":
		apply_preset(false)
		saved_high = false
	if d.get("fullscreen") is bool:
		fullscreen = d["fullscreen"]
	if d.get("subtitles") is bool:
		subtitles = d["subtitles"]


## Write the settings (SaveStore does it through a temporary file and a rename).
static func save_file(path: String = "") -> bool:
	return SaveStore.write_json(path if path != "" else file_path, to_dict())


## Returns true when a readable file was loaded. A missing file leaves the defaults; a damaged
## or unknown-version one leaves the defaults and is kept aside (SaveStore.set_aside), not deleted.
static func load_file(path: String = "") -> bool:
	if path == "":
		path = file_path
	defaults()
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = SaveStore.read_json(path)
	if parsed == null:
		SaveStore.set_aside(path)
		return false
	var version: Variant = (parsed as Dictionary).get("version")
	if not (version is float or version is int) or int(version) != VERSION:
		SaveStore.set_aside(path)
		return false
	from_dict(parsed)
	return true


static func apply_all() -> void:
	apply_audio()
	apply_window()


static func apply_audio() -> void:
	for k in VOLUME_BUSES:
		var i := AudioServer.get_bus_index(VOLUME_BUSES[k])
		if i < 0:
			continue
		var linear: float = volumes[k]
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))


static func apply_window() -> void:
	var m := DisplayServer.window_get_mode()
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if m != want:
		DisplayServer.window_set_mode(want)


static func set_volume(key: String, value: float) -> void:
	volumes[key] = clampf(value, 0.0, 1.0)
	apply_audio()
	save_file()


## The graphics preset as a player choice: applied by the caller's scene, remembered here.
static func set_graphics(is_high: bool) -> void:
	apply_preset(is_high)
	saved_high = is_high
	save_file()


static func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply_window()
	save_file()


static func set_subtitles(on: bool) -> void:
	subtitles = on
	save_file()

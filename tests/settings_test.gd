extends Node
## Headless checks for the player's settings: the JSON round trip, the defaults on a missing or
## damaged file, and that the volumes reach the audio buses.
##
##   godot --headless --path . res://tests/settings_test.tscn
##
## It writes only to its own file under user://, never to the real settings file.

const PATH := "user://settings_test.json"

var failures := 0


func _ready() -> void:
	_test_missing_file_gives_defaults()
	_test_round_trip()
	_test_no_temp_file_left()
	_test_damaged_file_gives_defaults()
	_test_unknown_version_gives_defaults()
	_test_bad_fields_keep_defaults_and_volumes_clamp()
	_test_volumes_reach_buses()
	_cleanup()
	print("")
	print("settings_test: %d failed" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, name: String, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL "), name, ("  " + detail) if detail != "" else "")
	if not ok:
		failures += 1


func _cleanup() -> void:
	for p in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _is_default() -> bool:
	for k in Settings.volumes:
		if not is_equal_approx(Settings.volumes[k], 1.0):
			return false
	return Settings.high and not Settings.fullscreen and Settings.subtitles


func _write_raw(text: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _test_missing_file_gives_defaults() -> void:
	_cleanup()
	Settings.volumes["music"] = 0.2
	var loaded := Settings.load_file(PATH)
	_check(not loaded and _is_default(), "a missing file loads the defaults")


func _test_round_trip() -> void:
	Settings.defaults()
	Settings.volumes["master"] = 0.8
	Settings.volumes["music"] = 0.35
	Settings.volumes["effects"] = 0.0
	Settings.volumes["voice"] = 0.65
	Settings.apply_preset(false)
	Settings.fullscreen = true
	Settings.subtitles = false
	var saved := Settings.save_file(PATH)
	Settings.defaults()
	var loaded := Settings.load_file(PATH)
	var ok := loaded and saved
	ok = ok and is_equal_approx(Settings.volumes["master"], 0.8) and is_equal_approx(Settings.volumes["music"], 0.35)
	ok = ok and is_equal_approx(Settings.volumes["effects"], 0.0) and is_equal_approx(Settings.volumes["voice"], 0.65)
	ok = ok and is_equal_approx(Settings.volumes["car"], 1.0) and not Settings.high and not Settings.sdfgi
	ok = ok and Settings.fullscreen and not Settings.subtitles
	_check(ok, "saved settings read back the same", "high=%s fullscreen=%s subtitles=%s" % [Settings.high, Settings.fullscreen, Settings.subtitles])


func _test_no_temp_file_left() -> void:
	_check(not FileAccess.file_exists(PATH + ".tmp"), "a save leaves no temporary file behind")


func _test_damaged_file_gives_defaults() -> void:
	_write_raw("{\"version\": 1, \"volumes\": {\"master\": 0.")
	var loaded := Settings.load_file(PATH)
	_check(not loaded and _is_default(), "a half-written file loads the defaults")
	_write_raw("not json at all")
	loaded = Settings.load_file(PATH)
	_check(not loaded and _is_default(), "a file that is not JSON loads the defaults")
	_write_raw("[1, 2, 3]")
	loaded = Settings.load_file(PATH)
	_check(not loaded and _is_default(), "JSON that is not an object loads the defaults")


func _test_unknown_version_gives_defaults() -> void:
	_write_raw(JSON.stringify({"version": 99, "volumes": {"master": 0.1}, "graphics": "low", "fullscreen": true}))
	var loaded := Settings.load_file(PATH)
	_check(not loaded and _is_default(), "an unknown version loads the defaults")


func _test_bad_fields_keep_defaults_and_volumes_clamp() -> void:
	_write_raw(JSON.stringify({"version": 1, "volumes": {"master": 7.0, "music": -3, "car": "loud", "voice": 0.5}, "graphics": 12, "fullscreen": "yes", "subtitles": false}))
	var loaded := Settings.load_file(PATH)
	var ok := loaded
	ok = ok and is_equal_approx(Settings.volumes["master"], 1.0) and is_equal_approx(Settings.volumes["music"], 0.0)
	ok = ok and is_equal_approx(Settings.volumes["car"], 1.0) and is_equal_approx(Settings.volumes["voice"], 0.5)
	ok = ok and Settings.high and not Settings.fullscreen and not Settings.subtitles
	_check(ok, "wrong-typed fields keep their defaults and volumes clamp to 0..1")


func _test_volumes_reach_buses() -> void:
	AudioMix.ensure_buses()
	var count := AudioServer.bus_count
	AudioMix.ensure_buses()
	_check(AudioServer.bus_count == count, "making the buses twice does not duplicate them", "buses=%d" % count)
	var names_ok := true
	for k in Settings.VOLUME_BUSES:
		if AudioServer.get_bus_index(Settings.VOLUME_BUSES[k]) < 0:
			names_ok = false
	_check(names_ok, "every volume has a bus (Master, Music, SFX, Car, Ambience, Voice)")
	Settings.defaults()
	Settings.volumes["music"] = 0.5
	Settings.volumes["voice"] = 0.0
	Settings.apply_audio()
	var music_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	var voice_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Voice"))
	var master_db := AudioServer.get_bus_volume_db(0)
	_check(absf(music_db - (-6.02)) < 0.05 and voice_db < -60.0 and absf(master_db) < 0.01, "the volumes are applied to their buses", "music=%.2f dB voice=%.1f dB master=%.2f dB" % [music_db, voice_db, master_db])

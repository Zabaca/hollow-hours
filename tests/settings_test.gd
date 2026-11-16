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
	_test_damaged_files_are_kept_aside()
	_test_run_time_graphics_override_is_not_saved()
	_test_mute_survives_a_new_audio_mix()
	_cleanup()
	print("")
	print("settings_test: %d failed" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, name: String, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL "), name, ("  " + detail) if detail != "" else "")
	if not ok:
		failures += 1


func _cleanup() -> void:
	var d := DirAccess.open("user://")
	for f in d.get_files():
		if f.begins_with("settings_test.json"):
			d.remove(f)


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
	Settings.saved_high = false  # the player's choice (set_graphics does both, and saves)
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


func _aside() -> Array:
	var out: Array = []
	for f in DirAccess.open("user://").get_files():
		if f.begins_with("settings_test.json.bad"):
			out.append(f)
	return out


func _test_damaged_files_are_kept_aside() -> void:
	_cleanup()
	_write_raw("{\"version\": 1, \"volumes\": {\"master\": 0.")
	Settings.load_file(PATH)
	var first := _aside()
	_check(first.size() == 1 and not FileAccess.file_exists(PATH), "a damaged settings file is kept aside, not deleted", str(first))
	if first.size() == 1:
		_check(FileAccess.get_file_as_string("user://" + first[0]).begins_with("{\"version\": 1"), "and kept as it was")
	_write_raw(JSON.stringify({"version": 99, "volumes": {"master": 0.1}}))
	Settings.load_file(PATH)
	_check(_aside().size() == 2 and _is_default(), "so is a file of an unknown version", str(_aside()))
	_cleanup()


## --low is for one run: it must not end up as the saved choice when another setting changes.
func _test_run_time_graphics_override_is_not_saved() -> void:
	_cleanup()
	var kept := Settings.file_path
	Settings.file_path = PATH
	Settings.defaults()
	Settings.apply_preset(false)  # what main.gd does for --low
	Settings.set_volume("music", 0.4)
	var saved: Variant = SaveStore.read_json(PATH)
	_check(saved != null and saved["graphics"] == "high" and not Settings.high, "--low is in force for the run but the saved choice stays High", str(saved))
	Settings.set_graphics(false)
	saved = SaveStore.read_json(PATH)
	_check(saved["graphics"] == "low", "choosing Low in Settings saves it")
	Settings.set_graphics(true)
	saved = SaveStore.read_json(PATH)
	_check(saved["graphics"] == "high" and Settings.high, "and choosing High saves that")
	Settings.file_path = kept
	Settings.defaults()
	_cleanup()


## Quit to menu builds a new AudioMix: the master bus stays muted, so the new one must know.
func _test_mute_survives_a_new_audio_mix() -> void:
	AudioMix.ensure_buses()
	AudioServer.set_bus_mute(0, false)
	var first := AudioMix.new()
	first.toggle_mute()
	var muted_now := AudioServer.is_bus_mute(0)
	var second := AudioMix.new()  # a new round after Quit to menu
	second.toggle_mute()
	_check(muted_now and not AudioServer.is_bus_mute(0), "M after Quit to menu unmutes a bus the last round muted")
	second.toggle_mute()
	_check(AudioServer.is_bus_mute(0), "and mutes it again")
	AudioServer.set_bus_mute(0, false)
	first.free()
	second.free()

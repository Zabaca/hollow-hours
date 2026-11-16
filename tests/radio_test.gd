extends Node
## Headless checks for the radio: every story line has an audio file and no file is an orphan, the
## Voice bus sounds like a radio, and the Radio plays calls in order without overlap, lets a
## priority line jump the queue, ducks the music and exposes the subtitle and its timing.
##
##   godot --headless --path . res://tests/radio_test.tscn
##
## The radio runs on its own clock, so the queue is stepped by hand with `advance`.

const STEP := 0.05

var failures := 0


func _ready() -> void:
	_test_files()
	_test_voice_bus()
	_test_call_sequence()
	_test_priority_jumps()
	_test_subtitle()
	_test_text_only()
	_test_duck()
	_test_events_and_clear()
	print("")
	print("radio_test: %d failed" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, name: String, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL "), name, ("  " + detail) if detail != "" else "")
	if not ok:
		failures += 1


func _radio() -> Radio:
	var r := Radio.new()
	add_child(r)
	return r


## Step until `done` is true or the bound runs out; returns the simulated seconds spent.
func _until(r: Radio, done: Callable, limit: float = 90.0) -> float:
	var t := 0.0
	while t < limit and not done.call():
		r.advance(STEP)
		t += STEP
	return t


## Run the radio dry and record each line that starts, in order.
func _play_out(r: Radio) -> Array:
	var order: Array = []
	r.line_started.connect(func(id: String) -> void: order.append(id))
	_until(r, func() -> bool: return not r.is_busy())
	return order


# ----------------------------------------------------------------------------- the files


func _test_files() -> void:
	var voiced := Radio.voiced_ids()
	var missing: Array = []
	var unloadable: Array = []
	var lengths_ok := true
	var longest := 0.0
	for id in StoryData.LINES:
		var path := Radio.file_for(id)
		if id not in voiced or not ResourceLoader.exists(path):
			missing.append(id)
			continue
		var s: AudioStream = load(path)
		if s == null:
			unloadable.append(id)
			continue
		var secs := s.get_length()
		longest = maxf(longest, secs)
		if secs < 1.0 or secs > 12.0:
			lengths_ok = false
	_check(missing.is_empty(), "every story line has an audio file", str(missing))
	var orphans: Array = []
	for id in voiced:
		if not StoryData.LINES.has(id):
			orphans.append(id)
	_check(orphans.is_empty(), "no audio file is an orphan (every file is a story line)", str(orphans))
	_check(voiced.size() == StoryData.LINES.size(), "the audio files and the story lines are the same set", "files=%d lines=%d" % [voiced.size(), StoryData.LINES.size()])
	_check(unloadable.is_empty() and lengths_ok, "every file loads and runs between 1 and 12 seconds", "unloadable=%s longest=%.1fs" % [str(unloadable), longest])
	_check(ResourceLoader.exists(Radio.SQUELCH_IN) and ResourceLoader.exists(Radio.STATIC_OUT), "the squelch and the closing static exist")


func _test_voice_bus() -> void:
	AudioMix.ensure_buses()
	var vi := AudioServer.get_bus_index("Voice")
	var kinds: Array = []
	for i in AudioServer.get_bus_effect_count(vi):
		kinds.append(AudioServer.get_bus_effect(vi, i).get_class())
	var hp: AudioEffectHighPassFilter = AudioServer.get_bus_effect(vi, 0) if kinds.size() > 0 and kinds[0] == "AudioEffectHighPassFilter" else null
	var lp: AudioEffectLowPassFilter = AudioServer.get_bus_effect(vi, 1) if kinds.size() > 1 and kinds[1] == "AudioEffectLowPassFilter" else null
	var ok: bool = hp != null and lp != null and kinds.size() == 3 and kinds[2] == "AudioEffectDistortion"
	ok = ok and absf(hp.cutoff_hz - 300.0) < 1.0 and absf(lp.cutoff_hz - 3400.0) < 1.0
	_check(ok, "the Voice bus is a radio: high-pass 300 Hz, low-pass 3,400 Hz, then distortion", str(kinds))
	AudioMix.ensure_buses()
	_check(AudioServer.get_bus_effect_count(vi) == 3, "making the buses twice does not stack the radio effects")


# ----------------------------------------------------------------------------- the queue


func _test_call_sequence() -> void:
	var r := _radio()
	var phases: Array = []
	var speaking_at_once := 0
	var order: Array = []
	r.line_started.connect(func(id: String) -> void: order.append(id))
	r.say("bat_call_1")
	r.say("bat_call_2")
	var last := -1
	var t := 0.0
	while t < 60.0 and (r.is_busy() or last == -1):
		r.advance(STEP)
		t += STEP
		if r.phase != last:
			phases.append(r.phase)
			last = r.phase
		# Never two lines at once: a current line only exists while speaking.
		if not r.current.is_empty() and r.phase != Radio.Phase.SPEAKING:
			speaking_at_once += 1
	var want := [Radio.Phase.OPENING, Radio.Phase.SPEAKING, Radio.Phase.GAP, Radio.Phase.SPEAKING, Radio.Phase.CLOSING, Radio.Phase.IDLE]
	_check(phases == want, "a call opens with a squelch, speaks its lines with a gap, closes with static", str(phases))
	_check(order == ["bat_call_1", "bat_call_2"] and speaking_at_once == 0, "lines play in order and never overlap", str(order))
	_check(not r.is_busy() and r.queue.is_empty(), "the radio is idle when the call is over", "took %.1fs of radio time" % t)
	r.free()


func _test_priority_jumps() -> void:
	var r := _radio()
	var order: Array = []
	r.line_started.connect(func(id: String) -> void: order.append(id))
	r.say("bat_shop")
	_until(r, func() -> bool: return r.phase == Radio.Phase.SPEAKING)
	r.say("bat_alarm")
	r.say("bat_loaded")
	r.say("wrecked", true)
	r.say("ph_failed", true)
	_check(r.queued_ids() == ["wrecked", "ph_failed", "bat_alarm", "bat_loaded"], "priority lines jump the queue and keep their own order", str(r.queued_ids()))
	_check(String(r.current["id"]) == "bat_shop", "a priority line does not cut the line already playing")
	_until(r, func() -> bool: return not r.is_busy())
	_check(order == ["bat_shop", "wrecked", "ph_failed", "bat_alarm", "bat_loaded"], "the played order follows the queue", str(order))
	r.free()


# ----------------------------------------------------------------------------- the subtitle


func _test_subtitle() -> void:
	var r := _radio()
	r.say("gate_call_1")
	_check(r.current_subtitle().is_empty(), "nothing is shown during the opening squelch")
	_until(r, func() -> bool: return r.phase == Radio.Phase.SPEAKING)
	var s := r.current_subtitle()
	var stream: AudioStream = load(Radio.file_for("gate_call_1"))
	var ok: bool = s.get("text", "") == StoryData.subtitle("gate_call_1") and not String(s["text"]).contains("[")
	ok = ok and s["name"] == "Ruck" and s["color"] == StoryData.SPEAKERS["ruck"]["color"] and s["speaker"] == "ruck"
	_check(ok, "the subtitle is the line's text without cue words, in the speaker's name and colour")
	_check(s["has_audio"] and absf(float(s["duration"]) - stream.get_length()) < 0.001, "its duration is the audio's length", "duration=%.2fs" % float(s["duration"]))
	for i in 20:
		r.advance(STEP)
	var s2 := r.current_subtitle()
	_check(float(s2["elapsed"]) > 0.9 and float(s2["remaining"]) < float(s["duration"]) - 0.9, "elapsed and remaining move with the line", "elapsed=%.2f remaining=%.2f" % [s2["elapsed"], s2["remaining"]])
	_until(r, func() -> bool: return r.current.is_empty())
	_check(r.current_subtitle().is_empty(), "the subtitle goes when the line ends")
	r.free()


func _test_text_only() -> void:
	var r := _radio()
	r.audio_dir = "res://tests/no_such_folder/"
	var finished: Array = []
	r.line_finished.connect(func(id: String) -> void: finished.append(id))
	r.say("end_ruck")
	_until(r, func() -> bool: return r.phase == Radio.Phase.SPEAKING)
	var s := r.current_subtitle()
	_check(not s["has_audio"] and absf(float(s["duration"]) - StoryData.reading_time("end_ruck")) < 0.001, "a line with no audio shows its subtitle for its reading time", "duration=%.2fs" % float(s["duration"]))
	_until(r, func() -> bool: return not r.is_busy())
	_check(finished == ["end_ruck"], "and finishes normally")
	r.free()


# ----------------------------------------------------------------------------- the music's dip


func _test_duck() -> void:
	var r := _radio()
	var music := AudioServer.get_bus_index("Music")
	var amp: AudioEffectAmplify = null
	for i in AudioServer.get_bus_effect_count(music):
		if AudioServer.get_bus_effect(music, i) is AudioEffectAmplify:
			amp = AudioServer.get_bus_effect(music, i)
	_check(amp != null, "the radio puts a dip on the Music bus")
	r.say("bat_loaded")
	_until(r, func() -> bool: return r.phase == Radio.Phase.SPEAKING)
	for i in 20:
		r.advance(STEP)
	_check(amp != null and absf(amp.volume_db - Radio.DUCK_DB) < 0.01, "the music is ducked while a line plays", "music dip=%.1f dB" % (amp.volume_db if amp != null else 0.0))
	_until(r, func() -> bool: return not r.is_busy())
	for i in 20:
		r.advance(STEP)
	_check(amp != null and absf(amp.volume_db) < 0.01, "and comes back when the call is over", "music dip=%.1f dB" % (amp.volume_db if amp != null else 0.0))
	r.free()


# ----------------------------------------------------------------------------- the simulation's events


func _test_events_and_clear() -> void:
	var r := _radio()
	r.on_event({"type": "objective", "text": "not a line"})
	_check(not r.is_busy(), "an event that is not a line is ignored")
	r.on_event({"type": "line", "id": "wrecked", "speaker": "vera", "priority": true})
	r.on_event({"type": "line", "id": "ph_failed", "speaker": "teo", "priority": false})
	_check(r.queued_ids() == ["wrecked", "ph_failed"], "line events are queued with their priority", str(r.queued_ids()))
	r.clear()
	_check(r.queue.is_empty() and r.current.is_empty(), "clear drops the queue and the current line")
	_until(r, func() -> bool: return not r.is_busy())
	_check(not r.is_busy(), "and the radio settles to idle")
	r.free()
	var d := _radio()
	d.say("bat_call_1")
	d.say("bat_shop")
	d.say("end_vera", true)
	d.say("bat_alarm")
	d.drop_ordinary()
	_check(d.queued_ids() == ["end_vera"], "drop_ordinary keeps the priority lines and drops the rest", str(d.queued_ids()))
	d.free()

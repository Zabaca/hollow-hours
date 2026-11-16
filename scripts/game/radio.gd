class_name Radio
extends Node
## The radio. Plays the story's lines one at a time on the Voice bus (a handheld radio: the bus
## filters and grits them), opens each call with a squelch and closes it with a burst of static,
## and dips the music while anyone is speaking. It owns no script: lines are StoryData's, and a
## line's audio is DIR + id + ".mp3". A line with no file shows its subtitle for its reading time,
## so everything works before any audio exists.
##
## A call is the lines that run back to back: squelch in, line, a short gap, line, ..., static out.
## Lines queue and never overlap. A priority line (a mission failed or completed) goes to the front
## of the queue; it does not cut the line already playing.
##
## The HUD reads `current_subtitle()` and the two signals; `on_event` takes the simulation's
## events, so the presenter can hand every event to the radio and nothing else.
##
## Timing is the radio's own clock (`advance`, called from _process), not the audio engine's, so
## the queue behaves the same with a dummy audio driver and a test can step it by hand.

signal line_started(id: String)
signal line_finished(id: String)

const DIR := "res://assets/audio/radio/"
const SQUELCH_IN := "res://assets/audio/radio_squelch_in.mp3"
const STATIC_OUT := "res://assets/audio/radio_static_out.mp3"
## Seconds of quiet between two lines of one call.
const GAP := 0.3
## The music's dip while the radio is speaking, in dB, and how fast it moves (dB per second).
const DUCK_DB := -10.0
const DUCK_RATE := 30.0

enum Phase { IDLE, OPENING, SPEAKING, GAP, CLOSING }

var phase := Phase.IDLE
## What is queued: [{id, priority}], the next line first.
var queue: Array = []
## The line being spoken: {id, speaker, name, color, text, duration, elapsed, has_audio}, or {}.
var current := {}
## The music's current dip in dB (0 when nothing is speaking).
var duck_db := 0.0

var _voice: AudioStreamPlayer
var _fx: AudioStreamPlayer
var _duck: AudioEffectAmplify
var _wait := 0.0
## Where line audio is looked for; a test points it at an empty folder to check the text-only path.
var audio_dir := DIR


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	AudioMix.ensure_buses()
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Voice"
	add_child(_voice)
	_fx = AudioStreamPlayer.new()
	_fx.bus = "Voice"
	add_child(_fx)
	_duck = _music_duck()


func _exit_tree() -> void:
	# Leave the Music bus as it was found.
	if _duck != null:
		_duck.volume_db = 0.0


func _process(delta: float) -> void:
	advance(delta)


## The file a line's audio lives in (it may not exist yet).
static func file_for(id: String) -> String:
	return DIR + id + ".mp3"


## Every line id that has an audio file in DIR, for the test that none is missing and none is extra.
static func voiced_ids() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		# An exported project lists the imported file as "<name>.mp3.import" or "<name>.mp3.remap".
		var base := f
		for suffix in [".import", ".remap"]:
			if base.ends_with(suffix):
				base = base.trim_suffix(suffix)
		if base.ends_with(".mp3") and base.get_basename() not in out:
			out.append(base.get_basename())
	return out


## Queue a line. Returns false (and says why) for an id the script does not have.
func say(id: String, priority: bool = false) -> bool:
	if not StoryData.LINES.has(id):
		push_error("Radio: no such line '%s'" % id)
		return false
	var entry := {"id": id, "priority": priority}
	if priority:
		var at := 0
		while at < queue.size() and queue[at]["priority"]:
			at += 1
		queue.insert(at, entry)
	else:
		queue.append(entry)
	if phase == Phase.IDLE:
		_open()
	return true


## The simulation's events, one at a time: a `line` event is queued, anything else is ignored.
func on_event(e: Dictionary) -> void:
	if e.get("type", "") == "line":
		say(String(e["id"]), bool(e.get("priority", false)))


## Drop everything queued and stop the current line, for a retry or a restart.
func clear() -> void:
	queue.clear()
	if not current.is_empty():
		current = {}
	_voice.stop()
	if phase != Phase.IDLE and phase != Phase.CLOSING:
		_close()


func is_busy() -> bool:
	return phase != Phase.IDLE


## What the HUD shows now, or {} when no one is speaking (the squelches and the gaps show nothing):
## id, speaker (the id), name, color, text (no cue words), duration, elapsed, remaining, has_audio.
func current_subtitle() -> Dictionary:
	if current.is_empty():
		return {}
	var s := current.duplicate()
	s["remaining"] = maxf(0.0, float(s["duration"]) - float(s["elapsed"]))
	return s


func queued_ids() -> Array:
	var out: Array = []
	for q in queue:
		out.append(q["id"])
	return out


## Step the radio's clock.
func advance(delta: float) -> void:
	match phase:
		Phase.OPENING:
			_wait -= delta
			if _wait <= 0.0:
				_next_line()
		Phase.SPEAKING:
			current["elapsed"] = float(current["elapsed"]) + delta
			if float(current["elapsed"]) >= float(current["duration"]):
				_end_line()
		Phase.GAP:
			_wait -= delta
			if _wait <= 0.0:
				_next_line()
		Phase.CLOSING:
			_wait -= delta
			if _wait <= 0.0:
				phase = Phase.IDLE
				if not queue.is_empty():
					_open()
	_move_duck(delta)


# ----------------------------------------------------------------------------- the call


func _open() -> void:
	phase = Phase.OPENING
	_wait = _play_fx(SQUELCH_IN)


func _close() -> void:
	phase = Phase.CLOSING
	_wait = _play_fx(STATIC_OUT)


func _next_line() -> void:
	if queue.is_empty():
		_close()
		return
	var entry: Dictionary = queue.pop_front()
	var id: String = entry["id"]
	var data: Dictionary = StoryData.LINES[id]
	var who: Dictionary = StoryData.SPEAKERS[data["speaker"]]
	var stream: AudioStream = null
	var path := audio_dir + id + ".mp3"
	if ResourceLoader.exists(path):
		stream = load(path)
	var duration := StoryData.reading_time(id)
	if stream != null:
		duration = maxf(stream.get_length(), 0.1)
		_voice.stream = stream
		_voice.play()
	current = {
		"id": id, "speaker": data["speaker"], "name": who["name"], "color": who["color"],
		"text": StoryData.subtitle(id), "duration": duration, "elapsed": 0.0, "has_audio": stream != null,
	}
	phase = Phase.SPEAKING
	line_started.emit(id)


func _end_line() -> void:
	var id: String = current["id"]
	current = {}
	line_finished.emit(id)
	if queue.is_empty():
		_close()
	else:
		phase = Phase.GAP
		_wait = GAP


## Play an effect on the Voice bus and say how long it runs (0 when its file does not exist).
func _play_fx(path: String) -> float:
	if not ResourceLoader.exists(path):
		return 0.0
	var s: AudioStream = load(path)
	_fx.stream = s
	_fx.play()
	return s.get_length()


# ----------------------------------------------------------------------------- the music's dip


## The dip is an Amplify on the Music bus, so the radio needs nothing from AudioMix (which sets the
## music's own levels every frame) and the Music volume setting is untouched.
func _music_duck() -> AudioEffectAmplify:
	var bus := AudioServer.get_bus_index("Music")
	for i in AudioServer.get_bus_effect_count(bus):
		var fx := AudioServer.get_bus_effect(bus, i)
		if fx is AudioEffectAmplify:
			return fx
	var amp := AudioEffectAmplify.new()
	AudioServer.add_bus_effect(bus, amp)
	return amp


func _move_duck(delta: float) -> void:
	var speaking := phase == Phase.OPENING or phase == Phase.SPEAKING or phase == Phase.GAP
	duck_db = move_toward(duck_db, DUCK_DB if speaking else 0.0, DUCK_RATE * delta)
	if _duck != null:
		_duck.volume_db = duck_db

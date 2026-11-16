class_name LineFeed
extends Node
## The subtitle seam: what the story presenter says radio lines to, and what the subtitle view reads.
## Anything that offers the same three members can stand in for it (the Radio, which also plays the
## audio, plugs in here):
##
##   say(id: String, priority: bool)   a line was spoken (a "line" event from MissionSim)
##   current() -> Dictionary           the line on screen now, or {}: {id, speaker, text, start, duration}
##                                     (`text` without cue words; `start` in seconds of engine time,
##                                     `duration` in seconds)
##   signal changed                    emitted when a line starts and when it ends
##
## This version has no audio: a line is up for StoryData.reading_time, lines queue one at a time, never
## overlap, and a priority line goes ahead of the ordinary ones waiting but behind earlier priority
## lines (so end_vera comes before end_ruck). The line already up is never cut off. It pauses with the
## scene tree.

signal changed

const GAP := 0.35  # seconds of silence between lines

var _queue: Array = []  # [{id, priority}]
var _now := {}
var _left := 0.0
var _gap := 0.0


func say(id: String, priority: bool = false) -> void:
	if not StoryData.LINES.has(id):
		return
	var item := {"id": id, "priority": priority}
	if not priority:
		_queue.append(item)
	else:
		var at := 0
		for i in _queue.size():
			if _queue[i]["priority"]:
				at = i + 1
		_queue.insert(at, item)
	if _now.is_empty() and _gap <= 0.0:
		_next()


func current() -> Dictionary:
	return _now


## Drop everything waiting and whatever is up (a retry or a restart starts the radio afresh).
func clear() -> void:
	_queue.clear()
	_gap = 0.0
	if not _now.is_empty():
		_now = {}
		changed.emit()


func _next() -> void:
	if _queue.is_empty():
		return
	var item: Dictionary = _queue.pop_front()
	var id: String = item["id"]
	_left = StoryData.reading_time(id)
	_now = {
		"id": id, "speaker": StoryData.LINES[id]["speaker"], "text": StoryData.subtitle(id),
		"start": Time.get_ticks_msec() / 1000.0, "duration": _left,
	}
	changed.emit()


func _process(delta: float) -> void:
	if _now.is_empty():
		if _gap > 0.0:
			_gap -= delta
			if _gap <= 0.0:
				_next()
		return
	_left -= delta
	if _left <= 0.0:
		_now = {}
		_gap = GAP
		changed.emit()

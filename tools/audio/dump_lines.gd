extends SceneTree
## Prints the radio script as one JSON line, `HOLLOW_LINES {...}`, for tools/audio/voices.ts, so the
## generator never keeps a second copy of the script.
##
##   godot --headless --path . --script res://tools/audio/dump_lines.gd

const StoryDataScript := preload("res://scripts/sim/story_data.gd")


func _init() -> void:
	var out: Array = []
	for id in StoryDataScript.LINES:
		var l: Dictionary = StoryDataScript.LINES[id]
		out.append({"id": id, "speaker": l["speaker"], "text": l["text"]})
	print("HOLLOW_LINES " + JSON.stringify(out))
	quit(0)

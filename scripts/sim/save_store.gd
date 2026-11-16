class_name SaveStore
extends RefCounted
## The save and the settings as JSON in the player's data folder. A write goes to a temporary file
## and is then renamed over the target, so a crash mid-write never leaves a broken file. A save that
## cannot be read, or has an unknown version or the wrong shape, counts as no save and is kept aside
## (renamed to <path>.bad-<time>), never deleted. The path is a parameter so tests use their own.

const VERSION := 1
const SAVE_PATH := "user://save.json"
const SETTINGS_PATH := "user://settings.json"


## Write `data` as JSON through a temporary file and a rename. False when it could not.
static func write_json(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	var ok := f.store_string(JSON.stringify(data, "\t"))
	f.flush()
	f.close()
	if not ok or DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	return true


## The dictionary in the file, or null when there is no file, it cannot be read or it is not an object.
static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return null
	return parser.data


## Rename a file we cannot use out of the way, keeping it. Returns where it went ("" if it failed).
static func set_aside(path: String) -> String:
	var stamp := int(Time.get_unix_time_from_system())
	var to := "%s.bad-%d" % [path, stamp]
	var n := 1
	while FileAccess.file_exists(to):
		to = "%s.bad-%d-%d" % [path, stamp, n]
		n += 1
	if DirAccess.rename_absolute(path, to) != OK:
		return ""
	return to


## Is this a save we can use: the version we know, the next mission a real one, the missions done
## the story's first few in order, and the totals numbers.
static func valid_save(d: Dictionary) -> bool:
	if not d.has("version") or typeof(d["version"]) not in [TYPE_FLOAT, TYPE_INT] or int(d["version"]) != VERSION:
		return false
	if typeof(d.get("next")) != TYPE_STRING or typeof(d.get("done")) != TYPE_ARRAY or typeof(d.get("totals")) != TYPE_DICTIONARY:
		return false
	if typeof(d.get("ending_seen")) != TYPE_BOOL:
		return false
	var done: Array = d["done"]
	if done.size() > StoryData.MISSIONS.size():
		return false
	for i in done.size():
		if typeof(done[i]) != TYPE_STRING or StoryData.mission_index(done[i]) != i:
			return false
	var expected := "" if done.size() >= StoryData.MISSIONS.size() else str(StoryData.MISSIONS[done.size()]["id"])
	if d["next"] != expected:
		return false
	for k in ["kills", "wrecks", "seconds"]:
		if typeof(d["totals"].get(k)) not in [TYPE_FLOAT, TYPE_INT]:
			return false
	return true


## The save, or {} when there is none (or it was damaged: then it is set aside).
static func load_save(path: String = SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = read_json(path)
	if d == null or not valid_save(d):
		set_aside(path)
		return {}
	return d


static func write_save(data: Dictionary, path: String = SAVE_PATH) -> bool:
	return write_json(path, data)


## Settings: the defaults with every key the file holds (of the same kind of value) laid over them.
## A missing file gives the defaults; a damaged one gives the defaults and is set aside.
static func load_settings(defaults: Dictionary, path: String = SETTINGS_PATH) -> Dictionary:
	var out := defaults.duplicate(true)
	if not FileAccess.file_exists(path):
		return out
	var d: Variant = read_json(path)
	if d == null:
		set_aside(path)
		return out
	for k in defaults:
		if not d.has(k):
			continue
		var want := typeof(defaults[k])
		var got := typeof(d[k])
		if want == got:
			out[k] = d[k]
		elif want == TYPE_INT and got == TYPE_FLOAT:
			out[k] = int(d[k])
		elif want == TYPE_FLOAT and got == TYPE_INT:
			out[k] = float(d[k])
	return out


static func write_settings(data: Dictionary, path: String = SETTINGS_PATH) -> bool:
	return write_json(path, data)

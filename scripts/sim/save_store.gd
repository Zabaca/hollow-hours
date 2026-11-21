class_name SaveStore
extends RefCounted
## The save as JSON in the player's data folder, and the JSON file I/O the settings (Settings in
## scripts/game/settings.gd, which owns their schema) go through too. A write goes to a temporary file
## and is then renamed over the target, so a crash mid-write never leaves a broken file. A save that
## cannot be read, or has an unknown version or the wrong shape, counts as no save and is kept aside
## (renamed to <path>.bad-<time>), never deleted. The path is a parameter so tests use their own.

const VERSION := 1
const SAVE_PATH := "user://save.json"


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
## the story's first few in order, and the totals numbers. `missions` is the story it is read against
## (StoryData.MISSIONS; a test hands a longer one).
##
## A save that finished the story as it was (next empty, the ending seen) is still good when the story
## has grown past it: it is one that finished a whole chapter, with the next chapter still to play
## (see upgraded()). Every other save with an empty `next` before the story's end is damaged.
static func valid_save(d: Dictionary, missions: Array = StoryData.MISSIONS) -> bool:
	if not d.has("version") or typeof(d["version"]) not in [TYPE_FLOAT, TYPE_INT] or int(d["version"]) != VERSION:
		return false
	if typeof(d.get("next")) != TYPE_STRING or typeof(d.get("done")) != TYPE_ARRAY or typeof(d.get("totals")) != TYPE_DICTIONARY:
		return false
	if typeof(d.get("ending_seen")) != TYPE_BOOL:
		return false
	if d.has("finished") and typeof(d["finished"]) != TYPE_BOOL:
		return false
	var done: Array = d["done"]
	if done.size() > missions.size():
		return false
	for i in done.size():
		if typeof(done[i]) != TYPE_STRING or _index(done[i], missions) != i:
			return false
	var expected := "" if done.size() >= missions.size() else str(missions[done.size()]["id"])
	if d["next"] != expected and not _finished_a_chapter(d, missions):
		return false
	for k in ["kills", "wrecks", "seconds"]:
		if typeof(d["totals"].get(k)) not in [TYPE_FLOAT, TYPE_INT]:
			return false
	return true


static func _index(id: String, missions: Array) -> int:
	for i in missions.size():
		if missions[i]["id"] == id:
			return i
	return -1


## A save that ended the story when it was written (next empty, the ending seen) and finished exactly
## a chapter's last mission, or a mission that said the story went on (closes_story false), with missions still to come after it.
static func _finished_a_chapter(d: Dictionary, missions: Array) -> bool:
	var n := (d["done"] as Array).size()
	# ...or stopped after a mission that did not close the story (the missions after it had not been built yet).
	var stopped_short: bool = n > 0 and n < missions.size() and not bool(missions[n - 1].get("closes_story", true))
	return d["next"] == "" and d["ending_seen"] == true and n > 0 and n < missions.size() and (StoryData.ends_chapter(n - 1, missions) or stopped_short)


## A save that has every mission done, nothing next and was not written by the end of the story (no `finished`): the
## last mission was not all there was when it was made.
static func _unfinished_end(d: Dictionary, missions: Array) -> bool:
	var n := (d["done"] as Array).size()
	return n > 0 and n == missions.size() and d["next"] == "" and d.get("finished", false) != true and bool(missions[n - 1].get("closes_story", true))


## The save as the story reads it now: a save that finished a chapter the story has since grown past
## (see valid_save) gets the next chapter's first mission as `next`; any other save is returned as it is.
## `ending_seen` stays, so what it unlocked (Survive the Night) stays. Pass a valid save.
static func upgraded(d: Dictionary, missions: Array = StoryData.MISSIONS) -> Dictionary:
	if _unfinished_end(d, missions):
		# Written when the last mission's first part was all there was (the story went on in free roam after it, with
		# no ending): it reads as that mission still to play, from the start.
		var back := d.duplicate(true)
		(back["done"] as Array).pop_back()
		back["next"] = str(missions[missions.size() - 1]["id"])
		return back
	if not _finished_a_chapter(d, missions):
		return d
	var out := d.duplicate(true)
	out["next"] = str(missions[(d["done"] as Array).size()]["id"])
	return out


## The city the save puts the player in: the next mission's, or the last chapter's when the story is over.
static func city_of(d: Dictionary, missions: Array = StoryData.MISSIONS) -> String:
	return StoryData.city_after((d["done"] as Array).size(), missions)


## The save, or {} when there is none (or it was damaged: then it is set aside). A save from before the
## story grew comes back upgraded.
static func load_save(path: String = SAVE_PATH, missions: Array = StoryData.MISSIONS) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = read_json(path)
	if d == null or not valid_save(d, missions):
		set_aside(path)
		return {}
	return upgraded(d, missions)


static func write_save(data: Dictionary, path: String = SAVE_PATH) -> bool:
	return write_json(path, data)


## What the player has unlocked, kept beside the save but outside it, so starting a new story does not
## take it away. Today that is Survive the Night, offered once the story has been finished.
static func unlocks_path(save_path: String = SAVE_PATH) -> String:
	return save_path.get_base_dir().path_join(save_path.get_file().get_basename() + "_unlocks.json")


static func survive_unlocked(save_path: String = SAVE_PATH) -> bool:
	var d: Variant = read_json(unlocks_path(save_path))
	return d != null and d.get("survive") == true


static func unlock_survive(save_path: String = SAVE_PATH) -> bool:
	return _unlock("survive", save_path)


## Survive the Night in the harbour city: unlocked by finishing chapter 2.
static func harbour_unlocked(save_path: String = SAVE_PATH) -> bool:
	var d: Variant = read_json(unlocks_path(save_path))
	return d != null and d.get("survive_harbour") == true


static func unlock_survive_harbour(save_path: String = SAVE_PATH) -> bool:
	return _unlock("survive_harbour", save_path)


static func _unlock(key: String, save_path: String) -> bool:
	var d: Variant = read_json(unlocks_path(save_path))
	var out: Dictionary = d if d != null else {}
	out["version"] = VERSION
	out[key] = true
	return write_json(unlocks_path(save_path), out)

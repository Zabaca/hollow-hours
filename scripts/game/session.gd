class_name Session
extends RefCounted
## What the title hands to the game scene, and the command line both scenes read.
##
## Game flags (`--demo`, `--shot`, `--low`, `--start`, `--drive`, `--cam-log`, `--audio-log`, and
## `--shot-at`, `--shot-game`, `--shot-speed`) skip the menus and go straight into the round, so every
## command in the README still works. `--screen=NAME` opens one screen for a screenshot instead
## (title, settings, controls, credits, confirm, pause, pause-settings, and in a story map, fail, complete, ending);
## `--shot=PATH` and `--shot-at=SECONDS`
## then save a frame of that screen and quit.
##
## Story flags: `--story` starts a new story, `--continue` continues from the save, `--mission=N` (1 to 3)
## starts mission N directly, with the car at its start; all skip the menus. `--gate=open` or
## `--gate=opening` (opens 1.5 s in) shows the west gate open, for screenshots. `--save=PATH` reads and writes the save there instead of the
## player's (for screenshots of Continue); it does not skip the menus. `--seed=N` fixes the pack's seed.

const GAME_FLAGS := [
	"--demo", "--shot", "--shot-at", "--shot-game", "--shot-speed", "--low", "--start", "--drive",
	"--cam-log", "--audio-log", "--no-hud", "--story", "--mission", "--continue",
]
## Screens that live in the story: the game scene opens them over a mission.
const STORY_SCREENS := ["map", "fail", "complete", "ending"]
const MAIN_SCENE := "res://scenes/main.tscn"
const TITLE_SCENE := "res://scenes/title.tscn"

## "survival" is today's round (Survive the Night); "story" is the three missions.
static var mode := "survival"
## Story: the save to Continue from ({} for a new game), and a mission (1 to 3) to start directly (0 for none).
static var continue_save := {}
static var mission_flag := 0
static var save_path := SaveStore.SAVE_PATH
static var seed_flag := -1
static var continue_flag := false
## The screen a screenshot run asked for, "" for none.
static var screen := ""
static var shot_path := ""
static var shot_at := 4.0
static var parsed := false


static func parse_args() -> void:
	if parsed:
		return
	parsed = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screen="):
			screen = a.trim_prefix("--screen=")
			if screen in STORY_SCREENS:
				mode = "story"
		elif a.begins_with("--shot="):
			shot_path = a.trim_prefix("--shot=")
		elif a.begins_with("--shot-at="):
			shot_at = float(a.trim_prefix("--shot-at="))
		elif a == "--story":
			mode = "story"
		elif a == "--continue":
			mode = "story"
			continue_flag = true
		elif a.begins_with("--mission="):
			mode = "story"
			mission_flag = clampi(int(a.trim_prefix("--mission=")), 1, StoryData.MISSIONS.size())
		elif a.begins_with("--save="):
			save_path = a.trim_prefix("--save=")
		elif a.begins_with("--seed="):
			seed_flag = int(a.trim_prefix("--seed="))


## True when the command line carries a game flag and no menu screen was asked for.
static func goes_straight_to_game() -> bool:
	parse_args()
	if screen != "":
		return false
	for a in OS.get_cmdline_user_args():
		for f in GAME_FLAGS:
			if a == f or a.begins_with(f + "="):
				return true
	return false


## Save the next drawn frame of the window as a PNG and quit.
static func save_shot_and_quit(tree: SceneTree, path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := tree.root.get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("shot saved: ", path, " (", err, ")  size ", img.get_size())
	tree.quit()

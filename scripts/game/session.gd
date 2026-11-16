class_name Session
extends RefCounted
## What the title hands to the game scene, and the command line both scenes read.
##
## Game flags (`--demo`, `--shot`, `--low`, `--start`, `--drive`, `--cam-log`, `--audio-log`, and
## `--shot-at`, `--shot-game`, `--shot-speed`) skip the menus and go straight into the round, so every
## command in the README still works. `--screen=NAME` opens one screen for a screenshot instead
## (title, settings, controls, credits, pause, pause-settings); `--shot=PATH` and `--shot-at=SECONDS`
## then save a frame of that screen and quit.

const GAME_FLAGS := [
	"--demo", "--shot", "--shot-at", "--shot-game", "--shot-speed", "--low", "--start", "--drive",
	"--cam-log", "--audio-log", "--no-hud",
]
const MAIN_SCENE := "res://scenes/main.tscn"
const TITLE_SCENE := "res://scenes/title.tscn"

## "survival" is today's round. Slice 3 adds "story".
static var mode := "survival"
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
		elif a.begins_with("--shot="):
			shot_path = a.trim_prefix("--shot=")
		elif a.begins_with("--shot-at="):
			shot_at = float(a.trim_prefix("--shot-at="))


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

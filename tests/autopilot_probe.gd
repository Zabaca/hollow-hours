extends Node
## How well the autopilot drives the story, over many seeds. A probe: it prints a table and asserts
## nothing (mission_test pins five seeds); it is how a change to the autopilot, the world or the pack
## is checked for "no worse". Each seed plays the whole story as mission_test's live guard does: the
## creatures the story places are live, the director is off, 600 simulated seconds at most. Two runs:
## the hull held at full (only the timers and the steps can stop it) and the hull not held (a wreck
## ends the run).
##
##   godot --headless --path . res://tests/autopilot_probe.tscn
##   godot --headless --path . res://tests/autopilot_probe.tscn -- --seeds=20 --first=1 --mode=held|free|both --director=off|on
##
## `--director=on` leaves the pack's director running too (the story's pack sizes, newcomers appearing as the
## car moves), which is closer to the game and harder.

const DT := 1.0 / 120.0

var seeds := 20
var first := 1
var mode := "both"
var director := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.trim_prefix("--seeds="))
		elif a.begins_with("--first="):
			first = int(a.trim_prefix("--first="))
		elif a.begins_with("--mode="):
			mode = a.trim_prefix("--mode=")
		elif a.begins_with("--director="):
			director = a.trim_prefix("--director=") == "on"
	var t0 := Time.get_ticks_msec()
	for held in [true, false]:
		if (held and mode == "free") or (not held and mode == "held"):
			continue
		var wins := 0
		var notes: Array = []
		for s in range(first, first + seeds):
			var r := _drive(s, held)
			if r["ok"]:
				wins += 1
			else:
				notes.append("seed %d: %s" % [s, r["why"]])
		print("hull %s, director %s: %d of %d seeds finish all three missions" % ["held" if held else "not held", "on" if director else "off", wins, seeds])
		for n in notes:
			print("  ", n)
	print("wall time %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit(0)


func _drive(seed_in: int, held: bool) -> Dictionary:
	var sim := GameSim.new(CityLayout.DATA, "bruiser", seed_in, true)
	if not director:
		sim.pack.director_on = false
		sim.pack.gaunts.clear()
	var pilot := Autopilot.new()
	var done := 0
	var why := "ran out of time (%d missions done)"
	for i in int(600.0 / DT):
		if held:
			sim.hull = GameSim.MAX_HULL
		sim.step(DT, pilot.controls(sim, DT))
		for e in sim.take_events():
			match e["type"]:
				"mission_complete":
					done += 1
				"mission_failed":
					return {"ok": false, "why": "failed %s (%s) at %d s" % [e["id"], e["reason"], int(sim.time)]}
				"story_complete":
					return {"ok": true, "why": ""}
	return {"ok": false, "why": why % done}

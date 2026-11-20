extends Node
## A developer tool, not a test (it needs a window and is not in run_all.sh): puts one creature, driven by hand through
## a given state, in front of the car in the real city, saves a frame and quits. The creature is not in the pack, so the
## sim leaves it alone; its GauntView is the real one.
##
##   godot --path . --resolution 1600x900 --audio-driver Dummy res://tests/creature_shots.tscn -- \
##     --drive=0,0 --no-hud --seed=3 --start=-30,0,0 --scenario=stalk --at=1.0 --out=/tmp/stalk.png
##
## Scenarios: stalk (creeping at the edge of the headlights), lit (frozen in them, eyes shining), sprint, wind (the
## crouch), leap, latch (--slot=N: 0 roof, 1 hood, 2 trunk, 3 left, 4 right), thrown, stunned, missed, dead.
## --at is the seconds after the state begins; --cam=close puts the camera 4.2 m from the creature, --dist=M puts it M metres ahead of the car, --cam=front 3.4 m in front of its face, --cam=face 1.5 m from it at head height, instead of the chase camera.

var main: Node
var game: GameSim
var scenario := "stalk"
var out := "/tmp/creature.png"
var at := 1.0
var cam_mode := "chase"
var slot := 0
var dist := -1.0  # --dist=M: metres ahead of the car (and a little to the left) instead of the scenario's own spot
var started := false
var elapsed := 0.0
var shot_done := false
var g: GauntSim
var view: GauntView
var from_pos := Vector2.ZERO
var to_pos := Vector2.ZERO


func _ready() -> void:
	process_priority = 100  # after main's own _process, so the camera override wins
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.trim_prefix("--scenario=")
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--at="):
			at = float(a.trim_prefix("--at="))
		elif a.begins_with("--cam="):
			cam_mode = a.trim_prefix("--cam=")
		elif a.begins_with("--slot="):
			slot = int(a.trim_prefix("--slot="))
		elif a.begins_with("--dist="):
			dist = float(a.trim_prefix("--dist="))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)


func _start() -> void:
	started = true
	game = main.game
	game.pack.director_on = false
	game.pack.gaunts.clear()
	var car := game.car
	var fwd := Vector2.from_angle(car.body.angle)
	var left := fwd.rotated(PI / 2.0)
	var c := car.body.position
	g = GauntSim.new()
	g.id = 99
	g.state = GauntSim.State.STALK
	var p := c + fwd * 20.0 + left * 12.0
	match scenario:
		"stalk":
			p = c + fwd * 21.0 + left * 12.0
		"lit":
			p = c + fwd * 15.0 + left * 1.0
			g.frozen = true
		"sprint":
			p = c + fwd * 36.0 + left * 2.0
			g.state = GauntSim.State.HUNT
		"wind", "leap":
			p = c + fwd * 9.0 + left * 3.0
			g.state = GauntSim.State.WIND
		"thrown", "stunned", "missed", "dead":
			p = c + fwd * 6.0 + left * 2.5
	if dist > 0.0:
		p = c + fwd * dist + left * 2.0
	g.pos = p
	g.heading = (c - p).angle()
	from_pos = p
	to_pos = c + fwd * 1.5
	match scenario:
		"leap":
			g.state = GauntSim.State.LEAP
		"latch":
			g.state = GauntSim.State.LATCHED
			g.slot = slot
		"thrown":
			g.state = GauntSim.State.THROWN
			g.tumble_rate = 8.0
		"stunned", "missed":
			g.state = GauntSim.State.DOWN
			g.stun = 1.5 if scenario == "stunned" else 0.7
		"dead":
			g.state = GauntSim.State.DEAD
	view = GauntView.new()
	main.add_child(view)
	view.setup(g)
	if scenario == "missed":
		view.last_state = GauntSim.State.LEAP
		view.down_clip = "missed"
	g.lit = game.pack.in_cone(car, g.pos)
	elapsed = 0.0


func _process(delta: float) -> void:
	if main == null or main.game == null:
		return
	if not started:
		if main.game.time > 0.3:
			_start()
		return
	elapsed += delta
	g.t = elapsed
	var car := game.car
	var spd := 0.0
	match scenario:
		"stalk":
			spd = 3.0
			g.vel = Vector2.from_angle(g.heading) * spd
			g.pos = from_pos + g.vel * elapsed
		"sprint":
			spd = 16.0
			g.vel = Vector2.from_angle(g.heading) * spd
			g.pos = from_pos + g.vel * elapsed
		"leap":
			var u := clampf(elapsed / PackSim.LEAP_TIME, 0.0, 1.0)
			g.pos = from_pos.lerp(to_pos, u)
			g.z = 1.3 * 4.0 * u * (1.0 - u)
			g.heading = (to_pos - from_pos).angle()
			g.vel = (to_pos - from_pos) / PackSim.LEAP_TIME
		"latch":
			var s: Dictionary = PackSim.SLOTS[slot]
			g.pos = car.body.to_world(s["local"])
			g.z = s["z"]
			g.heading = car.body.angle + float(s["face"])
		"thrown":
			g.tumble = g.tumble_rate * elapsed
			var u2 := clampf(elapsed / 0.6, 0.0, 1.0)
			g.pos = car.body.to_world(Vector2(0.1, 0.9)).lerp(from_pos, u2)
			g.z = 0.4 + 1.4 * 4.0 * u2 * (1.0 - u2)
		"stunned", "missed":
			g.stun = maxf(0.0, (1.5 if scenario == "stunned" else 0.7) - elapsed)
	g.lit = game.pack.in_cone(car, g.pos) or game.world.is_lit(g.pos)
	if scenario in ["wind", "leap", "sprint", "stalk"]:
		g.lit = g.lit and scenario != "stalk"
	if cam_mode == "face":
		var side_f := Vector2.from_angle(g.heading + 0.35) * 1.5
		main.cam.look_at_from_position(GM.to3(g.pos + side_f, 1.62), GM.to3(g.pos + Vector2.from_angle(g.heading) * 0.55, g.z + 1.55), Vector3.UP)
	if cam_mode == "close" or cam_mode == "front":
		var pos := GM.to3(g.pos, g.z)
		var side := Vector2.from_angle(g.heading + (0.9 if cam_mode == "close" else 0.25)) * (4.2 if cam_mode == "close" else 3.4)
		main.cam.look_at_from_position(GM.to3(g.pos + side, 1.5), pos + Vector3.UP * 1.3, Vector3.UP)
	view.sync(game.world, delta)
	if not shot_done and elapsed >= at:
		shot_done = true
		_shot()


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("shot ", scenario, " anim=", view.current, " -> ", out)
	get_tree().quit()

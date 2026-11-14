extends Node
## Replays the scripted runs in tests/car_reference.json (made by Roadkill's own car.js, see
## tests/reference/gen_reference.mjs) through the GDScript port and compares state every
## 0.125 s. Prints PASS/FAIL per run, the worst error, and exits non-zero on a failure.
##
##   godot --headless --path . res://tests/car_test.tscn
##
## Vector2 is 32-bit in Godot and JS is 64-bit, so the tolerances are not zero; the chaotic
## runs (a car spinning on the handbrake) are given a little more.

const REFERENCE := "res://tests/car_reference.json"
const TOL_POS := 0.03
const TOL_VEL := 0.03
const TOL_ANGLE := 0.004
const TOL_IMPACT := 0.05
const LOOSE := ["corner", "handbrake_slide", "worn", "jeep_slalom", "sports_slalom", "wall_slam", "post_glance"]


func _ready() -> void:
	var text := FileAccess.get_file_as_string(REFERENCE)
	if text.is_empty():
		print("FAIL cannot read ", REFERENCE)
		get_tree().quit(2)
		return
	var ref: Dictionary = JSON.parse_string(text)
	var failures := 0
	for run in ref["runs"]:
		var report := _check_run(ref, run)
		var ok: bool = report["ok"]
		print(("PASS " if ok else "FAIL "), String(run["name"]).rpad(16), report["summary"])
		if not ok:
			failures += 1
			for line in report["details"]:
				print("     ", line)
	print("")
	print("car_test: %d runs, %d failed" % [ref["runs"].size(), failures])
	get_tree().quit(1 if failures > 0 else 0)


func _controls_at(segs: Array, t: float, boost: Dictionary) -> Dictionary:
	var c := {"throttle": 0.0, "turn": 0.0, "handbrake": false}
	for s in segs:
		if t >= float(s["t0"]) and t < float(s["t1"]):
			if s.has("throttle"):
				c["throttle"] = float(s["throttle"])
			if s.has("turn"):
				c["turn"] = float(s["turn"])
			if s.get("handbrake", false):
				c["handbrake"] = true
			if s.get("boost", false):
				c["boost"] = boost
	return c


func _check_run(ref: Dictionary, run: Dictionary) -> Dictionary:
	var dt := 1.0 / float(ref["hz"])
	var every: int = int(ref["every"])
	var car := CarSim.from_id(String(run["car"]))
	var wear: Dictionary = CarSim.FRESH
	if run.get("wear") != null:
		wear = run["wear"]
	var is_crash: bool = run["kind"] == "crash"
	if is_crash:
		var s: Dictionary = run["start"]
		car.body.position = Vector2(float(s["x"]), float(s["y"]))
		car.body.angle = float(s["angle"])
	var states: Array = run["states"]
	var hits: Array = []
	var worst_pos := 0.0
	var worst_vel := 0.0
	var worst_angle := 0.0
	var details: Array = []
	var loose: float = 3.0 if String(run["name"]) in LOOSE else 1.0
	var steps := int(round(float(run["seconds"]) * float(ref["hz"])))
	var next := 0
	for i in steps:
		car.update(_controls_at(run["segs"], i * dt, ref["boost"]), dt, wear)
		if is_crash:
			_crash_step(run, car, i + 1, hits)
		if (i + 1) % every == 0:
			var want: Dictionary = states[next]
			next += 1
			var b := car.body
			var e_pos := Vector2(b.position.x - float(want["x"]), b.position.y - float(want["y"])).length()
			var e_vel := Vector2(b.velocity.x - float(want["vx"]), b.velocity.y - float(want["vy"])).length()
			var e_angle := absf(b.angle - float(want["angle"]))
			worst_pos = maxf(worst_pos, e_pos)
			worst_vel = maxf(worst_vel, e_vel)
			worst_angle = maxf(worst_angle, e_angle)
			if details.size() < 3 and (e_pos > TOL_POS * loose or e_vel > TOL_VEL * loose or e_angle > TOL_ANGLE * loose):
				details.append("step %d: pos err %.4f vel err %.4f angle err %.5f" % [i + 1, e_pos, e_vel, e_angle])
			if car.braking != bool(want["braking"]) or car.boosting != bool(want["boosting"]):
				if details.size() < 3:
					details.append("step %d: braking/boosting flags differ" % (i + 1))
				worst_pos = INF
	if is_crash:
		var want_hits: Array = run["hits"]
		if want_hits.size() != hits.size():
			details.append("hit count %d, want %d" % [hits.size(), want_hits.size()])
		else:
			for k in hits.size():
				var dh: float = absf(float(hits[k]["impact"]) - float(want_hits[k]["impact"]))
				if hits[k]["kind"] != want_hits[k]["kind"] or int(hits[k]["step"]) != int(want_hits[k]["step"]) or dh > TOL_IMPACT * loose:
					details.append("hit %d: %s step %d impact %.3f, want %s step %d impact %.3f" % [k, hits[k]["kind"], hits[k]["step"], hits[k]["impact"], want_hits[k]["kind"], want_hits[k]["step"], want_hits[k]["impact"]])
	var ok := details.is_empty() and worst_pos <= TOL_POS * loose and worst_vel <= TOL_VEL * loose and worst_angle <= TOL_ANGLE * loose
	return {
		"ok": ok,
		"summary": "pos %.4f m  vel %.4f m/s  angle %.5f rad" % [worst_pos, worst_vel, worst_angle],
		"details": details,
	}


## The collision pass of world.js's driveCar, in its order: arena wall, posts, boxes.
func _crash_step(run: Dictionary, car: CarSim, step: int, hits: Array) -> void:
	var arena: Dictionary = run["arena"]
	var wall := SimCollide.keep_in_box(car, arena, 0.35)
	if wall["impact"] > 6.0:
		hits.append({"step": step, "kind": "wall", "impact": wall["impact"]})
	for p in run["posts"]:
		var post := SimCollide.car_vs_circle(car, Vector2(float(p["x"]), float(p["y"])), float(p["r"]))
		if post["impact"] > 6.0:
			hits.append({"step": step, "kind": "post", "impact": post["impact"]})
	for box in run["boxes"]:
		var hit := SimCollide.car_vs_box(car, box, 0.3)
		if hit["impact"] > 6.0:
			hits.append({"step": step, "kind": "box", "impact": hit["impact"]})

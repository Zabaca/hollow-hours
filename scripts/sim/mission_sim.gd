class_name MissionSim
extends RefCounted
## The story's state machine, in the shape of the pack: plain logic over StoryData, its own events,
## no nodes. GameSim owns one in story mode and steps it at the end of each step, after the pack;
## it reads the game it is handed (it keeps no reference to it) and acts on it through the pack's
## hooks and GameSim's place_car, escape and hull.
##
## The presenter (the game scene) stops stepping GameSim on "mission_failed" and shows the fail menu;
## retry, restart and quit are the menu's choices (GameSim.retry_mission, restart_mission). The sim
## would otherwise go on: a timed-out mission leaves the car alive, with the pack still hunting.
##
## States: ROAM (free roam; the next mission's start is lit), ACTIVE (a mission, one step at a
## time), FAILED (waiting for retry, restart or quit), ENDED (the car has gone out of the gate).
##
## Events (all dictionaries with a "type"):
##   mission_started {mission, id, title, number}   objective {text, kind, step, place?, pos?}
##   line {id, speaker, priority}                   hold {state: filling|paused|done, progress}
##   checkpoint {step, pos}                         timer {id, state: start|stop, seconds?}
##   mission_complete {mission, id, title, final}   mission_failed {mission, id, reason, text}
##   gate_open / gate_closed                        escaped                story_complete
##   retry {to: checkpoint|start}                   roam {next}            roam_wrecked
##   save {data}  (a save is asked for: write it with SaveStore)

const WALL_GAP := 3.5  # placed creatures stand at least this far from a wall, so the car can reach them

enum State { ROAM, ACTIVE, FAILED, ENDED }

var state: int = State.ROAM
var next_mission := 0
var done: Array = []  # ids of the missions finished, in order
var ending_seen := false
var totals := {"kills": 0, "wrecks": 0, "seconds": 0.0}
var last_save := {}  # what a wreck in free roam goes back to; empty before the first mission is done
var mission := -1  # index of the current (or just failed) mission
var step_i := 0
var step_clock := 0.0
var hold := 0.0
var holding := false
var fired: Array = []
var timers := {}  # id -> {left, label, reason}
var checkpoint := {}  # {step, pos, angle, hull, pack, alert_all}
var fail_reason := ""
var events: Array = []
var _kills_base := 0
var _last_kills := 0
var _alert_all := false
var _roam_wreck_reported := false


func take_events() -> Array:
	var out := events
	events = []
	return out


func ev(type: String, extra: Dictionary = {}) -> void:
	var e := {"type": type}
	e.merge(extra)
	events.append(e)


# ----------------------------------------------------------------------------- queries


func mission_data() -> Dictionary:
	if mission < 0 or mission >= StoryData.MISSIONS.size():
		return {}
	return StoryData.MISSIONS[mission]


func step_data() -> Dictionary:
	var m := mission_data()
	if m.is_empty() or step_i >= m["steps"].size():
		return {}
	return m["steps"][step_i]


func next_data() -> Dictionary:
	if next_mission < StoryData.MISSIONS.size():
		return StoryData.MISSIONS[next_mission]
	return {}


func active() -> bool:
	return state == State.ACTIVE


func objective_text() -> String:
	if state == State.ACTIVE:
		return str(step_data().get("text", ""))
	return ""


## What the HUD, the markers and the autopilot need: {kind, text, step, place, pos, radius, stop,
## next_pos} for the current step, or the next mission's start in free roam; {} when there is none.
## `stop` is true where the car should come to rest (a hold, or the reach that leads into one).
func objective() -> Dictionary:
	if state == State.ROAM:
		var n := next_data()
		if n.is_empty() or n["start"] == "":
			return {}
		var sid: String = n["start"]
		return {"kind": "start", "text": "", "step": -1, "place": sid, "pos": StoryData.place_pos(sid), "radius": StoryData.place_radius(sid), "stop": false}
	if state != State.ACTIVE:
		return {}
	var s := step_data()
	var o := {"kind": s["kind"], "text": s.get("text", ""), "step": step_i, "stop": false}
	if s.has("place"):
		var pid: String = s["place"]
		o["place"] = pid
		o["pos"] = StoryData.place_pos(pid)
		o["radius"] = float(s.get("radius", StoryData.place_radius(pid)))
	var after := _step_at(step_i + 1)
	match s["kind"]:
		"hold":
			o["stop"] = true
		"reach":
			o["stop"] = not after.is_empty() and after["kind"] == "hold" and after.get("place", "") == s["place"]
		"kill":
			o["remaining"] = maxi(0, int(s["count"]) - (_kills_now() - _kills_base))
		"survive":
			if not after.is_empty() and after.has("place"):
				o["next_pos"] = StoryData.place_pos(after["place"])
	return o


## 0..1 progress of the current hold, or -1 when the step is not a hold.
func hold_progress() -> float:
	var s := step_data()
	if state == State.ACTIVE and s.get("kind", "") == "hold":
		return clampf(hold / float(s["seconds"]), 0.0, 1.0)
	return -1.0


## Running timers as [{id, label, left}].
func timers_left() -> Array:
	var out: Array = []
	for id in timers:
		out.append({"id": id, "label": timers[id]["label"], "left": maxf(0.0, timers[id]["left"])})
	return out


## Blips for the radar and the map: [{kind: objective|start, place, pos}].
func blips() -> Array:
	var o := objective()
	if o.is_empty() or not o.has("pos"):
		return []
	return [{"kind": "start" if o["kind"] == "start" else "objective", "place": o["place"], "pos": o["pos"]}]


## How far the night has lightened: a touch more with each mission, a little more after the end.
func dawn_amount() -> float:
	var i := mission if state == State.ACTIVE or state == State.FAILED else next_mission
	if state == State.ENDED or i >= StoryData.MISSIONS.size():
		return StoryData.ENDING_DAWN
	return float(StoryData.MISSIONS[maxi(i, 0)]["dawn"])


func save_data() -> Dictionary:
	var next_id := ""
	if next_mission < StoryData.MISSIONS.size():
		next_id = StoryData.MISSIONS[next_mission]["id"]
	return {
		"version": SaveStore.VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"next": next_id,
		"done": done.duplicate(),
		"ending_seen": ending_seen,
		"totals": {"kills": int(totals["kills"]), "wrecks": int(totals["wrecks"]), "seconds": float(totals["seconds"])},
	}


# ----------------------------------------------------------------------------- beginnings


func _reset_progress() -> void:
	state = State.ROAM
	next_mission = 0
	done = []
	ending_seen = false
	totals = {"kills": 0, "wrecks": 0, "seconds": 0.0}
	last_save = {}
	mission = -1
	checkpoint = {}
	timers = {}
	fail_reason = ""
	_alert_all = false
	_roam_wreck_reported = false


## New Game: mission 1 starts at once (it has no start marker), the car at the safe start with a pack
## that is out of sight of it (the layout's own player start is where Survive the Night begins).
func new_game(game: GameSim) -> void:
	_reset_progress()
	var safe: Dictionary = StoryData.PLACES["safe_start"]
	game.place_car(safe["pos"], float(safe["angle"]), GameSim.MAX_HULL)
	game.pack.reset_pack(game.car, StoryData.ROAM_PACK, false)
	_last_kills = game.pack.kills
	start_mission(game, 0)


## Continue: the safe start, full hull, the saved progress, the next mission's blip lit.
func resume(game: GameSim, save: Dictionary) -> void:
	_reset_progress()
	done = (save.get("done", []) as Array).duplicate()
	var next_id := str(save.get("next", ""))
	next_mission = StoryData.mission_index(next_id) if next_id != "" else StoryData.MISSIONS.size()
	ending_seen = bool(save.get("ending_seen", false))
	var t: Dictionary = save.get("totals", {})
	totals = {"kills": int(t.get("kills", 0)), "wrecks": int(t.get("wrecks", 0)), "seconds": float(t.get("seconds", 0.0))}
	last_save = save.duplicate(true)
	_last_kills = game.pack.kills
	var safe: Dictionary = StoryData.PLACES["safe_start"]
	game.place_car(safe["pos"], float(safe["angle"]), GameSim.MAX_HULL)
	_enter_roam(game)
	ev("roam", {"next": next_id})
	if not next_data().is_empty() and next_data()["start"] == "":
		start_mission(game, next_mission)


## Shut the gate, saying so when it was open, so a drawn gate never stays open over a closed wall.
func _close_gate(game: GameSim) -> void:
	if game.world.gate["open"]:
		game.world.gate["open"] = false
		ev("gate_closed")


func _enter_roam(game: GameSim) -> void:
	state = State.ROAM
	mission = -1
	timers = {}
	checkpoint = {}
	_alert_all = false
	_roam_wreck_reported = false
	_close_gate(game)
	game.pack.reset_pack(game.car, StoryData.ROAM_PACK, false)
	game.pack.set_size(StoryData.ROAM_PACK)


func start_mission(game: GameSim, i: int) -> void:
	var m: Dictionary = StoryData.MISSIONS[i]
	state = State.ACTIVE
	mission = i
	fail_reason = ""
	checkpoint = {}
	timers = {}
	_alert_all = false
	game.pack.stand_down()
	_close_gate(game)
	game.hull = GameSim.MAX_HULL
	ev("mission_started", {"mission": i, "id": m["id"], "title": m["title"], "number": i + 1})
	_apply(game, m.get("begin", {}))
	_begin_step(game, 0)


func _begin_step(game: GameSim, i: int) -> void:
	step_i = i
	step_clock = 0.0
	hold = 0.0
	holding = false
	fired = []
	_kills_base = game.pack.kills
	var s := step_data()
	var o := {"text": s.get("text", ""), "kind": s["kind"], "step": i}
	if s.has("place"):
		o["place"] = s["place"]
		o["pos"] = StoryData.place_pos(s["place"])
	ev("objective", o)
	_apply(game, s.get("begin", {}))


# ----------------------------------------------------------------------------- the step


func step(dt: float, game: GameSim) -> void:
	totals["seconds"] += dt
	var k := game.pack.kills
	if k >= _last_kills:
		totals["kills"] += k - _last_kills
	_last_kills = k
	match state:
		State.ROAM:
			_step_roam(game)
		State.ACTIVE:
			_step_active(dt, game)


func _step_roam(game: GameSim) -> void:
	if game.phase == GameSim.Phase.WRECKED:
		if not _roam_wreck_reported:
			_roam_wreck_reported = true
			totals["wrecks"] += 1
			ev("roam_wrecked")
		return
	var n := next_data()
	if n.is_empty():
		return
	if n["start"] == "":
		start_mission(game, next_mission)
		return
	var sid: String = n["start"]
	if game.car.body.position.distance_to(StoryData.place_pos(sid)) <= StoryData.place_radius(sid):
		start_mission(game, next_mission)


func _step_active(dt: float, game: GameSim) -> void:
	if game.phase == GameSim.Phase.WRECKED:
		_fail(game, "wrecked")
		return
	for id in timers.keys():
		timers[id]["left"] -= dt
		if timers[id]["left"] <= 0.0:
			_fail(game, str(timers[id]["reason"]))
			return
	step_clock += dt
	var s := step_data()
	if s["kind"] != "hold":
		_fire_during(game, s, step_clock)
	match s["kind"]:
		"reach":
			if _inside(game, s):
				_end_step(game)
		"hold":
			var inside := _inside(game, s) and game.car.speed() < StoryData.HOLD_SPEED
			if inside:
				hold = minf(hold + dt, float(s["seconds"]))
			if inside != holding:
				holding = inside
				ev("hold", {"state": "filling" if inside else "paused", "progress": hold / float(s["seconds"])})
			_fire_during(game, s, hold)
			if hold >= float(s["seconds"]):
				ev("hold", {"state": "done", "progress": 1.0})
				_end_step(game)
		"kill":
			if _kills_now() - _kills_base >= int(s["count"]):
				_end_step(game)
		"survive":
			if step_clock >= float(s["seconds"]):
				_end_step(game)
		"gate":
			# Lined up with the gap, not merely near the wall: the escape must not roll through bricks.
			if game.world.gate["open"] and _inside(game, s) and game.world.in_gap(game.car):
				_end_step(game)


func _kills_now() -> int:
	return _last_kills


func _inside(game: GameSim, s: Dictionary) -> bool:
	var pid: String = s["place"]
	var radius := float(s.get("radius", StoryData.place_radius(pid)))
	return game.car.body.position.distance_to(StoryData.place_pos(pid)) <= radius


func _step_at(i: int) -> Dictionary:
	var m := mission_data()
	if m.is_empty() or i >= m["steps"].size():
		return {}
	return m["steps"][i]


func _fire_during(game: GameSim, s: Dictionary, clock: float) -> void:
	var list: Array = s.get("during", [])
	for i in list.size():
		if i in fired or clock < float(list[i]["t"]):
			continue
		fired.append(i)
		_apply(game, list[i])


func _end_step(game: GameSim) -> void:
	var s := step_data()
	var last: bool = step_i + 1 >= mission_data()["steps"].size()
	_apply(game, s.get("end", {}), step_i + 1, last)
	if state != State.ACTIVE:
		return
	if step_i + 1 >= mission_data()["steps"].size():
		_complete_mission(game)
	else:
		_begin_step(game, step_i + 1)


func _complete_mission(game: GameSim) -> void:
	var m := mission_data()
	done.append(m["id"])
	next_mission = mission + 1
	var final := next_mission >= StoryData.MISSIONS.size()
	timers = {}
	checkpoint = {}
	_apply(game, m.get("end", {}), -1, true)
	ev("mission_complete", {"mission": mission, "id": m["id"], "title": m["title"], "final": final})
	if final:
		state = State.ENDED
	else:
		state = State.ROAM
		_roam_wreck_reported = false
		_alert_all = false
		game.pack.stand_down()
		_close_gate(game)
		game.pack.set_size(StoryData.ROAM_PACK)
	# The last mission asks for no save of its own: the car is still rolling out of the gate, and a
	# save now (next "", ending not seen) would strand Continue. finish_story saves once it is over.
	if not final:
		last_save = save_data()
		ev("save", {"data": last_save.duplicate(true)})


## The car has gone out of the gate and come to rest: the story is over. GameSim calls this.
func finish_story() -> void:
	ending_seen = true
	last_save = save_data()
	ev("story_complete")
	ev("save", {"data": last_save.duplicate(true)})


# ----------------------------------------------------------------------------- effects


## Apply an effect (see StoryData). `priority` makes its lines jump the radio queue: the closing
## lines of a completed mission do.
func _apply(game: GameSim, fx: Dictionary, next_step: int = -1, priority: bool = false) -> void:
	for id in fx.get("lines", []):
		line(id, priority)
	if fx.has("pack"):
		game.pack.set_size(int(fx["pack"]))
	if fx.has("alert"):
		var a: Dictionary = fx["alert"]
		if a.get("all", false):
			_alert_all = true
			game.pack.alert_all()
		else:
			game.pack.alert_near(StoryData.place_pos(a["place"]), float(a["radius"]))
	for sp in fx.get("spawn", []):
		_spawn_hunting(game, sp)
	if fx.has("timer"):
		var t: Dictionary = fx["timer"]
		timers[t["id"]] = {"left": float(t["seconds"]), "label": t["label"], "reason": t["reason"]}
		ev("timer", {"id": t["id"], "state": "start", "seconds": float(t["seconds"]), "label": t["label"]})
	if fx.has("stop_timer") and timers.has(fx["stop_timer"]):
		timers.erase(fx["stop_timer"])
		ev("timer", {"id": fx["stop_timer"], "state": "stop"})
	if fx.get("gate", "") == "open":
		game.world.gate["open"] = true
		ev("gate_open")
	if fx.get("checkpoint", false):
		checkpoint = {
			"step": next_step,
			"pos": game.car.body.position,
			"angle": game.car.body.angle,
			"hull": game.hull,
			"pack": game.pack.size_override,
			"alert_all": _alert_all,
		}
		ev("checkpoint", {"step": next_step, "pos": game.car.body.position})
	if fx.get("escape", false):
		game.escape()
		ev("escaped", {"pos": game.car.body.position})


func line(id: String, priority: bool = false) -> void:
	ev("line", {"id": id, "speaker": StoryData.LINES[id]["speaker"], "priority": priority})


## Creatures placed a ring's radius from a place, already hunting. Eight bearings from a random start
## (the pack's own generator, so a seed replays): the first with a clear line from the place and at
## least `clear` metres from the car, else the one furthest from the car. Never inside the car.
func _spawn_hunting(game: GameSim, sp: Dictionary) -> void:
	var center := StoryData.place_pos(sp["place"])
	var ring := float(sp.get("ring", 8.0))
	var clear := float(sp.get("clear", 6.0))
	var car_at := game.car.body.position
	for n in int(sp["count"]):
		var start := game.pack.rng.randf() * TAU
		if sp.has("bearings"):
			start = float((sp["bearings"] as Array)[n % (sp["bearings"] as Array).size()])
		var best := center
		var best_score := -INF
		for attempt in 8:
			# With a given bearing the first try is that exact spot; the rest fan out from it.
			var p := center + Vector2.from_angle(start + attempt * TAU / 8.0) * ring
			var d := p.distance_to(car_at)
			# Out in the street, where the car can get at it: a few metres from every wall, with a clear line.
			var open := _wall_gap(game.world, p) >= WALL_GAP and game.world.line_clear(center, p, 0.6)
			if open and d >= clear:
				best = p
				break
			var score := (1000.0 if open else 0.0) + minf(d, clear)
			if score > best_score:
				best_score = score
				best = p
		game.pack.place_hunting(best, game.car)


## How far a point is from the nearest building, wreck or prop (0 inside one).
func _wall_gap(world: SimWorld, p: Vector2) -> float:
	var best := INF
	for b in world.boxes:
		var dx := maxf(maxf(float(b["x0"]) - p.x, 0.0), p.x - float(b["x1"]))
		var dy := maxf(maxf(float(b["y0"]) - p.y, 0.0), p.y - float(b["y1"]))
		best = minf(best, Vector2(dx, dy).length())
	return best


# ----------------------------------------------------------------------------- failing and retrying


func _fail(game: GameSim, reason: String) -> void:
	state = State.FAILED
	fail_reason = reason
	timers = {}
	if reason == "wrecked":
		totals["wrecks"] += 1
	_close_gate(game)
	var r: Dictionary = StoryData.REASONS[reason]
	var m := mission_data()
	ev("mission_failed", {"mission": mission, "id": m["id"], "title": m["title"], "reason": reason, "text": r["text"]})
	line(r["line"], true)



## Retry from the checkpoint: the car where it was, its hull as it was but at least 60, a fresh
## pack away from it. Before the first checkpoint the mission restarts.
func retry(game: GameSim) -> void:
	if state != State.FAILED:
		return
	if checkpoint.is_empty():
		restart_mission(game)
		return
	var cp := checkpoint
	game.place_car(cp["pos"], float(cp["angle"]), maxf(float(cp["hull"]), StoryData.RETRY_MIN_HULL))
	game.pack.reset_pack(game.car, maxi(int(cp["pack"]), 0), bool(cp["alert_all"]))
	game.pack.set_size(int(cp["pack"]))
	_close_gate(game)
	state = State.ACTIVE
	timers = {}
	fail_reason = ""
	_alert_all = bool(cp["alert_all"])
	ev("retry", {"to": "checkpoint", "step": cp["step"]})
	_begin_step(game, int(cp["step"]))


## Start the current mission over: the car at its start marker (the safe start for mission 1),
## full hull, a fresh pack. Works from FAILED and from the pause menu in a mission.
func restart_mission(game: GameSim) -> void:
	if mission < 0 or state == State.ROAM or state == State.ENDED:
		return
	var m := mission_data()
	var pid: String = m["start"] if m["start"] != "" else "safe_start"
	var place: Dictionary = StoryData.PLACES[pid]
	game.place_car(place["pos"], float(place["angle"]), GameSim.MAX_HULL)
	game.pack.reset_pack(game.car, int(m["begin"].get("pack", StoryData.ROAM_PACK)), false)
	ev("retry", {"to": "start"})
	start_mission(game, mission)

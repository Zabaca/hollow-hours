class_name GameSim
extends RefCounted
## The whole simulation, headless: the car (CarSim, Roadkill's handling), the city (SimWorld), the
## pack (PackSim) and the rules around them: hull, boost gauge, crashes, claws, the night clock.
## Main.gd steps it at a fixed 120 Hz, like Roadkill's Stepper, and draws what it reports.
##
## Two modes. Survival (the default) is the five-minute round: a dawn clock, a pack that grows with
## the night. Story mode has no clock; a MissionSim (stepped at the end of each step, after the
## pack, its events joining this list) runs the three missions, sets the pack's size and ends the
## night only when the car drives out through the west gate (phase ESCAPED).

enum Phase { PLAYING, WRECKED, DAWN, ESCAPED }

const NIGHT_LENGTH := 300.0  # seconds until first light
const ESCAPE_TIME := 4.0  # seconds the car takes to roll out of the gate and come to rest
const MAX_HULL := 100.0
const CRASH := 6.0  # m/s into a wall that counts as a crash (Roadkill's threshold)
const BUMP := 1.5  # m/s into a wall that is still a knock you can hear
const CLAW_DPS := 3.0  # hull per second per creature clinging to the car
const BOOST := CarSim.BOOST
const GRAB := PackSim.GRAB_DRAG * PackSim.GAUNT_MASS / 80.0  # N per (m/s) per clinging creature

var world: SimWorld
var nav: NavGrid
var car: CarSim
var pack: PackSim
var phase: int = Phase.PLAYING
var hull := MAX_HULL
var gauge := 1.0
var dry := false
var since_boost := 0.0
var boosts := 0
var sputter := 0.0
var sputter_wait := 4.0
var time := 0.0
var kills := 0
var events: Array = []
var last_controls := {"throttle": 0.0, "turn": 0.0, "handbrake": false, "boost": false}
var seed_value := 1
var story_mode := false
var mission: MissionSim  # story mode only
var escape_t := 0.0
var escape_speed := 0.0
var story_done := false


func _init(layout: Dictionary, car_id: String = "bruiser", seed_in: int = 1, story: bool = false) -> void:
	seed_value = seed_in
	story_mode = story
	world = SimWorld.from_layout(layout)
	nav = NavGrid.new(world)
	car = CarSim.from_id(car_id)
	pack = PackSim.new(world, nav, seed_in)
	reset()


## A new round: survival from the start, or in story mode a new game (mission 1 begins).
func reset() -> void:
	_reset_state()
	if story_mode:
		mission = MissionSim.new()
		mission.new_game(self)
		_drain_mission()


## Story mode: Continue. Starts at the safe start with full hull, the saved progress and the next
## mission's start lit. `save` is a valid save (SaveStore.load_save returns one).
func continue_story(save: Dictionary) -> void:
	story_mode = true
	_reset_state()
	mission = MissionSim.new()
	mission.resume(self, save)
	_drain_mission()


## Story mode: start mission `i` (0 to 2) directly, as a developer flag does: a new game for the first,
## else the progress of someone who has finished the ones before it, the car at the mission's start
## marker and the mission begun.
func start_story_at(i: int) -> void:
	if i <= 0:
		story_mode = true
		reset()
		return
	var done: Array = []
	for k in i:
		done.append(StoryData.MISSIONS[k]["id"])
	continue_story({
		"version": SaveStore.VERSION, "saved_at": 0, "next": StoryData.MISSIONS[i]["id"], "done": done,
		"ending_seen": false, "totals": {"kills": 0, "wrecks": 0, "seconds": 0.0},
	})
	var at: Dictionary = StoryData.PLACES[StoryData.MISSIONS[i]["start"]]
	place_car(at["pos"], float(at["angle"]), MAX_HULL)
	mission.start_mission(self, i)
	_drain_mission()


## Story mode: wrecked in free roam sends you back to the last save (a new game before the first).
func revert_to_save() -> void:
	var last := mission.last_save if mission != null else {}
	if last.is_empty():
		reset()
	else:
		var live: Dictionary = mission.totals.duplicate()  # the wreck, and the time and kills since the save, still count
		continue_story(last)
		mission.totals = live


func retry_mission() -> void:
	mission.retry(self)
	_drain_mission()


func restart_mission() -> void:
	mission.restart_mission(self)
	_drain_mission()


func _drain_mission() -> void:
	if mission != null:
		events.append_array(mission.take_events())


## A fresh car of the Bruiser kind.
func _new_car() -> CarSim:
	var c := CarSim.new(CarSim.BODIES["bruiser"])
	# The Bruiser model (bruiser.glb) spans x -2.23..2.31 and z -1.2..1.2 against the 4 x 2 m
	# dynamics box; collide with most of that so the bull bar does not sink into a wall before
	# the crash is reported and heard (tests/aabb_probe.gd measures it).
	c.hit_half_length = 2.27
	c.hit_half_width = 1.06
	return c


## Put the car (new, at rest) at a pose with a given hull, for a checkpoint, a restart or Continue.
## It does not touch the pack.
func place_car(pos: Vector2, angle: float, hull_in: float) -> void:
	car = _new_car()
	car.body.position = pos
	car.body.angle = angle
	hull = clampf(hull_in, 1.0, MAX_HULL)
	phase = Phase.PLAYING
	gauge = 1.0
	dry = false
	since_boost = 0.0
	sputter = 0.0
	sputter_wait = 4.0


func _reset_state() -> void:
	var ps: Dictionary = world.player_start
	car = _new_car()
	car.body.position = Vector2(ps["x"], ps["y"])
	car.body.angle = ps["angle"]
	world.gate["open"] = false
	escape_t = 0.0
	story_done = false
	pack = PackSim.new(world, nav, seed_value)
	phase = Phase.PLAYING
	hull = MAX_HULL
	gauge = 1.0
	dry = false
	since_boost = 0.0
	boosts = 0
	sputter = 0.0
	sputter_wait = 4.0
	time = 0.0
	kills = 0
	events = []
	pack.spawn_initial(car, 3)


func take_events() -> Array:
	var out := events
	events = []
	return out


## What damage has done to the car, as car.js's wear multipliers.
func wear() -> Dictionary:
	var f := hull / MAX_HULL
	var power := 1.0
	if f < 0.5:
		power = lerpf(0.72, 1.0, f / 0.5)
	if sputter > 0.0:
		power *= 0.25
	var pull := 0.0
	if f < 0.35:
		pull = 0.05 * (1.0 - f / 0.35) * (1.0 if (seed_value % 2) == 0 else -1.0)
	return {"power": power, "left": 1.0, "right": 1.0, "rear": 1.0, "pull": pull}


## Boost, from world.js: it takes something in the gauge and an engine that isn't cutting out;
## once dry the key must be let go (or the gauge fill) before it boosts again.
func may_boost(held: bool) -> bool:
	if not held or gauge >= 1.0:
		dry = false
	return held and gauge > 0.0 and not dry and not (sputter > 0.0)


func boost_gauge(dt: float) -> void:
	if not car.boosting:
		if sputter > 0.0 and since_boost == 0.0:
			return
		since_boost += dt
		if since_boost >= BOOST["delay"]:
			gauge = minf(1.0, gauge + dt / BOOST["refill"])
		return
	if since_boost > 0.0:
		boosts += 1
		events.append({"type": "boost", "pos": car.body.position})
	since_boost = 0.0
	gauge = maxf(0.0, gauge - dt / BOOST["seconds"])
	if gauge == 0.0:
		dry = true


func damage(amount: float, reason: String) -> void:
	if phase == Phase.WRECKED or amount <= 0.0:
		return
	hull = maxf(0.0, hull - amount)
	events.append({"type": "hull", "amount": amount, "reason": reason, "hull": hull})


## One fixed step. controls: {throttle -1..1, turn -1..1 (+ = left), handbrake bool, boost bool}.
func step(dt: float, controls: Dictionary) -> void:
	var live := phase != Phase.WRECKED
	var c := controls if live else {"throttle": 0.0, "turn": 0.0, "handbrake": false, "boost": false}
	last_controls = c
	time += dt

	if phase == Phase.ESCAPED:
		_step_escape(dt)
		return

	# The night ends: the survivors flee. (Story mode has no clock: the night ends at the gate.)
	if not story_mode and phase == Phase.PLAYING and time >= NIGHT_LENGTH:
		phase = Phase.DAWN
		pack.start_dawn()
		events.append({"type": "dawn"})

	# An engine failing from damage cuts out now and then.
	if hull / MAX_HULL < 0.3 and live:
		sputter_wait -= dt
		if sputter_wait <= 0.0:
			sputter = 0.45
			sputter_wait = randf_range(2.5, 5.0)
			events.append({"type": "sputter"})
	sputter = maxf(0.0, sputter - dt)

	# Each creature clinging to the car drags it back.
	var clingers := pack.latched()
	if clingers.size() > 0:
		car.body.add_force(car.body.velocity * (-GRAB * clingers.size()))

	var keys := {
		"throttle": float(c.get("throttle", 0.0)),
		"turn": float(c.get("turn", 0.0)),
		"handbrake": bool(c.get("handbrake", false)),
	}
	if may_boost(bool(c.get("boost", false))):
		keys["boost"] = BOOST
	car.update(keys, dt, wear())
	boost_gauge(dt)

	# Walls, posts, buildings and wrecks.
	var worst := 0.0
	for hit in world.collide_car(car, BUMP):
		var impact: float = hit["impact"]
		if impact <= CRASH:
			# A knock under Roadkill's crash threshold: no damage, but it must be heard.
			events.append({"type": "bump", "impact": impact, "point": hit["point"], "kind": hit["kind"]})
			continue
		worst = maxf(worst, impact)
		damage(clampf((impact - CRASH) * 2.4 + 2.0, 2.0, 36.0), "crash")
		events.append({"type": "crash", "impact": impact, "point": hit["point"], "kind": hit["kind"]})
	if worst > 8.0:
		pack.shake(car, 0.6)

	if phase != Phase.WRECKED:
		pack.step(dt, car, c)
		kills = pack.kills
		for e in pack.take_events():
			if e["type"] == "roadkill":
				gauge = minf(1.0, gauge + BOOST["roadkill"])
			elif e["type"] == "latch":
				damage(4.0, "pounce")
			elif e["type"] == "claw":
				damage(CLAW_DPS * 0.7, "claws")
			events.append(e)
	if hull <= 0.0 and phase != Phase.WRECKED:
		phase = Phase.WRECKED
		events.append({"type": "wrecked"})
	if mission != null:
		mission.step(dt, self)
		_drain_mission()


## The car drives out through the gate: no controls, no collisions, an easing speed that comes to
## rest outside. The survivors flee as they do at dawn. Called by MissionSim on reaching the gate.
func escape() -> void:
	if phase == Phase.ESCAPED:
		return
	phase = Phase.ESCAPED
	escape_t = 0.0
	escape_speed = maxf(car.speed(), 10.0)
	pack.start_dawn()


func _step_escape(dt: float) -> void:
	escape_t += dt
	var dir: Vector2 = world.gate["dir"]
	var u := clampf(escape_t / ESCAPE_TIME, 0.0, 1.0)
	var v := escape_speed * (1.0 - u) * (1.0 - u)
	car.body.velocity = dir * v
	car.body.position += dir * v * dt
	car.body.angle = lerp_angle(car.body.angle, dir.angle(), minf(1.0, 4.0 * dt))
	car.body.angular_velocity = 0.0
	car.body.force = Vector2.ZERO  # nothing to spend while it rolls out
	car.body.torque = 0.0
	pack.step(dt, car, last_controls)
	for e in pack.take_events():
		events.append(e)
	if escape_t >= ESCAPE_TIME and not story_done and mission != null:
		story_done = true
		mission.finish_story()
	_drain_mission()

class_name GameSim
extends RefCounted
## The whole simulation, headless: the car (CarSim, Roadkill's handling), the city (SimWorld), the
## pack (PackSim) and the rules around them: hull, boost gauge, crashes, claws, the night clock.
## Main.gd steps it at a fixed 120 Hz, like Roadkill's Stepper, and draws what it reports.

enum Phase { PLAYING, WRECKED, DAWN }

const NIGHT_LENGTH := 300.0  # seconds until first light
const MAX_HULL := 100.0
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


func _init(layout: Dictionary, car_id: String = "bruiser", seed_in: int = 1) -> void:
	seed_value = seed_in
	world = SimWorld.from_layout(layout)
	nav = NavGrid.new(world)
	car = CarSim.from_id(car_id)
	pack = PackSim.new(world, nav, seed_in)
	reset()


func reset() -> void:
	var ps: Dictionary = world.player_start
	car = CarSim.new(CarSim.BODIES["bruiser"])
	car.body.position = Vector2(ps["x"], ps["y"])
	car.body.angle = ps["angle"]
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

	# The night ends: the survivors flee.
	if phase == Phase.PLAYING and time >= NIGHT_LENGTH:
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
	for hit in world.collide_car(car):
		var impact: float = hit["impact"]
		worst = maxf(worst, impact)
		damage(clampf((impact - 6.0) * 2.4 + 2.0, 2.0, 36.0), "crash")
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


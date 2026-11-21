class_name PackSim
extends RefCounted
## The pack: three to five Gaunts that hide in the dark, stalk toward the car staying out of its
## light, then sprint, flank and pounce onto it. Pure logic over map coordinates so the headless
## tests can run it; Gaunt3D reads the state to draw it.
##
## Life of a creature: LURK (still, in shadow) -> STALK (creeps, freezes in light) -> HUNT (sprints,
## leads the car, flanks) -> WIND (0.6 s crouch, the tell) -> LEAP (0.5 s ballistic jump along the
## line the car was taking when it launched) -> LATCHED (clings and tears at the car until shaken off) -> THROWN -> DOWN -> HUNT.
## A creature the car hits fast enough dies (roadkill). The director keeps the pack topped up
## from dark spawn points, bigger as the night wears on, and at first light the survivors flee.

## A pounce, in the order the driver sees it: the creature stops and crouches (WIND_TIME, with a hiss and
## a flare of its eyes: the tell), then leaps along the line the car was taking when it launched
## (LEAP_TIME) and does not steer in the air. Swerve, brake or boost inside that window and it lands
## behind or beside you.
const LEAP_TIME := 0.5
const WIND_TIME := 0.6
const WIND_ANIM := 0.3  # how much of the pounce clip is the crouch (the view stretches it over WIND_TIME)
const MAX_LEAP := 11.5
const LEAP_REACH := 0.4  # a leaping creature's claws: how far past the car's body it still holds on
const GRAVITY := 24.0
## Running one down needs the CAR's own speed into it: RUNDOWN_SPEED (25 km/h) for a creature up and about,
## DOWN_KILL_SPEED (32 km/h) for one lying stunned (a slow roll over it only shoves it aside).
const RUNDOWN_SPEED := 7.0
const LEAP_KILL_SPEED := 8.0  # the car's own speed into a creature in mid-leap that kills it (29 km/h)
const DOWN_KILL_SPEED := 9.0
const RAM_LATCH_SPEED := 5.0  # a hunter that reaches a car slower than this (18 km/h) takes hold at once
const SHAKE_MAX := 2.2  # the most effort that counts, so even a slide takes about a second and the bar is seen to fill
const GRIP := 2.0  # seconds a clinging creature holds against full shaking
const RELATCH_LOCK := 4.0  # a creature that has been thrown cannot take hold again for this long
const THROW_STUN := 1.5
const MISS_STUN := 0.7
const GRAB_DRAG := 140.0  # N per (m/s) per 80 kg (Roadkill CAR.grabDrag)
const GAUNT_MASS := 70.0
const MAX_LATCHED := 4
## The pack follows the car: newcomers come in this far from it (never closer than SPAWN_MIN, whatever
## the caller asks), ahead of it and toward where it is going; a creature that is not hunting and is
## left further than STRAGGLER_DISTANCE behind is dropped and replaced ahead. In a city barely wider than
## these (the quarter) they change little.
const SPAWN_MIN := 60.0
const SPAWN_MAX := 120.0
const STRAGGLER_DISTANCE := 150.0
const AHEAD := 0.35  # cosine of the widest angle off the heading that still counts as ahead (about 70 degrees)
## Where a creature can hold on: local position on the car (x forward, y left), height, and the
## heading offset it faces.
const SLOTS := [
	{"local": Vector2(-0.3, 0.0), "z": 1.5, "face": 0.0},  # roof
	{"local": Vector2(1.15, 0.0), "z": 0.95, "face": PI},  # hood
	{"local": Vector2(-1.45, 0.0), "z": 1.0, "face": 0.0},  # trunk
	{"local": Vector2(0.1, 0.9), "z": 0.85, "face": -PI / 2.0},  # left
	{"local": Vector2(0.1, -0.9), "z": 0.85, "face": PI / 2.0},  # right
	{"local": Vector2(1.1, 0.5), "z": 0.95, "face": PI},  # hood left
	{"local": Vector2(1.1, -0.5), "z": 0.95, "face": PI},  # hood right
]

var world: SimWorld
var nav: NavGrid
var rng := RandomNumberGenerator.new()
var gaunts: Array = []  # GauntSim
var events: Array = []
var time := 0.0
var dawn := false
var spawn_timer := 0.0
var next_id := 1
var kills := 0
var side := 1.0
## The story sets the pack's size (-1 keeps the time ramp of pack_size_for), and a test can switch
## the director off so nothing is spawned but what is placed by hand.
var size_override := -1
var director_on := true
## True after alert_all(): creatures the director adds from then on come in alerted too.
var alerted_spawns := false
## Where the car is going (the story's objective), or INF: newcomers are placed toward it. GameSim sets it.
var goal := Vector2.INF
## Creatures waiting in stalled cars: [{pos, release}]. The story arms them (arm_stalled); each is placed, already
## hunting, the first time the car comes within its `release` distance, and then forgotten.
var stalled: Array = []


func _init(w: SimWorld, n: NavGrid, seed_value: int = 1) -> void:
	world = w
	nav = n
	rng.seed = seed_value


func take_events() -> Array:
	var out := events
	events = []
	return out


func ev(type: String, g: GauntSim, extra: Dictionary = {}) -> void:
	var e := {"type": type, "id": g.id if g else 0, "pos": g.pos if g else Vector2.ZERO}
	e.merge(extra)
	events.append(e)


# ----------------------------------------------------------------------------- queries


func latched() -> Array:
	var out: Array = []
	for g in gaunts:
		if g.state == GauntSim.State.LATCHED:
			out.append(g)
	return out


func alive_count() -> int:
	var n := 0
	for g in gaunts:
		if g.alive():
			n += 1
	return n


## Distance from the car to the nearest creature that is hunting it (INF if none).
func nearest_hunter(car: CarSim) -> float:
	var best := INF
	for g in gaunts:
		if g.attacking() or g.state == GauntSim.State.STALK:
			best = minf(best, g.pos.distance_to(car.body.position))
	return best


func in_cone(car: CarSim, p: Vector2) -> bool:
	var v := p - car.body.position
	var d := v.length()
	if d < 0.1:
		return true
	if d > 38.0:
		return false
	return v.dot(car.forward()) / d > 0.9


func notice_range(car: CarSim) -> float:
	return 16.0 + car.speed() * 0.65


# ----------------------------------------------------------------------------- director


## The way the car is going, as a unit vector: its velocity once it is moving, else the way it faces,
## leaning toward the goal when it has one and is not on top of it.
func heading_of(car: CarSim) -> Vector2:
	var v := car.body.velocity
	var h: Vector2 = v.normalized() if v.length() > 3.0 else car.forward()
	if goal != Vector2.INF:
		var to := goal - car.body.position
		if to.length() > 30.0:
			var lean := h + to.normalized() * 0.6
			if lean.length() > 0.01:
				h = lean.normalized()
	return h


## A hiding place for a newcomer: 60 to 120 m from the car, out of its light and the lamps, ahead of it
## and toward its goal when there is one; else any such place in that band; else any 60 m or more away;
## else the furthest there is. One draw from the pack's generator whenever there is a choice, as before.
func spawn_one(car: CarSim, min_dist: float = SPAWN_MIN) -> GauntSim:
	var here := car.body.position
	var heading := heading_of(car)
	var ahead: Array = []
	var band: Array = []
	var far: Array = []
	for s in world.spawns:
		var d := (s as Vector2).distance_to(here)
		if d < min_dist or world.is_lit(s) or in_cone(car, s):
			continue
		if d > maxf(SPAWN_MAX, min_dist):
			far.append(s)
			continue
		band.append(s)
		if (s - here).dot(heading) > AHEAD * d:
			ahead.append(s)
	var cands: Array = ahead if not ahead.is_empty() else (band if not band.is_empty() else far)
	var p: Vector2
	if cands.is_empty():
		var furthest := 0.0
		p = world.spawns[0]
		for s in world.spawns:
			var d2 := (s as Vector2).distance_to(here)
			if d2 > furthest:
				furthest = d2
				p = s
	else:
		p = cands[rng.randi() % cands.size()]
	return _make(p, car, GauntSim.State.STALK if time > 90.0 else GauntSim.State.LURK)


## A creature at `p` (jittered a little and pushed out of anything solid), facing the car.
func _make(p: Vector2, car: CarSim, state: int) -> GauntSim:
	var g := GauntSim.new()
	g.id = next_id
	next_id += 1
	g.pos = p + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
	g.pos = world.resolve_circle(g.pos, g.radius)
	g.heading = (car.body.position - g.pos).angle()
	g.role = side
	side = -side
	g.max_speed = rng.randf_range(17.5, 20.5)
	g.cooldown = rng.randf_range(0.0, 0.8)
	g.chitter_t = rng.randf_range(3.0, 9.0)
	g.state = state
	if alerted_spawns:
		g.alert = true
		if g.state == GauntSim.State.LURK:
			g.state = GauntSim.State.STALK
	gaunts.append(g)
	ev("spawn", g)
	return g


func spawn_initial(car: CarSim, count: int = 3) -> void:
	for i in count:
		spawn_one(car)


## The story's hook: a creature placed at a point, already hunting the car.
func place_hunting(p: Vector2, car: CarSim) -> GauntSim:
	var g := _make(p, car, GauntSim.State.HUNT)
	g.alert = true
	return g


## The story's hook: every creature within `radius` of a point is alerted. A lurker starts
## stalking at once rather than waiting for the night to grow restless. Returns how many.
func alert_near(p: Vector2, radius: float) -> int:
	var n := 0
	for g in gaunts:
		if not g.alive() or g.pos.distance_to(p) > radius:
			continue
		n += 1
		if not g.alert:
			g.alert = true
			ev("alert", g)
		if g.state == GauntSim.State.LURK:
			g.set_state(GauntSim.State.STALK)
	return n


func alert_all() -> int:
	alerted_spawns = true
	return alert_near(Vector2.ZERO, INF)


## The story's hook: hold the pack at `n` creatures (the director tops it up at once, then every
## five seconds). It never culls: a bigger pack thins out as creatures are run down.
func set_size(n: int) -> void:
	size_override = n
	spawn_timer = minf(spawn_timer, 0.0)


## The story's hook: creatures the director adds from now on are no longer alerted on arrival, and the ones
## waiting in stalled cars are let go quietly (a mission that ends or begins starts with none armed).
func stand_down() -> void:
	alerted_spawns = false
	stalled = []


## The story's hook: arm creatures waiting in stalled cars ([{pos: Vector2, release: float}], World.stalled).
func arm_stalled(list: Array) -> void:
	stalled = list.duplicate()


## Release the armed creatures the car has come within range of: each bursts out of its car already hunting.
func _release_stalled(car: CarSim) -> void:
	if stalled.is_empty():
		return
	var here := car.body.position
	var keep: Array = []
	for h in stalled:
		if (h["pos"] as Vector2).distance_to(here) <= float(h["release"]):
			place_hunting(h["pos"], car)
		else:
			keep.append(h)
	stalled = keep


## A fresh pack of `count` creatures out of sight of the car, for a retry, a restart or a load.
func reset_pack(car: CarSim, count: int, alerted: bool) -> void:
	gaunts.clear()
	spawn_timer = 5.0
	alerted_spawns = false
	spawn_initial(car, count)
	if alerted:
		alert_all()


func start_dawn() -> void:
	dawn = true
	for g in gaunts:
		if g.alive():
			g.z = 0.0
			g.slot = -1
			g.set_state(GauntSim.State.FLEE)
			ev("flee", g)


func pack_size_for(t: float) -> int:
	return clampi(3 + int(t / 75.0), 3, 5)


# ----------------------------------------------------------------------------- the step


## One simulation step. `ctl` is the player's {handbrake: bool, boost: bool}, used to read how the
## car is being thrown about.
func step(dt: float, car: CarSim, _ctl: Dictionary = {}) -> void:
	time += dt
	var car_pos := car.body.position
	for g in gaunts:
		g.t += dt
		g.cooldown = maxf(0.0, g.cooldown - dt)
		g.lit = in_cone(car, g.pos) or world.is_lit(g.pos)
		match g.state:
			GauntSim.State.LURK:
				_lurk(g, dt, car)
			GauntSim.State.STALK:
				_stalk(g, dt, car)
			GauntSim.State.HUNT:
				_hunt(g, dt, car)
			GauntSim.State.WIND:
				_wind(g, dt, car)
			GauntSim.State.LEAP:
				_leap(g, dt, car)
			GauntSim.State.LATCHED:
				_latched(g, dt, car)
			GauntSim.State.THROWN:
				_thrown(g, dt, car)
			GauntSim.State.DOWN:
				_down(g, dt, car)
			GauntSim.State.FLEE:
				_flee(g, dt, car)
		if g.state in [GauntSim.State.LURK, GauntSim.State.STALK, GauntSim.State.HUNT, GauntSim.State.WIND, GauntSim.State.DOWN, GauntSim.State.FLEE]:
			_ram(g, car)
	# The dead are cleared after a few seconds, the fled once they are far away.
	var keep: Array = []
	for g in gaunts:
		if g.state == GauntSim.State.DEAD and g.t > 5.0:
			continue
		if g.state == GauntSim.State.FLEE and (g.t > 9.0 or g.pos.distance_to(car_pos) > 90.0):
			continue
		keep.append(g)
	gaunts = keep
	_spread_alert(car)
	_release_stalled(car)
	_director(dt, car)


func _director(dt: float, car: CarSim) -> void:
	if dawn or not director_on:
		return
	spawn_timer -= dt
	var want := size_override if size_override >= 0 else pack_size_for(time)
	_drop_stragglers(car, want)
	if alive_count() < want and spawn_timer <= 0.0:
		spawn_one(car)
		spawn_timer = 5.0


## A creature left far behind that is only lurking or stalking is of no use there: remove it and, if
## the pack is short, put its replacement ahead of the car at once.
func _drop_stragglers(car: CarSim, want: int) -> void:
	var here := car.body.position
	var heading := heading_of(car)
	var dropped := 0
	var keep: Array = []
	for g in gaunts:
		var behind: bool = (g.pos - here).dot(heading) < 0.0
		if (g.state == GauntSim.State.LURK or g.state == GauntSim.State.STALK) and behind and g.pos.distance_to(here) > STRAGGLER_DISTANCE:
			dropped += 1
		else:
			keep.append(g)
	if dropped == 0:
		return
	gaunts = keep
	for i in dropped:
		if alive_count() < want:
			spawn_one(car)


func _spread_alert(car: CarSim) -> void:
	for g in gaunts:
		if g.attacking() and not g.alert:
			g.alert = true
			ev("alert", g)
			for o in gaunts:
				if o != g and o.alive() and o.pos.distance_to(g.pos) < 55.0:
					o.alert = true


# ----------------------------------------------------------------------------- movement helpers


func _route(g: GauntSim, target: Vector2, dt: float) -> Vector2:
	if world.line_clear(g.pos, target, g.radius * 0.8):
		g.path = PackedVector2Array()
		g.path_i = 0
		return target
	g.repath_t -= dt
	if g.path.is_empty() or g.repath_t <= 0.0:
		g.path = nav.path(g.pos, target)
		g.path_i = 0
		g.repath_t = 0.6
	while g.path_i < g.path.size() and g.pos.distance_to(g.path[g.path_i]) < 1.5:
		g.path_i += 1
	if g.path_i < g.path.size():
		return g.path[g.path_i]
	return target


func _steer(g: GauntSim, goal: Vector2, speed: float, dt: float, accel: float) -> void:
	var to := goal - g.pos
	var dist := to.length()
	var want := Vector2.ZERO
	if dist > 0.05 and speed > 0.0:
		want = to / dist * minf(speed, maxf(dist * 8.0, 2.0))
	g.vel = g.vel.move_toward(want, accel * dt)
	g.pos += g.vel * dt
	var n: Array = [Vector2.ZERO]
	var fixed := world.resolve_circle(g.pos, g.radius, n)
	if fixed != g.pos:
		var nn: Vector2 = n[0]
		if nn != Vector2.ZERO and g.vel.dot(nn) < 0.0:
			g.vel -= nn * g.vel.dot(nn)
		g.pos = fixed
	if g.vel.length() > 0.6:
		g.heading = lerp_angle(g.heading, g.vel.angle(), minf(1.0, 14.0 * dt))


func _face(g: GauntSim, toward: Vector2, dt: float) -> void:
	var d := toward - g.pos
	if d.length() > 0.05:
		g.heading = lerp_angle(g.heading, d.angle(), minf(1.0, 16.0 * dt))


func _pack_hunting_near(g: GauntSim, radius: float) -> bool:
	for o in gaunts:
		if o != g and o.attacking() and o.pos.distance_to(g.pos) < radius:
			return true
	return false


# ----------------------------------------------------------------------------- states


func _lurk(g: GauntSim, dt: float, car: CarSim) -> void:
	g.vel = g.vel.move_toward(Vector2.ZERO, 30.0 * dt)
	var d := g.pos.distance_to(car.body.position)
	g.chitter_t -= dt
	if g.chitter_t <= 0.0:
		g.chitter_t = rng.randf_range(7.0, 13.0)
		ev("chitter", g)
	# The night grows restless: after a while the lurkers come looking whether they heard the car or not.
	if time > 45.0 and g.t > 25.0:
		g.alert = true
	# Nothing hunts in the first twenty seconds: time to get out of the first street.
	var noticed := time > 20.0 and (d < notice_range(car) or (g.alert and d < 90.0))
	if noticed:
		if d <= 22.0 or (car.speed() < 3.0 and d < 40.0):
			g.set_state(GauntSim.State.HUNT)
		else:
			g.set_state(GauntSim.State.STALK)


func _stalk(g: GauntSim, dt: float, car: CarSim) -> void:
	var car_pos := car.body.position
	var d := g.pos.distance_to(car_pos)
	# Out of the light it creeps; in the beam or a lamp's pool it flattens and freezes.
	var was_frozen := g.frozen
	g.frozen = g.lit and d > 9.0
	if g.frozen:
		g.frozen_t += dt
		if not was_frozen:
			ev("freeze", g)
	else:
		g.frozen_t = 0.0
	var speed := 0.0 if g.frozen else (3.6 + minf(car.speed() * 0.12, 2.5))
	# Come in from the side it was given, not straight down the road.
	var to_car := (car_pos - g.pos).normalized()
	var side_dir := Vector2(-to_car.y, to_car.x) * g.role
	var target := car_pos + side_dir * clampf(d * 0.25, 0.0, 9.0)
	var goal := _route(g, target, dt)
	_steer(g, goal, speed, dt, 14.0)
	g.chitter_t -= dt
	if g.chitter_t <= 0.0:
		g.chitter_t = rng.randf_range(4.0, 8.0)
		ev("chitter", g)
	var go_hunt := d < 15.0 or _pack_hunting_near(g, 40.0) or g.t > 14.0 or g.frozen_t > 4.0 or (car.speed() < 2.5 and d < 30.0)
	if go_hunt:
		g.frozen = false
		g.set_state(GauntSim.State.HUNT)


func _hunt(g: GauntSim, dt: float, car: CarSim) -> void:
	var car_pos := car.body.position
	var d := g.pos.distance_to(car_pos)
	var lead_t := clampf(d / maxf(g.max_speed, 1.0), 0.0, 1.2)
	var target := car_pos + car.body.velocity * lead_t
	var to := (target - g.pos)
	var dir := to.normalized() if to.length() > 0.01 else Vector2.RIGHT
	var perp := Vector2(-dir.y, dir.x)
	if d > 14.0:
		target += perp * g.role * 5.0 * clampf((d - 14.0) / 20.0, 0.0, 1.0)
	# A little weave so they are hard to line up.
	target += perp * sin(time * 3.0 + g.id * 1.7) * minf(1.2, d * 0.05)
	var goal := _route(g, target, dt)
	_steer(g, goal, g.max_speed, dt, 42.0)
	g.chitter_t -= dt
	# Pounce when close enough that the leap can reach where the car will be.
	if g.cooldown <= 0.0 and d > 1.0 and d < 14.0 and car.speed() < 27.0 and world.line_clear(g.pos, car_pos, 0.3):
		var land := car_pos + car.body.velocity * (WIND_TIME + LEAP_TIME * 0.5)
		if g.pos.distance_to(land) <= MAX_LEAP:
			g.vel *= 0.3
			g.set_state(GauntSim.State.WIND)
			ev("pounce_windup", g, {"duration": WIND_TIME})


func _wind(g: GauntSim, dt: float, car: CarSim) -> void:
	g.vel = g.vel.move_toward(Vector2.ZERO, 60.0 * dt)
	g.pos += g.vel * dt
	var car_pos := car.body.position
	_face(g, car_pos + car.body.velocity * 0.4, dt)
	if g.t >= WIND_TIME:
		var land := car_pos + car.body.velocity * LEAP_TIME
		if g.pos.distance_to(land) > MAX_LEAP + 1.5 or not world.line_clear(g.pos, land, 0.3):
			g.cooldown = 1.0
			g.set_state(GauntSim.State.HUNT)
			return
		g.leap_from = g.pos
		g.leap_to = land
		g.leap_car_vel = car.body.velocity
		g.heading = (land - g.pos).angle()
		g.set_state(GauntSim.State.LEAP)
		ev("leap", g)


func _leap(g: GauntSim, dt: float, car: CarSim) -> void:
	# The leap was committed at launch (_wind): it flies the line it was given and does not steer.
	var u := clampf(g.t / LEAP_TIME, 0.0, 1.0)
	g.pos = g.leap_from.lerp(g.leap_to, u)
	g.z = 1.3 * 4.0 * u * (1.0 - u)
	g.vel = (g.leap_to - g.leap_from) / LEAP_TIME
	if u > 0.35:
		var hit := SimCollide.circle_vs_car(car, g.pos, 0.45 + LEAP_REACH * 0.5)
		if not hit.is_empty() and g.z < 1.9:
			_latch_or_bounce(g, car, hit)
			return
	if u >= 1.0:
		# Nothing there: it lands, skids and tumbles, and gets up a moment later.
		g.z = 0.0
		g.vel *= 0.45
		g.pos = world.resolve_circle(g.pos, g.radius)
		g.cooldown = 2.4
		g.stun = MISS_STUN
		g.set_state(GauntSim.State.DOWN)
		ev("land", g, {"missed": true})
		ev("pounce_missed", g)


## How likely a creature that reaches the car holds on. It planned for the car as it was at launch, so the
## further the car's velocity has moved from that (a swerve, a hard brake, a boost) the less it is where
## the claws expected, and a faster car is harder to grab at all.
func latch_chance(g: GauntSim, car: CarSim) -> float:
	var planned := g.leap_car_vel
	var base := clampf(1.05 - planned.length() / 24.0, 0.12, 0.95)
	var off := (car.body.velocity - planned).length()
	return clampf(base * (1.0 - clampf(off / 6.0, 0.0, 0.9)), 0.03, 0.95)


func _latch_or_bounce(g: GauntSim, car: CarSim, hit: Dictionary) -> void:
	# A leaper that meets the car's front at speed is run down in the air, the same as one on the ground:
	# charging a crouching creature is a way to beat it, as dodging is.
	var n0: Vector2 = hit["normal"]
	var point: Vector2 = hit["point"]
	var car_into := car.body.velocity_at(point).dot(n0)
	if car_into >= LEAP_KILL_SPEED:
		_run_down(g, car, n0, point, car_into, car_into - g.vel.dot(n0))
		return
	if rng.randf() < latch_chance(g, car) and latched().size() < MAX_LATCHED:
		var slot := _pick_slot(g, car)
		if slot >= 0:
			_take_hold(g, slot)
			return
	# Glanced off the car: thrown clear.
	var n: Vector2 = hit["normal"]
	_throw(g, car, n, 8.0)
	ev("bounce", g)


func _take_hold(g: GauntSim, slot: int, via: String = "pounce") -> void:
	g.slot = slot
	g.stamina = GRIP
	g.claw_t = 0.4
	g.vel = Vector2.ZERO
	g.set_state(GauntSim.State.LATCHED)
	ev("latch", g, {"slot": slot, "via": via})


func _pick_slot(g: GauntSim, car: CarSim) -> int:
	var taken: Array = []
	for o in latched():
		taken.append(o.slot)
	var local := car.body.to_local(g.pos)
	var best := -1
	var best_d := INF
	for i in SLOTS.size():
		if i in taken:
			continue
		var d := local.distance_to(SLOTS[i]["local"])
		if d < best_d:
			best_d = d
			best = i
	return best


## How hard the driver is shaking: 0 (driving along) to about 4 (a handbrake slide). It does not depend on
## speed alone, so a driver who is crawling can still rock the car, and the same inputs always count.
func shake_effort(car: CarSim) -> float:
	var speed := car.speed()
	var e := 0.0
	if car.handbrake > 0.5 and speed > 2.5:
		e += 0.9
	e += car.slide_amount() * 0.9
	if speed > 1.5:
		e += maxf(0.0, absf(car.body.angular_velocity) - 0.4) * 2.0
	if car.boosting:
		e += 0.5
	return minf(e, SHAKE_MAX)


## 0 (just landed) to 1 (about to let go) for the creature clinging least well, or -1 with none on the car.
func shake_progress() -> float:
	var best := -1.0
	for g in latched():
		best = maxf(best, 1.0 - clampf(g.stamina / GRIP, 0.0, 1.0))
	return best


func _latched(g: GauntSim, dt: float, car: CarSim) -> void:
	var s: Dictionary = SLOTS[g.slot]
	g.pos = car.body.to_world(s["local"])
	g.heading = car.body.angle + float(s["face"])
	g.z = float(s["z"])
	g.vel = car.body.velocity
	# It holds on until the car is thrown about hard enough: a spin, a handbrake slide, a hard swerve.
	var w := absf(car.body.angular_velocity)
	var effort := shake_effort(car)
	# Holding on slowly gets easier again when the driver stops shaking, but never fully: it is a short fight.
	g.stamina = minf(GRIP, g.stamina - effort * dt + (0.3 * dt if effort < 0.3 else 0.0))
	if w > 3.2 or g.stamina <= 0.0:
		_throw(g, car, _side_of(g, car), 9.0)
		ev("thrown", g, {"shaken": true})
		return
	g.claw_t -= dt
	if g.claw_t <= 0.0:
		g.claw_t = 0.7
		ev("claw", g)


## The car scrapes or hits something at `point` (GameSim calls this for every bump and crash): a creature
## clinging on the side that took the knock is raked off against it, the others only lose a little grip.
## "That side" is worked out in the car's own frame, because a wall meets a car at a corner or along an edge,
## often well away from the slot itself: a side slot is hit by contact on its side of the car (left or right of
## the middle), the hood slots by contact at the front, the trunk slot at the back. The roof is out of reach.
func scrape(car: CarSim, point: Vector2, impact: float) -> void:
	var local := car.body.to_local(point)
	for g in latched():
		var slot: Vector2 = SLOTS[g.slot]["local"]
		var reached := false
		if absf(slot.y) > 0.5 and slot.x < 1.0:
			reached = signf(local.y) == signf(slot.y) and absf(local.y) > 0.4  # a side
		elif slot.x > 0.9:
			reached = local.x > 0.9  # the hood
		elif slot.x < -1.0:
			reached = local.x < -0.9  # the trunk
		if reached:
			_throw(g, car, _side_of(g, car), 7.0)
			ev("thrown", g, {"shaken": true, "scraped": true})
		else:
			g.stamina -= impact * 0.08


func _side_of(g: GauntSim, car: CarSim) -> Vector2:
	var local: Vector2 = SLOTS[g.slot]["local"] if g.slot >= 0 else Vector2(0, 1)
	var sgn := signf(local.y) if absf(local.y) > 0.1 else (1.0 if car.body.angular_velocity >= 0.0 else -1.0)
	return Vector2(-sin(car.body.angle), cos(car.body.angle)) * sgn


## Throw a clinging or glancing creature clear: it leaves to the side with a little of the car's way, flies
## about half a second and lands well off the car's line, stunned, and cannot take hold again for a while.
func _throw(g: GauntSim, car: CarSim, dir: Vector2, power: float) -> void:
	g.vel = car.body.velocity * 0.3 + dir.normalized() * power
	g.vz = 6.5
	g.z = maxf(g.z, 0.4)
	g.tumble = 0.0
	g.tumble_rate = rng.randf_range(6.0, 11.0) * (1.0 if rng.randf() < 0.5 else -1.0)
	g.slot = -1
	g.cooldown = RELATCH_LOCK
	g.set_state(GauntSim.State.THROWN)


func _thrown(g: GauntSim, dt: float, car: CarSim) -> void:
	g.vz -= GRAVITY * dt
	g.z += g.vz * dt
	g.pos += g.vel * dt
	g.tumble += g.tumble_rate * dt
	var n: Array = [Vector2.ZERO]
	var fixed := world.resolve_circle(g.pos, g.radius, n)
	if fixed != g.pos:
		var nn: Vector2 = n[0]
		g.vel -= nn * g.vel.dot(nn) * 1.4
		g.pos = fixed
	if g.z <= 0.0:
		g.z = 0.0
		ev("land", g, {"speed": g.vel.length(), "missed": false})
		# Nothing about being thrown kills it: it skids to a stop, stunned, and gets up angry.
		g.stun = THROW_STUN
		g.vel *= 0.3
		g.set_state(GauntSim.State.DOWN)
		ev("stunned", g, {"duration": THROW_STUN})


func _down(g: GauntSim, dt: float, car: CarSim) -> void:
	g.vel = g.vel.move_toward(Vector2.ZERO, 25.0 * dt)
	g.pos += g.vel * dt
	g.pos = world.resolve_circle(g.pos, g.radius)
	g.tumble = lerpf(g.tumble, 0.0, minf(1.0, 8.0 * dt))
	g.stun -= dt
	if g.stun <= 0.0:
		g.cooldown = maxf(g.cooldown, 1.8)
		g.alert = true
		g.set_state(GauntSim.State.HUNT)
		ev("recovered", g)


func _flee(g: GauntSim, dt: float, car: CarSim) -> void:
	var away := (g.pos - car.body.position).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	var goal := g.pos + away * 20.0
	_steer(g, goal, 20.0, dt, 40.0)


func _run_down(g: GauntSim, car: CarSim, n: Vector2, point: Vector2, car_into: float, closing: float) -> void:
	g.set_state(GauntSim.State.DEAD)
	g.z = 0.0
	g.vel = n * closing * 0.6
	kills += 1
	car.body.apply_impulse(-n * GAUNT_MASS * closing * 0.6, point)
	ev("roadkill", g, {"speed": car_into, "closing": closing, "point": point})


## A creature the car runs into. What happens depends on the CAR's speed into it, not on how fast the creature
## was coming: killed at RUNDOWN_SPEED (a lying, stunned one only at DOWN_KILL_SPEED, so a roll over one you
## just shook off does nothing to it), grabbed by a hunter that reaches a slow car, otherwise shoved aside.
func _ram(g: GauntSim, car: CarSim) -> void:
	var hit := SimCollide.circle_vs_car(car, g.pos, g.radius)
	if hit.is_empty():
		return
	var n: Vector2 = hit["normal"]  # from the car toward the creature
	var point: Vector2 = hit["point"]
	var car_into := car.body.velocity_at(point).dot(n)
	var closing := car_into - g.vel.dot(n)
	g.pos += n * float(hit["depth"])
	var need := DOWN_KILL_SPEED if g.state == GauntSim.State.DOWN else RUNDOWN_SPEED
	if car_into >= need:
		_run_down(g, car, n, point, car_into, closing)
		return
	if g.state == GauntSim.State.DOWN:
		# Lying in the road: pushed along, unhurt.
		g.vel += n * maxf(car_into, 0.0) * 0.8
		return
	if closing > 1.0:
		g.vel += n * closing * 0.6
		# A hunter that reaches a slow car takes hold (a gaunt that was just thrown cannot, for a while).
		if g.state == GauntSim.State.HUNT and g.cooldown <= 0.0 and car.speed() < RAM_LATCH_SPEED and latched().size() < MAX_LATCHED:
			var slot := _pick_slot(g, car)
			if slot >= 0:
				_take_hold(g, slot, "ram")


## A hard crash or violent move: each latched creature may be thrown off.
func shake(car: CarSim, chance: float) -> void:
	for g in latched():
		if rng.randf() < chance:
			_throw(g, car, _side_of(g, car), 7.0)
			ev("thrown", g, {"shaken": true})

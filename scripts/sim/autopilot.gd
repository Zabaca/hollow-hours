class_name Autopilot
extends RefCounted
## A pure-pursuit driver, for footage (`--demo`), for checking the game without hands and for the
## mission test, which plays the whole story with it. It follows a loop round the town; in story
## mode it drives to the current objective instead, comes to rest inside a hold's marker, runs
## down Gaunts on a kill step and loiters near the gate while it is still shut. Whatever is on the
## car it slides and swerves until it lets go, as a player would.
##
##   var pilot := Autopilot.new()
##   sim.step(dt, pilot.controls(sim, dt))

const DEMO_ROUTE := [
	Vector2(-14, -0.4), Vector2(3, -0.4), Vector2(8, 0.4), Vector2(50, 0.4), Vector2(62, 8), Vector2(62, 42),
	Vector2(40, 44), Vector2(10, 44), Vector2(5.8, 36), Vector2(5.8, 10), Vector2(2, -0.4), Vector2(-30, -0.4),
]
const CAR_CLEARANCE := 2.4  # metres from a wall to a cell the car may be routed through
const REACTION := 0.3  # seconds from the tell to the hand moving
const BRAKE_DECEL := 5.0  # m/s^2 the stopping plan assumes (the car manages about 11)

var route_i := 0
var stuck_t := 0.0
var path_t := 0.0
var path_goal := Vector2.ZERO
var nav_path := PackedVector2Array()
var reverse_t := 0.0
var reverse_turn := 1.0
var patrol_i := 0
var cap_speed := INF  # set by _target: a patrol does not need more than this, and the avenue has ends
var runup := false  # on a kill step: backing off down the avenue to get up speed before the next run
var wind_seen := -1.0  # game time a creature near the car began its wind-up (the tell), -1 for none
var rng := RandomNumberGenerator.new()
var nav: NavGrid  # the car's own grid: wider berth than the Gaunts', so it does not take an alley it cannot fit
var nav_world: SimWorld


func _init() -> void:
	rng.seed = 11


func controls(game: GameSim, delta: float) -> Dictionary:
	var car := game.car
	if nav == null or nav_world != game.world:
		nav_world = game.world
		nav = NavGrid.new(game.world, CAR_CLEARANCE)
	var obj := {}
	if game.mission != null:
		obj = game.mission.objective()
	var resting := false
	if not obj.is_empty() and obj.get("stop", false) and obj.has("pos"):
		resting = car.body.position.distance_to(obj["pos"]) <= float(obj["radius"])

	# Jammed against something: back out for a moment, steering away.
	if reverse_t > 0.0:
		reverse_t -= delta
		return {"throttle": -1.0, "turn": -reverse_turn, "handbrake": false, "boost": false}
	stuck_t = stuck_t + delta if (car.speed() < 1.0 and game.time > 2.0 and not resting) else 0.0
	if stuck_t > 1.2:
		stuck_t = 0.0
		reverse_t = 1.3
		reverse_turn = 1.0 if rng.randf() < 0.5 else -1.0
	# Something on the car: do what a player would, slide and swerve until it lets go.
	if game.pack.latched().size() > 0:
		# Swerve hard and boost: it throws one off in about a second and keeps the speed that keeps the next
		# one off (a handbrake slide is faster but leaves the car standing).
		var flip := 1.0 if int(game.time / 0.5) % 2 == 0 else -1.0
		var ahead: Vector2 = car.body.position + car.body.velocity * 1.6 + car.forward() * 6.0
		var room: bool = absf(ahead.x) < 64.0 and absf(ahead.y) < 50.0 and game.world.line_clear(car.body.position, ahead, 2.0)
		# Boost only with road ahead (a boosted car goes into the first wall it meets); without it, slide.
		return {"throttle": 1.0, "turn": flip, "handbrake": not room, "boost": room and car.speed() < 14.0}
	# A creature is crouching to pounce: read the tell, and a beat later throw the car away from its side.
	var crouching: GauntSim = null
	for g in game.pack.gaunts:
		if g.state == GauntSim.State.WIND and g.pos.distance_to(car.body.position) < 18.0:
			crouching = g
			break
	if crouching != null and obj.get("kind", "") == "kill":
		# On a kill step a creature crouching dead ahead is the target: charge it (the grille kills it, in the
		# air or on the ground) rather than dodging.
		crouching = null  # (on a kill step the car is after them: hold the line and take the grab, then shake it off)
	if crouching == null:
		wind_seen = -1.0
	else:
		if wind_seen < 0.0:
			wind_seen = game.time
		var since := game.time - wind_seen
		if since >= REACTION and since < REACTION + 0.45:
			var rel := crouching.pos - car.body.position
			var side := signf(car.forward().cross(rel))
			return {"throttle": 1.0, "turn": (-side if side != 0.0 else 1.0) * 0.8, "handbrake": false, "boost": false}

	cap_speed = INF
	var target := _target(game, obj)
	var stop: bool = obj.get("stop", false)
	var radius: float = float(obj.get("radius", 0.0))
	var chase: bool = obj.get("kind", "") == "kill" and target != Vector2.INF
	if target == Vector2.INF:
		return {"throttle": 0.0, "turn": 0.0, "handbrake": false, "boost": false}

	# Follow the nav grid round buildings; go straight when the way is clear.
	var aim := target
	if not game.world.line_clear(car.body.position, target, 1.6):
		path_t -= delta
		if path_t <= 0.0 or path_goal != target:
			path_t = 0.4
			path_goal = target
			nav_path = nav.path(car.body.position, target)
		for p in nav_path:
			if p.distance_to(car.body.position) > 7.0 and game.world.line_clear(car.body.position, p, 1.2):
				aim = p
				break
	var want := (aim - car.body.position).angle()
	var err := angle_difference(car.body.angle, want)
	var throttle := 0.7 if absf(err) < 0.5 else 0.4
	var turn := clampf(err * 2.4, -1.0, 1.0)
	var boosting := false
	var slide := false
	if not chase and absf(err) > 1.8 and car.speed() < 4.0 and not stop:
		# Pointing the wrong way at a crawl: back round (the nose swings towards the target) instead of circling.
		return {"throttle": -0.8, "turn": -signf(err), "handbrake": false, "boost": false}
	if chase and absf(err) > 1.3 and car.speed() > 5.0:
		# The target is behind: swing the car round on the handbrake rather than running on into the wall.
		slide = car.speed() > 8.0
		throttle = 0.6
		turn = signf(err)
	elif chase:
		throttle = 1.0 if absf(err) < 0.5 else 0.5
		boosting = absf(err) < 0.3 and car.speed() > 6.0 and car.body.position.distance_to(target) > 4.0
	if stop:
		var dist := car.body.position.distance_to(target)
		var along := car.body.velocity.dot(car.forward())
		if dist < radius * 0.7:
			# Inside the marker: take the speed off and sit still.
			throttle = clampf(-along * 0.8, -1.0, 1.0)
			turn = 0.0
		else:
			var limit := sqrt(2.0 * BRAKE_DECEL * maxf(dist - radius * 0.6, 0.0)) + 1.5
			if along > limit:
				throttle = -1.0
	if car.speed() > cap_speed:
		throttle = -0.6
		boosting = false
	return {"throttle": throttle, "turn": turn, "handbrake": slide, "boost": boosting}


## Where to drive: the objective, a Gaunt to run down, a patrol while waiting, or the demo loop.
## Vector2.INF means sit still (nothing to do).
func _target(game: GameSim, obj: Dictionary) -> Vector2:
	var car := game.car
	if obj.is_empty():
		return _demo_target(car)
	match obj["kind"]:
		"kill":
			# Charge them on the avenue: a car doing 45 km/h or more kills one it meets, whether it is
			# crouching, running or in mid-leap (PackSim.RUNDOWN_SPEED, LEAP_KILL_SPEED), and meets only
			# the grille. So keep the speed up along the avenue, aim at one that is ahead, and turn about at
			# the ends. Off the avenue there are only walls: get back onto it.
			var here: Vector2 = car.body.position
			if absf(here.y) > 8.5 or here.x < -66.0 or here.x > -10.0:
				return Vector2(-38.0, -0.4)  # the middle of it, a good way off, so there is room to get up speed
			var best := INF
			var at := Vector2.INF
			for g in game.pack.gaunts:
				if g.state == GauntSim.State.DEAD or g.state == GauntSim.State.FLEE or g.state == GauntSim.State.LATCHED:
					continue
				var rel: Vector2 = g.pos - here
				var off: float = absf(angle_difference(car.body.angle, rel.angle()))
				if off > 0.6 or rel.length() > 45.0:
					continue
				if rel.length() < best:
					best = rel.length()
					at = g.pos + g.vel * minf(rel.length() / 20.0, 0.4)
			if at != Vector2.INF and car.speed() > 10.0:
				return at
			cap_speed = 15.0
			# Nothing lined up: run the avenue end to end, building speed.
			var east: bool = cos(car.body.angle) > 0.0
			if here.x > -30.0:
				east = false
			elif here.x < -56.0:
				east = true
			# (The east end has wrecks and the burned bus, and 15 m/s takes 15 m to turn: aim well short.)
			return Vector2(-26.0 if east else -60.0, -0.4)
		"survive":
			if obj.has("next_pos"):
				# Wait for the gate on the avenue, far enough from it to reach it in time.
				var base: Vector2 = obj["next_pos"] + Vector2(25.0, -0.4)
				var pts := [base, base + Vector2(25.0, 0.0)]
				if car.body.position.distance_to(pts[patrol_i % 2]) < 9.0:
					patrol_i += 1
				return pts[patrol_i % 2]
			return _demo_target(car)
		_:
			return obj["pos"]


func _demo_target(car: CarSim) -> Vector2:
	var target: Vector2 = DEMO_ROUTE[route_i]
	if car.body.position.distance_to(target) < 9.0:
		route_i = (route_i + 1) % DEMO_ROUTE.size()
		target = DEMO_ROUTE[route_i]
	return target

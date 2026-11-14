class_name CarSim
extends RefCounted
## A top-down, rear-wheel-drive car on four wheels: a 1:1 port of Roadkill's car.js.
## Each wheel resists sliding sideways in proportion to its sideways speed, up to a grip
## limit; past the limit it slides. The handbrake takes most of the rear wheels' grip away,
## so the tail swings out. Runs at a fixed 120 Hz (see PlayerCar), like Roadkill's Stepper.
##
## Map coordinates: x right, y up, angle anticlockwise from +x. PlayerCar maps this to 3D
## (x, 0, -y) with rotation.y = angle.

const FRESH := {"power": 1.0, "left": 1.0, "right": 1.0, "rear": 1.0, "pull": 0.0}

## Roadkill's BOOST (config.js): drive x the engine up to top speed, `top` x that speed at most.
const BOOST := {"drive": 1.8, "top": 1.35, "seconds": 2.5, "delay": 1.0, "refill": 7.0, "roadkill": 0.1}

## Roadkill's CARS[...].body options (config.js), by id. The Bruiser is all defaults.
const BODIES := {
	"bruiser": {},
	"jeep": {
		"length": 3.9, "width": 2.1, "mass": 1350.0, "engine_force": 11500.0, "rolling": 100.0,
		"grip": 1200.0, "grip_limit": 6800.0, "max_steer": 0.5, "steer_rate": 4.5,
	},
	"sports": {
		"length": 4.3, "width": 1.85, "mass": 850.0, "engine_force": 10200.0, "rolling": 70.0,
		"grip": 1250.0, "grip_limit": 6600.0, "max_steer": 0.6, "steer_rate": 6.0,
	},
}

var engine_force := 9750.0
var brake_force := 11000.0
var reverse_share := 0.6
var rolling := 80.0  # N per (m/s) per wheel along its heading
var grip := 1100.0  # N per (m/s) per wheel across its heading
var grip_limit := 6000.0  # N per wheel before it slides
var max_steer := 0.55
var steer_rate := 5.0  # rad/s the front wheels turn toward the stick
var handbrake_grip := 0.12  # share of rear grip kept with the handbrake on
var handbrake_release := 0.2  # seconds for rear grip to come back

var half_length: float
var half_width: float
var body: SimBody
## Each: {"local": Vector2, "front": bool, "angle": float, "skidding": bool}
var wheels: Array = []
var steer := 0.0
var handbrake := 0.0  # 0 = full rear grip, 1 = handbrake fully on
## This step's drive (-1..1), whether it braked and whether it boosted, for the tail lights,
## exhaust and boost gauge.
var drive := 0.0
var braking := false
var boosting := false


func _init(opts: Dictionary = {}) -> void:
	var car_length: float = opts.get("length", 4.0)
	var car_width: float = opts.get("width", 2.0)
	var mass: float = opts.get("mass", 1000.0)
	engine_force = opts.get("engine_force", engine_force)
	brake_force = opts.get("brake_force", brake_force)
	reverse_share = opts.get("reverse_share", reverse_share)
	rolling = opts.get("rolling", rolling)
	grip = opts.get("grip", grip)
	grip_limit = opts.get("grip_limit", grip_limit)
	max_steer = opts.get("max_steer", max_steer)
	steer_rate = opts.get("steer_rate", steer_rate)
	handbrake_grip = opts.get("handbrake_grip", handbrake_grip)
	handbrake_release = opts.get("handbrake_release", handbrake_release)
	half_length = car_length / 2.0
	half_width = car_width / 2.0
	body = SimBody.new(mass, (mass * (car_length * car_length + car_width * car_width)) / 12.0)
	var axle := half_length - 0.65
	var track := half_width - 0.3
	for spec in [[axle, track, true], [axle, -track, true], [-axle, track, false], [-axle, -track, false]]:
		wheels.append({"local": Vector2(spec[0], spec[1]), "front": spec[2], "angle": 0.0, "skidding": false})


static func from_id(id: String) -> CarSim:
	return CarSim.new(BODIES.get(id, {}))


func forward() -> Vector2:
	return Vector2.from_angle(body.angle)


func speed() -> float:
	return body.velocity.length()


## How hard a boost ({drive, top}) pushes, as a multiple of the engine's push, at forward
## speed `v` on `power`: `drive` up to the car's top speed on that power, then less and less
## to `top` at `top` times that speed. Never less than the engine alone.
func boost_push(boost: Dictionary, v: float, power: float) -> float:
	var flat := (power * engine_force) / (4.0 * rolling)
	var past := maxf(0.0, v / maxf(flat, 1e-6) - 1.0) / maxf(float(boost["top"]) - 1.0, 1e-6)
	return maxf(1.0, float(boost["drive"]) - (float(boost["drive"]) - float(boost["top"])) * past)


## controls: {throttle -1..1, turn -1..1 (positive = left), handbrake bool, boost: BOOST while
## boosting (a Dictionary), else absent}.
## wear: what damage has done, as multipliers: power, left/right grip, rear grip, `pull` (a steering
## pull in radians, positive = left), and optionally `wheels`, a grip multiplier per wheel.
func update(controls: Dictionary, dt: float, wear: Dictionary = FRESH) -> void:
	var forward_speed := body.velocity.dot(forward())
	var w_power: float = wear.get("power", 1.0)
	var w_left: float = wear.get("left", 1.0)
	var w_right: float = wear.get("right", 1.0)
	var w_rear: float = wear.get("rear", 1.0)
	var w_pull: float = wear.get("pull", 0.0)
	var w_wheels: Array = wear.get("wheels", [])

	var target := clampf(float(controls.get("turn", 0.0)) * max_steer + w_pull, -max_steer, max_steer)
	steer += clampf(target - steer, -steer_rate * dt, steer_rate * dt)

	if controls.get("handbrake", false):
		handbrake = 1.0
	else:
		handbrake = maxf(0.0, handbrake - dt / maxf(1e-3, handbrake_release))

	# Throttle against the direction of travel brakes first, then reverses.
	var drive_now := 0.0
	var brake := 0.0
	var throttle: float = controls.get("throttle", 0.0)
	if throttle > 0.0:
		if forward_speed < -0.5:
			brake = 1.0
		else:
			drive_now = throttle
	elif throttle < 0.0:
		if forward_speed > 0.5:
			brake = 1.0
		else:
			drive_now = throttle * reverse_share

	drive = drive_now
	braking = brake > 0.0
	var boost_cfg: Dictionary = controls.get("boost", {})
	# A boost is for going forward: never in reverse, nor while braking out of it.
	boosting = not boost_cfg.is_empty() and drive_now > 0.0
	var boost := boost_push(boost_cfg, forward_speed, w_power) if boosting else 1.0
	var rear_grip := 1.0 - handbrake * (1.0 - handbrake_grip)
	for i in wheels.size():
		var wheel: Dictionary = wheels[i]
		var is_front: bool = wheel["front"]
		var local: Vector2 = wheel["local"]
		wheel["angle"] = steer if is_front else 0.0
		var at := body.to_world(local)
		var heading := Vector2.from_angle(body.angle + float(wheel["angle"]))
		var side := Vector2(-heading.y, heading.x)  # anticlockwise quarter turn
		var v := body.velocity_at(at)
		var along := v.dot(heading)
		var across := v.dot(side)

		# An oily tyre spins: it can't drive or brake any better than it grips.
		var slick := 1.0
		if i < w_wheels.size():
			slick = float(w_wheels[i])
		var push := -rolling * along * (1.0 if is_front else 1.0 + 6.0 * handbrake)
		if not is_front:
			push += (drive_now * w_power * engine_force * slick * boost) / 2.0
		if brake > 0.0:
			push -= signf(along) * minf(brake_force / 4.0, absf(along) * 4000.0) * slick

		var side_wear := w_left if local.y > 0.0 else w_right
		var held := (1.0 if is_front else rear_grip * w_rear) * side_wear * slick
		var limit := grip_limit * held
		var slide := clampf(-grip * held * across, -limit, limit)
		body.add_force(heading * push + side * slide, at)

		# Hysteresis keeps skid marks from flickering at the threshold.
		wheel["skidding"] = (not is_front) and absf(across) > (0.8 if wheel["skidding"] else 1.6)
	body.integrate(dt)


func corners() -> Array:
	var x := half_length
	var y := half_width
	var out: Array = []
	for p in [Vector2(x, y), Vector2(-x, y), Vector2(-x, -y), Vector2(x, -y)]:
		out.append(body.to_world(p))
	return out


## The point of the car that reaches furthest against a wall with inward normal n; the
## middle of a face when a whole face is flush, so a square hit does not spin the car.
func deepest(n: Vector2) -> Vector2:
	var pts := corners()
	var reach: Array = []
	var least := INF
	for p in pts:
		var r: float = p.dot(n)
		reach.append(r)
		least = minf(least, r)
	var sum := Vector2.ZERO
	var count := 0
	for i in pts.size():
		if reach[i] - least < 1e-6:
			sum += pts[i]
			count += 1
	return sum / float(count)


## 0..1: how hard the rear tyres are sliding (for squeal and skid marks).
func slide_amount() -> float:
	var worst := 0.0
	for i in [2, 3]:
		var wheel: Dictionary = wheels[i]
		var at := body.to_world(wheel["local"])
		var heading := Vector2.from_angle(body.angle)
		var across := absf(body.velocity_at(at).dot(Vector2(-heading.y, heading.x)))
		worst = maxf(worst, across)
	return clampf((worst - 1.2) / 5.0, 0.0, 1.0)

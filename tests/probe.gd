extends Node
## Drives main.gd's autopilot route through GameSim headless and prints what happens each
## second: position, speed, hull, creatures, and the events. A way to see the game without a screen.
##
##   godot --headless --path . res://tests/probe.tscn

const DT := 1.0 / 120.0
const ROUTE := [
	Vector2(-14, -0.4), Vector2(3, -0.4), Vector2(8, 0.4), Vector2(50, 0.4), Vector2(62, 8), Vector2(62, 42),
	Vector2(40, 44), Vector2(10, 44), Vector2(5.8, 36), Vector2(5.8, 10), Vector2(2, -0.4), Vector2(-30, -0.4),
]


func _ready() -> void:
	var sim := GameSim.new(CityLayout.DATA, "bruiser", 7)
	var route_i := 0
	var tally := {}
	var stuck_t := 0.0
	var reverse_t := 0.0
	for step in int(70.0 / DT):
		var car := sim.car
		var c: Dictionary
		stuck_t = stuck_t + DT if (car.speed() < 1.0 and sim.time > 2.0) else 0.0
		if stuck_t > 1.2:
			stuck_t = 0.0
			reverse_t = 1.3
		if reverse_t > 0.0:
			reverse_t -= DT
			c = {"throttle": -1.0, "turn": -1.0, "handbrake": false, "boost": false}
		elif sim.pack.latched().size() > 0:
			c = {"throttle": 1.0, "turn": 1.0 if int(sim.time / 0.7) % 2 == 0 else -1.0, "handbrake": true, "boost": false}
		else:
			var target: Vector2 = ROUTE[route_i]
			if car.body.position.distance_to(target) < 9.0:
				route_i = (route_i + 1) % ROUTE.size()
				target = ROUTE[route_i]
			var err := angle_difference(car.body.angle, (target - car.body.position).angle())
			c = {"throttle": 0.9 if absf(err) < 0.5 else 0.45, "turn": clampf(err * 2.4, -1.0, 1.0), "handbrake": false, "boost": false}
		sim.step(DT, c)
		for e in sim.take_events():
			var k: String = e["type"]
			tally[k] = int(tally.get(k, 0)) + 1
			if k in ["crash", "latch", "thrown", "roadkill", "alert"]:
				print("  t=%.1f %s %s" % [sim.time, k, e.get("kind", e.get("impact", ""))])
		if step % 120 == 0:
			var states := []
			for g in sim.pack.gaunts:
				states.append("%d:%d@%.0f" % [g.id, g.state, g.pos.distance_to(car.body.position)])
			print("t=%2d wp=%d pos=(%.0f,%.0f) v=%.1f hull=%.0f %s" % [int(sim.time), route_i, car.body.position.x, car.body.position.y, car.speed(), sim.hull, " ".join(states)])
		if sim.phase == GameSim.Phase.WRECKED:
			print("wrecked at %.1f" % sim.time)
			break
	print(tally)
	get_tree().quit()

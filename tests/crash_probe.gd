extends Node
## For each approach speed, drives the car straight at the west perimeter and prints the tick of
## the visible contact (the drawn bull bar, 2.31 m ahead of the centre, past the arena edge), the tick the sim raised a crash event, and
## the impact it reported. Shows whether a bump is reported late, sound late by how many ticks, or
## never (under the 6 m/s threshold).
##
##   godot --headless --path . res://tests/crash_probe.tscn

const DT := 1.0 / 120.0


func _ready() -> void:
	for v in [3.0, 5.0, 7.0, 10.0, 15.0, 22.0]:
		var sim := GameSim.new(CityLayout.DATA, "bruiser", 1)
		sim.pack.gaunts.clear()
		var left: float = sim.world.arena["left"]
		sim.car.body.position = Vector2(left + 12.0, 0.0)
		sim.car.body.angle = PI  # facing the west wall
		sim.car.body.velocity = Vector2(-v, 0.0)
		var contact := -1
		var crash := -1
		var impact := 0.0
		var min_speed_after := 99.0
		for tick in 1200:
			# Coast: no throttle, so the speed at the wall is the speed set here (less rolling drag).
			sim.step(DT, {"throttle": 0.0, "turn": 0.0, "handbrake": false, "boost": false})
			var nose := sim.car.body.to_world(Vector2(2.31, 0.0))  # the bull bar as drawn
			if contact < 0 and nose.x <= left + 0.001:
				contact = tick
			for e in sim.take_events():
				if (e["type"] == "crash" or e["type"] == "bump") and crash < 0:
					crash = tick
					impact = e["impact"]
			if crash >= 0 and tick > crash + 3:
				min_speed_after = sim.car.speed()
				break
		print("v0=%4.1f m/s  bull bar meets wall at tick %d  sound event (crash or bump) tick %d  (sound late by %s ticks = %s ms)  impact %.1f  speed 3 ticks later %.1f" % [
			v, contact, crash, str(crash - contact) if crash >= 0 else "never", str((crash - contact) * 1000.0 * DT) if crash >= 0 else "-", impact, min_speed_after])
	get_tree().quit()

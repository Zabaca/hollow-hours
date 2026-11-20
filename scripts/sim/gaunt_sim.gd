class_name GauntSim
extends RefCounted
## One creature's simulated state (see PackSim for what drives it). Map coordinates; `z` is the
## height above the ground for leaps and throws.

enum State { LURK, STALK, HUNT, WIND, LEAP, LATCHED, THROWN, DOWN, DEAD, FLEE }

var id := 0
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var heading := 0.0
var z := 0.0
var vz := 0.0
var radius := 0.5
var state: int = State.LURK
var t := 0.0  # seconds in the current state
var role := 1.0  # which side it flanks from (+1 / -1)
var max_speed := 19.0
var cooldown := 0.0  # seconds before it may pounce again
var alert := false
var frozen := false
var frozen_t := 0.0
var chitter_t := 8.0
var stamina := PackSim.GRIP  # how long it can hold on, in seconds of full shaking
var slot := -1  # index into PackSim.SLOTS while latched
var claw_t := 0.0
var leap_from := Vector2.ZERO
var leap_to := Vector2.ZERO
var leap_car_vel := Vector2.ZERO  # the car's velocity when it launched: the line it committed to
var path := PackedVector2Array()
var path_i := 0
var repath_t := 0.0
var tumble := 0.0  # rad, for the thrown spin
var tumble_rate := 0.0
var stun := 0.0
## Why it is on the ground: "" (not), "thrown" (shaken off the car), "missed" (a pounce that found nothing).
var fell := ""
var windup_total := 0.0  # seconds its wind-up lasts, for the view
var lit := false  # in a light right now (headlight or lamp)


func set_state(s: int) -> void:
	state = s
	t = 0.0


func alive() -> bool:
	return state != State.DEAD and state != State.FLEE


func attacking() -> bool:
	return state == State.HUNT or state == State.WIND or state == State.LEAP or state == State.LATCHED

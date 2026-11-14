class_name SimBody
extends RefCounted
## A rigid body in the plane: a 1:1 port of Roadkill's body.js RigidBody.
## Metres, seconds, kilograms; y points up on the map (the 3D world puts map y on -Z).
## Forces build up during a step and are spent by integrate().

var mass: float
var inertia: float
var position := Vector2.ZERO
var velocity := Vector2.ZERO
var angle := 0.0
var angular_velocity := 0.0
var force := Vector2.ZERO
var torque := 0.0


func _init(m: float, i: float) -> void:
	mass = m
	inertia = i


func to_world(local: Vector2) -> Vector2:
	return position + local.rotated(angle)


func to_local(point: Vector2) -> Vector2:
	return (point - position).rotated(-angle)


## Velocity of a world point fixed to the body: v + w x r.
func velocity_at(point: Vector2) -> Vector2:
	var r := point - position
	return Vector2(velocity.x - angular_velocity * r.y, velocity.y + angular_velocity * r.x)


## `at` is a world point (null = the centre of mass, so no torque).
func add_force(f: Vector2, at: Variant = null) -> void:
	force += f
	if at != null:
		var p: Vector2 = at
		torque += (p - position).cross(f)


func apply_impulse(impulse: Vector2, at: Variant = null) -> void:
	velocity += impulse / mass
	if at != null:
		var p: Vector2 = at
		angular_velocity += (p - position).cross(impulse) / inertia


## Symplectic Euler: update velocities from forces, then positions from the new velocities.
func integrate(dt: float) -> void:
	velocity += force * (dt / mass)
	angular_velocity += (torque / inertia) * dt
	position += velocity * dt
	angle += angular_velocity * dt
	force = Vector2.ZERO
	torque = 0.0

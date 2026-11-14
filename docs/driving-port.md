# Driving: the port of Roadkill's car handling

Source: `games/games/roadkill/game/car.js` (the car), `body.js` (the rigid body and `keepInBox`),
`world.js` (`driveCar`, `collideCarWithBox`, `circleVsBox`, `mayBoost`, `boostGauge`) and
`config.js` (`CARS`, `BOOST`, `CAR`). The games repo is read only; nothing there changed.

## What maps 1:1

| Roadkill | Here |
| --- | --- |
| `RigidBody` (symplectic Euler, forces and torque, impulses) | `SimBody` |
| `Car` (4 wheels, rolling resistance along heading, grip across it up to a limit, rear-wheel drive, reverse share, brake, handbrake taking rear grip, steer rate toward the stick, wear multipliers, boost push curve) | `CarSim`, same constants, same order of operations |
| `CARS.bruiser.body` (all defaults: 4 x 2 m, 1000 kg, engine 9750, brake 11000, rolling 80, grip 1100, limit 6000, steer 0.55 at 5 rad/s, handbrake grip 0.12 released in 0.2 s) | `CarSim.BODIES["bruiser"]` (the Jeep and Sports bodies are in the table too and tested) |
| `BOOST` and the gauge (`mayBoost`, `boostGauge`: drain over 2.5 s, 1 s delay, refill over 7 s, run dry until the key is released or the gauge fills, +0.1 per kill) | `GameSim.may_boost` / `boost_gauge`, `CarSim.BOOST` |
| `keepInBox` (arena walls, bounce 0.35, repeated 3 rounds) | `SimCollide.keep_in_box` |
| `collideCarWithBox` (separating axes, contact point, bounce 0.3, 2 rounds) | `SimCollide.car_vs_box` |
| `circleVsBox` and the tree branch of `driveCar` (impulse 1.35) | `SimCollide.circle_vs_car`, `car_vs_circle` (used for lamps, trees, hydrants) |
| Crash threshold: an impact over 6 m/s counts as a crash | `SimWorld.collide_car`, `GameSim.step` |
| The Stepper: a fixed 120 Hz, at most 10 steps a frame | `project.godot`: 120 physics ticks, 10 max steps; `CarSim` runs in `_physics_process`, the view interpolates between the last two steps |
| `CAR.grabDrag` (140 per m/s per 80 kg of clinging zombie) | `GameSim.GRAB`, per creature of 70 kg |
| `CAR.shakeSpin` (1.8 rad/s throws a clinger), shaking by sliding on the handbrake above 5 m/s | `PackSim._latched` (a clinger tires as you slide, swerve or spin; over 1.8 rad/s throws it at once) |
| Zombie run-down speed | `PackSim.RUNDOWN_SPEED` = 6.5 m/s closing speed |

Map coordinates are Roadkill's (metres, x right, y up, angle anticlockwise from +x). The 3D
world puts map y on -Z with `rotation.y = angle`, so the Blender models, which face +X, drive
forward without any extra turn. The Blender build writes the city in the same coordinates.

## What could not map 1:1

- **Precision.** Godot's `Vector2` is 32-bit float, JS numbers are 64-bit. A run is the same to a
  few millimetres over a few seconds; a chaotic one (a car spinning on the handbrake) drifts more.
  `tests/car_test.gd` allows 3 cm and 4 milliradians (three times that for the chaotic runs). If
  it fails by a little, that is the first suspect; by a lot, a porting error.
- **Input.** Roadkill's `turn` is a key (-1, 0, 1). The port accepts an analog stick as well, which
  Roadkill never sees; keyboard play is identical.
- **Damage.** Roadkill's `wear` comes from its per-part damage model (engine, tyres, steering).
  Here a single hull value maps to `power` (down to 72 % at the last half), a small steering `pull`
  below 35 %, and an engine that cuts out (`sputter`) below 30 %. `left`, `right`, `rear` and
  per-wheel grip stay at 1.
- **Collisions.** Boxes are axis aligned, as in Roadkill. Wrecks lie at 0 or 90 degrees for the
  sim and are drawn a few degrees off for looks, so a wreck's hit box can differ from what you see
  by about 0.2 m. Car-against-car collisions (`collideCars`) are not ported: there is one car.
- **Suspension.** Roadkill is top-down and has none. The car's roll and pitch (from lateral and
  longitudinal acceleration), wheel spin and steering, spray and skid marks are cosmetic, drawn
  from the sim state; the sidewalks are 0.12 m higher than the road for the view only, the sim
  stays flat.
- **Brake lights.** `Car.braking` lights the tail lights; reverse lights come on while backing.
  Roadkill's exhaust and tail-light effects are not drawn.
- **Camera.** Roadkill's is fixed top-down. This one follows behind and blends toward the
  velocity direction (so a slide shows), which is a presentation choice.

## Checking it

`bun tests/reference/gen_reference.mjs` runs the real `car.js` (and lifts the collision helpers
out of `world.js` verbatim, since they are not exported) over twelve scripted runs: a straight
launch, a corner, brake and reverse, a handbrake slide, boost, Jeep and Sports slaloms, a worn
car, and four crashes (a box head on, a box corner, a post glancing, a wall slam). The result is
`tests/car_reference.json`. `godot --headless --path . res://tests/car_test.tscn` replays the
inputs through the port and compares.

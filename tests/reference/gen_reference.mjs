// Writes tests/car_reference.json: scripted-input runs of Roadkill's own car.js, body.js and
// world.js collision code, which tests/car_test.gd replays against the GDScript port.
//
//   bun tests/reference/gen_reference.mjs path/to/roadkill/game
//
// The path is Roadkill's game folder (its car.js, body.js, world.js). The JSON is committed, so this only needs re-running
// when Roadkill's handling changes. Nothing in the games repo is modified.
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

if (!process.argv[2]) {
  console.error('usage: bun tests/reference/gen_reference.mjs path/to/roadkill/game')
  process.exit(2)
}
const GAME = resolve(process.argv[2])
const here = dirname(fileURLToPath(import.meta.url))
const load = (f) => import(pathToFileURL(join(GAME, f)).href)

const { Car } = await load('car.js')
const { keepInBox } = await load('body.js')
const v2 = await load('v2.js')
const { CARS, BOOST } = await load('config.js')

// world.js's collision helpers are not exported (the file pulls in the whole game), so lift
// their source text verbatim and evaluate it against the same v2 helpers.
const worldSrc = readFileSync(join(GAME, 'world.js'), 'utf8')
const from = worldSrc.indexOf('// Closest point between a circle and car')
const to = worldSrc.indexOf("// Where each player's car starts")
if (from < 0 || to < 0) throw new Error('world.js changed shape: update the extraction markers')
const ARENA = { left: -80, right: 80, bottom: -60, top: 60 }
const { vec, add, sub, scale, dot, cross, rotate, clamp, length } = v2
const lifted = new Function(
  'vec', 'add', 'sub', 'scale', 'dot', 'cross', 'rotate', 'clamp', 'length', 'ARENA',
  worldSrc.slice(from, to) + '\nreturn { collideCarWithBox, circleVsBox }',
)(vec, add, sub, scale, dot, cross, rotate, clamp, length, ARENA)

const HZ = 120
const DT = 1 / HZ
const EVERY = 15 // record every 15 steps = 0.125 s

const input = (t, segs) => {
  const c = { throttle: 0, turn: 0, handbrake: false, boost: null }
  for (const s of segs) {
    if (t >= s.t0 && t < s.t1) {
      if (s.throttle !== undefined) c.throttle = s.throttle
      if (s.turn !== undefined) c.turn = s.turn
      if (s.handbrake) c.handbrake = true
      if (s.boost) c.boost = BOOST
    }
  }
  return c
}

const snap = (car, step) => ({
  step,
  x: car.body.position.x,
  y: car.body.position.y,
  angle: car.body.angle,
  vx: car.body.velocity.x,
  vy: car.body.velocity.y,
  w: car.body.angularVelocity,
  steer: car.steer,
  handbrake: car.handbrake,
  drive: car.drive,
  braking: car.braking,
  boosting: car.boosting,
  skidding: car.wheels.map((w) => w.skidding),
})

const runs = []
const driving = (name, carId, segs, seconds, wear) => {
  const car = new Car(CARS[carId].body)
  const states = []
  const steps = Math.round(seconds * HZ)
  for (let i = 0; i < steps; i++) {
    car.update(input(i * DT, segs), DT, wear)
    if ((i + 1) % EVERY === 0) states.push(snap(car, i + 1))
  }
  runs.push({ name, kind: 'drive', car: carId, wear: wear ?? null, segs, seconds, states })
}

driving('launch', 'bruiser', [{ t0: 0, t1: 6, throttle: 1 }], 6)
driving('corner', 'bruiser', [{ t0: 0, t1: 8, throttle: 1 }, { t0: 2, t1: 7, turn: 1, throttle: 0.6 }], 8)
driving('brake_reverse', 'bruiser', [{ t0: 0, t1: 3, throttle: 1 }, { t0: 3, t1: 9, throttle: -1 }], 9)
driving(
  'handbrake_slide',
  'bruiser',
  [{ t0: 0, t1: 8, throttle: 1 }, { t0: 3, t1: 4.5, turn: -1, handbrake: true }, { t0: 4.5, t1: 6, turn: 0.4 }],
  8,
)
driving('boost', 'bruiser', [{ t0: 0, t1: 9, throttle: 1 }, { t0: 3, t1: 5.5, boost: true }], 9)
const slalom = (end) => {
  const segs = [{ t0: 0, t1: end, throttle: 1 }]
  for (let i = 0; i * 0.8 < end; i++) segs.push({ t0: i * 0.8, t1: (i + 1) * 0.8, turn: i % 2 ? -1 : 1 })
  return segs
}
driving('jeep_slalom', 'jeep', slalom(8), 8)
driving('sports_slalom', 'sports', slalom(8), 8)
driving(
  'worn',
  'bruiser',
  [{ t0: 0, t1: 8, throttle: 1 }, { t0: 2, t1: 6, turn: 0.7 }],
  8,
  { power: 0.7, left: 0.9, right: 0.6, rear: 0.8, pull: 0.08, wheels: [1, 1, 0.5, 1] },
)

// Collisions: a car driven into a box, a post and the arena wall, as world.js's driveCar does.
const small = { left: -40, right: 40, bottom: -20, top: 20 }
const boxes = [{ x0: 12, y0: -3, x1: 16, y1: 2 }, { x0: 24, y0: 8, x1: 30, y1: 14 }]
const posts = [{ x: 20, y: -9, r: 0.6 }]
const crash = (name, carId, start, segs, seconds) => {
  const car = new Car(CARS[carId].body)
  car.body.position = vec(start.x, start.y)
  car.body.angle = start.angle
  const states = []
  const hits = []
  const steps = Math.round(seconds * HZ)
  for (let i = 0; i < steps; i++) {
    car.update(input(i * DT, segs), DT)
    const body = car.body
    const wall = keepInBox(body, small, (n) => car.deepest(n), 0.35)
    if (wall.impact > 6) hits.push({ step: i + 1, kind: 'wall', impact: wall.impact })
    for (const p of posts) {
      const hit = lifted.circleVsBox(car, vec(p.x, p.y), p.r)
      if (!hit) continue
      body.position = sub(body.position, scale(hit.normal, hit.depth))
      const point = sub(hit.point, scale(hit.normal, hit.depth))
      const speed = dot(body.velocityAt(point), hit.normal)
      if (speed <= 0) continue
      const arm = cross(sub(point, body.position), hit.normal)
      const j = (1.35 * speed) / (1 / body.mass + (arm * arm) / body.inertia)
      body.applyImpulse(scale(hit.normal, -j), point)
      if (speed > 6) hits.push({ step: i + 1, kind: 'post', impact: speed })
    }
    for (const box of boxes) {
      const { impact } = lifted.collideCarWithBox(car, box)
      if (impact > 6) hits.push({ step: i + 1, kind: 'box', impact })
    }
    if ((i + 1) % EVERY === 0) states.push(snap(car, i + 1))
  }
  runs.push({ name, kind: 'crash', car: carId, start, segs, seconds, arena: small, boxes, posts, hits, states })
}
crash('box_head_on', 'bruiser', { x: 0, y: -0.5, angle: 0 }, [{ t0: 0, t1: 4, throttle: 1 }], 4)
crash('box_corner', 'bruiser', { x: 0, y: 2.6, angle: -0.08 }, [{ t0: 0, t1: 5, throttle: 1 }], 5)
crash('post_glance', 'jeep', { x: 0, y: -8.2, angle: 0.05 }, [{ t0: 0, t1: 5, throttle: 1 }], 5)
crash('wall_slam', 'sports', { x: 0, y: -12, angle: Math.PI / 2 + 0.2 }, [{ t0: 0, t1: 5, throttle: 1 }, { t0: 3, t1: 5, turn: 1 }], 5)

const out = join(here, '..', 'car_reference.json')
writeFileSync(out, JSON.stringify({ hz: HZ, every: EVERY, boost: BOOST, bodies: Object.fromEntries(Object.entries(CARS).map(([k, c]) => [k, c.body])), runs }))
console.log(`wrote ${out}: ${runs.length} runs`)
for (const r of runs) {
  const last = r.states[r.states.length - 1]
  console.log(r.name.padEnd(16), `x=${last.x.toFixed(2)} y=${last.y.toFixed(2)} a=${last.angle.toFixed(2)}`, r.hits ? `hits=${r.hits.length}` : '')
}

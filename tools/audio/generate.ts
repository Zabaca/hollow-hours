// Regenerates the game's own sound with ElevenLabs and converts it for Godot.
//
//   ELEVENLABS_API_KEY=... bun tools/audio/generate.ts [name ...]   (no names: everything missing)
//
// Sound effects go through /v1/sound-generation, music through /v1/music. Raw takes are cached in
// tools/audio/out/ (git-ignored), so a re-run only buys what is missing; the converted files land in
// assets/audio/. One-shots become mp3, loops become 16-bit wav with their ends cross-faded so they
// repeat without a click (Godot loops an mp3 with a gap). Credits are logged at the end.
import { existsSync, mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { $ } from 'bun'

const here = dirname(fileURLToPath(import.meta.url))
const out = join(here, 'out')
const dest = join(here, '..', '..', 'assets', 'audio')
mkdirSync(out, { recursive: true })
mkdirSync(dest, { recursive: true })

const key = process.env.ELEVENLABS_API_KEY
if (!key) throw new Error('set ELEVENLABS_API_KEY')

type Item = { name: string; kind: 'sfx' | 'music'; seconds: number; loop?: boolean; prompt: string }
const ITEMS: Item[] = [
  // the creature
  { name: 'creature_screech_1', kind: 'sfx', seconds: 1.6, prompt: 'A shrill, rasping predatory screech from a gaunt inhuman creature, wet and metallic, sudden and close, horror film sound design, no music, dry' },
  { name: 'creature_screech_2', kind: 'sfx', seconds: 1.8, prompt: 'A long rising shriek from a starved nocturnal animal-like monster, throat rattling, echoing between city buildings at night, no music' },
  { name: 'creature_screech_3', kind: 'sfx', seconds: 1.4, prompt: 'A short barking screech and hiss from a fast four-legged monster, sharp, angry, outdoors at night, no music' },
  { name: 'creature_hiss', kind: 'sfx', seconds: 2.2, prompt: 'Low wet rattling breath and throaty clicking growl of a starved predator crouching in the dark, close, tense, no music' },
  { name: 'creature_chitter', kind: 'sfx', seconds: 2.6, prompt: 'Dry clicking and chittering of an unseen creature stalking down an empty rainy street, sparse clicks with long gaps, echoing, no music' },
  { name: 'creature_pounce', kind: 'sfx', seconds: 1.2, prompt: 'A creature shrieks sharply as it launches itself through the air in a pounce, rush of air and claws scraping asphalt, no music' },
  { name: 'creature_latch', kind: 'sfx', seconds: 1.4, prompt: 'Heavy thump of a large creature landing on a car roof, claws screeching and scrabbling on sheet metal and glass, no music' },
  { name: 'creature_claw_loop', kind: 'sfx', seconds: 3.0, loop: true, prompt: 'Claws scratching and dragging on car metal and glass from inside the car, rhythmic scraping and a low snarl, close, no music' },
  { name: 'creature_thrown', kind: 'sfx', seconds: 1.3, prompt: 'A creature yelps and tumbles across wet asphalt, heavy thud and slide, short pained cry, no music' },
  { name: 'creature_death', kind: 'sfx', seconds: 1.4, prompt: "A creature's dying shriek cut off by a heavy wet impact, no music" },
  { name: 'creature_run_loop', kind: 'sfx', seconds: 3.0, loop: true, prompt: 'Fast clawed footsteps of a four-legged creature sprinting on wet asphalt, galloping rhythm with splashes, steady loop, no music' },
  { name: 'creature_stalk_loop', kind: 'sfx', seconds: 3.0, loop: true, prompt: 'Slow stealthy clawed footsteps on wet pavement, soft pads and occasional claw ticks, quiet, steady loop, no music' },
  // the world
  { name: 'rain_loop', kind: 'sfx', seconds: 20.0, loop: true, prompt: 'Heavy steady rain falling on a wet city street at night, asphalt, roofs and gutters, no thunder, no voices, seamless loop' },
  { name: 'rain_roof_loop', kind: 'sfx', seconds: 12.0, loop: true, prompt: 'Rain drumming on a car roof heard from inside the car, muffled and steady, seamless loop' },
  { name: 'thunder', kind: 'sfx', seconds: 8.0, prompt: 'Distant rolling thunder over a city at night, long and low, no rain' },
  { name: 'wet_road_loop', kind: 'sfx', seconds: 5.0, loop: true, prompt: 'Car tyres hissing on a wet road, steady spray and water, no engine, seamless loop' },
  // the car
  { name: 'boost', kind: 'sfx', seconds: 1.8, prompt: 'Turbo whoosh and an engine roar surging, a short powerful blast of acceleration, no music' },
  { name: 'metal_scrape', kind: 'sfx', seconds: 1.8, prompt: 'A car body scraping along a concrete wall, long metal screech with grinding, no music' },
  { name: 'glass_break', kind: 'sfx', seconds: 1.2, prompt: 'A car window shattering, glass falling on asphalt, no music' },
  { name: 'heartbeat_loop', kind: 'sfx', seconds: 3.0, loop: true, prompt: 'A slow tense human heartbeat, deep thumps, steady, no other sound, loop' },
  { name: 'sting_latch', kind: 'sfx', seconds: 1.6, prompt: 'A low horror sting: sub-bass boom with a metallic shriek and a sudden cut, no melody' },
  // music
  { name: 'music_tension', kind: 'music', seconds: 60, loop: true, prompt: 'Dark ambient horror score for a night drive through an abandoned city. A slow evolving sub-bass drone, distant detuned strings, sparse metallic scrapes and a soft low pulse. No melody, no drums, no vocals. Unsettling, spacious, steady, loopable.' },
  { name: 'music_chase', kind: 'music', seconds: 60, loop: true, prompt: 'Dark horror chase music for a night drive while being hunted. A driving low pulse, tense ostinato of detuned synth and bowed metal, dissonant strings rising, urgent but cold. No vocals, no melody lead, loopable, steady intensity.' },
]

const wanted = process.argv.slice(2)
const todo = ITEMS.filter((i) => !wanted.length || wanted.includes(i.name))

async function balance(): Promise<number> {
  const res = await fetch('https://api.elevenlabs.io/v1/user/subscription', { headers: { 'xi-api-key': key! } })
  const d = (await res.json()) as { character_count: number }
  return d.character_count
}

async function buy(item: Item): Promise<string> {
  const raw = join(out, `${item.name}.mp3`)
  if (existsSync(raw)) return raw
  const url =
    item.kind === 'sfx'
      ? 'https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128'
      : 'https://api.elevenlabs.io/v1/music?output_format=mp3_44100_128'
  const body =
    item.kind === 'sfx'
      ? { text: item.prompt, duration_seconds: item.seconds, prompt_influence: 0.7 }
      : { prompt: item.prompt, music_length_ms: Math.round(item.seconds * 1000) }
  const res = await fetch(url, { method: 'POST', headers: { 'xi-api-key': key!, 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
  if (res.status !== 200) throw new Error(`${item.name}: ElevenLabs answered ${res.status} ${(await res.text()).slice(0, 300)}`)
  writeFileSync(raw, new Uint8Array(await res.arrayBuffer()))
  return raw
}

// Impact one-shots are kept as wav: an mp3 has to be decoded as it starts, and a crash should sound on the impact frame.
const WAV_ONESHOTS = new Set(['glass_break', 'metal_scrape', 'creature_latch', 'sting_latch'])

async function convert(item: Item, raw: string) {
  if (!item.loop && WAV_ONESHOTS.has(item.name)) {
    await $`ffmpeg -y -loglevel error -i ${raw} -ac 1 -ar 44100 -c:a pcm_s16le ${join(dest, item.name + '.wav')}`
    return
  }
  if (!item.loop) {
    await $`ffmpeg -y -loglevel error -i ${raw} -ac 1 -b:a 112k ${join(dest, item.name + '.mp3')}`
    return
  }
  // Cross-fade the tail into the head so the loop has no seam: body = [x, T], head = [0, x], body then head cross-faded.
  const x = item.kind === 'music' ? 3.0 : 1.2
  const probe = (await $`ffprobe -v error -show_entries format=duration -of csv=p=0 ${raw}`.text()).trim()
  const T = parseFloat(probe)
  const ch = item.kind === 'music' ? 2 : 1
  const filter = `[0:a]asplit[a][b];[a]atrim=start=${x}:end=${T},asetpts=PTS-STARTPTS[body];[b]atrim=0:${x},asetpts=PTS-STARTPTS[head];[body][head]acrossfade=d=${x}`
  await $`ffmpeg -y -loglevel error -i ${raw} -filter_complex ${filter} -ac ${ch} -ar 44100 -c:a pcm_s16le ${join(dest, item.name + '.wav')}`
}

const before = await balance()
for (const item of todo) {
  process.stdout.write(`${item.name} ... `)
  try {
    const raw = await buy(item)
    await convert(item, raw)
    console.log('ok')
  } catch (e) {
    console.log('FAILED', (e as Error).message)
  }
}
const after = await balance()
console.log(`credits used this run: ${after - before}`)

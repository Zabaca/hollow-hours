// Voices the radio script with ElevenLabs and converts it for Godot. A sibling of generate.ts (the
// effects), with the same caching and credit log.
//
//   bun tools/audio/voices.ts --dry                      print what would be bought, buy nothing (needs no key)
//   ELEVENLABS_API_KEY=... bun tools/audio/voices.ts [id ...]   (no ids: every line missing)
//
// The lines are read from scripts/sim/story_data.gd through a headless Godot dump, so the script
// exists in one place. Each line is spoken by its speaker's voice with `eleven_v4`; the cue words in
// square brackets steer the delivery and are neither spoken nor shown. A take is cached in
// tools/audio/out/radio/ under the id and a hash of (model, voice, text), so editing a line
// re-voices only that line. The converted file lands in assets/audio/radio/<id>.mp3: mono, leading
// and trailing silence trimmed, levelled so the three voices sit together, with a short tail pad.
// One run refuses to buy more than 1,500 characters unless given --allow-more. Credits are printed;
// the account's counter lags a purchase by a few minutes, so re-read the balance later and note it in
// tools/audio/credits.log by hand.
import { existsSync, mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { createHash } from 'node:crypto'
import { fileURLToPath } from 'node:url'
import { $ } from 'bun'

const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, '..', '..')
const out = join(here, 'out', 'radio')
const dest = join(root, 'assets', 'audio', 'radio')
const MODEL = 'eleven_v4'
const LIMIT = 1500

// Premade voices, chosen to differ by ear: an older woman, a younger man, an older man.
const VOICES: Record<string, { name: string; id: string }> = {
  vera: { name: 'Matilda', id: 'XrExE9yKIg1WjnnlVkGX' },
  teo: { name: 'Liam', id: 'TX3LPaxmHKxFdv7VOQHJ' },
  ruck: { name: 'Bill', id: 'pqHfZKP75CvOlQylNhV4' },
}

type Line = { id: string; speaker: string; text: string }

const args = process.argv.slice(2)
const dry = args.includes('--dry')
const allowMore = args.includes('--allow-more')
const wanted = args.filter((a) => !a.startsWith('--'))

async function readLines(): Promise<Line[]> {
  const text = await $`godot --headless --path ${root} --script res://tools/audio/dump_lines.gd`.text()
  const row = text.split('\n').find((l) => l.startsWith('HOLLOW_LINES '))
  if (!row) throw new Error('the Godot dump printed no HOLLOW_LINES row')
  return JSON.parse(row.slice('HOLLOW_LINES '.length)) as Line[]
}

const lines = await readLines()
for (const w of wanted) if (!lines.some((l) => l.id === w)) throw new Error(`no line called ${w}`)
const hash = (l: Line) => createHash('sha1').update(`${MODEL}|${VOICES[l.speaker].id}|${l.text}`).digest('hex').slice(0, 8)
const rawPath = (l: Line) => join(out, `${l.id}.${hash(l)}.mp3`)
const todo = lines.filter((l) => !wanted.length || wanted.includes(l.id))
const missing = todo.filter((l) => !existsSync(rawPath(l)))
const chars = missing.reduce((n, l) => n + l.text.length, 0)

console.log(`${lines.length} lines in the script, ${todo.length} selected, ${missing.length} not yet voiced`)
for (const l of missing) console.log(`  ${l.id.padEnd(12)} ${VOICES[l.speaker].name.padEnd(8)} ${String(l.text.length).padStart(4)} chars`)
console.log(`characters to buy (cue words counted): ${chars}`)
if (dry) process.exit(0)
if (chars > LIMIT && !allowMore) throw new Error(`${chars} characters is over the ${LIMIT} limit for one run; pass --allow-more to buy anyway`)

const key = process.env.ELEVENLABS_API_KEY
if (!key) throw new Error('set ELEVENLABS_API_KEY')
mkdirSync(out, { recursive: true })
mkdirSync(dest, { recursive: true })

async function balance(): Promise<number> {
  const res = await fetch('https://api.elevenlabs.io/v1/user/subscription', { headers: { 'xi-api-key': key! } })
  const d = (await res.json()) as { character_count: number }
  return d.character_count
}

async function buy(l: Line): Promise<void> {
  const raw = rawPath(l)
  if (existsSync(raw)) return
  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${VOICES[l.speaker].id}?output_format=mp3_44100_128`, {
    method: 'POST',
    headers: { 'xi-api-key': key!, 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: l.text, model_id: MODEL, voice_settings: { stability: 0.5, similarity_boost: 0.75, style: 0 } }),
  })
  if (res.status !== 200) throw new Error(`${l.id}: ElevenLabs answered ${res.status} ${(await res.text()).slice(0, 300)}`)
  writeFileSync(raw, new Uint8Array(await res.arrayBuffer()))
}

// Trim the take's silence at both ends, level it (the three voices come out at different loudness),
// leave a 120 ms pad so the mp3 never ends on the last syllable.
const FILTER =
  'silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.04,' +
  'areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.12,areverse,' +
  'loudnorm=I=-18:TP=-2:LRA=7,apad=pad_dur=0.12'

async function convert(l: Line): Promise<void> {
  await $`ffmpeg -y -loglevel error -i ${rawPath(l)} -af ${FILTER} -ac 1 -ar 44100 -b:a 80k ${join(dest, l.id + '.mp3')}`
}

const before = await balance()
for (const l of todo) {
  process.stdout.write(`${l.id} ... `)
  try {
    await buy(l)
    await convert(l)
    console.log('ok')
  } catch (e) {
    console.log('FAILED', (e as Error).message)
  }
}
const after = await balance()
const used = after - before
console.log(`credits before ${before}, after ${after}, used this run: ${used} (the counter lags; re-read it in a few minutes)`)

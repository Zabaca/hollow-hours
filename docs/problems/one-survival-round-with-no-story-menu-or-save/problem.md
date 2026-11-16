---
title: Hollow Hours is one five-minute survival round, with no story, menu or save
description: The game starts straight into a single timed round. You drive the quarter until first light, five minutes away, or until the pack wrecks the car, then press R to go again. There is no title screen, no settings screen, no story and nothing that carries from one run to the next. The owner wants it to become a mission-driven game told through voiced radio calls, with a title screen and menus, three story missions and saving between them.
impact: Left alone, Hollow Hours stays a tech test. The car handling, the city, the pack and the sound are built and tested, but a player gets about five minutes of the same thing and no reason to come back. Doing it costs agent hours, a capped ElevenLabs spend for the voices (the round so far used about 2,300 credits for its 21 effects and two music beds), and a few dollars of image generation for the key art.
severity: mid
package: repo
evidence: "The owner's decisions of 2026-11-16, relayed by the lead session (below). The repository read on 2026-11-16 at commit 4d962e7 (main, in step with origin): README.md, docs/driving-port.md, every script in scripts/sim and scripts/game (city_layout.gd's top-level keys only), tests/pack_test.gd, tests/probe.gd, tests/run_all.sh, project.godot, export_presets.cfg, .gitignore, tools/audio/generate.ts, and tools/blender/city.py, car.py and creature.py (their headers and the city's blocks, street scene and perimeter). Image and voice access was checked by key name only; no secret value was read and nothing was bought."
status: open
---

## What the owner decided (2026-11-16)

These are settled; the options plan within them.

1. **Mission-driven, like an open-world crime game, instead of timed survival.** One story mission at a time, marked on the map and the HUD, with free roam between missions and the creatures always out. Missions unlock in order and the story ends with escaping the city. His examples: escaping the city, rescuing someone, delivering supplies.
2. **The story is told through voiced radio calls**, ElevenLabs voices with subtitles, the way such games tell a story through phone calls. A few hundred to about 2,000 ElevenLabs credits for this round.
3. **This round:** a title screen and menu, three missions, and saving between missions.
4. **The title screen** offers New Game, Continue, Settings (audio volumes, graphics High or Low, fullscreen, a list of the controls) and Quit, plus whatever else makes sense. Behind it, a scary AI-generated painted key-art image, with scary music and effects (reusing the tension music and the existing effects, or a new title cue). Pausing offers Resume, Settings and Quit to menu.

**Content rules.** Everything is original: no names, logos, characters or assets from any existing game, and no copy of any film creature. The creature is our own Gaunt. The key art shows our own Gaunt, our own car and our own city's mood. No em dashes anywhere.

## What exists today (read in the code, commit 4d962e7)

- **One scene, one round.** The main scene builds everything in code and starts playing at once. The HUD's top line counts down "FIRST LIGHT IN" from 5:00. At 300 seconds the rules switch to dawn: the creatures flee and "FIRST LIGHT" shows; at zero hull "WRECKED" shows. Either way, R restarts. Esc or P pauses with a "PAUSED" label and nothing else. F3 switches graphics High and Low, F11 fullscreen, M mutes. Nothing is written to disk.
- **The simulation is pure logic and runs headless** at a fixed 120 steps a second: the car (a port of Roadkill's handling, checked against Roadkill's own code by `car_test`), the city's colliders and a creature path grid, the pack and its director, and the game rules (hull, boost gauge, crashes, claws, the night clock). Everything it does comes out as a list of events (crash, latch, roadkill, dawn, wrecked) that the presentation turns into picture and sound. `pack_test` drives scripted scenes through it with a fixed seed.
- **The pack.** Three Gaunts at the start, a fourth after 75 seconds and a fifth after 150. Nothing hunts in the first 20 seconds. A creature stalks out of the light and freezes in the headlights or a live lamp's pool, then sprints, flanks and pounces; one that lands claws the hull and drags the car back until a slide or a hard swerve throws it. A car that stops is found in under ten seconds (the README's note). New creatures appear at dark hiding places at least 60 m from the car and out of its headlights.
- **The quarter** is 140 by 108 m inside a 4.5 m concrete perimeter wall: three east-west streets (the middle one the main avenue) and three north-south, four blocks. Northwest: a pharmacy tower, a diner, a motel. Northeast: a 24-hour gas station and shop, a parking lot. Southwest: a dead park with a ranger's hut. Southeast: a bar tower, a pawn shop and a hotel tower. A burned bus blocks the central junction. The car's top speed on the flat is about 30 m/s (110 km/h), so a block is a few seconds' drive.
- **Sound** was generated with ElevenLabs through the repository's own generator (21 effects and two one-minute music beds, a tension bed and a chase bed, crossfaded by threat), plus Roadkill's engine and impact recordings. Audio runs on five buses made in code: Master, SFX, Car, Ambience and Music.
- **No title, menu, settings screen, save, story, voice or map.** Graphics settings live in memory only.

## What was found about the tools (2026-11-16, by key name only)

- **Voices.** The ElevenLabs account that made the effects can also make speech; the repository's generator already buys effects and music and logs the credits each run used. The owner's other voiced work uses the `eleven_v4` voice model, at about one credit per character by its measured runs.
- **Images.** No image-generation key is in this session's environment. A Google Gemini key exists on the owner's Mac, outside this repository, and Zabaca's own `gemini-image` command-line tool uses it; whether its billing is still on was not checked (that takes a paid call). That tool's listed prices are $0.067 an image at 1K for Nano Banana 2 and $0.134 for Nano Banana Pro. Zabaca's Cloudflare account, already on a paid plan, could also run Workers AI image models through a short-lived token; its current model list was not checked.

## Requirements the lead set

- A headless-testable mission state machine in the simulation, tested like `pack_test`.
- Visual checks are screenshots the builder takes itself from a short, windowed, self-quitting run with the dummy audio driver; never the editor, and never the owner's open editor.
- Nothing is bought while planning. Each slice is sized in agent hours.

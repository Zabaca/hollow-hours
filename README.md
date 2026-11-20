# Hollow Hours

A night drive through a dead city. You are in a muscle car in the rain; the streets are fogged and
mostly unlit; and the things that live here are fast, hunt in packs and wait in the dark until you
slow down. Survive until first light.

This is a test build (Godot 4.7.2, Forward+). Everything in it is original: the car handling is
ported from Roadkill's `car.js`, the city and the creature (the "Gaunt") were modelled, rigged and
animated in Blender for this project, and the sound is regenerated plus a few of Roadkill's own
recordings.

> Status: first run done on 2026-11-14 in an sbx sandbox (Godot 4.7.2 Linux, no GPU): the import is clean,
> `car_test` and `pack_test` pass, the main scene starts and plays headless and under the compatibility
> renderer, and Windows, Linux and macOS exports build. It has not been seen on a GPU: Forward+ (fog, SSR,
> SDFGI, the real look) has never rendered. See "Software rendering" and "Known rough".

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Throttle / brake and reverse | W / S or Up / Down | Right / left trigger |
| Steer | A / D or Left / Right | Left stick |
| Handbrake | Space | A |
| Boost | Shift | X |
| Restart (Survive the Night only; in the story it is in the pause menu) | R | Y |
| Pause menu (Resume, Map, Settings, Restart mission, Quit to menu) | Esc or P | Start |
| Full map | Tab | Back |
| Fullscreen | F11 | |
| Graphics High / Low | F3 | |
| Mute | M | |
| Menus | Up / Down, Enter, Esc | D-pad or left stick, A, B |

The story: New Game starts three radio-told missions (Batteries, The Pharmacist, West Gate), with free
roam between them and the pack always out. The objective is at the top of the screen with a bar for each
hold and a timer on the timed steps; the radar (bottom left, car-up) and the full map (Tab) show the
objective in amber and the next mission's start in teal, with a ring and a column of light for each in the
world. The game saves when a mission completes; Continue resumes from the save, and Survive the Night (the
old five-minute round, below) appears on the title once the story is finished.

The ending: reaching the west gate while it is open (it opens a minute after you take Vera and Teo aboard, and
shuts again 20 s later) drives the car out onto the road beyond the wall. First light comes up, Vera and Ruck
speak their last lines, the camera draws slowly back round the stopped car, a short credits roll plays
and the game returns to the title, where Continue now reads "The end" (greyed) and Survive the Night is offered.

How to survive: creatures stay out of your headlights and the few live street lamps while they
stalk you, then sprint, flank and pounce. A pounce is a tell you can read: the creature stops and
crouches for over half a second (a hiss, its eyes flaring), then leaps along the line the car was
taking and does not steer in the air. Swerve, brake hard or boost and it lands behind or beside you,
tumbles and gets up; carry on straight, or crawl, and it takes hold. One on the car claws at the hull
and drags it back; shake it off with a handbrake slide, hard swerves or by scraping that side of the
car along a wall or wreck (the bar under "SOMETHING IS ON THE CAR" fills as you do). A creature you shake
off is thrown clear, stunned for a moment and cannot take hold again for four seconds. Run the others
down: it takes the car's own speed into them, about 25 km/h (32 km/h for one lying stunned or in mid-leap),
so charging a crouching creature head-on at 45 km/h or more kills it, and each kill puts a little boost back
(above 60 km/h the impact dents the car too). First light is five minutes away.

## Layout

```
project.godot, export_presets.cfg   Windows / macOS / Linux export presets
scenes/title.tscn                   the first scene: the title, its menus, Settings and Credits
scenes/main.tscn                    the round; main.gd builds everything in code
scripts/sim/                        the simulation, pure GDScript, runs headless
  car_sim.gd, sim_body.gd, sim_collide.gd   the port of Roadkill's car.js / body.js / world.js
  sim_world.gd, nav_grid.gd         colliders from the city layout, A* grid for the creatures
  gaunt_sim.gd, pack_sim.gd         the creature's states and the pack's AI and director (and its story hooks)
  game_sim.gd                       hull, boost gauge, crashes, claws, the night clock, the escape
  story_data.gd, mission_sim.gd     the story as data (places, radio script, three missions) and its state machine
  save_store.gd                     the save and the settings as JSON, written through a temporary file and a rename
  autopilot.gd                      the pure-pursuit driver for --demo and for the tests
scripts/game/                       what you see and hear
  main.gd                           wires the sim to the views; input, events, game feel
  city.gd, atmosphere.gd            the wet city, lights, fog, rain, lightning, dawn
  car_view.gd, gaunt_view.gd        the car and the creature on screen
  chase_camera.gd, fx.gd, hud.gd, audio_mix.gd
  title.gd, pause_menu.gd, settings_panel.gd, credits_panel.gd, menu_row.gd, menu_style.gd   the menus
  story_presenter.gd                reads the mission events and drives the story's views; writes the save; calls retry and restart
  story_hud.gd, map_view.gd, map_screen.gd, marker_view.gd   objective, hold bar, timers, subtitles, cards; the radar and full map; the ring and light column
  fail_menu.gd, confirm_panel.gd    "MISSION FAILED" and its choices; "Start over?"
  gate_view.gd, credits_roll.gd     the west gate (leaves, lamps, the cordon's searchlights); the credits roll of the ending
  radio.gd                          the radio: queues the story's lines, plays them on the Voice bus with squelch and static, dips the music, says what to subtitle
  settings.gd, session.gd           the player's saved settings (JSON in user://); what the title hands the round
  city_layout.gd                    GENERATED by tools/blender/city.py: colliders, lights, spawns, the gate record
shaders/                            wet_ground (puddles, ripples), screen_fx (post effects), title_fx (title weather), marker_beam (mission markers)
assets/models/                      bruiser.glb, gaunt.glb, city.glb (made by tools/blender/*.py)
assets/audio/                       generated sound and music, plus Roadkill's engine and impacts
assets/fonts/                       Cormorant (SIL Open Font License, licence beside it), the menus' face
assets/ui/title_art.png             the title's picture: for now a frame of the game itself, to be replaced by the key art
tests/                              car_test (vs Roadkill's own code), pack_test (behaviour), settings_test, menu_nav_test, mission_test (the story), presenter_test (the story on screen), story_input_test (the map and menus with real key events), radio_test (the radio)
tools/blender/, tools/audio/        how the models and sounds were made; not exported
docs/driving-port.md                what mapped 1:1 from car.js and what did not
```

## Open, run, test

You need Godot 4.7.2 (`/Applications/Godot.app`, CLI at `/opt/homebrew/bin/godot`). Run every
command from anywhere with `--path` pointing at this folder.

1. First import (once, and after changing any asset). It builds `.godot/` and the class cache the
   scripts rely on (`CarSim`, `CityLayout`, ...). Run it twice if the first run reports unknown
   classes.

   ```
   godot --headless --path . --import
   ```

2. Open in the editor: `godot --path . --editor`, or open `project.godot` from the Godot project
   manager. Play with F5; the first scene is `scenes/title.tscn`.

3. Run the game: `godot --path .` opens the title. Any game flag in step 5 (`--demo`, `--shot`, `--low`,
   `--start`, `--drive`, `--cam-log`, `--audio-log`, `--no-hud`) skips the menus and goes straight into the round.

4. Headless checks (no window, exit code 0 on success):

   ```
   godot --headless --path . res://tests/car_test.tscn
   godot --headless --path . res://tests/pack_test.tscn
   godot --headless --path . res://tests/settings_test.tscn
   godot --headless --path . --script res://tests/menu_nav_test.gd
   godot --headless --path . res://tests/mission_test.tscn
   ```

   `settings_test` checks the settings file's round trip and the defaults on a missing or damaged one.
   `menu_nav_test` drives the title, Settings and the pause menu with gamepad and keyboard events (about
   15 s of real time) and keeps its settings in a file of its own. `mission_test` plays each mission to
   success and to each fail state by stepping `GameSim` in story mode and reading its events (like
   `pack_test`), checks the save, and has the autopilot drive the whole story with the pack off.
   `tests/run_all.sh` runs them all.

   `car_test` replays scripted driving runs from `tests/car_reference.json` (made by Roadkill's
   own `car.js`, `body.js` and `world.js` collision code) through the GDScript port and compares
   position, velocity and heading every 0.125 s. To regenerate the reference:
   `bun tests/reference/gen_reference.mjs <roadkill game folder>` (reads Roadkill's `car.js`, `body.js` and `world.js`
   from the Roadkill `game` folder named on the command line).

5. Autopilot and screenshots (need a window and a GPU, so not `--headless`). Arguments after `--`
   are the game's:

   ```
   godot --path . -- --demo --shot=/tmp/hollow.png --shot-at=8
   godot --path . --write-movie /tmp/hollow/frame.png --fixed-fps 30 --quit-after 900 -- --demo
   ```

   `--demo` drives an autopilot round the town; `--shot` saves one frame after `--shot-at` seconds
   and quits; `--low` starts on the Low graphics preset (not saved); `--no-hud` hides the HUD;
   `--write-movie` is Godot's Movie Maker (a PNG sequence).

   Story flags: `--story` starts a new story, `--continue` continues from the save, and `--mission=N` (1 to 3) starts mission N directly, the car at
   its start; `--seed=N` fixes the pack; `--save=PATH` reads and writes the save there (for Continue
   screenshots). A story run started by a flag with no `--save=` uses `user://dev_save.json`, never the player's
   `save.json`, so screenshot runs cannot overwrite a real save. Combine them with `--start=x,y,angle`, `--drive=0,0` and `--shot-game=SECONDS` (game time)
   to photograph a moment, e.g. a hold at the shop:
   `-- --mission=1 --seed=11 --start=46,7,-1.57 --drive=0,0 --shot-game=2.7 --shot=/tmp/hold.png`.

   The west gate and the ending: `--gate=open|opening` shows the gate open (or opening 1.5 s in), `--cam-side=H`
   puts a low camera H metres up and 7 m to the car's left (for judging how it sits on the road), and
   `--screen=ending` puts the car on the avenue with the gate open and drives it out as reaching the gate
   would (the pull-back starts about 7 s in and the credits about 18 s in, 3 s of that being the screen's own
   delay; use `--quit-after 12000`).

   Menu screenshots: `--screen=title|settings|controls|credits|confirm|pause|pause-settings` opens that screen
   instead of the round, and `--shot=PATH --shot-at=SECONDS` then saves it and quits (the pause
   screens open 8 s into the round, and `--shot-at` counts from there). The story screens
   `--screen=map|fail|complete` open the full map, the failed-mission menu or the completion card 3 s into a
   mission (use them with `--mission=N`). Use `--resolution 1600x900`
   before the `--`, `--audio-driver Dummy` for silence and `--quit-after FRAMES` as a frame limit:

   ```
   godot --path . --resolution 1600x900 --audio-driver Dummy --quit-after 900 -- --screen=settings --shot=/tmp/settings.png --shot-at=2
   ```

## Probe and software rendering

`godot --headless --path . res://tests/encounter_probe.tscn [-- pounce|throw|thrown]` measures the encounter
loop with scripted human-like drivers: the latch rate per pounce at 0 to 80 km/h for a driver who holds
straight, wanders, swerves, brakes or boosts; how long it takes to throw one off and with what; and what
happens to a creature just thrown. It prints tables and asserts nothing (pack_test pins the rules).

`godot --headless --path . res://tests/probe.tscn` drives the autopilot round the town through the sim
for 70 seconds and prints position, speed, hull, creature states and events each second.

On a machine with no GPU (the sbx sandboxes) only the compatibility renderer is usable: Forward+ on Mesa's
lavapipe did not get a frame out in 400 s inside a 1 GB sandbox. Compatibility has no volumetric fog, SSR,
SDFGI or SSAO, at most 8 lights per object (so the headlights and most lamps drop out of the ground), and no
screen-space AA, so those frames are much darker and flatter than a GPU run will be:

```
xvfb-run -a -s "-screen 0 800x450x24" godot --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution 640x360 --path . --write-movie /tmp/frames/f.png --fixed-fps 30 --quit-after 1500 -- --low --demo
```

## Export

The exports have been built once, in a Linux sandbox with the 4.7.2 templates (Windows `.exe` 116 MB, macOS zip 66 MB, Linux 81 MB); the Windows one is copied to `build/windows/` (git-ignored). Export templates are not installed on this Mac yet. Install them once (about 1 GB download):

```
mkdir -p "$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable"
curl -L -o /tmp/godot_templates.tpz https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
unzip -q /tmp/godot_templates.tpz -d /tmp/godot_templates
mv /tmp/godot_templates/templates/* "$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable/"
```

(or Editor, Manage Export Templates, Download.) Then, from the Mac:

```
godot --headless --path . --export-release "Windows Desktop" build/windows/HollowHours.exe
godot --headless --path . --export-release "macOS" build/macos/HollowHours.zip
godot --headless --path . --export-release "Linux" build/linux/HollowHours.x86_64
```

The Windows preset embeds the PCK so the download is a single `.exe` (x86_64). It does not edit
the exe's resources (no icon, no version info) because that needs `rcedit`, which does not run on
a Mac without Wine; add it later on a Windows machine or through Wine. The macOS preset is
unsigned (`codesign=0`); a signed, notarised build needs an Apple developer identity. The presets
exclude `tools/`, `tests/` and `docs/`.

## Signed and notarized Mac build

`tools/macos/release.sh` exports the universal app, signs it with the Developer ID in the login keychain
(hardened runtime, secure timestamp, `tools/macos/HollowHours.entitlements`), then notarizes, staples and zips it to
`build/macos/HollowHours-mac.zip`. No identity or credential is stored in the repo: give it
`NOTARY_PROFILE=<keychain profile>` or `NOTARY_KEY`, `NOTARY_KEY_ID` and `NOTARY_ISSUER` (an App Store Connect team
key) in the environment. With neither it signs and stops. Only the macOS export template is needed
(`macos.zip` in `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`).

## Remaking the assets

Blender 5.3 headless, foreground, one script per asset (the output is committed, so this is only
needed when changing a model):

```
Blender --background --python-exit-code 1 --python tools/blender/car.py
Blender --background --python-exit-code 1 --python tools/blender/creature.py       # add -- preview for contact sheets
Blender --background --python-exit-code 1 --python tools/blender/city.py           # also rewrites scripts/game/city_layout.gd
```

Sound: `ELEVENLABS_API_KEY=... bun tools/audio/generate.ts [name ...]` buys only what is missing from
`tools/audio/out/` and converts to `assets/audio/` (mp3 one-shots, cross-faded wav loops). Roadkill's
`engine.wav`, `skid.wav`, the crash, wreck, slam, sputter, stomp and splat recordings are copied from
its `game/audio/` unchanged.

The radio's voices: `bun tools/audio/voices.ts --dry` prints what is missing and the character count and
buys nothing; `ELEVENLABS_API_KEY=... bun tools/audio/voices.ts [id ...]` voices the 21 lines of
`scripts/sim/story_data.gd` (read through a headless Godot dump, so there is one copy of the script) with
`eleven_v4`, Vera as Matilda, Teo as Liam and Ruck as Bill, into `assets/audio/radio/<id>.mp3`. A take is
cached under the id and a hash of its text and voice, so editing a line re-voices only that line; one run
refuses more than 1,500 characters without `--allow-more`. Spend is noted in `tools/audio/credits.log`.
The Voice bus (a 300 to 3,400 Hz radio with a little grit) is in `scripts/game/audio_mix.gd`, and
`scripts/game/radio.gd` plays the lines: queue, squelch, the music's dip and the subtitle.

## Tuning knobs

Everything below is a constant to edit; none of it has been balanced by playing.

- Pack and creature: `scripts/sim/pack_sim.gd` (sprint speed in `spawn_one`, `WIND_TIME` (the tell),
  `LEAP_TIME`, `MAX_LEAP`, `latch_chance`, `GRIP` and `shake_effort` (how long it takes to throw one off),
  `RELATCH_LOCK`, `THROW_STUN`, `RUNDOWN_SPEED`, `DOWN_KILL_SPEED`, `RAM_LATCH_SPEED`, notice range, the 45 s "restless" ramp, `pack_size_for`), `scripts/sim/game_sim.gd`
  (`NIGHT_LENGTH`, `CLAW_DPS`, crash damage).
- Look: `scripts/game/atmosphere.gd` (fog density and colour, glow, moon, rain amount), headlights in
  `scripts/game/car_view.gd` (`light_energy`, `spot_angle`), lamp brightness in `scripts/game/city.gd`
  (the `energy *= 0.32` factor), the wet shader parameters in `scripts/game/city.gd` and
  `shaders/wet_ground.gdshader`.
- Feel: hit-stop and shake amounts are in `main.gd` `_on_event`; the screen shader is
  `shaders/screen_fx.gdshader`.
- F3 in game, or Graphics in Settings, switches High and Low (SDFGI, SSR, SSAO, MSAA, TAA); fog stays on. Settings (volumes per bus, graphics, fullscreen, subtitles) are kept in `settings.json` in the game's user data folder and applied at start.
- The story's look: amber (objective) and teal (mission start) are `MapView.AMBER` and `MapView.TEAL`; the objective, cards and subtitles are in `scripts/game/story_hud.gd`; the radar's range is `MapView.RADAR_RANGE`; the marker's ring and column in `scripts/game/marker_view.gd` and `shaders/marker_beam.gdshader`; how long the fail menu waits after a wreck, `StoryPresenter.FAIL_DELAY_WRECKED`.
- Menus: the face and colours are in `scripts/game/menu_style.gd`; the title's picture is loaded from the one path `ART_PATH` in `scripts/game/title.gd`.

## Known rough

Never seen on a GPU (Forward+ look, fog, headlight beams, SDFGI and the wet shader's reflections are
unjudged); the creature animations have been seen only as Blender stills and as software-rendered
frames; difficulty and the pack's numbers are guesses to tune by hand (the autopilot loses about a
third of its hull to crashes in a minute and is wrecked by one pack; a pack takes a car that has stopped
in under ten seconds); the audio was never listened to; Windows export has no icon or version resource.

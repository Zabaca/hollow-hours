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

The story: New Game starts three radio-told missions in the quarter (Batteries, The Pharmacist, West Gate; chapter 1), with free
roam between them and the pack always out. The objective is at the top of the screen with a bar for each
hold and a timer on the timed steps; the radar (bottom left, car-up) and the full map (Tab) show the
objective in amber and the next mission's start in teal, with a ring and a column of light for each in the
world. The game saves when a mission completes; Continue resumes from the save, and Survive the Night (the
old five-minute round, below) appears on the title once chapter 1 is finished.

The end of chapter 1: reaching the west gate while it is open (it opens a minute after you take Vera and Teo aboard, and
shuts again 20 s later) drives the car out onto the road beyond the wall. First light comes up, Vera and Ruck
speak their last lines, the camera draws slowly back round the stopped car, the screen fades to black and a card
reads "Chapter 2, The next night". The game saves (The Long Road next) and cuts to the harbour city, a second, larger
map (chapter 2): the car is at the cordon's highway checkpoint at the far east end, at night again, and The Long Road
begins at once: drive the divided highway, about 1.2 km, into the city, through a toll plaza, a dead traffic jam with one
gap in it and past a fallen overpass (the way round is through a truck stop), with creatures waiting in a few of the
stalled cars. Reaching the east ring road completes the mission and leaves the car in free roam in the harbour city (the
rest of chapter 2 is built in later slices; Continue then reads "Free roam"). The credits are for the story's last mission,
which is not built yet.

How to survive: creatures stay out of your headlights and the few live street lamps while they
stalk you, then sprint, flank and pounce. A pounce is a tell you can read: the creature stops and
crouches for over half a second (a hiss, its eyes flaring), then leaps along the line the car was
taking and does not steer in the air. Swerve, brake hard or boost and it lands behind or beside you,
tumbles and gets up; carry on straight, or crawl, and it takes hold. One on the car claws at the hull
and drags it back; shake it off with a handbrake slide, hard swerves or by scraping that side of the
car along a wall or wreck (the bar under "SOMETHING IS ON THE CAR" fills as you do). A creature you shake
off is thrown clear, stunned for a moment and cannot take hold again for four seconds. Run the others
down: it takes the car's own speed into them, about 25 km/h (32 km/h for one lying stunned, 29 km/h for one in mid-leap),
so charging a crouching creature head-on at 45 km/h or more kills it, and each kill puts a little boost back
(above 60 km/h the impact dents the car too). First light is five minutes away.

## Layout

```
project.godot, export_presets.cfg   Windows / macOS / Linux export presets
scenes/title.tscn                   the first scene: the title, its menus, Settings and Credits
scenes/main.tscn                    the round; main.gd builds everything in code
scripts/sim/                        the simulation, pure GDScript, runs headless
  car_sim.gd, sim_body.gd, sim_collide.gd   the port of Roadkill's car.js / body.js / world.js
  sim_world.gd, nav_grid.gd         colliders from a city's layout (answered from 16 m buckets, so a query costs what is near, not the city's size), A* grid for the creatures
  cities.gd, layout_check.gd        the registry of cities (id, layout, model); the check that a layout has the shape a city must have
  gaunt_sim.gd, pack_sim.gd         the creature's states and the pack's AI and director (and its story hooks)
  game_sim.gd                       hull, boost gauge, crashes, claws, the night clock, the escape
  story_data.gd, mission_sim.gd     the story as data (places, radio script, three missions, each place and mission naming its city, chapters) and its state machine
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
  city_layout.gd                    GENERATED by tools/blender/city.py: the quarter's layout (colliders, roads, lights, spawns, the gate record)
assets/cities/                      the harbour city (chapter 2): harbour_city.glb and harbour_layout.gd, GENERATED by tools/blender/harbour.py (docs/harbour-city.md)
shaders/                            wet_ground (puddles, ripples), screen_fx (post effects), title_fx (title weather), marker_beam (mission markers)
assets/models/                      bruiser.glb, gaunt.glb, city.glb (made by tools/blender/*.py)
assets/audio/                       generated sound and music, plus Roadkill's engine and impacts
assets/fonts/                       Cormorant (SIL Open Font License, licence beside it), the menus' face
assets/ui/title_art.png             the title's picture: for now a frame of the game itself, to be replaced by the key art
tests/                              car_test (vs Roadkill's own code), pack_test (behaviour), world_test (near-only queries, the pack following the car, layouts), harbour_test (the harbour city and The Long Road), settings_test, menu_nav_test, mission_test (the story and its save), presenter_test (the story on screen), story_input_test (the map and menus with real key events), radio_test (the radio); probes: autopilot_probe, cost_probe, probe, encounter_probe
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
   godot --headless --path . res://tests/world_test.tscn
   godot --headless --path . res://tests/harbour_test.tscn
   godot --headless --path . res://tests/settings_test.tscn
   godot --headless --path . --script res://tests/menu_nav_test.gd
   godot --headless --path . res://tests/mission_test.tscn
   ```

   `world_test` holds the bucketed world to the whole-city loops it replaced (the same answers on the quarter, on a city
   three times as wide and tall and on a long thin one with a 1.2 km barrier), the path grid to the same solid cells, a
   query and a step to the same cost whatever the city's size, the pack to following the car, and LayoutCheck to what a
   layout must be. `harbour_test` checks the harbour city: its layout, its model, every place clear and reachable by road
   from the highway checkpoint, the highway leg at 1 km or more, the dev flags, the stalled-car creatures (released only
   within range, once), the autopilot driving The Long Road (pack off, and live with the hull held), and what happens after
   it. `settings_test` checks the settings file's round trip and the defaults on a missing or damaged one.
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

   Story flags: `--story` starts a new story, `--continue` continues from the save, and `--mission=N` (1 to 4) starts mission N directly, the car at
   its start (4 is The Long Road, on the highway in the harbour city); `--city=ID` loads that city (`quarter` or `harbour`;
   by default the one the story is in; with no mission it is Survive the Night there); `--seed=N` fixes the pack; `--save=PATH` reads and writes the save there (for Continue
   screenshots). A story run started by a flag with no `--save=` uses `user://dev_save.json`, never the player's
   `save.json`, so screenshot runs cannot overwrite a real save. Combine them with `--start=x,y,angle`, `--drive=0,0` and `--shot-game=SECONDS` (game time)
   to photograph a moment, e.g. a hold at the motel office:
   `-- --mission=1 --seed=11 --start=-20.5,41.5,3.14 --drive=0,0 --shot-game=2.7 --shot=/tmp/hold.png`.

   To see chapter 2 without playing chapter 1: `godot --path . -- --mission=4` (the harbour city, The Long Road), or
   `-- --mission=3` to play the West Gate mission and watch the ending, the card and the cut. `--screen=chapter` shows the
   card; `--shot-city=ID` takes `--shot` only in that city (for a run that cuts from the quarter to the harbour city);
   `--perf=SECONDS` prints frame time and draw calls after a 4 s warm-up and quits (vsync off; use it with `--demo`, or
   `--start=x,y,angle --drive=0,0` to hold a spot; the Mac's display caps frames at 120 fps, so the figure to watch is the
   render's CPU time and the draw calls).

   The west gate and the ending: `--gate=open|opening` shows the gate open (or opening 1.5 s in), `--cam-side=H`
   puts a low camera H metres up and 7 m to the car's left (for judging how it sits on the road), and
   `--screen=ending` puts the car on the avenue with the gate open and drives it out as reaching the gate
   would (the pull-back starts about 7 s in and the credits about 18 s in, 3 s of that being the screen's own
   delay; use `--quit-after 12000`).

   Menu screenshots: `--screen=title|settings|controls|credits|confirm|pause|pause-settings` opens that screen
   instead of the round, and `--shot=PATH --shot-at=SECONDS` then saves it and quits (the pause
   screens open 8 s into the round, and `--shot-at` counts from there). The story screens
   `--screen=map|fail|complete|chapter` open the full map, the failed-mission menu or the completion card 3 s into a
   mission (use them with `--mission=N`). Use `--resolution 1600x900`
   before the `--`, `--audio-driver Dummy` for silence and `--quit-after FRAMES` as a frame limit:

   ```
   godot --path . --resolution 1600x900 --audio-driver Dummy --quit-after 900 -- --screen=settings --shot=/tmp/settings.png --shot-at=2
   ```

## A city's layout

A city is a layout dictionary plus a model, registered in `scripts/sim/cities.gd`. The layout's shape (arena, boxes, posts,
blocks, roads, lights, creature spawns, fires, player start, gate; all axis aligned, nothing assuming a size) is written at
the top of `scripts/sim/sim_world.gd`, and `LayoutCheck.problems(layout)` lists what is wrong with one, so a city's generator
or test can assert it is empty. `tools/blender/city.py` writes the quarter's as `scripts/game/city_layout.gd`. To add a city:
generate its layout and model, add its id to `Cities.IDS` and a branch to `Cities.layout` and `Cities.model_path`, and give
its places and missions `"city": id` in `story_data.gd` (a city's safe start is the place marked `safe: true`). A chapter is a
run of missions in one city (`StoryData.chapters`). A save that finished the story as it was, when the story has since grown
past it, loads as "the next chapter next" (`SaveStore.upgraded`), never as damaged.

The second city, the harbour city (`Cities.HARBOUR`), is generated by `tools/blender/harbour.py` into `assets/cities/`;
`docs/harbour-city.md` says how its layout, its checks and its autopilot grid work. Its layout's one rectangle holds the
city in the west and a 1.2 km highway running out of the east side; the model is one mesh per block and per 100 m of highway,
which `City` hides beyond the fog (`CULL_RANGE`). The car's path grid for it is 1 m cells (`Autopilot.HINTS`), since a 2 m
grid with a wide berth cannot see a 4 m squeeze.

The simulation answers every question from 16 m buckets, so only what is near the car, a creature or a line is looked at.
`tests/cost_probe.tscn` prints what a query, a step and the world's and path grid's builds cost in the quarter and in synthetic
cities (`tests/synthetic_city.gd` makes one of any size); `tests/autopilot_probe.tscn -- --seeds=20` plays the story with the
autopilot over many seeds and counts the finishes, the "no worse" check for a change to the world, the pack or the driver.

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
needed when changing a model). The creature also needs ImageMagick (`magick` on the PATH; `brew install imagemagick`) to write its skin
textures, and Cycles to bake them (about 30 s):

```
Blender --background --python-exit-code 1 --python tools/blender/car.py
Blender --background --python-exit-code 1 --python tools/blender/creature.py       # add -- preview for contact sheets of the clips (ONLY=sprint:0,4,8 picks frames, VIEWSIDE=front)
Blender --background --python-exit-code 1 --python tools/blender/city.py           # also rewrites scripts/game/city_layout.gd
```

The creature (the Gaunt) is `tools/blender/creature.py`, built on the shared geometry in `tools/blender/gk.py`. The other two looks
considered for it, and the Gaunt it replaced, are kept in `tools/blender/concepts/` with the scripts that render the comparison shots.
In the game, `godot --path . --resolution 1600x900 --audio-driver Dummy res://tests/creature_shots.tscn -- --drive=0,0 --no-hud --seed=3 --start=-30,0,0 --scenario=lit --cam=front --out=/tmp/gaunt.png`
saves a frame of one creature in a given state (stalk, lit, sprint, wind, leap, latch, thrown, stunned, missed, dead; see the file's header).

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

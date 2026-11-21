# Follow-ups

Should-fix findings and nits from reviews, to pick up in a later change.

## From the slice 1 review (title and menus, merged 02a4318)

Nits:
- F11 on the title with Settings open leaves the Fullscreen row stale (title.gd).
- Session.screen outlives Quit to menu (a developer flag only).
- Colours are hard-coded outside menu_style.gd (hud.gd writes Color(MenuStyle.BONE, 0.72) four times; pause_menu.gd builds the left_shade gradient inline). title.gd calls SettingsPanel._build_controls, a private method. MenuStyle.rule's alpha is unused. menu_nav_test's helper names differ from the other tests'.
- The left stick is untested in the menus.

## From the slice 2 review (missions in the simulation, merged with this note)

Nits:
- Unverified: if Godot's Windows rename isn't atomic, fall back to reading save.json.tmp.

## From the followups-1 review (merged)

Nits:
- story_data.gd's spawn note says hunters stay at least `clear` from the car, but _make's jitter makes the real guarantee about clear minus 1.7 m. The `clear` key is also unused by any mission.
- _spawn_hunting now draws one rng value per creature, so seeded replays of the pharmacy spawn changed. Nothing pins them.

## From the slice 3 review (missions on screen, merged c314d0a)

Nits:
- The subtitle layer (23) sits above the map (22) and the pause menu (20), so a line mid-speech stays drawn over them.
- StoryHud.subtitle_source is untyped; type it Radio.
- Before the first checkpoint, the fail menu's "Retry mission" does the same as "Restart mission" below it.
- Continue's note says "Mission 2", not the mission's name.
- Duplication: StoryHud._text and Hud._label; FailMenu and ConfirmPanel build the same heading, text and rows; GameSim.start_story_at writes the save layout as a literal that must match MissionSim.save_data(). ConfirmPanel's heading_text, body and yes_text are never set. StoryPresenter.restart_mission only forwards. MapView.mode is typed int, not Mode.
- README's Layout omits input_setup.gd and gm.gd.
- The HUD restyle also changed Survive the Night's HUD, which the spec said stays unchanged (asked for by the lead).

## From the voices review (slice 5, merged)

Nits:
- clear() during the opening squelch plays the closing static for a call that never spoke.
- _music_duck takes the first Amplify on the Music bus.
- say() or clear() before the node is in the tree errors.
- radio.gd builds the path twice, and advance()'s OPENING and GAP branches are identical.
- voices.ts copies balance(), buy() and the run loop from generate.ts, hardcodes `godot` instead of honouring $GODOT, re-converts all 21 files on a run with no ids, and exits 0 when a line fails.
- generate.ts's header says tools/audio/out is git-ignored, but the raw takes are committed on purpose. Fix the header.

## From the slice 4 review (the West Gate and the ending, merged)

Nits:
- Survive the Night's dawn fog now thins (the spec said unchanged; the lead accepted it).
- The Bruiser's tyres reach 0.175 m below the model's origin, so the car sits in the road's skin (this is how it always drives); the pull-back's high angle and the wet road's reflections can read as hovering.

## From the followups-2 review (merged)

Nits:
- The gate leaves stand up to 0.36 m inside the arena (gate_view.gd RAIL_X), so a car against the shut gate or sliding past the open leaves clips them slightly. Moving the ribs to the leaf's outer face would cut it to about 0.1 m.
- The escape's rest distance is fixed at 26 m, so a 30 m/s crossing ends with a hard stop (about 28 m/s squared, a visible nose dip). Lengthen the rest distance for high entry speeds (the road runs out to 44 m).
- GateView runs PROCESS_MODE_ALWAYS, so its lamps, searchlights and leaves keep moving under the pause menu. Run it Always only while the fail menu is up.
- city.py's gate_frame docstring says the whole frame stays outside x = -70, but the rail sits just inside (0.12 m high).

## From the follow-on review (beams and contact shadow, merged)

Nits:
- The beam cones are 90 m long and only depth-tested, so from inside the quarter a cone can show passing through a building, and in the ending it ends in a hard line on the road. Check this with a windowed shot from inside the quarter looking west while the gate is shut.
- The beams also sweep the sky in Survive the Night, because GateView is built in both modes.
- The contact shadow (now along the car) still only lightly darkens the tyres (alpha about 0.17 there). Tune its size and falloff by hand. On a kerb, half of it hides under the sidewalk.

## From the encounters round

- The autopilot is a weak driver against a pack that fights (the guard in mission_test runs it with the creatures live and the hull held, and it finishes on every seed tried only with the 3:00 shutter and its kill-step tactics: charge on the avenue, no dodging there). It is a proxy, not a measure of how a person fares: hand play is still the test of the pharmacy run-down and of the motel's 4-second hold.
- A hunter that is hugging the car (cooldown running, 1 to 2 m off the flank) runs alongside and cannot be hit: kills come from the front. A bump or knock does not kill it.
- Hunters lead a fast car: above about 80 km/h a pursuer runs ahead of the car on the intercept it computed, so the pack is harmless from behind at that speed. Only a dent on a very fast run-down was added.
- The spec's 2:00 shutter is now 3:00 (StoryData.SHUTTER_SECONDS); the option file still says 2:00.

## From the encounters review (the fight rework, merged)

Should-fix:
- **The live-hunter guard rests on five seeds and a pinned hull.** On 10 seeds with the hull held, 8 finish (seed 6 fails the shutter); with the hull not held, 7 of 10 finish (seeds 6 and 8 are wrecked at the pharmacist). Base wrecked none at the pharmacist. Run 10 or more seeds and assert a pass rate, with the hull held and not held.
- **The shutter is 3:00, the option file says 2:00.** The owner decides after playing whether it should be a real clock (2:00 or 2:30).
- **Straight and fast is strong.** At 60 km/h on a straight the pack is near-harmless (creatures ahead are run down 83% of the time, about 14% latch). The danger sits at corners, stops and crashes. If the owner wants more threat: flank and rear pressure from side streets, or a smaller mid-leap kill window (LEAP_KILL_SPEED).

Nits:
- ~~autopilot.gd's kill step hard-codes the avenue's coordinates.~~ Closed by the chapter 2 slice 1 build: it reads the street at the objective's place from the layout's roads.
- The "lands clear" check passes at exactly its 2.5 m threshold.
- Throw-off at a crawl is still long (5 km/h: swerves 4.1 s, slide 2.4 s).

## From the creature review (the new Gaunt, squash-merged)

Nits:
- On LATCHED to THROWN the side-slot offset (0.45 m) drops to 0 in one frame.
- Hand tests still open: whether a creature on a side slot sinks into the door, whether a latched creature blocks the chase camera in hard turns, and frame time on a weak graphics card.
- The wind-up crouch at 10 m is a faint rim in dark fog; the rim strength (0.55 in gaunt_view.gd) is the lever.
- The model is built by script and still reads simple up close (tube-like limbs, a plain jaw). Decided 2026-11-20: keep the script-built model. One free image-to-3D try (Hunyuan3D 2.1, shape only) only smoothed the same shapes and grew a second pair of arms, and the owner judged ours better. Improve the creature in tools/blender/gaunt_body.py; a generator would need a realistic painted concept as input to be worth another try.

## From the chapter 2 slice 1 build (a second, bigger city: the simulation looks only at what is near)

Nits and things to know:
- The autopilot's chicane at the quarter's central junction (the narrow gap its own grid calls shut) is now a per-city hint (`Autopilot.HINTS`). Chapter 2's squeezes (a gap a car and a half wide) will meet the same limit: the car's grid should learn to take a gap rather than gain a hint per roadblock.
- The full map drew the west gate's gap 10 m wide, a number written into the map; it now draws the gate record's 8 m, which is the width of the wall's gap.
- GateView, the atmosphere and the `--screen=ending` developer flag still assume the west gate and the quarter; the sim, the camera and the map do not. The harbour city's slice builds the lift bridge's view beside the gate's.
- With the pack's director on, the autopilot finishes no story run, before or after (it is a proxy for the guard with the director off; 0 of 10 with the hull held in both). The pack's newcomers now come in 60 to 120 m out and ahead of the car, which is the change the option asked for.

## From the chapter 2 slice 2 and 2b build (the harbour city, the cut, and The Long Road)

Nits and things to know:
- The autopilot is slower than a driver where the road is tight (11 m/s where a wall or a stalled car is within 2.4 m of its way) and, with the creatures in the stalled cars and the pack live and the hull NOT held, finishes The Long Road in 4 of 6 seeds (it is wrecked after the truck stop's east queue in the others). With the hull held all six finish. The creatures' number and spacing (`HUNTER_SPACING`, `HUNTER_RELEASE` in `harbour_plan.py`) and the pack of 2 are the levers; they are for the owner's hand play to set.
- `City._cull_pieces` hides a block or highway chunk further than `CULL_RANGE` (170 m, plus half its size) from the camera. Godot's visibility range measures to the piece's own bounds, so a very tall piece could pop in late; none does today. The Mac's display caps frames at 120 fps, so `--perf` shows the cap, not the headroom: read the render's CPU time and the draw calls (the quarter about 1,300, the harbour city's centre about 2,600 on High).
- The full map's frame (`map_frame`) shows the city and 150 m of highway; the car and the objective pin to its edge with the distance when they are out along the road. The place labels past the frame are not drawn. A route line (slice 3) will want the whole highway.
- `StoryData.UNVOICED` lists The Long Road's five lines, which have subtitles and no audio; buying the voices empties it, and `radio_test` then wants every line voiced again.
- The title's Continue says "Free roam" after The Long Road, the end of what is built; it says "The end" only when a story's last mission closes it (`closes_story`).
- `GateView` still draws the west gate's leaves and searchlights at the harbour city's gate (the lift bridge's far end), which is where the sim's gate record puts them; the lift bridge's own view is slice 4's.
- `Session`'s chapter cut reloads the main scene with the save the chapter's end wrote as `continue_save`; a developer run started by `--mission=3` uses the scratch save, so it never touches the player's.

## From the chapter 2 slice 3 build (Dead Convoy, Floodlights, The Lift Bridge up to the control house)

Nits and things to know:
- The autopilot is weak against creatures clinging to it in a tight street: with the ambushes live, the director off and the hull held, it finishes Dead Convoy (in 190 to 330 s, against 112 s with them off) but not Floodlights inside its 360 s timer (it needs about 220 s with the ambushes off, and loses 200 s or more to creatures at the depot and the posts); with the pack on as well it can stall in a squeeze for good. A change in the autopilot's handling of a latched creature in a squeeze (it keeps its line and boosts on through; in the open it swerves as before) helped a little. The numbers that set how deadly the legs are: `AMBUSH_COUNT` (2) in `harbour_plan.py`, `AMBUSH_MAX` (2 a leg), `AMBUSH_RELEASE` (35 m) and `AMBUSH_ROAM` (3) in `story_data.gd`, `FLOODLIGHT_SECONDS` (360). Hand play sets them.
- Dead Convoy begins the moment The Long Road ends (its start place is the east ring road, where the car stands), so there is no free-roam gap there; Continue puts the car at a mission's `resume_at` place, not at the far end of the highway.
- A save made when The Long Road was the last built mission (next empty, ending seen) loads as Dead Convoy next; the same rule reads a save made at the end of whatever mission says `closes_story: false` (today The Lift Bridge) as the next mission once one exists.
- A retry from a checkpoint brings the floodlights timer back to what was left when the checkpoint was reached, not a fresh clock.
- The route line and the wide radar are for the cities with a route grid (`Cities.ROUTE_GRIDS`, the harbour city's); the quarter has none, so chapter 1 is unchanged. The route is worked out about once a second on the car's 1 m grid (4 ms for the longest), and drawn as a faint amber line.
- The field hospital's floodlights (layout tag `hospital_flood`) dim over the last third of the floodlights timer and go out when it fails; `main._floodlights` and `City.tag_levels` do it.
- With `CLOSED_ROADBLOCKS` off every chapter 2 test still passes except the run to the lift bridge (328 m, under 450): the other legs are 361 to 519 m.

## From the chapter 2 slice 4 build (the bridge comes down, the crossing, the ending)

Nits and things to know:
- The lift bridge's colliders (`closers` on the layout's lift record) leave the world when the mission says `bridge: "down"` (SimWorld.set_lift) and the creatures' and the car's path grids are built again (GameSim.set_bridge, about 70 ms in the harbour city, during a hold). The deck and its cables are their own pieces of the model (`lift_deck`, `lift_cables`) that BridgeView moves; if the generator's lift section changes, keep those two names and `deck_up_z` / `cable_top_z` on the bridge record.
- The harbour city has no GateView: its way out is the bridge, and the gate record is only the gap in the far bank's wall (the model has the piers and the road beyond). `--gate=open|opening` there shows the bridge instead.
- A save written when The Lift Bridge was only built as far as the control house (seven done, nothing next, no `finished` flag) loads as that mission still to play (`SaveStore._unfinished_end`); the story's real end writes `finished: true`.
- Stand-in sounds on the bridge: the gate's klaxon for the horn, the gate's rolling leaves for the motors, a slam for the deck meeting the road. Slice 5 buys the real ones (the list is in the slice 4 report).
- The credits' last line is still "Red got out." (the option asks the owner to approve a new one); the closing lines are subtitles only (`lb_end_1`, `lb_end_2`).
- The full map's height is 600 px (not 760) in a city with a route grid so the radio's subtitles sit below it; the quarter's map is unchanged. Place names on the map's bottom road are drawn above their spot.
- Survive the Night in the harbour city starts at the highway checkpoint (the layout's player start), with the pack's director and the night clock as in the quarter; it has not been tuned for a 1.6 km map.

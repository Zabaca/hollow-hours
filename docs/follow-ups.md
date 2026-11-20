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

- The autopilot is a weak driver against a pack that fights (the guard in mission_test runs it with the creatures live and the hull held, and it finishes on every seed tried only with the 3:00 shutter and its kill-step tactics: charge on the avenue, no dodging there). It is a proxy, not a measure of how a person fares: hand play is still the test of the pharmacy run-down and of the shop's 4-second hold.
- A hunter that is hugging the car (cooldown running, 1 to 2 m off the flank) runs alongside and cannot be hit: kills come from the front. A bump or knock does not kill it.
- The stunned creature plays the "dead" clip with dim eyes; a stagger or get-up clip would read better (creature animations are being redesigned elsewhere).
- Hunters lead a fast car: above about 80 km/h a pursuer runs ahead of the car on the intercept it computed, so the pack is harmless from behind at that speed. Only a dent on a very fast run-down was added.
- The spec's 2:00 shutter is now 3:00 (StoryData.SHUTTER_SECONDS); the option file still says 2:00.

## From the encounters review (the fight rework, merged)

Should-fix:
- **The live-hunter guard rests on five seeds and a pinned hull.** On 10 seeds with the hull held, 8 finish (seed 6 fails the shutter); with the hull not held, 7 of 10 finish (seeds 6 and 8 are wrecked at the pharmacist). Base wrecked none at the pharmacist. Run 10 or more seeds and assert a pass rate, with the hull held and not held.
- **The shutter is 3:00, the option file says 2:00.** The owner decides after playing whether it should be a real clock (2:00 or 2:30).
- **Straight and fast is strong.** At 60 km/h on a straight the pack is near-harmless (creatures ahead are run down 83% of the time, about 14% latch). The danger sits at corners, stops and crashes. If the owner wants more threat: flank and rear pressure from side streets, or a smaller mid-leap kill window (LEAP_KILL_SPEED).

Nits:
- autopilot.gd's kill step hard-codes the avenue's coordinates.
- The "lands clear" check passes at exactly its 2.5 m threshold.
- Throw-off at a crawl is still long (5 km/h: swerves 4.1 s, slide 2.4 s).

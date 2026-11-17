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
- `--mission=N` without `--save=` writes the completion save into the player's real save file.
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
- README's `--screen=ending` timings are stale: the pull-back starts at about 7 s and the credits at about 18 s.

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

## From the voices review (slice 5, merged)

Nits:
- clear() during the opening squelch plays the closing static for a call that never spoke.
- _music_duck takes the first Amplify on the Music bus.
- say() or clear() before the node is in the tree errors.
- radio.gd builds the path twice, and advance()'s OPENING and GAP branches are identical.
- voices.ts copies balance(), buy() and the run loop from generate.ts, hardcodes `godot` instead of honouring $GODOT, re-converts all 21 files on a run with no ids, and exits 0 when a line fails.
- generate.ts's header says tools/audio/out is git-ignored, but the raw takes are committed on purpose. Fix the header.

## From the slice 4 review (the West Gate and the ending, merged)

Should-fix (in the followups-2 round):
- **Speed snap at the gate.** The escape lerps from the trigger to a fixed spot, so a car arriving at 30 m/s drops to about 12 m/s in one tick, and the chase camera's FOV and distance snap. Start the curve at the car's own speed.
- **Pause during the credits.** Pause and Map still open in the roll's first second, and the roll then eats the next key as a skip. Pausing during the fade leaves an invisible live menu under the blackout. Block pause and the map once the ending reaches roll, fade or done.
- **Piers stick into the arena with no collider.** They reach 0.7 m past the sim wall at x = -70, and the shut leaves sit about 1.8 m behind the wall. Keep the piers outside x = -70 and put the leaves at the wall's inner face.
- **Screenshot flags write the real save.** `--screen=ending` and `--mission` without `--save=` overwrote the player's save on 2026-11-16 (it was moved aside to agent-run-aside/). Story screenshot flags should default to a scratch save path.
- **The pull-back jumps 2.6 m.** It starts at dist + 2.6 while the chase camera rests at dist. Lerp the radius from dist.
- **The last credit line vanishes before the fade.** _end() hides the roll; keep it visible through the fade.

Nits:
- hud.gd: fade_out sits under use_story_layout's doc comment. fade_out is duplicated in hud.gd and story_hud.gd. The gate_leaves play_at line appears twice in main.gd. Docs are missing on CreditsRoll.start and skip and GateView.setup. gate_view.gd's shape comments are stale. city.py's gate_frame has an unused `ax`. CanvasLayer numbers 24 and 30 are magic.
- Survive the Night's dawn fog now thins (the spec said unchanged; the lead accepted it).
- The closing lines play as the car crosses the gate, before the pull-back. The spec placed them after.
- pullback_progress() returns 0 at done, so the camera snaps back under the black.
- The fail menu freezes the gate leaves about 17% closed. A restart during the gate run plays a stray gate_leaves sound.

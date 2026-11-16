# Follow-ups

Should-fix findings and nits from reviews, to pick up in a later change.

## From the slice 1 review (title and menus, merged 02a4318)

Nits:
- F11 on the title with Settings open leaves the Fullscreen row stale (title.gd).
- Session.screen outlives Quit to menu (a developer flag only).
- Colours are hard-coded outside menu_style.gd. The heading-and-rule block is copied in three panels. title.gd calls SettingsPanel._build_controls, a private method. MenuRow.note and MenuStyle.rule's alpha are unused. menu_nav_test's helper names differ from the other tests'.
- The left stick is untested in the menus.

## From the slice 2 review (missions in the simulation, merged with this note)

Nits:
- Unverified: if Godot's Windows rename isn't atomic, fall back to reading save.json.tmp.

## From the followups-1 review (merged)

Nits:
- story_data.gd's spawn note says hunters stay at least `clear` from the car, but _make's jitter makes the real guarantee about clear minus 1.7 m. The `clear` key is also unused by any mission.
- The final step's two priority lines (end_vera, end_ruck) must keep their order in the radio queue: priority lines go ahead of normal ones but stay in order among themselves. Check this when the radio queue lands.
- _spawn_hunting now draws one rng value per creature, so seeded replays of the pharmacy spawn changed. Nothing pins them.

## From the voices review (slice 5, merged)

Should-fix:
- **Stale radio lines survive a retry.** Radio.on_event ignores the sim's "retry" event, and nothing drops queued lines on mission_failed, so an old call plays after a retry. Call clear() on retry, and drop non-priority lines on mission_failed. Slice 3 wires the radio, so it does this.
- **README is missing the radio.** The layout and test list leave out radio.gd and radio_test.

Nits:
- The radio clock uses scaled delta, so a hit-stop makes a subtitle outlast its voice. Use delta / Engine.time_scale, as fx.gd does.
- clear() during the opening squelch plays the closing static for a call that never spoke.
- _music_duck takes the first Amplify on the Music bus.
- say() or clear() before the node is in the tree errors.
- radio.gd builds the path twice, and advance()'s OPENING and GAP branches are identical.
- voices.ts copies balance(), buy() and the run loop from generate.ts, hardcodes `godot` instead of honouring $GODOT, re-converts all 21 files on a run with no ids, and exits 0 when a line fails.
- generate.ts's header says tools/audio/out is git-ignored, but the raw takes are committed on purpose. Fix the header.

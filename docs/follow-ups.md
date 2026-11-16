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
- _spawn_hunting now draws one rng value per creature, so seeded replays of the pharmacy spawn changed. Nothing pins them.

## From slice 3 (missions on screen)

- The ending is a stub: on story_complete the presenter shows a "First light" card and returns to the title after 9 s. Slice 4 replaces it (the closing lines, the pull-back, the credits roll).
- The radio keeps running (process mode Always) while the fail menu is open, so the wreck's call plays under it, and goes back to Pausable when the menu closes.
- Sky: the story lightens the sky with MissionSim.dawn_amount() at 0.04 per second; the first light of the ending is slice 4's.

## From the voices review (slice 5, merged)

Nits:
- clear() during the opening squelch plays the closing static for a call that never spoke.
- _music_duck takes the first Amplify on the Music bus.
- say() or clear() before the node is in the tree errors.
- radio.gd builds the path twice, and advance()'s OPENING and GAP branches are identical.
- voices.ts copies balance(), buy() and the run loop from generate.ts, hardcodes `godot` instead of honouring $GODOT, re-converts all 21 files on a run with no ids, and exits 0 when a line fails.
- generate.ts's header says tools/audio/out is git-ignored, but the raw takes are committed on purpose. Fix the header.

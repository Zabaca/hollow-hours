# Follow-ups

Should-fix findings and nits from reviews, to pick up in a later change.

## From the slice 1 review (title and menus, merged 02a4318)

Should-fix:
- **Settings file I/O belongs to SaveStore.** Lands with slice 2's merge. Settings keeps the schema; save_file and load_file go through SaveStore.write_json, read_json and set_aside. SaveStore.load_settings, write_settings and SETTINGS_PATH are deleted, and mission_test's settings cases move into settings_test.
- **Mute sticks across Quit to menu.** Each AudioMix starts with muted=false while the bus stays muted (audio_mix.gd). Read the state from AudioServer.is_bus_mute(0), or keep mute in Settings.
- **The credits label overruns.** "THE CITY AND THE CREATURE" runs into its value (credits_panel.gd).
- **--low leaks into the saved settings.** It's applied after Settings.boot(), so any settings change saves "low" (main.gd). Keep the run-time override separate from the saved choice.
- **The OFL licence text is not exported.** Add assets/fonts/OFL.txt to the export include_filter, or show the full text in Credits.

Nits:
- F11 on the title with Settings open leaves the Fullscreen row stale (title.gd).
- Session.screen outlives Quit to menu (a developer flag only).
- Colours are hard-coded outside menu_style.gd. The heading-and-rule block is copied in three panels. title.gd calls SettingsPanel._build_controls, a private method. MenuRow.note and MenuStyle.rule's alpha are unused. menu_nav_test's helper names differ from the other tests'.
- The left stick is untested in the menus.
- README links to a local Roadkill checkout path. Point it at the Roadkill repo instead.

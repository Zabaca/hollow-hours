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

## From the slice 2 review (missions in the simulation, merged with this note)

Should-fix (the first two before slice 4 draws the gate):
- **The gate trigger is wider than the gap.** The trigger radius is 6 m but the gap is about 3.9 m, so the escape can roll the car through the wall beside the gap (mission_sim.gd gate step, sim_world.gd). Require the gap test, or ease the car onto the gap's centre line.
- **Restart mission shuts the gate silently.** It sends no gate_closed event, so a drawn gate would stay open over a closed wall. Use one _close_gate helper that emits the event.
- **Quitting during the final roll-out strands Continue.** The final mission saves next "" with ending_seen false 4 s before story_complete, so resume() lands in roam with nothing to do. Skip that save, or play the ending on resume.
- **A free-roam wreck loses its totals on revert.** revert_to_save rebuilds from last_save, so wrecks, kills and seconds are lost. Carry the live totals across.
- **Pharmacy hunters can spawn inside the car.** They're placed 8 m out at a random bearing with no car check. Choose the bearing away from the car, or keep at least the ring's distance.
- **Completion lines don't jump the radio queue.** Only fail lines carry priority:true, but the spec says completion lines do too.
- **Settings ownership.** See the slice 1 notes: SaveStore owns the I/O, Settings the schema. Delete SaveStore.load_settings and write_settings.

Nits:
- mission_test has a dead expression at line 189, and it reads sim.mission.state, where the spec says to use events or objective().
- MissionSim sets pack.alerted_spawns directly; use a pack hook.
- probe.gd's header still mentions main.gd's autopilot.
- MIN_RETRY_HULL, HOLD_SPEED and ROAM_PACK are tuning numbers that belong in StoryData.
- Document that the presenter stops stepping on mission_failed.
- The map-only places were checked against city.py building centres; say so in the comment.
- Unverified: if Godot's Windows rename isn't atomic, fall back to reading save.json.tmp.

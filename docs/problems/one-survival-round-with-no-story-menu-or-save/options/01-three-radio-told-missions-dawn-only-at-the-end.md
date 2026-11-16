---
problem: one-survival-round-with-no-story-menu-or-save
title: Three radio-told missions on a mission layer inside the simulation, no clock until the escape at first light, a title screen over painted key art made from our own render, saved between missions
summary: A title screen (New Game, Continue, Settings, Credits, Quit) over a painted key-art image made by repainting a Blender render of our own Bruiser and Gaunts. A short story told in 21 voiced radio lines from three people (Vera on the hotel roof, Teo in the pharmacy, Ruck at the cordon) carries three missions in order, Batteries (a delivery), The Pharmacist (a rescue) and West Gate (the escape), with free roam between them and the pack always out. The five-minute clock goes: the night lightens a little each mission and first light comes only as you drive out through the west gate. Missions are a state machine inside the headless simulation, tested like the pack. A radar and a full map mark the objective. The game saves between missions, with checkpoints inside them. Six slices, about 18 to 26 agent hours including review, about 1,360 characters of voice (a 2,000-credit cap) and under $3 of image generation.
status: proposed
---

## Solution

### The story

**Premise.** Three nights ago the quarter was walled off. Something came up out of the storm drains: pale, starved, fast on all fours. The cordon outside calls them Gaunts. Nobody was meant to be left inside. You were, with a red muscle car and a radio that still picks up one voice.

**Cast** (three radio voices; you never speak, and they call you "Red" after the car):

| Who | Where | Voice |
|---|---|---|
| **Vera** | A night dispatcher stranded on the hotel roof with a radio and a dying battery. Dry, steady, kind. She runs the first two missions. | An older woman |
| **Teo** | A night pharmacist barricaded in the pharmacy tower. Young, scared, fast-talking. | A younger man |
| **Ruck** | An officer at the cordon outside the wall. Flat, tired, by the book. He offers the way out, and says the quarter burns at first light. | An older man |

### The three missions

| # | Mission | What you do | How it fails | How the pack presses |
|---|---|---|---|---|
| 1 | **Batteries** (delivery) | Starts with New Game. Drive to the 24-hour shop at the gas station, hold still at its south door for 4 seconds while the box is loaded, then drive it to the hotel's east door and hold for 3 seconds while Vera hauls it up. | The car is wrecked. | Three Gaunts. Loading sets off the shop's door alarm: every Gaunt within 90 m is alerted and a fourth joins. Every hold is a stop, and a stopped car is what they hunt. |
| 2 | **The Pharmacist** (rescue) | Start at the park hut, where Vera patches Teo's call through. Drive to the pharmacy tower on the avenue, run down two Gaunts, hold at the door for 3 seconds while Teo gets in, then take him to the hotel's east door (3 seconds). | Wrecked, or the shutter timer runs out: 2:00 from the call until Teo is in the car. | Four Gaunts, and two more placed at the pharmacy door already hunting when you arrive. |
| 3 | **West Gate** (the escape) | Start at the gas station, where the shop's aerial picks up Ruck. Pick Vera and Teo up at the hotel's east door (4 seconds). Then stay alive for 60 seconds until the gate opens, and reach the west gate at the end of the avenue within 20 seconds of it opening. Drive through: first light, the end. | Wrecked, or the gate closes before you reach it. | Four Gaunts until Vera and Teo are aboard; then six, all of them alerted, for the minute and the run to the gate. |

The quarter is small (a block is a few seconds' drive at top speed), so a mission's length comes from its stops and the pack, not from distance. Each mission is aimed at two to four minutes; the numbers above are first guesses, tuned by hand later.

**The places** (approximate map metres, read from the city layout; a test is the arbiter, below): the safe start where New Game and Continue begin, the layout's own player start at (-30, -2.5) facing east; the shop's south door, off the avenue, about (46, 7); the hotel's east door, on the east street, about (60, -16); the park hut, at the park's north gap, about (-32, -9); the pharmacy, on the avenue in front of the tower, about (-44, 4); the west gate, at the avenue's west end in the perimeter wall (x = -70).

### How a mission plays

1. **Free roam.** Between missions the city is open and the Gaunts are out (three, as at the start of today's round). The next mission's start is a blip on the radar and the map and a marker in the world. Mission 1 has none: New Game starts it.
2. **Start.** Driving into the start marker plays the opening call and shows the mission's title card ("MISSION 2  THE PHARMACIST") and its first objective.
3. **Steps.** Each step is one objective at the top of the screen with a marker in the world and on the radar: reach a place; hold still at a place (inside the marker, under 2 m/s; a bar fills, and pauses when you leave rather than resetting); run down a number of Gaunts; stay alive for a time; reach the gate in time. Calls play on the radio as steps change; the game never waits for a call to finish.
4. **Checkpoints.** After the box is loaded (mission 1), after Teo is in the car (2) and after Vera and Teo are aboard (3).
5. **Fail.** "MISSION FAILED" with the reason, and a menu: Retry from checkpoint (the car at the checkpoint's place, its hull as it was there but at least 60, a fresh pack away from the car; before the first checkpoint it restarts the mission), Restart mission, Quit to menu.
6. **Complete.** "MISSION COMPLETE", the closing call (which names where the next mission starts), an automatic save, and back to free roam.
7. **Hull** refills at each mission start and on Continue, and carries between the steps of a mission. Wrecked in free roam: back to the last save.

### The night and dawn

The five-minute countdown goes from the story. There is no clock in free roam or in a mission except the two step timers above. The sky lightens a touch with each mission, and first light comes only as you drive out through the west gate, when the survivors flee as they do today. Ruck's line ("At first light we burn the quarter") gives the escape its reason without putting a clock on the whole story.

Today's round stays in the game unchanged, available as **Survive the Night** (its five-minute clock, its dawn and its R to retry). Whether it shows on the title, and when, is an open question below.

### The map and the markers

- **Radar**, bottom left, round, car-up, about 120 m across: the buildings and wrecks drawn from the city layout, the car at the centre, the objective as an amber blip (pinned to the rim with its distance when it is beyond the edge), a mission start as a teal blip. No Gaunts on it: seeing them would undo the stalking. The hull and boost bars move beside it.
- **Full map**, from the pause menu or Tab (the gamepad's Back): the whole quarter north-up, with the places named (Pharmacy, Diner, Motel, 24H, Park, Bar, Pawn, Hotel, West Gate), the car and the objective.
- **In the world**, a ring on the ground and a faint column of light rising through the fog: amber for an objective, teal for a mission start. The glow is only a picture: it does not keep the Gaunts off, as the street lamps do.

### Saving and checkpoints

- **One save**, written when a mission completes and when the story ends, as JSON in the player's own data folder: a format version, when it was saved, the next mission, the missions done, whether the ending was seen, and a few totals (Gaunts run down, wrecks, time played). It is written to a temporary file and then renamed, so a crash mid-write never leaves a broken save. A save that cannot be read, or has an unknown version, counts as no save and is kept aside, not deleted.
- **Continue** starts at the safe start with full hull and the next mission's blip lit; the title shows which mission is next.
- **New Game** over an existing save asks first ("Start over? This replaces your saved progress.").
- **Checkpoints** live in memory only, inside a mission, as above. Quitting mid-mission resumes from the last save.
- **Settings** are saved the same way, in a file of their own, and applied at start.

### The title screen and menus

- **Title.** The key art fills the window with a slow push-in; a lightning flicker every 20 to 40 seconds with thunder; rain and the tension music under it; now and then a distant Gaunt screech. The title "HOLLOW HOURS" is drawn by the game, never painted into the image. Menu on the dark left third: **New Game, Continue** (greyed with no save; shows the next mission), **Settings, Credits, Quit**, and **Survive the Night** if the owner keeps it. A short fade in from black with a thunder crack opens it; any key skips. Keyboard, gamepad and mouse all work; the mouse shows in menus only.
- **Settings.** Volumes for Master, Music, Effects, Car, Ambience and Voice; graphics High or Low; fullscreen; subtitles on or off; the controls list (keyboard and gamepad, read from the game's own bindings; rebinding is out of scope). F3 and F11 still work in play and the screen follows them.
- **Pause.** Resume, Map, Settings, Restart mission (in a mission), Quit to menu. The world stops and the music drops; the radio pauses with it.
- **Credits.** Who made what, ElevenLabs for the voices and effects, Roadkill's car handling and recordings, the display font's licence, and Godot's licence notice, which its MIT licence asks a shipped game to include.
- **Mission cards.** A title card at a mission's start, "MISSION COMPLETE" and "MISSION FAILED", and the story's ending.

### The key art

1. **A reference render of our own models** in Blender: the Bruiser on the wet avenue at night, headlights on, one Gaunt clawing on its roof in its latch pose, two more crouched in the fog ahead with their eyes lit, one of the quarter's neon signs glowing teal behind, the left third kept dark for the menu. 1920 by 1080, EEVEE.
2. **Painted over** with Google's Nano Banana 2 through Zabaca's own `gemini-image` tool, using the render as the input image so the car and creature are ours, with the prompt below. Three drafts; the owner picks one; Nano Banana Pro repaints only the pick, and only if it has a visible flaw.
3. **Cost** at the tool's listed 1K prices: three drafts at $0.067 and one Pro final at $0.134, about $0.34. The cap is $3. The tool returns about 1376 by 768; the final is upscaled to at least 1920 by 1080, which a painted image takes well (asking for 2K directly is possible, its price not checked).
4. **Access.** The existing Gemini key on the owner's Mac, outside this repository; its billing is unchecked until the first call. If it fails: Workers AI on Zabaca's Cloudflare account through a short-lived token (prompt only), or the reference render itself graded as the key art (free and wholly ours, less painterly).
5. **Kept in the repository**: the reference render, the prompt and the chosen image, and the README says how it was made.

The prompt (the decision itself, so it is written here):

> Repaint this image as a dark, painterly horror key art illustration in thick oil paint with visible brush strokes. Keep the car's shape and the creature's shape exactly as in the image: a boxy dark red muscle car with a black bull bar and two dark stripes, and a pale, starved, long-limbed creature with a visible ribcage and spine, a long hinged jaw of needle teeth, a bony crest, three long claws on each hand and a whip tail, clinging to the car's roof. Night, heavy rain, cold fog. The headlights blaze through the rain onto a flooded avenue. Two more of the same creatures crouch in the fog ahead, their pale eyes catching the light. Dead street lamps, one flickering. A teal neon sign glows through the rain on a tall building. Wet asphalt reflects red and teal. Cold blue-green shadows, high contrast, wide cinematic frame, the left third of the frame dark and quiet. No text, no letters, no logos, no watermark, no people.

It names no film, game, artist, studio or franchise, and describes only what the reference render shows.

### The voices and the radio

**The script** (21 lines, 1,361 characters counted with the cue words in square brackets, which steer the voice and are neither spoken nor shown):

| Line | Who | Text |
|---|---|---|
| Batteries, call | Vera | [low, steady voice] Red car on the avenue. Yes, you. Keep moving. They come for anything that sits still. |
| | Vera | I'm on the hotel roof and my radio's dying. The all-night shop at the gas station has a box of batteries. Bring it to me. |
| At the shop | Vera | Pull up to the south door and hold still. Count to four. |
| Alarm | Vera | [urgent] That's the door alarm. Sorry. Hold on, hold on! |
| Loaded | Vera | Got it. Hotel, east door. I'll lower a rope. |
| Done | Vera | [relieved] Lights are back. And Red, someone else is on this band, near the park hut. Get close and I'll patch them through. |
| The Pharmacist, call | Teo | [whispering, scared] Hello? This is Teo, at the pharmacy. They're scratching at the shutter. It won't hold long. |
| | Vera | Hang on, Teo. Red, the pharmacy tower, north side of the avenue. Hurry. |
| At the door | Teo | [shouting] Two of them at the shutter! Run them down! |
| Cleared | Teo | Okay, okay. Stop by the door, I'm coming out. |
| Aboard | Teo | [breathless] I'm in. Drive! |
| Done | Vera | Teo's safe up here. If anyone outside can hear us, it's through the gas station's aerial. |
| Failed | Teo | [screaming] They're through the shutter! |
| West Gate, call | Ruck | [flat, tired voice] Unknown vehicle, this is the cordon. We open the west gate once, at the end of the avenue. At first light we burn the quarter. |
| | Vera | We're coming with you. Hotel, east door. Both of us. |
| Aboard | Ruck | Gate opens in sixty seconds. Keep moving. The whole quarter can hear you now. |
| Open | Ruck | Gate's open. Twenty seconds. |
| Failed | Ruck | Gate's shut. I'm sorry. |
| Ending | Vera | [quiet] Look at that, Red. First light. |
| Ending | Ruck | Vehicle is out. Seal it. |
| Wrecked (any mission) | Vera | [afraid] Red? Red, answer me. |

- **Model and cost.** `eleven_v4`, at about one credit per character (the rate the owner's other voiced work measured): about 1,360 credits. Four short effects (a radio squelch in, a burst of static and a click out, the gate's klaxon, the gate's steel leaves rolling) are aimed under 400 together. The tension bed is reused for the title, so no new music is bought. The round's cap is 2,000 credits, a hard stop.
- **Voices.** Three premade voices that differ by ear, picked by the builder from the account's voice list and its free preview clips; the previews go to the owner while the build carries on.
- **On the radio.** Lines play on a Voice bus that sounds like a handheld radio (high and low frequencies cut, a little grit), with a squelch before and after each call, and the music dips under them. Calls queue and never overlap. Subtitles name the speaker in their own colour (Vera teal, Teo amber, Ruck grey-red). Until a line's audio exists, its subtitle shows for its reading time, so everything but the voice slice is built and tested with no audio bought.

### Slices

Each slice ends with the import, `car_test`, `pack_test` and its own checks passing, and screenshots the builder takes itself: a windowed run with the dummy audio driver at 1600 by 900 and 1280 by 720, saving one frame and quitting on its own, with a frame limit so no run can hang.

| # | Slice | Agent hours | Needs |
|---|---|---|---|
| 1 | **Title and menus.** The title as the new first scene (with a placeholder background, a frame of the game itself, until the key art lands), New Game (today's round, for now), Continue greyed, Settings saved and applied, Credits, Quit; the pause menu (Resume, Settings, Quit to menu); the title's sound. Every existing command-line flag still goes straight into the game. | 3 to 4 | nothing |
| 2 | **Missions in the simulation.** The story data and mission state machine, the pack's new hooks, story mode without the dawn clock, the escape phase, checkpoints, the save and its round trip, the demo autopilot moved into the simulation so the tests can drive with it; the mission test. Headless only. | 4 to 6 | nothing (can run beside 1) |
| 3 | **Missions on screen.** The objective, timer and hold bar; subtitles from the text; the radar and full map; world markers; mission cards and the fail menu; New Game and Continue on the save; free roam; the sky by mission; Survive the Night if kept. | 4 to 6 | 1 and 2 |
| 4 | **The West Gate and the ending.** The city's west wall opened at the avenue with a gate frame and an approach road outside (the Blender city rebuilt, the layout gaining a gate record), the gate drawn and animated with its lamps and two cordon searchlights, the drive out, first light, a slow pull-back from the stopped car, the closing lines, a short credits roll, back to the title. | 3 to 4 | 3 |
| 5 | **Voices.** Pick the voices, a dry run that prints the character count, buy the 21 lines and four effects, the radio bus, subtitles timed to the audio; credits logged before and after. Reported as unlistened. | 2 to 3 | 2, and the owner's yes on the budget and script |
| 6 | **Key art.** The reference render, three painted drafts, the owner's pick, the final in the title. | 2 to 3 | 1, and the owner's yes on the spend |

About 18 to 26 agent hours in all, review rounds included. Slices 5 and 6 can run beside 3 and 4. The owner's time: answering the open questions (about 10 minutes), picking the key art (about 5), listening to the voices (about 5), and a hand play of the whole story after slice 4 (about 30), which is when the difficulty numbers get tuned.

## Trade-offs

- **No clock over the story rather than one night on a clock** (option 02). Free roam stays free, a failed mission costs only the mission, and dawn means the ending. The cost: the steady dread of a countdown is gone outside the two timed steps, and the old round's tested dawn is used only by Survive the Night and the ending.
- **Missions inside the simulation rather than in the scene.** The whole story can be played and checked headless, at many times real speed, exactly as the pack is; the presentation only draws events. The simulation's step grows a little.
- **Start markers rather than answering a call anywhere.** Free roam has somewhere to go and the map has something to mark. A mission cannot be started from wherever you happen to be.
- **Repainting our own render rather than a prompt alone.** The creature and the car in the key art are ours by construction, and the reference is kept as proof. It costs a Blender scene before any image call (part of slice 6's hours).
- **Calls as handheld radio rather than clean dialogue.** It fits the story, hides the small differences between takes and costs nothing (effects on a bus). Some voice detail is lost.
- **A small quarter.** Missions are short in distance, so the stops and the pack carry them. A bigger city is a later round.
- **Saving only between missions.** Simple and robust, as decided. Quitting mid-mission loses that mission's progress.

## User Stories

1. As a player, I want a title screen with a scary painted image, music and weather, so that the game sets its mood before I drive.
2. As a player, I want New Game, Continue, Settings, Credits and Quit on the title, so that I can start, resume, adjust or leave.
3. As a returning player, I want Continue to say which mission is next, so that I know where I am in the story.
4. As a player with a save, I want New Game to ask before replacing it, so that I never lose progress by accident.
5. As a player, I want to set the music, effects, car, ambience, voice and master volumes separately, so that I can hear the radio over the engine.
6. As a player on a weaker computer, I want a Low graphics setting that stays set between sessions, so that the game runs smoothly every time.
7. As a player, I want fullscreen in Settings and on F11, so that I can switch either way.
8. As a player, I want to see every control for keyboard and gamepad, so that I can learn them without leaving the game.
9. As a player, I want subtitles on by default with a switch, so that I can follow the calls with the sound low.
10. As a player, I want to pause and get Resume, Map, Settings, Restart mission and Quit to menu, so that I can step away or change something.
11. As a gamepad player, I want every menu to work with the stick and buttons, so that I never need the mouse.
12. As a player starting a new game, I want a voice on the radio to tell me where I am and what to do, so that the story pulls me in from the first seconds.
13. As a player, I want the current objective written at the top of the screen, so that I always know what to do next.
14. As a player, I want the objective marked on a radar and in the world, so that I can find it in the fog.
15. As a player, I want a full map with the places named, so that I can plan a route.
16. As a player, I want a bar that fills while I hold still at a stop, so that I know how long I have to survive standing there.
17. As a player, I want the hold to pause rather than reset if I have to shake a Gaunt off, so that a slide does not cost me the whole stop.
18. As a player, I want a visible timer on the timed steps, so that I know how long Teo can hold the shutter or the gate stays open.
19. As a player, I want the shop's alarm to bring the pack, so that the delivery has a real moment of danger.
20. As a player, I want Gaunts waiting at the pharmacy, so that the rescue feels like one.
21. As a player, I want the last minute before the gate to throw everything at me, so that the escape feels earned.
22. As a player, I want to drive out through the gate into first light, so that the story has an ending I can see.
23. As a player, I want "MISSION FAILED" to say why and offer a retry from the checkpoint, so that one mistake does not send me back to the start.
24. As a player, I want the game saved after each mission, so that I can stop and come back later.
25. As a player, I want free roam between missions with the Gaunts still out, so that the city stays dangerous when I am not on a job.
26. As a player, I want the next mission's start shown on the map, so that I can go when I am ready.
27. As a player, I want missions to unlock in order, so that the story makes sense.
28. As a player, I want calls to sound like a handheld radio with each speaker named in their own colour, so that I can tell who is talking while I drive.
29. As a player, I want calls never to talk over each other, so that I catch every line.
30. As a player, I want the sky to lighten a little as the story goes on, so that I feel the night running out.
31. As a player who finished the story, I want Survive the Night still there (if kept), so that I can play the old round for a score.
32. As a player, I want a credits screen, so that I can see who and what made the game.
33. As the owner, I want the key art to show our own Gaunt and Bruiser, so that it is ours and nobody else's.
34. As the owner, I want the voice spend capped and logged, so that this round stays inside its budget.
35. As the owner, I want a damaged save to be set aside rather than crash the game, so that a bad file never locks a player out.
36. As a builder, I want the whole story to be playable headless, so that a change to the pack or the rules cannot silently break a mission.
37. As a builder, I want every existing command-line flag to keep working, so that the README's commands and screenshots still run.
38. As a builder, I want a flag that starts a given mission directly and one that opens a given menu, so that I can screenshot any screen in seconds.
39. As a reviewer, I want the radio script to live in one place, so that the subtitles and the voices can never disagree.
40. As a reviewer, I want the key-art prompt and reference render kept in the repository, so that anyone can check it borrows from nothing.

## Implementation Decisions

- **Story data**, a new constant module in the simulation (beside the city layout's constant data): the places (name, map position, marker radius, a label for the map), the three missions (title, start place or none, the dawn amount, the pack size, the steps, the checkpoints, the timers) and the radio lines (an id, the speaker, the text with its cue words, and the subtitle without them). Every place, step, line and timer in this option is a row there, so tuning never touches logic.
- **Step kinds**: reach a place; hold at a place for some seconds (inside its radius and under 2 m/s; progress pauses outside); run down a number of Gaunts (counted from the run-downs and fatal throws since the step began); survive for some seconds; and the gate (reach the gate's trigger while it is open). A step may name lines to play when it begins and when it ends, a pack size, an alert (a place and a radius), and creatures to place (a place and how many, already hunting).
- **Timers** start at one step and stop when a later step completes (a single-step limit is the same thing), and fail the mission with their reason when they run out: the shutter (2:00, from the call until Teo is aboard) and the gate (20 seconds, from the gate opening until it is reached).
- **A mission state machine** (a new class in the simulation, in the shape of the pack: plain logic, its own events, no nodes) holds the current mission, step, timers, hold progress, checkpoint and the save's fields. The game simulation owns it in story mode and steps it at the end of each step, after the pack, and its events join the game's own event list. So the existing seam, one step and the events it reports, carries the story too. Its events: a mission started, an objective changed, a radio line, a hold's progress, a checkpoint, a timer, a mission completed, a mission failed (with the reason), the gate opened, escaped, the story completed, and a save asked for. It answers what the HUD needs: the objective's text, its place, the hold's progress, a timer's seconds left, and the blips.
- **Story mode in the game simulation**: the dawn clock is switched off (Survive the Night keeps it at five minutes); the pack's size comes from the story instead of the time ramp; a new escaped phase moves the car out through the gate at an easing speed with no collisions while the pack flees; and the car can be placed at a position, heading and hull, for checkpoints and Continue.
- **New pack hooks**: alert every Gaunt within a radius of a point; place a Gaunt at a point, already hunting; hold the pack at a size set from outside. The pack's behaviour is otherwise unchanged.
- **The demo autopilot moves from the main scene into the simulation** as its own class, so the demo, the story test and any later probe share one driver. With a story, it drives to the current objective, holds still at holds, and slides to shake Gaunts off as it does today. The old copy in the main scene is removed in the same change.
- **The save store** reads and writes the save and the settings as JSON in the player's data folder, through a temporary file and a rename. The file path is a parameter, so tests write their own.
- **A session holder**, static fields like the existing graphics settings, carries what the title asked for (story or survival, new or continue, a mission given by flag) into the game scene.
- **The title scene** becomes the project's first scene and is built in code like everything else. It hands any of today's game flags straight to the game scene, so the README's commands keep working. New flags: one to start a given mission directly, one to open a given screen (title, settings, pause, map, a failed mission, the ending) for a screenshot. The existing frame-and-quit flags work on every screen.
- **Menus** (pause, settings, map, fail, credits, confirm) are built in code like the HUD and stay live while the game is paused.
- **The HUD** gains the objective line where the countdown was (the countdown stays for Survive the Night), the timer, the hold bar, the subtitles, the mission cards, and the radar beside the bars. The warning when something is on the car stays.
- **A map view** draws the layout's buildings and wrecks, the arena, the car, the objective and the blips, at two sizes: the car-up radar and the north-up full map with place names.
- **A marker view** draws the ring and the light column for an objective or a start, from the story's events.
- **The gate.** The Blender city script leaves a gap in the west perimeter wall where the avenue meets it, adds a gate frame and an approach road outside the wall at the road's height, and writes a gate record (position, width) into the layout. Nothing else in the layout changes, and the script draws no extra random numbers, so every other box, light and spawn keeps its place. The game draws the gate's two steel leaves, its red and green lamps, and the cordon's two searchlights beyond the wall, and opens the leaves on the gate event. While the gate is shut, the arena wall in the simulation holds the car, as today.
- **The radio** plays a line's file if there is one and otherwise shows its subtitle for its reading time (about 14 characters a second, at least 2 seconds); squelch in and out; one line at a time from a queue; a failed or completed mission's line jumps the queue.
- **The audio mix** gains a Voice bus (a band-pass from about 300 to 3,400 Hz and light distortion), per-bus volumes from the settings, and a dip in the music while a line plays.
- **The graphics settings** grow the volumes, fullscreen and subtitles, and are loaded at start and saved on change.
- **Input**: a map action (Tab, the gamepad's Back). The restart action works only in Survive the Night; in the story, restarting is in the pause menu, so a stray key cannot throw a mission away.
- **The voice generator** is a sibling of the existing effects generator, with the same caching and credit log. It reads the lines from the story data through a short headless dump (no second copy of the script), buys each missing line by its id with `eleven_v4` and the speaker's voice, has a dry run that prints the character count, and refuses to buy more than 1,500 characters in one run without an explicit flag. The four new effects go through the existing effects generator.
- **Key art**: a new Blender script renders the reference from the existing car, creature and city models; the repaint goes through Zabaca's `gemini-image` tool; the key never enters the repository.
- **Fonts and notices**: one display font under the SIL Open Font License for the title and menu headings, committed with its licence; the HUD keeps the default font. The credits carry the font's licence and Godot's notice.

## Testing Decisions

- **The seam is the one the pack's tests already use: step the game simulation and read its events.** The story rides on that seam, so a new headless mission test scene runs exactly like the pack test, fixed seed, no window, exit code 0 on success, and joins the run-all script. A good test sets up a situation, steps, and checks what the events and the objective say; it does not reach into the state machine's fields.
- **The mission test covers:** a new story starts mission 1 with its objective and its first two lines; a hold fills only inside the marker and slow, and pauses outside; the run-down step counts kills from its start; a wreck fails the mission with its reason; the shutter timer fails mission 2 at 2:00; the gate timer fails mission 3 after 20 seconds; retry from checkpoint restores the step, the place and a hull of at least 60; restart mission starts over; a completed mission asks for a save, and the save written to a test file reads back to the same next mission; a damaged or unknown-version save reads as no save; mission 2 cannot start before mission 1 is done; every place is inside the arena, clear of every building, wreck and post with the car's clearance, and reachable on the path grid from the safe start; crossing the gate's trigger with the gate open ends the story, and with it shut the wall holds; the pack hooks alert only within their radius, place creatures where asked and hold the size.
- **The whole story, driven:** the autopilot plays all three missions start to finish with the pack switched off, within a bound of simulated time. This proves each mission can be finished by driving, not by moving the car by hand.
- **The settings round trip**: saved, loaded, defaults on a missing or damaged file.
- **Unchanged:** `car_test` and `pack_test` pass as they are; the pack test's dawn check still holds in Survive the Night.
- **The layout:** after the Blender rebuild, the regenerated layout differs from the committed one only by the gate record (read in the diff).
- **Screenshots** (the builder's own, windowed, dummy audio, self-quitting, 1600 by 900 and 1280 by 720), read by the builder before handing over: slice 1, the title, settings, the controls list and the pause menu; slice 3, each mission's first objective with its marker and radar, a hold in progress with the bar, a subtitle, the full map, a mission card, the failed-mission menu; slice 4, the gate shut, the gate open with the searchlights, a frame of the ending; slice 6, the title with the chosen key art. Prior art: the README's frame-and-quit flags, and the first Forward+ look pass on the Mac.

## Out of Scope

- A bigger city, new districts, more missions, side jobs or replaying a chosen mission.
- Leaving the car, a voiced player, people drawn in the world (Teo and Vera get in off screen), new cars, new creature kinds.
- Rebinding controls, localisation, achievements, a store page, cloud saves.
- Balancing beyond making each mission finishable; the numbers are tuned after the owner's hand play.
- New music; a studio card before the title.
- The Windows icon and version resource, and the signed Mac release (they have their own path in the README).
- Refactors not needed here, such as giving the probe the shared autopilot (worth raising later; it keeps its own copy for now).

## Further Notes

### Assumptions (each can be overturned)

1. **Missions start at a marker, except the first.** Rests on "marked on the map" and on free roam needing somewhere to go. The closing call of each mission names the next start, so no extra lines are needed.
2. **You are silent and called "Red"**, after the car. Saves credits and suits a story told by radio.
3. **Hull refills at each mission start and on Continue.** A mission's difficulty does not depend on how free roam went.
4. **Continue starts at the safe start**, the layout's own player start, where New Game begins too.
5. **The pack's size in the story comes from the story**: three in free roam, then per mission as above. Survive the Night keeps today's ramp.
6. **The gate is at the west end of the avenue**, far from the hotel, rather than the east street where police barriers already stand, so the final run crosses the quarter.
7. **Teo and Vera are never drawn**: a door slam and a line say they are in. Drawing people is out of scope.
8. **Settings are JSON like the save**, so one reader and writer serves both.
9. **About one credit per character** for `eleven_v4`, taken from the owner's other voiced work, not checked on this account's plan; the generator's credit log is the check, and the cap holds either way.
10. **The Pharmacy's neon faces the alley beside the tower**, so from the avenue the tower is found by its marker and the radar's label, not its sign.

### Open questions for the owner (recommendation first)

1. **Which option?** Recommended: this one, 01. Every slice waits on it.
2. **May slice 6 spend up to $3 on image generation with the existing Gemini key on your Mac?** Recommended: yes (about $0.34 expected). Slice 6 waits on it. If not: Workers AI on Zabaca's Cloudflare account, or the Blender render itself as the key art.
3. **May slice 5 spend up to 2,000 ElevenLabs credits** (about 1,360 for the 21 lines, under 400 for four effects, no new music)? Recommended: yes. Slice 5 waits on it.
4. **Is the story right as written** (the names Vera, Teo and Ruck, the cordon burning the quarter at first light, and the 21 lines)? Recommended: approve as written; a line changed later costs only its own characters to re-voice. Slice 5 waits on it.
5. **Keep today's round as "Survive the Night"?** Recommended: yes, shown on the title only after the story is finished, so new players meet the story first. Nothing waits on it; slice 3 adds or leaves out the entry.

---
title: The story ends at the west gate, and its city is too small for a mission to feel like a drive
description: After playing the story the owner said the checkpoints "seem like they are right next to each other". The walled quarter is 140 by 108 m, 8 seconds from wall to wall at 60 km/h; since the checkpoint spread every leg is at least 90 m, which is about 5 to 8 seconds and as far apart as the quarter allows. Asked about a bigger city, the owner chose to keep the quarter as it is and go on from it ("keep what we have but wasn't the plan to be able to escape this city and go to the next?"). Today the story ends at the gate with the credits; there is no next city, and nothing in the game is a long drive.
impact: Left alone, the game ends after three short missions in one small quarter, and the long drives the owner wants never happen. Fixing it means a chapter 2 in a second, larger city reached through the west gate. That costs agent hours and a small, capped ElevenLabs spend for chapter 2's radio lines (it needs the owner's yes). It also raises the stakes on two things nobody has measured, frame time on a weak graphics card and the download size.
severity: mid
package: repo
evidence: "The owner's words after playing the story, his yes to planning a bigger city, and then his turn to a next city instead (all relayed by the lead session on 2026-11-20). The repository read on 2026-11-20, first at commit 0198563 (the city script, the simulation's world, collisions, path grid, pack, game, missions, story data and autopilot; the map, camera, gate, city and atmosphere views; the tests' map positions; README; follow-ups; asset sizes), then at commit 99eeb89 after the checkpoint spread (the story data, the presenter's ending, the credits roll, the save store, the session, the title's Continue and Survive the Night, the credits log, every use of the city layout and model)."
intent: none (owner request)
serves_by: No intent or roadmap exists in this repository; it is the owner's own request after playing the story, and it gives the game a second chapter whose mission legs are drives of tens of seconds.
done_when: The owner plays chapter 2 and says the drives feel like drives (his hand test after chapter 2's missions merge), and the mission test reports every chapter 2 leg at least 300 m by road (about 18 seconds at 60 km/h), read from its output the day those missions merge.
status: open
---

## What exists today (read in the code, commit 99eeb89)

- **One city, the quarter.** A headless Blender script builds four hand-made blocks between three east-west streets (the middle one is the avenue) and three north-south ones, inside a 4.5 m wall (x from -70 to 70, y from -54 to 54) with the west gate's gap at the avenue's end and a ring of dark towers beyond as a skyline. It writes the city model (2.2 MB) and the layout the game reads (46 boxes, 54 posts, 13 lights, 17 wrecks, 24 creature hiding places). The game scene builds everything from that one layout and that one model; nothing loads a second map.
- **The story since the checkpoint spread** (merged as 3b07071, four lines re-voiced in 99eeb89):
  1. Batteries: from the safe start at the avenue's east end to the motel office (94 m), then to the hotel's east door (99 m).
  2. The Pharmacist: from the gas station to the pharmacy (90 m), then to the hotel (106 m).
  3. West Gate: from the park hut to the hotel (92 m), then to the west gate (131 m).
  The mission test checks every leg is at least 89 m in a straight line.
- **The ending.** Reaching the open gate rolls the car out onto the road beyond the wall; first light comes up; Vera and Ruck say their closing lines; the camera draws back; a 17-second credits roll ends on "Red got out."; the game returns to the title, where Continue reads "The end" (greyed) and Survive the Night is offered.
- **The save** holds the next mission's name, the missions done in order, whether the ending was seen, and totals; never a position. A save is valid only if its missions done are the story's first ones in order and its next mission is the one after them; anything else is set aside as damaged. So adding missions after the third would set aside every save that has finished the story (verified in the save check), unless the check learns about chapters.
- **The radio**: 21 lines by Vera, Teo and Ruck; the driver is silent and called Red. The voice spend so far: 631 credits for the 21 lines (1,361 characters with their cue words) and four effects, and about 170 more for the four re-voiced lines (the credits log).
- **The simulation looks at the whole city on every question.** Every collision, line-of-sight test, "is this creature lit" and push of a creature out of a wall loops over all the boxes, posts or lights, many times a step at 120 steps a second, and the creatures' path grid tests every 2 m cell against every box. Fine for four blocks; the cost grows with a city's size (inferred, not measured).
- **The pack does not follow the car.** A new Gaunt appears at any dark hiding place at least 60 m from the car; in a bigger city most are hundreds of metres away, so a pack of three to six would thin out (inferred from the code). A Gaunt runs at 63 to 74 km/h at most, so a car going faster on a clear road outruns them.
- **Danger sits at corners, stops and crashes.** The encounters review found that at 60 km/h on a straight the pack is near-harmless (creatures ahead are run down 83% of the time). A crash into something solid costs up to 36 hull.
- **Things tied to the one city:** the map's roads are fixed lines and its gate gap a fixed spot; the autopilot's run-down tactic uses the avenue's coordinates; about 40 placements in the tests are on the avenue; the camera's wall test loops every box each frame; the camera draws up to 600 m though the fog hides almost everything past about 95 m.
- **Survive the Night** (the old five-minute round) plays in the quarter from the layout's own start, and is offered once the story is finished.

## Known numbers

- The signed Mac build is 66 MB (the lead's figure; the README's first macOS export was also 66 MB zipped). A voiced line is about 40 to 80 KB.
- The new creature costs about 6% of frame time on an M3 Ultra (the lead's measure). Frame time on a weak graphics card has never been measured.

---
problem: the-city-is-too-small-for-a-mission-to-feel-like-a-drive
title: A new city generator with an irregular street plan (a diagonal boulevard, a river road that bends, blocks of many shapes), replacing today's grid and quarter
summary: The most city-like route. A new Blender generator lays out a street network that is not a grid (a diagonal boulevard, a river with a bending road beside it, odd-shaped blocks and plazas) about 400 by 300 m, fills it with buildings, and places the landmarks so the radio's lines stay true. The simulation learns walls at any angle, which the car's collisions (ported from Roadkill and checked against it) do not handle today. Today's quarter is replaced. About 23 to 34 agent hours with the detail pass (19 to 28 without), no money spent; the most memorable city and the biggest change to how the car feels against walls.
status: rejected
reason: "The owner chose to keep the quarter as it is and go on to a next city through the west gate (2026-11-20, relayed by the lead session); this option replaced the quarter. An irregular street plan for the next city is weighed in option 04's trade-offs."
---

> Written in the first round, for growing the quarter. Its references to option 01 are to that round's option 01, which is now a short record; the pieces this option shared with it carry over into option 04.

## Solution

- **A new generator**: a street network drawn from a few hand-set lines (the avenue, still running east to west to the west gate; a diagonal boulevard; a river with a bending road and three bridges) and a seeded fill of side streets between them, giving blocks of many shapes and sizes, small plazas at the odd junctions, and buildings fitted to each block's outline. About the same size as option 01's recommended city, with the same landmarks moved to the far corners and the pharmacy kept on the north side of the avenue, so no radio line changes.
- **Today's quarter is replaced.** Its look (materials, windows, signs, lamps, wrecks) carries over; its street plan and buildings do not.
- **Walls at any angle.** Buildings and wrecks that sit along a diagonal or a bend are angled boxes, so the car's collisions, the creatures' push out of walls, line of sight, the path grid, the camera's wall test and the map all learn angled boxes.
- **Everything on the drive, the route on the radar and the detail pass** as option 01 describes ("What happens on a longer drive", "Finding the way", "The detail pass"); not repeated here.

### Slices

| # | Slice | Agent hours | Waits on | The owner's hand test |
|---|---|---|---|---|
| 1 | The simulation for a big city with walls at any angle (option 01's slice 1, plus angled boxes everywhere) | 5 to 7 | the pick of option | crash into angled walls and judge the feel, about 10 min |
| 2 | The generator, plain | 8 to 12 | slice 1, the size | drive the city, about 20 min |
| 3 | The story's places, the tests and the autopilot moved into it | 3 to 4 | slice 2 | drive the whole story, about 30 min |
| 4 | Things on the drive (option 01's slice 3) | 3 to 5 | slice 3 | play the story again, about 30 min |
| 5 | The detail pass (optional) | 4 to 6 | the owner's yes | a look, about 10 min |

About 23 to 34 agent hours in all (19 to 28 without the detail pass).

## Trade-offs

- **The most city-like and memorable layout**: diagonals, a bending river, plazas, blocks that differ in shape as well as fill. Routes have real choices in them.
- **About 8 to 12 agent hours more than option 01.**
- **The car's feel against walls changes.** Today's collisions are a port of Roadkill's and are checked against Roadkill's own code; collisions with angled walls would be new code with nothing to check it against, so scraping along a diagonal building may feel unlike everything else until it is tuned by hand.
- **Today's quarter goes**: the streets the owner learned, the pharmacy scene tuned on today's avenue, and about 40 test placements on today's avenue and by the bus all have to be redone.
- **More ways to get stuck**: odd-shaped junctions and narrow plazas are where a car or a creature wedges, and each one is found by playing.

## Live Effects

Nothing. The game is not live: only the owner plays it. Nothing is bought. What is merged is public, because the repository is.

## User Stories

1. As a player, I want a city that does not look like a grid, so that it feels like a real place.
2. As a player, I want routes with real choices (the boulevard, the river road, the side streets), so that each drive can go a different way.
3. As a player, I want mission drives of tens of seconds, so that a mission feels like a drive.
4. As a player, I want hitting a wall to feel the same whatever angle it is at, so that the car stays predictable.
5. As a player, I want the radio's directions to stay true, so that the story still makes sense.

## Implementation Decisions

- A new generator script beside today's city script, reusing its materials and helpers; it writes the same layout records plus an angle on each box and the roads as polylines.
- The simulation's world keeps axis-aligned boxes as the common case and adds angled boxes: the car against an angled box (separating axes, the same contact rules as today's box collision), a circle out of an angled box, line of sight past one, the path grid marking its cells, the camera's wall test.
- Everything else is option 01's (the bucket world, the pack's director, ambushes as data, the map, the autopilot, the block pieces for culling).

## Testing Decisions

- Option 01's tests, plus: angled-box collisions give the same result as the axis-aligned ones when the angle is zero; a car driven into an angled wall at several speeds and angles stops, slides and is damaged like it is against a square one (recorded, compared by hand); no spot on the car's path grid is enclosed so a car can wedge there; the pack test's and mission test's placements are moved to the new city and say where.

## Out of Scope

As option 01, and: height (ramps, overpasses), curved walls (bends are made of short straight pieces).

## Further Notes

- Assumptions as option 01's, and: angled walls can reuse today's box collision with the box's own axes, which is an inference until it is built and driven.
- **Open question for the owner:** which option? Recommended: 01, not this one, for this round; an irregular plan is worth it later if the grid still feels like a grid after the detail pass.

---
problem: the-city-is-too-small-for-a-mission-to-feel-like-a-drive
title: Today's four hand-made blocks repeated, turned and mirrored across a grid about three times as wide and as tall, with new signs on the copies
summary: The cheapest bigger city. The same street grid and size as option 01 (about 400 by 300 m, 36 blocks, legs of 19 to 34 seconds at 60 km/h), but instead of a kit of new block types, today's four blocks (the towers, the gas station block, the park, the dense block) are copied across it, each copy turned or mirrored and given its own windows, roof clutter and shop signs. The landmarks, the story's places, the drive content and the simulation work are option 01's. About 13 to 19 agent hours with the detail pass (9 to 13 without), no money spent; the city repeats itself.
status: rejected
reason: "The owner chose to keep the quarter as it is and go on to a next city through the west gate (2026-11-20, relayed by the lead session); this option grew the quarter. Its idea of reusing the quarter's blocks is weighed in option 04's trade-offs."
---

> Written in the first round, for growing the quarter. Its references to option 01 are to that round's option 01, which is now a short record; the pieces this option shared with it carry over into option 04.

## Solution

- **The same city plan as option 01**: two rings of blocks round today's quarter on today's street grid, today's quarter kept where it is, the hotel, gas station and park hut moved to the far corners, the pharmacy staying, the canal and bridges, the roadblocks, the new wall and gate. Option 01's "How big", "What stays and what moves", "What happens on a longer drive", "Finding the way" and "The radio" sections hold unchanged; they are not repeated here.
- **What differs: how the 32 new blocks are filled.** Each is a copy of one of today's four blocks, turned a quarter or a half, or mirrored, with its own seed for lit windows, roof clutter and awnings, and its shop signs swapped from a list of plain words of ours. The copies of the gas station block lose their canopy and pumps (one gas station only); the park copies have no hut; the tower copies carry no PHARMACY or HOTEL sign. The landmarks are hand-made in the far corners as in option 01.
- **The detail pass**, if taken, is option 01's slice 4, applied to the four block functions, so it lands on every copy.

### Slices

| # | Slice | Agent hours | Waits on | The owner's hand test |
|---|---|---|---|---|
| 1 | The simulation ready for a big city (option 01's slice 1) | 3 to 4 | the pick of option | none |
| 2 | The bigger city of copies, plain, with the story in it | 3 to 4 | the size and the landmarks | drive the whole story, about 30 min |
| 3 | Things on the drive (option 01's slice 3) | 3 to 5 | slice 2 | play the story again, about 30 min |
| 4 | The detail pass (optional) | 4 to 6 | the owner's yes | a look, about 10 min |

About 13 to 19 agent hours in all (9 to 13 without the detail pass).

## Trade-offs

- **About 2 to 3 agent hours less than option 01**, because the block functions already exist; they only gain a position, a turn and a mirror.
- **The city repeats itself.** Nine copies of each of four blocks: the same tower shapes, the same park, the same parking lot, nine times over. A player who drives for a minute will see the same block again (an inference), which is what makes a city feel like a test level, and it makes the map harder to read from the street.
- **Turning and mirroring a hand-made block is fiddly**: its shopfronts, signs and hiding places are written for one orientation, so each needs mapping, and a copy can put a door against the wrong street.
- **Growing it later** is as cheap as option 01's.

## Live Effects

Nothing. The game is not live: only the owner plays it. Nothing is bought. What is merged is public, because the repository is.

## User Stories

1. As a player, I want mission drives of tens of seconds, so that a mission feels like a drive.
2. As a player, I want the radio's directions to stay true, so that the story still makes sense.
3. As a player, I want each landmark to exist once, so that the places the radio names are never in doubt.
4. As the owner, I want the bigger city in the fewest agent hours, so that I can play it soonest.
5. As a builder, I want the existing block functions reused, so that the city's look stays exactly today's.

## Implementation Decisions

- Today's four block functions take a block origin, a quarter-turn count, a mirror flag and a seed; their buildings, props, lights, shop faces, signs and hiding places are placed through that transform. A copy's sign comes from a list; landmark words are reserved for the landmark blocks.
- Everything else is option 01's: the block pieces for culling, the layout's new records, the bucket world, the path grid, the camera's wall test, the pack's director, ambushes as story data, the story's places, the autopilot and the map.

## Testing Decisions

- Option 01's tests, unchanged, plus: no landmark word appears on more than one block; every copy's shopfronts face a street, not a neighbour's wall.

## Out of Scope

As option 01.

## Further Notes

- Assumptions as option 01's.
- **Open question for the owner:** which option? Recommended: 01, not this one; the 2 to 3 hours saved buy a city that repeats itself, and the repetition is the thing a bigger city is most likely to be judged on.

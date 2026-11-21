---
problem: the-city-is-too-small-for-a-mission-to-feel-like-a-drive
title: Chapter 2 opens with a night run down a dead highway, about 1.2 km, into the second city
summary: Everything in option 04, plus the drive between the cities. After the card, chapter 2 opens at dusk on a highway that runs about 1.2 km into the harbour city: stalled traffic to weave through, a toll plaza, a fallen overpass with a way round through a truck stop. It is chapter 2's first mission (The Long Road), about 70 seconds at 60 km/h. The road and the city are one map, so there is still one cut at the gate. About 4 to 6 agent hours more than option 04 (23 to 32 in all, 27 to 38 with the detail pass) and about 4 more radio lines. A fast car outruns the pack on a clear road, so the road's danger comes from what is on it.
status: accepted
---

## Solution

- **Option 04 holds unchanged**: chapter 1 as it is, the card and the cut at the gate, the harbour city from the block kit, its three missions, the danger where the car slows, the route on the radar, saves and Continue, the credits after the lift bridge, Survive the Night, the detail pass. Its sections are not repeated here.
- **What it adds: the road in.** The harbour city's map gains a divided highway about 1.2 km long running into the city from the east, between concrete barriers, in fog, with a few live lamps. Chapter 2 opens on it at dusk, at the cordon's highway checkpoint, which is being overrun.
- **The Long Road** (chapter 2's first mission, before Dead Convoy): Ruck's convoy left Red, Vera and Teo at the checkpoint in the afternoon; at dusk it falls. Drive the highway into the city, where the convoy's last call came from. About four new lines.
- **The road's danger.** A Gaunt runs at 63 to 74 km/h at most, so on a clear road a fast car simply outruns the pack. The danger comes from what is on the road:
  - **Wrecks and stalled traffic in the fog.** A car at speed sees them late, and a crash costs up to 36 hull.
  - **Forced slowdowns, where the ambushes wait:** a dead traffic jam to weave through at a crawl, the toll plaza's booths a car's width apart, and the truck stop round the fallen overpass.
  - **Gaunts bursting out of stalled cars ahead,** in the headlights' path.
- **Length**: about 1.2 km, about 70 seconds at 60 km/h and 48 at 90 km/h, plus the weaving. It is the longest drive in the game.

### What it changes beyond option 04

- **Loading**: none. The road is part of the harbour city's map, so there is still one cut, at the gate, and one city in memory.
- **The map screen**: the full map frames the city, with the road shown running in from the east. Fitted whole, a map 1.6 km long would shrink the city to a strip.
- **Saves and Continue**: The Long Road is mission 4, so finishing chapter 1 saves with it next; Continue after it lands in the city as in option 04.
- **Creature behaviour**: the director's spawn-ahead and the ambushes of option 04, plus Gaunts placed in stalled cars along the road and released as the car passes.
- **Frame rate and download size**: a long straight sight line down the highway is where the camera's far plane matters most; the fog hides everything past about 95 m. The road is mostly repeated pieces (barriers, lamps, stalled cars): about 3 to 5 MB before compression (an inference), putting the Mac build near 80 to 85 MB.
- **Tests and the autopilot**: the autopilot drives the road with the pack off; the road's leg is checked at 1 km or more by road.
- **Voices**: about 28 lines in all instead of 24; about 1,100 credits expected with the effects, still under the 1,500 cap.

### Slices

Option 04's slices, with one more after its slice 2:

| # | Slice | Agent hours | Waits on | The owner's hand test |
|---|---|---|---|---|
| 2b | **The road in.** The highway, its stalled traffic, toll plaza, fallen overpass and truck stop; The Long Road as chapter 2's first mission, with subtitles; Gaunts in the stalled cars. | 4 to 6 | option 04's slice 2 | drive the road into the city, about 10 min |

About 23 to 32 agent hours for slices 1 to 5 and 2b, and 27 to 38 with the detail pass.

## Trade-offs

- **The journey is driven, not told by a card.** It is the most literal answer to "escape this city and go to the next", and the longest drive in the game.
- **A clear road is where the pack is weakest.** A fast car outruns it, so the road's danger rests on set pieces (the jam, the booths, the truck stop, the stalled cars) that each need tuning in the hand play.
- **4 to 6 agent hours more, and the city arrives one slice later.**
- **It can come later.** Built after option 04, the road slots in front of the city's east edge without undoing anything, so choosing option 04 now does not rule it out.

## Live Effects

Nothing live: only the owner plays the game. It spends up to 1,500 ElevenLabs credits on chapter 2's voices (about 1,100 expected), and only after the owner's yes on the script and the spend. What is merged is public, because the repository is.

## User Stories

1. As a player, I want to drive from the escaped quarter to the next city, so that the journey is something I do, not something I am told.
2. As a player, I want the highway to be dangerous in its own way, so that a long road is not a quiet one.
3. As a player, I want the stalled traffic and the toll plaza to slow me down where they wait, so that speed is not always the answer.
4. As a player, I want the full map to show the city clearly even with the road on it, so that the map stays useful.

## Implementation Decisions

- The harbour city's generator lays the highway along one axis into the city's east edge, between concrete barriers as long boxes (square to the map, as the collisions need), with stalled cars and trucks as wrecks, the toll booths as boxes a car's width apart, the fallen overpass as a block across the road with the truck stop beside it as the way round.
- The Long Road is mission 4 in the story data: a reach at the city's edge, with ambushes armed at the jam, the booths and the truck stop, and placed hunters released from stalled cars by distance (option 04's distance trigger).
- The full map frames the city's own rectangle and draws the road's last stretch running in.
- Everything else is option 04's.

## Testing Decisions

- Option 04's tests, plus: the road's leg is at least 1 km on the car's path grid; every stalled-car hunter is released only when the car comes within range; the autopilot drives The Long Road with the pack off within a time bound.

## Out of Scope

As option 04, and: a road driven back to the quarter, height (the overpass is a block across the road, not a bridge you drive under).

## Further Notes

- Assumptions as option 04's, and: the highway is straight or turns at right angles, because walls square to the map are what the collisions handle.
- **Open question for the owner:** which option? Recommended: 04, not this one, for this round; the road can follow it later without undoing anything, once the harbour city has been played.

- **Accepted 2026-11-21.** The owner chose this option with the highway built now, not later ("lets go but do the long highway now as well"), and took the recommendations: the chapter 2 story as sketched, the harbour city at about three times the quarter, the voice spend up to 1,500 credits, the credits after the lift bridge, the detail pass last. Option 04 is accepted with it as the part this option builds on.

---
problem: one-survival-round-with-no-story-menu-or-save
title: The same missions, menus, key art and voices as option 01, but the whole story is one night on a visible clock, and first light burns the quarter with you in it
summary: Everything in option 01 except the night. The countdown stays on screen for the whole story, about 25 minutes from New Game to first light, running in free roam and in missions alike. When it reaches zero the cordon burns the quarter and the story fails back to the last save, which keeps the clock as it was. The sky turns toward dawn with the clock, as it does in today's round. About 19 to 27 agent hours; the same voice and image budgets.
status: proposed
---

## Solution

Option 01's story, cast, three missions, title screen, menus, map, markers, key art, voices, radio, saving, checkpoints and slices all hold here. Only the night differs.

- **One clock for the whole story.** The HUD's top line keeps today's countdown, "FIRST LIGHT IN", starting at about 25:00 on New Game; the objective sits under it. The clock runs in free roam and in missions, and stops only while paused and during the ending.
- **First light is a fail, not a win.** At zero the cordon burns the quarter: a fade to orange, Ruck's line, "THE QUARTER BURNED", and back to the last save. Escaping through the west gate before zero is the ending, with dawn breaking behind you.
- **The save keeps the clock**, as it was when the mission completed. To stop a save that can never be finished, Continue never starts with less than 8 minutes on the clock.
- **Retries cost night.** Retrying from a checkpoint or restarting a mission does not wind the clock back.
- **The sky** follows the clock, as in today's round: its last stretch slides toward dawn.
- **The pack** grows with the clock as well as with the story, up to the mission's size.
- **One more line**: Ruck at zero ("[flat] First light. Burn it."), about 30 more characters, so the script is 22 lines and about 1,390 characters.

## Trade-offs

- **The dread never lets up**, and dawn means something every second, as in the game's name and today's round. That is the strongest thing about it.
- **Free roam costs night.** The owner asked for free roam between missions; a clock turns it into wasted time, so in practice players will not roam.
- **Failures stack.** A hard mission retried three times can leave too little night for the next; the 8-minute floor stops a dead save but makes the clock partly fake.
- **Harder to tune.** Three missions share one budget of time, so a change to one mission's difficulty changes whether the story can be finished at all.
- **Two timers on screen** during the timed steps (the night and the shutter or the gate).
- **Cost.** About an hour more than option 01 (the clock's save, floor, burn ending and their tests), and one more voiced line.

## User Stories

Option 01's stories 1 to 29 and 31 to 40 hold. In place of story 30:

1. As a player, I want the time to first light always on screen, so that I feel the night running out.
2. As a player, I want to know that first light means the quarter burns, so that the clock matters.
3. As a player who fails a mission several times, I want Continue to leave me enough night to finish, so that my save is never a dead end.

## Implementation Decisions

Option 01's decisions hold, with these changes:

- **Story mode keeps the dawn clock**, set from the story (about 25 minutes) rather than five minutes, and reaching it fails the story with its own reason instead of starting the dawn rules. Survive the Night keeps five minutes and today's dawn.
- **The save stores the clock**; loading applies the 8-minute floor.
- **The pack's size** is the larger of the story's size for the step and a ramp on the clock.
- **The ending** happens only before zero; the drive out still ends in first light.

## Testing Decisions

Option 01's tests hold, plus: the clock runs in free roam and in missions and stops while paused; reaching zero fails the story with the burn reason and returns to the last save; the save keeps the clock and Continue applies the floor; a retry does not wind the clock back; the story driven by the autopilot with the pack off finishes with time left.

## Out of Scope

As in option 01.

## Further Notes

- **Assumption: about 25 minutes.** Three missions of two to four minutes each plus driving between them and a few retries; tuned by hand later.
- **Open question for the owner:** none beyond option 01's, apart from which option. Recommended: option 01, because the owner asked for free roam between missions and a story-wide clock works against it.

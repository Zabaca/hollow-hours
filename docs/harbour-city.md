# The harbour city: generator, layout and checks

Chapter 2's map, built in slices 2 and 2b of `docs/problems/the-city-is-too-small-for-a-mission-to-feel-like-a-drive/` (options 04 and 05). One map: a walled city of 6 x 6 blocks (about 400 x 300 m) with a river and a lift bridge in the west, and a divided highway 1.2 km long running into it from the east. Plain by design: the detail pass is a later slice and lands in the kit (below).

## Files

| File | What it is |
| --- | --- |
| `tools/blender/harbour_plan.py` | the plan as plain data: the size, the kit per district, the places, the planned legs, the roadblocks, the highway's features |
| `tools/blender/blockkit.py` | the block kit: what goes inside one block (13 kits), plus the buildings, props, fences and low-polygon vehicles they are made of |
| `tools/blender/harbour.py` | the generator: roads, blocks, roadblocks, river and bridges, highway, checkpoint, gate, ground and skyline; writes the two files below |
| `tools/blender/harbour_check.py` | the checks on the layout, plain Python 3 (no Blender, no Godot) |
| `assets/cities/harbour_city.glb` | the model: one mesh per block (with its sidewalk and its stretch of road), one per 100 m of highway, the river, the world |
| `assets/cities/harbour_layout.gd` | the layout, `HarbourLayout.DATA`, in the shape of `CityLayout.DATA` plus the extra keys below |

Run both from the repository root. The generator is headless Blender and takes about two seconds:

```
/Applications/Blender.app/Contents/MacOS/Blender -b --python-exit-code 1 --python tools/blender/harbour.py -- [preview <dir>] [nolayout] [noglb]
python3 -I tools/blender/harbour_check.py
```

`preview <dir>` renders top-down and street-level stills (a dark, foggy, one-warm-light one and a lighter one beside it) into `<dir>`, which should be outside the repository. The layout is byte-identical from run to run; the glb has the same structure but its buffer varies by a few hundred bytes (the exporter's vertex merge), so do not diff it.

## The size is one setting

`harbour_plan.py`: `BLOCKS_X`, `BLOCKS_Y` (6 and 6), `STREET_X` and `STREET_Y` (64 and 48 m between road centre lines, as the quarter's), `RW` (14 m roads), `HIGHWAY_LEN` (1200 m), `SQUEEZE_GAP` (4 m). A larger city is those numbers plus the places and roadblocks moved out; `harbour_check.py` then says which legs fell out of range.

## Layout data

The shape is the one documented at the top of `scripts/sim/sim_world.gd` (arena, boxes, posts, blocks, roads, lights, lamps,
wrecks, creature_spawns, fires, player_start, gate); `LayoutCheck.problems` is empty for it (`tests/harbour_test.gd`). `arena`
is ONE rectangle, x -199 to 1410 and y -151 to 151: the city in the west and the highway running out of its east side; the
unused part beside the highway is solid colliders (`building`). Everything else is extra and read by the game or the checks:

- `blocks[]` gain `i`, `j`, `kit`, `district`. `wrecks[].kind` gains `truck`.
- `lights[]` may carry `tag`: `hospital_flood` (the four floodlights at the field hospital), `checkpoint` (the highway checkpoint's
  three), `generator_<post>`.
- `gate` is the lift bridge's far end: `{x -199, y -144, width 8, dx, dy, bridge}`, a gap in the west perimeter at the south ring road.
- `roads[]`: `{axis, c, width, from, to, kind}`, `axis` the direction the road runs along (`x` is east-west at y = c). Kinds
  `ring`, `street`, `highway` (two roads, one per 14 m carriageway).
- `roadblocks[]`: `{id, axis, c, pos, kind: squeeze|closed, gap: {lo, hi, width}|null, corridor}`, same axis convention. A
  roadblock spans kerb to kerb including both sidewalks (20 m), so it cannot be driven round.
- `bridges[]`: `{id, kind: fixed|lift, x, y, length, width, up?, closers?}`; the lift bridge's `closers` are the two collider
  rectangles (kind `fence`, also in `boxes`) that shut its road while it is raised: remove them when it comes down.
  `river`: `{x0, x1, y0, y1}`.
- `places{}`: `{x, y, r}` for `highway_start`, `convoy_call`, `ruck_truck`, `field_hospital`, `fuel_depot`, `post_north`,
  `post_centre_west`, `post_east`, `control_house`; `planned_legs[]` names the legs the missions drive and the least by road each
  may be. (`StoryData.PLACES` holds the places chapter 2's first mission uses, at the same coordinates where they overlap.)
- `ambush_spots[]`: `{id, x, y, count, near}`, one by every roadblock, one at each fixed bridge's east end and three on the highway's set
  pieces. A mission's `ambush` effect arms the ones beside a leg's route (`GameSim.ambushes_on`); free roam arms a few at random
  (`StoryData.AMBUSH_ROAM`); `count` is `AMBUSH_COUNT` in the plan (2).
  `stalled_hunters[]`: `{x, y, release}`, creatures waiting in stalled cars on the highway, placed hunting when the car comes
  within `release` metres (the mission's `stalled` effect arms them; `HUNTER_SPACING`, `HUNTER_RELEASE` in the plan).
- `generators[]`: `{post, x, y}`. `highway{}`: `toll_plaza`, `jam`, `fallen_overpass`, `truck_stop` (with its `squeeze` and
  `wide_gap`), `checkpoint`. `map_frame`: the part of the map the full map screen shows (the city and 150 m of highway).
  `size{}`: the setting above, as built.

## What the checker measures

Roads are at least 14 m wide, the quarter's (the highway is 14 m a carriageway). Every squeeze (the roadblocks' gaps, the toll lanes, the checkpoint's chicanes, the truck stop's way round) is 4 m, the quarter's burned-bus chicane, and the car's 2.2 m circle passes it. Each leg is the shortest route on a 1 m grid with that clearance, pulled straight, and every one is within its option's range and crosses a roadblock or a bridge. With the lift bridge up the gate cannot be reached; with it down the only way to the gate from the west bank is over it.

## Where the detail pass lands

Facades are drawn in one place, `blockkit.bldg` (with `window_band` and `bldg_roof`); props in `crate`, `container`, `fence` and `wreck_lp`; every block's ground in `harbour.cell_road` and `city.block_ground`. A texture, bevel or prop pass changes those and regenerates every block once.

## The closures are one setting

`CLOSED_ROADBLOCKS` in `harbour_plan.py` (`-- open` on the generator's command line tries it): True keeps the ten `closed`
roadblocks shut, so the routes wind round them; False loosens each into a 4 m squeeze at the middle of its road. Legs by
road, closed against loosened: convoy_call to ruck_truck 447 against 428 m; ruck_truck to field_hospital 502 against 486;
field_hospital to fuel_depot 524 against 360; fuel_depot to post_north 463 against 434; post_north to post_centre_west 370
against 369; post_centre_west to post_east 412 against 367; field_hospital to control_house 522 against 326 (under the 450 the
option wants). So loosening them keeps every leg over 300 m except the run to the lift bridge. The kits are cul-de-sacs
whichever way this is set.

## Things the next slices should know

- Every block is a solid building or a cul-de-sac (one gate, no way through), so the only routes are the roads. A new kit must keep
  that, or `harbour_check.py` will show the legs shrink.
- The checkpoint's chicane gaps are 7 m and the city's squeezes 4 m. The pack's own 2 m grid can lose a 4 m gap (it blocks a
  cell within about 1.55 m of a box); the car's grid for the harbour city is 1 m cells with a halo that keeps routes to the middle
  of a gap (`Autopilot.HINTS["harbour"]`), which sees every 4 m gap. The autopilot also slows to 11 m/s where a wall is within
  2.4 m of its way (`tight`), and follows its route when no point of it has a clear line, as a driver would.
- The highway's north carriageway (y 1 to 15) carries traffic west, the player's way in; the south one (y -15 to -1) carries it east.
  The median barrier has crossovers at the toll plaza, the overpass, the jam and 150 m out of the city. The creatures in stalled
  cars are kept out of the set pieces (the jam, the toll plaza, the overpass and truck stop), where the obstacles are the danger.

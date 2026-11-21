# The harbour city: generator, layout and checks

Chapter 2's map, built in the first half of slice 2 of `docs/problems/the-city-is-too-small-for-a-mission-to-feel-like-a-drive/` (options 04 and 05). One map: a walled city of 6 x 6 blocks (about 400 x 300 m) with a river and a lift bridge in the west, and a divided highway 1.2 km long running into it from the east. Plain by design: the detail pass is a later slice and lands in the kit (below).

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

Every key `city.py` writes is here with the same meaning (`arena`, `boxes`, `posts`, `lamps`, `lights`, `wrecks`, `blocks`, `creature_spawns`, `fires`, `player_start`, `gate`). `arena` is one rectangle: x -199 to 1410, y -151 to 151; the highway's two sides are solid colliders (`building`), so the rectangle's unused part cannot be reached. Added:

- `blocks[]` gain `i`, `j`, `kit`, `district`.
- `wrecks[].kind` gains `truck`. Box kinds gain `lift_up` (the two colliders that close the lift bridge's road while it is raised: remove them to let the car over) beside `building`, `wreck`, `prop`, `fence`.
- `lights[]` may carry `tag`: `hospital_flood` (the four floodlights at the field hospital, for the floodlights failing) and `checkpoint` (the highway checkpoint's three).
- `gate` is the lift bridge's far end: `{x, y, width, dx, dy, bridge}`, a gap in the west perimeter at the south ring road, direction west.
- `roads[]`: `{axis, at, a, b, kind, width}`; `axis` `y` is east-west at y = `at`. Kinds: `ring`, `street`, `highway` (carriageway width in `carriageway_width`).
- `roadblocks[]`: `{id, axis, at, pos, kind: squeeze|closed, gap: {lo, hi, width}|null, corridor}`. A roadblock spans kerb to kerb including both sidewalks (20 m), so it cannot be driven round.
- `bridges[]`: `{id, kind: fixed|lift, x, y, length, width, up?, closed_by?}`; `river`: `{x0, x1, y0, y1}`.
- `places{}`: `{x, y, r}` for `highway_start`, `convoy_call`, `ruck_truck`, `field_hospital`, `fuel_depot`, `post_north`, `post_centre_west`, `post_east`, `control_house`. `planned_legs[]` names the legs the missions drive and the least by road each may be.
- `ambush_spots[]`: `{id, x, y, count, near}`, one by every roadblock and the highway's set pieces. `stalled_hunters[]`: `{x, y, release}`, stalled cars on the highway to burst out of at `release` metres.
- `highway{}`: `toll_plaza`, `jam`, `fallen_overpass`, `truck_stop` (with its `squeeze` and `wide_gap`), `checkpoint`.
- `size{}`: the setting above, as built.

## What the checker measures

Roads are at least 14 m wide, the quarter's (the highway is 14 m a carriageway). Every squeeze (the roadblocks' gaps, the toll lanes, the checkpoint's chicanes, the truck stop's way round) is 4 m, the quarter's burned-bus chicane, and the car's 2.2 m circle passes it. Each leg is the shortest route on a 1 m grid with that clearance, pulled straight, and every one is within its option's range and crosses a roadblock or a bridge. With the lift bridge up the gate cannot be reached; with it down the only way to the gate from the west bank is over it.

## Where the detail pass lands

Facades are drawn in one place, `blockkit.bldg` (with `window_band` and `bldg_roof`); props in `crate`, `container`, `fence` and `wreck_lp`; every block's ground in `harbour.cell_road` and `city.block_ground`. A texture, bevel or prop pass changes those and regenerates every block once.

## Things the next half should know

- Every block is a solid building or a cul-de-sac (one gate, no way through), so the only routes are the roads and the closed roadblocks cannot be bypassed. A new kit must keep that, or `harbour_check.py` will show the legs shrink.
- The nav grid (2 m cells, 0.75 m clearance) can lose a 4 m gap: it blocks a cell within about 1.55 m of a box, so a gap under 5.1 m may show no free cell. Chapter 1's chicane has the same 4 m. If the autopilot cannot route a squeeze, grow `SQUEEZE_GAP` or change the grid's clearance there.
- The highway's north carriageway (y 1 to 15) carries traffic west, the player's way in; the south one (y -15 to -1) carries it east. The median barrier has crossovers at the toll plaza, the overpass, the jam and 150 m out of the city.

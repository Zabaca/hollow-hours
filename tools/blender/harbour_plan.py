"""The harbour city's plan as plain data: no Blender in here, so the generator (harbour.py) and the
checker (harbour_check.py) read the same numbers.

Coordinates are map metres, as in city.py: x east, y north. The city is a street grid like the
quarter's (roads every 64 m east-west of each other, every 48 m north-south, 14 m wide, blocks 50 x 34
between them), BLOCKS_X by BLOCKS_Y blocks; the size is these two numbers and the highway's length.
A river runs north to south through the west and meets the harbour at the south edge; a divided
highway runs out of the east side for HIGHWAY_LEN metres to the cordon's checkpoint.
"""

# ---------------------------------------------------------------- the size (one setting)

BLOCKS_X = 6          # 6 x 6 = 36 blocks, about 400 x 300 m
BLOCKS_Y = 6
STREET_X = 64.0       # distance between the north-south roads' centre lines
STREET_Y = 48.0       # distance between the east-west roads' centre lines
RW = 14.0             # road width, the quarter's
SW = 3.0              # sidewalk strip round every block
HIGHWAY_LEN = 1200.0  # from the city's east edge to the checkpoint's far end
SQUEEZE_GAP = 4.0     # the narrowest gap a roadblock leaves; the quarter's burned-bus chicane is 4 m

# ---------------------------------------------------------------- derived grid

XS = [round((i - BLOCKS_X / 2) * STREET_X, 3) for i in range(BLOCKS_X + 1)]   # north-south road centre lines
YS = [round((j - BLOCKS_Y / 2) * STREET_Y, 3) for j in range(BLOCKS_Y + 1)]   # east-west road centre lines
CITY_LEFT, CITY_RIGHT = XS[0] - RW / 2, XS[-1] + RW / 2
CITY_BOTTOM, CITY_TOP = YS[0] - RW / 2, YS[-1] + RW / 2
HIGHWAY_Y = 0.0                       # the median's centre line: the avenue's line
HW_HALF = 15.0                        # corridor half width: 1 m median half + a 14 m carriageway each way
HW_X0 = CITY_RIGHT
HW_X1 = CITY_RIGHT + HIGHWAY_LEN
ARENA = dict(left=CITY_LEFT, right=HW_X1 + 11.0, bottom=CITY_BOTTOM, top=CITY_TOP)

# The river: a north-south channel in the place of the road at XS[1], 20 m across, quay walls at both banks.
RIVER_COL = 1
RIVER_X0 = XS[RIVER_COL] - 10.0
RIVER_X1 = XS[RIVER_COL] + 10.0
# Fixed bridges carry three of the east-west roads over it; the lift bridge carries the south ring road.
BRIDGE_ROWS = [1, 3, 5]               # indices into YS: y = -96, 0, 96 (the middle one is the avenue)
LIFT_ROW = 0                          # y = -144, the south ring road, at the harbour mouth


def block_rect(i, j):
    """The block's sidewalk slab (x0, y0, x1, y1): the road's edge to the next road's edge, the river's quay for the two blocks beside it."""
    x0 = XS[i] + RW / 2
    x1 = XS[i + 1] - RW / 2
    if i == RIVER_COL - 1:
        x1 = RIVER_X0
    if i == RIVER_COL:
        x0 = RIVER_X1
    return (x0, YS[j] + RW / 2, x1, YS[j + 1] - RW / 2)


# ---------------------------------------------------------------- the kit per district

# Which kit fills each block. A pinned block is named; every other block draws from its district's list
# (seeded, so a regeneration is the same city). Kits live in blockkit.py.
PINNED = {
    (5, 1): "school",          # the field hospital
    (0, 1): "fuel_depot",      # the fuel depot, south-west docks on the west bank
    (1, 0): "lift_yard",       # the lift bridge's control house, east bank
    (0, 0): "sealed_warehouse",  # shuts the far-bank pocket (the south-west corner) from the north
}
DISTRICT_KITS = {
    "docks": ["container_yard", "container_yard", "warehouse_yard", "dock_crane"],
    "industry": ["warehouse_yard", "warehouse_yard", "lot", "container_yard"],
    "old_town": ["brick_row", "brick_row", "brick_row", "lot", "houses"],
    "centre": ["towers", "towers", "towers", "parking", "brick_row"],
    "residential": ["houses", "houses", "lot", "park", "brick_row"],
}


def district_of(i, j):
    if j == 0:
        return "docks"
    if i == 0:
        return "industry" if j <= 2 else "residential"
    if j >= 4:
        return "old_town"
    if i in (2, 3, 4) and j in (2, 3):
        return "centre"
    return "residential"


# ---------------------------------------------------------------- roads that are not the grid's

# Roads absent from the grid: the river's column has no street, and the outer ring roads exist only
# where there is city (the ring road is the outer street of the grid on every side).
def road_lines():
    """Every road as {axis, at, a, b, kind}: `axis` 'y' is an east-west road at y=at running x from a to b."""
    roads = []
    for j, y in enumerate(YS):
        kind = "ring" if j in (0, len(YS) - 1) else "street"
        # an east-west road runs the whole city; the river and its bridges cut it into two stretches
        roads.append(dict(axis="y", at=y, a=XS[0], b=XS[-1], kind=kind, width=RW))
    for i, x in enumerate(XS):
        if i == RIVER_COL:
            continue
        kind = "ring" if i in (0, len(XS) - 1) else "street"
        roads.append(dict(axis="x", at=x, a=YS[0], b=YS[-1], kind=kind, width=RW))
    return roads


# ---------------------------------------------------------------- places (the story's, chapter 2)

# Road-side points the missions reach. `r` is the reach radius the story would use. These are plan
# numbers: harbour_check.py measures the legs between them by road and says if one is off its range.
PLACES = {
    "highway_start": dict(x=HW_X1 - 25.0, y=8.0, r=10.0),       # the cordon's highway checkpoint, where chapter 2 opens
    "convoy_call": dict(x=CITY_RIGHT - 28.0, y=-3.5, r=12.0),   # where the convoy's last call came from, inside the east edge
    "ruck_truck": dict(x=XS[0] + 12.0, y=YS[-1] - 4.0, r=10.0),  # on the north ring road, far north-west
    "field_hospital": dict(x=XS[6] - 2.0, y=YS[1] + 4.5, r=12.0),  # the school, south-east
    "fuel_depot": dict(x=XS[0] + 22.0, y=YS[1] + 3.5, r=10.0),   # the depot's gate, south-west docks, west bank
    "post_north": dict(x=XS[5] + 20.0, y=YS[-1] - 3.5, r=9.0),         # generator post on the north ring road
    "post_centre_west": dict(x=XS[0] + 32.0, y=YS[3] + 3.5, r=9.0),  # generator post on the avenue, west bank
    "post_east": dict(x=XS[-1] - 3.5, y=YS[2], r=9.0),          # generator post on the east ring road
    "control_house": dict(x=RIVER_X1 + 6.0, y=YS[0] + 3.5, r=10.0),  # the lift bridge's control house, east bank
}

# The gate: the lift bridge's far bank. The exit is a gap in the west perimeter at the south ring road,
# where the road runs out of the city beyond the bridge.
GATE = dict(x=CITY_LEFT, y=YS[0], width=8.0)

# The legs the missions drive, in order. `min` is the least the option allows by road, in metres.
LEGS = [
    ("long_road", "highway_start", "convoy_call", 1000.0),
    ("dead_convoy_out", "convoy_call", "ruck_truck", 300.0),
    ("dead_convoy_back", "ruck_truck", "field_hospital", 300.0),
    ("floodlights_pickup", "field_hospital", "fuel_depot", 300.0),
    ("floodlights_1", "fuel_depot", "post_north", 300.0),
    ("floodlights_2", "post_north", "post_centre_west", 300.0),
    ("floodlights_3", "post_centre_west", "post_east", 300.0),
    ("lift_bridge_run", "field_hospital", "control_house", 450.0),
]

# ---------------------------------------------------------------- roadblocks

# kind 'squeeze': a barricade that leaves a SQUEEZE_GAP gap; 'closed': it shuts the road, so the
# route turns into a side street. `at` is the road's centre line coordinate and `pos` the point along
# it; `axis` 'y' means the road runs east-west (y = at). `gap_side` is where the gap sits across the
# road, as an offset from the centre line.
ROADBLOCKS = [
    # ring roads and main streets, spread so every leg meets one
    dict(id="rb_south_ring_east", axis="y", at=YS[0], pos=100.0, kind="closed"),
    dict(id="rb_south_ring_mid", axis="y", at=YS[0], pos=-32.0, kind="closed"),
    dict(id="rb_street_south_east", axis="y", at=YS[1], pos=96.0, kind="squeeze", gap_side=2.0),
    dict(id="rb_street_south_mid", axis="y", at=YS[1], pos=-32.0, kind="closed"),
    dict(id="rb_street_mid_south", axis="y", at=YS[2], pos=-32.0, kind="closed"),
    dict(id="rb_avenue_east", axis="y", at=YS[3], pos=96.0, kind="squeeze", gap_side=-2.5),
    dict(id="rb_avenue_mid", axis="y", at=YS[3], pos=-32.0, kind="closed"),
    dict(id="rb_street_mid_north", axis="y", at=YS[4], pos=-32.0, kind="squeeze", gap_side=-2.5),
    dict(id="rb_avenue_west", axis="y", at=YS[3], pos=-98.0, kind="squeeze", gap_side=2.5),
    dict(id="rb_street_north_east", axis="y", at=YS[5], pos=96.0, kind="squeeze", gap_side=3.0),
    dict(id="rb_street_north_west", axis="y", at=YS[5], pos=-96.0, kind="closed"),
    dict(id="rb_north_ring_west", axis="y", at=YS[6], pos=-96.0, kind="squeeze", gap_side=-3.0),
    dict(id="rb_north_ring_east", axis="y", at=YS[6], pos=100.0, kind="squeeze", gap_side=2.0),
    dict(id="rb_east_ring_north", axis="x", at=XS[6], pos=72.0, kind="squeeze", gap_side=-2.0),
    dict(id="rb_east_ring_south", axis="x", at=XS[6], pos=-72.0, kind="closed"),
    dict(id="rb_west_ring_north", axis="x", at=XS[0], pos=72.0, kind="squeeze", gap_side=2.5),
    dict(id="rb_west_ring_south", axis="x", at=XS[0], pos=-130.0, kind="closed"),   # shuts the far-bank pocket from the north
    dict(id="rb_road_east_mid", axis="x", at=XS[5], pos=24.0, kind="squeeze", gap_side=-2.0),
    dict(id="rb_road_centre", axis="x", at=XS[3], pos=-24.0, kind="squeeze", gap_side=2.5),
    dict(id="rb_road_centre_north", axis="x", at=XS[3], pos=72.0, kind="closed"),
    dict(id="rb_road_centre_south", axis="x", at=XS[3], pos=-120.0, kind="closed"),
    dict(id="rb_road_west", axis="x", at=XS[2], pos=24.0, kind="squeeze", gap_side=-2.0),
    dict(id="rb_road_west_south", axis="x", at=XS[2], pos=-72.0, kind="squeeze", gap_side=2.0),
    dict(id="rb_road_east_south", axis="x", at=XS[4], pos=-72.0, kind="squeeze", gap_side=2.0),
]

# Ambush spots: a place and a count, beside the squeezes and the highway's set pieces (ambushes.id
# matches the roadblock or feature it hides beside; harbour.py adds the highway's).
AMBUSH_COUNT = 3

# Lamps: about one in five lives, gathered at these junctions (index pairs into XS, YS).
LIT_JUNCTIONS = [(3, 3), (5, 1), (2, 5), (4, 0), (1, 3), (5, 5), (0, 2), (3, 1)]

# The highway's features, x positions along it (the city is at the left, the checkpoint at the right).
HW = dict(
    toll_x0=HW_X1 - 170.0, toll_x1=HW_X1 - 140.0,
    jam_x0=HW_X1 - 330.0, jam_x1=HW_X1 - 215.0,
    overpass_x=HW_X0 + 500.0,
    truck_stop_x0=HW_X0 + 410.0, truck_stop_x1=HW_X0 + 600.0,
    truck_stop_depth=62.0,
    checkpoint_x0=HW_X1 - 85.0,
)

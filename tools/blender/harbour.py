"""The harbour city of Hollow Hours (chapter 2): a walled city of 6 x 6 blocks built from a kit, a river with
bridges and a lift bridge, and a divided highway 1.2 km long running into it from the east, all one map.

Built straight in game coordinates, as city.py does (x, y map metres, Blender Z up; glTF turns y into
Godot -Z). Writes:
  assets/cities/harbour_city.glb       one mesh per block (with its sidewalk and its stretch of road), per river
                                       part and per 100 m of highway, flat-colour materials with city.py's names
  assets/cities/harbour_layout.gd      the layout, in the shape city.py writes (arena, boxes, posts, lamps, lights,
                                       wrecks, blocks, creature_spawns, fires, player_start, gate) plus the roads,
                                       roadblocks, bridges, places, ambush spots and the highway's features
The plan's numbers (size, places, roadblocks, kit per district) are in harbour_plan.py; the kit's
buildings and props are in blockkit.py. Run (headless, foreground, repeatable):
  Blender --background --python-exit-code 1 --python tools/blender/harbour.py -- [preview <dir>] [nolayout] [noglb]
"""
import sys, os, math, json, random
HERE_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE_DIR)
import bpy
import city as C
import harbour_plan as P
import blockkit as K
from rk import mat, reset, join, export
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if "open" in ARGS:
    P.CLOSED_ROADBLOCKS = False  # a trial: every closed roadblock loosened into a squeeze (see harbour_plan.py)
ROOT = os.path.abspath(os.path.join(HERE_DIR, "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "cities")
R = C.RNG
STATS = dict(wrecks_hw=0)


def define_extra_materials():
    d = C.MATS
    for i, c in enumerate(["#6a2a20", "#244650", "#7a6420", "#3a4a34"]):
        d["container%d" % i] = mat("container%d" % i, c, rough=0.7, metal=0.3)
    d["sandbag"] = mat("sandbag", "#4a4332", rough=0.95)
    d["canvas"] = mat("canvas", "#3a3d30", rough=0.9)
    d["sea"] = mat("sea", "#070e12", rough=0.05, metal=0.3)


# ---------------------------------------------------------------- helpers

def cell_of(x, y):
    i = min(max(sum(1 for v in P.XS[1:-1] if x >= v), 0), P.BLOCKS_X - 1)
    j = min(max(sum(1 for v in P.YS[1:-1] if y >= v), 0), P.BLOCKS_Y - 1)
    return i, j


def cell_group(x, y):
    i, j = cell_of(x, y)
    return "blk_%d_%d" % (i, j)


def hw_group(x):
    return "hw_%02d" % int((x - P.HW_X0) // 100.0)


def tilted_box(g, m, cx, cy, cz, sx, sy, sz, rx=0.0, ry=0.0, rz=0.0):
    v, f = K._cube(-sx / 2, -sy / 2, -sz / 2, sx / 2, sy / 2, sz / 2)
    mx = Matrix.Translation((cx, cy, cz)) @ Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X")
    C.add_mesh(g, m, v, f, mx)


def fill_stretch(g, axis, lo, hi, along, kind_pool=("sedan", "van", "sedan"), truck_ok=True, centre_line=None):
    """Fill [lo, hi] across a road with vehicles and barriers so nothing can pass. `axis` 'y' means the road
    runs east-west, the stretch is measured in y at x = along; 'x' the other way. Vehicles lie across the road."""
    t = lo
    first = True
    while hi - t > 0.05:
        r = hi - t
        if truck_ok and first and r >= 15.2 and R.random() < 0.7:
            kind, L = "truck", 15.0
        elif r >= 4.8:
            kind = R.choice(kind_pool)
            L = K.CAR_SIZE[kind][0]
            if kind == "van" and r < 4.8:
                kind, L = "sedan", 4.0
        elif r >= 4.0:
            kind, L = "sedan", 4.0
        else:
            kind = None
        if kind is None:
            # a concrete barrier closes the last bit
            if axis == "y":
                C.box(g, "concrete", along - 0.3, t, 0.0, along + 0.3, hi, 0.9)
                C.collider(along - 0.3, t, along + 0.3, hi, "prop")
            else:
                C.box(g, "concrete", t, along - 0.3, 0.0, hi, along + 0.3, 0.9)
                C.collider(t, along - 0.3, hi, along + 0.3, "prop")
            break
        first = False
        c = t + L / 2
        # vehicles lie across the road: heading along the stretch's axis
        if axis == "y":
            K.wreck_lp(g, along, c, math.pi / 2, kind, burnt=R.random() < 0.35)
        else:
            K.wreck_lp(g, c, along, 0.0, kind, burnt=R.random() < 0.35)
        t += L


# ---------------------------------------------------------------- streets: specs first, built with the block they fall in

def road_runs():
    """The east-west and north-south roads as drivable stretches, river and gaps taken out."""
    return P.road_lines()


def plan_street_objects():
    """Lamps, wrecks and roadblocks as specs by cell, drawn from a stream of their own so the kit's random numbers are not disturbed."""
    rng = random.Random(7)
    spec = {}
    # lit junctions
    lit = [(P.XS[a], P.YS[b]) for (a, b) in P.LIT_JUNCTIONS]

    def is_live(x, y):
        if any(abs(x - jx) < 24 and abs(y - jy) < 24 for jx, jy in lit):
            return True
        return rng.random() < 0.03

    def jn_dist_x(x):
        return min(abs(x - v) for v in P.XS)

    def jn_dist_y(y):
        return min(abs(y - v) for v in P.YS)

    n = 0
    # lamps
    for b, y in enumerate(P.YS):
        for sgn in (-1, 1):
            x = P.XS[0] + 14.0
            while x < P.XS[-1] - 10:
                px, py = x, y + sgn * (P.RW / 2 + 1.0)
                skip = jn_dist_x(x) < P.RW / 2 + 3.0 or P.RIVER_X0 - 6 < px < P.RIVER_X1 + 6 or abs(py) > P.ARENA["top"] - 3
                if not skip:
                    spec.setdefault(cell_group(px, py), []).append(("lamp", px, py, (0, -sgn), is_live(px, py), 0.45 if n % 2 else 0.0))
                    n += 1
                x += 32.0
    for a, x in enumerate(P.XS):
        if a == P.RIVER_COL:
            continue
        for sgn in (-1, 1):
            y = P.YS[0] + 14.0
            while y < P.YS[-1] - 10:
                px, py = x + sgn * (P.RW / 2 + 1.0), y
                skip = jn_dist_y(y) < P.RW / 2 + 3.0 or abs(px) > P.ARENA["right"] - 3
                if not skip and px > P.CITY_LEFT + 3 and px < P.CITY_RIGHT - 3:
                    spec.setdefault(cell_group(px, py), []).append(("lamp", px, py, (-sgn, 0), is_live(px, py), 0.45 if n % 2 else 0.0))
                    n += 1
                y += 32.0
    # roadblock spots, to keep wrecks away from them
    rbs = [(p["x"], p["y"]) for p in P.PLACES.values()]   # keep wrecks off the story's places too
    for rb in P.ROADBLOCKS:
        if rb["axis"] == "y":
            rbs.append((rb["pos"], rb["at"]))
        else:
            rbs.append((rb["at"], rb["pos"]))
    # stray wrecks in the lanes
    last = {}
    for b, y in enumerate(P.YS):
        x = P.XS[0] + 20.0
        while x < P.XS[-1] - 15:
            x += rng.uniform(30, 55)
            if x > P.XS[-1] - 15 or jn_dist_x(x) < P.RW / 2 + 7 or P.RIVER_X0 - 8 < x < P.RIVER_X1 + 8:
                continue
            lane = rng.choice((-3.6, 3.6))
            if any(abs(x - rx) < 14 and abs(y - ry) < 14 for rx, ry in rbs):
                continue
            kind = rng.choice(["sedan", "sedan", "van"])
            spec.setdefault(cell_group(x, y + lane), []).append(("wreck", x, y + lane, rng.choice((0.0, math.pi)), kind, rng.random() < 0.35, rng.random() < 0.12))
    for a, x in enumerate(P.XS):
        if a == P.RIVER_COL:
            continue
        y = P.YS[0] + 20.0
        while y < P.YS[-1] - 15:
            y += rng.uniform(30, 55)
            if y > P.YS[-1] - 15 or jn_dist_y(y) < P.RW / 2 + 7:
                continue
            lane = rng.choice((-3.6, 3.6))
            if any(abs(x + lane - rx) < 14 and abs(y - ry) < 14 for rx, ry in rbs):
                continue
            kind = rng.choice(["sedan", "sedan", "van"])
            spec.setdefault(cell_group(x + lane, y), []).append(("wreck", x + lane, y, rng.choice((math.pi / 2, 1.5 * math.pi)), kind, rng.random() < 0.35, rng.random() < 0.12))
    return spec


def build_roadblock(rb):
    """A roadblock across a road, from kerb to kerb (the road plus both sidewalks, 20 m), leaving a gap or none."""
    axis, at, pos = rb["axis"], rb["at"], rb["pos"]
    if rb["kind"] == "closed" and not P.CLOSED_ROADBLOCKS:
        rb = dict(rb, kind="squeeze", gap_side=0.0)
    lo, hi = at - (P.RW / 2 + P.SW), at + (P.RW / 2 + P.SW)
    if axis == "y":
        lo, hi = max(lo, P.ARENA["bottom"]), min(hi, P.ARENA["top"])
        gx, gy = pos, at
    else:
        lo, hi = max(lo, P.ARENA["left"]), min(hi, P.ARENA["right"])
        gx, gy = at, pos
    g = cell_group(gx, gy)
    if rb["kind"] == "closed":
        fill_stretch(g, axis, lo, hi, pos)
        gap = None
    else:
        c = at + rb["gap_side"]
        g0, g1 = c - P.SQUEEZE_GAP / 2, c + P.SQUEEZE_GAP / 2
        if g0 < lo + 0.5:
            g0, g1 = lo + 0.5, lo + 0.5 + P.SQUEEZE_GAP
        if g1 > hi - 0.5:
            g1, g0 = hi - 0.5, hi - 0.5 - P.SQUEEZE_GAP
        fill_stretch(g, axis, lo, g0, pos)
        fill_stretch(g, axis, g1, hi, pos, truck_ok=False)
        gap = (g0, g1)
    # a burning barrel and tape beside it, on the sidewalk side
    bx, by = (pos + 3.5, at + 11.0) if axis == "y" else (at + 11.0, pos + 3.5)
    if (axis == "y" and P.ARENA["bottom"] + 4 < by < P.ARENA["top"] - 4) or (axis == "x" and P.ARENA["left"] + 4 < bx < P.ARENA["right"] - 4):
        C.barrel(g, bx, by, fire=True)
    # `axis` is the direction the road runs along, as in roads[]: "x" for an east-west road, whose centre line is y = c
    rec = dict(id=rb["id"], axis="x" if axis == "y" else "y", c=at, pos=pos, kind=rb["kind"], gap=None, corridor=[round(lo, 2), round(hi, 2)])
    if gap:
        rec["gap"] = dict(lo=round(gap[0], 2), hi=round(gap[1], 2), width=round(gap[1] - gap[0], 2))
    # the ambush: two or three creatures wait in the dark beside the barricade, 8 m up the road on the sidewalk strip
    off = P.RW / 2 + 1.5
    if axis == "y":
        sd = 1.0 if at + off < P.ARENA["top"] - 1.0 else -1.0
        ax, ay = pos - 8.0, at + sd * off
    else:
        sd = 1.0 if at + off < P.ARENA["right"] - 1.0 else -1.0
        ax, ay = at + sd * off, pos - 8.0
    C.LAYOUT["ambush_spots"].append(dict(id=rb["id"], x=round(ax, 1), y=round(ay, 1), count=P.AMBUSH_COUNT, near=rb["id"]))
    C.LAYOUT["roadblocks"].append(rec)


# ---------------------------------------------------------------- roads, blocks

def cell_road(g, i, j, specs):
    ax = P.ARENA
    cx0 = P.CITY_LEFT if i == 0 else (P.RIVER_X1 if i == P.RIVER_COL else P.XS[i])
    cx1 = P.CITY_RIGHT if i == P.BLOCKS_X - 1 else (P.RIVER_X0 if i == P.RIVER_COL - 1 else P.XS[i + 1])
    cy0 = P.CITY_BOTTOM if j == 0 else P.YS[j]
    cy1 = P.CITY_TOP if j == P.BLOCKS_Y - 1 else P.YS[j + 1]
    C.box(g, "asphalt", cx0, cy0, -0.3, cx1, cy1, 0.0)
    # dashed centre lines: this cell draws its south road and its west road (the last row/column also the far ones)
    def ew(yc):
        yellow = abs(yc) < 0.1
        x = cx0 + 1.5
        while x < cx1 - 4.5:
            if not any(abs(x + 1.5 - xj) < P.RW / 2 + 1.0 for xj in P.XS):
                C.flat(g, "marking_y" if yellow else "marking", x, yc - 0.1, x + 3.0, yc + 0.1, 0.012)
                if yellow:
                    C.flat(g, "marking_y", x, yc - 0.45, x + 3.0, yc - 0.25, 0.012)
            x += 6.0

    def ns(xc):
        y = cy0 + 1.5
        while y < cy1 - 4.5:
            if not any(abs(y + 1.5 - yj) < P.RW / 2 + 1.0 for yj in P.YS):
                C.flat(g, "marking", xc - 0.1, y, xc + 0.1, y + 3.0, 0.012)
            y += 6.0
    ew(P.YS[j])
    if j == P.BLOCKS_Y - 1:
        ew(P.YS[j + 1])
    if i != P.RIVER_COL:
        ns(P.XS[i])
    if i == P.BLOCKS_X - 1:
        ns(P.XS[i + 1])
    # crosswalks at the junctions whose cell this is
    for a in (i, i + 1) if i == P.BLOCKS_X - 1 else (i,):
        for b in (j, j + 1) if j == P.BLOCKS_Y - 1 else (j,):
            if a == P.RIVER_COL:
                continue
            xc, yc = P.XS[a], P.YS[b]
            for sx in (-1, 1):
                for k in range(-4, 5):
                    px = xc + sx * (P.RW / 2 + 1.5)
                    py = yc + k * 1.5
                    if P.CITY_LEFT + 1 < px < P.CITY_RIGHT - 1 and P.CITY_BOTTOM + 1 < py < P.CITY_TOP - 1 and not (P.RIVER_X0 - 3 < px < P.RIVER_X1 + 3):
                        C.flat(g, "marking", px - 1.0, py - 0.3, px + 1.0, py + 0.3, 0.012)
            for sy in (-1, 1):
                for k in range(-4, 5):
                    py = yc + sy * (P.RW / 2 + 1.5)
                    px = xc + k * 1.5
                    if P.CITY_LEFT + 1 < px < P.CITY_RIGHT - 1 and P.CITY_BOTTOM + 1 < py < P.CITY_TOP - 1 and not (P.RIVER_X0 - 3 < px < P.RIVER_X1 + 3):
                        C.flat(g, "marking", px - 0.3, py - 1.0, px + 0.3, py + 1.0, 0.012)


def build_block(i, j, specs, kit_choice):
    g = "blk_%d_%d" % (i, j)
    C.RNG.seed(1000 + i * 17 + j * 131)
    rect = P.block_rect(i, j)
    cell_road(g, i, j, specs)
    C.block_ground(g, g, rect)
    blk = C.LAYOUT["blocks"][-1]
    blk.update(i=i, j=j, kit=kit_choice, district=P.district_of(i, j))
    x0, y0, x1, y1 = rect
    inner = (x0 + P.SW, y0 + P.SW, x1 - P.SW, y1 - P.SW)
    K.KITS[kit_choice](g, inner)
    K.add_spawns(rect, 3)
    for s in specs.get(g, []):
        if s[0] == "lamp":
            C.lamp(g, s[1], s[2], s[3], on=s[4], flicker=s[5])
        elif s[0] == "wreck":
            K.wreck_lp(g, s[1], s[2], s[3], s[4], burnt=s[5], lights_on=s[6], flicker=0.3 if s[6] else 0.0)


def pick_kits():
    rng = random.Random(3)
    kits = {}
    for i in range(P.BLOCKS_X):
        for j in range(P.BLOCKS_Y):
            if (i, j) in P.PINNED:
                kits[(i, j)] = P.PINNED[(i, j)]
                continue
            pool = P.DISTRICT_KITS[P.district_of(i, j)]
            choice = rng.choice(pool)
            # no two neighbours the same kit when a different one is on offer
            for _ in range(6):
                nb = [kits.get((i - 1, j)), kits.get((i, j - 1))]
                if choice not in nb:
                    break
                choice = rng.choice(pool)
            kits[(i, j)] = choice
    return kits


# ---------------------------------------------------------------- river and bridges

def build_river():
    g = "river"
    x0, x1 = P.RIVER_X0, P.RIVER_X1
    top, bot = P.CITY_TOP, P.CITY_BOTTOM
    C.flat(g, "water", x0, bot, x1, top + 300.0, -1.2)
    # bridge decks (road rows) and the lift bridge's gap
    decks = [(P.YS[b] - P.RW / 2, P.YS[b] + P.RW / 2) for b in P.BRIDGE_ROWS]
    lift = (P.YS[P.LIFT_ROW] - P.RW / 2, P.YS[P.LIFT_ROW] + P.RW / 2)
    gaps = sorted(decks + [lift])
    # quay walls: 3 m thick, from the water up to a little over the road, broken at each deck
    for (xa, xb) in ((x0, x0 + 3.0), (x1 - 3.0, x1)):
        y = bot
        for (g0, g1) in gaps + [(top, top)]:
            if g0 - y > 0.1:
                C.box(g, "concrete", xa, y, -1.6, xb, g0, 0.3)
                C.box(g, "trim", xa - 0.1 if xa == x0 else xa, y, 0.3, xb if xa == x0 else xb + 0.1, g0, 0.6)
                C.collider(xa, y, xb, g0, "fence")
            y = g1
    for k, (g0, g1) in enumerate(decks):
        yc = (g0 + g1) / 2
        C.box(g, "concrete", x0, g0, -1.0, x1, g1, -0.3)
        C.box(g, "asphalt", x0, g0, -0.3, x1, g1, 0.0)
        C.flat(g, "marking_y" if abs(yc) < 0.1 else "marking", x0, yc - 0.1, x1, yc + 0.1, 0.012)
        # parapets along both sides of the deck, from quay wall to quay wall
        for (pa, pb) in ((g0 - 0.5, g0), (g1, g1 + 0.5)):
            C.box(g, "concrete", x0 + 3.0, pa, -0.3, x1 - 3.0, pb, 1.0)
            C.collider(x0 + 3.0, pa, x1 - 3.0, pb, "fence")
        # piers under the deck
        C.box(g, "concrete", (x0 + x1) / 2 - 1.5, g0 + 1.0, -1.6, (x0 + x1) / 2 + 1.5, g0 + 3.0, -1.0)
        C.box(g, "concrete", (x0 + x1) / 2 - 1.5, g1 - 3.0, -1.6, (x0 + x1) / 2 + 1.5, g1 - 1.0, -1.0)
        # the creatures wait on the east bank's sidewalk, a few metres from the bridge's end, out of the headlights
        C.LAYOUT["ambush_spots"].append(dict(id="bridge_%d" % k, x=round(x1 + 8.0, 1), y=round(yc + P.RW / 2 + 1.5, 1), count=P.AMBUSH_COUNT, near="bridge_%d" % k))
        C.LAYOUT["bridges"].append(dict(id="bridge_%d" % k, kind="fixed", x=round((x0 + x1) / 2, 2), y=round(yc, 2), length=x1 - x0, width=P.RW, axis="x"))
    # the lift bridge, drawn raised: towers on both banks, a deck hung between them at 13 m, the road cut at the quays
    l0, l1 = lift
    closers = []
    for (xa, xb) in ((x0, x0 + 3.0), (x1 - 3.0, x1)):
        C.box(g, "concrete", xa, l0, -1.6, xb, l1, 0.3)
        C.box(g, "trim", xa, l0, 0.3, xb, l1, 0.6)
        C.collider(xa, l0, xb, l1, "fence")
        closers.append(dict(x0=xa, y0=l0, x1=xb, y1=l1))
        for ty in (l0 + 0.2, l1 - 1.6):
            C.box(g, "metal", xa, ty, 0.6, xb, ty + 1.4, 24.0)
            C.box(g, "trim", xa - 0.1, ty - 0.1, 24.0, xb + 0.1, ty + 1.5, 24.4)
    C.box(g, "rust", x0, l0, 23.2, x1, l0 + 1.4, 24.0)
    C.box(g, "rust", x0, l1 - 1.4, 23.2, x1, l1, 24.0)
    C.box(g, "asphalt", x0 + 3.0, l0 + 0.3, 12.4, x1 - 3.0, l1 - 0.3, 13.2)
    C.box(g, "concrete", x0 + 3.0, l0 + 0.3, 11.6, x1 - 3.0, l1 - 0.3, 12.4)
    for cx in (x0 + 7.0, (x0 + x1) / 2, x1 - 7.0):
        for cy in (l0 + 0.5, l1 - 0.5):
            C.box(g, "metal", cx - 0.05, cy - 0.05, 13.2, cx + 0.05, cy + 0.05, 23.2)
    for lx in (x0 + 3.5, x1 - 3.5):
        for ly in (l0 + 1.8, l1 - 1.8):
            C.box(g, "beacon", lx - 0.3, ly - 0.3, 24.4, lx + 0.3, ly + 0.3, 25.0)
    C.LAYOUT["bridges"].append(dict(id="lift_bridge", kind="lift", up=True, x=round((x0 + x1) / 2, 2), y=round(P.YS[P.LIFT_ROW], 2), length=x1 - x0, width=P.RW, axis="x",
                                      closers=closers, deck_up_z=12.4))
    C.LAYOUT["river"] = dict(x0=x0, x1=x1, y0=bot, y1=top, quay_thickness=3.0)


# ---------------------------------------------------------------- the highway

LANES_N = [3.75, 7.65, 11.55]
LANES_S = [-3.75, -7.65, -11.55]


def hw_wreck(x, y, heading, kind="sedan", **kw):
    STATS["wrecks_hw"] += 1
    return K.wreck_lp(hw_group(x), x, y, heading, kind, **kw)


def build_highway():
    x_a, x_b = P.HW_X0, P.HW_X1
    H = P.HW
    stop0, stop1, depth = H["truck_stop_x0"], H["truck_stop_x1"], H["truck_stop_depth"]
    ovx = H["overpass_x"]
    hy = P.HIGHWAY_Y
    # road surface, chunked
    k = 0
    x = x_a
    while x < x_b - 0.01:
        x1 = min(x + 100.0, x_b)
        g = hw_group(x + 1)
        C.box(g, "asphalt", x, -P.HW_HALF, -0.3, x1, P.HW_HALF, 0.0)
        # lane lines: dashed white between the lanes, solid yellow beside the median, white edge lines
        xx = x + 1.5
        while xx < x1 - 3.0:
            for yy in (5.7, 9.6, -5.7, -9.6):
                C.flat(g, "marking", xx, yy - 0.08, xx + 3.0, yy + 0.08, 0.012)
            xx += 9.0
        C.flat(g, "marking_y", x, 0.8, x1, 0.95, 0.012)
        C.flat(g, "marking_y", x, -0.95, x1, -0.8, 0.012)
        C.flat(g, "marking", x, 14.2, x1, 14.35, 0.012)
        C.flat(g, "marking", x, -14.35, x1, -14.2, 0.012)
        x = x1
    # the median barrier: 1 m half width, with crossovers (gaps) at the toll plaza and where the overpass fell
    cross = [(H["toll_x0"] - 40.0, H["toll_x0"] - 20.0), (H["toll_x1"] + 20.0, H["toll_x1"] + 40.0), (ovx + 20.0, ovx + 40.0), (ovx - 40.0, ovx - 20.0), (H["jam_x0"] + 50.0, H["jam_x0"] + 62.0), (x_a + 150.0, x_a + 162.0)]
    cuts = sorted(cross)
    seg_start = x_a
    for (c0, c1) in cuts + [(x_b, x_b)]:
        if c0 - seg_start > 1.0:
            # per chunk visuals, one collider
            xs = seg_start
            while xs < c0 - 0.01:
                xe = min(c0, (int((xs - x_a) // 100.0) + 1) * 100.0 + x_a)
                C.box(hw_group(xs + 0.5), "concrete", xs, -1.0, 0.0, xe, 1.0, 0.9)
                C.box(hw_group(xs + 0.5), "trim", xs, -0.4, 0.9, xe, 0.4, 1.05)
                xs = xe
            C.collider(seg_start, -1.0, c0, 1.0, "prop")
        seg_start = c1
    # embankments: the corridor is carved from solid; colliders in long pieces, a concrete wall seen on every chunk
    def emb(xa, xb, ya, yb):
        C.collider(xa, ya, xb, yb, "building")
    emb(x_a, stop0, P.HW_HALF, P.ARENA["top"])
    emb(stop1, P.ARENA["right"], P.HW_HALF, P.ARENA["top"])
    emb(stop0, stop1, P.HW_HALF + depth, P.ARENA["top"])
    emb(x_a, P.ARENA["right"], P.ARENA["bottom"], -P.HW_HALF)
    x = x_a
    while x < P.ARENA["right"] - 0.01:
        x1 = min(x + 100.0, P.ARENA["right"])
        g = hw_group(x + 1)
        C.box(g, "concrete", x, -P.HW_HALF - 2.0, 0.0, x1, -P.HW_HALF, 2.4)
        C.box(g, "trim", x, -P.HW_HALF - 2.1, 2.4, x1, -P.HW_HALF, 2.6)
        for (a, b) in ((x, x1),):
            # north wall, except along the truck stop
            segs = []
            if b <= stop0 or a >= stop1:
                segs = [(a, b)]
            else:
                if a < stop0:
                    segs.append((a, stop0))
                if b > stop1:
                    segs.append((stop1, b))
            for (sa, sb) in segs:
                C.box(g, "concrete", sa, P.HW_HALF, 0.0, sb, P.HW_HALF + 2.0, 2.4)
                C.box(g, "trim", sa, P.HW_HALF, 2.4, sb, P.HW_HALF + 2.1, 2.6)
        x = x1
    # lamps on the shoulders, few alive
    n = 0
    lx = x_a + 40.0
    live_at = {int(x_a + 220), int(x_a + 460), int(x_b - 360), int(x_b - 120)}
    while lx < x_b - 60:
        for sgn in (-1, 1):
            on = any(abs(lx - v) < 30 for v in live_at) and sgn == 1
            if stop0 - 5 < lx < stop1 + 5 and sgn == 1:
                continue
            C.lamp(hw_group(lx), lx, sgn * (P.HW_HALF - 0.7), (0, -sgn), on=on, flicker=0.4 if on else 0.0)
        lx += 60.0
    # gantry signs
    for gx, txt in ((x_a + 150.0, "HARBOUR"), (x_a + 330.0, "TRUCK STOP"), (H["toll_x1"] + 40.0, "TOLL AHEAD")):
        g = hw_group(gx)
        for sy in (-1, 1):
            C.box(g, "metal", gx - 0.3, sy * (P.HW_HALF + 0.3) - 0.3, 0.0, gx + 0.3, sy * (P.HW_HALF + 0.3) + 0.3, 7.2)
        C.box(g, "metal", gx - 0.25, -P.HW_HALF - 0.3, 6.6, gx + 0.25, P.HW_HALF + 0.3, 7.2)
        C.box(g, "trim", gx + 0.25, -7.0, 4.6, gx + 0.45, 7.0, 6.6)
        f = C.faces_of(gx + 0.45, -7.0, gx + 0.46, 7.0)["E"]
        K.sign3(g, "neon_teal", txt, f, f.L / 2, 5.6, 1.1)
    # ------ the toll plaza: booths on narrow islands, four metres of lane between them, a roof over the lot
    t0, t1 = H["toll_x0"], H["toll_x1"]
    g = hw_group(t0)
    for sgn in (1, -1):
        for (ya, yb) in ((5.0, 6.0), (10.0, 11.0)):
            ya, yb = sgn * ya, sgn * yb
            lo, hi = min(ya, yb), max(ya, yb)
            C.box(g, "concrete", t0, lo, 0.0, t1, hi, 0.3)
            C.collider(t0, lo, t1, hi, "prop")
            bx0 = (t0 + t1) / 2 - 2.5
            C.box(g, "wall3", bx0, lo, 0.3, bx0 + 5.0, hi, 2.9)
            C.fquad(g, "lit_shop", C.faces_of(bx0, lo, bx0 + 5.0, hi)["E"], 0.1, 0.9, 1.2, 2.4, 0.03)
            for px in (t0 + 0.6, t1 - 0.6):
                C.box(g, "metal", px - 0.3, lo + 0.1, 0.3, px + 0.3, hi - 0.1, 6.2)
    C.box(g, "trim", t0 + 6.0, -P.HW_HALF, 6.2, t1 - 6.0, P.HW_HALF, 6.9)
    f = C.faces_of(t0 + 6.0, -P.HW_HALF, t1 - 6.0, P.HW_HALF)["E"]
    K.sign3(g, "neon_amber", "TOLL", f, f.L / 2, 6.55, 0.5)
    C.light((t0 + t1) / 2, 0.0, 5.8, [1.0, 0.8, 0.5], 6.0, 20.0, 0.5, "omni", fog=1.5)
    C.LAYOUT["highway"]["toll_plaza"] = dict(x0=t0, x1=t1, lane_gap=4.0, lanes_per_way=3)
    # ------ the jam: rows of stalled traffic with one free lane that wanders, so a car can weave through
    def jam(xa, xb, rng, fill=0.86, step=9.0):
        free_n, free_s = 1, 1
        xr = xa
        hold_n = hold_s = 0
        while xr < xb:
            for lanes, free_ref in ((LANES_N, "n"), (LANES_S, "s")):
                if free_ref == "n":
                    if hold_n <= 0:
                        free_n = min(2, max(0, free_n + rng.choice((-1, 0, 1))))
                        hold_n = 2
                    hold_n -= 1
                    free = free_n
                else:
                    if hold_s <= 0:
                        free_s = min(2, max(0, free_s + rng.choice((-1, 0, 1))))
                        hold_s = 2
                    hold_s -= 1
                    free = free_s
                for li, ly in enumerate(lanes):
                    if li == free:
                        continue
                    if rng.random() > fill:
                        continue
                    heading = math.pi if ly > 0 else 0.0
                    kind = rng.choice(["sedan", "sedan", "sedan", "van"])
                    hw_wreck(xr + rng.uniform(-1.2, 1.2), ly + rng.uniform(-0.25, 0.25), heading, kind, burnt=rng.random() < 0.2, lights_on=rng.random() < 0.04, flicker=0.3)
            xr += step
    rng = random.Random(21)
    jam(H["jam_x0"], H["jam_x1"], rng)
    jam(t1 + 8.0, t1 + 45.0, rng, fill=0.7, step=10.0)        # the queue for the toll plaza (it stops short of the checkpoint)
    jam(ovx + 70.0, ovx + 130.0, rng, fill=0.6, step=11.0)    # the queue for the fallen overpass, east side
    C.LAYOUT["highway"]["jam"] = dict(x0=H["jam_x0"], x1=H["jam_x1"])
    # sparse strays elsewhere
    x = x_a + 25.0
    while x < x_b - 120:
        x += rng.uniform(28, 52)
        if H["jam_x0"] - 20 < x < H["jam_x1"] + 20 or H["toll_x0"] - 30 < x < H["toll_x1"] + 80 or ovx - 60 < x < ovx + 140 or x > H["checkpoint_x0"] - 20:
            continue
        lanes = LANES_N if rng.random() < 0.45 else LANES_S
        ly = rng.choice(lanes)
        hw_wreck(x, ly, math.pi if ly > 0 else 0.0, rng.choice(["sedan", "sedan", "van", "truck"]), burnt=rng.random() < 0.3)
    # ------ the fallen overpass: a block across both carriageways reaching into the truck stop, one tight way past
    ox0, ox1 = ovx - 8.0, ovx + 8.0
    slab_top = 26.0
    g = hw_group(ovx)
    C.collider(ox0, -P.HW_HALF, ox1, slab_top, "building")
    tilted_box(g, "concrete", ovx - 1.0, -7.5, 2.0, 15.0, 15.0, 1.4, rx=0.24)
    tilted_box(g, "concrete", ovx + 1.0, 5.0, 2.6, 15.0, 13.0, 1.4, rx=-0.18, rz=0.05)
    tilted_box(g, "concrete", ovx, 17.5, 1.5, 14.0, 12.0, 1.2, rx=0.3)
    C.box(g, "concrete", ovx - 1.0, -1.2, 0.0, ovx + 1.0, 1.2, 6.5)
    C.box(g, "trim", ovx - 1.3, -1.5, 6.5, ovx + 1.3, 1.5, 7.0)
    for k2 in range(10):
        ry = R.uniform(-13, 24)
        rx = R.uniform(ox0 + 1, ox1 - 1)
        C.cyl(g, "rust", rx, ry, 2.0, R.uniform(3.4, 5.0), 0.04, 4)
    for (wy, hd) in ((-9.0, 0.0), (9.5, math.pi)):
        # a car pinned at the foot of the slab, east side
        hw_wreck(ox1 + 3.0, wy, hd, "sedan", burnt=True)
    C.LAYOUT["highway"]["fallen_overpass"] = dict(x0=ox0, x1=ox1, y0=-P.HW_HALF, y1=slab_top)
    # ------ the truck stop: a lot open to the carriageway, a tanker and trailers across it that leave one squeeze
    lot = "hw_lot"
    lg = hw_group(ovx)
    C.box(lg, "asphalt", stop0, P.HW_HALF, -0.3, stop1, P.HW_HALF + depth, 0.0)
    for sx in (stop0, stop1):
        C.box(lg, "concrete", sx - 2.0 if sx == stop0 else sx, P.HW_HALF, 0.0, sx if sx == stop0 else sx + 2.0, P.HW_HALF + depth, 2.4)
    C.box(lg, "concrete", stop0, P.HW_HALF + depth, 0.0, stop1, P.HW_HALF + depth + 2.0, 2.4)
    # a fence of tanker and trailers from the slab's end north to the lot's wall, one 4 m squeeze and one wide gap
    sq0 = slab_top
    sq1 = sq0 + P.SQUEEZE_GAP
    fill_stretch(lg, "y", sq1, sq1 + 30.0, ovx)
    wide0, wide1 = sq1 + 30.0, sq1 + 37.0
    fill_stretch(lg, "y", wide1, P.HW_HALF + depth, ovx, truck_ok=False)
    # the diner with its sign pylon, a fuel canopy with pumps, parked trailers on the west side
    dx0, dx1 = ovx + 60.0, ovx + 100.0
    K.bldg(lg, dx0, P.HW_HALF + depth - 16.0, dx1, P.HW_HALF + depth - 3.0, 5.4, "wall4", lit_p=0.0, shop=("S",), awning="awn2", sign=("DINER", "neon_red"), floor_h=4.5)
    cx0, cx1, cy0, cy1 = ovx + 36.0, ovx + 70.0, 33.0, 46.0
    C.box(lg, "trim", cx0, cy0, 5.2, cx1, cy1, 5.8)
    C.box(lg, "lit_shop", cx0 + 0.5, cy0 + 0.5, 5.15, cx1 - 0.5, cy1 - 0.5, 5.2)
    for (px, py) in ((cx0 + 1.2, cy0 + 1.2), (cx1 - 1.2, cy0 + 1.2), (cx0 + 1.2, cy1 - 1.2), (cx1 - 1.2, cy1 - 1.2)):
        C.box(lg, "concrete", px - 0.3, py - 0.3, 0.0, px + 0.3, py + 0.3, 5.2)
        C.collider(px - 0.3, py - 0.3, px + 0.3, py + 0.3, "prop")
    for px in (cx0 + 8, cx0 + 17, cx0 + 26):
        C.box(lg, "metal", px - 0.5, cy0 + 6.1, 0.0, px + 0.5, cy0 + 6.9, 1.6)
        C.box(lg, "neon_red", px - 0.35, cy0 + 6.0, 1.25, px + 0.35, cy0 + 6.12, 1.5)
        C.collider(px - 0.5, cy0 + 6.1, px + 0.5, cy0 + 6.9, "prop")
    C.light((cx0 + cx1) / 2, (cy0 + cy1) / 2, 5.0, [1.0, 0.95, 0.8], 5.0, 20.0, 0.15, "omni", fog=1.5)
    C.cyl(lg, "metal", stop1 - 12.0, 50.0, 0.0, 15.0, 0.25, 6)
    C.post(stop1 - 12.0, 50.0, 0.5, "pylon")
    C.box(lg, "neon_amber", stop1 - 15.5, 49.2, 13.0, stop1 - 8.5, 50.8, 15.5)
    for k3 in range(4):
        tx = stop0 + 14.0 + k3 * 14.5
        K.wreck_lp(lg, tx, P.HW_HALF + 38.0 + (k3 % 2) * 4.0, math.pi / 2, "truck", burnt=k3 == 2)
    C.LAYOUT["highway"]["truck_stop"] = dict(x0=stop0, x1=stop1, y0=P.HW_HALF, y1=P.HW_HALF + depth, squeeze=dict(x=ovx, y0=sq0, y1=sq1, width=P.SQUEEZE_GAP),
                                              wide_gap=dict(x=ovx, y0=wide0, y1=wide1, width=wide1 - wide0))
    C.LAYOUT["ambush_spots"].append(dict(id="hw_truck_stop", x=ovx - 14.0, y=sq1 + 6.0, count=P.AMBUSH_COUNT, near="truck_stop"))
    C.LAYOUT["ambush_spots"].append(dict(id="hw_jam", x=(H["jam_x0"] + H["jam_x1"]) / 2, y=-5.0, count=P.AMBUSH_COUNT, near="jam"))
    C.LAYOUT["ambush_spots"].append(dict(id="hw_toll", x=t0 - 8.0, y=-12.0, count=P.AMBUSH_COUNT, near="toll_plaza"))
    # hunters waiting in stalled cars: released when the car comes within 35 m
    # Hunters waiting in stalled cars, released when the car comes within 40 m. One by one, not a crowd: at least
    # HUNTER_SPACING metres apart along the road (less in the jam, where the traffic is thick), mostly in the
    # carriageway the car drives (north).
    cars = sorted((w for w in C.LAYOUT["wrecks"] if w["kind"] != "bus" and w["x"] > P.HW_X0 + 100 and abs(w["y"]) < P.HW_HALF), key=lambda w: -w["x"])
    rng2 = random.Random(5)
    picked, last_x = [], 1e9
    # None in the set pieces themselves (the checkpoint, the toll plaza, the jam, the overpass and truck stop): there the
    # obstacles are the danger, and a creature on the car in a tight lane has nowhere to be thrown off.
    quiet = [(H["jam_x0"] - 30.0, H["toll_x1"] + 60.0), (H["truck_stop_x0"] - 40.0, H["overpass_x"] + 140.0)]
    for w in cars:
        spacing = P.HUNTER_SPACING
        if any(a <= w["x"] <= b for a, b in quiet):
            continue
        if last_x - w["x"] >= spacing and (w["y"] > 0 or rng2.random() < 0.3) and w["x"] < H["checkpoint_x0"] - 30:
            picked.append(dict(x=w["x"], y=w["y"], release=P.HUNTER_RELEASE))
            last_x = w["x"]
    C.LAYOUT["stalled_hunters"] = picked
    # ------ the checkpoint at the far end, being overrun
    build_checkpoint()
    # creature spawns: in the dark stretches' shoulders
    for xs in range(int(x_a + 60), int(x_b - 120), 70):
        for sgn in (1, -1):
            sx, sy = xs + rng.uniform(-8, 8), sgn * 13.2
            if not K._inside_boxes(sx, sy, 1.0):
                C.LAYOUT["creature_spawns"].append(dict(x=round(sx, 1), y=round(sy, 1)))


def build_checkpoint():
    H = P.HW
    x0 = H["checkpoint_x0"]
    xr = P.ARENA["right"]
    g = hw_group(x0 + 5)
    # a chicane on each carriageway, 20 m apart, each barrier leaving a 7 m gap (the car arrives at highway speed and
    # has to shift a lane and back: tighter than this is the city's 4 m squeezes, not a checkpoint's)
    def barrier_wall(xa, xb, ya, yb):
        C.box(hw_group(xa), "concrete", xa, ya, 0.0, xb, yb, 1.0)
        C.box(hw_group(xa), "marking_y", xa, ya, 1.0, xb, yb, 1.06)
        C.collider(xa, ya, xb, yb, "prop")
    barrier_wall(x0 + 22.0, x0 + 25.0, 1.0, 8.0)       # north carriageway: gap on the outer side
    barrier_wall(x0 + 2.0, x0 + 5.0, 1.0, 5.0)         # then the gap shifts a lane in: open between the two pieces
    barrier_wall(x0 + 2.0, x0 + 5.0, 12.0, 15.0)
    barrier_wall(x0 + 22.0, x0 + 25.0, -8.0, -1.0)
    barrier_wall(x0 + 2.0, x0 + 5.0, -5.0, -1.0)
    barrier_wall(x0 + 2.0, x0 + 5.0, -15.0, -12.0)
    # sandbags in a low wall on the south carriageway's shoulder, tents behind them, a hut at the median's end
    sg = hw_group(x0 + 30)
    C.box(sg, "sandbag", x0 + 32.0, -14.2, 0.0, x0 + 62.0, -12.6, 1.2)
    C.collider(x0 + 32.0, -14.2, x0 + 62.0, -12.6, "prop")
    for k in range(3):
        tx = x0 + 36.0 + k * 9.0
        C.box(sg, "canvas", tx - 3.0, -11.0, 0.0, tx + 3.0, -6.0, 2.6)
        C.box(sg, "awn2", tx - 3.2, -11.2, 2.6, tx + 3.2, -5.8, 2.9)
        C.collider(tx - 3.0, -11.0, tx + 3.0, -6.0, "prop")
    K.plain_shed(sg, x0 + 45.0, -4.5, x0 + 53.0, -1.0, 3.4, "wall5", "N")
    K.wreck_lp(sg, x0 + 78.0, -7.65, 0.0, "truck", "paint2", burnt=True)
    K.wreck_lp(sg, x0 + 40.0, 3.75, math.pi, "van", "paint3", burnt=True, lights_on=True, flicker=0.5)
    for (bx, by) in ((x0 + 30.0, -10.5), (x0 + 5.0, -13.0), (x0 + 60.0, -2.5)):
        C.barrel(sg, bx, by, fire=True)
    # floodlight poles on the shoulders: live, the checkpoint was being held
    for (fx, fy, tag) in ((x0 + 14.0, -13.8, "checkpoint"), (x0 + 48.0, -13.8, "checkpoint"), (x0 + 70.0, 13.8, "checkpoint")):
        C.cyl(sg, "metal", fx, fy, 0.0, 9.0, 0.14, 6)
        C.box(sg, "lamp_head", fx - 0.6, fy - 0.3, 8.8, fx + 0.6, fy + 0.3, 9.1)
        C.post(fx, fy, 0.25, "lamp")
        C.light(fx, fy, 8.6, [1.0, 0.95, 0.8], 7.0, 30.0, 0.35, "omni", fog=1.6)
        C.LAYOUT["lights"][-1]["tag"] = tag
    # the cordon's end wall and a gate frame, shut
    C.box(hw_group(xr - 3), "concrete", xr - 0.5, -P.HW_HALF - 2.0, 0.0, xr + 0.5, P.HW_HALF + 2.0, 4.5)
    C.LAYOUT["highway"]["checkpoint"] = dict(x0=x0, x1=xr, chicane_gap=7.0)


# ---------------------------------------------------------------- perimeter, gate, ground, skyline

def build_world():
    g = "world"
    ax = P.ARENA
    # ground to the horizon, cut where the river and the sea are
    ground_x0, ground_x1, ground_y1 = ax["left"] - 220.0, ax["right"] + 260.0, ax["top"] + 220.0
    C.box(g, "dirt", ground_x0, ax["bottom"], -0.6, P.RIVER_X0, ground_y1, -0.02)
    C.box(g, "dirt", P.RIVER_X1, ax["bottom"], -0.6, ground_x1, ground_y1, -0.02)
    C.flat(g, "sea", ground_x0 - 200, ax["bottom"] - 500.0, ground_x1 + 200, ax["bottom"], -1.2)
    # quay edge along the south, with bollards
    C.box(g, "concrete", ax["left"], ax["bottom"] - 0.8, -1.6, P.RIVER_X0, ax["bottom"], 0.3)
    C.box(g, "concrete", P.RIVER_X1, ax["bottom"] - 0.8, -1.6, ax["right"], ax["bottom"], 0.3)
    x = ax["left"] + 6.0
    while x < P.CITY_RIGHT:
        if not (P.RIVER_X0 - 3 < x < P.RIVER_X1 + 3):
            C.cyl(g, "metal", x, ax["bottom"] + 0.7, 0.0, 0.5, 0.18, 6)
        x += 18.0
    # perimeter walls (collision is the arena rectangle itself, as in the quarter)
    t = 1.0
    gate_y0, gate_y1 = P.GATE["y"] - P.GATE["width"] / 2, P.GATE["y"] + P.GATE["width"] / 2
    for (a, b, c, d) in ((ax["left"] - t, gate_y1, ax["left"], ax["top"] + t), (ax["left"] - t, ax["bottom"], ax["left"], gate_y0), (ax["left"] - t, ax["top"], P.CITY_RIGHT, ax["top"] + t)):
        C.box(g, "concrete", a, b, 0.0, c, d, 4.5)
        C.box(g, "trim", a - 0.1, b - 0.1, 4.5, c + 0.1, d + 0.1, 4.8)
    # the city's east wall either side of the highway's mouth
    for (ya, yb) in ((P.HW_HALF, ax["top"] + t), (ax["bottom"], -P.HW_HALF)):
        C.box(g, "concrete", P.CITY_RIGHT, ya, 0.0, P.CITY_RIGHT + 1.0, yb, 4.5)
    # the gate: where the south ring road leaves the city through the west wall, beyond the lift bridge
    x = P.GATE["x"]
    hw = P.GATE["width"] / 2
    gy = P.GATE["y"]
    for sgn in (-1, 1):
        y0, y1 = (gy + hw, gy + hw + 1.4) if sgn > 0 else (gy - hw - 1.4, gy - hw)
        C.box(g, "concrete", x - 1.5, y0, 0.0, x, y1, 7.0)
        C.box(g, "trim", x - 1.6, y0 - 0.1, 7.0, x, y1 + 0.1, 7.25)
    C.box(g, "concrete", x - 1.3, gy - hw, 6.2, x, gy + hw, 7.0)
    C.box(g, "trim", x - 1.4, gy - hw - 1.5, 7.0, x, gy + hw + 1.5, 7.25)
    C.box(g, "asphalt", x - 44.0, gy - hw - 1.0, -0.3, x, gy + hw + 1.0, 0.0)
    for k in range(7):
        xx = x - 3.0 - k * 6.0
        C.flat(g, "marking_y", xx - 3.0, gy - 0.1, xx, gy + 0.1, 0.012)
    C.LAYOUT["gate"] = dict(x=P.GATE["x"], y=P.GATE["y"], width=P.GATE["width"], dx=-1.0, dy=0.0, bridge="lift_bridge")
    # a skyline of dark, mostly unlit towers beyond the city's walls: only seen through the fog
    rng = random.Random(9)
    for k in range(70):
        a = 2 * math.pi * k / 70 + rng.uniform(-0.03, 0.03)
        cxm, cym = (P.CITY_LEFT + P.CITY_RIGHT) / 2, 0.0
        r = rng.uniform(1.0, 1.25)
        x = cxm + math.cos(a) * (P.CITY_RIGHT - P.CITY_LEFT) / 2 * r * 1.1 + math.cos(a) * 90
        y = cym + math.sin(a) * (P.CITY_TOP - P.CITY_BOTTOM) / 2 * r * 1.1 + math.sin(a) * 90
        if x > P.CITY_RIGHT + 30 or y < ax["bottom"] - 5:
            continue
        w, d, h = rng.uniform(12, 24), rng.uniform(12, 24), rng.uniform(25, 70)
        C.box(g, "skyline", x - w / 2, y - d / 2, 0.0, x + w / 2, y + d / 2, h)
    # low dark shapes along the highway's two sides: industrial sheds, pylons, a few tall stacks in the haze
    x = P.HW_X0 + 30.0
    while x < P.HW_X1:
        for sgn in (-1, 1):
            if rng.random() < 0.7:
                w, d, h = rng.uniform(14, 40), rng.uniform(10, 30), rng.uniform(6, 22)
                off = P.HW_HALF + (P.HW_HALF + depth_for(x) + 12.0 if sgn > 0 else 16.0) + rng.uniform(0, 40)
                y = sgn * off
                if abs(y) + d / 2 > 150 + 200:
                    continue
                C.box(g, "skyline", x - w / 2, y - d / 2, 0.0, x + w / 2, y + d / 2, h)
        x += rng.uniform(30, 60)


def depth_for(x):
    H = P.HW
    return H["truck_stop_depth"] if H["truck_stop_x0"] - 40 < x < H["truck_stop_x1"] + 40 else 0.0


# ---------------------------------------------------------------- build and export

def flush_all():
    objs = []
    for name in sorted(C.G.keys()):
        ob = C.flush_group(name, name)
        if ob:
            objs.append(ob)
    return objs


def init_layout():
    C.LAYOUT.clear()
    C.LAYOUT.update(
        arena=dict(left=P.ARENA["left"], right=P.ARENA["right"], bottom=P.ARENA["bottom"], top=P.ARENA["top"]),
        boxes=[], posts=[], lamps=[], lights=[], wrecks=[], blocks=[], creature_spawns=[], fires=[], generators=[],
        player_start=dict(x=round(P.PLACES["highway_start"]["x"] + 5.0, 2), y=P.PLACES["highway_start"]["y"], angle=round(math.pi, 4)),
        roads=[], roadblocks=[], bridges=[], ambush_spots=[], stalled_hunters=[], places={}, highway={}, planned_legs=[],
        map_frame=dict(left=P.CITY_LEFT, right=P.CITY_RIGHT + 150.0, bottom=P.CITY_BOTTOM, top=P.CITY_TOP),
        size=dict(blocks_x=P.BLOCKS_X, blocks_y=P.BLOCKS_Y, street_x=P.STREET_X, street_y=P.STREET_Y, road_width=P.RW, highway_length=P.HIGHWAY_LEN),
    )


def settle_points():
    """Creature spawns and ambush spots are hiding places: any that ended inside a collider is nudged clear, or a spawn dropped."""
    L = C.LAYOUT
    a = P.ARENA

    def clear(x, y):
        return a["left"] + 1 < x < a["right"] - 1 and a["bottom"] + 1 < y < a["top"] - 1 and not K._inside_boxes(x, y, 0.8)
    kept = []
    for s in L["creature_spawns"]:
        if clear(s["x"], s["y"]):
            kept.append(s)
    L["creature_spawns"] = kept
    for s in L["ambush_spots"]:
        if clear(s["x"], s["y"]):
            continue
        for r in (3.0, 5.0, 8.0):
            moved = False
            for dx, dy in ((r, 0), (-r, 0), (0, r), (0, -r), (r, r), (-r, -r), (r, -r), (-r, r)):
                if clear(s["x"] + dx, s["y"] + dy):
                    s["x"], s["y"] = round(s["x"] + dx, 1), round(s["y"] + dy, 1)
                    moved = True
                    break
            if moved:
                break


def build_story_props():
    """What the story's places show: Ruck's burnt-out truck with its lamps on, and a generator at each of the three posts."""
    L = C.LAYOUT
    rx, ry = P.RUCK_TRUCK
    g = cell_group(rx, ry)
    K.wreck_lp(g, rx, ry, math.pi, "truck", "paint2", burnt=True, lights_on=True, flicker=0.15)
    C.barrel(g, rx + 10.0, ry - 4.5, fire=True)
    C.barrel(g, rx - 10.0, ry - 3.5, fire=False)
    for name, (gx, gy) in P.GENERATORS.items():
        g = cell_group(gx, gy)
        C.box(g, "metal", gx - 1.2, gy - 0.6, 0.0, gx + 1.2, gy + 0.6, 1.3)
        C.box(g, "lit_cool", gx - 0.9, gy - 0.64, 0.5, gx + 0.9, gy - 0.6, 1.1)
        C.box(g, "rust", gx - 1.0, gy + 0.6, 1.3, gx + 1.0, gy + 0.9, 1.6)
        C.collider(gx - 1.2, gy - 0.6, gx + 1.2, gy + 0.6, "prop")
        C.light(gx, gy, 2.2, [0.6, 0.85, 1.0], 3.5, 10.0, 0.3, "omni", fog=1.4)
        L["lights"][-1]["tag"] = "generator_" + name
        L["generators"].append(dict(post=name, x=round(gx, 2), y=round(gy, 2)))


def build():
    reset()
    C.G.clear()
    C.MATS.clear()
    C.define_materials()
    define_extra_materials()
    init_layout()
    kits = pick_kits()
    specs = plan_street_objects()
    for i in range(P.BLOCKS_X):
        for j in range(P.BLOCKS_Y):
            build_block(i, j, specs, kits[(i, j)])
    for rb in P.ROADBLOCKS:
        build_roadblock(rb)
    build_story_props()
    build_river()
    build_highway()
    build_world()
    # roads as data, in the shape sim_world.gd documents: {axis, c, width, from, to}, `axis` the direction it runs along
    river_rows = set(P.BRIDGE_ROWS + [P.LIFT_ROW])
    for j, y in enumerate(P.YS):
        kind = "ring" if j in (0, len(P.YS) - 1) else "street"
        if j in river_rows:
            C.LAYOUT["roads"].append(dict(axis="x", c=y, width=P.RW, **{"from": P.CITY_LEFT, "to": P.CITY_RIGHT}, kind=kind))
        else:
            C.LAYOUT["roads"].append(dict(axis="x", c=y, width=P.RW, **{"from": P.CITY_LEFT, "to": P.RIVER_X0}, kind=kind))
            C.LAYOUT["roads"].append(dict(axis="x", c=y, width=P.RW, **{"from": P.RIVER_X1, "to": P.CITY_RIGHT}, kind=kind))
    for i, x in enumerate(P.XS):
        if i == P.RIVER_COL:
            continue
        kind = "ring" if i in (0, len(P.XS) - 1) else "street"
        C.LAYOUT["roads"].append(dict(axis="y", c=x, width=P.RW, **{"from": P.CITY_BOTTOM, "to": P.CITY_TOP}, kind=kind))
    for cy in (P.HW_HALF / 2 + 0.5, -(P.HW_HALF / 2 + 0.5)):
        C.LAYOUT["roads"].append(dict(axis="x", c=cy, width=P.HW_HALF - 1.0, **{"from": P.HW_X0, "to": P.HW_X1}, kind="highway"))
    settle_points()
    # places and legs
    for name, p in P.PLACES.items():
        C.LAYOUT["places"][name] = dict(x=round(p["x"], 2), y=round(p["y"], 2), r=p["r"])
    for (lid, a, b, lo) in P.LEGS:
        C.LAYOUT["planned_legs"].append(dict(id=lid, a=a, b=b, min_by_road=lo))
    return flush_all()


def write_layout():
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, "harbour_layout.gd")
    data = json.dumps(C.LAYOUT, indent=1, sort_keys=False)
    with open(path, "w") as f:
        f.write("# Generated by tools/blender/harbour.py: do not edit. The harbour city's layout, in the shape of CityLayout.DATA plus its roads, roadblocks, bridges, places and the highway.\n")
        f.write("class_name HarbourLayout\nextends RefCounted\n\nconst DATA := " + data + "\n")
    L = C.LAYOUT
    print("LAYOUT", path, len(L["boxes"]), "boxes", len(L["posts"]), "posts", len(L["lights"]), "lights", len(L["wrecks"]), "wrecks", len(L["creature_spawns"]), "spawns")


def stats(objs):
    tris = prims = 0
    for ob in objs:
        me = ob.data
        tris += sum(len(p.vertices) - 2 for p in me.polygons)
        prims += max(1, len(me.materials))
    print("STATS objects=%d primitives=%d triangles=%d" % (len(objs), prims, tris))
    return tris, prims


def preview_scene(path, cam, target, lens=35, res=(1400, 800), warm=None, fog=0.018, warm_power=7000.0, ambient=0.04, sun=0.0, world="#0a1118"):
    from rk import hexcol
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = path
    sc.render.image_settings.file_format = "PNG"
    sc.view_settings.view_transform = "Standard"
    sc.eevee.taa_render_samples = 16
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes["Background"].inputs["Color"].default_value = hexcol(world)
    nt.nodes["Background"].inputs["Strength"].default_value = ambient
    if fog > 0:
        vol = nt.nodes.new("ShaderNodeVolumePrincipled")
        vol.inputs["Density"].default_value = fog
        vol.inputs["Color"].default_value = hexcol("#38444f")
        nt.links.new(vol.outputs["Volume"], nt.nodes["World Output"].inputs["Volume"])
    sc.world = w
    for ob in [o for o in sc.objects if o.type in ("LIGHT", "CAMERA")]:
        bpy.data.objects.remove(ob)
    if sun > 0:
        ld = bpy.data.lights.new("sun", "SUN")
        ld.energy = sun
        so = bpy.data.objects.new("sun", ld)
        sc.collection.objects.link(so)
        so.rotation_euler = (0.9, 0.2, 0.6)
    if warm:
        ld = bpy.data.lights.new("warm", "POINT")
        ld.energy = warm_power
        ld.color = (1.0, 0.72, 0.4)
        ld.shadow_soft_size = 0.5
        lo = bpy.data.objects.new("warm", ld)
        sc.collection.objects.link(lo)
        lo.location = warm
    cd = bpy.data.cameras.new("cam")
    cd.lens = lens
    cd.clip_end = 3000.0
    co = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(co)
    co.location = cam
    co.rotation_euler = (Vector(target) - Vector(cam)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = co
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", path)


def run_previews(outdir):
    os.makedirs(outdir, exist_ok=True)
    L = C.LAYOUT
    # top-down: the city, then the whole map, then the highway in three stretches; lit flat, no fog
    cx = (P.CITY_LEFT + P.CITY_RIGHT) / 2
    preview_scene(os.path.join(outdir, "city_top.png"), (cx, -20, 560), (cx, 0, 0), lens=40, res=(1500, 1100), fog=0.0, ambient=1.0, sun=2.5, world="#1c2630")
    mid = (P.ARENA["left"] + P.ARENA["right"]) / 2
    preview_scene(os.path.join(outdir, "map_top.png"), (mid, 0, 1500), (mid, 0, 0), lens=45, res=(2000, 700), fog=0.0, ambient=1.0, sun=2.5, world="#1c2630")
    # street level, dark, fog, one warm light: the avenue; a side street; the river; the school; the docks
    pl = L["places"]
    def street(name, cam, tgt, warm):
        # the dark still (fog, one warm light), and a lighter one beside it to read the geometry by
        preview_scene(os.path.join(outdir, name), cam, tgt, lens=28, warm=warm)
        preview_scene(os.path.join(outdir, name.replace(".png", "_lit.png")), cam, tgt, lens=28, fog=0.0, ambient=1.0, sun=1.6, world="#1c2630")
    street("street_avenue.png", (-100, 3.5, 2.4), (-20, 3.5, 3.0), (-96, 3.5, 5.5))
    street("street_old_town.png", (-96, 52, 2.4), (20, 52, 4.0), (-92, 56, 6.0))
    street("river_bridge.png", (-158, 8, 5.0), (-96, 0, 2.0), (-150, 8, 7.0))
    street("lift_bridge.png", (-90, -142, 4.0), (-130, -144, 14.0), (-96, -140, 7.0))
    street("school_field.png", (150, -96, 3.0), (160, -60, 5.0), (150, -90, 7.5))
    street("docks.png", (-30, -144, 3.0), (-10, -118, 6.0), (-26, -140, 7.0))
    street("ruck_truck.png", (-140, 141, 2.6), (-170, 146, 1.8), (-146, 141, 6.0))
    # highway: from the checkpoint, the toll plaza, the jam, the overpass and truck stop, the open road to the city
    hx1 = P.HW_X1
    street("hw_checkpoint.png", (hx1 - 10, 8, 2.2), (hx1 - 90, 5, 2.5), (hx1 - 14, 8, 6.0))
    street("hw_toll.png", (P.HW["toll_x1"] + 30, 8, 2.4), (P.HW["toll_x0"] - 10, 8, 3.0), (P.HW["toll_x1"] + 24, 8, 5.5))
    street("hw_jam.png", (P.HW["jam_x1"] + 4, 8, 2.4), (P.HW["jam_x0"], 8, 2.0), (P.HW["jam_x1"] + 2, 8, 5.5))
    street("hw_overpass.png", (P.HW["overpass_x"] + 45, 8, 2.6), (P.HW["overpass_x"], 4, 3.0), (P.HW["overpass_x"] + 40, 8, 6.0))
    street("hw_truckstop.png", (P.HW["overpass_x"] + 30, 24, 2.4), (P.HW["overpass_x"] - 10, 34, 2.0), (P.HW["overpass_x"] + 24, 24, 6.0))
    street("hw_open.png", (P.HW_X0 + 220, 8, 2.4), (P.HW_X0 + 120, 8, 2.6), (P.HW_X0 + 214, 8, 6.0))
    street("hw_mouth.png", (P.HW_X0 + 60, 3.8, 2.2), (P.HW_X0 - 30, 0, 2.8), (P.HW_X0 + 54, 4, 6.0))
    preview_scene(os.path.join(outdir, "hw_top_east.png"), (P.HW_X1 - 150, 0, 380), (P.HW_X1 - 150, 0, 0), lens=40, res=(1600, 700), fog=0.0, ambient=1.0, sun=2.5, world="#1c2630")
    preview_scene(os.path.join(outdir, "hw_top_mid.png"), (P.HW["overpass_x"], 20, 300), (P.HW["overpass_x"], 20, 0), lens=40, res=(1600, 700), fog=0.0, ambient=1.0, sun=2.5, world="#1c2630")


if __name__ == "__main__":
    objs = build()
    if "nolayout" not in ARGS:
        write_layout()
    stats(objs)
    if "noglb" not in ARGS:
        export(os.path.join(OUT_DIR, "harbour_city.glb"), objs, extra=dict(export_apply=True))
    if "preview" in ARGS:
        run_previews(ARGS[ARGS.index("preview") + 1])

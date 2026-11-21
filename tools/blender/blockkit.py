"""The block kit for the harbour city: what goes inside one block, in the quarter's look, as plain geometry.

A kit function takes the block's group name `g` and its inner rectangle (the block's sidewalk slab
less the 3 m strip all round) and fills it with buildings, yards, props, colliders and spawns through
city.py's own helpers (`import city as C` shares its materials, its layout record and its random
stream). Everything is built in game coordinates. Each kit draws only from C.RNG, which harbour.py
seeds per block, so a regeneration is the same city.

Buildings are made by `bldg`, the one place a detail pass can change what every building looks like
(bevels, window frames, textures): it, `window_band` and `bldg_roof` are the only places that draw a
facade. Props are made by the small functions below the buildings (`crate`, `container`, `fence`,
`wreck_lp`), the one place a prop pass can land.
"""
import math
import bpy
import city as C
from mathutils import Matrix

R = C.RNG
C_SW = 3.0   # the sidewalk strip the kits are inset by (harbour_plan.SW)

SHOP_WORDS = ["LAUNDRY", "HARDWARE", "NOODLES", "BAKERY", "CINEMA", "TAILOR", "GROCER", "BOOKS", "PIANO", "TEA", "FISH", "CLINIC", "OPTICIAN", "TOYS", "RADIO", "SHOES"]
NEON = ["neon_red", "neon_teal", "neon_amber", "neon_pink"]
AWN = ["awn0", "awn1", "awn2"]
WALLS = ["wall0", "wall1", "wall2", "wall3", "wall4", "wall5"]
BRICKS = ["brick0", "brick1", "brick2"]
PAINTS = ["paint0", "paint1", "paint2", "paint3"]
CONTAINER_MATS = ["container0", "container1", "container2", "container3"]


# ---------------------------------------------------------------- small geometry

def _cube(x0, y0, z0, x1, y1, z1):
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return v, f


def _frustum(bot, top, z0, z1):
    """A box that narrows: `bot` and `top` are (x0, y0, x1, y1) at heights z0 and z1."""
    b0, b1, b2, b3 = (bot[0], bot[1]), (bot[2], bot[1]), (bot[2], bot[3]), (bot[0], bot[3])
    t0, t1, t2, t3 = (top[0], top[1]), (top[2], top[1]), (top[2], top[3]), (top[0], top[3])
    v = [(*b0, z0), (*b1, z0), (*b2, z0), (*b3, z0), (*t0, z1), (*t1, z1), (*t2, z1), (*t3, z1)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return v, f


def gable(g, m, x0, y0, x1, y1, z0, rise):
    """A pitched roof with its ridge along x."""
    bm = C._bm(g, m)
    cy = (y0 + y1) / 2
    V = bm.verts.new
    a = [V((x0, y0, z0)), V((x1, y0, z0)), V((x1, cy, z0 + rise)), V((x0, cy, z0 + rise))]
    b = [V((x1, y1, z0)), V((x0, y1, z0)), V((x0, cy, z0 + rise)), V((x1, cy, z0 + rise))]
    bm.faces.new(a)
    bm.faces.new(b)
    w = [V((x0, y1, z0)), V((x0, y0, z0)), V((x0, cy, z0 + rise))]
    e = [V((x1, y0, z0)), V((x1, y1, z0)), V((x1, cy, z0 + rise))]
    bm.faces.new(w)
    bm.faces.new(e)


def split_len(a, b, n, gap, rng=None):
    """n intervals across [a, b] with `gap` between them; widths vary a little."""
    rng = rng or R
    total = (b - a) - gap * (n - 1)
    ws = [rng.uniform(0.8, 1.25) for _ in range(n)]
    s = sum(ws)
    out, x = [], a
    for w in ws:
        ww = total * w / s
        out.append((x, x + ww))
        x += ww + gap
    return out


def faces_reaching(b, inner, tol=0.6):
    """The faces of footprint b = (x0, y0, x1, y1) that stand on the inner rectangle's edge (the street sides)."""
    out = []
    if b[1] - inner[1] < tol:
        out.append("S")
    if inner[3] - b[3] < tol:
        out.append("N")
    if inner[2] - b[2] < tol:
        out.append("E")
    if b[0] - inner[0] < tol:
        out.append("W")
    return tuple(out)


# ---------------------------------------------------------------- buildings (the one place a facade is drawn)

def sign3(g, m, text, f, u, z, size):
    """Raised lettering, cheaper than city.py's: a coarse curve, thin extrusion."""
    cu = bpy.data.curves.new("t", "FONT")
    cu.body = text
    cu.size = size
    cu.extrude = 0.03
    cu.resolution_u = 1
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    ob = bpy.data.objects.new("t", cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    px, py = f.p(u, 0.12)
    yaw = math.atan2(f.n[1], f.n[0]) + math.pi / 2
    mx = Matrix.Translation((px, py, z)) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X")
    C.add_mesh(g, m, [v.co[:] for v in me.vertices], [tuple(p.vertices) for p in me.polygons], mx)
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    bpy.data.meshes.remove(me)


def window_band(g, f, floors, floor_h, gf_h, lit_p, wide=False, skip=False):
    """Every upper-floor window of one wall face: a quad each, one sill strip per floor."""
    L = f.L
    n_cols = int((L - 1.4) // 3.2)
    if n_cols < 1 or skip:
        return
    w = 1.4 if wide else 0.62
    for fl in range(floors):
        z0 = gf_h + fl * floor_h + 0.55
        for k in range(n_cols):
            u = 0.7 + (L - 1.4) * (k + 0.5) / n_cols
            if R.random() < lit_p:
                m = R.choices(["lit_warm", "lit_cool", "lit_green"], weights=[6, 3, 1])[0]
            else:
                m = "glass"
            C.fquad(g, m, f, u - w, u + w, z0, z0 + 1.7, 0.03)
        C.fbox(g, "trim", f, 0.0, L, z0 - 0.14, z0, 0.0, 0.14)


def bldg_roof(g, x0, y0, x1, y1, h, stuff=True):
    t = 0.35
    C.box(g, "trim", x0, y0, h, x1, y0 + t, h + 0.7)
    C.box(g, "trim", x0, y1 - t, h, x1, y1, h + 0.7)
    C.box(g, "trim", x0, y0 + t, h, x0 + t, y1 - t, h + 0.7)
    C.box(g, "trim", x1 - t, y0 + t, h, x1, y1 - t, h + 0.7)
    C.box(g, "roof", x0 + t, y0 + t, h, x1 - t, y1 - t, h + 0.05)
    if stuff and (x1 - x0) > 6 and (y1 - y0) > 6:
        for _ in range(R.randint(1, 3)):
            bx = R.uniform(x0 + 1.5, x1 - 3.5)
            by = R.uniform(y0 + 1.5, y1 - 3.0)
            C.box(g, "metal", bx, by, h + 0.05, bx + R.uniform(1.0, 2.4), by + R.uniform(1.0, 1.8), h + R.uniform(0.8, 1.6))
        if h >= 20:
            C.cyl(g, "metal", x1 - 1.5, y1 - 1.5, h, h + 5.0, 0.07, 5)
            C.sphere(g, "beacon", x1 - 1.5, y1 - 1.5, h + 5.1, 0.22, 6)


def bldg(g, x0, y0, x1, y1, h, wall, lit_p=0.2, shop=(), sign=None, awning=None, floor_h=3.4, party=(), wide=False, collide=True, roof=True):
    """A building: walls, windows, a parapet. `shop`: faces with a shopfront; `party`: faces that stand flush on a neighbour (no windows)."""
    C.box(g, wall, x0, y0, 0.0, x1, y1, h)
    faces = C.faces_of(x0, y0, x1, y1)
    gf_h = 3.8
    floors = max(1, int((h - gf_h) // floor_h))
    for key, f in faces.items():
        L = f.L
        if key in party:
            continue
        if key in shop:
            C.fquad(g, "shopglass", f, 1.0, L - 1.0, 0.5, 3.0)
            C.fbox(g, "trim", f, 0.7, L - 0.7, 3.0, 3.3, 0.0, 0.18)
            if R.random() < 0.5:
                panes = max(2, int((L - 4.0) // 3.0))
                pw = (L - 4.0) / panes
                for pk in range(panes):
                    if R.random() < 0.8:
                        C.fquad(g, "lit_shop", f, 2.0 + pk * pw + 0.15, 2.0 + (pk + 1) * pw - 0.15, 0.9, 2.5, 0.04)
            C.fbox(g, "door", f, L * 0.5 - 0.6, L * 0.5 + 0.6, 0.0, 2.3, 0.0, 0.1)
            if awning:
                C.fbox(g, awning, f, 1.2, L - 1.2, 3.3, 3.55, 0.0, 1.5)
        else:
            n_w = int((L - 1.6) // 3.6)
            for k in range(n_w):
                u = 0.8 + (L - 1.6) * (k + 0.5) / n_w
                C.fquad(g, "glass", f, u - 0.6, u + 0.6, 1.0, 2.5)
            if R.random() < 0.7 and L > 4:
                C.fbox(g, "door", f, L * 0.5 - 0.6, L * 0.5 + 0.6, 0.0, 2.2, 0.0, 0.08)
        window_band(g, f, floors, floor_h, gf_h, lit_p, wide=wide)
    if roof:
        bldg_roof(g, x0, y0, x1, y1, h)
    if collide:
        C.collider(x0, y0, x1, y1)
    if sign and shop:
        txt, mname = sign
        f = faces[shop[0]]
        sign3(g, mname, txt, f, f.L / 2, 3.85, 0.8)
    return faces


def plain_shed(g, x0, y0, x1, y1, h, wall="wall3", door_face="S"):
    """A bare box with a roller door: warehouses, huts."""
    C.box(g, wall, x0, y0, 0.0, x1, y1, h)
    C.box(g, "roof", x0 - 0.2, y0 - 0.2, h, x1 + 0.2, y1 + 0.2, h + 0.3)
    f = C.faces_of(x0, y0, x1, y1)[door_face]
    n = max(1, int(f.L // 9))
    for k in range(n):
        u = f.L * (k + 0.5) / n
        C.fquad(g, "door", f, u - 2.0, u + 2.0, 0.0, 4.0, 0.05)
    C.collider(x0, y0, x1, y1)


# ---------------------------------------------------------------- props

def crate(g, x, y, sx, sy, h, m="metal", kind="prop"):
    C.box(g, m, x - sx / 2, y - sy / 2, 0.0, x + sx / 2, y + sy / 2, h)
    C.collider(x - sx / 2, y - sy / 2, x + sx / 2, y + sy / 2, kind)


def container(g, x, y, long_axis="x", levels=1, m=None):
    """A shipping container stack (12.2 x 2.5 m, 2.6 m a level), one collider for the stack."""
    L, W, H = 12.2, 2.5, 2.6
    sx, sy = (L, W) if long_axis == "x" else (W, L)
    for lv in range(levels):
        C.box(g, m or R.choice(CONTAINER_MATS), x - sx / 2, y - sy / 2, lv * H, x + sx / 2, y + sy / 2, (lv + 1) * H)
    C.collider(x - sx / 2, y - sy / 2, x + sx / 2, y + sy / 2, "prop")


def fence(g, xa, ya, xb, yb, gaps=(), h=2.0, collide=True):
    """A chain fence from a to b (axis-aligned): posts and rails, a thin collider per stretch between the gaps.
    `gaps` are (u0, u1) distances along the run that stay open."""
    length = math.hypot(xb - xa, yb - ya)
    if length < 0.1:
        return
    dx, dy = (xb - xa) / length, (yb - ya) / length
    cuts = [0.0]
    for (u0, u1) in sorted(gaps):
        cuts += [u0, u1]
    cuts.append(length)
    for k in range(0, len(cuts), 2):
        u0, u1 = cuts[k], cuts[k + 1]
        if u1 - u0 < 0.3:
            continue
        ax, ay = xa + dx * u0, ya + dy * u0
        bx, by = xa + dx * u1, ya + dy * u1
        n = max(1, int((u1 - u0) / 3.0))
        for i in range(n + 1):
            t = i / n
            C.cyl(g, "metal", ax + (bx - ax) * t, ay + (by - ay) * t, 0.0, h, 0.04, 4)
        C.rbox(g, "metal", (ax + bx) / 2, (ay + by) / 2, u1 - u0, 0.05, math.atan2(dy, dx), h - 0.1, h)
        C.rbox(g, "metal", (ax + bx) / 2, (ay + by) / 2, u1 - u0, 0.05, math.atan2(dy, dx), 0.4, 0.46)
        if collide:
            C.collider(min(ax, bx) - 0.3, min(ay, by) - 0.3, max(ax, bx) + 0.3, max(ay, by) + 0.3, "fence")


def ground_patch(g, m, x0, y0, x1, y1, z0=0.12, z1=0.15):
    C.box(g, m, x0, y0, z0, x1, y1, z1)


# ---------------------------------------------------------------- vehicles (low polygon, as the fog hides the rest)

CAR_SIZE = {"sedan": (4.0, 1.8), "van": (4.8, 2.0), "truck": (15.0, 2.7), "bus": (11.0, 2.6)}


def _vehicle_parts(kind):
    """Local-frame parts (forward +x): (material key, verts, faces). 'paint' and 'glass' are swapped by the caller."""
    parts = []

    def add(mk, vf):
        parts.append((mk, vf[0], vf[1]))

    if kind == "sedan":
        add("paint", _cube(-2.0, -0.9, 0.3, 2.0, 0.9, 0.9))
        add("glass", _frustum((-1.2, -0.8, 0.9, 0.8), (-0.8, -0.65, 0.3, 0.65), 0.9, 1.4))
        add("paint", _cube(-0.8, -0.65, 1.4, 0.3, 0.65, 1.45))
        wx, wy, wr = 1.25, 0.82, 0.34
    elif kind == "van":
        add("paint", _cube(-2.4, -1.0, 0.3, 2.4, 1.0, 2.1))
        add("glass", _frustum((1.2, -0.95, 2.4, 0.95), (1.9, -0.9, 2.4, 0.9), 1.3, 1.9))
        wx, wy, wr = 1.5, 0.9, 0.38
    elif kind == "truck":
        add("paint", _cube(-7.5, -1.3, 0.8, 4.0, 1.3, 3.6))       # trailer
        add("paint", _cube(4.3, -1.25, 0.6, 7.5, 1.25, 2.2))      # cab
        add("glass", _frustum((6.1, -1.2, 7.5, 1.2), (6.5, -1.1, 7.5, 1.1), 2.2, 3.1))
        wx, wy, wr = 5.8, 1.1, 0.5
        for ax in (-5.8, -3.8, 5.8):
            for sy in (-1, 1):
                add("tyre", _cube(ax - wr, sy * wy - 0.2, 0.0, ax + wr, sy * wy + 0.2, wr * 2))
        return parts
    else:
        raise ValueError(kind)
    for sx in (wx, -wx):
        for sy in (wy, -wy):
            add("tyre", _cube(sx - wr, sy - 0.12, 0.0, sx + wr, sy + 0.12, wr * 2))
    return parts


def wreck_lp(g, x, y, heading, kind="sedan", paint=None, burnt=False, lights_on=False, flicker=0.0, record=True):
    """A stalled or wrecked vehicle. `heading` snaps to the nearest quarter turn for its collider (the model leans a few
    degrees off it), as city.py's wreck does. Returns the (hx, hy) half extents of its collider."""
    paint = paint or R.choice(PAINTS)
    q = int(round(heading / (math.pi / 2))) % 4
    vis = q * math.pi / 2 + R.uniform(-0.07, 0.07)
    mx = Matrix.Translation((x, y, 0.02)) @ Matrix.Rotation(vis, 4, "Z")
    for mk, verts, faces in _vehicle_parts(kind):
        name = {"paint": ("char" if burnt else paint), "glass": "glass", "tyre": "tyre"}[mk]
        C.add_mesh(g, name, verts, faces, mx)
    L, W = CAR_SIZE[kind]
    hx, hy = (L / 2, W / 2) if q % 2 == 0 else (W / 2, L / 2)
    cx, cy = x, y
    C.collider(cx - hx, cy - hy, cx + hx, cy + hy, "wreck")
    if record:
        C.LAYOUT["wrecks"].append(dict(x=round(x, 2), y=round(y, 2), yaw=round(vis, 3), kind=kind))
    if lights_on:
        c, s = math.cos(vis), math.sin(vis)
        nx, ny = x + c * (L / 2), y + s * (L / 2)
        C.light(nx, ny, 0.7, [1.0, 0.95, 0.8], 14.0, 34.0, flicker, "spot", dx=c, dy=s, angle=22.0, fog=3.0)
        C.quad(g, "headlamp", (nx, ny - 0.5 * c, 0.6), (nx, ny + 0.5 * c, 0.6), (nx, ny + 0.5 * c, 0.8), (nx, ny - 0.5 * c, 0.8))
    return (cx - hx, cy - hy, cx + hx, cy + hy)


# ---------------------------------------------------------------- spawns

def _inside_boxes(x, y, pad=1.2):
    for b in C.LAYOUT["boxes"]:
        if b["x0"] - pad < x < b["x1"] + pad and b["y0"] - pad < y < b["y1"] + pad:
            return True
    for p in C.LAYOUT["posts"]:
        if abs(p["x"] - x) < p["r"] + pad and abs(p["y"] - y) < p["r"] + pad:
            return True
    return False


def add_spawns(rect, n=3):
    """Hiding places for creatures on the block's sidewalk strip and in its gaps: points on the strip clear of colliders."""
    x0, y0, x1, y1 = rect
    got, tries = 0, 0
    while got < n and tries < 60:
        tries += 1
        side = R.randrange(4)
        t = R.random()
        if side == 0:
            x, y = x0 + 1.5 + t * (x1 - x0 - 3.0), y0 + 1.5
        elif side == 1:
            x, y = x0 + 1.5 + t * (x1 - x0 - 3.0), y1 - 1.5
        elif side == 2:
            x, y = x0 + 1.5, y0 + 1.5 + t * (y1 - y0 - 3.0)
        else:
            x, y = x1 - 1.5, y0 + 1.5 + t * (y1 - y0 - 3.0)
        if not _inside_boxes(x, y):
            C.LAYOUT["creature_spawns"].append(dict(x=round(x, 1), y=round(y, 1)))
            got += 1


# ---------------------------------------------------------------- the kits

def _sign():
    return (R.choice(SHOP_WORDS), R.choice(NEON))


def k_towers(g, inner):
    x0, y0, x1, y1 = inner
    n = R.choice([2, 2, 3])
    for (a, b) in split_len(x0, x1, n, 2.0):
        d0 = y0 + R.choice([0.0, 0.0, 6.0])
        d1 = y1 - R.choice([0.0, 0.0, 6.0])
        h = R.choice([22.0, 28.0, 34.0, 40.0])
        fb = (a, d0, b, d1)
        shop = faces_reaching(fb, inner)
        bldg(g, a, d0, b, d1, h, R.choice(WALLS), lit_p=R.uniform(0.12, 0.25), shop=shop[:2], sign=_sign() if shop and R.random() < 0.7 else None, awning=R.choice(AWN), wide=R.random() < 0.4)


def k_brick_row(g, inner):
    x0, y0, x1, y1 = inner
    alley = 5.0 if (y1 - y0) > 22 else 0.0
    mid = (y0 + y1) / 2
    rows = [(y0, mid - alley / 2, "S"), (mid + alley / 2, y1, "N")] if alley else [(y0, y1, "S")]
    if alley:
        for xe in (x0, x1):
            fence(g, xe, mid - alley / 2, xe, mid + alley / 2)
    for (ya, yb, face) in rows:
        n = R.randint(3, 5)
        iv = split_len(x0, x1, n, 0.0)
        for k, (a, b) in enumerate(iv):
            floors = R.randint(3, 5)
            h = 3.8 + floors * 3.4 + R.choice([0, 0.4])
            party = tuple(p for p, ok in (("W", k > 0), ("E", k < n - 1)) if ok)
            bldg(g, a, ya, b, yb, h, R.choice(BRICKS), lit_p=R.uniform(0.15, 0.32), shop=(face,), sign=_sign(), awning=R.choice(AWN), party=party)


def k_warehouse_yard(g, inner):
    """A warehouse across the block's back and a fenced yard in front with one gate: a cul-de-sac, nothing to drive through."""
    x0, y0, x1, y1 = inner
    south = R.random() < 0.5
    dep = (y1 - y0) * 0.5
    h = R.choice([8.0, 9.0, 10.0])
    if south:
        plain_shed(g, x0, y0, x1, y0 + dep, h, R.choice(WALLS), "S")
        yard = (x0, y0 + dep, x1, y1)
        street_y = y1
    else:
        plain_shed(g, x0, y1 - dep, x1, y1, h, R.choice(WALLS), "N")
        yard = (x0, y0, x1, y1 - dep)
        street_y = y0
    gate_u = R.uniform(6, (x1 - x0) - 14)
    fence(g, x0, street_y, x1, street_y, gaps=[(gate_u, gate_u + 8.0)])
    fence(g, x0, yard[1], x0, yard[3])
    fence(g, x1, yard[1], x1, yard[3])
    for _ in range(R.randint(2, 4)):
        cx = R.uniform(yard[0] + 8, yard[2] - 8)
        cy = R.uniform(yard[1] + 4, yard[3] - 4)
        if abs(cx - (x0 + gate_u + 4)) < 9 and abs(cy - street_y) < 9:
            continue
        container(g, cx, cy, R.choice("xy"), R.choice([1, 1, 2]))
    wreck_lp(g, (yard[0] + yard[2]) / 2, (yard[1] + yard[3]) / 2, 0.0, "truck", R.choice(PAINTS), burnt=R.random() < 0.4)


def k_sealed_warehouse(g, inner):
    """One warehouse over the whole block, sidewalk strips included: nothing to drive round it (shuts the far-bank pocket)."""
    x0, y0, x1, y1 = inner
    plain_shed(g, x0 - C_SW, y0 - C_SW, x1 + C_SW, y1 + C_SW, 9.0, "wall4", "N")


def k_houses(g, inner):
    x0, y0, x1, y1 = inner
    d = (y1 - y0)
    rows = [(y0, y0 + min(11.0, d * 0.4)), (y1 - min(11.0, d * 0.4), y1)]
    for xe in (x0, x1):
        fence(g, xe, rows[0][1], xe, rows[1][0])
    for (ya, yb) in rows:
        n = R.randint(3, 4)
        for (a, b) in split_len(x0, x1, n, 2.0):
            ha = R.choice([4.2, 4.8, 5.6])
            C.box(g, R.choice(WALLS), a, ya, 0.0, b, yb, ha)
            gable(g, "roof", a - 0.3, ya - 0.3, b + 0.3, yb + 0.3, ha, R.uniform(1.4, 2.2))
            S = "S" if ya == rows[0][0] else "N"
            f = C.faces_of(a, ya, b, yb)[S]
            C.fquad(g, R.choice(["lit_warm", "glass", "glass"]), f, 1.0, 2.4, 1.2, 2.5, 0.03)
            C.fquad(g, "glass", f, f.L - 2.4, f.L - 1.0, 1.2, 2.5, 0.03)
            C.fbox(g, "door", f, f.L / 2 - 0.5, f.L / 2 + 0.5, 0.0, 2.2, 0.0, 0.08)
            C.collider(a, ya, b, yb)
            if R.random() < 0.6:
                tx = (a + b) / 2 + R.uniform(-1.5, 1.5)
                ty = (yb + 3.0) if S == "S" else (ya - 3.0)
                if (S == "S" and ty < y1 - 13) or (S == "N" and ty > y0 + 13):
                    C.tree(g, tx, ty)


def k_lot(g, inner):
    x0, y0, x1, y1 = inner
    ground_patch(g, "dirt", x0 - 3.0, y0 - 3.0, x1 + 3.0, y1 + 3.0)
    open_side = R.choice("SNWE")
    for side, (a, b, c, d) in {"S": (x0, y0, x1, y0), "N": (x0, y1, x1, y1), "W": (x0, y0, x0, y1), "E": (x1, y0, x1, y1)}.items():
        length = math.hypot(c - a, d - b)
        gaps = []
        if side == open_side:
            g1 = R.uniform(4, max(5, length - 14))
            gaps = [(g1, g1 + 7.0)]
        fence(g, a, b, c, d, gaps=gaps)
    for _ in range(R.randint(1, 2)):
        C.barrel(g, R.uniform(x0 + 4, x1 - 4), R.uniform(y0 + 4, y1 - 4), fire=True)
    for _ in range(R.randint(2, 3)):
        wreck_lp(g, R.uniform(x0 + 6, x1 - 6), R.uniform(y0 + 5, y1 - 5), R.choice([0.0, math.pi / 2, math.pi, 1.5 * math.pi]), R.choice(["sedan", "van"]), burnt=R.random() < 0.4)
    for _ in range(2):
        crate(g, R.uniform(x0 + 4, x1 - 4), R.uniform(y0 + 4, y1 - 4), R.uniform(1.2, 2.4), R.uniform(1.0, 1.6), R.uniform(0.8, 1.6), "rust")
    plain_shed(g, x1 - 12, y0 + 3, x1 - 4, y0 + 9, 3.6, "wall5", "N")


def k_park(g, inner):
    x0, y0, x1, y1 = inner
    C.box(g, "grass", x0 - 3.0, y0 - 3.0, 0.12, x1 + 3.0, y1 + 3.0, 0.16)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    C.box(g, "concrete", cx - 2.0, y0, 0.16, cx + 2.0, y1, 0.18)
    C.box(g, "concrete", x0, cy - 2.0, 0.16, x1, cy + 2.0, 0.18)
    C.cyl(g, "concrete", cx, cy, 0.16, 0.9, 3.4, 18)
    C.cyl(g, "water", cx, cy, 0.7, 0.8, 3.0, 18)
    C.post(cx, cy, 3.4, "fountain")
    for _ in range(9):
        tx, ty = R.uniform(x0 + 2, x1 - 2), R.uniform(y0 + 2, y1 - 2)
        if abs(tx - cx) < 4 or abs(ty - cy) < 4:
            continue
        C.tree(g, tx, ty)
    for (bx, by) in ((cx - 6, cy - 3.5), (cx + 6, cy + 3.5)):
        C.rbox(g, "rust", bx, by, 1.8, 0.5, 0.0, 0.45, 0.5)
        C.post(bx, by, 0.9, "bench")
    open_side = R.choice("SNWE")
    for side, (a, b, c, d) in {"S": (x0, y0, x1, y0), "N": (x0, y1, x1, y1), "W": (x0, y0, x0, y1), "E": (x1, y0, x1, y1)}.items():
        length = math.hypot(c - a, d - b)
        mid = length / 2
        fence(g, a, b, c, d, gaps=[(mid - 3.0, mid + 3.0)] if side == open_side else [], h=1.6)


def k_parking(g, inner):
    x0, y0, x1, y1 = inner
    x0 += R.uniform(0, 3)
    x1 -= R.uniform(0, 3)
    h = 12.8
    C.box(g, "concrete", x0, y0, 0.0, x1, y1, h)
    faces = C.faces_of(x0, y0, x1, y1)
    for key, f in faces.items():
        for lv in range(4):
            z0 = 0.6 + lv * 3.2
            C.fquad(g, "glass", f, 0.6, f.L - 0.6, z0, z0 + 2.2, 0.04)
            C.fbox(g, "trim", f, 0.0, f.L, z0 + 2.2, z0 + 2.45, 0.0, 0.2)
        for u in range(3, int(f.L) - 2, 6):
            C.fbox(g, "trim", f, u - 0.35, u + 0.35, 0.0, h, 0.0, 0.3)
    bldg_roof(g, x0, y0, x1, y1, h, stuff=False)
    C.collider(x0, y0, x1, y1)
    f = faces["S"]
    sign3(g, "neon_teal", "P", f, f.L / 2, h - 1.5, 1.4)


def k_school(g, inner):
    """The field hospital: a school with a floodlit field. Its lights are tagged so the story can put them out."""
    x0, y0, x1, y1 = inner
    bldg(g, x0, y0, x1 - 12, y0 + 11, 11.0, "brick0", lit_p=0.55, shop=("S",), floor_h=3.4, awning="awn1")
    bldg(g, x1 - 12, y0, x1, y0 + 15, 9.0, "wall3", lit_p=0.3)
    f = C.faces_of(x0, y0, x1 - 12, y0 + 11)["S"]
    C.fbox(g, "neon_red", f, f.L / 2 - 1.5, f.L / 2 + 1.5, 7.2, 8.0, 0.0, 0.2)
    C.fbox(g, "neon_red", f, f.L / 2 - 0.4, f.L / 2 + 0.4, 6.2, 9.0, 0.0, 0.2)
    ground_patch(g, "grass", x0, y0 + 16, x1, y1)
    px = [x0 + 6, x1 - 6, x0 + 6, x1 - 6]
    py = [y0 + 18, y0 + 18, y1 - 2, y1 - 2]
    for (px_, py_) in zip(px, py):
        C.cyl(g, "metal", px_, py_, 0.0, 8.0, 0.12, 6)
        C.box(g, "lamp_head", px_ - 0.5, py_ - 0.3, 7.8, px_ + 0.5, py_ + 0.3, 8.1)
        C.post(px_, py_, 0.25, "lamp")
        C.light(px_, py_, 7.6, [1.0, 0.92, 0.7], 9.0, 26.0, 0.05, "omni", fog=2.0)
        C.LAYOUT["lights"][-1]["tag"] = "hospital_flood"
    for k in range(4):
        tx = x0 + 8 + k * 9.5
        C.box(g, "awn0" if k % 2 else "awn2", tx - 3.0, y0 + 22, 0.0, tx + 3.0, y0 + 27, 2.6)
        C.collider(tx - 3.0, y0 + 22, tx + 3.0, y0 + 27, "prop")
    for gx in (x0 + 4, x1 - 8):
        crate(g, gx, y1 - 5, 2.0, 1.0, 1.2, "metal")
    fence(g, x0, y1, x1, y1, gaps=[(14, 22)])
    fence(g, x0, y0 + 11, x0, y1)
    fence(g, x1, y0 + 15, x1, y1)
    wreck_lp(g, x0 + 20, y0 + 14, 0.0, "van", "paint3")


def k_fuel_depot(g, inner):
    x0, y0, x1, y1 = inner
    ground_patch(g, "concrete", x0 - 3.0, y0 - 3.0, x1 + 3.0, y1 + 3.0, 0.12, 0.14)
    cy = (y0 + y1) / 2 + 3.0
    for k, cx in enumerate((x0 + 9, x0 + 22, x0 + 35)):
        C.cyl(g, "metal", cx, cy, 0.14, 9.0, 5.2, 16)
        C.cyl(g, "trim", cx, cy, 9.0, 9.4, 5.3, 16)
        C.post(cx, cy, 5.3, "tank")
        C.box(g, "rust", cx - 0.2, cy - 6.0, 0.14, cx + 0.2, cy - 5.2, 6.5)
    C.box(g, "metal", x0 + 6, cy - 7.5, 0.14, x1 - 5, cy - 7.1, 0.7)
    plain_shed(g, x1 - 9, y0, x1, y0 + 6, 3.6, "wall5", "S")
    fence(g, x0, y0, x1, y0, gaps=[(8, 16)])
    fence(g, x0, y1, x1, y1)
    fence(g, x0, y0, x0, y1)
    fence(g, x1, y0, x1, y1)
    wreck_lp(g, x0 + 28, y0 + 4.5, math.pi, "truck", "paint3", burnt=True)
    C.barrel(g, x0 + 4, y1 - 3, fire=True)
    C.light(x0 + 14, y0 + 6, 4.0, [1.0, 0.9, 0.65], 4.5, 14.0, 0.1, "omni", fog=1.2)


def container_row(g, x0, x1, ry, keep=None):
    """Tile [x0, x1] at y = ry with container stacks end to end, the remainder closed by a crate: no gap but the ones `keep` leaves."""
    n = max(1, int((x1 - x0) // 12.2))
    rem = (x1 - x0) - n * 12.2
    for k in range(n):
        if keep is None or keep(k):
            container(g, x0 + 6.1 + k * 12.2, ry, "x", R.choice([1, 2, 2, 3]))
    if rem > 0.2:
        crate(g, x1 - rem / 2, ry, rem, 2.5, 2.6, R.choice(CONTAINER_MATS))


def k_container_yard(g, inner):
    """Rows of container stacks with E-W aisles, walled at the ends and along the north side, with one way in on the
    south: a cul-de-sac, so a yard never opens a way round a roadblock."""
    x0, y0, x1, y1 = inner
    n = max(1, int((x1 - x0) // 12.2))
    skip = R.randrange(n)
    container_row(g, x0, x1, y0 + 3.0, keep=lambda k: k != skip)
    container_row(g, x0, x1, y0 + 14.0, keep=lambda k: R.random() < 0.8)
    container_row(g, x0, x1, y1 - 3.0)
    fence(g, x0, y0, x0, y1)
    fence(g, x1, y0, x1, y1)
    fence(g, x0, y1, x1, y1)


def k_dock_crane(g, inner):
    x0, y0, x1, y1 = inner
    cx = (x0 + x1) / 2
    for dx in (-9.0, 9.0):
        for dy in (2.0, 12.0):
            C.box(g, "metal", cx + dx - 0.7, y0 + dy - 0.7, 0.0, cx + dx + 0.7, y0 + dy + 0.7, 24.0)
            C.collider(cx + dx - 0.7, y0 + dy - 0.7, cx + dx + 0.7, y0 + dy + 0.7, "prop")
    C.box(g, "rust", cx - 10.0, y0 + 0.5, 23.0, cx + 10.0, y0 + 13.5, 25.0)
    C.box(g, "metal", cx - 1.0, y0 - 24.0, 24.0, cx + 1.0, y0 + 13.5, 25.2)
    C.box(g, "beacon", cx - 0.3, y0 - 24.0, 25.2, cx + 0.3, y0 - 23.4, 25.8)
    for k in range(3):
        container(g, x0 + 10 + k * 14, y1 - 4.0, "x", R.choice([1, 2]))
    container(g, x0 + 8, y0 + 22, "x", 1)
    container(g, x1 - 8, y0 + 22, "x", 2)
    fence(g, x0, y0, x0, y1)
    fence(g, x1, y0, x1, y1)
    fence(g, x0, y1, x1, y1)


def k_lift_yard(g, inner):
    """The lift bridge's control house on the east bank, with a small yard."""
    x0, y0, x1, y1 = inner
    bldg(g, x0 + 1, y0 + 1, x0 + 9, y0 + 9, 9.0, "wall2", lit_p=0.5, roof=True)
    f = C.faces_of(x0 + 1, y0 + 1, x0 + 9, y0 + 9)["N"]
    C.fquad(g, "lit_cool", f, 1.0, f.L - 1.0, 6.0, 8.2, 0.05)
    ground_patch(g, "concrete", x0, y0, x1, y1, 0.12, 0.14)
    for k in range(3):
        container(g, x0 + 14 + k * 13, y1 - 4.0, "x", R.choice([1, 2]))
    wreck_lp(g, x0 + 22, y0 + 8, 0.0, "sedan", "paint1")
    C.barrel(g, x0 + 12, y0 + 12, fire=True)
    fence(g, x0, y1, x1, y1)
    fence(g, x0, y0, x0, y1)
    fence(g, x1, y0, x1, y1)


KITS = {
    "towers": k_towers, "brick_row": k_brick_row, "warehouse_yard": k_warehouse_yard, "houses": k_houses, "lot": k_lot,
    "park": k_park, "parking": k_parking, "school": k_school, "fuel_depot": k_fuel_depot, "container_yard": k_container_yard,
    "dock_crane": k_dock_crane, "lift_yard": k_lift_yard, "sealed_warehouse": k_sealed_warehouse,
}

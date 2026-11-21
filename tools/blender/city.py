"""The city of Hollow Hours: four blocks of a sealed-off quarter, built straight in game coordinates.

x, y are map metres (the same numbers the GDScript sim uses; glTF turns y into Godot -Z, which is
exactly how the game maps them), Blender Z is up. Writes:
  assets/models/city.glb                   one mesh per block plus roads and props, flat-colour materials
  scripts/game/city_layout.gd              the colliders, roads, lamps, lights, wrecks and spawn points as a const
Material names are the contract with scripts/game/city.gd, which swaps the road, sidewalk and
glass materials for the wet and reflective ones. Run (headless, foreground):
  Blender --background --python-exit-code 1 --python tools/blender/city.py -- [preview]

Layout (metres): streets 14 wide, three east-west (y = -48, 0, 48) and three north-south
(x = -64, 0, 64), blocks 50 x 34 between them, a 3 m sidewalk around every block.
  NW dense towers and brick, NE a gas station and parking lot, SW a dead park, SE dense with an alley.
"""
import sys, os, math, json, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, Matrix
from rk import *

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RNG = random.Random(11)
G = {}  # group -> {material name -> bmesh}
MATS = {}
LAYOUT = dict(
    arena=dict(left=-70.0, right=70.0, bottom=-54.0, top=54.0),
    boxes=[], posts=[], lamps=[], lights=[], wrecks=[], blocks=[], creature_spawns=[], fires=[],
    player_start=dict(x=-30.0, y=-2.5, angle=0.0),
)

# The way out: a gap in the west perimeter wall where the avenue (y = 0) meets it. The game draws the
# gate's leaves and lamps and the cordon's searchlights; this script cuts the gap, builds the frame
# and an approach road outside, and writes the gate record. It draws no random numbers, so every other
# box, light and spawn keeps its place.
GATE = dict(x=-70.0, y=0.0, width=8.0)

ROADS_X = [-64.0, 0.0, 64.0]
ROADS_Y = [-48.0, 0.0, 48.0]
RW = 14.0
SW = 3.0
# The streets as the layout lists them (SimWorld's header says what each field means): a road along x at
# y = c runs the arena's width, one along y at x = c its height. The map draws them and the autopilot finds
# the street at a place from them.
_ax = LAYOUT["arena"]
LAYOUT["roads"] = (
    [{"axis": "x", "c": yc, "width": RW, "from": _ax["left"], "to": _ax["right"]} for yc in ROADS_Y]
    + [{"axis": "y", "c": xc, "width": RW, "from": _ax["bottom"], "to": _ax["top"]} for xc in ROADS_X]
)
BLOCKS = {"NW": (-57, 7, -7, 41), "NE": (7, 7, 57, 41), "SW": (-57, -41, -7, -7), "SE": (7, -41, 57, -7)}

# ---------------------------------------------------------------- materials


def define_materials():
    d = MATS
    d["asphalt"] = mat("asphalt", "#15171a", rough=0.28)
    d["sidewalk"] = mat("sidewalk", "#3a3d40", rough=0.55)
    d["curb"] = mat("curb", "#4b4e50", rough=0.6)
    d["marking"] = mat("marking", "#9a968a", rough=0.5)
    d["marking_y"] = mat("marking_y", "#a8892a", rough=0.5)
    d["grass"] = mat("grass", "#1b2a1a", rough=0.9)
    d["dirt"] = mat("dirt", "#2c261f", rough=0.95)
    for i, c in enumerate(["#3b3f46", "#463f3a", "#34403c", "#4a4642", "#3a3a46", "#41363a"]):
        d["wall%d" % i] = mat("wall%d" % i, c, rough=0.85)
    for i, c in enumerate(["#5a2e26", "#4d3025", "#40302c"]):
        d["brick%d" % i] = mat("brick%d" % i, c, rough=0.9)
    d["roof"] = mat("roof", "#141516", rough=0.9)
    d["trim"] = mat("trim", "#2a2c2f", rough=0.7)
    d["glass"] = mat("glass", "#0a1014", rough=0.08, metal=0.6)
    d["shopglass"] = mat("shopglass", "#070b0e", rough=0.05, metal=0.7)
    d["lit_warm"] = mat("lit_warm", "#3a2a18", rough=0.4, emit="#ffb25a", emit_strength=2.6)
    d["lit_cool"] = mat("lit_cool", "#1a2630", rough=0.4, emit="#9fd4ff", emit_strength=2.2)
    d["lit_green"] = mat("lit_green", "#1a2a1c", rough=0.4, emit="#b6ffb0", emit_strength=2.0)
    d["lit_shop"] = mat("lit_shop", "#2a2a22", rough=0.4, emit="#ffd98a", emit_strength=1.3)
    d["door"] = mat("door", "#1c1d20", rough=0.6, metal=0.3)
    d["metal"] = mat("metal", "#3c4146", rough=0.4, metal=0.85)
    d["rust"] = mat("rust", "#4a2a1c", rough=0.7, metal=0.5)
    d["concrete"] = mat("concrete", "#55585a", rough=0.8)
    d["awn0"] = mat("awn0", "#5a1f22", rough=0.8)
    d["awn1"] = mat("awn1", "#1f3d44", rough=0.8)
    d["awn2"] = mat("awn2", "#4a3a1c", rough=0.8)
    d["neon_red"] = mat("neon_red", "#401010", rough=0.3, emit="#ff2a2a", emit_strength=6.0)
    d["neon_teal"] = mat("neon_teal", "#0c2a2a", rough=0.3, emit="#35ffe0", emit_strength=5.0)
    d["neon_amber"] = mat("neon_amber", "#2a1c08", rough=0.3, emit="#ffa51c", emit_strength=5.0)
    d["neon_pink"] = mat("neon_pink", "#2a0c1c", rough=0.3, emit="#ff4fa8", emit_strength=5.0)
    d["lamp_head"] = mat("lamp_head", "#2a2418", rough=0.3, emit="#ffc070", emit_strength=8.0)
    d["lamp_dead"] = mat("lamp_dead", "#14161a", rough=0.3, metal=0.4)
    d["beacon"] = mat("beacon", "#300808", rough=0.3, emit="#ff1a1a", emit_strength=6.0)
    d["tyre"] = mat("tyre", "#0a0b0c", rough=0.9)
    d["paint0"] = mat("paint0", "#4a2320", rough=0.5, metal=0.4)
    d["paint1"] = mat("paint1", "#1e2c3a", rough=0.5, metal=0.4)
    d["paint2"] = mat("paint2", "#343a30", rough=0.5, metal=0.4)
    d["paint3"] = mat("paint3", "#6a6a62", rough=0.55, metal=0.4)
    d["char"] = mat("char", "#0d0c0b", rough=0.8, metal=0.3)
    d["headlamp"] = mat("headlamp", "#fff0c8", rough=0.2, emit="#fff0c8", emit_strength=7.0)
    d["tail_red"] = mat("tail_red", "#400a0a", rough=0.3, emit="#ff2020", emit_strength=2.0)
    d["leaf"] = mat("leaf", "#18241a", rough=0.9)
    d["bark"] = mat("bark", "#241d18", rough=0.95)
    d["water"] = mat("water", "#0a1316", rough=0.05, metal=0.2)
    d["fire"] = mat("fire", "#ff7a1a", rough=0.4, emit="#ff8a22", emit_strength=5.0)
    d["barrel"] = mat("barrel", "#2f3c3a", rough=0.5, metal=0.7)
    d["tape"] = mat("tape", "#b89a1a", rough=0.5, emit="#b89a1a", emit_strength=0.15)
    d["skyline"] = mat("skyline", "#0b0d10", rough=0.9)
    return d


# ---------------------------------------------------------------- geometry helpers


def _bm(g, m):
    return G.setdefault(g, {}).setdefault(m, bmesh.new())


def prism(g, m, pts, z0, z1):
    """A vertical prism over a polygon of (x, y) points (any winding)."""
    bm = _bm(g, m)
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    if area < 0:
        pts = pts[::-1]
    lo = [bm.verts.new((x, y, z0)) for x, y in pts]
    hi = [bm.verts.new((x, y, z1)) for x, y in pts]
    n = len(pts)
    bm.faces.new(lo[::-1])
    bm.faces.new(hi)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))


def box(g, m, x0, y0, z0, x1, y1, z1):
    prism(g, m, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], z0, z1)


def rbox(g, m, cx, cy, sx, sy, yaw, z0, z1):
    c, s = math.cos(yaw), math.sin(yaw)
    pts = []
    for dx, dy in ((-sx / 2, -sy / 2), (sx / 2, -sy / 2), (sx / 2, sy / 2), (-sx / 2, sy / 2)):
        pts.append((cx + dx * c - dy * s, cy + dx * s + dy * c))
    prism(g, m, pts, z0, z1)


def cyl(g, m, x, y, z0, z1, r, segs=10, r2=None):
    bm = _bm(g, m)
    r2 = r if r2 is None else r2
    lo = [bm.verts.new((x + r * math.cos(2 * math.pi * i / segs), y + r * math.sin(2 * math.pi * i / segs), z0)) for i in range(segs)]
    hi = [bm.verts.new((x + r2 * math.cos(2 * math.pi * i / segs), y + r2 * math.sin(2 * math.pi * i / segs), z1)) for i in range(segs)]
    bm.faces.new(lo[::-1])
    bm.faces.new(hi)
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))


def sphere(g, m, x, y, z, r, segs=8):
    bm = _bm(g, m)
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(4, segs // 2), radius=r, matrix=Matrix.Translation((x, y, z)))


def quad(g, m, p0, p1, p2, p3):
    bm = _bm(g, m)
    bm.faces.new([bm.verts.new(p) for p in (p0, p1, p2, p3)])


def flat(g, m, x0, y0, x1, y1, z):
    """A horizontal quad facing up."""
    quad(g, m, (x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z))


def add_mesh(g, m, verts, faces, matrix):
    bm = _bm(g, m)
    vs = [bm.verts.new(matrix @ Vector(v)) for v in verts]
    for f in faces:
        try:
            bm.faces.new([vs[i] for i in f])
        except ValueError:
            pass


class Face:
    """A wall face: origin, unit tangent, outward normal and length. Points run counterclockwise seen from outside."""

    def __init__(self, ox, oy, tx, ty, nx, ny, length):
        self.o, self.t, self.n, self.L = (ox, oy), (tx, ty), (nx, ny), length

    def p(self, u, off=0.0):
        return (self.o[0] + self.t[0] * u + self.n[0] * off, self.o[1] + self.t[1] * u + self.n[1] * off)


def faces_of(x0, y0, x1, y1):
    return {
        "S": Face(x0, y0, 1, 0, 0, -1, x1 - x0),
        "E": Face(x1, y0, 0, 1, 1, 0, y1 - y0),
        "N": Face(x1, y1, -1, 0, 0, 1, x1 - x0),
        "W": Face(x0, y1, 0, -1, -1, 0, y1 - y0),
    }


def fquad(g, m, f, u0, u1, z0, z1, off=0.02):
    a, b = f.p(u0, off), f.p(u1, off)
    quad(g, m, (a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1))


def fbox(g, m, f, u0, u1, z0, z1, off0, off1):
    prism(g, m, [f.p(u0, off0), f.p(u1, off0), f.p(u1, off1), f.p(u0, off1)], z0, z1)


def sign_text(g, m, text, f, u, z, size, off=0.12):
    """Raised extruded lettering on a wall face, centred at u."""
    cu = bpy.data.curves.new("t", "FONT")
    cu.body = text
    cu.size = size
    cu.extrude = 0.03
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    ob = bpy.data.objects.new("t", cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    px, py = f.p(u, off)
    yaw = math.atan2(f.n[1], f.n[0]) + math.pi / 2
    mx = Matrix.Translation((px, py, z)) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "X")
    add_mesh(g, m, [v.co[:] for v in me.vertices], [tuple(p.vertices) for p in me.polygons], mx)
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    bpy.data.meshes.remove(me)


def collider(x0, y0, x1, y1, kind="building"):
    LAYOUT["boxes"].append(dict(x0=round(x0, 3), y0=round(y0, 3), x1=round(x1, 3), y1=round(y1, 3), kind=kind))


def post(x, y, r, kind="post"):
    LAYOUT["posts"].append(dict(x=round(x, 3), y=round(y, 3), r=r, kind=kind))


def light(x, y, z, color, energy, rng, flicker=0.0, kind="omni", dx=0.0, dy=0.0, angle=0.0, fog=1.0):
    LAYOUT["lights"].append(dict(x=round(x, 2), y=round(y, 2), z=z, color=color, energy=energy, range=rng, flicker=flicker, kind=kind, dx=dx, dy=dy, angle=angle, fog=fog))


# ---------------------------------------------------------------- buildings


def building(g, x0, y0, x1, y1, h, wall, lit_p=0.22, shop_faces=(), sign=None, awning=None, floor_h=3.4, alley_faces=(), tower=False, collide=True, roof_stuff=True, glass_style="punched"):
    """A building with windows, a parapet and roof clutter. `shop_faces`: faces ('S','N','E','W') with a shopfront at ground level."""
    box(g, wall, x0, y0, 0.0, x1, y1, h)
    faces = faces_of(x0, y0, x1, y1)
    gf_h = 3.8
    floors = max(1, int((h - gf_h) // floor_h))
    for key, f in faces.items():
        L = f.L
        shop = key in shop_faces
        # ground floor
        if shop:
            fquad(g, "shopglass", f, 1.0, L - 1.0, 0.5, 3.0)
            fbox(g, "trim", f, 0.7, L - 0.7, 3.0, 3.3, 0.0, 0.18)
            fbox(g, "trim", f, 0.7, 1.0, 0.0, 3.3, 0.0, 0.14)
            fbox(g, "trim", f, L - 1.0, L - 0.7, 0.0, 3.3, 0.0, 0.14)
            # a lit shop interior on some, glimpsed through the glass
            if RNG.random() < 0.5:
                panes = max(2, int((L - 4.0) // 3.0))
                pw = (L - 4.0) / panes
                for pk in range(panes):
                    if RNG.random() < 0.8:
                        fquad(g, "lit_shop", f, 2.0 + pk * pw + 0.15, 2.0 + (pk + 1) * pw - 0.15, 0.9, 2.5, 0.04)
            du = min(L * 0.3, 8.0)
            fbox(g, "door", f, L * 0.5 - 0.6, L * 0.5 + 0.6, 0.0, 2.3, 0.0, 0.1)
            if awning:
                fbox(g, awning, f, 1.2, L - 1.2, 3.3, 3.55, 0.0, 1.5)
        else:
            n_w = int((L - 1.6) // 3.6)
            for k in range(n_w):
                u = 1.8 + (L - 3.6) * (k + 0.5) / max(1, n_w) if n_w else L / 2
                u = 0.8 + (L - 1.6) * (k + 0.5) / n_w
                fquad(g, "glass", f, u - 0.6, u + 0.6, 1.0, 2.5)
            if RNG.random() < 0.8 and L > 4:
                fbox(g, "door", f, L * 0.5 - 0.6, L * 0.5 + 0.6, 0.0, 2.2, 0.0, 0.08)
        # upper floors
        n_cols = int((L - 1.4) // 3.2)
        if n_cols < 1:
            continue
        for fl in range(floors):
            z0 = gf_h + fl * floor_h + 0.55
            band = RNG.random() < 0.5
            for k in range(n_cols):
                u = 0.7 + (L - 1.4) * (k + 0.5) / n_cols
                lit = RNG.random() < lit_p
                if lit:
                    m = RNG.choices(["lit_warm", "lit_cool", "lit_green"], weights=[6, 3, 1])[0]
                else:
                    m = "glass"
                w = 0.62 if glass_style == "punched" else 1.4
                fquad(g, m, f, u - w, u + w, z0, z0 + 1.7, 0.03)
                fbox(g, "trim", f, u - w - 0.08, u + w + 0.08, z0 - 0.14, z0, 0.0, 0.16)
            if tower:
                fbox(g, "trim", f, 0.0, L, z0 - 0.45, z0 - 0.3, 0.0, 0.1)
    # parapet and roof
    t = 0.35
    box(g, "trim", x0, y0, h, x1, y0 + t, h + 0.7)
    box(g, "trim", x0, y1 - t, h, x1, y1, h + 0.7)
    box(g, "trim", x0, y0 + t, h, x0 + t, y1 - t, h + 0.7)
    box(g, "trim", x1 - t, y0 + t, h, x1, y1 - t, h + 0.7)
    box(g, "roof", x0 + t, y0 + t, h, x1 - t, y1 - t, h + 0.05)
    if roof_stuff:
        for _ in range(RNG.randint(2, 4)):
            bx = RNG.uniform(x0 + 2, x1 - 3)
            by = RNG.uniform(y0 + 2, y1 - 3)
            box(g, "metal", bx, by, h + 0.05, bx + RNG.uniform(1.0, 2.4), by + RNG.uniform(1.0, 1.8), h + RNG.uniform(0.8, 1.6))
        if RNG.random() < 0.5 and (x1 - x0) > 8 and (y1 - y0) > 8:
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            cyl(g, "rust", cx, cy, h + 1.8, h + 4.0, 1.4, 10)
            for dx in (-1, 1):
                for dy in (-1, 1):
                    cyl(g, "metal", cx + dx * 1.0, cy + dy * 1.0, h, h + 1.8, 0.07, 5)
        if h >= 20:
            cyl(g, "metal", x1 - 1.5, y1 - 1.5, h, h + 5.0, 0.07, 5)
            sphere(g, "beacon", x1 - 1.5, y1 - 1.5, h + 5.1, 0.22, 6)
    if collide:
        collider(x0, y0, x1, y1)
    # signs on shopfronts
    if sign and shop_faces:
        f = faces[shop_faces[0]]
        txt, mname = sign
        sign_text(g, mname, txt, f, f.L / 2, 3.85, 0.8)
    return faces


# ---------------------------------------------------------------- street furniture


def lamp(g, x, y, facing, on=False, flicker=0.0):
    """A street lamp: pole, a curved arm over the road (`facing` = unit vector toward the road) and a head."""
    fx, fy = facing
    cyl(g, "metal", x, y, 0.0, 7.0, 0.1, 8)
    cyl(g, "metal", x, y, 0.0, 0.4, 0.2, 8)
    hx, hy = x + fx * 1.6, y + fy * 1.6
    box(g, "metal", min(x, hx) - 0.05, min(y, hy) - 0.05, 6.9, max(x, hx) + 0.05, max(y, hy) + 0.05, 7.05)
    box(g, "lamp_head" if on else "lamp_dead", hx - 0.35, hy - 0.2, 6.75, hx + 0.35, hy + 0.2, 6.92)
    post(x, y, 0.2, "lamp")
    LAYOUT["lamps"].append(dict(x=round(x, 2), y=round(y, 2), hx=round(hx, 2), hy=round(hy, 2), on=on, flicker=flicker))
    if on:
        light(hx, hy, 6.6, [1.0, 0.72, 0.4], 5.5, 15.0, flicker, "omni", fog=1.2)


def tree(g, x, y, big=True):
    """A dead tree: a trunk and forked branches."""
    cyl(g, "bark", x, y, 0.0, 3.2, 0.3, 7, r2=0.18)
    for k in range(5):
        a = RNG.uniform(0, 2 * math.pi)
        z = 2.4 + k * 0.5
        L = RNG.uniform(1.6, 3.0)
        ex, ey, ez = x + math.cos(a) * L, y + math.sin(a) * L, z + RNG.uniform(1.2, 2.4)
        n = 5
        for i in range(n):
            t0, t1 = i / n, (i + 1) / n
            p0 = (x + (ex - x) * t0, y + (ey - y) * t0, z + (ez - z) * t0)
            p1 = (x + (ex - x) * t1, y + (ey - y) * t1, z + (ez - z) * t1)
            r0, r1 = 0.1 * (1 - t0) + 0.015, 0.1 * (1 - t1) + 0.015
            _tube_seg(g, "bark", p0, p1, r0, r1)
    post(x, y, 0.4, "tree")


def _tube_seg(g, m, p0, p1, r0, r1, segs=5):
    bm = _bm(g, m)
    a, b = Vector(p0), Vector(p1)
    d = (b - a).normalized()
    up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    u = d.cross(up).normalized()
    v = d.cross(u).normalized()
    r_a = [bm.verts.new(a + (u * math.cos(2 * math.pi * i / segs) + v * math.sin(2 * math.pi * i / segs)) * r0) for i in range(segs)]
    r_b = [bm.verts.new(b + (u * math.cos(2 * math.pi * i / segs) + v * math.sin(2 * math.pi * i / segs)) * r1) for i in range(segs)]
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((r_a[i], r_a[j], r_b[j], r_b[i]))


def dumpster(g, x, y, yaw=0.0):
    rbox(g, "metal", x, y, 2.4, 1.3, yaw, 0.2, 1.4)
    rbox(g, "trim", x, y, 2.5, 1.4, yaw, 1.4, 1.5)
    dx, dy = abs(math.cos(yaw)) * 1.2 + abs(math.sin(yaw)) * 0.65, abs(math.sin(yaw)) * 1.2 + abs(math.cos(yaw)) * 0.65
    collider(x - dx, y - dy, x + dx, y + dy, "prop")


def barrel(g, x, y, fire=False):
    cyl(g, "barrel", x, y, 0.0, 0.95, 0.3, 10)
    post(x, y, 0.32, "barrel")
    if fire:
        cyl(g, "fire", x, y, 0.95, 1.0, 0.24, 8)
        LAYOUT["fires"].append(dict(x=round(x, 2), y=round(y, 2)))
        light(x, y, 1.8, [1.0, 0.55, 0.2], 4.0, 11.0, 0.8, "omni", fog=2.0)


def barrier(g, x, y, yaw, length=3.0):
    rbox(g, "concrete", x, y, length, 0.6, yaw, 0.0, 0.85)
    c, s = abs(math.cos(yaw)), abs(math.sin(yaw))
    hx, hy = (length * c + 0.6 * s) / 2, (length * s + 0.6 * c) / 2
    collider(x - hx, y - hy, x + hx, y + hy, "prop")


def hydrant(g, x, y):
    cyl(g, "rust", x, y, 0.0, 0.7, 0.16, 8)
    sphere(g, "rust", x, y, 0.75, 0.17, 6)
    post(x, y, 0.2, "hydrant")


# ---------------------------------------------------------------- wrecks


def proto_sedan(kind="sedan"):
    """A car body (loft, smoothed) as per-material meshes; instanced into the city by `place_wreck`."""
    reset()
    M = {
        "paint": mat("paint", "#ffffff", rough=0.5),
        "glass": mat("glass", "#0a1014", rough=0.08, metal=0.6),
        "tyre": mat("tyre", "#0a0b0c", rough=0.9),
        "trim": mat("trim", "#2a2c2f", rough=0.7),
    }
    if kind == "van":
        body = [(-2.4, 0.9, 0.34, 1.0), (-2.3, 1.0, 0.3, 1.9), (-1.0, 1.0, 0.3, 2.0), (1.1, 1.0, 0.3, 2.0), (1.9, 0.98, 0.32, 1.6), (2.3, 0.9, 0.36, 0.9), (2.4, 0.86, 0.38, 0.7)]
        cab = None
        wx, wy, wr = 1.5, 0.82, 0.4
    else:
        body = [(-2.0, 0.74, 0.34, 0.78), (-1.95, 0.86, 0.28, 0.86), (-1.2, 0.9, 0.26, 0.92), (0.8, 0.9, 0.26, 0.9), (1.5, 0.86, 0.28, 0.78), (1.9, 0.78, 0.3, 0.62), (2.0, 0.72, 0.32, 0.56)]
        cab = [(-1.1, 0.74, 0.88, 0.94), (-0.85, 0.77, 0.88, 1.38), (0.05, 0.77, 0.88, 1.42), (0.45, 0.77, 0.88, 1.3), (0.85, 0.8, 0.88, 0.94)]
        wx, wy, wr = 1.2, 0.8, 0.34
    b = make_obj("body", loft_bm(body), M["paint"])
    add_mod(b, "SUBSURF", levels=1, render_levels=1)
    objs = [b]
    if cab:
        c = make_obj("cab", loft_bm(cab, side=0.8, corner=0.18), M["glass"])
        add_mod(c, "SUBSURF", levels=1, render_levels=1)
        objs.append(c)
    elif kind == "van":
        win = make_obj("vw", cube_bm((1.6, 1.74, 0.5), loc=(1.5, 0, 1.45)), M["glass"])
        objs.append(win)
    bpy.context.view_layer.update()
    for o in objs:
        if o.modifiers:
            bake(o)
    for sx in (wx, -wx):
        for sy in (wy, -wy):
            objs.append(make_obj("w", cyl_bm(wr, 0.24, loc=(sx, sy, wr), axis="Y", segs=10), M["tyre"]))
    proto = {}
    for o in objs:
        me = o.data
        key = me.materials[0].name if me.materials else "trim"
        proto.setdefault(key, []).append(([v.co[:] for v in me.vertices], [tuple(p.vertices) for p in me.polygons]))
    return proto


def place_wreck(g, proto, x, y, yaw, paint, tilt=0.0, burnt=False, size=None):
    mx = Matrix.Translation((x, y, 0.02)) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(tilt, 4, "X")
    for key, meshes in proto.items():
        name = {"paint": ("char" if burnt else paint), "glass": "glass", "tyre": "tyre", "trim": "trim"}.get(key, key)
        for verts, faces in meshes:
            add_mesh(g, name, verts, faces, mx)


def wreck(g, protos, x, y, yaw, paint, kind="sedan", burnt=False, lights_on=False, flicker=0.0):
    yaw_deg = round(math.degrees(yaw) / 90.0) * 90.0
    vis = math.radians(yaw_deg) + RNG.uniform(-0.12, 0.12)
    place_wreck(g, protos[kind], x, y, vis, paint, tilt=RNG.uniform(-0.04, 0.04), burnt=burnt)
    L = 4.0 if kind == "sedan" else 4.8
    W = 1.8 if kind == "sedan" else 2.0
    horiz = int(round(yaw_deg / 90.0)) % 2 == 0
    hx, hy = (L / 2, W / 2) if horiz else (W / 2, L / 2)
    collider(x - hx, y - hy, x + hx, y + hy, "wreck")
    LAYOUT["wrecks"].append(dict(x=round(x, 2), y=round(y, 2), yaw=round(vis, 3), kind=kind))
    if lights_on:
        # one headlamp still burning: a spot along the car's nose, cutting through the fog
        c, s = math.cos(vis), math.sin(vis)
        nx, ny = x + c * (L / 2), y + s * (L / 2)
        light(nx, ny, 0.7, [1.0, 0.95, 0.8], 14.0, 34.0, flicker, "spot", dx=c, dy=s, angle=22.0, fog=3.0)
        quad(g, "headlamp", (nx, ny - 0.5 * c, 0.6), (nx, ny + 0.5 * c, 0.6), (nx, ny + 0.5 * c, 0.8), (nx, ny - 0.5 * c, 0.8))


def bus(g, x, y):
    """The burned-out bus across the middle junction."""
    L, W, H = 11.0, 2.6, 3.0
    box(g, "char", x - L / 2, y - W / 2, 0.5, x + L / 2, y + W / 2, H)
    for k in range(7):
        u = x - L / 2 + 1.0 + k * 1.4
        for sy in (-1, 1):
            quad(g, "glass", (u, y + sy * (W / 2 + 0.02), 1.5), (u + 1.0, y + sy * (W / 2 + 0.02), 1.5), (u + 1.0, y + sy * (W / 2 + 0.02), 2.5), (u, y + sy * (W / 2 + 0.02), 2.5))
    for wx in (x - 3.5, x + 3.2):
        for sy in (-1, 1):
            cyl(g, "tyre", wx, y + sy * 1.1, 0.0, 0.5, 0.5, 10)
    collider(x - L / 2, y - W / 2, x + L / 2, y + W / 2, "wreck")
    LAYOUT["wrecks"].append(dict(x=round(x, 2), y=round(y, 2), yaw=0.0, kind="bus"))


# ---------------------------------------------------------------- ground, roads, markings


def roads(g):
    ax = LAYOUT["arena"]
    box(g, "asphalt", ax["left"] - 2, ax["bottom"] - 2, -0.3, ax["right"] + 2, ax["top"] + 2, 0.0)
    # dashed centre lines, double yellow on the main avenue
    for yc in ROADS_Y:
        x = ax["left"] + 2
        while x < ax["right"] - 4:
            if not any(abs(x - rx) < RW / 2 + 1 for rx in ROADS_X):
                flat(g, "marking_y" if yc == 0 else "marking", x, yc - 0.1, x + 3.0, yc + 0.1, 0.012)
                if yc == 0:
                    flat(g, "marking_y", x, yc - 0.45, x + 3.0, yc - 0.25, 0.012)
            x += 6.0
    for xc in ROADS_X:
        y = ax["bottom"] + 2
        while y < ax["top"] - 4:
            if not any(abs(y - ry) < RW / 2 + 1 for ry in ROADS_Y):
                flat(g, "marking", xc - 0.1, y, xc + 0.1, y + 3.0, 0.012)
            y += 6.0
    # crosswalks and stop lines at every junction
    for xc in ROADS_X:
        for yc in ROADS_Y:
            for sx in (-1, 1):
                for k in range(-5, 6):
                    cx = xc + sx * (RW / 2 + 1.5)
                    if abs(cx) < ax["right"] - 1 and abs(yc + k * 1.15) < ax["top"] - 1:
                        flat(g, "marking", cx - 1.0, yc + k * 1.15 - 0.3, cx + 1.0, yc + k * 1.15 + 0.3, 0.012)
            for sy in (-1, 1):
                for k in range(-5, 6):
                    cy = yc + sy * (RW / 2 + 1.5)
                    if abs(cy) < ax["top"] - 1 and abs(xc + k * 1.15) < ax["right"] - 1:
                        flat(g, "marking", xc + k * 1.15 - 0.3, cy - 1.0, xc + k * 1.15 + 0.3, cy + 1.0, 0.012)


def block_ground(g, name, rect):
    x0, y0, x1, y1 = rect
    box(g, "sidewalk", x0, y0, 0.0, x1, y1, 0.12)
    # kerb: a slightly raised lip round the edge
    for (a, b, c, d) in ((x0, y0, x1, y0 + 0.2), (x0, y1 - 0.2, x1, y1), (x0, y0, x0 + 0.2, y1), (x1 - 0.2, y0, x1, y1)):
        box(g, "curb", a, b, 0.0, c, d, 0.14)
    LAYOUT["blocks"].append(dict(x0=x0, y0=y0, x1=x1, y1=y1))


# ---------------------------------------------------------------- the four blocks


def block_nw(g, protos):
    building(g, -54, 10, -34, 38, 28, "wall0", lit_p=0.18, shop_faces=("E",), sign=("PHARMACY", "neon_teal"), awning="awn1", tower=True, glass_style="wide")
    building(g, -31, 10, -10, 22, 14, "brick0", lit_p=0.25, shop_faces=("S",), sign=("DINER", "neon_red"), awning="awn0")
    building(g, -31, 25, -10, 38, 21, "brick1", lit_p=0.3, shop_faces=("N",), sign=("MOTEL", "neon_pink"), awning="awn2")
    dumpster(g, -32.5, 23.5, math.pi / 2)
    barrel(g, -32.2, 17.0, fire=True)
    barrel(g, -32.4, 28.5)
    barrier(g, -33.0, 6.0, 0.0)
    for y in (12.0, 33.0):
        hydrant(g, -9.5, y)
    LAYOUT["creature_spawns"] += [dict(x=-32.5, y=14), dict(x=-32.5, y=34), dict(x=-20, y=23.5), dict(x=-52, y=8.5)]


def block_ne(g, protos):
    # gas station: shop, canopy, pumps; parking lot with wrecks; a long warehouse wall behind
    building(g, 38, 10, 54, 20, 5.0, "wall3", lit_p=0.0, shop_faces=("W", "S"), sign=("24H", "neon_amber"), awning="awn2", roof_stuff=False)
    fquad_f = faces_of(38, 10, 54, 20)["W"]
    fquad(g, "lit_shop", fquad_f, 2.0, fquad_f.L / 2 - 0.2, 0.7, 2.7, 0.05)
    fquad(g, "lit_shop", fquad_f, fquad_f.L / 2 + 1.4, fquad_f.L - 2.0, 0.7, 2.7, 0.05)
    building(g, 10, 33.5, 54, 38, 10, "wall4", lit_p=0.05, floor_h=4.5)
    cx0, cy0, cx1, cy1 = 14, 24, 34, 31
    box(g, "trim", cx0, cy0, 5.2, cx1, cy1, 5.8)
    box(g, "lit_shop", cx0 + 0.5, cy0 + 0.5, 5.15, cx1 - 0.5, cy1 - 0.5, 5.2)
    for (px, py) in ((cx0 + 1.2, cy0 + 1.2), (cx1 - 1.2, cy0 + 1.2), (cx0 + 1.2, cy1 - 1.2), (cx1 - 1.2, cy1 - 1.2)):
        box(g, "concrete", px - 0.3, py - 0.3, 0.0, px + 0.3, py + 0.3, 5.2)
        collider(px - 0.3, py - 0.3, px + 0.3, py + 0.3, "prop")
    for px in (19, 24, 29):
        box(g, "metal", px - 0.5, 27.1, 0.12, px + 0.5, 27.9, 1.6)
        box(g, "neon_red", px - 0.35, 27.0, 1.25, px + 0.35, 27.12, 1.5)
        collider(px - 0.5, 27.1, px + 0.5, 27.9, "prop")
    light(24, 27.5, 5.0, [1.0, 0.95, 0.8], 5.0, 20.0, 0.12, "omni", fog=1.5)
    light(46, 15, 3.8, [1.0, 0.9, 0.6], 4.0, 12.0, 0.0, "omni", fog=1.0)
    # parking lot markings
    for k in range(8):
        flat(g, "marking", 11 + k * 3.0, 11, 11.15 + k * 3.0, 18.5, 0.126)
    wreck(g, protos, 13.5, 14.8, 0.0, "paint1", "sedan", burnt=False)
    wreck(g, protos, 19.2, 15.0, math.pi, "paint3", "van", burnt=True)
    wreck(g, protos, 31.5, 13.5, math.pi / 2, "paint0", "sedan", lights_on=True, flicker=0.35)
    wreck(g, protos, 24.0, 20.0, 0.0, "paint2", "sedan")
    wreck(g, protos, 44.5, 25.0, math.pi / 2, "paint1", "van", burnt=True)
    for x in (9.5, 55.5):
        for y in (12.0, 37.0):
            hydrant(g, x, y)
    LAYOUT["creature_spawns"] += [dict(x=36, y=22), dict(x=48, y=30), dict(x=12, y=30)]


def block_sw(g, protos):
    # the dead park
    x0, y0, x1, y1 = -54, -38, -10, -10
    box(g, "grass", x0, y0, 0.12, x1, y1, 0.16)
    # paths
    box(g, "concrete", -34.0, y0, 0.16, -30.0, y1, 0.18)
    box(g, "concrete", x0, -26.0, 0.16, x1, -22.0, 0.18)
    # dry fountain at the crossing
    cyl(g, "concrete", -32, -24, 0.16, 0.9, 3.4, 20)
    cyl(g, "water", -32, -24, 0.7, 0.8, 3.0, 20)
    cyl(g, "concrete", -32, -24, 0.9, 2.2, 0.5, 8)
    post(-32, -24, 3.4, "fountain")
    # iron fence round the park, with two gaps on the road sides
    def fence_run(xa, ya, xb, yb):
        n = int(math.hypot(xb - xa, yb - ya) / 0.6)
        for i in range(n + 1):
            t = i / max(1, n)
            fx, fy = xa + (xb - xa) * t, ya + (yb - ya) * t
            cyl(g, "metal", fx, fy, 0.16, 1.7, 0.03, 4)
        rbox(g, "metal", (xa + xb) / 2, (ya + yb) / 2, math.hypot(xb - xa, yb - ya), 0.05, math.atan2(yb - ya, xb - xa), 1.5, 1.58)
        rbox(g, "metal", (xa + xb) / 2, (ya + yb) / 2, math.hypot(xb - xa, yb - ya), 0.05, math.atan2(yb - ya, xb - xa), 0.4, 0.46)
    fence_run(x0, y0, x0, y1)
    fence_run(x1, y0, x1, -30)
    fence_run(x1, -18, x1, y1)
    fence_run(x0, y0, -38, y0)
    fence_run(-26, y0, x1, y0)
    fence_run(x0, y1, -38, y1)
    fence_run(-26, y1, x1, y1)
    collider(x0 - 0.1, y0, x0 + 0.1, y1, "fence")
    for (a, b, c, d) in ((x1 - 0.1, y0, x1 + 0.1, -30), (x1 - 0.1, -18, x1 + 0.1, y1), (x0, y0 - 0.1, -38, y0 + 0.1), (-26, y0 - 0.1, x1, y0 + 0.1), (x0, y1 - 0.1, -38, y1 + 0.1), (-26, y1 - 0.1, x1, y1 + 0.1)):
        collider(a, b, c, d, "fence")
    for (tx, ty) in ((-48, -16), (-42, -33), (-22, -14), (-18, -30), (-26, -34), (-50, -28), (-14, -22), (-40, -14)):
        tree(g, tx, ty)
    for (bx, by, yaw) in ((-36, -22.5, 0.0), (-28, -25.5, math.pi), (-32, -30.5, 0.0)):
        rbox(g, "rust", bx, by, 1.8, 0.5, yaw, 0.45, 0.5)
        rbox(g, "trim", bx, by + 0.28 * math.cos(yaw), 1.8, 0.1, yaw, 0.5, 1.0)
        post(bx, by, 0.7, "bench")
    # ranger's hut
    building(g, -29, -19, -23, -14, 3.8, "wall5", lit_p=0.0, shop_faces=(), roof_stuff=False)
    light(-26, -13.5, 2.6, [0.6, 0.95, 0.85], 4.0, 13.0, 0.6, "omni", fog=1.5)
    wreck(g, protos, -52, -9.0, math.pi / 2, "paint2", "sedan")
    for lx in (-45, -20):
        lamp(g, lx, -9.5, (0, -1), on=False)
    LAYOUT["creature_spawns"] += [dict(x=-48, y=-16), dict(x=-42, y=-34), dict(x=-18, y=-30), dict(x=-14, y=-14), dict(x=-26, y=-34)]


def block_se(g, protos):
    building(g, 10, -38, 28, -10, 24, "wall2", lit_p=0.2, shop_faces=("W", "N"), sign=("BAR", "neon_pink"), awning="awn0", tower=True)
    building(g, 31, -38, 54, -26, 12, "brick2", lit_p=0.28, shop_faces=("E",), sign=("PAWN", "neon_amber"), awning="awn2")
    building(g, 31, -23, 54, -10, 32, "wall1", lit_p=0.16, shop_faces=("S", "E"), sign=("HOTEL", "neon_teal"), awning="awn1", tower=True, glass_style="wide")
    dumpster(g, 29.5, -24.5, 0.0)
    barrel(g, 29.6, -30.0, fire=True)
    barrel(g, 29.4, -18.0)
    # fire escape on the alley face of the east tower
    f = faces_of(31, -23, 54, -10)["W"]
    for k in range(3, 9):
        z = 3.8 + k * 3.4 - 0.2
        fbox(g, "metal", f, 3.0, 5.0, z, z + 0.08, 0.0, 1.2)
        for u in (3.0, 5.0):
            fbox(g, "metal", f, u - 0.03, u + 0.03, z, z + 1.0, 1.1, 1.17)
    wreck(g, protos, 40, -6.2, 0.0, "paint0", "sedan", burnt=True)
    for x in (9.5, 55.5):
        for y in (-12.0, -37.0):
            hydrant(g, x, y)
    LAYOUT["creature_spawns"] += [dict(x=29.5, y=-18), dict(x=29.5, y=-33), dict(x=42, y=-24.5), dict(x=20, y=-9)]


def street_scene(g, protos):
    # the burned bus across the central junction, and cars abandoned at the mouths of the roads
    bus(g, -3.5, 3.0)
    wreck(g, protos, 12.0, -3.5, math.pi / 2, "paint1", "sedan", lights_on=True, flicker=0.6)
    wreck(g, protos, -9.0, -3.5, 0.0, "paint3", "van", burnt=True)
    wreck(g, protos, 3.5, 22.0, math.pi / 2, "paint2", "sedan")
    wreck(g, protos, -3.5, -22.0, math.pi / 2, "paint0", "van")
    wreck(g, protos, -64, 20.0, math.pi / 2, "paint1", "sedan")
    wreck(g, protos, 66.5, -20.0, math.pi / 2, "paint3", "sedan", burnt=True)
    wreck(g, protos, 30.0, 48.0, 0.0, "paint2", "sedan")
    wreck(g, protos, -30.0, -48.0, math.pi, "paint0", "van", lights_on=True, flicker=0.2)
    wreck(g, protos, 40.0, 3.5, 0.0, "paint1", "sedan")
    # lamps along the sidewalk edges, mostly dead; the live ones flicker
    n = 0
    live = {3, 8, 13, 17, 22, 27, 31, 36, 41}
    for yc in ROADS_Y:
        for sgn in (-1, 1):
            x = -66.0
            while x < 66.0:
                px, py = x, yc + sgn * (RW / 2 + 1.0)
                if abs(py) < LAYOUT["arena"]["top"] - 3 and not any(abs(x - rx) < RW / 2 + 1.5 for rx in ROADS_X):
                    lamp(g, px, py, (0, -sgn), on=(n in live), flicker=0.45 if n % 2 else 0.0)
                    n += 1
                x += 26.0
    for xc in ROADS_X:
        for sgn in (-1, 1):
            y = -46.0
            while y < 46.0:
                px, py = xc + sgn * (RW / 2 + 1.0), y
                if abs(px) < LAYOUT["arena"]["right"] - 3 and not any(abs(y - ry) < RW / 2 + 1.5 for ry in ROADS_Y):
                    lamp(g, px, py, (-sgn, 0), on=(n in live), flicker=0.45 if n % 2 else 0.0)
                    n += 1
                y += 26.0
    # traffic signals at the central junction, dead
    for (sx, sy) in ((7.8, 7.8), (-7.8, -7.8)):
        cyl(g, "metal", sx, sy, 0.0, 5.5, 0.1, 8)
        box(g, "trim", sx - 0.2, sy - 0.2, 4.4, sx + 0.2, sy + 0.2, 5.6)
        post(sx, sy, 0.2, "signal")
    # police tape / barriers at one mouth
    for k in range(3):
        barrier(g, 62.5 + k * 3.2, 24.5 + (k % 2) * 3.0, 0.0)
    LAYOUT["creature_spawns"] += [dict(x=-66, y=30), dict(x=66, y=-30), dict(x=-30, y=52), dict(x=30, y=-52), dict(x=0, y=40), dict(x=0, y=-40), dict(x=-64, y=-6), dict(x=64, y=6)]


def gate_frame(g):
    """Two concrete piers either side of the gap, a lintel over it, a rail for the leaves to roll on, and
    the road that carries on outside the wall, with its edge lines. Everything of the frame stays outside
    x = GATE["x"] (the sim's wall), so nothing stands in the arena without a collider; the leaves hang on
    the wall's inner face and the game draws them."""
    x = GATE["x"]
    hw = GATE["width"] / 2
    for sgn in (-1, 1):
        y0, y1 = (hw, hw + 1.4) if sgn > 0 else (-hw - 1.4, -hw)
        box(g, "concrete", x - 1.5, y0, 0.0, x, y1, 7.0)
        box(g, "trim", x - 1.6, y0 - 0.1, 7.0, x, y1 + 0.1, 7.25)
    box(g, "concrete", x - 1.3, -hw, 6.2, x, hw, 7.0)
    box(g, "trim", x - 1.4, -hw - 1.5, 7.0, x, hw + 1.5, 7.25)
    # the rail along the wall's inner face the leaves slide on
    box(g, "metal", x, -hw - 6.0, 0.0, x + 0.12, hw + 6.0, 0.12)
    # the road outside: the avenue carries on to the cordon
    box(g, "asphalt", x - 44.0, -hw - 1.0, -0.3, x, hw + 1.0, 0.0)
    for k in range(7):
        x0 = x - 3.0 - k * 6.0
        flat(g, "marking_y", x0 - 3.0, -0.1, x0, 0.1, 0.012)
    for sgn in (-1, 1):
        flat(g, "marking", x - 44.0, sgn * (hw - 0.3), x, sgn * (hw - 0.15), 0.012)
    LAYOUT["gate"] = dict(x=GATE["x"], y=GATE["y"], width=GATE["width"])


def perimeter(g):
    ax = LAYOUT["arena"]
    t = 1.0
    gy0, gy1 = GATE["y"] - GATE["width"] / 2, GATE["y"] + GATE["width"] / 2
    for (a, b, c, d) in ((ax["left"] - t, ax["bottom"] - t, ax["right"] + t, ax["bottom"]), (ax["left"] - t, ax["top"], ax["right"] + t, ax["top"] + t), (ax["left"] - t, ax["bottom"], ax["left"], gy0), (ax["left"] - t, gy1, ax["left"], ax["top"]), (ax["right"], ax["bottom"], ax["right"] + t, ax["top"])):
        box(g, "concrete", a, b, 0.0, c, d, 4.5)
        box(g, "trim", a - 0.1, b - 0.1, 4.5, c + 0.1, d + 0.1, 4.8)
        # razor-wire hint: a thin dark band above
    gate_frame(g)
    # a skyline of dark, mostly unlit towers beyond the wall: only seen through the fog
    for k in range(60):
        a = 2 * math.pi * k / 60 + RNG.uniform(-0.03, 0.03)
        r = RNG.uniform(105, 150)
        x, y = math.cos(a) * r * 1.25, math.sin(a) * r * 0.95
        w, d, h = RNG.uniform(10, 22), RNG.uniform(10, 22), RNG.uniform(25, 70)
        box(g, "skyline", x - w / 2, y - d / 2, 0.0, x + w / 2, y + d / 2, h)
    # extra dark ground out to the horizon so the fog has something to hide
    box(g, "asphalt", -200, -150, -0.5, 200, 150, -0.35)


# ---------------------------------------------------------------- build and export


def flush_group(g, name, parent=None):
    objs = []
    for mname, bm in G.pop(g, {}).items():
        if not len(bm.faces):
            bm.free()
            continue
        me = bpy.data.meshes.new("%s_%s" % (name, mname))
        bm.to_mesh(me)
        bm.free()
        for p in me.polygons:
            p.use_smooth = False
        ob = bpy.data.objects.new("%s_%s" % (name, mname), me)
        bpy.context.scene.collection.objects.link(ob)
        me.materials.append(MATS[mname])
        objs.append(ob)
    if not objs:
        return None
    ob = join(name, objs)
    return ob


def build():
    reset()
    protos = {"sedan": None, "van": None}
    # prototypes first (they reset the scene)
    sed = proto_sedan("sedan")
    van = proto_sedan("van")
    reset()
    define_materials()
    protos = {"sedan": sed, "van": van}
    roads("roads")
    for name, rect in BLOCKS.items():
        block_ground("roads", name, rect)
    objs = [flush_group("roads", "roads")]
    for name, fn in (("block_nw", block_nw), ("block_ne", block_ne), ("block_sw", block_sw), ("block_se", block_se)):
        fn(name, protos)
        objs.append(flush_group(name, name))
    street_scene("street", protos)
    perimeter("street")
    objs.append(flush_group("street", "street"))
    return [o for o in objs if o]


def write_layout():
    path = os.path.join(HERE, "..", "..", "scripts", "game", "city_layout.gd")
    data = json.dumps(LAYOUT, indent=1)
    with open(path, "w") as f:
        f.write("# Generated by tools/blender/city.py: do not edit. Colliders, lamps, lights, wrecks and spawns.\n")
        f.write("class_name CityLayout\nextends RefCounted\n\nconst DATA := " + data.replace("\n", "\n") + "\n")
    print("LAYOUT", path, len(LAYOUT["boxes"]), "boxes", len(LAYOUT["posts"]), "posts", len(LAYOUT["lights"]), "lights")


if __name__ == "__main__":
    objs = build()
    write_layout()
    if "preview" in ARGS:
        os.makedirs("/private/tmp/hh_prev", exist_ok=True)
        sc = bpy.context.scene
        preview("/private/tmp/hh_prev/city_top.png", (0, -150, 170), (0, 0, 0), lens=40, res=(1300, 800), sun=1.2, fill=0.6, world="#101820", sun_rot=(0.8, 0.2, 0.4))
        preview("/private/tmp/hh_prev/city_street.png", (-34, -4, 3.0), (10, 6, 6), lens=30, res=(1300, 800), sun=1.0, fill=0.8, world="#18202a", sun_rot=(0.9, 0.3, 0.7))
    export(os.path.join(OUT, "city.glb"), objs, extra=dict(export_apply=True))

"""The player car for Hollow Hours: Roadkill's Bruiser (same 4 x 2 m footprint, config.js) as a weathered night-city muscle car.
Lofted shell, wheel arches cut by boolean, real wheels, bull bar, nothing mounted on top. Moving parts are named nodes the game drives:
steer_FL/FR (front wheel pivots), wheel_FL/FR/RL/RR (spin). Exported without Draco (Godot 4 cannot read it). Run:
  Blender --background --python-exit-code 1 --python tools/blender/car.py -- [preview]
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, Matrix
from rk import *

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

SPECS = {
    "bruiser": dict(
        L=4.0, wr=0.42, ww=0.36, wx=1.35, wy=0.84, arch=0.54,
        body=[(-2.0, 0.84, 0.46, 0.9), (-1.94, 0.94, 0.38, 0.98), (-1.5, 1.0, 0.34, 1.02), (-0.5, 1.0, 0.32, 1.05), (0.5, 1.0, 0.32, 1.05),
              (1.2, 1.0, 0.34, 1.02), (1.75, 0.97, 0.38, 0.92), (1.94, 0.9, 0.42, 0.82), (2.0, 0.82, 0.46, 0.74)],
        cabin=[(-1.2, 0.8, 1.0, 1.08), (-1.02, 0.82, 1.0, 1.4), (-0.8, 0.82, 1.0, 1.55), (0.0, 0.82, 1.0, 1.58), (0.35, 0.82, 1.0, 1.52), (0.82, 0.86, 1.0, 1.08)],
        roof=[(-0.85, 0.6, 1.40, 1.48), (-0.75, 0.64, 1.40, 1.50), (0.1, 0.64, 1.40, 1.50), (0.25, 0.6, 1.36, 1.46)],
        stripes=[0.2, -0.2], stripe_w=0.16, hood=(0.6, 1.9), trunk=(-1.95, -1.1),
        gun=(-1.4, 1.1), zap=(1.3, 1.03), bumper_z=0.46, light="slab",
    ),
}


def materials():
    M = type("M", (), {})()
    M.paint = mat("paint", "#7a1d22", rough=0.34, metal=0.5, coat=1.0, coat_rough=0.06, vcol=True)
    M.stripe = mat("stripe", "#16181b", rough=0.4, metal=0.3, vcol=True)
    M.glass = mat("glass", "#0a1318", rough=0.05, metal=0.8, vcol=True)
    M.trim = mat("trim", "#0c1013", rough=0.7, vcol=True)
    M.steel = mat("steel", "#9aa6ac", rough=0.32, metal=0.9, vcol=True)
    M.dark = mat("dark", "#353f45", rough=0.5, metal=0.5, vcol=True)
    M.tyre = mat("tyre", "#0b0e10", rough=0.92)
    M.rim = mat("rim", "#6c7378", rough=0.3, metal=0.9)
    M.headlight = mat("headlight", "#fff3cf", emit="#fff3cf", emit_strength=6.0, rough=0.2)
    M.taillight = mat("taillight", "#8a1820", emit="#ff2a30", emit_strength=3.0, rough=0.3)
    M.scrap = mat("scrap", "#ffb86b", rough=0.5, metal=0.7)
    M.coil = mat("coil", "#7ff0ff", emit="#7ff0ff", emit_strength=3.0, rough=0.3)
    M.seat = mat("seat", "#1b2429", rough=0.85)
    return M


def wheel_object(name, S, M):
    r, w = S["wr"], S["ww"]
    parts = []
    tyre = make_obj("t", cyl_bm(r, w, axis="Y", segs=32, bevel=w * 0.2), M.tyre)
    parts.append(tyre)
    rim = make_obj("r", cyl_bm(r * 0.62, w * 1.05, axis="Y", segs=24), M.rim)
    parts.append(rim)
    hub = make_obj("h", cyl_bm(r * 0.16, w * 1.0, axis="Y", segs=10), M.steel)
    parts.append(hub)
    for k in range(5):
        a = k * 2 * math.pi / 5
        sp = make_obj("s", cube_bm((r * 0.5, w * 1.09, r * 0.1), loc=(math.cos(a) * r * 0.3, 0, math.sin(a) * r * 0.3), rot=(0, -a, 0)), M.dark)
        parts.append(sp)
    # tread blocks round the tyre
    for k in range(18):
        a = k * 2 * math.pi / 18
        tb = make_obj("b", cube_bm((r * 0.12, w * 0.8, r * 0.04), loc=(math.cos(a) * r * 0.985, 0, math.sin(a) * r * 0.985), rot=(0, -a + math.pi / 2, 0), bevel=0.01), M.tyre)
        parts.append(tb)
    o = join(name, parts)
    return o


def stripe_obj(x0, x1, y, w, target, M, n=70):
    bm = bmesh.new()
    cols = []
    for k in (-1, 0, 1):
        cols.append([bm.verts.new((x0 + (x1 - x0) * i / n, y + k * w / 2, 3.0)) for i in range(n + 1)])
    for k in range(2):
        for i in range(n):
            bm.faces.new((cols[k][i], cols[k][i + 1], cols[k + 1][i + 1], cols[k + 1][i]))
    o = make_obj("stripe", bm, M.stripe, smooth=True)
    m = o.modifiers.new("sw", "SHRINKWRAP")
    m.target = target
    m.wrap_method = "PROJECT"
    m.use_project_z = True
    m.use_negative_direction = True
    m.use_positive_direction = False
    m.offset = 0.006
    return o


def build(kind, with_extras=True):
    reset()
    S = SPECS[kind]
    M = materials()
    root = empty("car")
    L = S["L"]
    static = []

    # --- body shell, smoothed, with wheel arches cut ---
    body = make_obj("body", loft_bm(S["body"]), M.paint)
    add_mod(body, "SUBSURF", levels=2, render_levels=2)
    wz = S["wr"]
    cb = bmesh.new()
    for sx in (S["wx"], -S["wx"]):
        for sy in (S["wy"], -S["wy"]):
            bmesh.ops.create_cone(cb, cap_ends=True, segments=28, radius1=S["arch"], radius2=S["arch"], depth=S["ww"] + 0.5, matrix=Matrix.Translation((sx, sy, wz)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
    cutter = make_obj("cutter", cb, None)
    bo = body.modifiers.new("arches", "BOOLEAN")
    bo.operation = "DIFFERENCE"
    bo.object = cutter
    bo.solver = "EXACT"
    bpy.context.view_layer.update()

    extras = []
    # --- cabin, roof panel and stripes ---
    roof = None
    if S["cabin"]:
        cab = make_obj("cabin", loft_bm(S["cabin"], side=0.8, corner=0.18), M.glass)
        add_mod(cab, "SUBSURF", levels=2, render_levels=2)
        extras.append(cab)
        roof = make_obj("roof", loft_bm(S["roof"], side=0.85, corner=0.3), M.paint)
        add_mod(roof, "SUBSURF", levels=2, render_levels=2)
        extras.append(roof)
    bpy.context.view_layer.update()
    for y in S["stripes"]:
        extras.append(stripe_obj(S["hood"][0], S["hood"][1], y, S["stripe_w"], body, M))
        extras.append(stripe_obj(S["trunk"][0], S["trunk"][1], y, S["stripe_w"], body, M, n=40))
        if roof:
            r0 = S["roof"][1][0] + 0.05
            r1 = S["roof"][-2][0] - 0.05
            extras.append(stripe_obj(r0, r1, y * 0.9, S["stripe_w"] * 0.9, roof, M, n=30))
    bpy.context.view_layer.update()
    for o in extras:
        if o.modifiers:
            bake(o)
    bake(body)
    bpy.data.objects.remove(cutter)
    static += [body] + extras

    top = max(b[3] for b in S["body"])
    hz = S["body"][len(S["body"]) // 2][3]

    def add(name, bm, material, smooth=True, loc=(0, 0, 0)):
        o = make_obj(name, bm, material, smooth=smooth, loc=loc)
        static.append(o)
        return o

    # --- underbody, bumpers, grille, lights, mirrors, exhaust, bull bar ---
    add("floor", cube_bm((L - 0.5, 1.5, 0.16), loc=(0, 0, 0.3), bevel=0.04), M.trim)
    bz = S["bumper_z"]
    wmax = S["body"][4][1]
    add("bumperF", cube_bm((0.16, wmax * 1.9, 0.18), loc=(L / 2 + 0.03, 0, bz), bevel=0.05), M.steel)
    add("bumperR", cube_bm((0.16, wmax * 1.9, 0.18), loc=(-L / 2 - 0.02, 0, bz), bevel=0.05), M.steel)
    for sy in (-1, 1):
        add("skirt", cube_bm((L * 0.52, 0.05, 0.1), loc=(0, sy * (wmax - 0.01), 0.36), bevel=0.02), M.trim)
        # side mirrors
        mz = (S["cabin"][2][3] - 0.38) if S["cabin"] else top + 0.35
        mx = 0.5
        add("mirror", cube_bm((0.12, 0.16, 0.1), loc=(mx, sy * (wmax + 0.12), mz), bevel=0.03), M.paint)
        add("mstalk", cube_bm((0.05, 0.14, 0.05), loc=(mx, sy * (wmax + 0.02), mz - 0.03)), M.trim)
        # tail lights
        add("tail", cube_bm((0.06, 0.26, 0.1), loc=(-L / 2 - 0.0, sy * 0.66, S["body"][0][3] - 0.12), bevel=0.02), M.taillight)
        # exhaust pipes
        add("pipe", cyl_bm(0.06, 0.3, loc=(-L / 2 - 0.08, sy * 0.52, 0.36), axis="X", segs=12), M.steel)
        # headlights
        if S["light"] == "round":
            add("hl", sphere_bm(0.16, loc=(L / 2 - 0.1, sy * 0.66, 0.95), scale=(0.7, 1, 1)), M.headlight)
            add("hlr", torus_bm(0.17, 0.025, loc=(L / 2 - 0.02, sy * 0.66, 0.95), axis="X"), M.steel)
        elif S["light"] == "slim":
            add("hl", cube_bm((0.1, 0.38, 0.07), loc=(L / 2 - 0.12, sy * 0.58, 0.5), rot=(0.25 * sy, 0, 0), bevel=0.02), M.headlight)
        else:
            add("hl", cube_bm((0.08, 0.28, 0.1), loc=(L / 2 - 0.04, sy * 0.7, 0.76), bevel=0.03), M.headlight)
    # grille
    gz = 0.6
    add("grille", cube_bm((0.08, 0.9, 0.2), loc=(L / 2 - 0.02, 0, gz), bevel=0.02), M.trim)
    # bull bar: a tube across the nose on uprights, the game's first car upgrade (steel; kept on all three cars)
    bw = wmax - 0.25
    add("bullbar", tube_bm([(L / 2 + 0.2, -bw, bz + 0.1), (L / 2 + 0.26, -bw + 0.1, bz + 0.34), (L / 2 + 0.26, bw - 0.1, bz + 0.34), (L / 2 + 0.2, bw, bz + 0.1)], 0.055), M.steel)
    for sy in (-0.55, 0.55):
        add("bbup", tube_bm([(L / 2 + 0.26, sy, bz + 0.34), (L / 2 + 0.1, sy, bz + 0.05)], 0.045), M.steel)

    # --- per-car character ---
    if kind == "bruiser":
        add("scoop", cube_bm((0.7, 0.5, 0.1), loc=(1.15, 0, top + 0.01), bevel=0.04), M.trim)

    shell = join("shell", static, parent=root)

    # --- wheels: pivots and spinning wheels ---
    for nm, sx, sy in (("FL", S["wx"], S["wy"]), ("FR", S["wx"], -S["wy"]), ("RL", -S["wx"], S["wy"]), ("RR", -S["wx"], -S["wy"])):
        w = wheel_object("wheel_" + nm, S, M)
        if nm[0] == "F":
            piv = empty("steer_" + nm, (sx, sy, wz), parent=root)
            w.parent = piv
            w.location = (0, 0, 0)
        else:
            w.parent = root
            w.location = (sx, sy, wz)

    # contact shadow baked into the shell's vertex colours: under the sills, in the wheel arches, bumper creases, under the cabin
    bpy.context.view_layer.update()
    wheels = [o for o in root.children_recursive if o.name.startswith("wheel_")]
    vertex_ao([shell], [shell] + wheels, ground=(14, 14), rays=14, maxd=1.4, strength=0.85)
    return root, S


def finish(kind, root):
    objs = [root] + list(root.children_recursive)
    path = os.path.join(OUT, kind + ".glb")
    export(path, objs)


if __name__ == "__main__":
    root, S = build("bruiser")
    if "preview" in ARGS:
        os.makedirs("/private/tmp/hh_prev", exist_ok=True)
        preview("/private/tmp/hh_prev/car_a.png", (6.2, -6.5, 3.6), (0, 0, 0.9), lens=42)
        preview("/private/tmp/hh_prev/car_b.png", (-6.0, 5.0, 3.2), (0, 0, 0.9), lens=42)
    finish("bruiser", root)

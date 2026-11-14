"""The creature of Hollow Hours, "the Gaunt": modelled, skinned, rigged and animated here.

An original design: a starved, long-limbed pack hunter that goes on all fours when it stalks and
sprints, and rears up to leap. Pale wet skin over a visible ribcage and spine, a long hinged jaw
with needle teeth, two pale eyes, a bony crest, forearms longer than a man's, three claws on each
hand, digitigrade hind legs and a whip tail. About 2 m long nose to rump, 0.85 m at the shoulder.

Coordinates: Blender Z up, +X forward, +Y left; the glTF exporter keeps +X forward for Godot.
Rig: 27 bones. Clips (30 fps): idle, stalk, sprint, pounce, latch, thrown, dead.
Poses are written as ABSOLUTE elevation deltas per bone from the rest pose (positive = the
bone's tip swings counterclockwise seen from the left, i.e. forward/up for limbs that hang
down) plus optional yaw and roll; the script turns them into local bone rotations.

Run (headless, foreground):
  Blender --background --python-exit-code 1 --python tools/blender/creature.py -- [preview]
Output: assets/models/gaunt.glb (and contact sheets in /private/tmp/hh_prev with `preview`).
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, Matrix, Quaternion
from rk import *

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
FPS = 30

# ------------------------------------------------------------------ mesh helpers


def lerp(a, b, t):
    return a + (b - a) * t


def tube_taper(points, radii, segs=8, cap=True):
    """A tube along a polyline whose radius changes per point."""
    bm = bmesh.new()
    P = [Vector(p) for p in points]
    rings = []
    for i, p in enumerate(P):
        if i == 0:
            d = P[1] - P[0]
        elif i == len(P) - 1:
            d = P[i] - P[i - 1]
        else:
            d = P[i + 1] - P[i - 1]
        d.normalize()
        up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        u = d.cross(up).normalized()
        v = d.cross(u).normalized()
        r = radii[i]
        rings.append([bm.verts.new(p + (u * math.cos(2 * math.pi * j / segs) + v * math.sin(2 * math.pi * j / segs)) * r) for j in range(segs)])
    for i in range(len(rings) - 1):
        for j in range(segs):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % segs], rings[i + 1][(j + 1) % segs], rings[i + 1][j]))
    if cap:
        bm.faces.new(rings[0][::-1])
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def curve_tube(points, radii, per=6, segs=10, cap=True):
    """A tube along a Catmull-Rom curve through the points, radius interpolated smoothly: limbs that bend without pinching."""
    P = [Vector(p) for p in points]
    R = list(radii)
    ext = [P[0] * 2 - P[1]] + P + [P[-1] * 2 - P[-2]]
    rex = [R[0]] + R + [R[-1]]
    pts, rad = [], []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            pt = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            pts.append(pt)
            tt = t * t * (3 - 2 * t)
            rad.append(lerp(rex[i], rex[i + 1], tt))
    pts.append(P[-1])
    rad.append(R[-1])
    return tube_taper(pts, rad, segs, cap)


def ellipse_loft(stations, n=12):
    """A body lofted through elliptical cross-sections along +X: each station is (x, z_centre, half_width, half_height)."""
    bm = bmesh.new()
    rings = []
    for (x, zc, ry, rz) in stations:
        rings.append([bm.verts.new((x, ry * math.cos(2 * math.pi * j / n), zc + rz * math.sin(2 * math.pi * j / n))) for j in range(n)])
    for i in range(len(rings) - 1):
        for j in range(n):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % n], rings[i + 1][(j + 1) % n], rings[i + 1][j]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def merge_bms(bms):
    out = bmesh.new()
    for b in bms:
        me = bpy.data.meshes.new("tmp")
        b.to_mesh(me)
        b.free()
        out.from_mesh(me)
        bpy.data.meshes.remove(me)
    return out


def smooth_obj(ob, levels=1):
    add_mod(ob, "SUBSURF", levels=levels, render_levels=levels)
    bpy.context.view_layer.update()
    bake(ob)
    return ob


# ------------------------------------------------------------------ the rig

BONES = {}  # name -> (head, tail, parent)


def define_bones():
    B = BONES
    B["root"] = ((0, 0, 0.0), (0, 0, 0.15), None)
    B["hips"] = ((-0.45, 0, 0.72), (-0.25, 0, 0.75), "root")
    B["spine1"] = ((-0.25, 0, 0.75), (0.05, 0, 0.78), "hips")
    B["spine2"] = ((0.05, 0, 0.78), (0.35, 0, 0.80), "spine1")
    B["chest"] = ((0.35, 0, 0.80), (0.55, 0, 0.84), "spine2")
    B["neck"] = ((0.55, 0, 0.84), (0.82, 0, 0.86), "chest")
    B["head"] = ((0.82, 0, 0.86), (1.30, 0, 0.80), "neck")
    B["jaw"] = ((0.90, 0, 0.78), (1.28, 0, 0.72), "head")
    B["tail1"] = ((-0.55, 0, 0.72), (-1.0, 0, 0.64), "hips")
    B["tail2"] = ((-1.0, 0, 0.64), (-1.5, 0, 0.52), "tail1")
    B["tail3"] = ((-1.5, 0, 0.52), (-1.95, 0, 0.55), "tail2")
    for sd, s in (("L", 1), ("R", -1)):
        B["clav." + sd] = ((0.40, 0.08 * s, 0.82), (0.42, 0.20 * s, 0.80), "chest")
        B["upperarm." + sd] = ((0.42, 0.20 * s, 0.80), (0.28, 0.30 * s, 0.50), "clav." + sd)
        B["forearm." + sd] = ((0.28, 0.30 * s, 0.50), (0.58, 0.30 * s, 0.20), "upperarm." + sd)
        B["hand." + sd] = ((0.58, 0.30 * s, 0.20), (0.72, 0.30 * s, 0.05), "forearm." + sd)
        B["thigh." + sd] = ((-0.50, 0.17 * s, 0.74), (-0.15, 0.24 * s, 0.50), "hips")
        B["shin." + sd] = ((-0.15, 0.24 * s, 0.50), (-0.62, 0.24 * s, 0.34), "thigh." + sd)
        B["foot." + sd] = ((-0.62, 0.24 * s, 0.34), (-0.45, 0.24 * s, 0.05), "shin." + sd)
        B["toes." + sd] = ((-0.45, 0.24 * s, 0.05), (-0.28, 0.24 * s, 0.02), "foot." + sd)


def make_armature():
    arm = bpy.data.armatures.new("rig")
    ao = bpy.data.objects.new("rig", arm)
    bpy.context.scene.collection.objects.link(ao)
    bpy.context.view_layer.objects.active = ao
    ao.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (h, t, par) in BONES.items():
        b = arm.edit_bones.new(name)
        b.head = Vector(h)
        b.tail = Vector(t)
        if par:
            b.parent = arm.edit_bones[par]
    bpy.ops.object.mode_set(mode="OBJECT")
    return ao


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.dot(ab), 1e-9)))
    return (p - (a + ab * t)).length


def skin(ob, candidates, power=4.0, top=4):
    """Smooth weights from the distance to each candidate bone's segment, normalised, the strongest `top` kept."""
    me = ob.data
    groups = {n: ob.vertex_groups.new(name=n) for n in candidates}
    segs = {n: (Vector(BONES[n][0]), Vector(BONES[n][1])) for n in candidates}
    for v in me.vertices:
        ws = []
        for n in candidates:
            d = seg_dist(v.co, *segs[n])
            ws.append((1.0 / (d + 0.025) ** power, n))
        ws.sort(reverse=True)
        ws = ws[:top]
        tot = sum(w for w, _ in ws)
        for w, n in ws:
            if w / tot > 0.01:
                groups[n].add([v.index], w / tot, "REPLACE")


def rigid(ob, bone):
    vg = ob.vertex_groups.new(name=bone)
    vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")


# ------------------------------------------------------------------ the body


def build_body():
    reset()
    M = type("M", (), {})()
    M.skin = mat("skin", "#8a949a", rough=0.4, coat=0.55, coat_rough=0.12, vcol=True)
    M.bone = mat("bone", "#d2cbb6", rough=0.5)
    M.eyes = mat("eyes", "#f2eec4", emit="#e8e6a8", emit_strength=4.0, rough=0.3)
    M.mouth = mat("mouth", "#2a0a10", rough=0.55)
    skin_parts, other = [], []

    def part(name, bm, material, cands=None, bone=None, subdiv=0, is_skin=True):
        ob = make_obj(name, bm, material, smooth=True)
        if subdiv:
            smooth_obj(ob, subdiv)
        (skin_parts if is_skin else other).append(ob)
        ob["cands"] = cands or []
        ob["bone"] = bone or ""
        return ob

    # torso: pelvis, narrow waist, a deep barrelled ribcage with a ridge for each rib
    st = [(-0.64, 0.70, 0.09, 0.10), (-0.52, 0.73, 0.15, 0.17), (-0.38, 0.74, 0.11, 0.14), (-0.22, 0.755, 0.095, 0.125), (-0.10, 0.775, 0.12, 0.17)]
    for k in range(8):
        x = 0.0 + k * 0.07
        r = 1.0 + (0.05 if k % 2 == 0 else -0.015)
        st.append((x, 0.79 + k * 0.004, (0.14 + 0.006 * k) * r, (0.215 + 0.006 * k) * r))
    st += [(0.55, 0.82, 0.15, 0.20), (0.62, 0.85, 0.10, 0.125)]
    part("torso", ellipse_loft(st, 12), M.skin, ["hips", "spine1", "spine2", "chest"], subdiv=1)
    part("neck", curve_tube([(0.52, 0, 0.83), (0.68, 0, 0.855), (0.86, 0, 0.865)], [0.10, 0.085, 0.075], 5, 10), M.skin, ["chest", "neck", "head"])

    # skull: long, low, tapering to a narrow snout; the lower jaw hangs from it
    sk = [(0.80, 0.86, 0.085, 0.10), (0.90, 0.87, 0.118, 0.122), (1.00, 0.86, 0.105, 0.108), (1.10, 0.835, 0.078, 0.078), (1.20, 0.81, 0.056, 0.058), (1.285, 0.795, 0.04, 0.044)]
    part("skull", ellipse_loft(sk, 10), M.skin, ["neck", "head"], subdiv=1)
    jw = [(0.90, 0.772, 0.07, 0.036), (1.00, 0.752, 0.072, 0.031), (1.10, 0.74, 0.056, 0.026), (1.20, 0.735, 0.042, 0.023), (1.27, 0.73, 0.03, 0.02)]
    part("jaw", ellipse_loft(jw, 8), M.skin, ["jaw", "head"], subdiv=1)
    # mouth lining: a dark slab between the jaws so the open mouth reads
    part("mouth", cube_bm((0.34, 0.1, 0.03), loc=(1.08, 0, 0.775)), M.mouth, bone="jaw", is_skin=False)

    # tail
    part("tail", curve_tube([(-0.55, 0, 0.72), (-1.0, 0, 0.64), (-1.5, 0, 0.52), (-1.95, 0, 0.55)], [0.09, 0.062, 0.036, 0.012], 6, 8), M.skin, ["hips", "tail1", "tail2", "tail3"])
    part("tailspike", tube_taper([(-1.93, 0, 0.55), (-2.1, 0, 0.58)], [0.02, 0.003], 6), M.bone, bone="tail3", is_skin=False)

    for sd, s in (("L", 1), ("R", -1)):
        # forelimb: scapula hump, long upper arm, longer forearm, big three-clawed hand
        arm_pts = [(0.42, 0.18 * s, 0.82), (0.28, 0.30 * s, 0.50), (0.58, 0.30 * s, 0.20), (0.71, 0.30 * s, 0.06)]
        part("arm" + sd, curve_tube(arm_pts, [0.10, 0.068, 0.048, 0.056], 7, 10), M.skin, ["chest", "clav." + sd, "upperarm." + sd, "forearm." + sd, "hand." + sd])
        for nm, c, r, cands in (("scap", (0.38, 0.17 * s, 0.86), (0.13, 0.07, 0.13), ["spine2", "chest", "clav." + sd]), ("elbow", (0.27, 0.31 * s, 0.50), (0.075, 0.07, 0.075), ["upperarm." + sd, "forearm." + sd]), ("wrist", (0.58, 0.30 * s, 0.20), (0.058, 0.058, 0.058), ["forearm." + sd, "hand." + sd])):
            part(nm + sd, sphere_bm(1.0, loc=c, scale=r, segs=10, rings=6), M.skin, cands)
        for k, dy in enumerate((-0.05, 0.0, 0.05)):
            y = 0.30 * s + dy * s
            part("claw%s%d" % (sd, k), tube_taper([(0.70, y, 0.065), (0.84, y + dy * 0.8, 0.045), (0.97, y + dy * 1.3, 0.012)], [0.016, 0.012, 0.002], 6), M.bone, bone="hand." + sd, is_skin=False)
        part("dew" + sd, tube_taper([(0.62, 0.30 * s - 0.04 * s, 0.14), (0.7, 0.30 * s - 0.08 * s, 0.1), (0.76, 0.30 * s - 0.1 * s, 0.07)], [0.012, 0.01, 0.002], 6), M.bone, bone="hand." + sd, is_skin=False)
        # hind limb: heavy haunch, thigh, a long reversed shin, a tall foot on three toes
        part("haunch" + sd, sphere_bm(1.0, loc=(-0.44, 0.17 * s, 0.64), scale=(0.19, 0.10, 0.17), segs=12, rings=8), M.skin, ["hips", "thigh." + sd, "shin." + sd])
        leg_pts = [(-0.50, 0.17 * s, 0.74), (-0.15, 0.24 * s, 0.50), (-0.62, 0.24 * s, 0.34), (-0.45, 0.24 * s, 0.06)]
        part("leg" + sd, curve_tube(leg_pts, [0.125, 0.075, 0.045, 0.045], 7, 10), M.skin, ["hips", "thigh." + sd, "shin." + sd, "foot." + sd, "toes." + sd])
        part("knee" + sd, sphere_bm(1.0, loc=(-0.15, 0.245 * s, 0.50), scale=(0.075, 0.065, 0.075), segs=10, rings=6), M.skin, ["thigh." + sd, "shin." + sd])
        part("ankle" + sd, sphere_bm(1.0, loc=(-0.62, 0.24 * s, 0.34), scale=(0.052, 0.052, 0.052), segs=8, rings=5), M.skin, ["shin." + sd, "foot." + sd])
        for k, dy in enumerate((-0.05, 0.0, 0.05)):
            y = 0.24 * s + dy * s
            part("toe%s%d" % (sd, k), tube_taper([(-0.47, y, 0.06), (-0.36, y + dy * 0.6, 0.035), (-0.25, y + dy, 0.008)], [0.02, 0.014, 0.003], 6), M.bone, bone="toes." + sd, is_skin=False)

    # dorsal vertebrae: a row of bony knobs down the spine, riding the top of the back
    tops = [(-0.52, 0.92), (-0.38, 0.91), (-0.22, 0.905), (-0.1, 0.935), (0.0, 0.985), (0.2, 1.0), (0.4, 1.03), (0.5, 1.01)]

    def top_at(x):
        for (x0, z0), (x1, z1) in zip(tops, tops[1:]):
            if x0 <= x <= x1:
                return lerp(z0, z1, (x - x0) / (x1 - x0))
        return tops[0][1] if x < tops[0][0] else tops[-1][1]

    for k in range(10):
        x = -0.5 + k * 0.105
        z = top_at(x) - 0.02
        h = 0.075 - 0.003 * k
        bone = "spine1" if x < -0.1 else ("spine2" if x < 0.33 else "chest")
        part("vert%d" % k, tube_taper([(x, 0, z), (x - 0.02, 0, z + h * 0.5), (x - 0.045, 0, z + h)], [0.03, 0.02, 0.003], 5), M.bone, bone=bone, is_skin=False)
    # bony crest sweeping back from the skull, and the eyes
    for s in (1, -1):
        part("crest%d" % s, tube_taper([(0.86, 0.05 * s, 0.93), (0.70, 0.09 * s, 0.99), (0.52, 0.12 * s, 1.0)], [0.022, 0.014, 0.003], 6), M.bone, bone="head", is_skin=False)
        part("eye%d" % s, sphere_bm(1.0, loc=(1.005, 0.088 * s, 0.887), scale=(0.022, 0.014, 0.016), segs=8, rings=5), M.eyes, bone="head", is_skin=False)
        # teeth: upper and lower rows of needles
        for k in range(7):
            x = 1.02 + k * 0.04
            w = 0.052 - k * 0.004
            part("tu%d_%d" % (k, s), tube_taper([(x, w * s, 0.80 - k * 0.006), (x, w * s * 0.96, 0.76 - k * 0.006)], [0.007, 0.001], 4), M.bone, bone="head", is_skin=False)
            part("tl%d_%d" % (k, s), tube_taper([(x + 0.01, w * s * 0.9, 0.745 - k * 0.003), (x + 0.01, w * s * 0.86, 0.785 - k * 0.003)], [0.006, 0.001], 4), M.bone, bone="jaw", is_skin=False)
    return M, skin_parts, other


def assemble():
    define_bones()
    M, skin_parts, other = build_body()
    # self-shadowing baked into the skin's vertex colours (armpits, between ribs, under the jaw)
    vertex_ao(skin_parts, skin_parts + other, ground=(6, 6), rays=10, maxd=0.5, strength=0.8)
    ao = make_armature()
    for ob in skin_parts + other:
        if ob["bone"]:
            rigid(ob, ob["bone"])
        else:
            skin(ob, list(ob["cands"]))
    allobj = skin_parts + other
    for ob in allobj:
        for k in ("cands", "bone"):
            del ob[k]
    mesh = join("gaunt", allobj)
    mod = mesh.modifiers.new("Armature", "ARMATURE")
    mod.object = ao
    mesh.parent = ao
    return ao, mesh


# ------------------------------------------------------------------ poses
# pose = {bone: (elevation, yaw, roll)}, plus "dz" (hips drop/lift) and "dx"/"dy"

SIDES = ("L", "R")


def S(x):
    return math.sin(x)


def C(x):
    return math.cos(x)


def pos(x):
    return max(0.0, x)


def smooth01(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    """Blend two poses."""
    out = {}
    for k in set(a) | set(b):
        va, vb = a.get(k), b.get(k)
        if k in ("dx", "dy", "dz"):
            out[k] = lerp(va or 0.0, vb or 0.0, t)
        else:
            va = va or (0.0, 0.0, 0.0)
            vb = vb or (0.0, 0.0, 0.0)
            out[k] = tuple(lerp(va[i], vb[i], t) for i in range(3))
    return out


def pose_idle(p):
    th = 2 * math.pi * p
    b = S(th)
    P = {"dz": -0.05 + 0.006 * b}
    P["spine1"] = (0.02 * b - 0.04, 0.0, 0.0)
    P["spine2"] = (0.03 * b - 0.04, 0.0, 0.0)
    P["chest"] = (0.03 * b, 0.0, 0.0)
    P["neck"] = (0.12 + 0.04 * b, 0.25 * S(th), 0.0)
    P["head"] = (-0.05 + 0.05 * b, 0.55 * S(th + 0.4), 0.05 * S(th))
    P["jaw"] = (-0.06 - 0.05 * pos(S(2 * th)), 0.0, 0.0)
    P["tail1"] = (0.1, 0.25 * S(th + 0.4), 0.0)
    P["tail2"] = (0.12, 0.40 * S(th + 0.8), 0.0)
    P["tail3"] = (0.12, 0.55 * S(th + 1.2), 0.0)
    for sd in SIDES:
        sg = 1 if sd == "L" else -1
        ph = 0.0 if sd == "L" else 1.7
        P["clav." + sd] = (0.1 + 0.04 * S(th + ph), 0.0, 0.0)
        P["upperarm." + sd] = (-0.25 + 0.03 * S(th + ph), 0.0, 0.0)
        P["forearm." + sd] = (-0.3 + 0.05 * S(th + ph), 0.0, 0.0)
        P["hand." + sd] = (-0.25 + 0.2 * pos(S(3 * th + ph)), 0.0, 0.0)
        P["thigh." + sd] = (0.08, 0.0, 0.0)
        P["shin." + sd] = (0.1, 0.0, 0.0)
        P["foot." + sd] = (0.17, 0.0, 0.0)
    return P


def leg_pair_walk(P, sd, q, low=True):
    """A walking leg set at phase q (radians): swing, fold while forward."""
    fold = pos(C(q))
    sw = S(q)
    # forelimb
    P["upperarm." + sd] = (-0.55 + 0.45 * sw, 0.0, 0.0)
    P["forearm." + sd] = (-0.05 + 0.3 * sw - 0.5 * fold, 0.0, 0.0)
    P["hand." + sd] = (-0.4 + 0.1 * sw - 0.4 * fold, 0.0, 0.0)
    P["clav." + sd] = (0.18 + 0.12 * sw, 0.0, 0.0)


def pose_stalk(p):
    th = 2 * math.pi * p
    P = {"dz": -0.17 + 0.012 * S(2 * th)}
    P["spine1"] = (0.03 + 0.04 * S(th), 0.05 * S(th), 0.0)
    P["spine2"] = (-0.16 + 0.05 * S(th + 0.5), -0.06 * S(th), 0.0)
    P["chest"] = (-0.14, 0.0, 0.0)
    P["neck"] = (0.05, -0.04 * S(th), 0.0)
    P["head"] = (-0.08, 0.1 * S(th + 1.0), 0.0)
    P["jaw"] = (-0.14 - 0.03 * S(2 * th), 0.0, 0.0)
    P["tail1"] = (0.0, 0.2 * S(th + 1.0), 0.0)
    P["tail2"] = (0.04, 0.3 * S(th + 1.5), 0.0)
    P["tail3"] = (0.06, 0.4 * S(th + 2.0), 0.0)
    # 4-beat walk: hind left, fore left, hind right, fore right
    for sd, qf, qh in (("L", 0.25, 0.0), ("R", 0.75, 0.5)):
        leg_pair_walk(P, sd, th + 2 * math.pi * qf)
        qq = th + 2 * math.pi * qh
        P["thigh." + sd] = (0.25 + 0.38 * S(qq), 0.0, 0.0)
        P["shin." + sd] = (0.19 + 0.26 * S(qq) - 0.44 * pos(C(qq)), 0.0, 0.0)
        P["foot." + sd] = (0.43 + 0.14 * S(qq) - 0.7 * pos(C(qq)), 0.0, 0.0)
    return P


def pose_sprint(p):
    th = 2 * math.pi * p
    ths = th + 0.4
    P = {"dz": -0.02 + 0.11 * S(2 * th + 0.6)}
    P["spine1"] = (0.17 * S(ths + 0.6), 0.0, 0.0)
    P["spine2"] = (0.2 * S(ths + 0.4) - 0.05, 0.0, 0.0)
    P["chest"] = (0.1 * S(ths + 0.2) - 0.04, 0.0, 0.0)
    P["neck"] = (0.12 - 0.12 * S(ths + 0.2), 0.0, 0.0)
    P["head"] = (-0.05 - 0.1 * S(ths), 0.0, 0.0)
    P["jaw"] = (-0.22 - 0.1 * S(th + 1.0), 0.0, 0.0)
    P["tail1"] = (0.28 + 0.1 * S(ths + 1.5), 0.0, 0.0)
    P["tail2"] = (0.25 + 0.14 * S(ths + 2.0), 0.15 * S(th), 0.0)
    P["tail3"] = (0.2 + 0.18 * S(ths + 2.4), 0.25 * S(th), 0.0)
    for sd, off_f, off_h in (("L", 0.0, 1.0), ("R", 0.35, 1.35)):
        q = th + off_f
        fold = pos(C(q))
        P["clav." + sd] = (0.2 * S(q), 0.0, 0.0)
        P["upperarm." + sd] = (0.15 + 0.95 * S(q), 0.0, 0.0)
        P["forearm." + sd] = (0.1 + 0.55 * S(q + 0.5) - 0.65 * fold, 0.0, 0.0)
        P["hand." + sd] = (0.0 + 0.3 * S(q + 0.9) - 0.4 * fold, 0.0, 0.0)
        qh = th + off_h
        fh = pos(C(qh))
        P["thigh." + sd] = (-0.36 + 1.05 * S(qh), 0.0, 0.0)
        P["shin." + sd] = (0.19 + 0.26 * S(qh) - 0.52 * fh, 0.0, 0.0)
        P["foot." + sd] = (0.25 + 0.35 * S(qh) - 0.79 * fh, 0.0, 0.0)
    return P


POUNCE_COIL = None


def pounce_key(name):
    P = {}
    if name == "coil":
        P["dz"] = -0.34
        P["dx"] = 0.0
        P["spine1"] = (-0.25, 0.0, 0.0)
        P["spine2"] = (-0.22, 0.0, 0.0)
        P["chest"] = (-0.12, 0.0, 0.0)
        P["neck"] = (0.1, 0.0, 0.0)
        P["head"] = (0.0, 0.0, 0.0)
        P["jaw"] = (-0.25, 0.0, 0.0)
        P["tail1"] = (0.5, 0.0, 0.0)
        P["tail2"] = (0.6, 0.0, 0.0)
        P["tail3"] = (0.5, 0.0, 0.0)
        for sd in SIDES:
            P["clav." + sd] = (0.2, 0.0, 0.0)
            P["upperarm." + sd] = (-0.5, 0.0, 0.0)
            P["forearm." + sd] = (0.1, 0.0, 0.0)
            P["hand." + sd] = (-0.2, 0.0, 0.0)
            P["thigh." + sd] = (0.77, 0.0, 0.0)
            P["shin." + sd] = (0.54, 0.0, 0.0)
            P["foot." + sd] = (0.95, 0.0, 0.0)
    elif name == "fly":
        P["dz"] = 0.32
        P["dx"] = 0.0
        P["spine1"] = (0.14, 0.0, 0.0)
        P["spine2"] = (0.1, 0.0, 0.0)
        P["chest"] = (0.12, 0.0, 0.0)
        P["neck"] = (0.1, 0.0, 0.0)
        P["head"] = (-0.1, 0.0, 0.0)
        P["jaw"] = (-0.85, 0.0, 0.0)
        P["tail1"] = (-0.15, 0.0, 0.0)
        P["tail2"] = (-0.2, 0.0, 0.0)
        P["tail3"] = (-0.1, 0.0, 0.0)
        for sd in SIDES:
            sg = 1 if sd == "L" else -1
            P["clav." + sd] = (0.5, 0.0, 0.0)
            P["upperarm." + sd] = (1.55, 0.14 * sg, 0.0)
            P["forearm." + sd] = (0.55, 0.1 * sg, 0.0)
            P["hand." + sd] = (0.25, 0.0, 0.0)
            P["thigh." + sd] = (-2.02, 0.0, 0.0)
            P["shin." + sd] = (-0.19, 0.0, 0.0)
            P["foot." + sd] = (-1.84, 0.0, 0.0)
    elif name == "land":
        P["dz"] = -0.12
        P["spine1"] = (-0.1, 0.0, 0.0)
        P["spine2"] = (-0.1, 0.0, 0.0)
        P["chest"] = (-0.1, 0.0, 0.0)
        P["neck"] = (0.05, 0.0, 0.0)
        P["head"] = (0.0, 0.0, 0.0)
        P["jaw"] = (-0.5, 0.0, 0.0)
        P["tail1"] = (0.3, 0.0, 0.0)
        P["tail2"] = (0.3, 0.0, 0.0)
        P["tail3"] = (0.2, 0.0, 0.0)
        for sd in SIDES:
            P["clav." + sd] = (0.3, 0.0, 0.0)
            P["upperarm." + sd] = (0.5, 0.0, 0.0)
            P["forearm." + sd] = (0.3, 0.0, 0.0)
            P["hand." + sd] = (-0.2, 0.0, 0.0)
            P["thigh." + sd] = (0.51, 0.0, 0.0)
            P["shin." + sd] = (0.37, 0.0, 0.0)
            P["foot." + sd] = (0.69, 0.0, 0.0)
    return P


def pose_pounce(f):
    """One-shot, 28 frames: 0-9 coil (quivering), 9-12 launch, 12-24 flight, 24-27 landing."""
    coil, fly, land = pounce_key("coil"), pounce_key("fly"), pounce_key("land")
    if f <= 9:
        # settle down into the coil, then shiver
        P = mix(pose_stalk(0.0), coil, smooth01(f / 7.0))
        sh = 0.02 * S(f * 2.1) * smooth01(f / 7.0)
        P["spine2"] = (P["spine2"][0] + sh, 0, 0)
        P["tail3"] = (P["tail3"][0], 0.3 * S(f * 1.3), 0)
        return P
    if f <= 12:
        return mix(coil, fly, smooth01((f - 9) / 3.0))
    if f <= 24:
        t = (f - 12) / 12.0
        P = dict(fly)
        P["thigh.L"] = (fly["thigh.L"][0] + 0.9 * t, 0, 0)
        P["thigh.R"] = (fly["thigh.R"][0] + 0.9 * t, 0, 0)
        P["dz"] = fly["dz"] - 0.08 * t * t
        P["upperarm.L"] = (fly["upperarm.L"][0] - 0.2 * t, 0.12, 0)
        P["upperarm.R"] = (fly["upperarm.R"][0] - 0.2 * t, -0.12, 0)
        return P
    P = mix(fly, land, smooth01((f - 24) / 3.0))
    return P


def pose_latch(p):
    th = 2 * math.pi * p
    P = {"dz": -0.2 + 0.015 * S(2 * th)}
    P["spine1"] = (-0.12 + 0.1 * S(2 * th), 0.08 * S(th), 0.0)
    P["spine2"] = (0.05 + 0.08 * S(2 * th + 0.5), -0.08 * S(th), 0.0)
    P["chest"] = (0.12, 0.1 * S(th), 0.04 * S(th))
    P["neck"] = (0.28 + 0.12 * S(2 * th), 0.4 * S(th), 0.0)
    P["head"] = (-0.1 + 0.1 * S(2 * th), 0.8 * S(th + 0.6), 0.1 * S(th))
    P["jaw"] = (-0.15 - 0.55 * pos(S(2 * th + 0.3)), 0.0, 0.0)
    P["tail1"] = (0.3, 0.3 * S(th), 0.0)
    P["tail2"] = (0.35, 0.5 * S(th + 0.7), 0.0)
    P["tail3"] = (0.3, 0.7 * S(th + 1.4), 0.0)
    for sd, ph in (("L", 0.0), ("R", math.pi)):
        sg = 1 if sd == "L" else -1
        P["clav." + sd] = (0.45 + 0.1 * S(th + ph), 0.0, 0.0)
        P["upperarm." + sd] = (1.35 + 0.3 * S(th + ph), 0.2 * sg, 0.0)
        P["forearm." + sd] = (0.75 + 0.35 * S(th + ph + 0.6), 0.1 * sg, 0.0)
        P["hand." + sd] = (0.2 - 0.4 * pos(S(th + ph)), 0.0, 0.0)
        P["thigh." + sd] = (0.6, 0.0, 0.0)
        P["shin." + sd] = (0.45, 0.0, 0.0)
        P["foot." + sd] = (0.6 + 0.15 * S(th + ph), 0.0, 0.0)
    return P


def pose_thrown(p):
    th = 2 * math.pi * p
    P = {"dz": 0.15 * S(th)}
    P["spine1"] = (0.3 * S(th), 0.2 * S(2 * th), 0.0)
    P["spine2"] = (0.35 * S(th + 0.5), 0.2 * S(2 * th + 1.0), 0.0)
    P["chest"] = (0.2 * S(th + 1.0), 0.0, 0.0)
    P["neck"] = (0.3 * S(th + 1.5), 0.3 * S(th), 0.0)
    P["head"] = (0.3 * S(th + 2.0), 0.0, 0.0)
    P["jaw"] = (-0.6 - 0.3 * S(2 * th), 0.0, 0.0)
    P["tail1"] = (0.3 * S(th), 0.5 * S(th + 1.0), 0.0)
    P["tail2"] = (0.4 * S(th + 0.5), 0.7 * S(th + 1.5), 0.0)
    P["tail3"] = (0.4 * S(th + 1.0), 0.9 * S(th + 2.0), 0.0)
    for k, sd in enumerate(SIDES):
        sg = 1 if sd == "L" else -1
        ph = k * 2.2
        P["clav." + sd] = (0.3 * S(th + ph), 0.0, 0.0)
        P["upperarm." + sd] = (1.0 + 0.9 * S(th + ph), 0.5 * sg, 0.0)
        P["forearm." + sd] = (0.5 + 0.6 * S(th + ph + 1.0), 0.2 * sg, 0.0)
        P["hand." + sd] = (0.4 * S(2 * th + ph), 0.0, 0.0)
        P["thigh." + sd] = (0.2 + 0.9 * S(th + ph + 1.5), 0.3 * sg, 0.0)
        P["shin." + sd] = (-0.4 + 0.6 * S(th + ph + 2.2), 0.0, 0.0)
        P["foot." + sd] = (0.3 * S(2 * th + ph), 0.0, 0.0)
    return P


def pose_dead(f):
    t = smooth01(f / 12.0)
    A = pose_sprint(0.0)
    P = {"dz": -0.55}
    P["spine1"] = (-0.1, 0.0, 0.0)
    P["spine2"] = (-0.2, 0.0, 0.1)
    P["chest"] = (-0.1, 0.1, 0.1)
    P["neck"] = (-0.05, 0.4, 0.0)
    P["head"] = (-0.2, 0.2, 0.2)
    P["jaw"] = (-0.5, 0.0, 0.0)
    P["tail1"] = (-0.05, 0.4, 0.0)
    P["tail2"] = (-0.05, 0.6, 0.0)
    P["tail3"] = (-0.05, 0.7, 0.0)
    for sd in SIDES:
        sg = 1 if sd == "L" else -1
        P["clav." + sd] = (-0.1, 0.0, 0.0)
        P["upperarm." + sd] = (-0.05, 0.9 * sg, 0.0)
        P["forearm." + sd] = (-0.2, 0.3 * sg, 0.0)
        P["hand." + sd] = (-0.3, 0.0, 0.0)
        P["thigh." + sd] = (-0.1, 0.7 * sg, 0.0)
        P["shin." + sd] = (-0.4, 0.3 * sg, 0.0)
        P["foot." + sd] = (-0.2, 0.0, 0.0)
    return mix(A, P, t)


# name -> (frames, looping, pose function of (phase for loops | frame for one-shots))
CLIPS = {
    "idle": (60, True, pose_idle),
    "stalk": (48, True, pose_stalk),
    "sprint": (16, True, pose_sprint),
    "pounce": (28, False, pose_pounce),
    "latch": (24, True, pose_latch),
    "thrown": (24, True, pose_thrown),
    "dead": (14, False, pose_dead),
}


def pose_bone_rotations(P, ao, rest):
    """Turn absolute armature-space deltas into local pose-bone rotations (see module docstring)."""
    A = {}
    for name in BONES:
        e, yw, rl = P.get(name, (0.0, 0.0, 0.0))
        A[name] = Matrix.Rotation(yw, 3, "Z") @ Matrix.Rotation(-e, 3, "Y") @ Matrix.Rotation(rl, 3, "X")
    out = {}
    for name, (_, _, par) in BONES.items():
        Ap = A[par] if par else Matrix.Identity(3)
        B = rest[name]
        rel = Ap.inverted() @ A[name]
        out[name] = (B.inverted() @ rel @ B).to_quaternion()
    return out


def apply_pose(ao, P, rest):
    qs = pose_bone_rotations(P, ao, rest)
    for pb in ao.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = qs[pb.name]
    hips = ao.pose.bones["hips"]
    d = Vector((P.get("dx", 0.0), P.get("dy", 0.0), P.get("dz", 0.0)))
    hips.location = rest["hips"].inverted() @ d


def animate(ao):
    ao.animation_data_create()
    rest = {b.name: b.matrix_local.to_3x3() for b in ao.data.bones}
    actions = []
    for name, (n, looping, fn) in CLIPS.items():
        act = bpy.data.actions.new(name)
        ao.animation_data.action = act
        keys = n + 1 if looping else n
        for f in range(keys):
            P = fn(f / n) if looping else fn(f)
            apply_pose(ao, P, rest)
            for pb in ao.pose.bones:
                pb.keyframe_insert("rotation_quaternion", frame=f + 1)
            ao.pose.bones["hips"].keyframe_insert("location", frame=f + 1)
        act.use_fake_user = True
        actions.append(act)
    ao.animation_data.action = actions[0]
    return actions


# ------------------------------------------------------------------ previews


def preview_sheet(ao, mesh):
    """Render a few frames of every clip, side on, for checking."""
    sc = bpy.context.scene
    out_dir = "/private/tmp/hh_prev"
    os.makedirs(out_dir, exist_ok=True)
    rest = {b.name: b.matrix_local.to_3x3() for b in ao.data.bones}
    ao.animation_data.action = None  # or the action overrides the manual pose at render time
    frames = {
        "idle": [0, 15, 30],
        "stalk": [0, 12, 24, 36],
        "sprint": [0, 4, 8, 12],
        "pounce": [0, 8, 11, 16, 22, 27],
        "latch": [0, 6, 12, 18],
        "thrown": [0, 8, 16],
        "dead": [0, 13],
    }
    only = os.environ.get("ONLY")  # e.g. ONLY=sprint:0,8,pounce:16
    if only:
        frames = {}
        cur = None
        for tok in only.split(","):
            if ":" in tok:
                cur, tok = tok.split(":")
                frames.setdefault(cur, [])
            frames[cur].append(int(tok))
    res = tuple(int(x) for x in os.environ.get("RES", "560x360").split("x"))
    cam = tuple(float(x) for x in os.environ.get("CAM", "1.2,-4.4,1.2").split(","))
    for name, (n, looping, fn) in list(CLIPS.items()) + [("rest", (1, True, lambda p: {}))]:
        for f in frames.get(name, []):
            P = fn(f / n) if looping else fn(f)
            apply_pose(ao, P, rest)
            bpy.context.view_layer.update()
            for ob in list(bpy.data.objects):
                if ob.name.startswith(("sun", "cam")):
                    bpy.data.objects.remove(ob)
            preview(os.path.join(out_dir, "gaunt_%s_%02d.png" % (name, f)), cam, (0.0, 0, 0.55), lens=42, res=res, sun_rot=(0.9, 0.3, 0.5), world="#1c2630", sun=2.4, fill=1.8)


if __name__ == "__main__":
    ao, mesh = assemble()
    animate(ao)
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.frame_start, sc.frame_end = 1, 61
    if "preview" in ARGS:
        preview_sheet(ao, mesh)
    else:
        # restore the rest pose for export
        for pb in ao.pose.bones:
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)
    export(os.path.join(OUT, "gaunt.glb"), [ao, mesh], extra=dict(export_animations=True, export_animation_mode="ACTIONS", export_skins=True, export_force_sampling=True, export_frame_range=False, export_optimize_animation_size=False))

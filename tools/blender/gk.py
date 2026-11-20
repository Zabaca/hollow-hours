"""Geometry kit shared by the creature scripts (Blender 5.3 Python): smooth elliptical tubes through points, lofted bodies,
long-fingered hands, and the Maker that collects parts per material. Coordinates are Blender's: Z up, +X forward."""
import math
import bpy, bmesh
from mathutils import Vector, Matrix
from rk import make_obj, sphere_bm, add_mod, bake, join

# ------------------------------------------------------------------ geometry

def lerp(a, b, t):
    return a + (b - a) * t


def prof(t, table):
    """Piecewise-linear lookup: table is [(t, value), ...] ascending."""
    if t <= table[0][0]:
        return table[0][1]
    for (t0, v0), (t1, v1) in zip(table, table[1:]):
        if t <= t1:
            return lerp(v0, v1, (t - t0) / (t1 - t0))
    return table[-1][1]


def spline(points, radii_u, radii_v, per=6):
    """Catmull-Rom through points; two radius lists interpolated smoothly alongside."""
    P = [Vector(p) for p in points]
    n = len(P)
    ext = [P[0] * 2 - P[1]] + P + [P[-1] * 2 - P[-2]]
    pts, ru, rv = [], [], []
    for i in range(1, n):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            pts.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
            tt = t * t * (3 - 2 * t)
            ru.append(lerp(radii_u[i - 1], radii_u[i], tt))
            rv.append(lerp(radii_v[i - 1], radii_v[i], tt))
    pts.append(P[-1])
    ru.append(radii_u[-1])
    rv.append(radii_v[-1])
    return pts, ru, rv


def etube_bm(points, ru, rv=None, per=6, segs=10, ref=(0, 1, 0), cap=True, flat=False):
    """A smooth tube through points with an elliptical section: ru across `ref` (default lateral, Y), rv the other way.
    ru/rv may be one number or a list per point. flat=True keeps the end caps as single points (a pointed end)."""
    points = [Vector(p) for p in points]
    n = len(points)
    ru = [ru] * n if not isinstance(ru, (list, tuple)) else list(ru)
    rv = ru if rv is None else ([rv] * n if not isinstance(rv, (list, tuple)) else list(rv))
    pts, RU, RV = spline(points, ru, rv, per) if n > 2 else spline([points[0], points[0] * 0.5 + Vector(points[1]) * 0.5, points[1]], [ru[0], (ru[0] + ru[1]) / 2, ru[1]], [rv[0], (rv[0] + rv[1]) / 2, rv[1]], per)
    bm = bmesh.new()
    rings = []
    refv = Vector(ref)
    for i, p in enumerate(pts):
        if i == 0:
            d = pts[1] - pts[0]
        elif i == len(pts) - 1:
            d = pts[i] - pts[i - 1]
        else:
            d = pts[i + 1] - pts[i - 1]
        d = d.normalized()
        u = refv - d * refv.dot(d)
        if u.length < 0.2:
            alt = Vector((0, 0, 1)) if abs(refv.z) < 0.9 else Vector((1, 0, 0))
            u = alt - d * alt.dot(d)
        u = u.normalized()
        v = d.cross(u).normalized()
        rings.append([bm.verts.new(p + u * (math.cos(2 * math.pi * j / segs) * RU[i]) + v * (math.sin(2 * math.pi * j / segs) * RV[i])) for j in range(segs)])
    for i in range(len(rings) - 1):
        for j in range(segs):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % segs], rings[i + 1][(j + 1) % segs], rings[i + 1][j]))
    if cap:
        bm.faces.new(rings[0][::-1])
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def merge(bms):
    out = bmesh.new()
    for b in bms:
        me = bpy.data.meshes.new("tmp")
        b.to_mesh(me)
        b.free()
        out.from_mesh(me)
        bpy.data.meshes.remove(me)
    return out


def blob(c, r, scale=(1, 1, 1), segs=12, rings=8):
    return sphere_bm(1.0, loc=c, scale=tuple(x * r for x in scale) if not isinstance(r, (tuple, list)) else r, segs=segs, rings=rings)


class Maker:
    """Collects parts into one mesh per material, subdivided and joined at the end."""

    def __init__(self):
        self.groups = {}

    def add(self, material_key, bm, subdiv=1):
        self.groups.setdefault((material_key, subdiv), []).append(bm)

    def sub(self, matrix):
        """A view of this maker whose parts are built in a local frame and carried by `matrix` (a head, a hand)."""
        parent = self

        class Sub:
            def add(self, key, bm, subdiv=1):
                bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
                parent.add(key, bm, subdiv)

        return Sub()

    def build(self, mats, name="creature"):
        objs = []
        for (key, subdiv), bms in self.groups.items():
            ob = make_obj("%s_%s" % (name, key), merge(bms), mats[key], smooth=True)
            if subdiv:
                add_mod(ob, "SUBSURF", levels=subdiv, render_levels=subdiv)
                bpy.context.view_layer.update()
                bake(ob)
            objs.append(ob)
        out = join(name, objs)
        return out


def V(*a):
    return Vector(a if len(a) == 3 else a[0])


def path(keys, n):
    """n points along a Catmull-Rom curve through keys, with the parameter 0..1 for each."""
    pts, _, _ = spline(keys, [0] * len(keys), [0] * len(keys), per=24)
    out = []
    for i in range(n):
        out.append(pts[int(round(i / (n - 1) * (len(pts) - 1)))])
    return out


def body(maker, key, keys, n, ru, rv, segs=12, subdiv=1, ref=(0, 1, 0), bumps=None):
    """A torso or neck lofted along keys with n stations; ru(t), rv(t) give the half-width (across ref) and half-depth.
    bumps(i) multiplies both radii (ribs: alternate stations)."""
    pts = path(keys, n)
    RU = [ru(i / (n - 1)) * (bumps(i) if bumps else 1.0) for i in range(n)]
    RV = [rv(i / (n - 1)) * (bumps(i) if bumps else 1.0) for i in range(n)]
    maker.add(key, etube_bm(pts, RU, RV, per=1, segs=segs, ref=ref), subdiv)
    return pts


def jlimb(maker, key, pts, radii, knob=1.2, ratio=1.0, segs=10, per=4, ref=(0, 1, 0), subdiv=0, belly=(1.0, 1.0)):
    """A limb through joint points: straight shafts between joints (two extra control points per shaft), a knob at each joint."""
    keys, rr, rv = [], [], []
    n = len(pts)
    for i in range(n):
        p = Vector(pts[i])
        r = radii[i]
        if 0 < i < n - 1:
            r *= knob
        keys.append(p)
        rr.append(r)
        if i < n - 1:
            q = Vector(pts[i + 1])
            r2 = radii[i + 1] * (knob if i + 1 < n - 1 else 1.0)
            for t, bl in ((0.3, belly[0]), (0.7, belly[1])):
                keys.append(p.lerp(q, t))
                rr.append(lerp(radii[i], radii[i + 1], t) * 0.92 * bl)
    maker.add(key, etube_bm(keys, rr, [r * ratio for r in rr], per=per, segs=segs, ref=ref), subdiv)
    return keys


def limb(maker, key, keys, ru, rv=None, per=7, segs=10, ref=(0, 1, 0), subdiv=0):
    maker.add(key, etube_bm(keys, ru, rv, per=per, segs=segs, ref=ref), subdiv)


def spike(maker, key, base, tip, r, segs=6):
    maker.add(key, etube_bm([Vector(base), Vector(tip)], [r, r * 0.04], [r, r * 0.04], per=2, segs=segs, cap=False), 0)


def eye(maker, c, r, key="eye", scale=(1, 1, 1)):
    maker.add(key, sphere_bm(1.0, loc=c, scale=tuple(r * x for x in scale), segs=10, rings=7), 0)


def finger(maker, key, base, d, bend_axis, lens, bends, r0=0.011, taper=0.4, bone_key=None):
    """A finger of len(lens) segments: direction `d`, each joint bending about bend_axis by bends[i] radians. Tip is a point."""
    d = Vector(d).normalized()
    ax = Vector(bend_axis).normalized()
    p = Vector(base)
    pts = [p.copy()]
    for L, b in zip(lens, bends):
        d = (Matrix.Rotation(b, 3, ax) @ d).normalized()
        p = p + d * L
        pts.append(p.copy())
    n = len(pts)
    rr = [r0 * (1 - (1 - taper) * i / (n - 1)) for i in range(n)]
    rr[-1] = r0 * taper * 0.55
    maker.add(key, etube_bm(pts, rr, rr, per=3, segs=6, ref=(0, 0, 1) if abs(d.z) < 0.9 else (1, 0, 0)), 0)
    return pts


def hand(maker, key, wrist, fwd, side, down_normal, spread=0.2, flen=0.26, curl=0.35, r0=0.011, n=5, claw_key=None, palm_maker=None):
    """A long-fingered hand: n fingers fanned across `side`, pointing along `fwd`, curling toward `down_normal`."""
    fwd = Vector(fwd).normalized()
    side = Vector(side).normalized()
    dn = Vector(down_normal).normalized()
    ax = fwd.cross(dn).normalized()
    (palm_maker or maker).add(key, etube_bm([Vector(wrist), Vector(wrist) + fwd * 0.09], [0.034, 0.042], [0.014, 0.016], per=2, segs=8, ref=tuple(side)), 0)
    fingers = []
    for i in range(n):
        o = (i - (n - 1) / 2)
        base = Vector(wrist) + fwd * 0.09 + side * (o * 0.021)
        d = (Matrix.Rotation(o * spread * 0.5, 3, dn) @ fwd)
        L = flen * (1.0 - 0.13 * abs(o) * (0.6 if i in (0, n - 1) else 0.3))
        if i == 0 and n == 5:
            L *= 0.8
        pts = finger(maker, key, base, d, ax, (L * 0.42, L * 0.33, L * 0.25), (0.05 * curl, curl * 0.8, curl * 0.9), r0=r0)
        fingers.append(pts)
        if claw_key:
            tip = pts[-1]
            dd = (pts[-1] - pts[-2]).normalized()
            spike(maker, claw_key, tip - dd * 0.01, tip + dd * 0.05 + dn * 0.01, r0 * 0.7)
    return fingers


def seg_point_dist(p, a, b):
    ab = b - a
    t = 0.0 if ab.length_squared < 1e-12 else max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


def dent_bm(bm, dents):
    """Push the surface inward (against the vertex normal) near each dent: (a, b, radius, depth), a..b a segment (a == b a point),
    a cosine falloff. Sockets, hollow cheeks, a torn mouth corner."""
    bm.normal_update()
    for v in bm.verts:
        push = 0.0
        for a, b, r, depth in dents:
            d = seg_point_dist(v.co, Vector(a), Vector(b))
            if d < r:
                push = max(push, depth * 0.5 * (1.0 + math.cos(math.pi * d / r)))
        if push > 0.0:
            v.co -= v.normal * push
    return bm


def ribbon_bm(pts, widths, across, cols=3, jag=0.25, wave=0.01, holes=0.0, seed=1, rows_per=3):
    """A ragged strip of cloth or a clump of hair: a grid along the path, `across` the direction of its width, an uneven end
    (every column stops at its own length, `jag` is how much), a gentle wave and, with `holes`, torn gaps. Single sided."""
    import random
    rnd = random.Random(seed)
    P = [Vector(p) for p in pts]
    path_pts, w, _ = spline(P, list(widths), list(widths), per=rows_per)
    pts_d = path_pts
    n = len(pts_d) - 1
    A = Vector(across).normalized()
    bm = bmesh.new()
    lens = [1.0 - jag * rnd.random() for _ in range(cols + 1)]
    grid = []
    for c in range(cols + 1):
        col = []
        ph = rnd.random() * 6.28
        for i in range(n + 1):
            s = i / n * lens[c]
            k = s * n
            i0 = min(int(k), n - 1)
            fr = k - i0
            p = pts_d[i0].lerp(pts_d[i0 + 1], fr)
            ww = lerp(w[i0], w[i0 + 1], fr)
            d = (pts_d[min(i0 + 1, n)] - pts_d[i0]).normalized() if i0 < n else Vector((0, 0, -1))
            nrm = d.cross(A).normalized()
            off = (c / cols - 0.5) * ww
            q = p + A * off + nrm * (wave * math.sin(ph + s * 9.0 + c * 1.3))
            col.append(bm.verts.new(q))
        grid.append(col)
    for c in range(cols):
        for i in range(n):
            if holes and 1 < i < n - 1 and rnd.random() < holes:
                continue
            bm.faces.new((grid[c][i], grid[c + 1][i], grid[c + 1][i + 1], grid[c][i + 1]))
    return bm


def tooth_bm(base, up, w, d, h, tilt=(0.0, 0.0), pointed=0.0):
    """One tooth: a rounded block from `base` along `up`, w wide, d deep, h long; `pointed` thins the tip (a canine)."""
    up = Vector(up).normalized()
    ref = Vector((0, 1, 0)) if abs(up.y) < 0.9 else Vector((1, 0, 0))
    u = up.cross(ref).normalized()
    v = up.cross(u).normalized()
    up = (up + u * tilt[0] + v * tilt[1]).normalized()
    bm = bmesh.new()
    rings = []
    segs = 8
    steps = 5
    for i in range(steps + 1):
        t = i / steps
        sc = 1.0 - pointed * t * t - (0.35 * t ** 4)
        rw = max(0.0, w * 0.5 * sc * (0.85 + 0.15 * math.sin(math.pi * min(1.0, t * 1.3))))
        rd = max(0.0, d * 0.5 * sc * (0.85 + 0.15 * math.sin(math.pi * min(1.0, t * 1.3))))
        ctr = Vector(base) + up * (h * t)
        rings.append([bm.verts.new(ctr + u * (math.cos(2 * math.pi * j / segs) * rw) + v * (math.sin(2 * math.pi * j / segs) * rd)) for j in range(segs)])
    for i in range(steps):
        for j in range(segs):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % segs], rings[i + 1][(j + 1) % segs], rings[i + 1][j]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm

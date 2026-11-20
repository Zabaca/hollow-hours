"""The Gaunt's body: its rest skeleton, its surface, its skinning and its baked skin textures (Blender 5.3 Python).

The parts are modelled at rest (a hunched stand, arms hanging) from smooth tubes and blobs. The ones that make up the big
forms (torso, limbs, neck, skull, palms) are fused into one continuous surface by a voxel remesh, so there is no ball joint
and no seam where a limb meets the body; the fine anatomy (ribs, collar bones, spine, tendons, knuckles, neck cords) rides on
that surface as separate pieces; the jaw, fingers, toes, teeth, cloth and hair are their own meshes. The skin is a procedural
material baked to an albedo, a roughness and a normal map (Cycles, headless), and the glTF carries those.
"""
import sys, os, math, tempfile, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, Matrix, noise
from rk import *
from gk import *

TEX = os.environ.get("HH_TEX", os.path.join(tempfile.gettempdir(), "hollow-hours-tex"))
TEX_SIZE = int(os.environ.get("HH_TEX_SIZE", "2048"))
VOXEL = float(os.environ.get("HH_VOXEL", "0.008"))
BODY_TRIS = int(os.environ.get("HH_BODY_TRIS", "34000"))

# ------------------------------------------------------------------ the rest skeleton (hunched stand, arms hanging)

HIP = V(-0.05, 0, 1.10)
S1, S2, S3 = V(0.10, 0, 1.38), V(0.30, 0, 1.64), V(0.47, 0, 1.80)
N1, N2 = V(0.62, 0, 1.84), V(0.76, 0, 1.87)
HEAD_PITCH0 = 0.12  # the head's face tilts down by this at rest
HP = V(0.84, 0, 1.88)  # centre of the skull
HEAD_TAIL = V(0.90, 0, 1.853)
HINGE = V(0.82, 0, 1.82)
CHIN = V(0.905, 0, 1.415)
SHOULDER_Y, SHOULDER_Z = 0.20, 1.80
ELBOW = V(0.40, 0.28, 1.30)  # left; the right mirrors y
WRIST = V(0.52, 0.27, 0.76)
HIPJ_Y = 0.10
KNEE = V(0.14, 0.12, 0.62)
ANKLE = V(0.03, 0.12, 0.10)
BALL = V(0.28, 0.12, 0.04)
TOE = V(0.41, 0.12, 0.012)
M_HEAD = Matrix.Translation(HP) @ Matrix.Rotation(HEAD_PITCH0, 4, "Y")
SIDES = (("L", 1), ("R", -1))


def mir(v, s):
    return V(v.x, v.y * s, v.z)


# ------------------------------------------------------------------ parts: collected, fused or skinned by bone

PARTS = []  # (key material, bm, subdiv, bones, union)


class Sink:
    """Quacks like the gk Maker (add(key, bm, subdiv)) but remembers which bones the parts belong to, whether they fuse into
    the main surface, and an optional matrix that carries them from a local frame (the head's)."""

    def __init__(self, bones, matrix=None, union=False):
        self.bones = bones
        self.matrix = matrix
        self.union = union

    def add(self, key, bm, subdiv=0):
        if self.matrix is not None:
            bmesh.ops.transform(bm, matrix=self.matrix, verts=bm.verts)
        PARTS.append((key, bm, subdiv, self.bones, self.union))


def at(*bones, matrix=None, union=False):
    return Sink(list(bones), matrix, union)


def make_materials():
    M = {}
    M["skin"] = mat("skin", "#7a7c76", rough=0.42, coat=0.5, coat_rough=0.12)  # replaced by the baked one at the end
    M["teeth"] = mat("teeth", "#7d6f4d", rough=0.5, coat=0.2, coat_rough=0.3)
    M["bone"] = mat("bone", "#8f8468", rough=0.62, coat=0.1, coat_rough=0.4)
    M["eyes"] = mat("eyes", "#f2eec4", rough=0.25, emit="#e8e6a8", emit_strength=4.0)
    M["mouth"] = mat("mouth", "#050203", rough=0.7)
    M["cloth"] = mat("cloth", "#27231f", rough=0.9, coat=0.15, coat_rough=0.4)
    M["cloth"].use_backface_culling = False
    M["hair"] = mat("hair", "#15100e", rough=0.65, coat=0.05, coat_rough=0.5)
    M["hair"].use_backface_culling = False
    return M


BONES = {}  # name -> (head, tail, parent)


def define_bones(fingers):
    """`fingers`: the finger point lists of the left hand, to place the finger bones along the middle finger."""
    B = BONES
    B.clear()
    B["root"] = (V(0, 0, 0), V(0, 0, 0.15), None)
    B["hips"] = (HIP, HIP + V(0.0, 0, 0.12), "root")
    B["spine1"] = (HIP, S1, "hips")
    B["spine2"] = (S1, S2, "spine1")
    B["chest"] = (S2, S3, "spine2")
    B["neck1"] = (S3, N1, "chest")
    B["neck2"] = (N1, N2, "neck1")
    B["head"] = (N2, HEAD_TAIL, "neck2")
    B["jaw"] = (HINGE, CHIN, "head")
    mid = fingers[2]
    for sd, s in SIDES:
        sh = V(0.46, SHOULDER_Y * s, SHOULDER_Z)
        B["clav." + sd] = (V(0.45, 0.03 * s, SHOULDER_Z), sh, "chest")
        B["upperarm." + sd] = (sh, mir(ELBOW, s), "clav." + sd)
        B["forearm." + sd] = (mir(ELBOW, s), mir(WRIST, s), "upperarm." + sd)
        B["hand." + sd] = (mir(WRIST, s), mir(mid[0], s), "forearm." + sd)
        B["f1." + sd] = (mir(mid[0], s), mir(mid[1], s), "hand." + sd)
        B["f2." + sd] = (mir(mid[1], s), mir(mid[3], s), "f1." + sd)
        hipj = V(HIP.x, HIPJ_Y * s, 1.08)
        B["thigh." + sd] = (hipj, mir(KNEE, s), "hips")
        B["shin." + sd] = (mir(KNEE, s), mir(ANKLE, s), "thigh." + sd)
        B["foot." + sd] = (mir(ANKLE, s), mir(BALL, s), "shin." + sd)
        B["toes." + sd] = (mir(BALL, s), mir(TOE, s), "foot." + sd)


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.dot(ab), 1e-9)))
    return (p - (a + ab * t)).length


def skin_weights(ob, cands, power=4.0, top=4, offset=0.02):
    """Smooth weights from the distance to each candidate bone's segment, normalised, the strongest `top` kept."""
    me = ob.data
    groups = {n: ob.vertex_groups.new(name=n) for n in cands}
    segs = {n: (BONES[n][0], BONES[n][1]) for n in cands}
    for v in me.vertices:
        ws = []
        for n in cands:
            d = seg_dist(v.co, *segs[n])
            ws.append((1.0 / (d + offset) ** power, n))
        ws.sort(reverse=True)
        ws = ws[:top]
        tot = sum(w for w, _ in ws)
        for w, n in ws:
            if w / tot > 0.01:
                groups[n].add([v.index], w / tot, "REPLACE")


def rigid_weights(ob, bone):
    vg = ob.vertex_groups.new(name=bone)
    vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")


# ------------------------------------------------------------------ the body

def lat(s):
    return "L" if s == 1 else "R"


def build_parts():
    """Model the creature at rest as a list of parts in PARTS. Returns the left-hand finger point lists (for the rig)."""
    PARTS.clear()
    # --- torso: a deep starved ribcage over a sunken belly, a slight curve to the spine; the ribs are separate pieces on it
    keys = [HIP, V(0.10, 0.012, 1.38), V(0.30, 0.028, 1.64), V(0.47, 0.012, 1.80)]
    ru_t = [(0, 0.115), (0.25, 0.082), (0.52, 0.14), (0.78, 0.155), (1.0, 0.15)]
    rv_t = [(0, 0.09), (0.25, 0.058), (0.52, 0.112), (0.78, 0.115), (1.0, 0.07)]
    n = 30
    torso = at("hips", "spine1", "spine2", "chest", union=True)
    pts = body(torso, "skin", keys, n, lambda t: prof(t, ru_t), lambda t: prof(t, rv_t), segs=20, subdiv=0,
               bumps=lambda i: (1.05 if i % 2 == 0 else 0.99) if 9 <= i <= 26 else 1.0)

    def tangent(i):
        return (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()

    def back_at(i):
        d = tangent(i)
        return Vector((-d.z, 0, d.x))

    def surf(i, phi, s=1, grow=0.0):
        """A point on the ribcage at station i: phi 0 = the side, pi/2 = the back, -pi/2 = the front."""
        t = i / (n - 1)
        ru, rv = prof(t, ru_t) + grow, prof(t, rv_t) + grow
        return pts[i] + Vector((0, 1, 0)) * s * ru * math.cos(phi) + back_at(i) * rv * math.sin(phi)

    ribs = at("spine1", "spine2", "chest")
    for sd, s in SIDES:
        for r, i in enumerate(range(10, 27, 2)):
            rp = []
            for k in range(10):
                phi = lerp(1.3, -1.15, k / 9.0)
                shift = -0.05 * (1.3 - phi) / 2.45
                rp.append(surf(i, phi, s, 0.0035) + tangent(i) * shift)
            ribs.add("skin", etube_bm(rp, [0.0085 if s == 1 else 0.0095] * 10, per=2, segs=6, ref=(0, 0, 1)), 0)
    ribs.add("skin", etube_bm([surf(i, -1.5707, 1, 0.003) for i in range(13, 28, 2)], 0.011, per=2, segs=6, ref=(0, 1, 0)), 0)  # the sternum
    for i in range(3, n - 2, 2):  # the spine, a row of knobs riding the back
        t = i / (n - 1)
        ribs.add("skin", blob(pts[i] + back_at(i) * prof(t, rv_t) * 0.985, 1.0, scale=(0.013 + 0.003 * ((i * 7) % 3), 0.014, 0.02), segs=8, rings=5), 0)
    # --- pelvis, hip bones, sunken groin
    at("hips", "spine1", union=True).add("skin", blob(V(-0.05, 0, 1.08), 1.0, scale=(0.12, 0.125, 0.1)), 0)
    for sd, s in SIDES:
        at("hips", "spine1").add("skin", etube_bm([V(-0.02, 0.125 * s, 1.15), V(0.04, 0.138 * s, 1.185), V(0.09, 0.118 * s, 1.2)], [0.014, 0.019, 0.013], [0.012, 0.015, 0.011], per=4, segs=7, ref=(0, 0, 1)), 0)
    # --- shoulders: the slope of the trapezius, the collar bones, shoulder blades
    sh_union = at("chest", "clav.L", "clav.R", "neck1", union=True)
    sh_union.add("skin", etube_bm([V(0.40, 0, 1.78), V(0.44, 0.11, 1.835), V(0.46, 0.2, 1.80)], [0.05, 0.05, 0.048], [0.04, 0.036, 0.04], per=5, segs=10, ref=(0, 0, 1)), 0)
    sh_union.add("skin", etube_bm([V(0.40, 0, 1.78), V(0.44, -0.11, 1.83), V(0.46, -0.2, 1.78)], [0.05, 0.05, 0.048], [0.04, 0.036, 0.04], per=5, segs=10, ref=(0, 0, 1)), 0)
    for sd, s in SIDES:
        at("chest", "clav." + sd).add("skin", etube_bm([V(0.47, 0.01 * s, 1.805), V(0.505, 0.08 * s, 1.842), V(0.466, 0.17 * s, 1.822)], [0.014, 0.015, 0.013], [0.013, 0.013, 0.012], per=5, segs=7, ref=(0, 0, 1)), 0)
        at("chest", "clav." + sd, "spine2").add("skin", etube_bm([V(0.30, 0.07 * s, 1.80), V(0.36, 0.15 * s, 1.70), V(0.42, 0.18 * s, 1.58)], [0.018, 0.045 + 0.005 * s, 0.02], [0.026, 0.03, 0.018], per=4, segs=8, ref=(0, 0, 1)), 0)
    # --- neck: a long thin column with the cords of its muscles and an Adam's apple
    neck = at("chest", "neck1", "neck2", "head", union=True)
    limb(neck, "skin", [V(0.40, 0, 1.76), V(0.56, 0, 1.83), V(0.79, 0, 1.87)], [0.1, 0.062, 0.048], [0.075, 0.054, 0.044], per=8, segs=16)
    cords = at("chest", "neck1", "neck2", "head")
    for sd, s in SIDES:
        limb(cords, "skin", [V(0.77, 0.045 * s, 1.865), V(0.60, 0.058 * s, 1.80), V(0.47, 0.10 * s, 1.80)], [0.014, 0.019, 0.016], per=6, segs=8)
    cords.add("skin", blob(V(0.62, 0, 1.775), 1.0, scale=(0.014, 0.012, 0.016)), 0)
    build_head()
    build_cloth_and_hair(pts, n, ru_t, rv_t, back_at)
    # --- legs: human built but thin and too long; the left a little heavier than the right
    for sd, s in SIDES:
        hipj = V(HIP.x, HIPJ_Y * s, 1.08)
        knee, ankle, ball, toe = mir(KNEE, s), mir(ANKLE, s), mir(BALL, s), mir(TOE, s)
        k = 1.1 if s == 1 else 0.95
        leg = at("hips", "thigh." + sd, "shin." + sd, "foot." + sd, union=True)
        ks = [hipj, hipj.lerp(knee, 0.5), knee, knee.lerp(ankle, 0.28), knee.lerp(ankle, 0.65), ankle]
        limb(leg, "skin", ks, [0.075 * k, 0.062 * k, 0.042, 0.05 * (1.0 if s == 1 else 0.88), 0.034, 0.024], per=6, segs=14)
        leg.add("skin", blob(knee, 0.038, scale=(1.1, 1, 1.15)), 0)
        limb(leg, "skin", [ankle, ball, toe], [0.025, 0.027, 0.013], [0.025, 0.02, 0.008], per=4, segs=10)
        at("shin." + sd, "foot." + sd).add("skin", blob(ankle + V(0, 0.018 * s, 0.0), 0.016), 0)
        at("shin." + sd, "foot." + sd).add("skin", blob(ankle + V(0, -0.018 * s, 0.0), 0.014), 0)
        for j in (-1, 0, 1):
            tip = toe + V(0.07, j * 0.04, 0.0)
            limb(at("foot." + sd, "toes." + sd), "skin", [ball + V(0, j * 0.018, 0.0), toe + V(0.0, j * 0.02, 0), tip], [0.014, 0.012, 0.006], per=3, segs=6)
            spike(at("toes." + sd), "bone", tip, tip + V(0.035, 0, -0.004), 0.007)
    # --- arms: a long thin upper arm, a longer forearm with the tendons showing, a wrist, the hand
    fingers = None
    for sd, s in SIDES:
        sh = V(0.46, SHOULDER_Y * s, SHOULDER_Z - (0.02 if s == 1 else 0.0))
        el, wr = mir(ELBOW, s), mir(WRIST, s)
        arm = at("chest", "clav." + sd, "upperarm." + sd, "forearm." + sd, "hand." + sd, union=True)
        ks = [sh, sh.lerp(el, 0.5), el, el.lerp(wr, 0.3), el.lerp(wr, 0.7), wr]
        thick = 1.0 if s == 1 else 0.88
        limb(arm, "skin", ks, [0.05, 0.043 * thick, 0.026, 0.034 * thick, 0.027, 0.02], [0.055, 0.042 * thick, 0.026, 0.036 * thick, 0.026, 0.018], per=6, segs=14)
        arm.add("skin", blob(sh, 0.048, scale=(1, 1, 1.1)), 0)
        arm.add("skin", blob(el + V(-0.012, 0, 0.0), 0.025), 0)
        # tendons on the back of the forearm and the hand
        tend = at("forearm." + sd, "hand." + sd, "f1." + sd)
        fwd = V(0.15, 0, -1).normalized()
        for ly in (-0.010, 0.0, 0.010):
            off = V(-0.026, ly * s, 0.0)
            tp = [el.lerp(wr, 0.42) + off * 1.15, el.lerp(wr, 0.8) + off * 0.95, wr + off * 0.7, wr + fwd * 0.085 + off * 0.5 + V(0, 0, 0)]
            tend.add("skin", etube_bm(tp, [0.006, 0.0065, 0.006, 0.005], per=4, segs=6, ref=(0, 1, 0)), 0)
        hand_sink = at("hand." + sd, "f1." + sd, "f2." + sd)
        palm = at("hand." + sd, "forearm." + sd, union=True)
        fg = hand(hand_sink, "skin", wr, V(0.15, 0, -1), V(0, 1, 0), V(1, 0, 0), spread=0.4, flen=0.38 * (1.0 if s == 1 else 0.94), curl=0.3, claw_key=None, palm_maker=palm)
        if sd == "L":
            fingers = fg
        for pts_f in fg:
            tip = pts_f[-1]
            dd = (pts_f[-1] - pts_f[-2]).normalized()
            spike(at("f2." + sd), "bone", tip - dd * 0.012, tip + dd * 0.028, 0.0065)
            hand_sink.add("skin", blob(pts_f[0], 0.0125, scale=(1, 1, 0.9)), 0)  # the knuckle
            hand_sink.add("skin", blob(pts_f[1], 0.0105), 0)
    return fingers


def build_head():
    """The head, upright in its own frame (face +X, up +Z), carried to the neck by M_HEAD; the jaw hangs in the world frame."""
    skull_dents = []
    for s in (1, -1):
        skull_dents += [
            ((0.082, 0.037 * s, 0.012), (0.082, 0.037 * s, 0.012), 0.03, 0.03),  # the eye sockets
            ((0.075, 0.063 * s, -0.045), (0.075, 0.063 * s, -0.045), 0.036, 0.015),  # hollow cheeks
            ((0.02, 0.078 * s, 0.05), (0.02, 0.078 * s, 0.05), 0.03, 0.01),  # temples
            ((0.094, 0.009 * s, -0.052), (0.094, 0.009 * s, -0.052), 0.011, 0.016),  # nostrils, no nose
            ((0.062, 0.058 * s, -0.098), (0.024, 0.088 * s, -0.09), 0.014, 0.022),  # the cheek torn back toward the hinge
        ]
    skull = etube_bm([V(0, 0, 0.125), V(0, 0, 0.07), V(0, 0, 0.0), V(0, 0, -0.07), V(0, 0, -0.125)], [0.03, 0.074, 0.08, 0.07, 0.058], [0.04, 0.092, 0.098, 0.078, 0.066], per=18, segs=44, ref=(0, 1, 0))
    dent_bm(skull, skull_dents)
    H = at("head", matrix=M_HEAD, union=True)
    H.add("skin", skull, 0)
    # heavy brow, high cheekbones, a flat nose bridge
    H.add("skin", etube_bm([V(0.066, 0.058, 0.047), V(0.087, 0.0, 0.052), V(0.066, -0.058, 0.047)], [0.015, 0.02, 0.015], [0.014, 0.017, 0.014], per=6, segs=10, ref=(1, 0, 0)), 0)
    H.add("skin", etube_bm([V(0.084, 0, 0.042), V(0.099, 0, -0.008), V(0.094, 0, -0.048)], [0.009, 0.012, 0.009], per=4, segs=8, ref=(0, 1, 0)), 0)
    for s in (1, -1):
        H.add("skin", etube_bm([V(0.05, 0.072 * s, -0.012), V(0.077, 0.056 * s, -0.026), V(0.082, 0.034 * s, -0.038)], [0.012, 0.013, 0.011], [0.011, 0.011, 0.009], per=5, segs=10, ref=(0, 0, 1)), 0)
    # the eyes, deep in their sockets; the right a little larger and lower
    eyes = at("head", matrix=M_HEAD)
    eye(eyes, V(0.066, 0.037, 0.013), 0.0085, key="eyes", scale=(0.6, 1, 1))
    eye(eyes, V(0.064, -0.037, 0.006), 0.0098, key="eyes", scale=(0.6, 1, 1))
    for s in (1, -1):
        eyes.add("mouth", blob(V(0.058, 0.037 * s, 0.01), 1.0, scale=(0.012, 0.022, 0.026)), 0)  # the dark behind the eye
    # the mouth: a gum line, teeth like a person's gone wrong
    gum = at("head", matrix=M_HEAD)
    arc = [V(0.047 + 0.02 * (1 - (k / 4.0) ** 2), 0.05 * k / 4.0, -0.114) for k in range(-4, 5)]
    gum.add("mouth", etube_bm(arc, [0.0042] * 9, [0.0035] * 9, per=3, segs=6, ref=(1, 0, 0)), 0)
    mouth_in = at("head", matrix=M_HEAD)
    mouth_in.add("mouth", blob(V(0.03, 0, -0.1), 1.0, scale=(0.05, 0.07, 0.03)), 0)
    teeth_up = at("head", matrix=M_HEAD)
    seed = 17
    import random
    rnd = random.Random(seed)
    spec = {0: (0.0135, 0.0105, 0.031, 0.0), 1: (0.013, 0.0105, 0.031, 0.0), 2: (0.011, 0.009, 0.026, 0.1), 3: (0.0115, 0.0115, 0.035, 0.55), 4: (0.0135, 0.012, 0.021, 0.0), 5: (0.014, 0.014, 0.019, 0.0), 6: (0.0155, 0.0155, 0.014, 0.0)}
    for k in range(-6, 7):
        if rnd.random() < 0.28 and abs(k) > 1:
            continue  # a gap where one is gone
        w, d, h, pt = spec[abs(k)]
        h *= 0.75 + 0.5 * rnd.random()
        if rnd.random() < 0.12:
            h *= 0.5  # a broken one
        t = k / 6.5
        base = V(0.047 + 0.02 * (1 - t * t), 0.05 * t, -0.112)
        teeth_up.add("teeth", tooth_bm(base, V(0.0, 0.0, -1.0), w, d, h, tilt=(rnd.uniform(-0.18, 0.18), rnd.uniform(-0.15, 0.15)), pointed=pt), 0)
    # sparse long wet hair clinging to the back of the skull
    hair = at("head", matrix=M_HEAD)
    for k in range(10):
        a = -0.95 + k * 0.21
        base = V(-0.03, 0.065 * math.sin(a), 0.095 - 0.03 * abs(math.sin(a)))
        pts = [base, base + V(-0.05, 0.05 * math.sin(a), -0.05), base + V(-0.065, 0.075 * math.sin(a), -0.15), base + V(-0.05, 0.085 * math.sin(a), -0.28 - 0.1 * rnd.random())]
        hair.add("hair", ribbon_bm(pts, [0.014, 0.016, 0.012, 0.008], (0, 1, 0), cols=2, jag=0.3, wave=0.004, seed=40 + k), 0)
    # the lower jaw: dropped far too low but still attached, covered in the same skin as the rest of the head; a black mouth behind it
    J = at("jaw")
    hx, hz = HINGE.x, HINGE.z
    jaw = [V(hx - 0.02, 0.076, hz), V(hx + 0.02, 0.07, hz - 0.14), V(hx + 0.06, 0.042, hz - 0.30), V(hx + 0.085, 0, hz - 0.345), V(hx + 0.06, -0.042, hz - 0.30), V(hx + 0.02, -0.07, hz - 0.14), V(hx - 0.02, -0.076, hz)]
    J.add("skin", etube_bm(jaw, [0.034, 0.028, 0.022, 0.02, 0.022, 0.028, 0.034], [0.014, 0.016, 0.02, 0.024, 0.02, 0.016, 0.014], per=8, segs=14, ref=(1, 0, 0)), 0)
    # the black inside: a throat from the palate down between the arms of the jaw, so the opening is dark and not see-through
    HW = lambda v: M_HEAD @ v
    throat = at("head", "jaw")
    throat.add("mouth", etube_bm([HW(V(0.03, 0, -0.118)), HW(V(0.04, 0, -0.15)), V(hx + 0.035, 0.0, hz - 0.12), V(hx + 0.05, 0.0, hz - 0.20)], [0.056, 0.05, 0.034, 0.008], [0.03, 0.028, 0.018, 0.005], per=5, segs=14, ref=(0, 1, 0)), 0)
    palate = at("head", matrix=M_HEAD)
    palate.add("mouth", blob(V(0.03, 0, -0.121), 1.0, scale=(0.062, 0.062, 0.014)), 0)
    spec_l = {0: (0.011, 0.0095, 0.026, 0.0), 1: (0.011, 0.0095, 0.025, 0.0), 2: (0.01, 0.009, 0.029, 0.25), 3: (0.011, 0.0095, 0.034, 0.5), 4: (0.0125, 0.0125, 0.02, 0.0)}
    for k in range(-4, 5):
        if rnd.random() < 0.3 and k != 0:
            continue
        w, d, h, pt = spec_l[abs(k)]
        h *= 0.7 + 0.6 * rnd.random()
        t = k / 4.0
        base = V(hx + 0.078 - 0.014 * t * t, 0.034 * t, hz - 0.324 + 0.02 * abs(t))
        J.add("teeth", tooth_bm(base, V(0.0, 0.0, 1.0), w, d, h, tilt=(rnd.uniform(-0.3, 0.3), rnd.uniform(-0.25, 0.25)), pointed=pt), 0)
    for k in range(5):
        for sy in (1, -1):
            if rnd.random() < 0.4:
                continue
            z = hz - 0.18 - k * 0.026
            J.add("teeth", tooth_bm(V(hx + 0.045 + k * 0.004, sy * (0.062 - k * 0.006), z), V(-0.1, -sy * 0.55, 0.8), 0.009, 0.009, 0.014 + 0.005 * rnd.random(), tilt=(rnd.uniform(-0.2, 0.2), 0.0)), 0)


def build_cloth_and_hair(pts, n, ru_t, rv_t, back_at):
    """Rags: strips hanging from the waist, torn shirt remnants over the back and the chest, all ragged ribbons."""
    import random
    rnd = random.Random(5)
    skirt = at("hips", "spine1", "thigh.L", "thigh.R")
    for k in range(13):
        a = (k / 13.0) * 2 * math.pi + 0.2
        L = 0.24 + 0.36 * rnd.random()
        flare = 0.03 + 0.06 * rnd.random()
        c, sn = math.cos(a), math.sin(a)
        base = V(HIP.x + 0.14 * c * 0.9, 0.152 * sn, 1.075)
        path_k = [base, base + V(flare * 0.6 * c, flare * 0.6 * sn, -L * 0.35), base + V(flare * c - 0.01, flare * sn, -L * 0.7), base + V(flare * c * 1.3 - 0.02, flare * sn * 1.3, -L)]
        w = 0.05 + 0.04 * rnd.random()
        skirt.add("cloth", ribbon_bm(path_k, [w, w * 1.05, w * 0.95, w * 0.7], (-sn, c, 0), cols=3, jag=0.35, wave=0.012, holes=0.05, seed=100 + k), 0)
    shirt = at("chest", "spine2", "spine1", "clav.L", "clav.R")
    for k, (yy, t0, t1) in enumerate(((-0.12, 0.93, 0.28), (-0.05, 0.95, 0.15), (0.04, 0.95, 0.36), (0.12, 0.92, 0.2), (0.0, 0.72, 0.05), (-0.17, 0.9, 0.4))):
        i0, i1 = int(t0 * (n - 1)), int(t1 * (n - 1))
        kk = []
        for i in range(i0, i1 - 1, -3):
            tt = i / (n - 1)
            kk.append(pts[i] + back_at(i) * (prof(tt, rv_t) * 1.07 + 0.012) + V(0, yy * prof(tt, ru_t) / 0.15 * 0.85, 0))
        if len(kk) >= 3:
            w = 0.05 + 0.035 * rnd.random()
            shirt.add("cloth", ribbon_bm(kk, [w] * len(kk), (0, 1, 0), cols=3, jag=0.3, wave=0.008, holes=0.06, seed=200 + k), 0)
    for k, yy in enumerate((-0.1, 0.0, 0.1)):
        kk = []
        for i in range(27, 12, -3):
            tt = i / (n - 1)
            kk.append(pts[i] - back_at(i) * (prof(tt, rv_t) * 1.07 + 0.012) + V(0, yy * prof(tt, ru_t) / 0.15, 0))
        shirt.add("cloth", ribbon_bm(kk, [0.045] * len(kk), (0, 1, 0), cols=2, jag=0.35, wave=0.008, holes=0.05, seed=300 + k), 0)


# ------------------------------------------------------------------ the skin: fused surface, weights, painted masks, baked textures

def remesh_fuse(ob):
    """Fuse the objects joined into `ob` into one continuous surface, smooth the voxel steps, decimate to the budget."""
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    ob.data.remesh_voxel_size = VOXEL
    ob.data.remesh_voxel_adaptivity = 0.0
    bpy.ops.object.voxel_remesh()
    add_mod(ob, "LAPLACIANSMOOTH", lambda_factor=0.55, iterations=3, use_volume_preserve=True, lambda_border=0.0)
    bpy.context.view_layer.update()
    bake(ob)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris > BODY_TRIS:
        add_mod(ob, "DECIMATE", ratio=BODY_TRIS / tris)
        bpy.context.view_layer.update()
        bake(ob)
    print("BODY SURFACE tris", sum(len(p.vertices) - 2 for p in ob.data.polygons), "was", tris)


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def paint_masks(ob):
    """Vertex attribute Ext for the skin bake: R darker toward the hands, feet, knees and elbows, G the sockets, B the mouth and torn cheeks."""
    me = ob.data
    if "Ext" in me.color_attributes:
        me.color_attributes.remove(me.color_attributes["Ext"])
    attr = me.color_attributes.new("Ext", "FLOAT_COLOR", "POINT")
    import numpy as np
    R3 = M_HEAD.to_3x3()
    eyes = [M_HEAD @ V(0.07, 0.037, 0.012), M_HEAD @ V(0.07, -0.037, 0.006)]
    mouth_segs = []
    for s in (1, -1):
        c = M_HEAD @ V(0.062, 0.058 * s, -0.098)
        e = M_HEAD @ V(0.024, 0.088 * s, -0.09)
        mouth_segs.append((c, e))
        nost = M_HEAD @ V(0.094, 0.009 * s, -0.052)
        mouth_segs.append((nost, nost))
    lip = (M_HEAD @ V(0.07, 0.058, -0.1), M_HEAD @ V(0.07, -0.058, -0.1))
    cols = np.zeros((len(me.vertices), 4), dtype=np.float32)
    cols[:, 3] = 1.0
    for v in me.vertices:
        p = v.co
        r = 0.0
        for sd, s in SIDES:
            d = seg_dist(p, mir(WRIST, s), mir(V(0.56, 0.27, 0.28), s))
            r = max(r, 1.0 - smoothstep(0.0, 0.42, d))
            d = seg_dist(p, mir(ANKLE, s), mir(TOE, s))
            r = max(r, 1.0 - smoothstep(0.0, 0.4, d))
            for j in (mir(KNEE, s), mir(ELBOW, s)):
                r = max(r, 0.4 * (1.0 - smoothstep(0.0, 0.07, (p - j).length)))
        g = max(1.0 - smoothstep(0.018, 0.05, (p - e).length) for e in eyes)
        b = 0.0
        for c, e in mouth_segs:
            b = max(b, 1.0 - smoothstep(0.004, 0.022, seg_dist(p, c, e)))
        b = max(b, 0.9 * (1.0 - smoothstep(0.004, 0.02, seg_dist(p, lip[0], lip[1]))))
        cols[v.index, 0], cols[v.index, 1], cols[v.index, 2] = r, g, b
    attr.data.foreach_set("color", cols.ravel())


def proc_skin_material():
    """The skin as a procedural material in object space (so every piece of the skin lines up): ash and mottle, bruises,
    thin blue veins, dirt, darker hands and feet and sockets and mouth (the Ext attribute), wet and dry roughness, pores and wrinkles."""
    m = bpy.data.materials.new("skin_proc")
    m.use_nodes = True
    nt = m.node_tree
    N = nt.nodes
    L = nt.links
    for x in list(N):
        if x.type not in ("OUTPUT_MATERIAL",):
            N.remove(x)
    out = [x for x in N if x.type == "OUTPUT_MATERIAL"][0]
    bs = N.new("ShaderNodeBsdfPrincipled")
    L.new(bs.outputs["BSDF"], out.inputs["Surface"])
    tc = N.new("ShaderNodeTexCoord")

    def mapping(scale, loc=(0, 0, 0)):
        mp = N.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (scale, scale, scale)
        mp.inputs["Location"].default_value = loc
        L.new(tc.outputs["Object"], mp.inputs["Vector"])
        return mp

    def noise_node(scale, detail=6.0, rough=0.55, loc=(0, 0, 0)):
        nz = N.new("ShaderNodeTexNoise")
        nz.inputs["Detail"].default_value = detail
        nz.inputs["Roughness"].default_value = rough
        L.new(mapping(scale, loc).outputs["Vector"], nz.inputs["Vector"])
        return nz

    def ramp(src, stops):
        r = N.new("ShaderNodeValToRGB")
        r.color_ramp.elements[0].position = stops[0][0]
        r.color_ramp.elements[0].color = stops[0][1]
        r.color_ramp.elements[1].position = stops[-1][0]
        r.color_ramp.elements[1].color = stops[-1][1]
        for pos_, col in stops[1:-1]:
            e = r.color_ramp.elements.new(pos_)
            e.color = col
        L.new(src, r.inputs["Fac"])
        return r

    def mix(a, b, fac):
        mx = N.new("ShaderNodeMix")
        mx.data_type = "RGBA"
        for sock, v in (("A", a), ("B", b)):
            if isinstance(v, tuple):
                mx.inputs[sock].default_value = v
            else:
                L.new(v, mx.inputs[sock])
        if isinstance(fac, float):
            mx.inputs["Factor"].default_value = fac
        else:
            L.new(fac, mx.inputs["Factor"])
        return mx.outputs["Result"]

    def scale_val(src, k, add=0.0):
        mt = N.new("ShaderNodeMath")
        mt.operation = "MULTIPLY_ADD"
        L.new(src, mt.inputs[0])
        mt.inputs[1].default_value = k
        mt.inputs[2].default_value = add
        mt.use_clamp = True
        return mt.outputs["Value"]

    def mulv(a, b):
        mt = N.new("ShaderNodeMath")
        mt.operation = "MULTIPLY"
        L.new(a, mt.inputs[0])
        L.new(b, mt.inputs[1])
        return mt.outputs["Value"]

    def lin(h):
        return hexcol(h)

    n1 = noise_node(3.2)
    base = ramp(n1.outputs["Fac"], [(0.3, lin("#9a988d")), (0.55, lin("#74766d")), (0.75, lin("#50534c"))])
    n2 = noise_node(1.8, 5.0, 0.6, (4.0, 2.0, 1.0))
    bruise_f = ramp(n2.outputs["Fac"], [(0.45, (0, 0, 0, 1)), (0.62, (1, 1, 1, 1))])
    n3 = noise_node(2.6, 4.0, 0.5, (1.0, 7.0, 3.0))
    bruise_c = ramp(n3.outputs["Fac"], [(0.35, lin("#4e2f56")), (0.65, lin("#5c6a30"))])
    col = mix(base.outputs["Color"], bruise_c.outputs["Color"], scale_val(bruise_f.outputs["Color"], 0.85))
    vo = N.new("ShaderNodeTexVoronoi")
    vo.feature = "DISTANCE_TO_EDGE"
    vo.inputs["Scale"].default_value = 13.0
    L.new(mapping(1.0, (3, 3, 3)).outputs["Vector"], vo.inputs["Vector"])
    vein = ramp(vo.outputs["Distance"], [(0.0, (1, 1, 1, 1)), (0.035, (0, 0, 0, 1))])
    sparse = ramp(noise_node(2.4, 3.0, 0.5, (9, 1, 5)).outputs["Fac"], [(0.5, (0, 0, 0, 1)), (0.66, (1, 1, 1, 1))])
    vein_mask = mulv(vein.outputs["Color"], sparse.outputs["Color"])
    col = mix(col, lin("#566b85"), scale_val(vein_mask, 0.6))
    ext = N.new("ShaderNodeAttribute")
    ext.attribute_name = "Ext"
    sep = N.new("ShaderNodeSeparateColor")
    L.new(ext.outputs["Color"], sep.inputs["Color"])
    col = mix(col, lin("#2a2630"), scale_val(sep.outputs["Red"], 1.0))
    col = mix(col, lin("#140c0f"), sep.outputs["Green"])
    col = mix(col, lin("#3a1517"), scale_val(sep.outputs["Blue"], 0.95))
    n4 = noise_node(9.0, 8.0, 0.6, (2, 2, 8))
    grime = ramp(n4.outputs["Fac"], [(0.5, (0, 0, 0, 1)), (0.8, (1, 1, 1, 1))])
    col = mix(col, lin("#352f28"), scale_val(grime.outputs["Color"], 0.4))
    L.new(col, bs.inputs["Base Color"])
    # roughness: wet in places, dry and dirty in others, the veins a little wetter
    n5 = noise_node(5.0, 3.0, 0.5, (6, 4, 0))
    rough = N.new("ShaderNodeMath")
    rough.operation = "MULTIPLY_ADD"
    L.new(n5.outputs["Fac"], rough.inputs[0])
    rough.inputs[1].default_value = 0.55
    rough.inputs[2].default_value = 0.2
    rough2 = N.new("ShaderNodeMath")
    rough2.operation = "MULTIPLY_ADD"
    L.new(grime.outputs["Color"], rough2.inputs[0])
    rough2.inputs[1].default_value = 0.25
    L.new(rough.outputs["Value"], rough2.inputs[2])
    rough2.use_clamp = True
    rough3 = N.new("ShaderNodeMath")
    rough3.operation = "MULTIPLY_ADD"
    L.new(sep.outputs["Red"], rough3.inputs[0])
    rough3.inputs[1].default_value = 0.4
    L.new(rough2.outputs["Value"], rough3.inputs[2])
    rough3.use_clamp = True
    L.new(rough3.outputs["Value"], bs.inputs["Roughness"])
    # pores and wrinkles as a bump
    pore = noise_node(170.0, 2.0, 0.5)
    wr = noise_node(34.0, 5.0, 0.55, (0, 0, 5))
    hh = N.new("ShaderNodeMath")
    hh.operation = "ADD"
    L.new(scale_val(pore.outputs["Fac"], 0.5), hh.inputs[0])
    L.new(scale_val(wr.outputs["Fac"], 1.0), hh.inputs[1])
    bump = N.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.7
    bump.inputs["Distance"].default_value = 0.004
    L.new(hh.outputs["Value"], bump.inputs["Height"])
    L.new(bump.outputs["Normal"], bs.inputs["Normal"])
    return m


def bake_skin(skin, final_mat):
    """UV unwrap the fused skin, bake the procedural skin to textures, give the skin its final textured material."""
    import numpy as np
    os.makedirs(TEX, exist_ok=True)
    sc = bpy.context.scene
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = skin
    skin.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(70), island_margin=0.002, area_weight=0.7)
    bpy.ops.object.mode_set(mode="OBJECT")
    proc = proc_skin_material()
    skin.data.materials.clear()
    skin.data.materials.append(proc)
    nt = proc.node_tree
    tex_node = nt.nodes.new("ShaderNodeTexImage")
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 6
    sc.cycles.use_denoising = False
    sc.render.bake.margin = 8
    sc.render.bake.use_clear = True
    images = {}

    def run(name, kind, colorspace, **kw):
        img = bpy.data.images.new("gaunt_" + name, TEX_SIZE, TEX_SIZE, alpha=False, float_buffer=False)
        img.colorspace_settings.name = colorspace
        tex_node.image = img
        for x in nt.nodes:
            x.select = False
        tex_node.select = True
        nt.nodes.active = tex_node
        bpy.ops.object.bake(type=kind, **kw)
        images[name] = img

    run("albedo", "DIFFUSE", "sRGB", pass_filter={"COLOR"})
    run("rough", "ROUGHNESS", "Non-Color")
    run("normal", "NORMAL", "Non-Color")
    sc.cycles.samples = 48
    run("ao", "AO", "Non-Color")
    # occlusion folded into the albedo: the creases between ribs, under the jaw, in the armpits
    a = np.empty(TEX_SIZE * TEX_SIZE * 4, dtype=np.float32)
    o = np.empty_like(a)
    images["albedo"].pixels.foreach_get(a)
    images["ao"].pixels.foreach_get(o)
    a = a.reshape(-1, 4)
    o = o.reshape(-1, 4)
    a[:, :3] *= (0.38 + 0.62 * o[:, :1]) * 0.7
    images["albedo"].pixels.foreach_set(a.ravel())
    import subprocess
    finals = {}
    for name in ("albedo", "rough", "normal"):
        img = images[name]
        png = os.path.join(TEX, "gaunt_%s.png" % name)
        jpg = os.path.join(TEX, "gaunt_%s.jpg" % name)
        img.filepath_raw = png
        img.file_format = "PNG"
        img.save()
        # Blender's own JPEG writer embeds a colour profile that Godot's decoder rejects: write plain JPEGs and let the glTF export carry them as they are
        extra = ["-resize", "50%"] if name == "rough" else []  # roughness varies slowly; the glTF export re-packs it as a PNG, so keep it small
        magick = shutil.which("magick")
        if magick is None:
            raise SystemExit("ImageMagick (the `magick` command) is needed to write the skin JPEGs: install it (brew install imagemagick) and run again")
        subprocess.run([magick, png] + extra + ["-strip", "-quality", "88", jpg], check=True)
        fin = bpy.data.images.load(jpg)
        fin.colorspace_settings.name = "sRGB" if name == "albedo" else "Non-Color"
        finals[name] = fin
    # the final material: three images
    m = final_mat
    m.use_nodes = True
    nt2 = m.node_tree
    for x in list(nt2.nodes):
        if x.type != "OUTPUT_MATERIAL":
            nt2.nodes.remove(x)
    out = [x for x in nt2.nodes if x.type == "OUTPUT_MATERIAL"][0]
    bs = nt2.nodes.new("ShaderNodeBsdfPrincipled")
    nt2.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
    bs.inputs["Coat Weight"].default_value = 0.2
    bs.inputs["Coat Roughness"].default_value = 0.25
    ia = nt2.nodes.new("ShaderNodeTexImage")
    ia.image = finals["albedo"]
    nt2.links.new(ia.outputs["Color"], bs.inputs["Base Color"])
    ir = nt2.nodes.new("ShaderNodeTexImage")
    ir.image = finals["rough"]
    sp = nt2.nodes.new("ShaderNodeSeparateColor")
    nt2.links.new(ir.outputs["Color"], sp.inputs["Color"])
    nt2.links.new(sp.outputs["Green"], bs.inputs["Roughness"])
    inn = nt2.nodes.new("ShaderNodeTexImage")
    inn.image = finals["normal"]
    nm = nt2.nodes.new("ShaderNodeNormalMap")
    nt2.links.new(inn.outputs["Color"], nm.inputs["Color"])
    nt2.links.new(nm.outputs["Normal"], bs.inputs["Normal"])
    skin.data.materials.clear()
    skin.data.materials.append(m)
    bpy.data.materials.remove(proc)
    sc.render.engine = "BLENDER_EEVEE"


# ------------------------------------------------------------------ assemble

def paint_cloth(ob):
    """Dirt and wet on the cloth: darker and more stained toward the hem, patchy."""
    me = ob.data
    if "Col" not in me.color_attributes:
        me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    attr = me.color_attributes["Col"]
    import numpy as np
    cols = np.ones((len(me.loops), 4), dtype=np.float32)
    for li, lp in enumerate(me.loops):
        co = me.vertices[lp.vertex_index].co
        f = 0.5 + 0.5 * noise.noise(co * 8.0)
        g = 0.5 + 0.5 * noise.noise(co * 2.5 + Vector((3, 1, 2)))
        base = Vector((0.15, 0.135, 0.11)) * (0.5 + 0.7 * f) * (0.6 + 0.6 * g)
        cols[li, 0], cols[li, 1], cols[li, 2] = base.x, base.y, base.z
    attr.data.foreach_set("color", cols.ravel())


def assemble():
    reset()
    M = make_materials()
    fingers = build_parts()
    define_bones(fingers)
    objs = []
    for idx, (key, bm, subdiv, bones, union) in enumerate(PARTS):
        ob = make_obj("p%03d" % idx, bm, M[key], smooth=True)
        ob["bones"] = bones
        ob["key"] = key
        ob["union"] = bool(union)
        if subdiv:
            add_mod(ob, "SUBSURF", levels=subdiv, render_levels=subdiv)
        objs.append(ob)
    bpy.context.view_layer.update()
    for ob in objs:
        if ob.modifiers:
            bake(ob)
    U = [o for o in objs if o["union"] and o["key"] == "skin"]
    D = [o for o in objs if not o["union"] and o["key"] == "skin"]
    O = [o for o in objs if o["key"] != "skin"]
    for o in objs:
        for k in ("key", "union"):
            pass
    # the fused surface
    fused = join("skin_fused", U)
    remesh_fuse(fused)
    skin_weights(fused, [b for b in BONES if b not in ("root", "jaw")], power=5.0, offset=0.015)
    for ob in D:
        bones = list(ob["bones"])
        if len(bones) == 1:
            rigid_weights(ob, bones[0])
        else:
            skin_weights(ob, bones)
    for ob in D:
        del ob["bones"]
        del ob["key"]
        del ob["union"]
    skin = join("skin", [fused] + D)
    for k in ("bones", "key", "union"):
        if k in skin:
            del skin[k]
    paint_masks(skin)
    bake_skin(skin, M["skin"])
    for ob in O:
        bones = list(ob["bones"])
        if len(bones) == 1:
            rigid_weights(ob, bones[0])
        else:
            skin_weights(ob, bones)
        del ob["bones"]
        del ob["key"]
        del ob["union"]
    ao = make_armature()
    mesh = join("gaunt", [skin] + O)
    mod = mesh.modifiers.new("Armature", "ARMATURE")
    mod.object = ao
    mesh.parent = ao
    return ao, mesh


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

"""The creature of Hollow Hours, "the Gaunt": modelled, skinned, rigged and animated here.

An original design (concept A, "the Stooper"): a once-human thing, 2.1 m hunched and 2.4 m if it ever stood straight.
Starved, ashen wet skin over a visible spine, ribs and hips, rags of cloth hanging from the waist and shoulders,
arms that reach the shins ending in oversized hands with 40 cm fingers, and a head cocked to one side whose
lower jaw is unhinged and hangs a forearm's length below the face. It lopes upright when it stalks and runs on
its fingertips and feet when it sprints. Pale eyes that throw the light back.

Coordinates: Blender Z up, +X forward; the glTF exporter keeps +X forward for Godot. The root sits on the ground
between the feet.

Rig: 31 bones. Poses are written as target positions (hips, wrists, ankles) and absolute angles (spine, neck,
head, jaw, hand, fingers, foot); `solve` turns them into bone rotations with two-bone IK for the arms and legs.
Clips (30 fps): idle, stalk, sprint, pounce, latch, thrown, dead, missed, stunned.

Run (headless, foreground):
  Blender --background --python-exit-code 1 --python tools/blender/creature.py -- [preview] [rest]
Output: assets/models/gaunt.glb (and contact sheets in $HH_PREV, default a hollow-hours-prev folder in the system temp dir, with `preview`).
The body (surface, skinning, baked skin textures) is in gaunt_body.py; this file is the posing, the clips and the export.
"""
import sys, os, math, tempfile, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, Matrix, Quaternion, noise
from rk import *
from gk import *
from gaunt_body import *

MAGICK = shutil.which("magick")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
FPS = 30
PREV = os.environ.get("HH_PREV", os.path.join(tempfile.gettempdir(), "hollow-hours-prev"))

# ------------------------------------------------------------------ posing: targets and angles in, bone rotations out

TORSO = ("spine1", "spine2", "chest", "neck1", "neck2", "head")


def bdir(name):
    h, t, _ = BONES[name]
    return (t - h).normalized()


def pitch_of(v):
    v = Vector(v)
    return math.atan2(v.z, math.hypot(v.x, v.y))


def yaw_of(v):
    return math.atan2(v.y, v.x)


def ang_dir(p, y):
    return Vector((math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), math.sin(p)))


def arc(r, d):
    return r.rotation_difference(d).to_matrix()


def abs_rot(name, p, y, roll=0.0):
    d = ang_dir(p, y)
    return Matrix.Rotation(roll, 3, d) @ arc(bdir(name), d)


def ik2(root, target, a, b, pole):
    d = target - root
    L = min(max(d.length, abs(a - b) + 1e-3), a + b - 1e-3)
    dv = d.normalized() if d.length > 1e-6 else Vector((0, 0, -1))
    x = (a * a - b * b + L * L) / (2 * L)
    h = math.sqrt(max(a * a - x * x, 0.0))
    pv = pole - dv * pole.dot(dv)
    if pv.length < 1e-4:
        pv = Vector((0, 0, 1)) - dv * dv.z
    pv.normalize()
    mid = root + dv * x + pv * h
    return mid, root + dv * L


def base_pose():
    """The rest pose as a full parameter dict: every clip starts from this, then overrides."""
    P = {"hip": HIP.copy(), "hips": (0.0, 0.0, 0.0), "G": None}
    for n in TORSO:
        d = bdir(n)
        P[n] = (pitch_of(d), 0.0, 0.0)
    P["jaw"] = (pitch_of(bdir("jaw")), 0.0, 0.0)
    P["shrug"] = (0.0, 0.0)
    for sd, s in (("L", 1), ("R", -1)):
        P["wrist." + sd] = None  # None = the rest offset from the shoulder; a Vector = a world target
        P["wrist_rel." + sd] = mir(WRIST, s) - V(0.46, SHOULDER_Y * s, SHOULDER_Z)
        P["epole." + sd] = V(-1.0, 0.6 * s, 0.3)
        P["hand." + sd] = None  # None = continues the forearm
        P["curl." + sd] = (0.0, 0.0)
        P["ankle." + sd] = mir(ANKLE, s)
        P["kpole." + sd] = V(1.0, 0.15 * s, 0.0)
        P["foot." + sd] = (pitch_of(bdir("foot." + sd)), 0.0, 0.0)
        P["toe." + sd] = 0.0
    return P


def mixp(a, b, t):
    """Blend two full poses (numbers, tuples and Vectors blend; None keeps whichever side has a value)."""
    out = {}
    for k in a:
        va, vb = a[k], b[k]
        if va is None or vb is None:
            out[k] = vb if t > 0.5 else va
        elif isinstance(va, Vector):
            out[k] = va.lerp(vb, t)
        elif isinstance(va, tuple):
            out[k] = tuple(lerp(x, y, t) for x, y in zip(va, vb))
        elif isinstance(va, (int, float)):
            out[k] = lerp(va, vb, t)
        else:
            out[k] = vb if t > 0.5 else va
    return out


def solve(P):
    """Pose params -> ({bone: absolute rotation (3x3, armature space)}, hips location, {bone: head position})."""
    A, H = {}, {}
    rh = {n: BONES[n][0] for n in BONES}
    A["root"], H["root"] = Matrix.Identity(3), V(0, 0, 0)
    pd, yw, rl = P["hips"]
    A["hips"] = Matrix.Rotation(yw, 3, "Z") @ Matrix.Rotation(pd, 3, "Y") @ Matrix.Rotation(rl, 3, "X")
    H["hips"] = Vector(P["hip"])

    def place(n):
        par = BONES[n][2]
        H[n] = H[par] + A[par] @ (rh[n] - rh[par])

    for n in TORSO:
        place(n)
        p, y, r = P[n]
        A[n] = abs_rot(n, p, y, r)
    place("jaw")
    p, y, r = P["jaw"]
    A["jaw"] = abs_rot("jaw", p, y, r)
    for sd, s in (("L", 1), ("R", -1)):
        place("clav." + sd)
        A["clav." + sd] = A["chest"]
        place("upperarm." + sd)
        sh = H["upperarm." + sd]
        a = (BONES["forearm." + sd][0] - BONES["upperarm." + sd][0]).length
        b = (BONES["hand." + sd][0] - BONES["forearm." + sd][0]).length
        tgt = P["wrist." + sd] if P["wrist." + sd] is not None else sh + P["wrist_rel." + sd]
        el, wr = ik2(sh, tgt, a, b, P["epole." + sd])
        A["upperarm." + sd] = arc(bdir("upperarm." + sd), (el - sh).normalized())
        H["forearm." + sd] = el
        A["forearm." + sd] = arc(bdir("forearm." + sd), (wr - el).normalized())
        H["hand." + sd] = wr
        if P["hand." + sd] is None:
            A["hand." + sd] = A["forearm." + sd]
        else:
            hp_, hy_, hr_ = P["hand." + sd]
            A["hand." + sd] = abs_rot("hand." + sd, hp_, hy_, hr_)
        c1, c2 = P["curl." + sd]
        place("f1." + sd)
        A["f1." + sd] = A["hand." + sd] @ Matrix.Rotation(-c1, 3, "Y")
        place("f2." + sd)
        A["f2." + sd] = A["f1." + sd] @ Matrix.Rotation(-c2, 3, "Y")
        # legs
        place("thigh." + sd)
        hj = H["thigh." + sd]
        a = (BONES["shin." + sd][0] - BONES["thigh." + sd][0]).length
        b = (BONES["foot." + sd][0] - BONES["shin." + sd][0]).length
        kn, an = ik2(hj, P["ankle." + sd], a, b, P["kpole." + sd])
        A["thigh." + sd] = arc(bdir("thigh." + sd), (kn - hj).normalized())
        H["shin." + sd] = kn
        A["shin." + sd] = arc(bdir("shin." + sd), (an - kn).normalized())
        H["foot." + sd] = an
        fp, fy, fr = P["foot." + sd]
        A["foot." + sd] = abs_rot("foot." + sd, fp, fy, fr)
        place("toes." + sd)
        A["toes." + sd] = A["foot." + sd] @ Matrix.Rotation(-P["toe." + sd], 3, "Y")
    hip = Vector(P["hip"])
    if P["G"] is not None:
        pivot, R = P["G"]
        for n in A:
            if n != "root":
                A[n] = R @ A[n]
        hip = pivot + R @ (hip - pivot)
    return A, hip


def apply_pose(ao, P, rest):
    A, hip = solve(P)
    for pb in ao.pose.bones:
        n = pb.name
        par = BONES[n][2]
        Ap = A[par] if par else Matrix.Identity(3)
        B = rest[n]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (B.inverted() @ (Ap.inverted() @ A[n]) @ B).to_quaternion()
    ao.pose.bones["hips"].location = rest["hips"].inverted() @ (hip - BONES["hips"][0])


# ------------------------------------------------------------------ clips

SIDES = (("L", 1), ("R", -1))
JAW0 = None  # the jaw's rest pitch, set once the bones exist
FOOT0 = None


def S(x):
    return math.sin(x)


def C(x):
    return math.cos(x)


def pos(x):
    return max(0.0, x)


def smooth01(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def bump(P, key, dp=0.0, dy=0.0, dr=0.0):
    p, y, r = P[key]
    P[key] = (p + dp, y + dy, r + dr)


def foot_path(u, stride, swing, lift):
    """x and height of a foot (or hand) over a cycle: swings from the back to the front over `swing`, then is dragged back along the ground."""
    if u < swing:
        t = u / swing
        return lerp(-stride / 2, stride / 2, smooth01(t)), lift * S(math.pi * t) ** 0.8, t, True
    t = (u - swing) / (1.0 - swing)
    return lerp(stride / 2, -stride / 2, t), 0.0, t, False


def pose_idle(p):
    """Lurking: it stands hunched in the dark, swaying, head cocked and turning slowly, jaw swinging on its own, fingers twitching."""
    th = 2 * math.pi * p
    P = base_pose()
    P["hip"] = HIP + V(0.0, 0.012 * S(th), -0.05 + 0.006 * S(2 * th))
    bump(P, "spine1", -0.06 + 0.02 * S(2 * th), 0.05 * S(th))
    bump(P, "spine2", -0.05 + 0.03 * S(2 * th + 0.4), -0.06 * S(th))
    bump(P, "chest", -0.02 + 0.02 * S(2 * th + 0.8), 0.04 * S(th))
    bump(P, "neck1", 0.0, 0.15 * S(th + 0.4), 0.15)
    bump(P, "neck2", -0.02, 0.25 * S(th + 0.4), 0.2)
    bump(P, "head", -0.08, 0.5 * S(th + 0.4), 0.42 + 0.05 * S(th))
    P["jaw"] = (JAW0 + 0.12 * S(th + 1.0) + 0.04 * S(3 * th), 0.04 * S(th + 0.5), 0.0)
    for sd, s in SIDES:
        ph = 0.0 if sd == "L" else 1.7
        P["wrist_rel." + sd] = P["wrist_rel." + sd] + V(0.04 * S(th + ph), 0.01 * S(th), 0.02 * S(2 * th + ph))
        P["curl." + sd] = (0.15 * pos(S(3 * th + ph)), 0.25 * pos(S(3 * th + ph + 0.6)))
    return P


STALK_STRIDE = 1.15
STALK_SWING = 0.42


def pose_stalk(p):
    """An upright lope, low and long: knees bent, hips dropped, torso leaning forward over its stride, arms swinging by the shins."""
    th = 2 * math.pi * p
    P = base_pose()
    P["hip"] = HIP + V(0.0, 0.015 * S(th), -0.17 + 0.03 * C(2 * th))
    bump(P, "hips", 0.0, 0.1 * S(th), 0.04 * S(th))
    bump(P, "spine1", -0.2 + 0.03 * S(2 * th), -0.12 * S(th))
    bump(P, "spine2", -0.22, -0.1 * S(th))
    bump(P, "chest", -0.2, 0.2 * S(th))
    bump(P, "neck1", -0.1, -0.1 * S(th), 0.2 * S(th))
    bump(P, "neck2", -0.12, 0.0, 0.2)
    bump(P, "head", -0.25 + 0.04 * S(2 * th), 0.15 * S(th + 1.0), 0.32)
    P["jaw"] = (JAW0 + 0.18 * S(2 * th + 0.5), 0.0, 0.0)
    for sd, s in SIDES:
        u = (p + (0.0 if sd == "L" else 0.5)) % 1.0
        x, z, t, sw = foot_path(u, STALK_STRIDE, STALK_SWING, 0.24)
        heel = smooth01((t - 0.75) / 0.25) if not sw else 0.0
        P["ankle." + sd] = V(HIP.x + 0.22 + x, 0.12 * s, 0.10 + z + 0.1 * heel)
        P["foot." + sd] = (FOOT0 - 0.45 * heel + (0.25 * S(math.pi * t) if sw else 0.0), 0.0, 0.0)
        P["toe." + sd] = -0.3 * heel
        # arms swing against the legs, hands trailing
        ph = math.pi if sd == "L" else 0.0
        sw_a = S(th + ph)
        P["wrist_rel." + sd] = V(0.2 + 0.34 * sw_a, 0.07 * s, -0.98 + 0.12 * pos(sw_a))
        P["epole." + sd] = V(-0.6, 0.8 * s, 0.1)
        P["curl." + sd] = (0.25 + 0.2 * S(th + ph + 1.0), 0.35 + 0.2 * S(th + ph + 1.6))
    return P


def pose_sprint(p):
    """A bounding gallop on the fingertips and the balls of the feet: torso level and arched, arms and legs reaching to meet under the chest."""
    th = 2 * math.pi * p
    P = base_pose()
    P["hip"] = HIP + V(0.0, 0.0, -0.10 + 0.16 * S(2 * th + 0.4))
    arch = 0.2 * S(2 * th + 1.2)
    bump(P, "hips", -0.15 + 0.1 * S(2 * th + 1.0))
    P["spine1"] = (0.3 + arch, 0.0, 0.0)
    P["spine2"] = (0.18 + 0.7 * arch, 0.0, 0.0)
    P["chest"] = (0.06 + 0.4 * arch, 0.0, 0.0)
    P["neck1"] = (0.1 - 0.5 * arch, 0.0, 0.1)
    P["neck2"] = (0.0, 0.0, 0.2)
    P["head"] = (-0.12 - 0.4 * arch, 0.0, 0.25)
    P["jaw"] = (JAW0 + 0.25 + 0.2 * S(2 * th), 0.0, 0.0)
    hipx = P["hip"].x
    for sd, s in SIDES:
        off = 0.0 if sd == "L" else 0.09
        # hind: contact for the first third, then swung forward folded
        uh = (p + off) % 1.0
        x, z, t, sw = foot_path(uh, 1.1, 0.62, 0.55)
        P["ankle." + sd] = V(hipx + 0.3 + x * 1.0, 0.13 * s, 0.10 + z)
        P["foot." + sd] = (FOOT0 - 0.6 * (1 - smooth01(t * 3)) * (0 if sw else 1) + (0.1 if sw else 0.0), 0.0, 0.0)
        # fore: the hand lands on its fingertips ahead of the shoulder and rakes back
        uf = (p + 0.5 + off) % 1.0
        x, z, t, sw = foot_path(uf, 1.2, 0.6, 0.6)
        P["wrist." + sd] = V(hipx + 0.84 + 0.2 + x, 0.27 * s, 0.46 + z)
        P["hand." + sd] = (-0.95, 0.0, 0.0)
        P["epole." + sd] = V(-0.4, 0.9 * s, 1.0)
        P["curl." + sd] = (0.5 if not sw else 0.2, 0.6 if not sw else 0.3)
    return P


def splay(P, sd, a=0.3, b=0.35):
    P["curl." + sd] = (a, b)


def key_coil():
    """The wind-up (the tell): down on both feet and both hands wide, knees up beside the chest, back arched, head low, jaw gaping."""
    P = base_pose()
    P["hip"] = V(-0.12, 0.0, 0.56)
    bump(P, "hips", 0.25, 0.0, 0.0)
    P["spine1"] = (0.42, 0.0, 0.0)
    P["spine2"] = (0.24, 0.0, 0.0)
    P["chest"] = (0.02, 0.0, 0.0)
    P["neck1"] = (0.1, 0.0, 0.1)
    P["neck2"] = (-0.05, 0.0, 0.2)
    P["head"] = (-0.3, 0.0, 0.3)
    P["jaw"] = (JAW0 + 0.15, 0.0, 0.0)
    for sd, s in SIDES:
        P["ankle." + sd] = V(0.12, 0.26 * s, 0.10)
        P["kpole." + sd] = V(1.0, 0.9 * s, 0.4)
        P["foot." + sd] = (FOOT0 + 0.1, 0.0, 0.0)
        P["wrist." + sd] = V(0.62, 0.55 * s, 0.34)
        P["hand." + sd] = (-1.0, 0.25 * s, 0.0)
        P["epole." + sd] = V(-0.3, 0.9 * s, 1.0)
        splay(P, sd, 0.35, 0.55)
    return P


def key_fly():
    """Airborne, stretched out: arms reaching, fingers spread, legs trailing, head up, jaw wide."""
    P = base_pose()
    P["hip"] = V(-0.30, 0.0, 1.0)
    bump(P, "hips", 0.25)
    P["spine1"] = (0.5, 0.0, 0.0)
    P["spine2"] = (0.42, 0.0, 0.0)
    P["chest"] = (0.3, 0.0, 0.0)
    P["neck1"] = (0.3, 0.0, 0.1)
    P["neck2"] = (0.15, 0.0, 0.2)
    P["head"] = (0.0, 0.0, 0.25)
    P["jaw"] = (JAW0 + 0.35, 0.0, 0.0)
    for sd, s in SIDES:
        P["wrist_rel." + sd] = V(0.8, 0.3 * s, 0.55)
        P["hand." + sd] = (0.5, 0.0, 0.0)
        P["epole." + sd] = V(-0.2, 0.9 * s, 0.5)
        splay(P, sd, -0.1, 0.1)
        P["ankle." + sd] = V(-0.85, 0.22 * s, 0.55)
        P["kpole." + sd] = V(0.3, 0.8 * s, 0.6)
        P["foot." + sd] = (-0.6, 0.0, 0.0)
        P["toe." + sd] = -0.3
    return P


def key_land():
    """The reach for the car: arms forward and down, claws open, legs coming through under the body."""
    P = base_pose()
    P["hip"] = V(-0.2, 0.0, 0.85)
    bump(P, "hips", 0.1)
    P["spine1"] = (0.7, 0.0, 0.0)
    P["spine2"] = (0.55, 0.0, 0.0)
    P["chest"] = (0.3, 0.0, 0.0)
    P["neck1"] = (0.2, 0.0, 0.1)
    P["neck2"] = (0.0, 0.0, 0.2)
    P["head"] = (-0.2, 0.0, 0.3)
    P["jaw"] = (JAW0 + 0.45, 0.0, 0.0)
    for sd, s in SIDES:
        P["wrist_rel." + sd] = V(0.75, 0.34 * s, -0.45)
        P["hand." + sd] = (-0.4, 0.0, 0.0)
        P["epole." + sd] = V(-0.2, 0.9 * s, 0.5)
        splay(P, sd, 0.1, 0.2)
        P["ankle." + sd] = V(0.2, 0.25 * s, 0.35)
        P["kpole." + sd] = V(1.0, 0.7 * s, 0.4)
        P["foot." + sd] = (-0.2, 0.0, 0.0)
    return P


def pose_pounce(f):
    """One shot, 28 frames: 0-9 the crouch (the view stretches this part over the wind-up), 9-12 the launch, 12-24 flight, 24-27 the reach."""
    coil, fly, land = key_coil(), key_fly(), key_land()
    if f <= 9:
        P = mixp(pose_idle(0.0), coil, smooth01(f / 6.0))
        sh = 0.025 * S(f * 2.4) * smooth01(f / 6.0)
        bump(P, "spine2", sh)
        bump(P, "head", 0.4 * sh)
        return P
    if f <= 12:
        return mixp(coil, fly, smooth01((f - 9) / 3.0))
    if f <= 24:
        t = (f - 12) / 12.0
        P = dict(fly)
        P["hip"] = fly["hip"] + V(0.1 * t, 0, -0.1 * t)
        return mixp(fly, land, smooth01(max(0.0, t - 0.3) / 0.7) * 0.6)
    return mixp(mixp(fly, land, 0.6), land, smooth01((f - 24) / 3.0))


def pose_latch(p):
    """Crouched on the car, hands forward raking at the metal in turn, head ducking to bite, the jaw swinging shut and open."""
    th = 2 * math.pi * p
    P = base_pose()
    P["hip"] = V(-0.25, 0.012 * S(th), 0.66 + 0.02 * S(2 * th))
    bump(P, "hips", 0.2)
    P["spine1"] = (0.45 + 0.05 * S(2 * th), 0.0, 0.0)
    P["spine2"] = (0.28 + 0.06 * S(2 * th + 0.5), 0.1 * S(th), 0.0)
    P["chest"] = (0.12, 0.15 * S(th), 0.0)
    P["neck1"] = (0.0, 0.1 * S(th + 0.5), 0.1)
    P["neck2"] = (-0.2 + 0.15 * S(2 * th), 0.2 * S(th + 0.5), 0.2)
    P["head"] = (-0.5 + 0.35 * S(2 * th + 0.3), 0.3 * S(th + 0.8), 0.35)
    P["jaw"] = (JAW0 + 0.45 + 0.45 * S(2 * th + 0.3), 0.0, 0.0)
    for sd, s in SIDES:
        u = (p + (0.0 if sd == "L" else 0.5)) % 1.0
        x, z, t, sw = foot_path(u, 0.5, 0.35, 0.18)
        P["wrist." + sd] = V(0.62 + 0.28 + x, 0.36 * s, 0.34 + z)
        P["hand." + sd] = (-1.0 + (0.3 if sw else 0.0), 0.0, 0.0)
        P["epole." + sd] = V(-0.3, 0.9 * s, 1.0)
        splay(P, sd, 0.5 if not sw else 0.15, 0.7 if not sw else 0.3)
        P["ankle." + sd] = V(0.05, 0.3 * s, 0.10)
        P["kpole." + sd] = V(1.0, 0.8 * s, 0.4)
        P["foot." + sd] = (FOOT0, 0.0, 0.0)
    return P


def pose_thrown(p):
    """Limp in the air: arms and legs flung out and flailing, back whipping, head lolling, the jaw flapping, fingers spread."""
    th = 2 * math.pi * p
    P = base_pose()
    P["hip"] = V(0.0, 0.0, 0.95)
    bump(P, "hips", 0.2 * S(th), 0.2 * S(th + 1.0), 0.3 * S(th + 2.0))
    bump(P, "spine1", -0.3 + 0.3 * S(th + 0.5), 0.25 * S(2 * th))
    bump(P, "spine2", -0.2 + 0.3 * S(th + 1.0), 0.25 * S(2 * th + 1.0))
    bump(P, "chest", 0.2 * S(th + 1.5), 0.2 * S(th))
    bump(P, "neck1", 0.3 * S(th + 2.0), 0.4 * S(th), 0.3 * S(th))
    bump(P, "neck2", 0.3 * S(th + 2.5), 0.4 * S(th + 0.5), 0.3)
    bump(P, "head", 0.4 * S(th + 3.0), 0.5 * S(th + 1.0), 0.6 * S(th))
    P["jaw"] = (JAW0 + 0.5 + 0.5 * S(2 * th), 0.2 * S(th), 0.0)
    for sd, s in SIDES:
        ph = 0.0 if sd == "L" else 2.3
        P["wrist_rel." + sd] = V(0.4 * S(th + ph), (0.5 + 0.35 * S(th + ph + 1.0)) * s, 0.3 + 0.5 * S(th + ph + 2.0))
        P["epole." + sd] = V(-0.3, 0.9 * s, 0.5)
        splay(P, sd, 0.2 * S(2 * th + ph), -0.1 + 0.2 * S(2 * th + ph))
        P["ankle." + sd] = V(0.5 * S(th + ph + 1.5), (0.35 + 0.15 * S(th + ph)) * s, 0.25 + 0.45 * pos(S(th + ph + 2.2)) + 0.1)
        P["kpole." + sd] = V(1.0, 0.5 * s, 0.4)
        P["foot." + sd] = (FOOT0 + 0.5 * S(th + ph), 0.0, 0.0)
    return P


def lying(P, side=0.0):
    """Prone and spread: belly on the ground, arms out ahead, legs splayed behind, head turned."""
    P["hip"] = V(-0.45, 0.0, 0.13)
    P["hips"] = (0.0, 0.0, 0.0)
    P["spine1"] = (0.02, 0.0, 0.0)
    P["spine2"] = (0.0, 0.1, 0.0)
    P["chest"] = (0.0, 0.0, 0.0)
    P["neck1"] = (0.05, 0.3, 0.0)
    P["neck2"] = (0.0, 0.5, 0.4)
    P["head"] = (-0.3, 0.9, 1.2)
    P["jaw"] = (-0.9, 0.0, 0.0)
    for sd, s in SIDES:
        P["wrist." + sd] = V(0.5, (0.65 + 0.1 * s * side) * s, 0.06)
        P["hand." + sd] = (-0.2, 0.2 * s, 0.0)
        P["epole." + sd] = V(-0.2, 1.0 * s, -0.3)
        splay(P, sd, 0.2, 0.3)
        P["ankle." + sd] = V(-0.85 - 0.1 * s * side, 0.42 * s, 0.07)
        P["kpole." + sd] = V(-0.2, 1.0 * s, 0.5)
        P["foot." + sd] = (-0.2, 0.0, 0.0)
        P["toe." + sd] = 0.0
    return P


def pose_dead(f):
    """One shot, 14 frames: the sprint collapses into a prone sprawl."""
    t = smooth01(f / 11.0)
    A = pose_sprint(0.0)
    B = lying(base_pose(), 0.3)
    P = mixp(A, B, t)
    P["hip"] = V(lerp(A["hip"].x, B["hip"].x, t), 0.0, lerp(A["hip"].z, B["hip"].z, smooth01(f / 9.0)) + 0.18 * S(math.pi * min(1.0, f / 7.0)))
    return P


def roll_about_x(P, theta, pivot):
    R = Matrix.Rotation(theta, 3, "X")
    P["G"] = (pivot, R)
    return P


def pose_missed(f):
    """One shot, 21 frames: it lands on its hands, skids, rolls over once and scrambles back onto fingertips and feet."""
    P0 = pose_dead(11)
    fall = key_land()
    if f <= 3:
        P = mixp(fall, lying(base_pose(), 0.0), smooth01(f / 3.0))
        P["hip"] = V(-0.4, 0.0, lerp(0.85, 0.2, smooth01(f / 3.0)))
        P["head"] = (-0.4, 0.2 * S(f), 0.3)
        return P
    if f <= 12:
        # a tight roll, tucked, along its own length
        t = (f - 3) / 9.0
        P = lying(base_pose(), 0.0)
        hz = 0.42 + 0.1 * S(math.pi * t)
        P["hip"] = V(-0.4 + 0.5 * t, 0.0, hz)
        P["spine1"] = (0.0, 0.0, 0.0)
        P["head"] = (-0.3, 0.0, 0.3)
        P["jaw"] = (-0.9 + 0.3 * S(5 * t), 0.0, 0.0)
        for sd, s in SIDES:
            P["wrist." + sd] = V(0.25 + P["hip"].x + 0.4, 0.22 * s, hz - 0.1)
            P["epole." + sd] = V(-0.2, 1.0 * s, 0.3)
            P["ankle." + sd] = V(P["hip"].x - 0.05, 0.2 * s, hz - 0.25)
            P["kpole." + sd] = V(1.0, 1.0 * s, 0.2)
            P["foot." + sd] = (-0.8, 0.0, 0.0)
            splay(P, sd, 0.5, 0.7)
        return roll_about_x(P, 2 * math.pi * smooth01(t), V(P["hip"].x + 0.3, 0.0, hz))
    t = smooth01((f - 12) / 9.0)
    A = lying(base_pose(), 0.0)
    A["hip"] = V(-0.4, 0.0, 0.2)
    B = pose_sprint(0.45)
    return mixp(A, B, t)


def pose_stunned_ground(f):
    """The ground part of the stun, 45 frames: face down where it landed, twitching, then it pushes up and gets its feet under it."""
    A = lying(base_pose(), 0.4)
    if f <= 18:
        P = dict(A)
        tw = S(f * 1.7) * 0.5 + S(f * 3.1) * 0.5
        bump(P, "chest", 0.02 * tw)
        bump(P, "head", 0.05 * tw, 0.1 * tw, 0.0)
        P["jaw"] = (A["jaw"][0] + 0.12 * tw, 0.0, 0.0)
        for sd, s in SIDES:
            P["curl." + sd] = (0.2 + 0.3 * pos(S(f * 2.3 + s)), 0.3 + 0.3 * pos(S(f * 2.9 - s)))
        P["hip"] = A["hip"] + V(0.0, 0.0, 0.01 * tw)
        return P
    if f <= 33:
        t = smooth01((f - 18) / 15.0)
        B = base_pose()
        B["hip"] = V(-0.35, 0.0, 0.6)
        B["hips"] = (0.25, 0.0, 0.0)
        B["spine1"] = (0.4, 0.0, 0.0)
        B["spine2"] = (0.22, 0.0, 0.0)
        B["chest"] = (0.05, 0.0, 0.0)
        B["neck1"] = (0.1, 0.0, 0.1)
        B["neck2"] = (-0.1, 0.0, 0.2)
        B["head"] = (-0.4, 0.0, 0.3)
        B["jaw"] = (JAW0 + 0.2, 0.0, 0.0)
        for sd, s in SIDES:
            B["wrist." + sd] = V(0.45, 0.45 * s, 0.34)
            B["hand." + sd] = (-1.0, 0.2 * s, 0.0)
            B["epole." + sd] = V(-0.3, 0.9 * s, 1.0)
            splay(B, sd, 0.4, 0.5)
            B["ankle." + sd] = V(-0.05, 0.28 * s, 0.10)
            B["kpole." + sd] = V(1.0, 0.9 * s, 0.4)
            B["foot." + sd] = (FOOT0, 0.0, 0.0)
        return mixp(A, B, t)
    t = smooth01((f - 33) / 12.0)
    B = key_coil()
    B["hip"] = V(-0.35, 0.0, 0.6)
    return mixp(B, pose_sprint(0.45), t)


def key_skid():
    """Hitting the road on its feet and hands, skidding: low, hands out ahead, legs braced, head snapping down."""
    P = base_pose()
    P["hip"] = V(-0.35, 0.0, 0.5)
    bump(P, "hips", 0.3)
    P["spine1"] = (0.2, 0.0, 0.0)
    P["spine2"] = (0.08, 0.0, 0.0)
    P["chest"] = (-0.05, 0.0, 0.0)
    P["neck1"] = (0.0, 0.0, 0.1)
    P["neck2"] = (-0.1, 0.0, 0.2)
    P["head"] = (-0.5, 0.3, 0.5)
    P["jaw"] = (JAW0 + 0.4, 0.0, 0.0)
    for sd, s in SIDES:
        P["wrist." + sd] = V(0.75, 0.5 * s, 0.1)
        P["hand." + sd] = (-0.3, 0.2 * s, 0.0)
        P["epole." + sd] = V(-0.2, 1.0 * s, 0.2)
        splay(P, sd, 0.1, 0.2)
        P["ankle." + sd] = V(0.25, 0.3 * s, 0.12)
        P["kpole." + sd] = V(1.0, 0.9 * s, 0.3)
        P["foot." + sd] = (FOOT0 + 0.2, 0.0, 0.0)
    return P


def pose_stunned(f):
    """One shot, 54 frames: knocked out of the air it hits the road and skids (9 frames), then lies, twitches, pushes up and gets up."""
    if f < 9:
        A, K, L_ = pose_thrown(0.45), key_skid(), lying(base_pose(), 0.4)
        if f <= 4:
            return mixp(A, K, smooth01(f / 4.0))
        return mixp(K, L_, smooth01((f - 4) / 5.0))
    return pose_stunned_ground(f - 9)


# name -> (frames, looping, pose function of (phase for loops | frame for one-shots))
CLIPS = {
    "idle": (60, True, pose_idle),
    "stalk": (26, True, pose_stalk),
    "sprint": (16, True, pose_sprint),
    "pounce": (28, False, pose_pounce),
    "latch": (24, True, pose_latch),
    "thrown": (24, True, pose_thrown),
    "dead": (14, False, pose_dead),
    "missed": (21, False, pose_missed),
    "stunned": (54, False, pose_stunned),
}


def rest_mats(ao):
    return {b.name: b.matrix_local.to_3x3() for b in ao.data.bones}


def animate(ao):
    ao.animation_data_create()
    rest = rest_mats(ao)
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

def preview_rest(ao, mesh):
    os.makedirs(PREV, exist_ok=True)
    res = (900, 900)
    for name, cam in (("front", (6.0, 0.0, 1.1)), ("side", (0.4, -6.0, 1.1)), ("threeq", (4.2, -3.8, 1.5))):
        for ob in list(bpy.data.objects):
            if ob.name.startswith(("sun", "cam")):
                bpy.data.objects.remove(ob)
        preview(os.path.join(PREV, "gaunt_rest_%s.png" % name), cam, (0.4, 0, 1.0), lens=50, res=res, sun_rot=(0.9, 0.3, 0.5), world="#1c2630", sun=2.4, fill=1.4)


def preview_sheet(ao, mesh):
    """Frames of the clips side on (or from the front with VIEWSIDE=front), each strip written to $HH_PREV/<clip>.png with a ground line."""
    os.makedirs(PREV, exist_ok=True)
    rest = rest_mats(ao)
    ao.animation_data_clear()
    only = os.environ.get("ONLY")  # e.g. ONLY=sprint:0,4,8,12,stalk:0,6
    frames = {}
    if only:
        cur = None
        for tok in only.split(","):
            if ":" in tok:
                cur, tok = tok.split(":")
                frames.setdefault(cur, [])
            frames[cur].append(int(tok))
    else:
        for name, (n, looping, fn) in CLIPS.items():
            frames[name] = list(range(0, n, max(1, n // 8)))
    if MAGICK is None:
        raise SystemExit("ImageMagick (the `magick` command) is needed to stitch the contact sheets")
    side = os.environ.get("VIEWSIDE", "side")
    flo = cube_bm((6, 6, 0.02), loc=(0, 0, -0.01))
    make_obj("floor", flo, mat("floor", "#2a2f36", rough=0.6))
    for i in range(-5, 6):
        make_obj("tick%d" % i, cube_bm((0.02, 6, 0.004), loc=(i * 0.5, 0, 0.0)), mat("tick", "#5a626c", rough=0.6))
    scale_hint = float(os.environ.get("CAMX", "0.4"))
    for name, fl in frames.items():
        n, looping, fn = CLIPS[name]
        files = []
        for f in fl:
            P = fn(f / n) if looping else fn(f)
            apply_pose(ao, P, rest)
            bpy.context.view_layer.update()
            for ob in list(bpy.data.objects):
                if ob.name.startswith(("sun", "cam")):
                    bpy.data.objects.remove(ob)
            cam = (scale_hint, -6.0, 1.0) if side == "side" else (7.0, 0.0, 1.0)
            fp = os.path.join(PREV, "_f_%s_%03d.png" % (name, f))
            preview(fp, cam, (scale_hint, 0, 0.95), lens=62, res=(600, 600), sun_rot=(0.9, 0.3, 0.5), world="#1c2630", sun=2.6, fill=1.6)
            files.append(fp)
        out = os.path.join(PREV, "%s%s.png" % (name, "" if side == "side" else "_front"))
        import subprocess
        rows = []
        for r in range(0, len(files), 4):
            rp = os.path.join(PREV, "_row%d.png" % r)
            subprocess.run([MAGICK] + files[r:r + 4] + ["+append", rp], check=True)
            rows.append(rp)
        subprocess.run([MAGICK] + rows + ["-append", out], check=True)
        for rp in rows:
            os.remove(rp)
        for fp in files:
            os.remove(fp)
        print("SHEET", out)


def preview_view(spec):
    """VIEW="x,y,z,tx,ty,tz,lens,name": one close still of the current pose (the rest pose here) for checking details."""
    v = spec.split(",")
    f = [float(x) for x in v[:7]]
    os.makedirs(PREV, exist_ok=True)
    for ob in list(bpy.data.objects):
        if ob.name.startswith(("sun", "cam")):
            bpy.data.objects.remove(ob)
    preview(os.path.join(PREV, "gaunt_view_%s.png" % v[7]), tuple(f[:3]), tuple(f[3:6]), lens=f[6], res=(1000, 1000), sun_rot=(0.9, 0.3, 0.5), world="#1c2630", sun=2.4, fill=1.4)


def init_rest():
    """The jaw's and the foot's rest pitch, which the clips are written relative to; needs the bones."""
    global JAW0, FOOT0
    JAW0 = pitch_of(bdir("jaw"))
    FOOT0 = pitch_of(bdir("foot.L"))


if __name__ == "__main__":
    ao, mesh = assemble()
    init_rest()
    animate(ao)
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.frame_start, sc.frame_end = 1, 61
    if "rest" in ARGS:
        preview_rest(ao, mesh)
    if "preview" in ARGS:
        preview_sheet(ao, mesh)
    elif "rest" not in ARGS and not os.environ.get("VIEW"):
        # the rest pose for export; the actions carry the clips
        for pb in ao.pose.bones:
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)
        tris = sum(len(p.vertices) - 2 for p in mesh.data.polygons)
        print("TRIANGLES", tris, "VERTS", len(mesh.data.vertices))
        export(os.path.join(OUT, "gaunt.glb"), [ao, mesh], extra=dict(export_animations=True, export_animation_mode="ACTIONS", export_skins=True, export_force_sampling=True, export_frame_range=False, export_optimize_animation_size=False, export_image_format="AUTO"))
    if os.environ.get("VIEW"):
        preview_view(os.environ["VIEW"])

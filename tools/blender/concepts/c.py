"""Concept C, "the Stilt": wrong limbs. A narrow, ribby torso no bigger than a man's, hung between legs 1.5 m long with a
bird's reversed knee and a foot as long as a forearm, and arms that end below the knee with fingers half a metre long.
The head is smooth and blind, a pale wedge on a long snaking neck, with a mouth that splits the whole length of it.
Stands 2.3 m, reaches 3 m. Stalks with slow, high, deliberate steps, freezes, then covers ground in huge bounding strides;
the legs let it jump onto a car's roof from the road, and the arms wrap a car like a cage. Thin in fog and headlights
until it is close, then all limb."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit
from kit import *
from gk import *
from mathutils import Matrix


def build():
    reset()
    M = {
        "skin": skin_material("skin", "#767a7c", mottle="#34373a", mottle_amt=0.7, scale=6.0),
        "pale": skin_material("pale", "#c9c4b6", mottle="#6e675f", mottle_amt=0.5, scale=8.0),
        "bone": mat("bone", "#d9d2bb", rough=0.45, coat=0.25),
        "dark": mat("dark", "#0c0607", rough=0.7),
    }
    mk = Maker()
    # torso: narrow, leaning forward over the hips, ribs like a cage
    keys = [V(-0.05, 0, 1.20), V(0.12, 0, 1.30), V(0.32, 0, 1.40), V(0.50, 0, 1.47)]
    ru_t = [(0, 0.11), (0.3, 0.085), (0.62, 0.14), (1.0, 0.13)]
    rv_t = [(0, 0.09), (0.3, 0.07), (0.62, 0.115), (1.0, 0.08)]
    n = 22
    pts = body(mk, "skin", keys, n, lambda t: prof(t, ru_t), lambda t: prof(t, rv_t), segs=12, bumps=lambda i: (1.05 if i % 2 == 0 else 0.985) if 7 <= i <= 19 else 1.0)
    for i in range(3, n - 2, 2):
        t = i / (n - 1)
        d = (pts[i + 1] - pts[i - 1]).normalized()
        back = Vector((-d.z, 0, d.x))
        mk.add("skin", blob(pts[i] + back * prof(t, rv_t) * 0.97, 0.014 + 0.004 * ((i * 5) % 3) / 2, segs=8, rings=5), 0)
    mk.add("skin", blob(V(-0.05, 0, 1.20), 1.0, scale=(0.1, 0.11, 0.09)), 1)
    # a long snaking neck down to a low head
    jn = [V(0.44, 0, 1.44), V(0.68, 0, 1.64), V(0.98, 0.03, 1.52), V(1.23, 0.05, 1.20)]
    limb(mk, "skin", jn, [0.075, 0.048, 0.04, 0.036], [0.065, 0.045, 0.038, 0.034], per=8, segs=10, subdiv=1)
    # the head: smooth, blind, a pale wedge; one long seam where the mouth is
    hp = V(1.23, 0.05, 1.19)
    H = mk.sub(Matrix.Translation(hp) @ Matrix.Rotation(1.05, 4, "Y"))
    H.add("pale", etube_bm([V(-0.03, 0, 0), V(0.1, 0, 0.005), V(0.26, 0, 0.0), V(0.42, 0, -0.01)], [0.045, 0.07, 0.05, 0.018], [0.055, 0.075, 0.05, 0.02], per=6, segs=12, ref=(0, 1, 0)), 1)
    H.add("dark", etube_bm([V(0.04, 0.0, -0.062), V(0.2, 0.0, -0.048), V(0.4, 0.0, -0.016)], [0.006, 0.007, 0.004], [0.004, 0.004, 0.003], per=6, segs=6, ref=(0, 1, 0)), 0)
    # the mouth, half open: upper and lower rows of needles
    Hj = mk.sub(Matrix.Translation(hp) @ Matrix.Rotation(1.45, 4, "Y"))
    Hj.add("pale", etube_bm([V(0.0, 0, -0.04), V(0.12, 0, -0.05), V(0.26, 0, -0.045), V(0.38, 0, -0.03)], [0.035, 0.05, 0.036, 0.014], [0.022, 0.026, 0.02, 0.01], per=5, segs=10, ref=(0, 1, 0)), 1)
    H.add("dark", sphere_bm(1.0, loc=V(0.2, 0, -0.065), scale=(0.17, 0.03, 0.02), segs=8, rings=5), 0)
    for k in range(10):
        x = 0.08 + k * 0.03
        for sy in (1, -1):
            spike(H, "bone", V(x, sy * (0.042 - 0.0012 * k), -0.058), V(x + 0.003, sy * (0.04 - 0.001 * k), -0.098 + 0.002 * k), 0.0042)
            spike(Hj, "bone", V(x + 0.01, sy * (0.03 - 0.0008 * k), -0.065), V(x + 0.012, sy * (0.028 - 0.0008 * k), -0.03 - 0.001 * k), 0.0038)
    # legs: a bird's reversed knee, a long foot; the left plants, the right is lifted high mid-step
    legs = (
        (1, [V(-0.05, 0.12, 1.20), V(0.50, 0.21, 1.52), V(-0.15, 0.18, 0.62), V(0.22, 0.18, 0.07)], V(0.46, 0.18, 0.015)),
        (-1, [V(-0.05, -0.12, 1.20), V(0.38, -0.21, 1.42), V(-0.28, -0.18, 0.60), V(0.08, -0.18, 0.07)], V(0.34, -0.18, 0.015)),
    )
    for s, jp, toe in legs:
        jlimb(mk, "skin", jp, [0.07, 0.052, 0.04, 0.028], knob=0.85, segs=10, belly=(1.35, 0.8))
        limb(mk, "skin", [jp[-1], jp[-1].lerp(toe, 0.5), toe], [0.026, 0.024, 0.008], [0.022, 0.018, 0.008], per=4, segs=8)
        for j in (-1, 0, 1):
            tip = toe + V(0.1, j * 0.045, -0.003)
            limb(mk, "skin", [jp[-1].lerp(toe, 0.75), toe + V(0.03, 0.02 * j, 0), tip], [0.014, 0.012, 0.005], per=3, segs=6)
            spike(mk, "bone", tip, tip + V(0.045, 0, -0.005), 0.007)
    # arms: shoulder, a long upper arm, an even longer forearm, a wrist and a half-metre hand
    arms = (
        (1, [V(0.50, 0.17, 1.44), V(0.58, 0.40, 0.98), V(1.16, 0.34, 0.66), V(1.34, 0.33, 0.52)], V(0.8, 0, -0.55), V(0, 0, -1)),
        (-1, [V(0.50, -0.17, 1.42), V(0.50, -0.40, 0.94), V(1.14, -0.32, 0.34), V(1.34, -0.31, 0.16)], V(0.9, 0, -0.35), V(0, 0, -1)),
    )
    for s, jp, fwd, dn in arms:
        jlimb(mk, "skin", jp, [0.05, 0.036, 0.028, 0.02], knob=0.9, segs=8, belly=(1.3, 0.85))
        hand(mk, "pale", jp[-1], fwd, V(0, 1, 0), dn, spread=0.45, flen=0.52, curl=0.22, r0=0.012, claw_key="bone")
    return [mk.build(M, "stilt")]


if __name__ == "__main__":
    kit.main(build, "c")

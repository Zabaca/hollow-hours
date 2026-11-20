"""Concept B, "the Slab": heavy and low, a hyena-sloped back on a quarter of a tonne. About 2.8 m long, 1.4 m at the withers.
Charcoal wet skin over a deep barrel chest, a shingle of low bone scutes down the spine, forelimbs far bigger than the
hind with three blunt claws on each hand, a thick neck carrying a bare pale skull (lips gone, every tooth showing,
sockets deep) held low between the shoulders so it floats in the dark as a white shape. Moves in a rolling lope,
charges in a gallop, leaps short and heavy and clamps onto a car with the forelimbs, too heavy to be thrown far."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit
from kit import *
from gk import *
from mathutils import Matrix


def build():
    reset()
    M = {
        "skin": skin_material("skin", "#625b5a", mottle="#2c2527", mottle_amt=0.7, scale=5.0),
        "bone": mat("bone", "#d6cdb4", rough=0.42, coat=0.35),
        "scute": mat("scute", "#7a715c", rough=0.5, coat=0.3),
        "eye": mat("eye", "#efe9b0", rough=0.2, emit="#e5dc90", emit_strength=3.0),
        "dark": mat("dark", "#0d0607", rough=0.7),
    }
    mk = Maker()

    def span(a, b, ts):
        return [a.lerp(b, t) for t in ts]

    # body: deep barrel at the chest, sloping down to a narrow heavy rump
    keys = [V(-0.95, 0, 0.72), V(-0.55, 0, 0.80), V(-0.05, 0, 0.90), V(0.35, 0, 1.02), V(0.62, 0, 1.10), V(0.88, 0, 1.02)]
    ru_t = [(0, 0.14), (0.2, 0.2), (0.45, 0.24), (0.7, 0.36), (0.88, 0.33), (1.0, 0.25)]
    rv_t = [(0, 0.19), (0.2, 0.25), (0.45, 0.27), (0.7, 0.38), (0.88, 0.36), (1.0, 0.28)]
    n = 22
    pts = body(mk, "skin", keys, n, lambda t: prof(t, ru_t), lambda t: prof(t, rv_t), segs=16, bumps=lambda i: (1.035 if i % 2 == 0 else 0.99) if 10 <= i <= 19 else 1.0)
    # a shingle of low bone scutes down the spine, each tipped back
    for k, i in enumerate(range(15, 1, -3)):
        t = i / (n - 1)
        top = pts[i] + V(0, 0, prof(t, rv_t) * 0.97)
        w = prof(t, ru_t) * 0.85
        ln = 0.2 - 0.008 * k
        i0, i1 = i - 1, min(i + 1, n - 1)
        slope = (pts[i1].z - pts[i0].z) / (pts[i1].x - pts[i0].x)
        P = mk.sub(Matrix.Translation(top) @ Matrix.Rotation(-math.atan(slope) + 0.3, 4, "Y"))
        P.add("scute", sphere_bm(1.0, loc=V(0, 0, 0.0), scale=(ln, w, 0.03), segs=14, rings=6), 0)
        spike(P, "scute", V(-ln * 0.5, 0, 0.0), V(-ln * 1.0, 0, 0.1 - 0.004 * k), 0.022)
    # shoulder and haunch masses
    for s in (1, -1):
        mk.add("skin", blob(V(0.56, 0.32 * s, 0.9), 1.0, scale=(0.3, 0.21, 0.3)), 1)
        mk.add("skin", blob(V(-0.58, 0.2 * s, 0.72), 1.0, scale=(0.26, 0.15, 0.24)), 1)
    # thick neck, then the bare skull carried low
    limb(mk, "skin", [V(0.72, 0, 1.02), V(0.92, 0, 0.9), V(1.08, 0, 0.78)], [0.27, 0.22, 0.17], [0.27, 0.22, 0.17], per=6, segs=14, subdiv=1)
    hp = V(1.18, 0, 0.74)
    mk.add("skin", blob(V(1.08, 0, 0.78), 1.0, scale=(0.17, 0.19, 0.18)), 1)
    H = mk.sub(Matrix.Translation(hp) @ Matrix.Rotation(0.3, 4, "Y"))
    H.add("bone", sphere_bm(1.0, loc=V(0, 0, 0), scale=(0.17, 0.14, 0.13), segs=14, rings=8), 1)
    H.add("bone", etube_bm([V(0.08, 0, -0.01), V(0.26, 0, -0.025), V(0.5, 0, -0.045)], [0.12, 0.095, 0.065], [0.115, 0.08, 0.055], per=6, segs=12), 1)
    H.add("bone", sphere_bm(1.0, loc=V(0.0, 0, 0.14), scale=(0.2, 0.014, 0.035), segs=10, rings=5), 0)  # crest
    for s in (1, -1):
        H.add("dark", sphere_bm(1.0, loc=V(0.15, 0.083 * s, 0.045), scale=(0.05, 0.04, 0.03), segs=10, rings=6), 0)
        H.add("bone", etube_bm([V(0.17, 0.045 * s, 0.085), V(0.15, 0.085 * s, 0.075), V(0.12, 0.12 * s, 0.045)], [0.014, 0.014, 0.012], [0.012, 0.012, 0.01], per=5, segs=8, ref=(1, 0, 0)), 0)
        eye(H, V(0.188, 0.083 * s, 0.043), 0.012, scale=(0.6, 1, 0.6))
        H.add("bone", etube_bm([V(0.2, 0.1 * s, -0.01), V(0.1, 0.17 * s, -0.03), V(-0.04, 0.14 * s, -0.03)], [0.018, 0.02, 0.018], [0.014, 0.016, 0.014], per=5, segs=8, ref=(0, 0, 1)), 0)  # cheek arch
        H.add("dark", sphere_bm(1.0, loc=V(0.52, 0.025 * s, 0.0), scale=(0.01, 0.014, 0.014), segs=6, rings=4), 0)
        # upper teeth: a full bared row, a long canine
        for k in range(8):
            x = 0.16 + k * 0.045
            hw = 0.115 - 0.05 * (x - 0.16) / 0.35
            ln = 0.075 if k == 5 else 0.04 + (0.01 if k == 2 else 0)
            spike(H, "bone", V(x, hw * s, -0.07 + 0.012 * k * 0), V(x + 0.004, (hw - 0.004) * s, -0.07 - ln), 0.011 if k == 5 else 0.008)
    # lower jaw, hung slightly open under the face
    Jm = mk.sub(Matrix.Translation(hp) @ Matrix.Rotation(0.5, 4, "Y"))
    jaw = [V(0.0, 0.11, -0.1), V(0.22, 0.075, -0.115), V(0.44, 0.03, -0.12), V(0.5, 0, -0.12), V(0.44, -0.03, -0.12), V(0.22, -0.075, -0.115), V(0.0, -0.11, -0.1)]
    Jm.add("bone", etube_bm(jaw, [0.02, 0.025, 0.02, 0.018, 0.02, 0.025, 0.02], [0.02, 0.022, 0.018, 0.016, 0.018, 0.022, 0.02], per=6, segs=8, ref=(0, 0, 1)), 0)
    Jm.add("dark", sphere_bm(1.0, loc=V(0.26, 0, -0.06), scale=(0.22, 0.07, 0.05), segs=10, rings=6), 0)
    for k in range(8):
        t = (k - 3.5) / 3.5
        for sy in (1, -1):
            x = 0.12 + k * 0.045
            hw = 0.085 - 0.05 * (x - 0.12) / 0.4
            spike(Jm, "bone", V(x, sy * hw, -0.11), V(x + 0.004, sy * (hw - 0.004), -0.11 + (0.075 if k == 4 else 0.04)), 0.008)
    # forelimbs: far bigger than the hind; the left lifted mid-step, the right planted
    arms = (
        (1, V(0.56, 0.32, 0.92), V(0.28, 0.47, 0.64), V(0.80, 0.44, 0.42), V(0.95, 0.43, 0.32)),
        (-1, V(0.56, -0.32, 0.92), V(0.30, -0.47, 0.56), V(0.74, -0.44, 0.18), V(0.88, -0.43, 0.08)),
    )
    for s, sh, el, wr, hand_c in arms:
        keys = [sh, sh.lerp(el, 0.5), el] + span(el, hand_c, (0.35, 0.7)) + [hand_c]
        limb(mk, "skin", keys, [0.2, 0.17, 0.12, 0.15, 0.12, 0.1], [0.22, 0.18, 0.13, 0.15, 0.11, 0.1], per=6, segs=12)
        mk.add("skin", blob(el, 0.12), 0)
        mk.add("skin", blob(hand_c, 1.0, scale=(0.13, 0.13, 0.09)), 0)
        for j in (-1, 0, 1):
            base = hand_c + V(0.08, 0.07 * j, -0.01)
            pts_f = finger(mk, "skin", base, V(1, 0.1 * j, -0.25), V(0, 1, 0), (0.08, 0.06, 0.05), (0.0, 0.3, 0.3), r0=0.045, taper=0.6)
            tip = pts_f[-1]
            dd = (pts_f[-1] - pts_f[-2]).normalized()
            spike(mk, "bone", tip - dd * 0.03, tip + dd * 0.12, 0.03)
    # hind limbs: short, stout, digitigrade
    for s in (1, -1):
        hip = V(-0.60, 0.22 * s, 0.76)
        knee = V(-0.30 + 0.06 * s, 0.30 * s, 0.46)
        hock = V(-0.78, 0.26 * s, 0.33)
        toe = V(-0.56, 0.26 * s, 0.03)
        keys = [hip, hip.lerp(knee, 0.5), knee] + span(knee, hock, (0.5,)) + [hock] + span(hock, toe, (0.5,)) + [toe]
        limb(mk, "skin", keys, [0.17, 0.15, 0.1, 0.085, 0.06, 0.05, 0.05], [0.18, 0.15, 0.1, 0.09, 0.06, 0.05, 0.05], per=5, segs=10)
        mk.add("skin", blob(knee, 0.095), 0)
        mk.add("skin", blob(toe + V(0.05, 0, 0.02), 1.0, scale=(0.14, 0.09, 0.05)), 0)
        for j in (-1, 0, 1):
            spike(mk, "bone", toe + V(0.14, 0.05 * j, 0.01), toe + V(0.27, 0.07 * j, 0.0), 0.024)
    mk.add("skin", etube_bm([V(-1.0, 0, 0.7), V(-1.18, 0, 0.64), V(-1.3, 0, 0.56)], [0.1, 0.06, 0.012], [0.1, 0.06, 0.012], per=5, segs=8), 1)
    return [mk.build(M, "slab")]


if __name__ == "__main__":
    kit.main(build, "b")

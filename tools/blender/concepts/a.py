"""Concept A, "the Stooper": a once-human figure, tall, starved and wrong. Stands 2.1 m hunched, would be 2.4 m straight.
Arms hang to the shins, the head leans on a long neck and the lower jaw hangs slack and too long. Walks upright in a
stalking lope and drops to all fours (arms are long enough that the hands reach the ground without a crouch) to sprint,
the long fingers leading. Pale wet skin over a visible spine and ribs, a few rags from the waist."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit
from kit import *
from gk import *


def build():
    reset()
    M = {
        "skin": skin_material("skin", "#a8a398", mottle="#4d4648", mottle_amt=0.6, scale=7.0),
        "bone": mat("bone", "#d9d3bf", rough=0.45, coat=0.25),
        "eye": mat("eye", "#eceab8", rough=0.2, emit="#e3e0a0", emit_strength=3.0),
        "dark": mat("dark", "#0c0607", rough=0.7),
        "cloth": mat("cloth", "#26241f", rough=0.95),
    }
    mk = Maker()
    # torso: leans forward along a bent spine; narrow waist, a deep starved ribcage, sharp collar line
    keys = [(-0.05, 0, 1.10), (0.10, 0, 1.38), (0.30, 0.02, 1.64), (0.47, 0.03, 1.80)]
    ru_t = [(0, 0.115), (0.28, 0.085), (0.55, 0.14), (0.78, 0.155), (1.0, 0.15)]
    rv_t = [(0, 0.09), (0.28, 0.07), (0.55, 0.115), (0.78, 0.115), (1.0, 0.07)]
    n = 26
    pts = body(mk, "skin", keys, n, lambda t: prof(t, ru_t), lambda t: prof(t, rv_t), segs=14, bumps=lambda i: (1.045 if i % 2 == 0 else 0.985) if 8 <= i <= 22 else 1.0)
    # spine knobs along the back
    for i in range(3, n - 2, 2):
        t = i / (n - 1)
        d = (pts[i + 1] - pts[i - 1]).normalized()
        back = Vector((-d.z, 0, d.x))
        c = pts[i] + back * prof(t, rv_t) * 0.97
        mk.add("skin", blob(c, 0.016 + 0.006 * ((i * 7) % 3) / 2, segs=8, rings=5), 0)
    # shoulder blades jutting
    for s in (1, -1):
        mk.add("skin", etube_bm([V(0.30, 0.08 * s, 1.80), V(0.36, 0.16 * s, 1.70), V(0.44, 0.19 * s, 1.60)], [0.02, 0.05, 0.02], [0.03, 0.03, 0.02], per=4, segs=8, ref=(0, 0, 1)), 0)
    mk.add("skin", blob(V(-0.05, 0, 1.08), 1.0, scale=(0.12, 0.125, 0.1)), 1)
    # neck and head; the head leans to the left, face forward and down
    limb(mk, "skin", [V(0.40, 0, 1.76), V(0.56, 0.02, 1.82), V(0.72, 0.04, 1.84)], [0.1, 0.065, 0.05], [0.075, 0.056, 0.046], subdiv=1)
    limb(mk, "skin", [V(0.44, -0.15, 1.79), V(0.45, 0.0, 1.84), V(0.44, 0.15, 1.81)], [0.02, 0.03, 0.02], [0.018, 0.026, 0.018], per=6, segs=8, ref=(1, 0, 0))
    # the head, built upright in its own frame (face +X, up +Z), then cocked and carried to the neck
    from mathutils import Matrix
    hp = V(0.82, 0.06, 1.86)
    M_head = Matrix.Translation(hp) @ Matrix.Rotation(-0.42, 4, "X") @ Matrix.Rotation(0.18, 4, "Y")
    H = mk.sub(M_head)
    H.add("skin", etube_bm([V(0, 0, 0.125), V(0, 0, 0.07), V(0, 0, 0.0), V(0, 0, -0.07), V(0, 0, -0.125)], [0.03, 0.074, 0.08, 0.07, 0.042], [0.04, 0.092, 0.098, 0.078, 0.052], per=5, segs=14, ref=(0, 1, 0)), 1)
    # heavy brow shelf over sunken eyes, high cheekbones, no nose: only two slits
    H.add("skin", etube_bm([V(0.066, 0.056, 0.046), V(0.086, 0.0, 0.05), V(0.066, -0.056, 0.046)], [0.012, 0.016, 0.012], [0.012, 0.014, 0.012], per=6, segs=8, ref=(1, 0, 0)), 0)
    for s in (1, -1):
        H.add("dark", blob(V(0.076, 0.037 * s, 0.012), 1.0, scale=(0.014, 0.02, 0.024)), 0)
        eye(H, V(0.087, 0.037 * s, 0.008), 0.0045, scale=(0.5, 1, 1.2))
        H.add("skin", etube_bm([V(0.05, 0.07 * s, -0.012), V(0.076, 0.054 * s, -0.026), V(0.082, 0.032 * s, -0.036)], [0.011, 0.011, 0.01], [0.01, 0.01, 0.008], per=5, segs=8, ref=(0, 0, 1)), 0)
        H.add("dark", blob(V(0.093, 0.008 * s, -0.052), 1.0, scale=(0.005, 0.004, 0.014)), 0)
    # wide lipless mouth line, upper teeth
    H.add("dark", etube_bm([V(0.075, 0.062, -0.098), V(0.092, 0.0, -0.104), V(0.075, -0.062, -0.098)], [0.004, 0.006, 0.004], [0.004, 0.005, 0.004], per=6, segs=6, ref=(1, 0, 0)), 0)
    for k in range(11):
        t = (k - 5) / 5.0
        y = t * 0.056
        x = 0.062 + 0.026 * (1 - t * t)
        spike(H, "bone", V(x, y, -0.108), V(x + 0.004, y, -0.158 + 0.012 * abs(t)), 0.0052)
    # the lower jaw: a U of bone under stretched skin, unhinged, hanging well below the face (hangs near-straight down)
    M_jaw = Matrix.Translation(hp) @ Matrix.Rotation(-0.10, 4, "X") @ Matrix.Rotation(0.05, 4, "Y")
    J = mk.sub(M_jaw)
    jaw = [V(-0.02, 0.076, -0.06), V(0.02, 0.07, -0.20), V(0.06, 0.042, -0.36), V(0.085, 0.0, -0.405), V(0.06, -0.042, -0.36), V(0.02, -0.07, -0.20), V(-0.02, -0.076, -0.06)]
    J.add("skin", etube_bm(jaw, [0.02, 0.019, 0.017, 0.016, 0.017, 0.019, 0.02], per=6, segs=8, ref=(1, 0, 0)), 0)
    J.add("dark", blob(V(0.03, 0.0, -0.20), 1.0, scale=(0.05, 0.062, 0.1)), 0)
    for k in range(9):
        t = (k - 4) / 4.0
        y = t * 0.032
        spike(J, "bone", V(0.075 - 0.012 * t * t, y, -0.385 + 0.02 * abs(t)), V(0.076 - 0.012 * t * t, y, -0.335 + 0.02 * abs(t)), 0.0046)
    for k in range(5):
        for sy in (1, -1):
            z = -0.24 - k * 0.026
            spike(J, "bone", V(0.045 + k * 0.004, sy * (0.06 - k * 0.006), z), V(0.04 + k * 0.004, sy * (0.045 - k * 0.006), z + 0.022), 0.0042)
    # legs: human built but too long and thin, one trailing in push-off
    def span(a, b, ts):
        return [a.lerp(b, t) for t in ts]

    for s, knee, ankle, toe, ball in (
        (1, V(0.24, 0.13, 0.63), V(0.06, 0.13, 0.10), V(0.40, 0.13, 0.015), V(0.30, 0.13, 0.04)),
        (-1, V(0.10, -0.13, 0.66), V(-0.36, -0.12, 0.17), V(-0.14, -0.12, 0.012), V(-0.20, -0.12, 0.04)),
    ):
        hip = V(-0.05, 0.10 * s, 1.08)
        keys = [hip, hip.lerp(knee, 0.5), knee] + span(knee, ankle, (0.28, 0.65)) + [ankle]
        limb(mk, "skin", keys, [0.07, 0.06, 0.04, 0.047, 0.034, 0.023], [0.075, 0.062, 0.042, 0.05, 0.034, 0.023], per=6, segs=10)
        mk.add("skin", blob(knee, 0.036, scale=(1.1, 1, 1.15)), 0)
        limb(mk, "skin", [ankle, ball, toe], [0.024, 0.026, 0.012], [0.024, 0.02, 0.008], per=4, segs=8)
        spike(mk, "bone", toe, toe + V(0.05, 0, -0.004), 0.007)
    # arms to the shins; the left reaches out, fingers spread, the right hangs
    shL, shR = V(0.46, 0.20, 1.80), V(0.46, -0.20, 1.76)
    elL, wrL = V(0.64, 0.31, 1.42), V(1.02, 0.25, 1.28)
    elR, wrR = V(0.42, -0.29, 1.30), V(0.55, -0.27, 0.78)
    for sh, el, wr in ((shL, elL, wrL), (shR, elR, wrR)):
        keys = [sh, sh.lerp(el, 0.5), el] + span(el, wr, (0.3, 0.7)) + [wr]
        limb(mk, "skin", keys, [0.05, 0.043, 0.027, 0.033, 0.026, 0.019], [0.055, 0.042, 0.027, 0.036, 0.026, 0.017], per=6, segs=8)
    hand(mk, "skin", wrL, V(0.9, 0, -0.35), V(0, 1, 0), V(0, 0, -1), spread=0.4, flen=0.38, curl=0.32, claw_key="bone")
    hand(mk, "skin", wrR, V(0.15, 0, -1), V(0, 1, 0), V(1, 0, 0), spread=0.25, flen=0.38, curl=0.3, claw_key="bone")
    return [mk.build(M, "stooper")]


if __name__ == "__main__":
    kit.main(build, "a")

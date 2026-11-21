"""Checks the harbour city's generated layout without Blender or Godot: plain Python 3, standard library only.

  python3 tools/blender/harbour_check.py [path to harbour_layout.gd]

It reads the layout the generator wrote, rasterises it at 1 m with the car's clearance (a 1.1 m circle:
the car is 4 x 2 m), and reports:
  - every road's width against the quarter's (14 m), and the highway's carriageway
  - every roadblock's gap, the toll lanes, the chicanes and the truck stop's squeeze, against the 4 m
    the quarter's burned-bus chicane leaves, and whether the car's circle passes each
  - every place: inside the arena, clear of colliders with the car's clearance, reachable from the highway's start
  - each planned mission leg and the highway, by road (a shortest route on the grid, then pulled straight
    where the line is clear), against the least the option allows, and which roadblocks, bridges and set
    pieces the route crosses
Exit status is 1 if a hard check fails (a road narrower than the quarter's, a squeeze under 4 m, a place
blocked or unreachable, a leg under its minimum), 0 otherwise.
"""
import sys, os, json, math, heapq

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DEFAULT = os.path.join(ROOT, "assets", "cities", "harbour_layout.gd")
CAR_R = 1.1          # the car's circle for route finding: half its width plus a little
CELL = 1.0
QUARTER_ROAD = 14.0  # city.py's RW
QUARTER_CHICANE = 4.0


def load(path):
    s = open(path).read()
    return json.loads(s[s.index("const DATA := ") + len("const DATA := "):])


class Grid:
    def __init__(self, lay, r=CAR_R, skip_kinds=()):
        a = lay["arena"]
        self.left, self.bottom = a["left"], a["bottom"]
        self.w = int(math.ceil((a["right"] - a["left"]) / CELL))
        self.h = int(math.ceil((a["top"] - a["bottom"]) / CELL))
        self.solid = bytearray(self.w * self.h)
        self.r = r
        for b in lay["boxes"]:
            if b["kind"] in skip_kinds:
                continue
            self._rect(b["x0"] - r, b["y0"] - r, b["x1"] + r, b["y1"] + r)
        for p in lay["posts"]:
            rr = p["r"] + r
            x0, x1 = int((p["x"] - rr - self.left) / CELL), int((p["x"] + rr - self.left) / CELL) + 1
            y0, y1 = int((p["y"] - rr - self.bottom) / CELL), int((p["y"] + rr - self.bottom) / CELL) + 1
            for iy in range(max(y0, 0), min(y1, self.h)):
                for ix in range(max(x0, 0), min(x1, self.w)):
                    cx, cy = self.left + (ix + 0.5) * CELL, self.bottom + (iy + 0.5) * CELL
                    if (cx - p["x"]) ** 2 + (cy - p["y"]) ** 2 < rr * rr:
                        self.solid[iy * self.w + ix] = 1
        # the arena's walls hold the car's centre r in
        self._rect(a["left"] - 50, a["bottom"] - 50, a["left"] + r, a["top"] + 50)
        self._rect(a["right"] - r, a["bottom"] - 50, a["right"] + 50, a["top"] + 50)
        self._rect(a["left"] - 50, a["bottom"] - 50, a["right"] + 50, a["bottom"] + r)
        self._rect(a["left"] - 50, a["top"] - r, a["right"] + 50, a["top"] + 50)

    def _rect(self, x0, y0, x1, y1):
        # a cell is solid when its centre is inside the rectangle
        ix0 = max(int(math.ceil((x0 - self.left) / CELL - 0.5)), 0)
        ix1 = min(int(math.floor((x1 - self.left) / CELL - 0.5)), self.w - 1)
        iy0 = max(int(math.ceil((y0 - self.bottom) / CELL - 0.5)), 0)
        iy1 = min(int(math.floor((y1 - self.bottom) / CELL - 0.5)), self.h - 1)
        for iy in range(iy0, iy1 + 1):
            base = iy * self.w
            for ix in range(ix0, ix1 + 1):
                self.solid[base + ix] = 1

    def cell(self, x, y):
        return int((x - self.left) / CELL), int((y - self.bottom) / CELL)

    def centre(self, ix, iy):
        return self.left + (ix + 0.5) * CELL, self.bottom + (iy + 0.5) * CELL

    def free(self, ix, iy):
        return 0 <= ix < self.w and 0 <= iy < self.h and not self.solid[iy * self.w + ix]

    def nearest_free(self, x, y, maxr=6):
        ix, iy = self.cell(x, y)
        if self.free(ix, iy):
            return ix, iy
        for r in range(1, maxr + 1):
            for dx in range(-r, r + 1):
                for dy in range(-r, r + 1):
                    if max(abs(dx), abs(dy)) == r and self.free(ix + dx, iy + dy):
                        return ix + dx, iy + dy
        return None

    def line_free(self, a, b):
        (x0, y0), (x1, y1) = a, b
        n = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for k in range(n + 1):
            t = k / n
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            ix, iy = self.cell(x, y)
            if not self.free(ix, iy):
                return False
        return True

    def astar(self, a, b):
        w = self.w
        sa, sb = a[1] * w + a[0], b[1] * w + b[0]
        gx, gy = b
        dist = {sa: 0.0}
        prev = {}
        heap = [(0.0, sa)]
        SQ = 1.41421356
        nbrs = [(1, 0, 1.0), (-1, 0, 1.0), (0, 1, 1.0), (0, -1, 1.0), (1, 1, SQ), (1, -1, SQ), (-1, 1, SQ), (-1, -1, SQ)]
        solid = self.solid
        h = self.h
        while heap:
            f, cur = heapq.heappop(heap)
            if cur == sb:
                break
            d = dist[cur]
            cx, cy = cur % w, cur // w
            ddx0, ddy0 = abs(gx - cx), abs(gy - cy)
            if f > d + (ddx0 + ddy0) + (SQ - 2) * min(ddx0, ddy0) + 1e-6:
                continue
            for dx, dy, c in nbrs:
                nx, ny = cx + dx, cy + dy
                if nx < 0 or ny < 0 or nx >= w or ny >= h:
                    continue
                ni = ny * w + nx
                if solid[ni]:
                    continue
                if dx and dy and (solid[cy * w + nx] or solid[ny * w + cx]):
                    continue
                nd = d + c
                if nd < dist.get(ni, 1e18):
                    dist[ni] = nd
                    prev[ni] = cur
                    ddx, ddy = abs(gx - nx), abs(gy - ny)
                    hh = (ddx + ddy) + (SQ - 2) * min(ddx, ddy)
                    heapq.heappush(heap, (nd + hh, ni))
        if sb not in prev and sa != sb:
            return None
        path, cur = [], sb
        while cur != sa:
            path.append((cur % w, cur // w))
            cur = prev[cur]
        path.append(a)
        path.reverse()
        return path

    def pull(self, path):
        """Pull a cell path straight wherever the line between two of its points is clear."""
        pts = [self.centre(*c) for c in path]
        out = [pts[0]]
        i = 0
        while i < len(pts) - 1:
            j = min(len(pts) - 1, i + 120)
            while j > i + 1 and not self.line_free(pts[i], pts[j]):
                j -= 1
            out.append(pts[j])
            i = j
        return out


def plen(pts):
    return sum(math.hypot(pts[k + 1][0] - pts[k][0], pts[k + 1][1] - pts[k][1]) for k in range(len(pts) - 1))


def near_path(pts, x, y, d):
    for k in range(len(pts) - 1):
        (ax, ay), (bx, by) = pts[k], pts[k + 1]
        vx, vy = bx - ax, by - ay
        L2 = vx * vx + vy * vy
        t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((x - ax) * vx + (y - ay) * vy) / L2))
        if math.hypot(ax + vx * t - x, ay + vy * t - y) <= d:
            return True
    return False


def main(path):
    lay = load(path)
    fails = []
    print("layout:", os.path.relpath(path, ROOT))
    a = lay["arena"]
    print("arena: x %.0f..%.0f, y %.0f..%.0f (%.0f x %.0f m); city part %.0f x %.0f m, %d blocks; highway %.0f m" % (
        a["left"], a["right"], a["bottom"], a["top"], a["right"] - a["left"], a["top"] - a["bottom"],
        lay["size"]["blocks_x"] * lay["size"]["street_x"] + lay["size"]["road_width"], lay["size"]["blocks_y"] * lay["size"]["street_y"] + lay["size"]["road_width"],
        len(lay["blocks"]), lay["size"]["highway_length"]))
    print("counts: %d boxes, %d posts, %d lights, %d wrecks, %d spawns, %d roadblocks, %d bridges, %d ambush spots" % (
        len(lay["boxes"]), len(lay["posts"]), len(lay["lights"]), len(lay["wrecks"]), len(lay["creature_spawns"]), len(lay["roadblocks"]), len(lay["bridges"]), len(lay["ambush_spots"])))

    # ---- road widths
    print("\nroads (the quarter's are %.0f m wide):" % QUARTER_ROAD)
    narrowest = 1e9
    for r in lay["roads"]:
        w = r.get("carriageway_width", r["width"])
        narrowest = min(narrowest, w)
        if w < QUARTER_ROAD - 1e-6:
            fails.append("road %s at %s is %.1f m" % (r["axis"], r["at"], w))
    kinds = {}
    for r in lay["roads"]:
        kinds.setdefault(r["kind"], []).append(r.get("carriageway_width", r["width"]))
    for k, v in kinds.items():
        print("  %-8s %d roads, width %.1f m%s" % (k, len(v), min(v), " per carriageway" if k == "highway" else ""))
    for b in lay["bridges"]:
        if b["width"] < QUARTER_ROAD - 1e-6:
            fails.append("bridge %s is %.1f m wide" % (b["id"], b["width"]))
    print("  narrowest road: %.1f m" % narrowest)

    # ---- squeezes
    g = Grid(lay)
    print("\nsqueezes (the quarter's chicane is %.1f m; the car's circle is %.1f m across):" % (QUARTER_CHICANE, 2 * CAR_R))
    gaps = []
    for rb in lay["roadblocks"]:
        if rb["gap"]:
            gaps.append((rb["id"], rb["gap"]["width"], rb["axis"], rb["at"], rb["pos"], (rb["gap"]["lo"] + rb["gap"]["hi"]) / 2))
    hw = lay["highway"]
    ts = hw["truck_stop"]["squeeze"]
    gaps.append(("truck_stop_squeeze", ts["width"], "y", ts["x"], ts["x"], (ts["y0"] + ts["y1"]) / 2))
    wg = hw["truck_stop"]["wide_gap"]
    gaps.append(("truck_stop_wide_gap", wg["width"], "y", wg["x"], wg["x"], (wg["y0"] + wg["y1"]) / 2))
    cp = hw["checkpoint"]
    for k, (gx, gy) in enumerate(((cp["x0"] + 9.5, 13.0), (cp["x0"] + 23.5, 3.0), (cp["x0"] + 9.5, -3.0), (cp["x0"] + 23.5, -13.0))):
        gaps.append(("checkpoint_chicane_%d" % k, cp["chicane_gap"], "y", gx, gx, gy))
    tp = hw["toll_plaza"]
    for k, gy in enumerate((3.0, 8.0, 13.0, -3.0, -8.0, -13.0)):
        gaps.append(("toll_lane_%d" % k, tp["lane_gap"], "y", (tp["x0"] + tp["x1"]) / 2, (tp["x0"] + tp["x1"]) / 2, gy))
    worst = 1e9
    for (gid, width, axis, at, pos, c) in gaps:
        worst = min(worst, width)
        # the car's circle passes: the line through the gap, 6 m each side, is clear on the grid
        if axis == "y":
            p0, p1 = (pos - 6.0, c), (pos + 6.0, c)
        else:
            p0, p1 = (c, pos - 6.0), (c, pos + 6.0)
        # the toll lanes and truck stop run along different axes than roadblocks'
        if gid.startswith("toll_lane") or gid.startswith("checkpoint"):
            p0, p1 = (pos - 2.0, c), (pos + 2.0, c)
        if gid.startswith("truck_stop"):
            p0, p1 = (pos - 6.0, c), (pos + 6.0, c)
        ok = g.line_free(p0, p1)
        if width < QUARTER_CHICANE - 1e-6:
            fails.append("%s is %.2f m" % (gid, width))
        if not ok:
            fails.append("the car's circle does not pass %s (%.1f m)" % (gid, width))
        print("  %-26s %.2f m  %s" % (gid, width, "passes" if ok else "BLOCKED"))
    print("  narrowest gap: %.2f m over %d squeezes" % (worst, len(gaps)))
    closed = [rb["id"] for rb in lay["roadblocks"] if rb["kind"] == "closed"]
    print("  closed roadblocks (shut the road): %s" % ", ".join(closed))

    # ---- places
    print("\nplaces:")
    pl = lay["places"]
    cells = {}
    for name, p in pl.items():
        inside = a["left"] < p["x"] < a["right"] and a["bottom"] < p["y"] < a["top"]
        c = g.cell(p["x"], p["y"])
        free = inside and g.free(*c)
        if not free:
            fails.append("place %s is blocked or outside (%.1f, %.1f)" % (name, p["x"], p["y"]))
        cells[name] = c
        print("  %-18s (%7.1f, %6.1f)  %s" % (name, p["x"], p["y"], "clear" if free else "BLOCKED"))
    start = cells["highway_start"]

    # ---- legs
    print("\nlegs by road (shortest route on a 1 m grid with the car's clearance, pulled straight; min is the option's):")
    rbpos = [(rb["id"], rb["pos"] if rb["axis"] == "y" else rb["at"], rb["at"] if rb["axis"] == "y" else rb["pos"]) for rb in lay["roadblocks"]]
    bridges = lay["bridges"]
    legs = []
    for leg in lay["planned_legs"]:
        pa, pb = pl[leg["a"]], pl[leg["b"]]
        pth = g.astar(cells[leg["a"]], cells[leg["b"]])
        if pth is None:
            fails.append("leg %s: no route" % leg["id"])
            print("  %-20s NO ROUTE" % leg["id"])
            continue
        pts = g.pull(pth)
        L = plen(pts)
        straight = math.hypot(pa["x"] - pb["x"], pa["y"] - pb["y"])
        crossed = [i for (i, x, y) in rbpos if near_path(pts, x, y, 9.0)]
        br = [b["id"] for b in bridges if near_path(pts, b["x"], b["y"], 6.0)]
        sets = []
        for nm, (x, y) in (("toll_plaza", ((hw["toll_plaza"]["x0"] + hw["toll_plaza"]["x1"]) / 2, 8.0)), ("jam", ((hw["jam"]["x0"] + hw["jam"]["x1"]) / 2, 8.0)), ("fallen_overpass", (hw["fallen_overpass"]["x0"] + 8.0, 28.0)), ("checkpoint_chicane", (cp["x0"] + 16.0, 8.0))):
            if near_path(pts, x, y, 14.0 if nm != "jam" else 60.0):
                sets.append(nm)
        ok = L >= leg["min_by_road"]
        if not ok:
            fails.append("leg %s is %.0f m, under %.0f" % (leg["id"], L, leg["min_by_road"]))
        legs.append((leg["id"], L))
        print("  %-20s %7.0f m  (min %5.0f, straight %5.0f, route %.2fx)  %s  at 60 km/h %3.0f s, 90 km/h %3.0f s%s%s%s" % (
            leg["id"], L, leg["min_by_road"], straight, L / max(straight, 1), "ok " if ok else "LOW", L / 16.67, L / 25.0,
            ("  roadblocks: " + ", ".join(crossed)) if crossed else "", ("  bridges: " + ", ".join(br)) if br else "", ("  set pieces: " + ", ".join(sets)) if sets else ""))
        if leg["id"] != "long_road" and not crossed and not br:
            fails.append("leg %s crosses no roadblock or bridge" % leg["id"])
    # the highway's own length by road
    hw_start = (hw["toll_plaza"]["x1"], 0)
    print("\nthe highway: %.0f m long (city edge x=%.0f to the far wall x=%.0f); start to the city edge by road %.0f m" % (
        lay["size"]["highway_length"], a["right"] - 11.0 - lay["size"]["highway_length"], a["right"] - 11.0,
        next((L for (i, L) in legs if i == "long_road"), 0)))
    # the route must go through the truck stop: the overpass shuts both carriageways
    pth = g.astar(g.nearest_free(pl["highway_start"]["x"], pl["highway_start"]["y"]), g.nearest_free(pl["convoy_call"]["x"], pl["convoy_call"]["y"]))
    if pth:
        pts = g.pull(pth)
        ov = hw["fallen_overpass"]
        through = [p for p in pts if abs(p[0] - (ov["x0"] + ov["x1"]) / 2) < 10 and p[1] > ov["y1"]]
        print("the route passes the fallen overpass through the truck stop: %s" % ("yes" if through else "NO"))
        if not through:
            fails.append("the route does not pass through the truck stop")
    # every place reachable from the highway's start
    for name, c in cells.items():
        if g.astar(start, c) is None:
            fails.append("place %s is not reachable from the highway's start" % name)

    # spawns and ambush spots stand clear of colliders, inside the arena
    def clear_of(x, y, pad=0.5):
        for b in lay["boxes"]:
            if b["x0"] - pad < x < b["x1"] + pad and b["y0"] - pad < y < b["y1"] + pad:
                return False
        for p in lay["posts"]:
            if math.hypot(p["x"] - x, p["y"] - y) < p["r"] + pad:
                return False
        return a["left"] < x < a["right"] and a["bottom"] < y < a["top"]
    bad_sp = [s for s in lay["creature_spawns"] if not clear_of(s["x"], s["y"])]
    bad_am = [s["id"] for s in lay["ambush_spots"] if not clear_of(s["x"], s["y"])]
    print("creature spawns: %d, %d inside a collider; ambush spots: %d, %d inside a collider %s" % (len(lay["creature_spawns"]), len(bad_sp), len(lay["ambush_spots"]), len(bad_am), bad_am))
    if bad_sp or bad_am:
        fails.append("%d spawns and %d ambush spots stand inside colliders" % (len(bad_sp), len(bad_am)))

    # the lift bridge down: the colliders that close it taken out, the way to the gate runs over it and only over it
    gd = lay["gate"]
    g2 = Grid(lay, skip_kinds=("lift_up",))
    gate_cell = g2.nearest_free(gd["x"] + 4.0, gd["y"])
    cc = g2.nearest_free(pl["control_house"]["x"], pl["control_house"]["y"])
    lb = next(b for b in lay["bridges"] if b["id"] == "lift_bridge")
    p1 = g2.astar(cc, gate_cell)
    west = g2.astar(g2.nearest_free(pl["fuel_depot"]["x"], pl["fuel_depot"]["y"]), gate_cell)
    if p1 is None or west is None:
        fails.append("with the lift bridge down there is no way to the gate")
        print("lift bridge down: NO WAY TO THE GATE")
    else:
        q1, q2 = g2.pull(p1), g2.pull(west)
        print("lift bridge down: control house to the gate %.0f m; from the west bank's depot %.0f m, over the bridge: %s" % (plen(q1), plen(q2), "yes" if near_path(q2, lb["x"], lb["y"], 8.0) else "NO"))
        if not near_path(q2, lb["x"], lb["y"], 8.0):
            fails.append("the west bank reaches the gate without the lift bridge")
    shut = g.astar(cc, g.nearest_free(gd["x"] + 4.0, gd["y"]))
    print("lift bridge up: the gate is %s from the control house" % ("REACHABLE" if shut else "unreachable"))
    if shut:
        fails.append("the gate is reachable with the lift bridge up")
    print()
    if fails:
        print("FAILED:")
        for f in fails:
            print("  -", f)
        return 1
    print("all hard checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else DEFAULT))

"""Shared kit for the Hollow Hours creature look concepts (Blender 5.3, headless, no Blender MCP).

A concept file defines build() that resets the scene, models a creature in a static pose (feet on z=0,
facing +X, nose toward +X) and returns its top-level objects; then calls kit.main(build, "a").
Three shots per concept, written to $CREATURE_OUT (default: the system temp folder):
  turn  : front, three-quarter and side views on a neutral dark ground (<name>-turnaround.png)
  scene : the creature 15 m ahead of the Bruiser in its headlights, wet road, fog (<name>-scene.png)
  sil   : the creature backlit in fog at 30 m (<name>-silhouette.png)

Run:  Blender --background --python-exit-code 1 --python tools/blender/concepts/a.py -- [turn] [scene] [sil]
"""
import sys, os, math, subprocess, tempfile, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import bpy, bmesh
from mathutils import Vector, Matrix
from rk import reset, mat, make_obj, sphere_bm, hexcol, join, add_mod, bake, cube_bm

OUT = os.environ.get("CREATURE_OUT", os.path.join(tempfile.gettempdir(), "hollow-hours-creature"))
CAR = os.path.join(HERE, "..", "..", "..", "assets", "models", "bruiser.glb")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []



# ------------------------------------------------------------------ materials

def skin_material(name, base, rough=0.45, coat=0.5, coat_rough=0.1, mottle="#5a5348", mottle_amt=0.5, scale=9.0, sss=0.0):
    """Wet skin: base colour mottled by noise, a clear coat for the wet sheen."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Coat Weight"].default_value = coat
    bsdf.inputs["Coat Roughness"].default_value = coat_rough
    if sss:
        try:
            bsdf.inputs["Subsurface Weight"].default_value = sss
            bsdf.inputs["Subsurface Radius"].default_value = (0.6, 0.25, 0.2)
        except Exception:
            pass
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = scale
    nz.inputs["Detail"].default_value = 6.0
    nz.inputs["Roughness"].default_value = 0.6
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[0].color = hexcol(base)
    ramp.color_ramp.elements[1].color = hexcol(mottle)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    nz2 = nt.nodes.new("ShaderNodeTexNoise")
    nz2.inputs["Scale"].default_value = 60.0
    nz2.inputs["Detail"].default_value = 3.0
    nt.links.new(tc.outputs["Object"], nz2.inputs["Vector"])
    nt.links.new(nz2.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def std_mats(skin="#9aa0a2", mottle="#6b655a", bone="#cfc8b2", eye="#e9e6b4"):
    return {
        "skin": skin_material("skin", skin, mottle=mottle),
        "bone": mat("bone", bone, rough=0.5, coat=0.2),
        "eye": mat("eye", eye, rough=0.25, emit=eye, emit_strength=2.5),
        "dark": mat("dark", "#120a0b", rough=0.6),
        "cloth": mat("cloth", "#2b2a27", rough=0.9),
    }


# ------------------------------------------------------------------ framing helpers

def bounds(objs):
    """World bounding box (min, max) of the evaluated meshes under objs."""
    dg = bpy.context.evaluated_depsgraph_get()
    mn = Vector((1e9,) * 3)
    mx = Vector((-1e9,) * 3)
    todo = []

    def walk(o):
        todo.append(o)
        for c in o.children:
            walk(c)

    for o in objs:
        walk(o)
    for o in todo:
        if o.type != "MESH":
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ev.matrix_world
        for v in me.vertices:
            w = mw @ v.co
            mn = Vector(min(a, b) for a, b in zip(mn, w))
            mx = Vector(max(a, b) for a, b in zip(mx, w))
        ev.to_mesh_clear()
    return mn, mx


def place(objs, loc, yaw=0.0):
    """Parent the creature's top-level objects to an empty at loc, turned yaw about Z; feet on loc.z."""
    bpy.context.view_layer.update()
    mn, mx = bounds(objs)
    root = bpy.data.objects.new("creature_root", None)
    bpy.context.scene.collection.objects.link(root)
    root.location = (loc[0], loc[1], loc[2] - mn.z)
    root.rotation_euler = (0, 0, yaw)
    for o in objs:
        o.parent = root
    bpy.context.view_layer.update()
    return root, (mn, mx)


# ------------------------------------------------------------------ scenes

def engine():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    e = sc.eevee
    for k, v in (("taa_render_samples", 48), ("use_raytracing", True), ("volumetric_samples", 96), ("volumetric_tile_size", "2"), ("volumetric_end", 120.0), ("use_volumetric_shadows", True), ("volumetric_shadow_samples", 32)):
        try:
            setattr(e, k, v)
        except Exception as ex:
            print("eevee setting skipped", k, ex)
    sc.render.image_settings.file_format = "PNG"
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Base Contrast"
    except Exception:
        sc.view_settings.view_transform = "Standard"
    return sc


def set_world(color, strength, fog=0.0, fog_color="#9fb0bb", aniso=0.5):
    sc = bpy.context.scene
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes["Background"]
    bg.inputs["Color"].default_value = hexcol(color)
    bg.inputs["Strength"].default_value = strength
    out = nt.nodes["World Output"]
    if fog > 0:
        vs = nt.nodes.new("ShaderNodeVolumeScatter")
        vs.inputs["Density"].default_value = fog
        vs.inputs["Color"].default_value = hexcol(fog_color)
        vs.inputs["Anisotropy"].default_value = aniso
        nt.links.new(vs.outputs["Volume"], out.inputs["Volume"])
    sc.world = w


def road(length=240, width=14, lane_y=0.0):
    """Wet asphalt: dark, patchy roughness so puddles mirror the lights; dashed centre line."""
    m = bpy.data.materials.new("road")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = hexcol("#1c1d1f")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (0.35, 0.8, 1.0)
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 1.6
    nz.inputs["Detail"].default_value = 5.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.45
    ramp.color_ramp.elements[0].color = (0.04, 0.04, 0.04, 1)
    ramp.color_ramp.elements[1].position = 0.62
    ramp.color_ramp.elements[1].color = (0.45, 0.45, 0.45, 1)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Roughness"])
    nz2 = nt.nodes.new("ShaderNodeTexNoise")
    nz2.inputs["Scale"].default_value = 90.0
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.15
    nt.links.new(tc.outputs["Object"], nz2.inputs["Vector"])
    nt.links.new(nz2.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * length, v.co.y * width, 0))
    ob = make_obj("road", bm, m)
    ob.location = (length * 0.3, lane_y, 0)
    line = mat("line", "#b9b49a", rough=0.5)
    for k in range(-6, 24):
        bl = cube_bm((2.4, 0.14, 0.01), loc=(k * 8.0, lane_y, 0.006))
        make_obj("dash%d" % k, bl, line)


def import_car(loc, yaw=0.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=CAR)
    new = [o for o in bpy.data.objects if o not in before]
    car = [o for o in new if o.name == "car"][0]
    car.location = loc
    car.rotation_euler = (0, 0, yaw)
    # taillights and headlights glow a little
    for m in bpy.data.materials:
        if m.name.startswith("taillight") or m.name.startswith("headlight"):
            b = m.node_tree.nodes.get("Principled BSDF")
            if b:
                col = (1.0, 0.05, 0.03, 1) if m.name.startswith("taillight") else (1.0, 0.95, 0.8, 1)
                b.inputs["Emission Color"].default_value = col
                b.inputs["Emission Strength"].default_value = 4.0 if m.name.startswith("taillight") else 25.0
    return car


def spot(name, loc, target, power, size_deg=50, blend=0.6, color=(1, 0.93, 0.8), vol=1.0):
    ld = bpy.data.lights.new(name, "SPOT")
    ld.energy = power
    ld.spot_size = math.radians(size_deg)
    ld.spot_blend = blend
    ld.color = color
    ld.shadow_soft_size = 0.08
    try:
        ld.volume_factor = vol
    except Exception:
        pass
    o = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return o


def area(name, loc, target, power, size=2.0, color=(1, 1, 1), shape="RECTANGLE"):
    ld = bpy.data.lights.new(name, "AREA")
    ld.energy = power
    ld.size = size
    ld.shape = "SQUARE"
    ld.color = color
    ld.volume_factor = 0.0
    o = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return o


def moon(name, direction, strength, color=(0.55, 0.66, 0.95)):
    ld = bpy.data.lights.new(name, "SUN")
    ld.energy = strength
    ld.color = color
    ld.volume_factor = 0.0
    o = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(o)
    o.rotation_euler = Vector(direction).to_track_quat("-Z", "Y").to_euler()
    return o


def camera(loc, target, lens=35, ortho=None):
    cd = bpy.data.cameras.new("cam")
    if ortho:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho
    else:
        cd.lens = lens
    co = bpy.data.objects.new("cam", cd)
    bpy.context.scene.collection.objects.link(co)
    co.location = loc
    co.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = co
    return co


def render(path, res):
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)


# ------------------------------------------------------------------ the three shots

def shot_turnaround(build, name):
    """Front, three-quarter and side on a neutral dark ground, orthographic, with a 1.8 m bar for scale."""
    tmp = []
    views = (("front", 0.0), ("threeq", 40.0), ("side", 90.0))
    for vname, ang in views:
        objs = build()
        sc = engine()
        sc.eevee.taa_render_samples = 64
        root, (mn, mx) = place(objs, (0, 0, 0), 0.0)
        mn, mx = bounds([root])
        h = mx.z - mn.z
        length = mx.x - mn.x
        span = max(h * 1.3, length * 1.22, 2.4)
        set_world("#15171a", 0.6)
        floor = bmesh.new()
        bmesh.ops.create_grid(floor, x_segments=1, y_segments=1, size=30)
        make_obj("floor", floor, mat("floor", "#0e0f11", rough=0.5), smooth=False)
        # a 1.8 m bar standing beside the creature
        make_obj("bar", cube_bm((0.04, 0.04, 1.8)), mat("bar", "#6d727a", rough=0.6, emit="#6d727a", emit_strength=0.8))
        bar = bpy.data.objects["bar"]
        a = math.radians(ang)
        cx, cy = (mn.x + mx.x) / 2, 0.0
        look = Vector((cx, cy, h * 0.5))
        d = Vector((math.cos(a), math.sin(a), 0))  # camera direction from the creature (front view looks from +X)
        dist = 14.0
        co = camera(look + d * dist + Vector((0, 0, 0.0)), look, ortho=span)
        # bar sits to the camera's left, at the edge of the frame
        left = Vector((-d.y, d.x, 0))
        bar.location = look - left * (span * 0.47)
        bar.location.z = 0.9
        key = area("key", look + d * 5 + left * -4 + Vector((0, 0, 6)), look, 900, size=4, color=(1.0, 0.95, 0.88))
        rim = area("rim", look - d * 5 + left * 4 + Vector((0, 0, 4)), look, 1300, size=3, color=(0.65, 0.78, 1.0))
        fill = area("fill", look + d * 4 + left * 5 + Vector((0, 0, 1.5)), look, 150, size=4, color=(0.8, 0.85, 1.0))
        p = os.path.join(OUT, "_%s_%s.png" % (name, vname))
        render(p, (900, 900))
        tmp.append(p)
    out = os.path.join(OUT, "%s-turnaround.png" % name)
    subprocess.run([shutil.which("magick") or "magick"] + tmp + ["+append", out], check=True)
    for p in tmp:
        os.remove(p)
    print("TURNAROUND", out)


def shot_scene(build, name, dist=15.0, res=(2000, 1125), cam_lens=42):
    """The creature `dist` metres in front of the Bruiser's grille, in the headlights, fog and rain-wet road."""
    objs = build()
    sc = engine()
    sc.eevee.taa_render_samples = 64
    set_world("#2c3744", 0.45, fog=0.03, fog_color="#a9b8c4")
    road()
    nose = 2.32
    car = import_car((0, -1.9, 0), 0.0)
    cx = nose + dist
    root, _ = place(objs, (cx, -1.1, 0), math.pi - 0.55)
    for sy in (-0.62, 0.62):
        spot("hl", (nose - 0.05, -1.9 + sy, 0.72), (cx, -1.6, 0.9), 30000, size_deg=44, blend=0.7)
    camera((-13.0, 1.4, 2.9), (cx * 0.7, -1.3, 0.55), lens=cam_lens)
    moon("moon", (-0.5, 0.55, -0.45), 1.2)
    area("kicker", (-9, 5.5, 6.5), (0, -1.9, 1.0), 5000, size=5, color=(0.62, 0.72, 1.0))
    render(os.path.join(OUT, "%s-scene.png" % name), res)


def shot_silhouette(build, name, dist=30.0, res=(1600, 900), lens=75, phi_deg=38.0):
    """The creature from `dist` metres, backlit by a lamp behind it through fog, mostly a shape."""
    objs = build()
    sc = engine()
    sc.eevee.taa_render_samples = 64
    set_world("#1d2630", 0.3, fog=0.035, fog_color="#8fa0ae")
    road()
    root, (mn, mx) = place(objs, (0, -0.8, 0), 0.0)
    mn, mx = bounds([root])
    h = mx.z - mn.z
    phi = math.radians(phi_deg)
    d = Vector((math.cos(phi), math.sin(phi), 0))
    base = Vector((0, -0.8, 0))
    camera(base + d * dist + Vector((0, 0, 1.3)), base + Vector((0, 0, h * 0.5 + 0.1)), lens=lens)
    back = base - d * 6.0
    spot("lamp", back + Vector((0, 0, h * 0.6)), base + d * dist + Vector((0, 0, 1.3)), 4500, size_deg=24, blend=0.8, color=(1, 0.9, 0.72))
    render(os.path.join(OUT, "%s-silhouette.png" % name), res)


def shot_dev(build, name, spec):
    """A close studio look for iterating: DEV="x,y,z,tx,ty,tz,lens" in the creature's own coordinates (feet on z=0)."""
    objs = build()
    sc = engine()
    sc.eevee.taa_render_samples = 48
    v = [float(x) for x in spec.split(",")]
    root, _ = place(objs, (0, 0, 0), 0.0)
    set_world("#15171a", 0.5)
    fl = bmesh.new()
    bmesh.ops.create_grid(fl, x_segments=1, y_segments=1, size=30)
    make_obj("floor", fl, mat("floor", "#0e0f11", rough=0.5), smooth=False)
    tgt = Vector(v[3:6])
    loc = Vector(v[0:3])
    camera(loc, tgt, lens=v[6])
    d = (loc - tgt).normalized()
    left = Vector((-d.y, d.x, 0))
    area("key", tgt + d * 3 - left * 2 + Vector((0, 0, 2.5)), tgt, 500, size=3, color=(1.0, 0.95, 0.88))
    area("rim", tgt - d * 3 + left * 2 + Vector((0, 0, 2)), tgt, 700, size=3, color=(0.65, 0.78, 1.0))
    area("fill", tgt + d * 2 + left * 3, tgt, 120, size=3, color=(0.8, 0.85, 1.0))
    render(os.path.join(OUT, "_dev-%s.png" % name), (1200, 900))


def main(build, name):
    os.makedirs(OUT, exist_ok=True)
    if os.environ.get("DEV"):
        return shot_dev(build, name, os.environ["DEV"])
    todo = [a for a in ARGS if a in ("turn", "scene", "sil")] or ["turn", "scene", "sil"]
    if "turn" in todo:
        shot_turnaround(build, name)
    if "scene" in todo:
        shot_scene(build, name)
    if "sil" in todo:
        shot_silhouette(build, name)

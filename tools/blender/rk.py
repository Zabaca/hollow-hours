"""Helpers shared by the Blender scripts (Blender 5.3 headless, run inside Blender's Python). Copied from the Roadkill 3D demo, trimmed.
Coordinates: Blender Z up, +X is the car's forward. The glTF exporter turns that into three.js Y up (Blender y -> glTF -z), and
game (x, y) maps to Blender (x, y), so the city is built straight in game coordinates.
Colours are sRGB hex strings; hexcol() converts to linear.
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix

OUT = os.environ.get("RK_OUT", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models"))
HERE = os.path.dirname(os.path.abspath(__file__))


def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h, a=1.0):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return (lin(r), lin(g), lin(b), a)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return bpy.context.scene


def mat(name, hexc, rough=0.55, metal=0.0, emit=None, emit_strength=1.0, coat=0.0, coat_rough=0.1, tex=None, vcol=False, alpha=1.0, emit_tex=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if coat:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = coat_rough
    if emit:
        bsdf.inputs["Emission Color"].default_value = hexcol(emit)
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    if emit_tex:
        et = nt.nodes.new("ShaderNodeTexImage")
        et.image = emit_tex
        nt.links.new(et.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    base = hexcol(hexc)
    if tex or vcol:
        # base colour x texture (greyscale detail) x vertex colour: how a flat colour gets grain and painted-on shading
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs["A"].default_value = base
        src = None
        if tex:
            img = nt.nodes.new("ShaderNodeTexImage")
            img.image = tex
            src = img.outputs["Color"]
            mix.location = (-200, 0)
            nt.links.new(src, mix.inputs["B"])
            last = mix.outputs["Result"]
        else:
            mix.inputs["B"].default_value = (1, 1, 1, 1)
            last = mix.outputs["Result"]
        if vcol:
            ca = nt.nodes.new("ShaderNodeVertexColor")
            ca.layer_name = "Col"
            mix2 = nt.nodes.new("ShaderNodeMix")
            mix2.data_type = "RGBA"
            mix2.blend_type = "MULTIPLY"
            mix2.inputs["Factor"].default_value = 1.0
            nt.links.new(last, mix2.inputs["A"])
            nt.links.new(ca.outputs["Color"], mix2.inputs["B"])
            last = mix2.outputs["Result"]
        nt.links.new(last, bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = base
    return m


def make_obj(name, bm, material, smooth=True, parent=None, loc=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if material:
        me.materials.append(material)
    ob.location = loc
    if parent:
        ob.parent = parent
    return ob


def empty(name, loc=(0, 0, 0), parent=None):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.location = loc
    if parent:
        e.parent = parent
    return e


def cube_bm(size, loc=(0, 0, 0), rot=None, bevel=0.0, seg=3):
    bm = bmesh.new()
    m = Matrix.Translation(loc)
    if rot is not None:
        from mathutils import Euler
        m = m @ Euler(rot).to_matrix().to_4x4()
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    for v in bm.verts:
        l = m.inverted() @ v.co
        v.co = m @ Vector((l.x * size[0], l.y * size[1], l.z * size[2]))
    if bevel > 0:
        b = min(bevel, min(size) * 0.45)
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=b, segments=seg, affect="EDGES")
    return bm


def cyl_bm(r, depth, loc=(0, 0, 0), axis="Z", segs=24, r2=None, bevel=0.0, cap=True):
    bm = bmesh.new()
    rot = {"Z": Matrix.Identity(4), "Y": Matrix.Rotation(math.pi / 2, 4, "X"), "X": Matrix.Rotation(math.pi / 2, 4, "Y")}[axis]
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segs, radius1=r, radius2=r if r2 is None else r2, depth=depth, matrix=Matrix.Translation(loc) @ rot)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=[e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > 0.5], offset=bevel, segments=3, affect="EDGES")
    return bm


def sphere_bm(r, loc=(0, 0, 0), scale=(1, 1, 1), segs=None, rings=None):
    # small spheres (eyes, ears) get fewer segments: they are seen from metres away
    if segs is None:
        segs, rings = (8, 5) if r < 0.08 else (12, 7)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r, matrix=Matrix.Translation(loc))
    c = Vector(loc)
    for v in bm.verts:
        d = v.co - c
        v.co = c + Vector((d.x * scale[0], d.y * scale[1], d.z * scale[2]))
    return bm


def torus_bm(R, r, loc=(0, 0, 0), axis="Z", major=24, minor=8, arc=None):
    bm = bmesh.new()
    pts = []
    n = major if arc is None else max(2, int(major * arc / (2 * math.pi)))
    rot = {"Z": Matrix.Identity(4), "Y": Matrix.Rotation(math.pi / 2, 4, "X"), "X": Matrix.Rotation(math.pi / 2, 4, "Y")}[axis]
    mt = Matrix.Translation(loc) @ rot
    rings = []
    total = 2 * math.pi if arc is None else arc
    steps = n if arc is None else n + 1
    for i in range(steps):
        a = total * i / n
        ring = []
        for j in range(minor):
            b = 2 * math.pi * j / minor
            x = (R + r * math.cos(b)) * math.cos(a)
            y = (R + r * math.cos(b)) * math.sin(a)
            z = r * math.sin(b)
            ring.append(bm.verts.new(mt @ Vector((x, y, z))))
        rings.append(ring)
    last = len(rings) if arc is None else len(rings) - 1
    for i in range(last):
        a, b = rings[i], rings[(i + 1) % len(rings)]
        for j in range(minor):
            bm.faces.new((a[j], a[(j + 1) % minor], b[(j + 1) % minor], b[j]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def tube_bm(points, r, segs=8):
    """A round tube following a polyline (bull bars, roll cages, lamp arms)."""
    bm = bmesh.new()
    rings = []
    P = [Vector(p) for p in points]
    for i, p in enumerate(P):
        if i == 0:
            d = P[1] - P[0]
        elif i == len(P) - 1:
            d = P[i] - P[i - 1]
        else:
            d = (P[i + 1] - P[i - 1])
        d.normalize()
        up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        u = d.cross(up).normalized()
        v = d.cross(u).normalized()
        ring = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            ring.append(bm.verts.new(p + (u * math.cos(a) + v * math.sin(a)) * r))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(segs):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % segs], rings[i + 1][(j + 1) % segs], rings[i + 1][j]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def loft_bm(stations, side=0.78, corner=0.22):
    """A body shell lofted through cross-sections along +X: each station is (x, half_width, z_bottom, z_top). Each section is an
    8-point rounded rectangle; Subdivision smooths the result. Duplicate stations close together keep an edge crisp."""
    bm = bmesh.new()
    rings = []
    for (x, w, z0, z1) in stations:
        h = z1 - z0
        c = h * corner
        pts = [(w * side, z0), (w, z0 + c), (w, z1 - c), (w * side, z1), (-w * side, z1), (-w, z1 - c), (-w, z0 + c), (-w * side, z0)]
        rings.append([bm.verts.new((x, y, z)) for (y, z) in pts])
    n = 8
    for i in range(len(rings) - 1):
        for k in range(n):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % n], rings[i + 1][(k + 1) % n], rings[i + 1][k]))
    bm.faces.new(rings[-1])
    bm.faces.new(rings[0][::-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def add_mod(ob, kind, **kw):
    m = ob.modifiers.new(kind.title(), kind)
    for k, v in kw.items():
        setattr(m, k, v)
    return m


def evaluated_bm(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    return bm


def bake(ob):
    """Apply every modifier so the object is plain geometry."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    for p in me.polygons:
        p.use_smooth = True
    return ob


def join(name, objs, parent=None):
    """Join objects into one with all their material slots (one glTF mesh, a primitive per material)."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    if parent:
        ob.parent = parent
    return ob


def world_uv(ob, scale=6.0, local=None):
    """Triplanar-ish UVs from world position: walls tile by metres, roofs and floors by plan position."""
    me = ob.data
    if "UVMap" not in me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers["UVMap"].data
    corners = ((0, 0), (0, 1), (1, 1), (1, 0))
    for p in me.polygons:
        n = p.normal
        if local and p.material_index in local and len(p.loop_indices) == 4:
            # window panes: 0..1 across the pane, for the page's interior mapping
            for k, li in enumerate(p.loop_indices):
                uv[li].uv = corners[k]
            continue
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if abs(n.z) > 0.7:
                uv[li].uv = (co.x / scale, co.y / scale)
            elif abs(n.x) > abs(n.y):
                uv[li].uv = (co.y / scale, co.z / scale)
            else:
                uv[li].uv = (co.x / scale, co.z / scale)


def export(path, objs, extra=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    kw = dict(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
        export_image_format="JPEG",
        export_jpeg_quality=82,
        export_materials="EXPORT",
    )
    if extra:
        kw.update(extra)
    if os.environ.get("DRACO"):
        kw.update(export_draco_mesh_compression_enable=True, export_draco_mesh_compression_level=int(os.environ.get('DRACO_LEVEL', 6)))
        if os.environ.get('DRACO_Q'):
            kw.update(export_draco_position_quantization=12, export_draco_normal_quantization=8, export_draco_texcoord_quantization=10, export_draco_color_quantization=6)
    bpy.ops.export_scene.gltf(**kw)
    print("EXPORTED", path, os.path.getsize(path), "bytes")


def grunge_image(name, size=256, seed=3, lo=0.72, hi=1.0):
    """A small tileable concrete-grain greyscale image, generated here so no files are needed."""
    import numpy as np

    rng = np.random.default_rng(seed)
    acc = np.zeros((size, size))
    for octave, amp in ((4, 0.5), (8, 0.3), (16, 0.2), (64, 0.15), (128, 0.1)):
        g = rng.random((octave, octave))
        # tileable upscale by repeating the grid with wrap and smoothing with a cosine blend
        xs = np.linspace(0, octave, size, endpoint=False)
        x0 = np.floor(xs).astype(int)
        t = xs - x0
        t = t * t * (3 - 2 * t)
        x1 = (x0 + 1) % octave
        row0 = g[x0][:, x0] * (1 - t)[None, :] + g[x0][:, x1] * t[None, :]
        row1 = g[x1][:, x0] * (1 - t)[None, :] + g[x1][:, x1] * t[None, :]
        acc += amp * (row0 * (1 - t)[:, None] + row1 * t[:, None])
    acc = (acc - acc.min()) / (acc.max() - acc.min())
    v = lo + (hi - lo) * acc
    img = bpy.data.images.new(name, size, size, alpha=False)
    px = np.empty((size, size, 4), dtype=np.float32)
    px[..., 0] = px[..., 1] = px[..., 2] = v
    px[..., 3] = 1
    img.pixels.foreach_set(px.ravel())
    img.pack()
    return img


def preview(path, loc, target, lens=40, res=(1100, 700), sun_rot=(0.9, 0.2, 0.6), world="#1a2a38", sun=3.0, fill=1.5):
    """A quick Eevee still for checking a model."""
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = path
    sc.render.image_settings.file_format = "PNG"
    sc.view_settings.view_transform = "Standard"
    sc.eevee.taa_render_samples = 32
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = hexcol(world)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = fill
    sc.world = w
    ld = bpy.data.lights.new("sun", "SUN")
    ld.energy = sun
    so = bpy.data.objects.new("sun", ld)
    sc.collection.objects.link(so)
    so.rotation_euler = sun_rot
    cam = bpy.data.cameras.new("cam")
    cam.lens = lens
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    co.location = loc
    co.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = co
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", path)


def vertex_ao(targets, occluders, ground=None, rays=10, maxd=4.0, strength=0.85, layer="Col", skip=None):
    """Bake ambient occlusion into a vertex colour layer: for every face corner of the target objects, cast hemisphere rays against all
    the occluders (and a ground plane, if given as (half_x, half_y)), and multiply the layer's rgb by how open the corner is. No Cycles.
    Objects must sit at the origin (their vertices are world positions)."""
    import numpy as np
    from mathutils.bvhtree import BVHTree

    verts, polys = [], []
    for ob in occluders:
        me = ob.data
        base = len(verts)
        mw = ob.matrix_world
        verts.extend(mw @ v.co for v in me.vertices)
        polys.extend(tuple(base + i for i in p.vertices) for p in me.polygons)
    if ground:
        gx, gy = ground
        base = len(verts)
        verts.extend([Vector((-gx, -gy, 0)), Vector((gx, -gy, 0)), Vector((gx, gy, 0)), Vector((-gx, gy, 0))])
        polys.append((base, base + 1, base + 2, base + 3))
    bvh = BVHTree.FromPolygons(verts, polys)
    # cosine-weighted hemisphere directions (local z up)
    dirs = []
    for k in range(rays):
        u = (k + 0.5) / rays
        a = k * 2.399963
        r = math.sqrt(u)
        dirs.append((r * math.cos(a), r * math.sin(a), math.sqrt(1 - u)))
    done = 0
    for ob in targets:
        me = ob.data
        if layer not in me.color_attributes:
            me.color_attributes.new(layer, "FLOAT_COLOR", "CORNER")
            init = np.ones(len(me.loops) * 4, dtype=np.float32)
            me.color_attributes[layer].data.foreach_set("color", init)
        attr = me.color_attributes[layer]
        arr = np.empty(len(me.loops) * 4, dtype=np.float32)
        attr.data.foreach_get("color", arr)
        arr = arr.reshape(-1, 4)
        for p in me.polygons:
            if skip and p.material_index in skip:
                continue
            n = p.normal
            ref = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))
            t = n.cross(ref).normalized()
            b = n.cross(t)
            for li in p.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co
                org = co + n * 0.03
                spin = ((co.x * 12.9898 + co.y * 78.233 + co.z * 37.719) % 1.0) * 6.2832
                cs, sn = math.cos(spin), math.sin(spin)
                occ = 0.0
                for dx, dy, dz in dirs:
                    rx, ry = dx * cs - dy * sn, dx * sn + dy * cs
                    d = t * rx + b * ry + n * dz
                    hit = bvh.ray_cast(org, d, maxd)
                    if hit[0] is not None:
                        occ += 1.0 - hit[3] / maxd
                ao = 1.0 - strength * (occ / rays)
                arr[li, :3] *= ao
            done += 1
        attr.data.foreach_set("color", arr.ravel())
    return done

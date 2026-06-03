"""Re-texture the КОРСАР1 firecracker box GLB with a clean box-projected UV map.

Headless Blender pipeline:
  import scan GLB -> join -> planar (dissolve) decimate -> per-face box UV
  projection into tex_korobka.png atlas rects -> assign material -> export GLB.
A quick EEVEE preview is rendered so the artwork orientation can be verified.

Run:  blender --background --python tools/texture_petard.py
"""
import bpy, math

ROOT = "c:/Room45"
SRC_GLB  = ROOT + "/models/korobka_dlya_petard.glb"
OUT_GLB  = ROOT + "/models/korobka_dlya_petard_tex.glb"
ATLAS    = ROOT + "/tex_korobka.png"
RENDER   = ROOT + "/_raw/_petard_render.png"

# Atlas rects (normalized, TOP-LEFT origin) — must match tools that build tex_korobka.png.
# The striker is baked into the TOP tile as a clean rectangle (see build_atlas.py).
RECTS = {  # = build_atlas.py pixel rects / 2048
    "TOP":    (0.0200, 0.0200, 0.6201, 0.4302),
    "BOTTOM": (0.6602, 0.0200, 0.3198, 0.2998),
    "FRONT":  (0.0200, 0.5000, 0.7798, 0.2002),
    "BACK":   (0.0200, 0.7202, 0.7798, 0.2002),
    "LEFT":   (0.0200, 0.9399, 0.2998, 0.0498),
    "RIGHT":  (0.3398, 0.9399, 0.2998, 0.0498),
}
# Per-face orientation flips (flip_s, flip_t) in TOP-LEFT space.
FLIPS = {
    "TOP":    (True,  True),
    "BOTTOM": (False, True),
    "FRONT":  (False, True),
    "BACK":   (True,  True),
    "LEFT":   (False, False),
    "RIGHT":  (True,  False),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_and_join():
    bpy.ops.import_scene.gltf(filepath=SRC_GLB)
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    # Bake transforms so vertex coords are world-aligned (Blender Z-up).
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def decimate(obj):
    before = len(obj.data.polygons)
    m = obj.modifiers.new("planar", 'DECIMATE')
    m.decimate_type = 'DISSOLVE'
    m.angle_limit = math.radians(8)
    bpy.ops.object.modifier_apply(modifier=m.name)
    print(f"[decimate] polys {before} -> {len(obj.data.polygons)}")


def axis_roles(obj):
    cos = [v.co for v in obj.data.vertices]
    mn = [min(c[i] for c in cos) for i in range(3)]
    mx = [max(c[i] for c in cos) for i in range(3)]
    size = [mx[i] - mn[i] for i in range(3)]
    thin = min(range(3), key=lambda i: size[i])
    rest = [i for i in range(3) if i != thin]
    long_a, short_a = (rest[0], rest[1]) if size[rest[0]] >= size[rest[1]] else (rest[1], rest[0])
    print(f"[axes] size={['%.3f'%s for s in size]} thin={thin} long={long_a} short={short_a}")
    return mn, size, thin, long_a, short_a


def project_uv(obj):
    mn, size, thin, long_a, short_a = axis_roles(obj)
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data

    def emit(poly, ua, va, key):
        rx, ry, rw, rh = RECTS[key]
        fs, ft = FLIPS[key]
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            s = (co[ua] - mn[ua]) / size[ua]
            t = (co[va] - mn[va]) / size[va]
            if fs: s = 1.0 - s
            if ft: t = 1.0 - t
            uv[li].uv = (rx + s * rw, 1.0 - (ry + t * rh))

    # The striker is painted as a clean rectangle baked INTO the TOP tile, so the
    # whole top face maps continuously to "TOP" (no ragged mesh splitting).
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        positive = n[ax] >= 0.0
        if ax == thin:
            emit(poly, long_a, short_a, "TOP" if positive else "BOTTOM")
        elif ax == short_a:
            emit(poly, long_a, thin, "FRONT" if positive else "BACK")
        else:
            emit(poly, short_a, thin, "LEFT" if positive else "RIGHT")


def assign_material(obj):
    mat = bpy.data.materials.new("Korsar")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(ATLAS)
    nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.6
    bsdf.inputs["Metallic"].default_value = 0.0
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def render_preview(obj):
    scene = bpy.context.scene
    # frame the object
    c = obj.location
    dim = max(obj.dimensions)
    cam_data = bpy.data.cameras.new("Cam"); cam = bpy.data.objects.new("Cam", cam_data)
    cam_data.type = 'ORTHO'; cam_data.ortho_scale = dim * 1.15
    scene.collection.objects.link(cam); scene.camera = cam
    # straight-on view of the +Y lid to check the striker rectangle
    cam.location = (c.x, c.y + dim*3.0, c.z)
    d = obj.matrix_world.translation - cam.location
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 4.0; sun.rotation_euler = (math.radians(50), 0, math.radians(40))
    scene.collection.objects.link(sun)
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 700; scene.render.resolution_y = 700
    scene.render.filepath = RENDER
    scene.world = bpy.data.worlds.new("W"); scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.9, 0.9, 0.9, 1)
    bpy.ops.render.render(write_still=True)
    print("[render]", RENDER)


def main():
    reset()
    obj = import_and_join()
    decimate(obj)
    project_uv(obj)
    assign_material(obj)
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB', use_selection=False)
    print("[export]", OUT_GLB)
    render_preview(obj)


main()

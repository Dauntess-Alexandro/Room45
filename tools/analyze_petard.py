"""Locate the raised striker platform on the box: analyse up-facing faces.

Run:  blender --background --python tools/analyze_petard.py
"""
import bpy

SRC = "c:/Room45/models/korobka_dlya_petard.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ms = [o for o in bpy.context.scene.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for m in ms:
    m.select_set(True)
bpy.context.view_layer.objects.active = ms[0]
if len(ms) > 1:
    bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = obj.data

cos = [v.co for v in me.vertices]
mn = [min(c[i] for c in cos) for i in range(3)]
mx = [max(c[i] for c in cos) for i in range(3)]
size = [mx[i] - mn[i] for i in range(3)]
print("[bbox] min", ["%.3f" % v for v in mn], "size", ["%.3f" % v for v in size])
thin = min(range(3), key=lambda i: size[i])
print("[thin axis (up/down)] =", thin)

# up-facing faces (normal along +thin)
up = []
for p in me.polygons:
    if p.normal[thin] > 0.5:
        c = p.center
        up.append((c[thin], c[0], c[1], c[2]))
if not up:
    print("no up faces?!")
else:
    ys = [u[0] for u in up]
    print("[up faces] count", len(up), "center[thin] min %.3f max %.3f" % (min(ys), max(ys)))
    # histogram across the two non-thin axes to find a raised, localized strip
    rest = [i for i in range(3) if i != thin]
    a, b = rest
    print("[up faces] axis%d range %.3f..%.3f  axis%d range %.3f..%.3f"
          % (a, min(u[1+a] for u in up), max(u[1+a] for u in up),
             b, min(u[1+b] for u in up), max(u[1+b] for u in up)))
    # for each non-thin axis, bin and report the mean height (center[thin]) per bin
    for ax in rest:
        print(f"--- height profile along axis {ax} (looking for the raised lip) ---")
        lo, hi = mn[ax], mx[ax]
        N = 12
        bins = [[] for _ in range(N)]
        for u in up:
            coord = u[1 + ax]
            k = min(N - 1, int((coord - lo) / max(hi - lo, 1e-6) * N))
            bins[k].append(u[0])
        for k in range(N):
            if bins[k]:
                seg = lo + (hi - lo) * (k + 0.5) / N
                print("  %s=%.3f  n=%4d  meanH=%.4f  maxH=%.4f"
                      % ("xyz"[ax], seg, len(bins[k]),
                         sum(bins[k]) / len(bins[k]), max(bins[k])))

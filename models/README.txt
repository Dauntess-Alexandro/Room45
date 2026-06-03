3D models (models/)
=====================

How furniture works now (editable nodes)
----------------------------------------
furniture.gd is a @tool script. The FIRST time you open main.tscn in the editor
it builds the whole room (desk, shelf, wardrobe, sofa, computer, pillow, window,
chandelier, rug, decals) as real, selectable, draggable nodes under the
"Furniture" node, auto-sized/oriented/placed.

  -> Press Ctrl+S once to bake those nodes into main.tscn.

After that, the script leaves them alone (a get_child_count() guard), so any
position / rotation / scale / material you tweak by hand sticks. Move things in
the 3D viewport like any normal node.

Regenerate from scratch: delete all children of the Furniture node and reopen
the scene (it will rebuild + you Ctrl+S again).

Adding a NEW model (editable by default)
----------------------------------------
1. Export as GLB (preferred), lowercase name, drop it in this folder.
2. In furniture.gd add a small `_build_*()` that loads + places it and call it
   from _ready(). Use the sofa/computer helpers as a template:
     - _instance + _mesh_aabb_in_space() to measure real-world bounds
     - scale to a target size, rotate, position in room coords
3. Open the scene, Ctrl+S. Anything a _build_* adds is auto-owned, so the new
   prop is a draggable scene node with no extra work.

Sofa (daybed)
-------------
File: sofa.glb. Auto-scaled to SOFA_TARGET_SIZE and placed on the west wall.
Tweak defaults in furniture.gd: SOFA_TARGET_SIZE, SOFA_CENTER_Z, SOFA_WALL_GAP,
and _pick_sofa_y_rotation() for orientation. (Or just drag the baked Sofa node.)

Pillow
------
File: pillow.glb — auto-placed flat on the sofa cushion (blue material).
Tweak: GLB_UNIT_SCALE and the pillow_xz ratio in _attach_sofa_accessories().
Note: the blue tint is a material_override; if it doesn't survive a save on the
instanced mesh, set it by hand on the Pillow's MeshInstance in the editor.

Computer + screen
-----------------
File: old_computer.glb — one PC on the desk, auto-scaled to COMPUTER_TARGET_H
and rotated by COMPUTER_YAW. The glowing CRT (tex_monitor.jpg) is a SEPARATE
hand-placed node "ComputerScreen" in main.tscn — select & drag it onto the
monitor glass; size lives on its ScreenQuad mesh.

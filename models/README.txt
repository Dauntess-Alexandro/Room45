3D models (models/)
=====================

Sofa (daybed)
-------------

1. Generate a model (see prompts in chat / project docs).
2. Export as  GLB  (preferred) or  GLTF .
3. Save as:  sofa.glb  in this folder (lowercase name).
4. Run the game (F5). Furniture auto-scales and places it on the west wall.

If the sofa is wrong way around, edit furniture.gd:
  _build_sofa_from_glb()  →  rotation_degrees on the Sofa node
  _finalize_sofa_glb()    →  SOFA_TARGET_SIZE, SOFA_CENTER_Z

Target real size: ~0.85 m wide (into room) × ~1.9 m long × ~0.55 m tall.

Monitor + PC
------------
Desk uses procedural CRT boxes + tex_monitor.jpg glowing screens (two monitors).
old_computer.glb is not loaded yet — drop it in models/ when ready to try again.

Tweak: furniture.gd → SCREEN_SIZE and monitor positions in _build_monitors().

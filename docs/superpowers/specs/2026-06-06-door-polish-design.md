# Door polish — handle animation, weight, motion-driven creak

**Date:** 2026-06-06
**Scope:** Make the interactive door (`SimpleWoodDoor`) feel more alive and physical.
Polish-track only — no physical mouse-drag, no horror/locked-door features.

## Current behaviour
- `SimpleWoodDoor` (`models/simple_wood_door.tscn`) is a `StaticBody3D` running
  `interactable.gd` with `kind = DOOR`.
- On interact, `_toggle_door()` tweens `rotation:y` from 0 to `door_open_angle`
  (95°) over `door_anim_time` (0.65s) with `TRANS_CUBIC` / `EASE_OUT`, and plays a
  slice of `sound/woodendoor.mp3` via the `DoorSound` `AudioStreamPlayer3D`.
- The handle does **not** move; only the leaf rotates.
- Door model `models/simple_wood_door.glb` has a separate handle node
  `#DOR0001_Handles_0` (confirmed) — so the handle can be rotated independently.

## Goals (3 features)

### 1. Handle animation
- When the player opens or closes the door, the handle lever first **presses down**
  (~35°, ~0.15s), then **returns up** (~0.2s) while the leaf swings.
- Sequence on interact: handle down → leaf starts swinging → handle returns up.
- The handle node is found at runtime by name pattern (`*Handles*`) under the Model.
- The rotation **axis and pivot** are unknown up front and will be calibrated
  in-engine: rotate, run via the `godot` MCP, screenshot, adjust. Plan for ~2
  iterations. If the handle node's origin is not at the spindle, introduce a
  pivot wrapper node so the lever rotates about the correct point.
- Exposed as exported vars so values are tweakable in the scene
  (e.g. `handle_press_angle`, `handle_press_time`, `handle_return_time`).
- Degrade gracefully: if no handle node is found, skip handle animation and just
  swing the leaf (current behaviour) — no errors.

### 2. Weight (door settle)
- Replace the plain ease-out with a subtle **overshoot-and-settle**: the leaf
  slightly passes the target angle then eases back, like a heavy door on its
  inertia. Effect must be small enough not to clip the wall (overshoot only when
  opening, capped at a few degrees).
- Tunable via an exported `door_settle_degrees` (default small, e.g. 2–3°).
  Setting it to 0 reproduces the current clean ease-out.

### 3. Motion-driven creak
- While the leaf is moving, drive the `DoorSound` player's `pitch_scale` and
  `volume_db` from the leaf's **current angular speed** (fast at the start of the
  swing → louder and slightly higher; slowing to a stop → quieter).
- Implemented by sampling the leaf's rotation delta each frame during the tween
  (in `_process` or `_physics_process`, active only while animating).
- Keep the existing start/duration slice vars as the clip selection; this feature
  modulates that playback rather than replacing it.
- Tunable mapping via exported vars (min/max pitch, volume range).

## Out of scope
- Physical mouse-drag door, locked door / keys, dust particles, light spill,
  self-opening door. (Atmosphere/horror track was not chosen.)

## Files touched
- `interactable.gd` — handle lookup, handle tween sequencing, settle easing,
  per-frame creak modulation, new exported vars.
- `models/simple_wood_door.tscn` — set/calibrate the new exported values; possibly
  add a handle pivot wrapper node if calibration requires it.

## Verification
- Run via `godot` MCP `run_project` on `C:/Room45`, open and close the door,
  screenshot to confirm the handle presses down and the leaf settles; check
  `get_debug_output` for errors. Listen-test not possible headless — creak logic
  verified by code review + no runtime errors.

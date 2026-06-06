# Physics door — grab-and-swing hinge door (My Summer Car style)

**Date:** 2026-06-06
**Scope:** Rebuild the interactive `SimpleWoodDoor` from a script-animated
`StaticBody3D` into a true physics door: a `RigidBody3D` leaf on a `HingeJoint3D`,
pushed by mouse movement while the player holds the interact key.

Replaces the current tap-to-toggle door animation. Decision record:
- **Physics:** true `RigidBody3D` + `HingeJoint3D` (not script-faked).
- **Control:** mouse-grab only (no tap-to-auto-open).
- **Push direction:** mouse-impulse based ("push" the door, momentum carries it),
  not exact cursor-follow.

## Current behaviour (being replaced)
- `models/simple_wood_door.tscn`: root `StaticBody3D` with `interactable.gd`,
  `kind = DOOR`. `_toggle_door()` tweens `rotation:y` 0↔95° with handle press,
  settle overshoot, and speed-driven creak. Prompt flips OPEN/CLOSE DOOR.
- Door model `models/simple_wood_door.glb` has a separate handle node
  `#DOR0001_Handles_0` (reused for the press animation).
- Player (`player.gd`): mouse look in `_unhandled_input`; raycast interaction in
  `_update_interaction` calls `interact()` on `Interactable` colliders; prompt via
  `get_prompt()`.

## Architecture

### Scene: `models/simple_wood_door.tscn` (restructured)
- Root `Node3D` "SimpleWoodDoor" at the hinge position (preserves how it is placed
  in `main.tscn`).
- `DoorLeaf` : `RigidBody3D` — runs the new `physics_door.gd`. Holds:
  - `Model` (the GLB instance, with `simple_wood_door_cleanup.gd`).
  - `Collision` : `CollisionShape3D` (the existing leaf box).
  - `DoorSound` : `AudioStreamPlayer3D` (reused, with `woodendoor.mp3`).
  - Mass moderate (heavy door feel), `angular_damp` tuned for natural slow-down,
    `continuous_cd = true` to avoid tunneling, gravity disabled (hinge holds it).
  - Collision layer/mask so the closed leaf still blocks the player and the
    interaction ray detects it.
- `Hinge` : `HingeJoint3D` — `node_a` empty (anchors to world), `node_b` = DoorLeaf.
  Positioned/oriented at the hinge axis (vertical). Angular limit enabled
  (lower ~0°, upper ~95° — exact sign matched to the model). Used to stop the
  swing at closed and fully-open.

### Script: `physics_door.gd` (new, on `DoorLeaf`)
Single responsibility: own the door's physical behaviour and feedback. Public
interface used by the player:
- `is_grabbable() -> bool` — marks this body as a grabbable door.
- `get_prompt() -> String` — HUD text (e.g. "HOLD [E]  DOOR").
- `grab_begin() -> void` — player took hold (press handle down, mark grabbed).
- `grab_drive(mouse_dx: float) -> void` — apply an angular impulse from horizontal
  mouse movement this frame.
- `grab_end() -> void` — player let go (release handle, leave momentum).

Internals:
- Handle press reuse: find `*Handles*` node, tween it down on `grab_begin`, back on
  `grab_end` (same rest-basis + local-axis approach as before).
- Creak: in `_physics_process`/`_integrate_forces`, read the leaf's angular speed
  and modulate `DoorSound` pitch/volume (as in the current door).
- Slam + latch: when the leaf reaches the closed limit with speed above a threshold,
  play a sharper "slam"/latch via the sound player; below threshold, quiet settle.
- All feel values exported: `push_strength`, `mass`, `angular_damp`,
  `open_limit_degrees`, `slam_speed_threshold`, creak pitch/volume range.

### Player changes: `player.gd`
- New grab state: `_grabbed_door` (the door being held) and an accumulator for
  mouse delta.
- `_unhandled_input`: if a door is grabbed, route `InputEventMouseMotion.relative.x`
  to the door (`grab_drive`) and suppress camera look; otherwise look as today.
- `_update_interaction`: when the ray hits a body with `is_grabbable()` and the
  player presses-and-holds interact, call `grab_begin()` and enter grab state; while
  held, keep driving; on release (or aim-away / distance break) call `grab_end()`
  and exit. Show the door's `get_prompt()` while aimed at it.
- The existing `Interactable` tap path is untouched (switches, computer, pickups).

## Control flow
1. Aim at the door → prompt "HOLD [E]  DOOR".
2. Press and hold interact → `grab_begin()`; camera look suspended; handle presses.
3. Move mouse left/right → `grab_drive(dx)` imparts angular impulse; door swings with
   momentum.
4. Release interact (or look away / step too far) → `grab_end()`; door keeps its
   momentum and damps to rest; handle returns.
5. Swinging into the closed limit fast → slam + latch click; gently → quiet settle.

## Error handling / guardrails
- `continuous_cd = true` and a capped per-event impulse to prevent tunneling and
  runaway spin.
- Hinge angular limits keep the leaf within 0…open; it can rest at any angle between.
- Auto-release if the aim leaves the door or the player exceeds the interact distance
  while holding, so the camera can never get "stuck" in grab mode.
- Null-guards: if the handle node or sound player is missing, those effects are
  skipped without errors.

## Out of scope
- Door physically shoving the (kinematic) player — it stops against the player like a
  wall but does not push them. (Full player-push is a separate, riskier task.)
- The balcony doors and any other door — only `SimpleWoodDoor`.
- Locks/keys, drafts, light-spill (separate atmosphere track).

## Verification
- `godot` MCP `run_project` + `get_debug_output`: project loads, no errors,
  joint/rigidbody set up without warnings.
- Behaviour (grab, swing, inertia, slam) cannot be exercised headless (no mouse
  injection, no screenshot). Verified iteratively by the user in-engine: grab works,
  no jitter/tunneling, door rests at arbitrary angles, slam reads. Tuning passes
  follow user feedback.

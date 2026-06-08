# Realistic sky — Stage 3: camera & light (auto-exposure, soft shadows)

**Date:** 2026-06-08
**Scope:** Third stage of the staged sky/atmosphere effort. Add a gentle, bounded
auto-exposure ("eye adjusts to light"), soften shadow edges, and tune shadow
distance for the small interior. Stages 1 (sky) and 2 (atmosphere) are done.

Later/optional (NOT here): clouds, blue-hour, anything that brightens the night.

## Current state
- `main.tscn`: `WorldEnvironment` with Environment `Env` (sky, glow, fog,
  volumetric fog, Filmic tonemap). No `camera_attributes` set → no exposure
  control. Player camera is `Player/Camera3D` (no attributes).
- Lights: `Sun` (DirectionalLight3D, `shadow_enabled`, default shadow settings),
  `Moon` (DirectionalLight3D, soft moonlight at night), chandelier/lamp
  `OmniLight3D`s with `shadow_enabled` on some.
- `sun_controller.gd` drives sun/moon energy & shadow_enabled by time of day.
- `project.godot`: default shadow filter quality.

## Goals

### 1. Bounded, gentle auto-exposure
- Add a `CameraAttributesPractical` resource on the `WorldEnvironment`
  (`camera_attributes`) so exposure applies globally to the player's view.
- Enable auto-exposure with a **narrow min/max sensitivity range** and a **slow
  adaptation speed**, so moving between bright and dark areas eases the brightness
  a little — but the clamp keeps night and dark corners dark (no auto-brightening
  the night). All knobs exported/tunable in the scene.

### 2. Soft shadows
- Give the `Sun` (and `Moon`) directional lights an angular size
  (`light_angular_distance`) so their shadows gain a natural penumbra (soft edge
  that widens with distance), plus a small `shadow_blur`.
- Add `shadow_blur` to the shadow-casting lamps/omnis so their edges aren't hard.
- Raise the project's soft-shadow filter quality
  (`rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality`
  and the directional equivalent) for clean penumbra.

### 3. Shadow distance tuning
- Set the `Sun`'s `directional_shadow_max_distance` to suit the flat (~20 m) so
  near shadows stay crisp instead of being spread thin across a huge range; tune
  split/fade so indoor shadows read sharply.

## Architecture / files
- Modify: `main.tscn` — add a `CameraAttributesPractical` sub-resource, set it as
  `WorldEnvironment.camera_attributes`; add `light_angular_distance` /
  `shadow_blur` / `directional_shadow_max_distance` to `Sun` and `Moon`, and
  `shadow_blur` to shadow-casting lamps.
- Modify: `project.godot` — soft-shadow filter quality settings.
- No script changes expected; `sun_controller` continues to drive light energies.
  (If auto-exposure needs time-of-day modulation it stays in scope, but the bounded
  static setup is the goal — keep it simple.)

## Interfaces
- `WorldEnvironment.camera_attributes` → the practical camera attributes
  (auto-exposure min/max sensitivity, speed, scale).
- Light shadow properties are static node settings tuned in the scene.

## Error handling / guardrails
- Auto-exposure min/max sensitivity clamped so the night cannot brighten past a
  set floor; slow speed avoids visible "pumping".
- Soft-shadow quality kept at a moderate level (not ultra) to protect fps; tunable.
- Nothing here adds light sources, so it can't leak daylight into night.
- If auto-exposure proves distracting, it can be disabled with one flag without
  touching the rest.

## Out of scope
Clouds, blue-hour, lens effects (DOF, motion blur), per-time exposure scripting.

## Verification
- `godot` MCP `run_project` + `get_debug_output`: loads with no errors.
- In-engine USER TESTS: move between a bright window and a dark corner (gentle
  exposure ease, night still dark), check shadow edges are soft not pixelated, and
  near shadows are crisp; fps fine. Exposure range/speed and shadow softness tuned
  from feedback (cannot be seen headless).

# Realistic sky — Stage 1: sky, sun disk, moon & stars

**Date:** 2026-06-07
**Scope:** First of a staged "realistic sun/sky" effort. Replace the flat colour
background with a procedural day–night sky (sun disk, stars + Milky Way, moon),
add real moonlight, and drive it all from the existing time-of-day system.

Later stages (NOT in this spec): atmosphere (bloom, volumetric god-rays, fog),
camera realism (auto-exposure, soft shadows), dynamics (clouds, blue hour).

## Current state
- `main.tscn` Environment (`SubResource("Env")`): `background_mode = 1` (flat
  Color), `tonemap_mode = 2` (Filmic), `ambient_light_sky_contribution = 0`,
  no Sky, no fog, no glow.
- `sun_controller.gd` (on the `Sun` DirectionalLight3D) already, each frame:
  reads `GameClock` hour, computes a `daylight` amount (0 night … 1 day) and a
  `day_t` (0 at sunrise … 1 at sunset), points the sun via `_sun_ray_direction`,
  sets sun colour/energy, window beam, window fill lights, the zal extra window
  fill, ambient colour/energy, background colour, and the `*Daylight` panel mats.
- Sunrise 6.0, sunset 20.5, night 21.5 (exported).

## Goals

### 1. Procedural day–night sky (`sky.gdshader`)
A custom `ShaderMaterial` used by a `Sky` resource, set as the Environment
background (`background_mode = Sky`). One shader covers the whole cycle, blended
by a `daylight` uniform:
- **Day:** horizon→zenith gradient, a **sun disk** with soft glow drawn at the
  sun direction; warmer near the horizon.
- **Night:** deep blue-black sky, a **starfield** (procedural hash stars) with a
  **Milky Way** band and subtle **twinkle** (time-based), plus a **moon disk**
  with glow at the moon direction.
- **Uniforms** (set every frame by `sun_controller`): `sun_dir` (Vector3, toward
  the sun), `moon_dir` (Vector3, toward the moon), `daylight` (float 0..1),
  `time` (float seconds, for twinkle), plus tunable colours/sizes.

### 2. Real moonlight (new `Moon` DirectionalLight3D)
- A second directional light: cool, dim. Energy ramps up at night
  (`~ (1 - daylight)`), zero in daytime; casts soft shadows when lit.
- Its direction follows a simple night arc (opposite side of the sky from the
  sun is fine for Stage 1); the same direction is fed to the sky as `moon_dir`.
- Driven by `sun_controller` (it is already the time-of-day "conductor").

### 3. Wiring & integration
- `sun_controller` resolves the sky material (from the Environment) and the Moon
  light, and updates their uniforms/energy inside `_apply_time_of_day`.
- Switch the Environment to `background_mode = Sky` with the new sky.
- Let the sky tint indoor ambient: set a modest `ambient_light_sky_contribution`
  (and/or keep driving `ambient_light_color`) so lighting reads as one piece.
  Keep it subtle so enclosed rooms don't wash out — exact value tuned in-engine.
- Existing window fills, beam, `*Daylight` panels, and room/switch lights are
  unchanged.

## Architecture / files
- Create: `sky.gdshader` — the day–night sky shader (single responsibility:
  paint the sky from uniforms). No game logic inside.
- Modify: `sun_controller.gd` — resolve + feed the sky material uniforms; resolve
  + drive the Moon light. New exported paths (`sky_path` or read from
  Environment; `moon_light_path`) and moon tuning vars.
- Modify: `main.tscn` — add a `Sky`/`ShaderMaterial` sub-resource on the
  Environment, set `background_mode = Sky`, add the `Moon` DirectionalLight3D,
  wire the new `sun_controller` paths.

## Interfaces
- `sun_controller` → sky: sets shader params `sun_dir`, `moon_dir`, `daylight`,
  `time` (and static colour/size params at startup).
- `sun_controller` → moon light: sets `light_energy`, `light_color`,
  orientation, `shadow_enabled`.

## Error handling / guardrails
- All new node/resource lookups null-guarded; if the sky material or Moon light
  is missing, the rest of `sun_controller` still runs without errors.
- Moon energy is 0 in daytime so it never double-lights the scene with the sun.
- Sky shader must compile clean (no Godot shader errors on load).

## Out of scope (later stages)
Bloom/glow, volumetric fog, god-rays, distance fog, auto-exposure, soft-shadow
tuning beyond enabling moon shadows, clouds, blue-hour refinement.

## Verification
- `godot` MCP `run_project` + `get_debug_output`: loads with no shader/script
  errors. Behaviour (sky look, sun arc, moon, stars, Milky Way, twinkle, night
  brightness) is verified by the user in-engine across day and night; colours,
  star density, moon size, and ambient contribution tuned from their feedback
  (cannot be seen headless — no screenshot of the running game).

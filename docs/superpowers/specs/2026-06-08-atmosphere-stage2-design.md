# Realistic sky — Stage 2: atmosphere (glow, light god-rays, fog)

**Date:** 2026-06-08
**Scope:** Second stage of the staged sky/atmosphere effort. Add a light, VotV-style
atmosphere on top of Stage 1's sky: screen glow/bloom, a low-density volumetric fog
for subtle dust light-shafts from the window, a cheap time-tinted distance haze, and
a stronger golden hour. Deliberately the LIGHT variant (low perf cost).

Stage 1 (sky, sun disk, moon, stars, moonlight) is done. Later/optional stages
(camera auto-exposure, soft shadows, clouds, blue-hour) are NOT in this spec.

## Current state
- `main.tscn` Environment sub-resource `id="Env"`: `background_mode = 2` (sky),
  `sky = SkyRes`, `ambient_light_source = 2` (Color), `ambient_light_energy = 0.45`,
  `tonemap_mode = 2` (Filmic). **No glow, no fog, no volumetric fog.**
- `sun_controller.gd` is the time-of-day conductor: each frame computes `daylight`
  (0 night … 1 day), `day_t`, `height`, sun colour/dir; drives the sky uniforms,
  window fills, beam, moon, reflection-probe refresh, ambient colour/energy.
- Lights that can scatter into volumetric fog: `Sun` (DirectionalLight3D) and
  `WindowSunBeam` (SpotLight3D, aimed through the window).

## Goals

### 1. Glow / bloom
- Enable Environment glow (HDR) so bright emitters — sun disk, lit windows, the
  chandelier bulbs, the CRT — bloom softly.
- Use a moderate threshold so only genuinely bright pixels bloom (no full-screen
  haze). Tunable: `glow_intensity`, `glow_strength`, `glow_bloom`, HDR threshold.

### 2. Light volumetric fog (subtle dust god-rays)
- Enable Environment volumetric fog at **low density** so the air carries faint
  dust; the `Sun` and `WindowSunBeam` scatter in it to make gentle light-shafts
  from the window along the sun direction.
- Give `Sun` and `WindowSunBeam` a `volumetric_fog_energy` so they produce visible
  shafts; keep density low for performance.
- Density is exported/tunable; can be lowered (or the fog disabled) if fps drops.

### 3. Cheap distance haze, tinted by time of day
- Enable Environment depth fog (the cheap kind, not volumetric) at low density for
  a faint moody haze, mostly seen in depth / out the window.
- `sun_controller` tints the fog colour by `daylight`: light by day, warm at
  sunset, cool blue at night — matching the rest of the lighting.

### 4. Stronger golden hour
- In `sun_controller`, deepen the warm sunrise/sunset sun colour so low-sun hours
  read clearly golden/orange (a tweak to the existing `_sun_color` horizon blend).

## Architecture / files
- Modify: `main.tscn` — Environment `Env`: glow, volumetric fog, depth fog
  settings; `Sun` and `WindowSunBeam`: `volumetric_fog_energy`.
- Modify: `sun_controller.gd` — tint/drive the fog colour (and optionally volumetric
  density) by time of day; deepen the golden-hour sun colour. New exported tuning
  vars (fog day/sunset/night colours, max densities) and resolving the environment
  fog (already has `_environment`).

## Interfaces
- `sun_controller` → Environment: sets `fog_light_color` (and density if modulated)
  each frame from `daylight`/`day_t`.
- Glow, volumetric-fog enable/density, and the lights' `volumetric_fog_energy` are
  static Environment/node settings tuned in the scene.

## Error handling / guardrails
- All Environment access stays null-guarded (existing `_environment` check).
- Volumetric fog density kept low by default; a single exported knob lets us cut it
  or turn it off without touching structure.
- Glow threshold set so normal interior brightness doesn't bloom into mush.
- Nothing here should brighten the night: fog at night is cool/dim, volumetric fog
  only scatters the (night-zero) sun and the (night-zero) beam, so no daylight leak.

## Out of scope (later stages)
Auto-exposure, soft-shadow tuning, clouds, blue-hour, any heavy/high-density
volumetric setup.

## Verification
- `godot` MCP `run_project` + `get_debug_output`: loads with no errors.
- Look (glow on lights/windows, faint dust shafts from the window by day, time-tinted
  haze, golden sunrise/sunset, dark night) verified by the user in-engine across day
  and night; glow threshold, fog density/colour, and volumetric density tuned from
  feedback and for fps (cannot be seen headless).

**Verified 2026-06-08:** Glow on emitters, daytime room reads well, indoor haze
reduced to non-intrusive, god-rays present (faint at noon by design, stronger at
low sun), night stays dark, fps fine. Tuning applied: glow threshold 0.95, depth
fog density 0.004, volumetric anisotropy 0.7, sun/beam volumetric energy 2.0/5.0.

# Atmosphere Stage 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a light, VotV-style atmosphere — glow/bloom, faint volumetric dust shafts from the window, a cheap time-tinted distance haze, and a stronger golden hour — on top of the Stage 1 sky.

**Architecture:** Almost all of it is Environment settings on the existing `Env` sub-resource in `main.tscn` (glow, low-density volumetric fog, low-density depth fog) plus a `volumetric_fog_energy` on the sun/beam lights. `sun_controller.gd` tints the fog colour by time of day and deepens the golden-hour sun colour, reusing its existing per-frame `_apply_time_of_day()`.

**Tech Stack:** Godot 4.6 Environment (glow, fog, volumetric fog), GDScript. Verification: `godot` MCP (`run_project`/`get_debug_output`) for load errors **plus in-engine USER TESTS** day and night (no headless screenshot of the running game).

**Reference — current `Env` sub-resource in `main.tscn` (around line 54):**
```
[sub_resource type="Environment" id="Env"]
background_mode = 2
sky = SubResource("SkyRes")
ambient_light_source = 2
ambient_light_color = Color(0.28, 0.29, 0.32, 1)
ambient_light_sky_contribution = 0.0
ambient_light_energy = 0.45
tonemap_mode = 2
```
- `Sun` DirectionalLight3D (script `sun_controller.gd`) and `WindowSunBeam`
  SpotLight3D both exist and point through the window.
- `sun_controller._apply_time_of_day()` already computes `daylight`, `day_t`,
  `height`, `horizon_warmth`, sun `color`, and holds `_environment`.

---

## File Structure
- Modify: `main.tscn` — `Env`: glow + volumetric fog + depth fog; `Sun` and
  `WindowSunBeam`: `light_volumetric_fog_energy`.
- Modify: `sun_controller.gd` — tint fog colour by time of day; deepen golden hour.
- Modify: `docs/superpowers/specs/2026-06-08-atmosphere-stage2-design.md` — verify note.

---

## Task 1: Glow / bloom

**Files:**
- Modify: `main.tscn` (`Env` sub-resource)

- [ ] **Step 1: Add glow to the Environment**

In `main.tscn`, add these lines to the `Env` sub-resource (right after
`tonemap_mode = 2`):

```
glow_enabled = true
glow_normalized = true
glow_intensity = 0.5
glow_strength = 0.9
glow_bloom = 0.08
glow_blend_mode = 1
glow_hdr_threshold = 1.1
glow_levels/3 = 1.0
glow_levels/4 = 1.0
glow_levels/5 = 1.0
```

(`glow_hdr_threshold = 1.1` blooms only genuinely bright pixels — sun disk, lit
windows, bulbs, CRT — not the whole room. `glow_blend_mode = 1` is additive.)

- [ ] **Step 2: Run and check for errors**

`run_project` on `C:/Room45`, then `get_debug_output`. Expected: loads, no errors.
`stop_project`.

- [ ] **Step 3: USER TEST — glow**

Ask the user: do bright things (chandelier bulbs, the lit window/balcony, the sun
on the sky, the CRT when on) now have a soft glow halo, WITHOUT the matte walls
blooming into mush? Report if too strong/weak for tuning (`glow_strength`,
`glow_hdr_threshold`).

- [ ] **Step 4: Commit**

```bash
git add main.tscn
git commit -m "Add HDR glow/bloom to the environment"
```

---

## Task 2: Cheap distance haze, tinted by time of day

**Files:**
- Modify: `main.tscn` (`Env`)
- Modify: `sun_controller.gd`

- [ ] **Step 1: Enable depth fog on the Environment**

Add to the `Env` sub-resource (after the glow lines):

```
fog_enabled = true
fog_light_color = Color(0.62, 0.68, 0.80, 1)
fog_light_energy = 1.0
fog_density = 0.012
fog_sky_affect = 0.0
fog_aerial_perspective = 0.0
```

(`fog_sky_affect = 0.0` keeps the sky crisp; low density = faint haze in depth.)

- [ ] **Step 2: Add fog-colour tuning vars to sun_controller**

In `sun_controller.gd`, add exports after the moon/probe exports:

```gdscript
@export var fog_day_color := Color(0.62, 0.68, 0.80, 1.0)
@export var fog_night_color := Color(0.05, 0.07, 0.13, 1.0)
@export var fog_sunset_color := Color(0.85, 0.50, 0.30, 1.0)
```

- [ ] **Step 3: Tint the fog each frame**

Add this helper to `sun_controller.gd`:

```gdscript
func _fog_color(daylight: float, horizon_warmth: float) -> Color:
	var base := fog_night_color.lerp(fog_day_color, daylight)
	return base.lerp(fog_sunset_color, horizon_warmth * 0.5 * daylight)
```

In `_apply_time_of_day()`, inside the existing `if _environment != null:` block
(after the ambient/background lines), add:

```gdscript
		_environment.fog_light_color = _fog_color(daylight, horizon_warmth)
```

- [ ] **Step 4: Run and check for errors**

`run_project`, `get_debug_output`. Expected: no errors. `stop_project`.

- [ ] **Step 5: USER TEST — haze**

Ask the user: is there a faint haze in depth / looking down a room or out the
window, and does its colour shift with time (light by day, warm at sunset, cool
blue at night)? Report if too thick/thin (`fog_density`).

- [ ] **Step 6: Commit**

```bash
git add main.tscn sun_controller.gd
git commit -m "Add time-tinted distance haze"
```

---

## Task 3: Light volumetric fog (subtle dust god-rays)

**Files:**
- Modify: `main.tscn` (`Env`; `Sun` and `WindowSunBeam` nodes)

- [ ] **Step 1: Enable low-density volumetric fog**

Add to the `Env` sub-resource (after the depth-fog lines):

```
volumetric_fog_enabled = true
volumetric_fog_density = 0.012
volumetric_fog_albedo = Color(0.9, 0.9, 0.95, 1)
volumetric_fog_length = 32.0
volumetric_fog_gi_inject = 0.0
volumetric_fog_ambient_inject = 0.0
volumetric_fog_sky_affect = 0.0
```

(Low density = faint dust. `sky_affect = 0` keeps the sky clean. `ambient_inject = 0`
means the fog itself doesn't add ambient light — only the lights scatter in it.)

- [ ] **Step 2: Let the sun and window beam scatter into the fog**

On the `Sun` node in `main.tscn`, add (under its other properties, e.g. after
`shadow_enabled = true`):

```
light_volumetric_fog_energy = 1.2
```

On the `WindowSunBeam` node, add (after `spot_angle_attenuation = 0.22`):

```
light_volumetric_fog_energy = 2.0
```

- [ ] **Step 3: Run and check for errors**

`run_project`, `get_debug_output`. Expected: no errors. `stop_project`.

- [ ] **Step 4: USER TEST — dust shafts**

Ask the user, in daytime, to look toward the window/balcony: are there faint dusty
light-shafts coming in along the sun direction (clearest when the sun is low —
morning/evening)? It should be subtle, not a thick wall of fog. At night there
should be no daylight shafts (sun/beam are off). Report strength + fps for tuning
(`volumetric_fog_density`, the lights' `light_volumetric_fog_energy`).

- [ ] **Step 5: Commit**

```bash
git add main.tscn
git commit -m "Add light volumetric fog for subtle window god-rays"
```

---

## Task 4: Stronger golden hour

**Files:**
- Modify: `sun_controller.gd`

- [ ] **Step 1: Broaden the golden-hour warmth**

In `sun_controller.gd`, in `_apply_time_of_day()`, find:

```gdscript
	var horizon_warmth := pow(clampf(1.0 - height, 0.0, 1.0), 1.2)
```

and change the exponent so warmth ramps in earlier (a wider golden hour):

```gdscript
	var horizon_warmth := pow(clampf(1.0 - height, 0.0, 1.0), 0.85)
```

- [ ] **Step 2: Deepen the sunrise/sunset sun colour**

Replace the `_sun_color` function body:

```gdscript
func _sun_color(day_t: float, horizon_warmth: float, daylight: float) -> Color:
	var day := Color(1.0, 0.92, 0.78, 1.0)
	var dawn := Color(1.0, 0.50, 0.38, 1.0)
	var dusk := Color(1.0, 0.38, 0.14, 1.0)
	var horizon := dawn if day_t < 0.5 else dusk
	var sun := day.lerp(horizon, horizon_warmth)
	return Color(0.2, 0.25, 0.45, 1.0).lerp(sun, daylight)
```

- [ ] **Step 3: Run and check for errors**

`run_project`, `get_debug_output`. Expected: no errors. `stop_project`.

- [ ] **Step 4: USER TEST — golden hour**

Ask the user to watch sunrise/sunset (scrub the clock if possible): is the low-sun
light clearly warm/golden-orange, spilling warm through the window, without the
midday look going orange? Report for tuning.

- [ ] **Step 5: Commit**

```bash
git add sun_controller.gd
git commit -m "Strengthen and widen the golden hour"
```

---

## Task 5: Tuning pass + spec verification

**Files:**
- Modify: `main.tscn` / `sun_controller.gd` (tuned values from feedback)
- Modify: `docs/superpowers/specs/2026-06-08-atmosphere-stage2-design.md`

- [ ] **Step 1: Apply tuning from the user's reports**

Common adjustments:
- Glow too strong / walls blooming → raise `glow_hdr_threshold` (e.g. 1.3) or lower
  `glow_strength`. Too weak → lower threshold (e.g. 0.9).
- Haze too thick → lower `fog_density` (e.g. 0.006); too thin → raise (e.g. 0.02).
- Dust shafts too strong/foggy or fps drop → lower `volumetric_fog_density`
  (e.g. 0.006) and/or the lights' `light_volumetric_fog_energy`; if fps still bad,
  set `volumetric_fog_enabled = false` to drop the feature.
- Golden hour over/under → adjust the `dawn`/`dusk` colours or the warmth exponent.

Re-run + re-ask until day and night both read well and fps is fine.

- [ ] **Step 2: Record verification in the spec**

Append to the spec's Verification section, e.g.:
`Verified 2026-06-08: glow on bright emitters, faint window dust-shafts by day,
time-tinted haze, golden sunrise/sunset, dark night, fps fine — values tuned.`

- [ ] **Step 3: Commit**

```bash
git add main.tscn sun_controller.gd docs/superpowers/specs/2026-06-08-atmosphere-stage2-design.md
git commit -m "Tune atmosphere and record stage 2 verification"
```

---

## Self-Review notes
- **Spec coverage:** Glow → Task 1. Light volumetric god-rays → Task 3 (Env + light
  energies). Cheap time-tinted haze → Task 2 (Env fog + `sun_controller` tint).
  Golden hour → Task 4. Perf knobs (volumetric density, can disable) → Tasks 3 & 5.
  Night-stays-dark guardrail → fog night colour cool/dim (Task 2), volumetric only
  scatters night-zero sun/beam (Task 3). All spec goals mapped; out-of-scope items
  (auto-exposure, soft shadows, clouds, blue-hour) excluded.
- **Type/name consistency:** `_fog_color(daylight, horizon_warmth)`, `fog_day_color`,
  `fog_night_color`, `fog_sunset_color`, and `_sun_color(day_t, horizon_warmth,
  daylight)` match their call sites. `horizon_warmth` is the existing local in
  `_apply_time_of_day`; Task 4 changes its exponent in place (still in scope for the
  `_fog_color` call in Task 2, which uses the same value).
- **Order:** Task 2 references `horizon_warmth`; Task 4 only changes its exponent,
  not its name, so Task 2's call stays valid regardless of order.
- **Headless caveat:** all visual results need USER TESTS; tuning in Task 5.

# Camera & Light Stage 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add gentle bounded auto-exposure ("eye adjusts"), soften shadow edges, and tune shadow distance for the small interior — without brightening the night.

**Architecture:** All scene/project settings. A `CameraAttributesPractical` sub-resource on the `WorldEnvironment` adds clamped, slow auto-exposure. The `Sun`/`Moon` directional lights get an angular size + blur + a sensible shadow max-distance; project settings raise soft-shadow filter quality so all shadows get clean soft edges. No script changes.

**Tech Stack:** Godot 4.6 (CameraAttributesPractical, directional light shadow params, project shadow-quality settings). Verification: `godot` MCP (`run_project`/`get_debug_output`) for load errors **plus in-engine USER TESTS** (no headless screenshot).

**Reference — current scene:**
- `main.tscn`: `[node name="WorldEnvironment" ...] environment = SubResource("Env")`
  (no `camera_attributes`).
- `Sun` DirectionalLight3D (script `sun_controller.gd`, `shadow_enabled = true`,
  default shadow params).
- `Moon` DirectionalLight3D (`light_color = Color(0.6,0.7,1,1)`,
  `shadow_enabled = true`).
- `project.godot` has a `[rendering]` section (other keys present).

---

## File Structure
- Modify: `main.tscn` — `CameraAttributesPractical` sub-resource +
  `WorldEnvironment.camera_attributes`; soft-shadow params on `Sun` and `Moon`.
- Modify: `project.godot` — `[rendering]` soft-shadow filter quality.
- Modify: `docs/superpowers/specs/2026-06-08-camera-stage3-design.md` — verify note.

---

## Task 1: Soft shadows (sun/moon + global quality)

**Files:**
- Modify: `project.godot` (`[rendering]`)
- Modify: `main.tscn` (`Sun`, `Moon` nodes)

- [ ] **Step 1: Raise soft-shadow filter quality**

Open `project.godot`. In the existing `[rendering]` section, add these two keys
(if the section is absent, add it at the end of the file):

```
[rendering]
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=3
lights_and_shadows/positional_shadow/soft_shadow_filter_quality=3
```

(Quality 3 = High: clean penumbra without the cost of Ultra. Keep any keys already
in `[rendering]`; just add these.)

- [ ] **Step 2: Give the Sun a soft, crisp-near shadow**

On the `Sun` node in `main.tscn`, add these properties (after `shadow_enabled = true`):

```
light_angular_distance = 1.5
shadow_blur = 1.5
directional_shadow_mode = 0
directional_shadow_max_distance = 25.0
```

(`light_angular_distance` gives a real penumbra that widens with distance;
`directional_shadow_mode = 0` is a single orthogonal split — crisp for a small
interior; `max_distance = 25` suits the flat so detail isn't spread thin.)

- [ ] **Step 3: Soften the Moon shadow**

On the `Moon` node in `main.tscn`, add (after `shadow_enabled = true`):

```
light_angular_distance = 2.5
shadow_blur = 2.0
directional_shadow_max_distance = 25.0
```

- [ ] **Step 4: Run and check for errors**

`run_project` on `C:/Room45`, then `get_debug_output`. Expected: loads, no errors.
`stop_project`.

- [ ] **Step 5: USER TEST — soft shadows**

Ask the user: are shadow edges now **soft** (a gentle penumbra) rather than hard
and pixelated, while **near shadows stay reasonably crisp**? Check both a sunlit
daytime shadow and (if the chandelier is on) lamp shadows. Report if too blurry or
still too hard, and fps.

- [ ] **Step 6: Commit**

```bash
git add project.godot main.tscn
git commit -m "Soft shadows: sun/moon penumbra + higher filter quality"
```

---

## Task 2: Gentle bounded auto-exposure

**Files:**
- Modify: `main.tscn` (new `CameraAttributesPractical` sub-resource;
  `WorldEnvironment.camera_attributes`)

- [ ] **Step 1: Add the camera attributes sub-resource**

In `main.tscn`, add a sub-resource near the `Env` sub-resource (anywhere in the
sub-resource block, e.g. right after the `[sub_resource type="Environment" id="Env"]`
block ends):

```
[sub_resource type="CameraAttributesPractical" id="CamAttr"]
auto_exposure_enabled = true
auto_exposure_min_sensitivity = 50.0
auto_exposure_max_sensitivity = 320.0
auto_exposure_scale = 0.5
auto_exposure_speed = 0.5
```

(Narrow sensitivity range + slow speed = a gentle ease; the capped
`max_sensitivity` stops the dark/night from auto-brightening.)

- [ ] **Step 2: Attach it to the WorldEnvironment**

On the `WorldEnvironment` node in `main.tscn`, add under `environment = SubResource("Env")`:

```
camera_attributes = SubResource("CamAttr")
```

- [ ] **Step 3: Run and check for errors**

`run_project`, `get_debug_output`. Expected: no errors. `stop_project`.

- [ ] **Step 4: USER TEST — eye adapts, night stays dark**

Ask the user to:
- Look at the bright window, then turn to a dark corner — the view should **gently
  ease** brighter over a moment (and darker when turning back), not snap.
- Confirm **night is still dark** (no auto-brightening to daylight levels).
Report if the ease is too strong/weak (`auto_exposure_scale`, `_speed`) or if night
lifts too much (lower `auto_exposure_max_sensitivity`).

- [ ] **Step 5: Commit**

```bash
git add main.tscn
git commit -m "Add gentle bounded auto-exposure (eye adapts, night stays dark)"
```

---

## Task 3: Tuning pass + spec verification

**Files:**
- Modify: `main.tscn` / `project.godot` (tuned values)
- Modify: `docs/superpowers/specs/2026-06-08-camera-stage3-design.md`

- [ ] **Step 1: Apply tuning from the user's reports**

Common adjustments:
- Shadows too blurry → lower `light_angular_distance` / `shadow_blur`; too hard →
  raise them, or bump filter quality to 4.
- Near shadows muddy → lower `directional_shadow_max_distance` (e.g. 18).
- Exposure ease too strong / pumping → lower `auto_exposure_scale` (e.g. 0.35) and
  `auto_exposure_speed` (e.g. 0.3).
- Night lifts too much → lower `auto_exposure_max_sensitivity` (e.g. 220) or, if
  unwanted entirely, set `auto_exposure_enabled = false`.
- fps drop from shadow quality → drop filter quality to 2.

Re-run + re-ask until it reads well day and night with fps fine.

- [ ] **Step 2: Record verification in the spec**

Append to the spec's Verification section, e.g.:
`Verified 2026-06-08: soft shadow penumbra with crisp near shadows, gentle eye-adapt
exposure, night stays dark, fps fine — values tuned.`

- [ ] **Step 3: Commit**

```bash
git add main.tscn project.godot docs/superpowers/specs/2026-06-08-camera-stage3-design.md
git commit -m "Tune camera/shadows and record stage 3 verification"
```

---

## Self-Review notes
- **Spec coverage:** Bounded auto-exposure → Task 2 (capped `max_sensitivity`,
  slow speed). Soft shadows (sun/moon penumbra + global quality) → Task 1. Shadow
  distance tuning → Task 1 (`directional_shadow_max_distance`, single-split mode).
  Night-stays-dark guardrail → capped sensitivity (Task 2). All spec goals mapped;
  out-of-scope (clouds, blue-hour, DOF, per-time exposure scripting) excluded.
- **Type/name consistency:** `CameraAttributesPractical` id `CamAttr` is referenced
  by `WorldEnvironment.camera_attributes = SubResource("CamAttr")`. Property names
  (`auto_exposure_*`, `light_angular_distance`, `shadow_blur`,
  `directional_shadow_mode`, `directional_shadow_max_distance`,
  `soft_shadow_filter_quality`) are the real Godot 4 names.
- **No script changes:** `sun_controller` keeps driving light energies/shadow_enabled;
  these are additive node/project settings, so day/night logic is untouched.
- **Headless caveat:** every visual result needs a USER TEST; tuning in Task 3.

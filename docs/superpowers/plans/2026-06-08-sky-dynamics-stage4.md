# Sky Dynamics Stage 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the sky to life — drifting procedural clouds, a blue-hour twilight, moon phases, and rare shooting stars — all in the sky shader, driven by the existing time-of-day controller.

**Architecture:** Extend `sky.gdshader` with cloud/twilight/moon-phase/shooting-star math behind new uniforms (sky-only, no room-light changes). `sun_controller.gd` feeds three new per-frame uniforms — `cloud_tint` (from the sun colour), `twilight` (from daylight), `moon_phase` (from the GameClock day) — alongside the existing sky uniforms.

**Tech Stack:** Godot 4.6 sky shader (GLSL-like), GDScript. Verification: `godot` MCP (`run_project`/`get_debug_output`) for compile/load errors **plus in-engine USER TESTS** across day/sunset/night (no headless screenshot).

**Reference — current state:**
- `sky.gdshader` (full current content is the day/night sky with `hash13`, stars,
  Milky Way, moon disk, ground). Task 1 replaces it wholesale.
- `sun_controller.gd` `_apply_time_of_day()` already has a block:
  ```gdscript
  if _sky_material != null:
      _sky_material.set_shader_parameter("sun_dir", -ray_dir)
      _sky_material.set_shader_parameter("daylight", daylight)
  ```
  and computes `color` (sun colour) and reads `GameClock`. `moon_dir` is set later.
- `GameClock.get_datetime()` returns a Dictionary containing `"day"`.

---

## File Structure
- Modify: `sky.gdshader` — add clouds, twilight, moon phase, shooting stars + uniforms.
- Modify: `sun_controller.gd` — feed `cloud_tint`, `twilight`, `moon_phase`.
- Modify: `docs/superpowers/specs/2026-06-08-sky-dynamics-stage4-design.md` — verify note.

---

## Task 1: Rewrite `sky.gdshader` with the dynamic features

**Files:**
- Modify: `sky.gdshader` (full replace)

- [ ] **Step 1: Replace the shader**

Overwrite `sky.gdshader` with exactly:

```glsl
shader_type sky;
render_mode use_debanding;

// Set every frame by sun_controller.gd
uniform vec3 sun_dir = vec3(0.0, 0.3, 1.0);
uniform vec3 moon_dir = vec3(0.0, 0.3, -1.0);
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform float twilight : hint_range(0.0, 1.0) = 0.0;
uniform float moon_phase : hint_range(0.0, 1.0) = 0.0;
uniform vec3 cloud_tint : source_color = vec3(1.0, 0.6, 0.4);

uniform vec3 day_zenith : source_color = vec3(0.17, 0.35, 0.72);
uniform vec3 day_horizon : source_color = vec3(0.64, 0.76, 0.93);
uniform vec3 night_zenith : source_color = vec3(0.010, 0.015, 0.040);
uniform vec3 night_horizon : source_color = vec3(0.030, 0.050, 0.100);
uniform vec3 twilight_color : source_color = vec3(0.06, 0.09, 0.22);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 moon_color : source_color = vec3(0.70, 0.78, 0.95);
uniform float sun_size : hint_range(0.0, 0.2) = 0.015;
uniform float moon_size : hint_range(0.0, 0.2) = 0.030;
uniform float star_amount : hint_range(0.9, 1.0) = 0.985;
uniform float milky_way_strength : hint_range(0.0, 1.0) = 0.6;
uniform vec3 ground_color : source_color = vec3(0.10, 0.09, 0.08);

uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_speed = 0.006;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.9;
uniform vec3 cloud_day_color : source_color = vec3(0.92, 0.93, 0.96);
uniform vec3 cloud_night_color : source_color = vec3(0.04, 0.05, 0.09);
uniform float shooting_star_rate = 0.08;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);

	// --- Day gradient + sun ---
	vec3 day = mix(day_horizon, day_zenith, pow(up, 0.6));
	float sd = dot(dir, normalize(sun_dir));
	float sun_disk = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.5, sd);
	float sun_glow = pow(max(sd, 0.0), 120.0) * 0.6;
	day += sun_color * (sun_disk * 8.0 + sun_glow);

	// --- Night gradient + stars + Milky Way + moon ---
	vec3 night = mix(night_horizon, night_zenith, pow(up, 0.8));

	vec3 cell = floor(dir * 250.0);
	float rnd = hash13(cell);
	float star = step(star_amount, rnd);
	float twinkle = 0.65 + 0.35 * sin(TIME * 3.0 + rnd * 120.0);
	float star_fade = smoothstep(0.02, 0.30, dir.y);
	night += vec3(1.0) * (star * twinkle * star_fade);

	float band = smoothstep(0.22, 0.0, abs(dot(dir, normalize(vec3(0.7, 0.25, 0.6)))));
	float band_noise = hash13(floor(dir * 70.0));
	night += vec3(0.05, 0.06, 0.10) * band * band_noise * milky_way_strength * star_fade;

	// Moon with a phase terminator (shadow disk slides across the face).
	vec3 mo = normalize(moon_dir);
	float md = dot(dir, mo);
	float moon_glow = pow(max(md, 0.0), 180.0) * 0.4;
	vec3 up_ref = abs(mo.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 mtx = normalize(cross(up_ref, mo));
	vec3 mty = cross(mo, mtx);
	vec2 muv = vec2(dot(dir, mtx), dot(dir, mty)) / max(moon_size, 0.0001);
	float in_disk = step(length(muv), 1.0) * step(0.0, md);
	float shadow_x = (moon_phase * 2.0 - 1.0) * 2.0;
	float shadow = step(length(muv - vec2(shadow_x, 0.0)), 1.0);
	float moon_lit = in_disk * (1.0 - shadow);
	night += moon_color * (moon_lit * 3.0 + moon_glow);

	// Rare shooting star (night only; faded out by daylight at the end).
	float t = TIME * shooting_star_rate;
	float bucket = floor(t);
	float prog = fract(t);
	if (hash12(vec2(bucket, 7.3)) > 0.78 && dir.y > 0.1) {
		vec2 suv = dir.xz / max(dir.y, 0.25);
		vec2 sp = vec2(hash12(vec2(bucket, 1.7)), hash12(vec2(bucket, 2.9))) * 3.0 - 1.5;
		vec2 sdir = normalize(vec2(1.0, -0.5));
		vec2 head = sp + sdir * (prog * 2.0 - 1.0);
		float dline = length(suv - head);
		float streak = smoothstep(0.05, 0.0, dline) * smoothstep(0.0, 0.15, prog) * smoothstep(1.0, 0.85, prog);
		night += vec3(1.0) * streak * star_fade;
	}

	// --- Clouds (sky-only, drifting, fade near the horizon) ---
	float cloud_amt = 0.0;
	if (dir.y > 0.04) {
		vec2 cuv = (dir.xz / dir.y) * 0.55 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.3);
		float n = fbm(cuv);
		cloud_amt = smoothstep(cloud_coverage, cloud_coverage + 0.22, n);
		cloud_amt *= smoothstep(0.04, 0.30, dir.y);
	}

	vec3 sky_col = mix(night, day, daylight);

	// Clouds lit by time of day, warm-tinted toward the sun at sunset.
	float sun_near = pow(max(sd, 0.0), 4.0);
	vec3 cloud_lit = mix(cloud_night_color, cloud_day_color, daylight);
	cloud_lit = mix(cloud_lit, cloud_tint, sun_near * daylight * 0.7);
	sky_col = mix(sky_col, cloud_lit, cloud_amt * cloud_opacity);

	// Blue hour: tint the lower sky deep blue during twilight.
	float low = 1.0 - smoothstep(0.0, 0.5, dir.y);
	sky_col = mix(sky_col, twilight_color, twilight * low * 0.6);

	// Below the horizon, ground (neutral) so downward reflections aren't blue.
	vec3 ground = ground_color * (0.25 + 0.75 * daylight);
	float horizon = smoothstep(0.0, 0.12, dir.y);
	COLOR = mix(ground, sky_col, horizon);
}
```

- [ ] **Step 2: Run and check the shader compiles**

`run_project` on `C:/Room45`, then `get_debug_output`. Expected: NO shader compile
errors (pre-existing warnings in other files are fine). `stop_project`.

- [ ] **Step 3: USER TEST — clouds + moon shape**

Ask the user, by day: are there soft clouds drifting slowly across the sky (fading
out near the horizon, none below it)? By night: does the moon now show a **shape**
(not always a full disc)? (Cloud sunset tint, blue hour, and phase-by-day come once
`sun_controller` drives them in Task 2 — with defaults the moon is full and clouds
are neutral.) Report cloud amount/speed for tuning.

- [ ] **Step 4: Commit**

```bash
git add sky.gdshader
git commit -m "Add clouds, blue hour, moon phases and shooting stars to the sky shader"
```

---

## Task 2: Drive the new uniforms from sun_controller

**Files:**
- Modify: `sun_controller.gd`

- [ ] **Step 1: Feed cloud tint, twilight, and moon phase**

In `sun_controller.gd`, in `_apply_time_of_day()`, replace the existing sky block:

```gdscript
	if _sky_material != null:
		_sky_material.set_shader_parameter("sun_dir", -ray_dir)
		_sky_material.set_shader_parameter("daylight", daylight)
```

with:

```gdscript
	if _sky_material != null:
		_sky_material.set_shader_parameter("sun_dir", -ray_dir)
		_sky_material.set_shader_parameter("daylight", daylight)
		# Clouds take the sun's colour so they warm up at sunrise/sunset.
		_sky_material.set_shader_parameter("cloud_tint", color)
		# Blue hour: peaks when the sun is just below the daytime threshold.
		var twilight := clampf(1.0 - absf(daylight - 0.22) / 0.22, 0.0, 1.0)
		_sky_material.set_shader_parameter("twilight", twilight)
		# Moon phase advances across in-game days (~29.5-day cycle).
		var dt := GameClock.get_datetime()
		var day_idx := float(dt.get("day", 0))
		_sky_material.set_shader_parameter("moon_phase", fposmod(day_idx / 29.5, 1.0))
```

(`moon_dir` continues to be set later in the existing moon block — unchanged.)

- [ ] **Step 2: Run and check for errors**

`run_project`, `get_debug_output`. Expected: no errors. `stop_project`.

- [ ] **Step 3: USER TEST — driven dynamics**

Ask the user to watch across time (scrub the clock if possible):
- **Sunset/sunrise:** clouds near the sun turn warm orange/pink; a deep-blue **blue
  hour** appears low in the sky during the dusk/dawn transition.
- **Night:** the moon shows a phase; occasionally a faint **shooting star** streaks
  by (rare — may need a minute of watching).
- Day still bright, night still dark.
Report twilight strength, cloud warmth, and shooting-star frequency for tuning.

- [ ] **Step 4: Commit**

```bash
git add sun_controller.gd
git commit -m "Drive cloud tint, blue hour and moon phase from time of day"
```

---

## Task 3: Tuning pass + spec verification

**Files:**
- Modify: `main.tscn` (`SkyMat` shader params) / `sun_controller.gd` (from feedback)
- Modify: `docs/superpowers/specs/2026-06-08-sky-dynamics-stage4-design.md`

- [ ] **Step 1: Apply tuning from the user's reports**

Shader params live on the `SkyMat` sub-resource in `main.tscn` as
`shader_parameter/<name>` lines. Common adjustments:
- More/fewer clouds → lower/raise `cloud_coverage` (lower = more cloud).
- Clouds drift too fast/slow → `cloud_speed`.
- Clouds too opaque → lower `cloud_opacity`.
- Blue hour too strong/weak → adjust the `0.6` weight in the shader's blue-hour line
  or the `twilight` window (`0.22`) in `sun_controller`.
- Shooting stars too frequent/rare → lower/raise `shooting_star_rate` (lower = rarer).
- Moon phase changes too fast/slow per day → adjust the `29.5` divisor.

Re-run + re-ask until day/sunset/night all read well.

- [ ] **Step 2: Record verification in the spec**

Append to the spec's Verification section, e.g.:
`Verified 2026-06-08: clouds drift and warm at sunset, blue hour at dusk/dawn, moon
shows phases by day, rare shooting stars at night, day bright + night dark, no
errors — values tuned.`

- [ ] **Step 3: Commit**

```bash
git add main.tscn sun_controller.gd docs/superpowers/specs/2026-06-08-sky-dynamics-stage4-design.md
git commit -m "Tune sky dynamics and record stage 4 verification"
```

---

## Self-Review notes
- **Spec coverage:** Clouds (drift, time-tint, sky-only, horizon fade) → Task 1
  shader + Task 2 `cloud_tint`. Blue hour / smoother twilight → Task 1
  (`twilight_color` blend) + Task 2 `twilight`. Moon phases → Task 1 terminator +
  Task 2 `moon_phase` from GameClock day. Shooting stars (rare, night) → Task 1.
  All spec goals mapped; out-of-scope (volumetric clouds, sun dimming, weather)
  excluded.
- **Type/name consistency:** uniforms `cloud_tint`, `twilight`, `moon_phase`,
  `cloud_coverage`, `cloud_speed`, `cloud_opacity`, `cloud_day_color`,
  `cloud_night_color`, `twilight_color`, `shooting_star_rate` match the
  `set_shader_parameter` names (Task 2) and `shader_parameter/` tuning (Task 3).
- **Guardrails:** clouds/stars gated by `dir.y` (none below horizon) and the night
  term is hidden by `daylight` so day stays clean; `moon_phase` only reshapes the
  disc, not moonlight (driven separately); `dt.get("day", 0)` guards a missing field.
- **Headless caveat:** all visual results need USER TESTS; tuning in Task 3.

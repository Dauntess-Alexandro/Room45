# Realistic sky — Stage 4: dynamics (clouds, blue hour, moon phases, shooting stars)

**Date:** 2026-06-08
**Scope:** Final stage of the sky/atmosphere effort. Bring the sky to life: drifting
procedural clouds, a deep-blue "blue hour" twilight phase with a smoother day↔night
transition, varying moon phases, and rare shooting stars. Sky-only (no room-light
changes). Stages 1 (sky), 2 (atmosphere) are done; Stage 3 (camera) was reverted.

## Current state
- `sky.gdshader` (`shader_type sky`): paints day/night from uniforms `sun_dir`,
  `moon_dir`, `daylight`, plus colours/sizes. Has day gradient + sun disk, night
  gradient + procedural stars (`hash13`) + Milky Way + twinkle (via `TIME`), moon
  disk + glow, and a ground colour below the horizon. Blends night→day by `daylight`.
- `sun_controller.gd` feeds the shader each frame: `sun_dir = -ray_dir`, `daylight`,
  `moon_dir` (from `_moon_progress`/arc). It already computes `daylight`, `day_t`,
  `height`, `horizon_warmth`, sun `color`, and reads `GameClock` for the hour.
- `GameClock.get_datetime()` provides hour/minute/second (used by `_game_hour`); a
  day index is available for moon phase (see below).

## Goals

### 1. Drifting clouds (sky-only)
- Procedural noise clouds in the sky shader, **slowly drifting** with `TIME`, only in
  the upper hemisphere (fade at the horizon, none below it).
- Tinted by time of day: white/grey by day, warm orange/pink near the sun at sunset
  (use a `cloud_tint` colour fed from the sun colour), faint/dark at night.
- Do NOT affect room lighting (no shadow/dimming). Exposed knobs: `cloud_coverage`,
  `cloud_speed`, cloud colours.

### 2. Blue hour + smoother twilight
- Add a distinct **deep-blue twilight** band to the sky during the transition just
  after sunset / before sunrise, and smooth the day↔night blend (warm → pink → blue
  → night) instead of a direct lerp.
- Driven by a `twilight` factor (0 at full day/night, 1 at the sunset/sunrise edge)
  fed from `sun_controller` (derived from `daylight`/sun height), plus a
  `twilight_color` uniform.

### 3. Moon phases
- A `moon_phase` uniform (0 = new … 0.5 = full … 1 = new) shapes the lit moon disk
  with a terminator (crescent/half/gibbous/full) instead of always-full.
- `sun_controller` advances the phase slowly across in-game **days** (from the
  GameClock day count), so it changes night to night, not within one night.

### 4. Rare shooting stars
- Occasional short streaks across the **night** sky, procedural and time-based, rare
  (long gaps), subtle. Faded out by `daylight` so they only show at night.
- Exposed: `shooting_star_rate` (how often) / brightness.

## Architecture / files
- Modify: `sky.gdshader` — add clouds, twilight colour blend, moon-phase terminator,
  shooting stars; new uniforms (`cloud_coverage`, `cloud_speed`, `cloud_day_color`,
  `cloud_night_color`, `cloud_tint`, `twilight`, `twilight_color`, `moon_phase`,
  `shooting_star_rate`). One file, one job: paint the sky.
- Modify: `sun_controller.gd` — each frame set `cloud_tint` (from sun colour),
  `twilight` (from daylight/height), and `moon_phase` (from GameClock day index);
  small additions to the existing sky-uniform block in `_apply_time_of_day`.

## Interfaces
- `sun_controller` → sky shader: existing `sun_dir`/`moon_dir`/`daylight` plus new
  `cloud_tint`, `twilight`, `moon_phase`.
- All look knobs (coverage, speed, colours, star rate) are shader uniforms tuned in
  the `SkyMat` sub-resource.

## Error handling / guardrails
- Clouds/stars fade with `daylight` and the horizon so they never appear below ground
  or wash out the day; sky-only, so no risk to room lighting or night darkness.
- Moon phase only changes the moon disk's lit shape, not its light energy (moonlight
  stays driven by `sun_controller` as today).
- If GameClock exposes no day index, derive one from total elapsed hours; guard the
  call so a missing field can't crash (fallback day = 0).
- All new uniforms have shader defaults, so the sky still renders if `sun_controller`
  doesn't set one.

## Out of scope
Volumetric/3D clouds, clouds dimming the sun (room light), weather/rain, aurora.

## Verification
- `godot` MCP `run_project` + `get_debug_output`: loads with no shader/script errors.
- In-engine USER TESTS across day/sunset/night: clouds drift and tint correctly, blue
  hour reads at dusk/dawn, the moon shows a phase, rare shooting stars appear at
  night, day still bright and night still dark. Coverage, speed, twilight strength,
  phase, and star rate tuned from feedback (cannot be seen headless).

**Verified 2026-06-08:** Clouds drift and read well, sunset/blue-hour and moon phase
work, day bright + night dark, no errors — user approved at default tuning.

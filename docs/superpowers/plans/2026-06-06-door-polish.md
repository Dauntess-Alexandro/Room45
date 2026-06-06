# Door Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `SimpleWoodDoor` feel physical — animate the handle lever, give the leaf a slight settle, and drive the creak volume/pitch from the leaf's speed.

**Architecture:** All logic lives in `interactable.gd` under `kind == DOOR`. We mirror the existing light-switch pattern (capture a rest `Basis`, tween a tilt via `tween_method` about a local axis) for the handle. The leaf swing gains an overshoot-and-settle. A per-frame `_process` loop modulates the existing `DoorSound` player while the leaf moves. New behaviour is gated so a door with no handle node still works exactly as today.

**Tech Stack:** Godot 4.6, GDScript, `godot` MCP (`run_project`, `get_debug_output`, screenshot) for verification. Godot binary: `C:\tools\godot`.

**Verification model:** This codebase has no unit-test framework. Each task ends by running the project via the `godot` MCP, confirming behaviour on a screenshot and checking `get_debug_output` for zero new errors, then committing. Audio cannot be heard headless — creak correctness is verified by code review + absence of runtime errors.

**Key facts (already confirmed):**
- Door scene: `models/simple_wood_door.tscn` → `StaticBody3D` with `interactable.gd`, `kind = DOOR`.
- `DoorSound` is an `AudioStreamPlayer3D` child (path `NodePath("DoorSound")`).
- Door model `models/simple_wood_door.glb` has a separate handle node named `#DOR0001_Handles_0` (child `Object_4`). It matches the glob `*Handles*`.
- The handle node's pivot/axis are NOT yet known — Task 2 calibrates them in-engine.
- Current swing: `_toggle_door()` tweens `rotation:y` 0↔`deg_to_rad(door_open_angle)` over `door_anim_time`, `TRANS_CUBIC`/`EASE_OUT`.

---

## File Structure

- Modify: `interactable.gd` — new exported vars, internal state, handle lookup, handle tween, settle easing, creak modulation. All additions confined to the `Door` group and the door functions.
- Modify: `models/simple_wood_door.tscn` — set calibrated handle axis/angle values (only if defaults need overriding after Task 2).
- Modify: `docs/superpowers/specs/2026-06-06-door-polish-design.md` — none planned; spec stays as the source of truth.

No new files. No model/asset changes. No changes to other `Interactable` kinds.

---

## Task 1: Add exported vars, internal state, and handle lookup (no behaviour change)

**Files:**
- Modify: `interactable.gd` (Door export group ~lines 25-32; internal state ~lines 55-57; `_ready` ~lines 65-69)

- [ ] **Step 1: Extend the Door export group**

In `interactable.gd`, replace the Door export group (currently lines 25-32):

```gdscript
@export_group("Door")
@export var door_open_angle: float = 95.0   ## degrees
@export var door_anim_time: float = 0.6      ## seconds
@export var door_settle_degrees: float = 2.5 ## extra overshoot past the open angle, then ease back (0 = clean stop)
@export var door_sound_player_path: NodePath ## AudioStreamPlayer3D used for door open/close sounds
@export var door_open_sound_start: float = 0.0
@export var door_open_sound_duration: float = 0.0
@export var door_close_sound_start: float = 0.0
@export var door_close_sound_duration: float = 0.0
## Creak modulation: while the leaf moves, DoorSound pitch/volume follow its speed.
@export var creak_pitch_min: float = 0.85
@export var creak_pitch_max: float = 1.10
@export var creak_volume_min_db: float = -16.0
@export var creak_volume_max_db: float = 0.0
@export var creak_speed_for_max: float = 3.0 ## leaf angular speed (rad/s) mapped to the loudest/highest creak

@export_group("Door Handle")
## Name fragment used to find the lever node inside the door model (case-insensitive glob "*<hint>*").
@export var handle_node_hint: String = "Handles"
@export var handle_press_axis: Vector3 = Vector3(0, 0, 1) ## local axis the lever rotates about
@export var handle_press_degrees: float = 35.0            ## how far the lever presses down
@export var handle_press_time: float = 0.15              ## time to press down
@export var handle_return_time: float = 0.28             ## time to spring back up
```

- [ ] **Step 2: Add internal state**

Replace the door internal-state lines (currently lines 55-57):

```gdscript
# --- Internal state ----------------------------------------------------------
var _door_open: bool = false
var _door_tween: Tween
var _door_sound_generation: int = 0
var _door_sound_player: AudioStreamPlayer3D
var _door_sound_base_db: float = 0.0
var _creak_active: bool = false
var _prev_door_rot: float = 0.0
var _handle_node: Node3D
var _handle_rest_basis: Basis
var _handle_rest_captured: bool = false
var _handle_angle: float = 0.0
var _handle_tween: Tween
```

- [ ] **Step 3: Resolve handle + sound player in `_ready`**

Replace `_ready()` (currently lines 65-69):

```gdscript
func _ready() -> void:
	_saved_energy = default_light_energy
	if kind == Kind.LIGHT_SWITCH and not switch_visual_path.is_empty():
		_capture_switch_rest()
		call_deferred("_sync_light_switch_visual")
	if kind == Kind.DOOR:
		_resolve_door_nodes()
	set_process(false)
```

Add these helpers right after `_ready()`:

```gdscript
func _resolve_door_nodes() -> void:
	if not door_sound_player_path.is_empty():
		_door_sound_player = get_node_or_null(door_sound_player_path) as AudioStreamPlayer3D
		if _door_sound_player != null:
			_door_sound_base_db = _door_sound_player.volume_db
	if handle_node_hint.strip_edges() != "":
		for node in find_children("*%s*" % handle_node_hint, "Node3D", true, false):
			_handle_node = node as Node3D
			if _handle_node != null:
				_handle_rest_basis = _handle_node.transform.basis
				_handle_rest_captured = true
				break
```

- [ ] **Step 4: Run the project and verify it still loads**

Use the `godot` MCP: `run_project` on `C:/Room45`, then `get_debug_output`.
Expected: project launches, the room renders, NO new errors/warnings mentioning `interactable.gd`, the handle node, or null access. Door still opens/closes as before (behaviour unchanged this task). Then `stop_project`.

- [ ] **Step 5: Commit**

```bash
git add interactable.gd
git commit -m "Add door handle + creak exported vars and node lookup"
```

---

## Task 2: Animate the handle lever (press down, spring back) + calibrate

**Files:**
- Modify: `interactable.gd` (`_toggle_door` ~lines 88-98; add handle helpers)
- Possibly modify: `models/simple_wood_door.tscn` (calibrated values)

- [ ] **Step 1: Add the handle animation functions**

Add after `_resolve_door_nodes()` (or anywhere in the Door section):

```gdscript
func _animate_handle() -> void:
	if _handle_node == null or not _handle_rest_captured:
		return
	if _handle_tween != null and _handle_tween.is_running():
		_handle_tween.kill()
	var start_deg := _handle_angle
	_handle_tween = create_tween()
	_handle_tween.tween_method(_apply_handle_angle, start_deg, handle_press_degrees, handle_press_time) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_handle_tween.tween_method(_apply_handle_angle, handle_press_degrees, 0.0, handle_return_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _apply_handle_angle(deg: float) -> void:
	_handle_angle = deg
	if _handle_node == null:
		return
	var axis := handle_press_axis.normalized()
	if axis.is_zero_approx():
		axis = Vector3(0, 0, 1)
	_handle_node.transform.basis = _handle_rest_basis * Basis(axis, deg_to_rad(deg))
```

- [ ] **Step 2: Call the handle animation from `_toggle_door`**

In `_toggle_door()`, add `_animate_handle()` right after `_play_door_sound(_door_open)`:

```gdscript
func _toggle_door() -> void:
	_door_open = not _door_open
	var target_rotation: float = deg_to_rad(door_open_angle) if _door_open else 0.0
	_play_door_sound(_door_open)
	_animate_handle()

	# Restart any in-progress swing so rapid presses stay responsive.
	if _door_tween != null and _door_tween.is_running():
		_door_tween.kill()

	_door_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_door_tween.tween_property(self, "rotation:y", target_rotation, door_anim_time)
```

(The settle change to this tween comes in Task 3 — leave it plain for now.)

- [ ] **Step 3: Run and observe the handle**

`run_project`, walk/look toward the door is not needed — instead, the door is in view at spawn per the project's start. Trigger isn't scriptable headless, so verification is visual on the editor screenshot of the door at rest plus a code review of the rotation. Use `get_debug_output` to confirm no errors. If the lever's resting pose looks unchanged and no errors appear, the wiring is correct.

> Practical calibration: the unknowns are `handle_press_axis` and whether the lever's pivot sits at the spindle. To calibrate quickly, temporarily set `handle_press_degrees` large (e.g. 60) and in `_resolve_door_nodes` temporarily call `_apply_handle_angle(handle_press_degrees)` at the end so the lever is shown pressed at startup. `run_project`, screenshot, and check:
> - **Right axis?** The lever should rotate down in the door's plane (tip dips toward the floor), not twist into/out of the door. If it twists wrong, try `handle_press_axis = Vector3(1,0,0)` or `Vector3(0,1,0)` until the dip looks right.
> - **Right pivot?** The lever should rotate about where it meets the door (the round rose), the far tip swinging down. If instead the whole handle orbits the door's hinge edge, the handle node origin is offset: wrap it — in `models/simple_wood_door.tscn` add an intermediate `Node3D` ("HandlePivot") positioned at the spindle, reparent the handle model under it, and point `handle_node_hint`/lookup at the pivot. (Only do this if calibration shows it's needed.)
> Remove the temporary startup `_apply_handle_angle` call and restore `handle_press_degrees` to ~35 once the axis/pivot are correct.

- [ ] **Step 4: Persist calibrated values**

If the calibrated `handle_press_axis` / `handle_press_degrees` differ from the script defaults, set them in `models/simple_wood_door.tscn` on the `SimpleWoodDoor` node (e.g. `handle_press_axis = Vector3(1, 0, 0)`), so the model's correct values live with the scene.

- [ ] **Step 5: Run a final open/close check**

`run_project`, confirm via screenshot the lever rests correctly and `get_debug_output` shows no errors. `stop_project`.

- [ ] **Step 6: Commit**

```bash
git add interactable.gd models/simple_wood_door.tscn
git commit -m "Animate door handle lever on open/close"
```

---

## Task 3: Leaf settle (weight)

**Files:**
- Modify: `interactable.gd` (`_toggle_door` swing tween)

- [ ] **Step 1: Replace the swing tween with overshoot-and-settle**

In `_toggle_door()`, replace the final two lines (the `create_tween` + `tween_property`) with:

```gdscript
	_door_tween = create_tween()
	if _door_open and door_settle_degrees > 0.0:
		# Heavy door: swing a touch past the open angle, then ease back to rest.
		var overshoot := deg_to_rad(door_open_angle + door_settle_degrees)
		_door_tween.tween_property(self, "rotation:y", overshoot, door_anim_time * 0.82) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_door_tween.tween_property(self, "rotation:y", target_rotation, door_anim_time * 0.18) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_door_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_door_tween.tween_property(self, "rotation:y", target_rotation, door_anim_time)
```

(Overshoot is applied only when opening, so the door never swings past the closed position into the frame.)

- [ ] **Step 2: Run and sanity-check the open angle**

`run_project`, `get_debug_output`. Confirm no errors. Visually the door should not clip the wall — `door_open_angle` (95°) + `door_settle_degrees` (2.5°) = 97.5° peak; confirm on screenshot the leaf clears the wall. If it clips, lower `door_settle_degrees` in `models/simple_wood_door.tscn`. `stop_project`.

- [ ] **Step 3: Commit**

```bash
git add interactable.gd
git commit -m "Give the door leaf a slight settle when opening"
```

---

## Task 4: Motion-driven creak (pitch + volume follow leaf speed)

**Files:**
- Modify: `interactable.gd` (`_toggle_door` to start modulation; add `_process`)

- [ ] **Step 1: Start creak modulation when the swing begins**

At the very end of `_toggle_door()` (after the tween block), add:

```gdscript
	if _door_sound_player != null:
		_prev_door_rot = rotation.y
		_creak_active = true
		set_process(true)
```

- [ ] **Step 2: Add the per-frame modulation in `_process`**

Add this function (door-section):

```gdscript
func _process(delta: float) -> void:
	if not _creak_active:
		set_process(false)
		return
	# Angular speed of the leaf this frame (rad/s).
	var speed := 0.0
	if delta > 0.0:
		speed = absf(rotation.y - _prev_door_rot) / delta
	_prev_door_rot = rotation.y

	if _door_sound_player != null:
		var t := clampf(speed / maxf(creak_speed_for_max, 0.001), 0.0, 1.0)
		_door_sound_player.pitch_scale = lerpf(creak_pitch_min, creak_pitch_max, t)
		_door_sound_player.volume_db = lerpf(creak_volume_min_db, creak_volume_max_db, t)

	# Stop once the swing tween has finished.
	if _door_tween == null or not _door_tween.is_running():
		_creak_active = false
		if _door_sound_player != null:
			_door_sound_player.pitch_scale = 1.0
			_door_sound_player.volume_db = _door_sound_base_db
		set_process(false)
```

- [ ] **Step 3: Run and verify no runtime errors**

`run_project`, `get_debug_output`. Expected: no errors referencing `_process`, `pitch_scale`, or null player. The door opens/closes; the creak clip plays (audio not audible headless, so confirm via no-error + code review that `pitch_scale`/`volume_db` are restored after the swing). `stop_project`.

- [ ] **Step 4: Commit**

```bash
git add interactable.gd
git commit -m "Drive door creak pitch and volume from leaf speed"
```

---

## Task 5: Final pass + spec verification note

**Files:**
- Modify: `docs/superpowers/specs/2026-06-06-door-polish-design.md` (mark verification done)

- [ ] **Step 1: Full run-through**

`run_project`. Open and close the door a few times (the door is reachable at spawn). On screenshots confirm: handle dips then returns, leaf settles, no wall clip. `get_debug_output`: no errors across the session. `stop_project`.

- [ ] **Step 2: Note verification result in the spec**

Append a short "Verified 2026-06-06: handle animates, leaf settles, creak modulates with no runtime errors" line to the spec's Verification section.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-06-06-door-polish-design.md
git commit -m "Record door polish verification"
```

---

## Self-Review notes

- **Spec coverage:** Handle animation → Task 2. Weight/settle → Task 3. Motion-driven creak → Task 1 (vars/player cache) + Task 4. Graceful degrade when no handle → guarded in `_animate_handle`/`_apply_handle_angle` (null checks). All spec goals mapped.
- **Type consistency:** `_apply_handle_angle(deg: float)`, `_animate_handle()`, `_resolve_door_nodes()`, `_door_sound_player`, `_creak_active`, `_prev_door_rot` referenced consistently across Tasks 1, 2, 4.
- **Pattern match:** Handle uses the same rest-basis + `tween_method` + local-axis `Basis` approach as the existing light switch (`_apply_switch_tilt`), so it fits the codebase idiom.
- **No new errors path:** All new node access is null-guarded; `set_process(false)` default keeps `_process` idle until a swing.

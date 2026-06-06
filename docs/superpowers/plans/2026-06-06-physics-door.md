# Physics Door Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the tap-animated `SimpleWoodDoor` with a true physics door — a `RigidBody3D` leaf on a `HingeJoint3D` that the player pushes by holding the interact key and moving the mouse.

**Architecture:** The door scene becomes `Node3D` root → `DoorLeaf` (`RigidBody3D`, mesh + box collision + `DoorSound`) held by a sibling `HingeJoint3D` anchored to the world. A new `physics_door.gd` on the leaf exposes a small grab interface (`is_grabbable`, `get_prompt`, `grab_begin`, `grab_drive`, `grab_end`) and handles handle-press, creak, and slam feedback. `player.gd` gains a grab mode: while a door is grabbed, horizontal mouse motion drives the door instead of the camera.

**Tech Stack:** Godot 4.6, GDScript, `RigidBody3D`, `HingeJoint3D`. Verification via `godot` MCP (`run_project`, `get_debug_output`) for compile/load errors **plus mandatory in-engine USER TESTS** — mouse-driven physics cannot be exercised headless (no mouse injection, no screenshot).

**Critical unknowns (calibrated in-engine, flagged at each step):**
- `HingeJoint3D` swing axis orientation — set so the leaf hinges about vertical.
- Hinge angular-limit sign/direction — so closed = 0°, open = the room side.
- Mouse push sign — so moving the mouse one way opens, the other closes.
- Feel values (mass, damping, push strength, slam threshold) — tuned by the user.

**Reference — current files:**
- `models/simple_wood_door.tscn`: root `StaticBody3D` + `interactable.gd`, `Model` (GLB, scale 1.025, `simple_wood_door_cleanup.gd`), `Collision` (BoxShape3D size `(0.92, 2.02, 0.18)`, transform offset `(-0.452, 1.012, -0.017)`), `DoorSound` (`woodendoor.mp3`, unit_size 2.0, max_distance 8.0).
- `main.tscn:339-340`: instances the door under `Zal` at transform position `(0.86, 0, 2.35)`, no property overrides. **Root must stay a `Node3D` at the hinge origin so this placement still works — main.tscn needs no change.**
- Handle node inside the GLB: `#DOR0001_Handles_0` (matches `*Handles*`).
- `player.gd`: mouse look in `_unhandled_input`; `_update_interaction()` in `_physics_process`; prompt via `_refresh_prompt_text()` / `_set_prompt_visible()`; action name is `"interact"`.

---

## File Structure

- Create: `physics_door.gd` — all door physics + feedback, on the `DoorLeaf` RigidBody.
- Modify: `models/simple_wood_door.tscn` — full restructure into the physics rig.
- Modify: `player.gd` — grab mode (mouse routing + grab begin/end + generalized prompt).
- Modify: `docs/superpowers/specs/2026-06-06-physics-door-design.md` — verification note at the end.
- `interactable.gd` is **not** touched.

---

## Task 1: Create `physics_door.gd`

**Files:**
- Create: `physics_door.gd`

- [ ] **Step 1: Write the full script**

Create `physics_door.gd` with exactly this content:

```gdscript
class_name PhysicsDoor
extends RigidBody3D
## A door leaf you physically push: the player holds the interact key and moves
## the mouse to swing it. The leaf hangs on a HingeJoint3D defined in the scene.
## This script exposes the grab interface the player calls, plus handle-press,
## creak, and slam feedback. All feel values are exported for tuning.

@export_group("Grab")
@export var prompt: String = "HOLD TO MOVE DOOR"
@export var push_strength: float = 0.06   ## angular impulse per pixel of mouse movement
@export var max_push_impulse: float = 1.2 ## clamp per motion event (anti-tunnel / anti-spin)
@export var push_sign: float = 1.0        ## flip to -1 if the mouse opens the wrong way

@export_group("Handle")
@export var handle_node_hint: String = "Handles"
@export var handle_press_axis: Vector3 = Vector3(0, 0, 1)
@export var handle_press_degrees: float = -35.0
@export var handle_anim_time: float = 0.18

@export_group("Sound")
@export var sound_player_path: NodePath = NodePath("DoorSound")
@export var creak_clip_start: float = 0.0     ## seconds into woodendoor.mp3 for the creak
@export var creak_pitch_min: float = 0.85
@export var creak_pitch_max: float = 1.10
@export var creak_volume_min_db: float = -16.0
@export var creak_volume_max_db: float = 0.0
@export var creak_speed_for_max: float = 3.0  ## leaf speed (rad/s) mapped to loudest/highest
@export var creak_idle_speed: float = 0.12    ## below this the creak stops
@export var slam_clip_start: float = 4.0      ## seconds into the clip for the close/slam
@export var slam_speed_threshold: float = 2.0 ## leaf speed (rad/s) into the closed stop = slam
@export var closed_angle_epsilon: float = 0.07 ## rad; how close to 0 counts as "closed"

var _grabbed: bool = false
var _handle_node: Node3D
var _handle_rest_basis: Basis
var _handle_captured: bool = false
var _handle_angle: float = 0.0
var _handle_tween: Tween
var _sound: AudioStreamPlayer3D
var _sound_base_db: float = 0.0
var _slam_cooldown: float = 0.0


func _ready() -> void:
	_sound = get_node_or_null(sound_player_path) as AudioStreamPlayer3D
	if _sound != null:
		_sound_base_db = _sound.volume_db
	if handle_node_hint.strip_edges() != "":
		for node in find_children("*%s*" % handle_node_hint, "Node3D", true, false):
			_handle_node = node as Node3D
			if _handle_node != null:
				_handle_rest_basis = _handle_node.transform.basis
				_handle_captured = true
				break


# --- Player-facing grab interface -------------------------------------------
func is_grabbable() -> bool:
	return true


func get_prompt() -> String:
	return prompt


func grab_begin() -> void:
	_grabbed = true
	_tween_handle(handle_press_degrees)


func grab_drive(mouse_dx: float) -> void:
	if not _grabbed:
		return
	var impulse := clampf(mouse_dx * push_strength * push_sign, -max_push_impulse, max_push_impulse)
	# Torque about world up so the leaf swings around the vertical hinge.
	apply_torque_impulse(Vector3(0, impulse, 0))


func grab_end() -> void:
	_grabbed = false
	_tween_handle(0.0)


# --- Handle ------------------------------------------------------------------
func _tween_handle(target_deg: float) -> void:
	if _handle_node == null or not _handle_captured:
		return
	if _handle_tween != null and _handle_tween.is_running():
		_handle_tween.kill()
	_handle_tween = create_tween()
	_handle_tween.tween_method(_apply_handle_angle, _handle_angle, target_deg, handle_anim_time) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _apply_handle_angle(deg: float) -> void:
	_handle_angle = deg
	if _handle_node == null:
		return
	var axis := handle_press_axis.normalized()
	if axis.is_zero_approx():
		axis = Vector3(0, 0, 1)
	_handle_node.transform.basis = _handle_rest_basis * Basis(axis, deg_to_rad(deg))


# --- Creak + slam ------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if _slam_cooldown > 0.0:
		_slam_cooldown -= delta

	var speed := absf(angular_velocity.y)

	# Slam: arriving at the closed stop with speed.
	if absf(rotation.y) < closed_angle_epsilon and speed > slam_speed_threshold and _slam_cooldown <= 0.0:
		_play_slam()
		return

	if _sound == null:
		return
	if speed > creak_idle_speed:
		var t := clampf(speed / maxf(creak_speed_for_max, 0.001), 0.0, 1.0)
		if not _sound.playing:
			_sound.play(creak_clip_start)
		_sound.pitch_scale = lerpf(creak_pitch_min, creak_pitch_max, t)
		_sound.volume_db = lerpf(creak_volume_min_db, creak_volume_max_db, t)
	elif _sound.playing and _slam_cooldown <= 0.0:
		_sound.stop()
		_sound.pitch_scale = 1.0
		_sound.volume_db = _sound_base_db


func _play_slam() -> void:
	_slam_cooldown = 0.35
	if _sound == null:
		return
	_sound.pitch_scale = 1.0
	_sound.volume_db = _sound_base_db
	_sound.play(slam_clip_start)
```

- [ ] **Step 2: Verify it parses**

Run the `godot` MCP `run_project` on `C:/Room45`, then `get_debug_output`.
Expected: NO parse error for `physics_door.gd` (the class compiles even though it is not yet instanced anywhere). Pre-existing warnings in other files are fine. Then `stop_project`.

- [ ] **Step 3: Commit**

```bash
git add physics_door.gd
git commit -m "Add physics_door.gd: grab interface, handle, creak, slam"
```

---

## Task 2: Rebuild `simple_wood_door.tscn` into the physics rig

**Files:**
- Modify: `models/simple_wood_door.tscn` (full rewrite)

- [ ] **Step 1: Replace the scene with the physics rig**

Overwrite `models/simple_wood_door.tscn` with exactly:

```
[gd_scene load_steps=6 format=3]

[ext_resource type="PackedScene" path="res://models/simple_wood_door.glb" id="1_glb"]
[ext_resource type="Script" path="res://models/simple_wood_door_cleanup.gd" id="2_cleanup"]
[ext_resource type="Script" path="res://physics_door.gd" id="3_physics"]
[ext_resource type="AudioStream" path="res://sound/woodendoor.mp3" id="4_sound"]

[sub_resource type="BoxShape3D" id="DoorLeafShape"]
size = Vector3(0.92, 2.02, 0.18)

[node name="SimpleWoodDoor" type="Node3D"]

[node name="DoorLeaf" type="RigidBody3D" parent="."]
script = ExtResource("3_physics")
mass = 18.0
gravity_scale = 0.0
angular_damp = 2.5
continuous_cd = true
can_sleep = false

[node name="Model" parent="DoorLeaf" instance=ExtResource("1_glb")]
transform = Transform3D(1.025, 0, 0, 0, 1.025, 0, 0, 0, 1.025, 0, 0, 0)
script = ExtResource("2_cleanup")

[node name="Collision" type="CollisionShape3D" parent="DoorLeaf"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.452, 1.012, -0.017)
shape = SubResource("DoorLeafShape")

[node name="DoorSound" type="AudioStreamPlayer3D" parent="DoorLeaf"]
stream = ExtResource("4_sound")
unit_size = 2.0
max_distance = 8.0

[node name="Hinge" type="HingeJoint3D" parent="."]
node_a = NodePath("../DoorLeaf")
node_b = NodePath("")
```

Notes baked in:
- The hinge is at the root origin (identity transform) = the leaf's pivot edge, matching the old StaticBody pivot.
- `node_a` = the leaf, `node_b` empty = anchored to the world (so the leaf swings against the world).
- Limits are intentionally **off** for this task so we can confirm free rotation and the axis first.
- `gravity_scale = 0.0` so the closed door does not sag; the player's pushes move it.

- [ ] **Step 2: Run and check for load errors**

`run_project`, `get_debug_output`. Expected: scene loads, no errors about the joint, RigidBody, or missing nodes. `stop_project`.

- [ ] **Step 3: USER TEST — does the door hang correctly?**

Ask the user to run the game and look at the door, reporting:
- (a) Does the leaf stay in the doorway, roughly closed, without falling, sinking, or spinning on its own?
- (b) If they walk into it, does it swing around a **vertical** edge (like a real door) — or does it tip/rotate around a wrong axis?

Calibration from the report:
- **Spins/tips around the wrong axis** → the hinge axis is not vertical. Edit the `Hinge` node in `models/simple_wood_door.tscn` to add a rotation, trying in order: `transform = Transform3D(1, 0, 0, 0, 0, -1, 0, 1, 0, 0, 0, 0)` (rotate +90° about X), then the +90°-about-Z variant `Transform3D(0, -1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0)`. Re-run + re-ask until the leaf swings about vertical.
- **Door drifts/falls** → confirm `gravity_scale = 0.0` is set on `DoorLeaf`.
- **Door is rock-solid / cannot move at all** → the hinge axis is locking it; apply the same rotations above.

- [ ] **Step 4: Commit (with whatever hinge transform calibration landed)**

```bash
git add models/simple_wood_door.tscn
git commit -m "Rebuild door as RigidBody leaf on a HingeJoint3D"
```

---

## Task 3: Add grab mode to `player.gd`

**Files:**
- Modify: `player.gd` (state ~line 50; `_unhandled_input` ~lines 61-71; `_update_interaction` ~lines 129-159; `_refresh_prompt_text`)

- [ ] **Step 1: Add grab state and a grab-distance export**

In `player.gd`, under the `Movement` (or a new) export group near the other exports, add:

```gdscript
@export var grab_max_distance: float = 2.5  ## how far the player can be and still hold a physics door
```

And in the internal state block (after `var _current_target: Object = null`):

```gdscript
var _grabbed_door: Node = null
```

- [ ] **Step 2: Route mouse motion to the door while grabbing**

Replace the mouse-look block in `_unhandled_input` (currently lines 62-66):

```gdscript
	# Mouse look — unless we are holding a door, in which case the mouse pushes it.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _grabbed_door != null and is_instance_valid(_grabbed_door):
			_grabbed_door.grab_drive(event.relative.x)
		else:
			rotate_y(-event.relative.x * mouse_sensitivity)
			_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, min_pitch, max_pitch)
			camera.rotation.x = _pitch
```

- [ ] **Step 3: Rewrite `_update_interaction` to handle grab + tap**

Replace the whole `_update_interaction()` body (currently lines 129-159) with:

```gdscript
func _update_interaction() -> void:
	# While holding a door, the mouse drives it (see _unhandled_input). Stay in
	# grab mode until the key is released, the door is gone, or we walk too far.
	if _grabbed_door != null:
		var still_valid := is_instance_valid(_grabbed_door)
		var holding := Input.is_action_pressed("interact")
		var too_far := still_valid and global_position.distance_to(
			(_grabbed_door as Node3D).global_position) > grab_max_distance
		if not holding or too_far or not still_valid:
			if still_valid:
				_grabbed_door.grab_end()
			_grabbed_door = null
			_current_target = null
			_set_prompt_visible(false)
		return

	# Find what we are aiming at.
	var target: Object = null
	if interaction_ray.is_colliding():
		var collider := interaction_ray.get_collider()
		if collider is Interactable:
			target = collider
			var max_dist: float = (collider as Interactable).max_interact_distance
			if max_dist > 0.0:
				var dist := interaction_ray.global_position.distance_to(interaction_ray.get_collision_point())
				if dist > max_dist:
					target = null
		elif collider != null and collider.has_method("is_grabbable") and collider.is_grabbable():
			var gdist := interaction_ray.global_position.distance_to(interaction_ray.get_collision_point())
			if gdist <= grab_max_distance:
				target = collider

	# Update the prompt only when the target changes.
	if target != _current_target:
		_current_target = target
		if target != null:
			_refresh_prompt_text()
			_set_prompt_visible(true)
		else:
			_set_prompt_visible(false)

	if _current_target == null:
		return

	# Grabbable door: hold to grab. Everything else: tap to interact.
	if _current_target.has_method("is_grabbable") and _current_target.is_grabbable():
		if Input.is_action_pressed("interact"):
			_grabbed_door = _current_target
			_grabbed_door.grab_begin()
	elif Input.is_action_just_pressed("interact"):
		_current_target.interact(self)
		if not is_instance_valid(_current_target):
			_current_target = null
			_set_prompt_visible(false)
		else:
			_refresh_prompt_text()
```

- [ ] **Step 4: Generalize `_refresh_prompt_text` to any node with `get_prompt()`**

Replace `_refresh_prompt_text()`:

```gdscript
func _refresh_prompt_text() -> void:
	if prompt_label != null and _current_target != null and _current_target.has_method("get_prompt"):
		prompt_label.text = "[E]  " + _current_target.get_prompt()
```

- [ ] **Step 5: Run and check for errors**

`run_project`, `get_debug_output`. Expected: no errors. `stop_project`.

- [ ] **Step 6: USER TEST — grab and swing**

Ask the user to run the game, aim at the door (prompt should read `[E]  HOLD TO MOVE DOOR`), then **hold the interact key and move the mouse left/right**. Report:
- Does the door swing as the mouse moves, and keep momentum when the key is released?
- Does moving the mouse one way open it and the other way close it? If it opens the "wrong" way relative to the mouse, set `push_sign = -1.0` on the `DoorLeaf` node in `models/simple_wood_door.tscn`.
- Does the camera correctly freeze while holding, and resume on release?
- Any jitter, tunneling (door passing through the wall/frame), or the door flying off?

- [ ] **Step 7: Commit**

```bash
git add player.gd models/simple_wood_door.tscn
git commit -m "Add mouse-grab door mode to the player"
```

---

## Task 4: Hinge limits, slam, and feel tuning

**Files:**
- Modify: `models/simple_wood_door.tscn` (hinge limits + tuned values)

- [ ] **Step 1: Enable angular limits so the door stops at closed and fully-open**

In `models/simple_wood_door.tscn`, add to the `Hinge` node these properties (the
exact lower/upper signs depend on which way Task 3 confirmed "open" is):

```
angular_limit/enable = true
angular_limit/lower = 0.0
angular_limit/upper = 1.658
```

(`1.658` rad ≈ 95°. If Task 3 showed the door opens toward negative angles, use
`angular_limit/lower = -1.658` and `angular_limit/upper = 0.0` instead.)

- [ ] **Step 2: Run and check for errors**

`run_project`, `get_debug_output`. Expected: no errors. `stop_project`.

- [ ] **Step 3: USER TEST — limits, slam, weight**

Ask the user to push the door fully open and slam it closed, reporting:
- Does it stop cleanly at closed (≈ the frame) and at fully-open (≈ 95°) without
  passing through the wall or bouncing wildly?
- Does a fast close produce the slam/latch sound; a gentle close stay quiet?
- Does it feel like the right weight — too heavy / too floaty / too slippery?

Tune on the `DoorLeaf` node from the report:
- Too heavy to move → lower `mass` (e.g. 12) or raise `push_strength` (e.g. 0.09).
- Keeps spinning / never settles → raise `angular_damp` (e.g. 4.0).
- Stops too abruptly / feels sticky → lower `angular_damp` (e.g. 1.5).
- Slam never triggers → lower `slam_speed_threshold` (e.g. 1.2); triggers on every
  close → raise it (e.g. 3.0).
- Tunnels through the wall on a hard push → lower `max_push_impulse` (e.g. 0.8) and
  confirm `continuous_cd = true`.

Re-run + re-ask until it feels right.

- [ ] **Step 4: Commit final tuning**

```bash
git add models/simple_wood_door.tscn
git commit -m "Add door hinge limits and tune physics-door feel"
```

---

## Task 5: Spec verification note

**Files:**
- Modify: `docs/superpowers/specs/2026-06-06-physics-door-design.md`

- [ ] **Step 1: Append the verification result**

Add a line to the spec's Verification section recording the in-engine result, e.g.:
`Verified 2026-06-06: grab + swing works, hinge limits hold, slam reads, no jitter/tunneling after tuning.`

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-06-06-physics-door-design.md
git commit -m "Record physics door verification"
```

---

## Self-Review notes

- **Spec coverage:** RigidBody leaf + HingeJoint → Task 2. `physics_door.gd` grab
  interface (`is_grabbable`/`get_prompt`/`grab_begin`/`grab_drive`/`grab_end`) →
  Task 1, consumed in Task 3. Mouse-grab control + camera suspend → Task 3. Handle
  press while grabbed → Task 1 (`grab_begin`/`grab_end` → `_tween_handle`). Creak by
  angular speed + slam at closed → Task 1 (`_physics_process`/`_play_slam`), exercised
  in Task 4. Hinge limits / rest at any angle → Tasks 2+4. Guardrails (continuous_cd,
  clamped impulse, auto-release on key-up/too-far) → Tasks 1+3. Out-of-scope items
  (player push, other doors, locks) excluded. All spec points mapped.
- **Type/name consistency:** Method names `is_grabbable`, `get_prompt`, `grab_begin`,
  `grab_drive(mouse_dx)`, `grab_end` are identical in `physics_door.gd` (Task 1) and
  every call site in `player.gd` (Task 3). `_grabbed_door`, `grab_max_distance`,
  `push_sign` used consistently. `_refresh_prompt_text` works for both `Interactable`
  and `PhysicsDoor` via the `has_method("get_prompt")` check.
- **Calibration honesty:** Hinge axis, limit sign, and push sign are explicitly
  marked unknown and resolved by USER TESTS in Tasks 2-4 (cannot be verified headless).
- **No placeholders:** every code step shows complete code; tuning steps give concrete
  values and directions.

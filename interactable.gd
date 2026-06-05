class_name Interactable
extends StaticBody3D
## A single, configurable interactable object.
##
## Attach this script to a StaticBody3D so the player's RayCast3D can detect it.
## Pick a `kind` in the inspector (or in main.tscn) and the matching behaviour
## runs when the player presses E while looking at it:
##
##   DOOR         -> swings around its local Y axis (hinge at node origin).
##   LIGHT_SWITCH -> toggles the energy of the Light3D at `target_light_path`.
##   PICKUP       -> removes itself from the scene.
##   COMPUTER     -> opens the in-world CRT terminal.
##   COMPUTER_POWER -> toggles the terminal power state.
##
## The player reads `prompt_text` to populate the on-screen interaction prompt.

enum Kind { DOOR, LIGHT_SWITCH, PICKUP, COMPUTER, COMPUTER_POWER }

@export var kind: Kind = Kind.DOOR
## Shown next to the "[E]" indicator in the HUD.
@export var prompt_text: String = "INTERACT"

@export_group("Door")
@export var door_open_angle: float = 95.0   ## degrees
@export var door_anim_time: float = 0.6      ## seconds

@export_group("Light Switch")
@export var target_light_path: NodePath      ## Light3D to toggle
@export var target_light_paths: Array[NodePath] = []
@export var default_light_energy: float = 2.0

@export_group("Switch Visual")
@export var switch_visual_path: NodePath              ## Node3D that tilts (e.g. the rocker key)
@export var switch_tilt_axis: Vector3 = Vector3(1, 0, 0)  ## Hinge axis, in the visual's local space
@export var switch_on_tilt_degrees: float = -2.0      ## Tilt when the light is ON
@export var switch_off_tilt_degrees: float = 2.0      ## Tilt when the light is OFF
@export var switch_visual_anim_time: float = 0.09

@export_group("Computer")
@export var target_terminal_path: NodePath   ## Node with open_terminal(player)

@export_group("Sound")
@export var click_sound: AudioStream         ## Played on each switch toggle
@export var click_player_path: NodePath      ## AudioStreamPlayer3D used to play it

# --- Internal state ----------------------------------------------------------
var _door_open: bool = false
var _door_tween: Tween
var _switch_visual_tween: Tween
var _saved_energy: float = 2.0
var _switch_rest_basis: Basis
var _switch_rest_captured: bool = false
var _switch_angle: float = 0.0


func _ready() -> void:
	_saved_energy = default_light_energy
	if kind == Kind.LIGHT_SWITCH and not switch_visual_path.is_empty():
		_capture_switch_rest()
		call_deferred("_sync_light_switch_visual")


## Called by the player controller when the object is activated.
func interact(_by: Node = null) -> void:
	match kind:
		Kind.DOOR:
			_toggle_door()
		Kind.LIGHT_SWITCH:
			_toggle_light()
		Kind.PICKUP:
			_pickup()
		Kind.COMPUTER:
			_use_computer(_by)
		Kind.COMPUTER_POWER:
			_toggle_computer_power(_by)


# --- Door --------------------------------------------------------------------
func _toggle_door() -> void:
	_door_open = not _door_open
	var target_rotation: float = deg_to_rad(door_open_angle) if _door_open else 0.0

	# Restart any in-progress swing so rapid presses stay responsive.
	if _door_tween != null and _door_tween.is_running():
		_door_tween.kill()

	_door_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_door_tween.tween_property(self, "rotation:y", target_rotation, door_anim_time)


# --- Light switch ------------------------------------------------------------
func _toggle_light() -> void:
	# Target may be a single Light3D OR a parent node holding several lights
	# (e.g. the four chandelier bulbs) — collect and toggle them together.
	var lights := _collect_light_targets(true)
	if lights.is_empty():
		push_warning("Interactable '%s': target_light_path has no Light3D under it." % name)
		return

	# Lit if any light is currently on; flip them all to the opposite state.
	var any_on := _has_enabled_light(lights)
	for light in lights:
		if any_on:
			# Remember each bulb's brightness so we can restore it exactly.
			light.set_meta("saved_energy", light.light_energy if light.light_energy > 0.0 else default_light_energy)
			light.light_energy = 0.0
		else:
			light.light_energy = float(light.get_meta("saved_energy", default_light_energy))
	_set_light_switch_visual(not any_on, true)


func _collect_light_targets(warn_missing: bool) -> Array[Light3D]:
	var target_paths: Array[NodePath] = []
	if not target_light_path.is_empty():
		target_paths.append(target_light_path)
	target_paths.append_array(target_light_paths)
	if target_paths.is_empty():
		if warn_missing:
			push_warning("Interactable '%s': target_light_path is not set or not found." % name)
		return []

	var lights: Array[Light3D] = []
	for path in target_paths:
		var target := get_node_or_null(path)
		if target == null:
			if warn_missing:
				push_warning("Interactable '%s': target_light_path is not set or not found: %s" % [name, path])
			continue
		if target is Light3D and not lights.has(target):
			lights.append(target)
		for child in target.find_children("*", "Light3D", true, false):
			var light := child as Light3D
			if light != null and not lights.has(light):
				lights.append(light)
	return lights


func _has_enabled_light(lights: Array[Light3D]) -> bool:
	for light in lights:
		if light.light_energy > 0.0:
			return true
	return false


func _sync_light_switch_visual() -> void:
	var lights := _collect_light_targets(false)
	if not lights.is_empty():
		_set_light_switch_visual(_has_enabled_light(lights), false)


func _capture_switch_rest() -> void:
	var visual := get_node_or_null(switch_visual_path) as Node3D
	if visual != null:
		_switch_rest_basis = visual.transform.basis
		_switch_rest_captured = true


## Tilts only the rocker key about its local hinge axis, relative to the rest
## pose captured at startup (so the key's baked import orientation is preserved).
func _set_light_switch_visual(is_on: bool, animate: bool) -> void:
	if switch_visual_path.is_empty():
		return
	var visual := get_node_or_null(switch_visual_path) as Node3D
	if visual == null:
		push_warning("Interactable '%s': switch_visual_path is not set or not found." % name)
		return
	if not _switch_rest_captured:
		_capture_switch_rest()

	var target_deg := switch_on_tilt_degrees if is_on else switch_off_tilt_degrees
	if _switch_visual_tween != null and _switch_visual_tween.is_running():
		_switch_visual_tween.kill()
	if animate:
		_play_click()
	if animate and is_inside_tree() and switch_visual_anim_time > 0.0:
		# Tactile rocker "click": snap a touch past the target, then settle back.
		var start_deg := _switch_angle
		var overshoot := target_deg + (target_deg - start_deg) * 0.22
		_switch_visual_tween = create_tween()
		_switch_visual_tween.tween_method(_apply_switch_tilt, start_deg, overshoot, switch_visual_anim_time * 0.6) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_switch_visual_tween.tween_method(_apply_switch_tilt, overshoot, target_deg, switch_visual_anim_time * 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	else:
		_apply_switch_tilt(target_deg)


func _apply_switch_tilt(deg: float) -> void:
	_switch_angle = deg
	var visual := get_node_or_null(switch_visual_path) as Node3D
	if visual == null:
		return
	var axis := switch_tilt_axis.normalized()
	if axis.is_zero_approx():
		axis = Vector3(1, 0, 0)
	visual.transform.basis = _switch_rest_basis * Basis(axis, deg_to_rad(deg))


func _play_click() -> void:
	if click_sound == null:
		return
	var player := get_node_or_null(click_player_path) as AudioStreamPlayer3D
	if player == null:
		return
	player.stream = click_sound
	player.play()


# --- Pickup ------------------------------------------------------------------
func _pickup() -> void:
	# Hook for VFX/SFX here (particles, sound) before removal if desired.
	queue_free()


# --- Computer ----------------------------------------------------------------
func _use_computer(by: Node = null) -> void:
	var target := get_node_or_null(target_terminal_path)
	if target == null:
		push_warning("Interactable '%s': target_terminal_path is not set or not found." % name)
		return
	if target.has_method("open_terminal"):
		target.call("open_terminal", by)


func _toggle_computer_power(by: Node = null) -> void:
	var target := get_node_or_null(target_terminal_path)
	if target == null:
		push_warning("Interactable '%s': target_terminal_path is not set or not found." % name)
		return
	if target.has_method("toggle_power"):
		target.call("toggle_power", by)

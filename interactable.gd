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
## Max distance (m) at which this can be used. 0 = no limit (full ray length).
@export var max_interact_distance: float = 0.0

@export_group("Door")
@export var door_close_prompt: String = "CLOSE DOOR" ## prompt shown while the door is open (prompt_text is used while closed)
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
@export var click_sound: AudioStream          ## Played on each switch toggle (fallback)
@export var click_sounds: Array[AudioStream] = []  ## If set, a random one plays each toggle
@export var click_player_path: NodePath       ## AudioStreamPlayer3D used to play it

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
	if kind == Kind.DOOR:
		_resolve_door_nodes()
	set_process(false)


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


## Text the HUD should show for this object right now. Doors flip between the
## open and close prompts based on their current state; everything else just
## uses prompt_text.
func get_prompt() -> String:
	if kind == Kind.DOOR:
		return door_close_prompt if _door_open else prompt_text
	return prompt_text


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
	_play_door_sound(_door_open)
	_animate_handle()

	# Restart any in-progress swing so rapid presses stay responsive.
	if _door_tween != null and _door_tween.is_running():
		_door_tween.kill()

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

	# Drive the creak's pitch/volume from the leaf's speed while it moves.
	if _door_sound_player != null:
		_prev_door_rot = rotation.y
		_creak_active = true
		set_process(true)


# Lever presses down, then springs back up while the leaf swings.
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


func _play_door_sound(opening: bool) -> void:
	if door_sound_player_path.is_empty():
		return
	var player := get_node_or_null(door_sound_player_path) as AudioStreamPlayer3D
	if player == null or player.stream == null:
		return
	_door_sound_generation += 1
	var generation := _door_sound_generation
	var start_time := door_open_sound_start if opening else door_close_sound_start
	var duration := door_open_sound_duration if opening else door_close_sound_duration
	if player.playing:
		player.stop()
	player.play(maxf(start_time, 0.0))
	if duration > 0.0:
		var timer := get_tree().create_timer(duration)
		timer.timeout.connect(_stop_door_sound.bind(player, generation))


func _stop_door_sound(player: AudioStreamPlayer3D, generation: int) -> void:
	if generation == _door_sound_generation and is_instance_valid(player):
		player.stop()


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
	var stream: AudioStream = click_sound
	if not click_sounds.is_empty():
		stream = click_sounds[randi() % click_sounds.size()]
	if stream == null:
		return
	var player := get_node_or_null(click_player_path) as AudioStreamPlayer3D
	if player == null:
		return
	player.stream = stream
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

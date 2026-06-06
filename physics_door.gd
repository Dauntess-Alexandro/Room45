class_name PhysicsDoor
extends RigidBody3D
## A door you operate by holding a button: while held, the leaf swings slowly and
## heavily toward open (or toward closed if it is already open); release and it
## stops where it is. The leaf hangs on a HingeJoint3D defined in the scene. This
## script owns the motion, handle-press, creak, and slam feedback; the player just
## calls grab_begin()/grab_end(). All feel values are exported for tuning.

@export_group("Grab")
@export var prompt: String = "HOLD LMB TO OPEN DOOR"

@export_group("Open / Close")
@export var open_angle_degrees: float = 95.0  ## must match the hinge open limit
@export var open_speed: float = 1.1           ## rad/s while held — the slow, heavy travel
@export var open_accel: float = 2.0           ## rad/s^2 ramp-up (lower = heavier start)
@export var stop_decel: float = 6.0           ## rad/s^2 settle rate when released
@export var limit_epsilon: float = 0.03       ## rad; stop driving this close to a limit

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
@export var creak_speed_for_max: float = 1.5  ## leaf speed (rad/s) mapped to loudest/highest
@export var creak_idle_speed: float = 0.08    ## below this the creak stops
@export var slam_clip_start: float = 4.0      ## seconds into the clip for the close/latch
@export var slam_speed_threshold: float = 0.8 ## leaf speed (rad/s) into the closed stop = latch
@export var closed_angle_epsilon: float = 0.07 ## rad; how close to 0 counts as "closed"

var _operating: bool = false
var _operate_dir: float = 0.0   ## -1 = opening (toward negative angle), +1 = closing
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
	# Decide direction once on press: if more than halfway closed, open; else close.
	var open_rad := deg_to_rad(open_angle_degrees)
	_operate_dir = -1.0 if rotation.y > -open_rad * 0.5 else 1.0
	_operating = true
	_tween_handle(handle_press_degrees)


func grab_end() -> void:
	_operating = false
	_tween_handle(0.0)


# --- Motion (velocity-controlled so it stays slow and stable on the hinge) ----
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var open_rad := deg_to_rad(open_angle_degrees)
	var ang := rotation.y
	var w := state.angular_velocity.y

	if _operating:
		var at_open := _operate_dir < 0.0 and ang <= -open_rad + limit_epsilon
		var at_closed := _operate_dir > 0.0 and ang >= -limit_epsilon
		if at_open or at_closed:
			w = move_toward(w, 0.0, stop_decel * state.step)
		else:
			w = move_toward(w, _operate_dir * open_speed, open_accel * state.step)
	else:
		w = move_toward(w, 0.0, stop_decel * state.step)

	state.angular_velocity = Vector3(0.0, w, 0.0)
	_update_sound(absf(w), ang, state.step)


# --- Creak + latch -----------------------------------------------------------
func _update_sound(speed: float, ang: float, step: float) -> void:
	if _slam_cooldown > 0.0:
		_slam_cooldown -= step

	# Latch click when arriving at the closed stop with some speed.
	if absf(ang) < closed_angle_epsilon and speed > slam_speed_threshold and _slam_cooldown <= 0.0:
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

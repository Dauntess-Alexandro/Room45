class_name PhysicsDoor
extends RigidBody3D
## A door you operate by holding a button: while held, the leaf swings slowly and
## heavily toward open (or toward closed if it is already open); release and it
## settles where it is. The leaf hangs on a HingeJoint3D defined in the scene and
## is driven by that joint's built-in motor (works in the joint's own frame, so no
## world-axis sign guesswork). This script owns direction, handle-press, creak, and
## latch feedback; the player just calls grab_begin()/grab_end(). Values exported.

@export_group("Grab")
@export var prompt: String = "LMB OPEN / RMB CLOSE"
@export var hinge_path: NodePath = NodePath("../Hinge")

@export_group("Open / Close")
@export var open_angle_degrees: float = 95.0  ## must match the hinge open limit
@export var open_speed: float = 1.1           ## rad/s motor target — the slow, heavy travel
@export var motor_max_impulse: float = 6.0    ## motor strength; lower = heavier / slower to start
@export var limit_epsilon: float = 0.01       ## rad; stop this short of the hard limit (no bounce)
@export var approach_zone: float = 0.45       ## rad before a limit where the motor eases off (no bounce)

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
@export var slam_speed_threshold: float = 0.15 ## leaf speed (rad/s) into the closed stop = latch
@export var closed_angle_epsilon: float = 0.08 ## rad; how close to 0 counts as "closed"

var _operating: bool = false
var _operate_dir: float = 0.0   ## -1 = opening (toward lower limit), +1 = closing (toward 0)
var _hinge: HingeJoint3D
var _excepted: PhysicsBody3D
var _handle_node: Node3D
var _handle_rest_basis: Basis
var _handle_captured: bool = false
var _handle_angle: float = 0.0
var _handle_tween: Tween
var _sound: AudioStreamPlayer3D
var _sound_base_db: float = 0.0
var _slam_cooldown: float = 0.0


func _ready() -> void:
	_hinge = get_node_or_null(hinge_path) as HingeJoint3D
	if _hinge != null:
		_hinge.set("motor/target_velocity", 0.0)
		_hinge.set("motor/max_impulse", motor_max_impulse)
		_hinge.set("motor/enable", false)
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


## opening = true drives toward the open limit, false drives toward closed.
func grab_begin(by: Node = null, opening: bool = true) -> void:
	if _hinge == null:
		return
	# If the door is already at the end we'd drive toward, do nothing — re-pushing
	# into a hard limit just bounces it back (looks like it starts closing).
	var open_rad := deg_to_rad(open_angle_degrees)
	var ang := absf(rotation.y)
	if opening and ang >= open_rad - limit_epsilon:
		return
	if not opening and ang <= limit_epsilon:
		return
	# Open is the hinge's lower limit; -target_velocity drives there, + back to 0.
	_operate_dir = -1.0 if opening else 1.0
	_operating = true
	# Once the player has grabbed the door, stop it colliding with them for good —
	# re-enabling mid-overlap would punt the door (and the player) on release.
	if by is PhysicsBody3D and _excepted == null:
		_excepted = by
		add_collision_exception_with(by)
	_hinge.set("motor/max_impulse", motor_max_impulse)
	_hinge.set("motor/target_velocity", _operate_dir * open_speed)
	_hinge.set("motor/enable", true)
	_tween_handle(handle_press_degrees)


func grab_end() -> void:
	_operating = false
	if _hinge != null:
		_hinge.set("motor/enable", false)
	_tween_handle(0.0)


# --- Motion end + creak ------------------------------------------------------
func _physics_process(delta: float) -> void:
	if _slam_cooldown > 0.0:
		_slam_cooldown -= delta

	if _operating and _hinge != null:
		var open_rad := deg_to_rad(open_angle_degrees)
		# Sign-agnostic distance to the target end: |angle| is 0 closed, open_rad
		# fully open, whichever way the hinge measures rotation.
		var ang_abs := absf(rotation.y)
		var remaining := (open_rad - ang_abs) if _operate_dir < 0.0 else ang_abs
		if remaining <= limit_epsilon:
			# Stop inside the (widened) hard limits and kill the momentum, so the
			# leaf never touches the springy joint stop — nothing to bounce off.
			_hinge.set("motor/enable", false)
			angular_velocity = Vector3.ZERO
			if _operate_dir > 0.0:
				# Snap flush shut and latch at the moment it closes.
				rotation = Vector3.ZERO
				angular_velocity = Vector3.ZERO
				_play_slam()
			_operating = false
		else:
			# Ease the motor down near the end so it arrives gently. Same both ways.
			var speed_scale := clampf(remaining / approach_zone, 0.18, 1.0)
			_hinge.set("motor/target_velocity", _operate_dir * open_speed * speed_scale)

	_update_creak(absf(angular_velocity.y))


func _update_creak(speed: float) -> void:
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

extends CharacterBody3D
## First-person player controller (VotV-style).
##
## Features: WASD movement, mouse look, sprint, crouch and jump, plus a
## centered RayCast3D used to detect and trigger `Interactable` objects.
##
## The interaction prompt lives in the Main scene's UI layer; this controller
## reaches it through the two exported NodePaths below (set on the Player
## instance inside main.tscn), so the controller stays self-contained and the
## UI can live wherever it likes.

# --- Movement tuning ---------------------------------------------------------
@export_group("Movement")
@export var mouse_sensitivity: float = 0.0025
@export var walk_speed: float = 3.0
@export var sprint_speed: float = 6.0
@export var crouch_speed: float = 1.5
@export var jump_velocity: float = 4.2
@export var acceleration: float = 12.0   ## How snappily we reach target speed.
@export var grab_max_distance: float = 2.5  ## how far the player can be and still hold a physics door

# --- Crouch tuning -----------------------------------------------------------
@export_group("Crouch")
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.0
@export var stand_camera_y: float = 1.6
@export var crouch_camera_y: float = 0.9
@export var crouch_lerp_speed: float = 10.0

# --- Look limits -------------------------------------------------------------
@export_group("Look")
@export var min_pitch: float = -1.5   ## radians (~ -86 deg)
@export var max_pitch: float = 1.5    ## radians (~ +86 deg)

# --- UI links (set on the Player instance in main.tscn) ----------------------
@export_group("UI Links")
@export var prompt_root_path: NodePath
@export var prompt_label_path: NodePath

# --- Node references ---------------------------------------------------------
@onready var camera: Camera3D = $Camera3D
@onready var interaction_ray: RayCast3D = $Camera3D/InteractionRay
@onready var capsule: CollisionShape3D = $CollisionShape3D
@onready var prompt_root: Control = get_node_or_null(prompt_root_path)
@onready var prompt_label: Label = get_node_or_null(prompt_label_path)

# --- Internal state ----------------------------------------------------------
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _pitch: float = 0.0
var _is_crouching: bool = false
var _current_target: Object = null
var _grabbed_door: Node = null


func _ready() -> void:
	# Capture the mouse for first-person look.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Never let our own body block the interaction ray.
	interaction_ray.add_exception(self)
	_set_prompt_visible(false)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse look.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, min_pitch, max_pitch)
		camera.rotation.x = _pitch

	# Re-capture the mouse after closing the pause menu (Esc is handled there).
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if not get_tree().paused:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_update_crouch(delta)
	_update_movement(delta)
	_update_interaction()


# --- Movement ----------------------------------------------------------------
func _update_movement(delta: float) -> void:
	# Gravity.
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# Jump (not while crouched).
	if is_on_floor() and Input.is_action_just_pressed("jump") and not _is_crouching:
		velocity.y = jump_velocity

	# Desired horizontal direction, relative to where we face.
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	# Pick a speed based on state.
	var speed: float = walk_speed
	if _is_crouching:
		speed = crouch_speed
	elif Input.is_action_pressed("sprint"):
		speed = sprint_speed

	# Smoothly accelerate toward the target horizontal velocity.
	var target: Vector3 = direction * speed
	var weight: float = clamp(acceleration * delta, 0.0, 1.0)
	velocity.x = lerp(velocity.x, target.x, weight)
	velocity.z = lerp(velocity.z, target.z, weight)

	move_and_slide()


# --- Crouch ------------------------------------------------------------------
func _update_crouch(delta: float) -> void:
	_is_crouching = Input.is_action_pressed("crouch")

	var shape := capsule.shape as CapsuleShape3D
	if shape == null:
		return

	var weight: float = clamp(crouch_lerp_speed * delta, 0.0, 1.0)
	var target_height: float = crouch_height if _is_crouching else stand_height
	shape.height = lerp(shape.height, target_height, weight)
	# Keep the capsule's feet planted on the floor as it shrinks/grows.
	capsule.position.y = shape.height * 0.5

	var target_camera_y: float = crouch_camera_y if _is_crouching else stand_camera_y
	camera.position.y = lerp(camera.position.y, target_camera_y, weight)


# --- Interaction -------------------------------------------------------------
func _update_interaction() -> void:
	# While operating a door (left mouse held), it swings itself. Keep going until
	# the button is released, the door is gone, or we walk too far away.
	if _grabbed_door != null:
		var still_valid := is_instance_valid(_grabbed_door)
		var holding := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
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
			# Some interactables (e.g. a wall switch) should only respond at
			# arm's reach. Honour their per-object distance limit.
			var max_dist: float = (collider as Interactable).max_interact_distance
			if max_dist > 0.0:
				var dist := interaction_ray.global_position.distance_to(interaction_ray.get_collision_point())
				if dist > max_dist:
					target = null
		elif collider != null and collider.has_method("is_grabbable") and collider.is_grabbable():
			var gdist := interaction_ray.global_position.distance_to(interaction_ray.get_collision_point())
			if gdist <= grab_max_distance:
				target = collider

	# Update the on-screen prompt only when the target changes.
	if target != _current_target:
		_current_target = target
		if target != null:
			_refresh_prompt_text()
			_set_prompt_visible(true)
		else:
			_set_prompt_visible(false)

	if _current_target == null:
		return

	# Grabbable door: hold left mouse to operate. Everything else: tap [E].
	if _current_target.has_method("is_grabbable") and _current_target.is_grabbable():
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_grabbed_door = _current_target
			_grabbed_door.grab_begin()
	elif Input.is_action_just_pressed("interact"):
		_current_target.interact(self)
		# Pickups free themselves; drop the stale reference and hide the prompt.
		if not is_instance_valid(_current_target):
			_current_target = null
			_set_prompt_visible(false)
		else:
			# State may have changed (e.g. door open<->close) — refresh the label.
			_refresh_prompt_text()


func _refresh_prompt_text() -> void:
	if prompt_label == null or _current_target == null or not _current_target.has_method("get_prompt"):
		return
	# Tap interactables use the "[E]" key; grabbable doors carry their own key hint.
	if _current_target is Interactable:
		prompt_label.text = "[E]  " + _current_target.get_prompt()
	else:
		prompt_label.text = _current_target.get_prompt()


func _set_prompt_visible(value: bool) -> void:
	if prompt_root != null:
		prompt_root.visible = value

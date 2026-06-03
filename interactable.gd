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
##
## The player reads `prompt_text` to populate the on-screen interaction prompt.

enum Kind { DOOR, LIGHT_SWITCH, PICKUP, COMPUTER }

@export var kind: Kind = Kind.DOOR
## Shown next to the "[E]" indicator in the HUD.
@export var prompt_text: String = "INTERACT"

@export_group("Door")
@export var door_open_angle: float = 95.0   ## degrees
@export var door_anim_time: float = 0.6      ## seconds

@export_group("Light Switch")
@export var target_light_path: NodePath      ## Light3D to toggle
@export var default_light_energy: float = 2.0

@export_group("Computer")
@export var target_terminal_path: NodePath   ## Node with open_terminal(player)

# --- Internal state ----------------------------------------------------------
var _door_open: bool = false
var _door_tween: Tween
var _saved_energy: float = 2.0


func _ready() -> void:
	_saved_energy = default_light_energy


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
	var target := get_node_or_null(target_light_path)
	if target == null:
		push_warning("Interactable '%s': target_light_path is not set or not found." % name)
		return
	var lights: Array[Node] = []
	if target is Light3D:
		lights.append(target)
	lights.append_array(target.find_children("*", "Light3D", true, false))
	if lights.is_empty():
		push_warning("Interactable '%s': target_light_path has no Light3D under it." % name)
		return

	# Lit if any light is currently on; flip them all to the opposite state.
	var any_on := false
	for l in lights:
		if (l as Light3D).light_energy > 0.0:
			any_on = true
			break
	for l in lights:
		var light := l as Light3D
		if any_on:
			# Remember each bulb's brightness so we can restore it exactly.
			light.set_meta("saved_energy", light.light_energy if light.light_energy > 0.0 else default_light_energy)
			light.light_energy = 0.0
		else:
			light.light_energy = float(light.get_meta("saved_energy", default_light_energy))


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

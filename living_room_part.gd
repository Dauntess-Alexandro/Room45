@tool
extends Node3D

const LIVING_ROOM_GLB := preload("res://models/living_room.glb")
const SOURCE_ROOT := "Sketchfab_model/9b7a5044c2fb4020aae65cf02c0da975_fbx/RootNode"
const INTERNAL_ROOT := "_LivingRoomPartRoot"

@export var source_names: PackedStringArray = []:
	set(value):
		source_names = value
		_queue_rebuild()

@export var part_origin := Vector3.ZERO:
	set(value):
		part_origin = value
		_queue_rebuild()

var _rebuild_queued := false


func _ready() -> void:
	_queue_rebuild()


func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_rebuild")


func _rebuild() -> void:
	_rebuild_queued = false
	for child in get_children(true):
		if child.name == INTERNAL_ROOT:
			child.free()

	if source_names.is_empty():
		return

	var model := LIVING_ROOM_GLB.instantiate() as Node3D
	model.name = INTERNAL_ROOT
	model.position = -part_origin
	add_child(model, false, Node.INTERNAL_MODE_BACK)

	var root := model.get_node_or_null(SOURCE_ROOT)
	if root == null:
		push_warning("Living room source root not found.")
		return

	for child in root.get_children():
		if not source_names.has(child.name):
			child.free()

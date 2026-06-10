@tool
extends Node3D
## Instances a shared GLB asset pack and keeps only the parts whose names contain
## one of `keep_names` (case-insensitive substring match), so a single item can be
## pulled out of a multi-item pack. Kept parts are recentred on `part_origin`
## (the pack-space position that should end up at this node's origin).

@export var source_scene: PackedScene:
	set(value):
		source_scene = value
		_queue_rebuild()

## Name of the node inside the pack whose children are the individual items.
@export var root_node_name := "RootNode":
	set(value):
		root_node_name = value
		_queue_rebuild()

@export var keep_names: PackedStringArray = []:
	set(value):
		keep_names = value
		_queue_rebuild()

## Names to drop (case-insensitive substring). Applied after keep_names; with an
## empty keep list this means "keep everything except these".
@export var exclude_names: PackedStringArray = []:
	set(value):
		exclude_names = value
		_queue_rebuild()

@export var part_origin := Vector3.ZERO:
	set(value):
		part_origin = value
		_queue_rebuild()

const INTERNAL_ROOT := "_GlbPartRoot"

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

	if source_scene == null:
		return

	var model := source_scene.instantiate() as Node3D
	model.name = INTERNAL_ROOT
	model.position = -part_origin
	add_child(model, false, Node.INTERNAL_MODE_BACK)

	# No filters = use the whole model (just recentred on part_origin).
	if keep_names.is_empty() and exclude_names.is_empty():
		return

	var root := model.find_child(root_node_name, true, false)
	if root == null:
		push_warning("glb_part: node '%s' not found in source scene." % root_node_name)
		return

	for child in root.get_children():
		var keep := _matches(child.name, keep_names) if not keep_names.is_empty() else true
		if keep and _matches(child.name, exclude_names):
			keep = false
		if not keep:
			child.free()


func _matches(node_name: String, names: PackedStringArray) -> bool:
	var lower := node_name.to_lower()
	for k in names:
		if k != "" and lower.contains(k.to_lower()):
			return true
	return false

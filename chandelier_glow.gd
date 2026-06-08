extends Node3D
## Makes a chandelier's emissive bulb glass follow its lights: the glass only
## glows while the controlling lights are on, and goes dark when they're off.
##
## Attach to a chandelier model node. `lights_path` points at the node holding
## the chandelier's OmniLight3D bulbs (use "." if they're children of this node).

@export var lights_path: NodePath

var _mats: Array[StandardMaterial3D] = []
var _base_energy: Array[float] = []
var _lights: Array[OmniLight3D] = []
var _was_on: bool = true


func _ready() -> void:
	var src := get_node_or_null(lights_path)
	if src != null:
		for child in src.find_children("*", "OmniLight3D", true, false):
			_lights.append(child as OmniLight3D)
	for mi in find_children("*", "MeshInstance3D", true, false):
		_collect_emissive(mi as MeshInstance3D)
	_apply(_lights_on())


func _collect_emissive(mi: MeshInstance3D) -> void:
	if mi == null or mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(s) as StandardMaterial3D
		if mat != null and mat.emission_enabled:
			var dup := mat.duplicate() as StandardMaterial3D
			mi.set_surface_override_material(s, dup)
			_mats.append(dup)
			_base_energy.append(dup.emission_energy_multiplier)


func _process(_delta: float) -> void:
	var on := _lights_on()
	if on != _was_on:
		_was_on = on
		_apply(on)


func _lights_on() -> bool:
	for l in _lights:
		if l.light_energy > 0.0:
			return true
	return false


func _apply(on: bool) -> void:
	for i in _mats.size():
		_mats[i].emission_energy_multiplier = _base_energy[i] if on else 0.0

extends Node3D


func _ready() -> void:
	# Hide hardware we don't want shown. Deadbolt and Passage_Latch are standalone
	# nodes, so hiding the whole node is fine.
	for marker in ["Deadbolt", "Passage_Latch"]:
		for node in find_children("*%s*" % marker, "Node", true, false):
			if node is Node3D:
				(node as Node3D).visible = false

	# The door leaf is parented UNDER the "Hinges" node in this model, so hiding
	# that node would hide the whole door. Hide only the hinge's own mesh and
	# leave the door (and anything else nested under it) visible.
	for hinge in find_children("*Hinges*", "Node3D", true, false):
		for child in hinge.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).visible = false

extends Node3D


func _ready() -> void:
	for marker in ["Deadbolt", "Passage_Latch", "Hinges"]:
		for node in find_children("*%s*" % marker, "Node", true, false):
			if node is Node3D:
				(node as Node3D).visible = false

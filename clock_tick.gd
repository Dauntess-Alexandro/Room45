extends AudioStreamPlayer3D


func _ready() -> void:
	if stream != null:
		stream.set("loop", true)
	play()


func _exit_tree() -> void:
	stop()

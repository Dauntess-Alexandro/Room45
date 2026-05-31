extends Node
## Display / resolution helper (autoload). Persists to user://settings.cfg.

signal settings_applied

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

const SETTINGS_PATH := "user://settings.cfg"

var resolution_index: int = 1
var fullscreen: bool = false


func _ready() -> void:
	load_settings()
	call_deferred("apply")


func get_resolution() -> Vector2i:
	return RESOLUTIONS[clampi(resolution_index, 0, RESOLUTIONS.size() - 1)]


func resolution_label(index: int) -> String:
	var r := RESOLUTIONS[clampi(index, 0, RESOLUTIONS.size() - 1)]
	return "%d × %d" % [r.x, r.y]


func apply() -> void:
	var res := get_resolution()
	var win := get_tree().root

	win.content_scale_size = res

	if fullscreen:
		win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		win.borderless = true
	else:
		win.mode = Window.MODE_WINDOWED
		win.borderless = false
		win.size = res
		var screen := DisplayServer.screen_get_size(win.current_screen)
		win.position = Vector2i(
			int((screen.x - res.x) / 2.0),
			int((screen.y - res.y) / 2.0),
		)

	settings_applied.emit()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "resolution_index", resolution_index)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	resolution_index = int(cfg.get_value("display", "resolution_index", 1))
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))

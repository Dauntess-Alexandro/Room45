extends Control
## Pause / settings overlay (Esc). Works while the tree is paused.

@onready var _resolution: OptionButton = %ResolutionOption
@onready var _fullscreen: CheckBox = %FullscreenCheck
@onready var _apply: Button = %ApplyButton
@onready var _resume: Button = %ResumeButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_resolution_list()
	_sync_from_settings()
	_apply.pressed.connect(_on_apply_pressed)
	_resume.pressed.connect(close_menu)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if visible:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()


func open_menu() -> void:
	_sync_from_settings()
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_menu() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_resolution_list() -> void:
	_resolution.clear()
	for i in DisplaySettings.RESOLUTIONS.size():
		_resolution.add_item(DisplaySettings.resolution_label(i), i)


func _sync_from_settings() -> void:
	_resolution.select(DisplaySettings.resolution_index)
	_fullscreen.button_pressed = DisplaySettings.fullscreen


func _on_apply_pressed() -> void:
	DisplaySettings.resolution_index = _resolution.get_selected_id()
	DisplaySettings.fullscreen = _fullscreen.button_pressed
	DisplaySettings.apply()
	DisplaySettings.save_settings()

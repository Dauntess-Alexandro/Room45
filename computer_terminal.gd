extends Node
## Runtime CRT terminal rendered into the in-world ComputerScreen mesh.

@export var screen_path: NodePath
@export var player_path: NodePath
@export var crosshair_path: NodePath
@export var prompt_path: NodePath
@export var viewport_size := Vector2i(512, 384)

var _screen: MeshInstance3D
var _player: Node
var _crosshair: Control
var _prompt: Control
var _viewport: SubViewport
var _log: RichTextLabel
var _prompt_line: Label
var _active := false
var _current_command := ""
var _history: Array[String] = []


func _ready() -> void:
	_screen = get_node_or_null(screen_path) as MeshInstance3D
	_player = get_node_or_null(player_path)
	_crosshair = get_node_or_null(crosshair_path) as Control
	_prompt = get_node_or_null(prompt_path) as Control
	_build_viewport()
	_apply_screen_texture()
	_boot()


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("ui_cancel"):
		close_terminal()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed:
		_handle_key(event)
		get_viewport().set_input_as_handled()


func open_terminal(_by: Node = null) -> void:
	if _active:
		return
	_active = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _player != null:
		if _player is CharacterBody3D:
			(_player as CharacterBody3D).velocity = Vector3.ZERO
		_player.set_physics_process(false)
		_player.set_process_unhandled_input(false)
	if _crosshair != null:
		_crosshair.visible = false
	if _prompt != null:
		_prompt.visible = false
	_current_command = ""
	_refresh_prompt_line()
	_write("session opened. type 'help' or 'exit'.")


func close_terminal() -> void:
	if not _active:
		return
	_active = false
	_current_command = ""
	_refresh_prompt_line()
	if _player != null:
		_player.set_physics_process(true)
		_player.set_process_unhandled_input(true)
	if _crosshair != null:
		_crosshair.visible = true
	if _prompt != null:
		_prompt.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_write("session closed.")


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "TerminalViewport"
	_viewport.size = viewport_size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(root)

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	root.add_child(bg)

	_log = RichTextLabel.new()
	_log.name = "Log"
	_log.set_anchors_preset(Control.PRESET_FULL_RECT)
	_log.offset_left = 22.0
	_log.offset_top = 22.0
	_log.offset_right = -18.0
	_log.offset_bottom = -52.0
	_log.bbcode_enabled = false
	_log.scroll_following = true
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_color_override("default_color", Color(0.15, 1.0, 0.22, 1.0))
	_log.add_theme_font_size_override("normal_font_size", 16)
	root.add_child(_log)

	_prompt_line = Label.new()
	_prompt_line.name = "PromptLine"
	_prompt_line.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt_line.offset_left = 22.0
	_prompt_line.offset_top = -42.0
	_prompt_line.offset_right = -18.0
	_prompt_line.offset_bottom = -12.0
	_prompt_line.add_theme_color_override("font_color", Color(0.15, 1.0, 0.22, 1.0))
	_prompt_line.add_theme_font_size_override("font_size", 16)
	root.add_child(_prompt_line)


func _apply_screen_texture() -> void:
	if _screen == null:
		push_warning("ComputerTerminal: screen_path is not set.")
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.emission_enabled = true
	mat.emission_texture = _viewport.get_texture()
	mat.emission = Color(0.55, 1.0, 0.55, 1.0)
	mat.emission_energy_multiplier = 1.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.no_depth_test = true
	mat.render_priority = 10
	_screen.material_override = mat


func _boot() -> void:
	_history.clear()
	_write("AcerAlb BIOS 1.45")
	_write("ROOM45 CRT terminal ready")
	_write("press [E] near the monitor to focus")
	_refresh_prompt_line()


func _handle_key(event: InputEventKey) -> void:
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_submit_command(_current_command)
	elif event.keycode == KEY_BACKSPACE:
		if not _current_command.is_empty():
			_current_command = _current_command.substr(0, _current_command.length() - 1)
			_refresh_prompt_line()
	elif event.unicode >= 32 and event.unicode != 127 and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		_current_command += char(event.unicode)
		_refresh_prompt_line()


func _submit_command(command: String) -> void:
	var cmd := command.strip_edges()
	if cmd.is_empty():
		_current_command = ""
		_refresh_prompt_line()
		return
	_write("user@AcerAlb:~$ " + cmd)
	_current_command = ""
	_refresh_prompt_line()
	_run_command(cmd)


func _run_command(cmd: String) -> void:
	var lower := cmd.to_lower()
	if lower == "help":
		_write("commands: help, ls, whoami, status, sudo update, hello world, clear, exit")
	elif lower == "ls":
		_write("desktop  room45.log  antenna.cfg  petard_box.txt")
	elif lower == "whoami":
		_write("user")
	elif lower == "status":
		_write("monitor: online")
		_write("lamp: unstable")
		_write("signal: waiting")
	elif lower == "sudo update":
		_write("[sudo] password for user: ********")
		_write("package room45-radio is already the newest version")
	elif lower == "hello world":
		_write("hello, room")
	elif lower.begins_with("echo "):
		_write(cmd.substr(5))
	elif lower == "clear":
		_history.clear()
		_refresh_log()
	elif lower == "exit" or lower == "logout":
		close_terminal()
	else:
		_write("command not found: " + cmd)


func _write(line: String) -> void:
	_history.append(line)
	while _history.size() > 16:
		_history.pop_front()
	_refresh_log()


func _refresh_log() -> void:
	if _log == null:
		return
	var lines := PackedStringArray()
	for item in _history:
		lines.append(item)
	_log.text = "\n".join(lines)


func _refresh_prompt_line() -> void:
	if _prompt_line == null:
		return
	var cursor := "_" if _active else ""
	_prompt_line.text = "user@AcerAlb:~$ " + _current_command + cursor

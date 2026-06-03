extends Node
## Runtime CRT terminal rendered into the in-world ComputerScreen mesh.

const DRIVE_SOUND_PATH := "res://sound/old-hard-drive-booting-up-and-shutting-down.wav"
const DRIVE_LOOP_BEGIN_TIME := 16.0
const DRIVE_LOOP_END_TIME := 69.0
const DRIVE_SHUTDOWN_TIME := 70.0
const DRIVE_VOLUME_DB := -15.0
const DRIVE_SILENT_DB := -80.0
const DRIVE_CROSSFADE_TIME := 0.35

@export var screen_path: NodePath
@export var power_led_path: NodePath
@export var activity_led_path: NodePath
@export var drive_audio_origin_path: NodePath
@export var player_path: NodePath
@export var crosshair_path: NodePath
@export var prompt_path: NodePath
@export var viewport_size := Vector2i(512, 384)

var _screen: MeshInstance3D
var _power_led: Node3D
var _power_led_light: Light3D
var _activity_led: Node3D
var _activity_led_light: Light3D
var _drive_audio_origin: Node3D
var _player: Node
var _crosshair: Control
var _prompt: Control
var _prompt_label: Label
var _viewport: SubViewport
var _log: RichTextLabel
var _prompt_line: Label
var _screen_mat: StandardMaterial3D
var _screen_glow_tween: Tween
var _power_led_tween: Tween
var _activity_led_tween: Tween
var _beep_player: AudioStreamPlayer
var _drive_player_a: AudioStreamPlayer3D
var _drive_player_b: AudioStreamPlayer3D
var _drive_active_player: AudioStreamPlayer3D
var _drive_standby_player: AudioStreamPlayer3D
var _drive_tweens: Array[Tween] = []
var _drive_audio_id := 0
var _drive_looping := false
var _drive_crossfading := false
var _beep_id := 0
var _boot_id := 0
var _prompt_hint_id := 0
var _active := false
var _powered_on := false
var _booting := false
var _current_command := ""
var _history: Array[String] = []


func _ready() -> void:
	_screen = get_node_or_null(screen_path) as MeshInstance3D
	_power_led = get_node_or_null(power_led_path) as Node3D
	_power_led_light = _power_led as Light3D
	_activity_led = get_node_or_null(activity_led_path) as Node3D
	_activity_led_light = _activity_led as Light3D
	_drive_audio_origin = get_node_or_null(drive_audio_origin_path) as Node3D
	_player = get_node_or_null(player_path)
	_crosshair = get_node_or_null(crosshair_path) as Control
	_prompt = get_node_or_null(prompt_path) as Control
	if _prompt != null:
		_prompt_label = _prompt.get_node_or_null("PromptLabel") as Label
	_build_viewport()
	_apply_screen_texture()
	_setup_boot_audio()
	_setup_power_led()
	_setup_activity_led()
	_set_powered(false)


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


func _process(delta: float) -> void:
	_update_drive_audio(delta)


func open_terminal(_by: Node = null) -> void:
	if _active:
		return
	if not _powered_on:
		_flash_interaction_hint("TURN ON COMPUTER FIRST")
		return
	if _booting:
		_flash_interaction_hint("COMPUTER IS BOOTING...")
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


func toggle_power(_by: Node = null) -> void:
	if _booting:
		power_off()
		return
	if _powered_on:
		power_off()
	else:
		power_on()


func power_on() -> void:
	if _powered_on or _booting:
		return
	_boot_sequence()


func power_off() -> void:
	if not _powered_on and not _booting:
		return
	if _active:
		close_terminal()
	_booting = false
	_boot_id += 1
	_set_powered(false)


func _set_powered(value: bool) -> void:
	var had_power := _powered_on or _booting
	_powered_on = value
	if not value:
		_set_screen_emission(0.0)
		if _beep_player != null:
			_beep_player.stop()
		if had_power:
			_stop_drive_audio()
		else:
			_silence_drive_audio()
	else:
		_start_drive_audio()
	_set_power_led(value)
	_set_activity_led(value)
	_history.clear()
	_current_command = ""
	_refresh_log()
	_refresh_prompt_line()


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
	_screen_mat = mat


func _set_screen_emission(value: float) -> void:
	if _screen_glow_tween != null:
		_screen_glow_tween.kill()
		_screen_glow_tween = null
	if _screen_mat != null:
		_screen_mat.emission_energy_multiplier = value


func _tween_screen_emission(value: float, duration: float) -> void:
	if _screen_mat == null:
		return
	if _screen_glow_tween != null:
		_screen_glow_tween.kill()
	_screen_glow_tween = create_tween()
	_screen_glow_tween.tween_property(_screen_mat, "emission_energy_multiplier", value, duration)


func _setup_boot_audio() -> void:
	_beep_player = AudioStreamPlayer.new()
	_beep_player.name = "BootBeepPlayer"
	_beep_player.volume_db = -8.0
	add_child(_beep_player)

	var drive_stream := load(DRIVE_SOUND_PATH) as AudioStream
	if drive_stream == null:
		push_warning("ComputerTerminal: drive sound not found at %s." % DRIVE_SOUND_PATH)
		return
	_drive_player_a = _create_drive_player("ComputerDrivePlayerA", drive_stream)
	_drive_player_b = _create_drive_player("ComputerDrivePlayerB", drive_stream)
	_drive_active_player = _drive_player_a
	_drive_standby_player = _drive_player_b


func _create_drive_player(player_name: String, stream: AudioStream) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = player_name
	player.stream = stream
	player.volume_db = DRIVE_SILENT_DB
	player.max_distance = 5.0
	player.unit_size = 1.0
	if _drive_audio_origin != null:
		_drive_audio_origin.add_child(player)
	elif _screen != null:
		_screen.add_child(player)
	else:
		add_child(player)
	return player


func _start_drive_audio() -> void:
	if _drive_active_player == null:
		return
	_drive_audio_id += 1
	_drive_looping = true
	_drive_crossfading = false
	_kill_drive_tweens()
	_drive_player_a.stop()
	_drive_player_b.stop()
	_drive_active_player = _drive_player_a
	_drive_standby_player = _drive_player_b
	_drive_active_player.volume_db = DRIVE_SILENT_DB
	_drive_active_player.play(0.0)
	_tween_drive_volume(_drive_active_player, DRIVE_VOLUME_DB, 0.9)


func _stop_drive_audio() -> void:
	if _drive_active_player == null:
		return
	_drive_audio_id += 1
	var audio_id := _drive_audio_id
	_drive_looping = false
	_drive_crossfading = false
	_kill_drive_tweens()
	_drive_player_a.stop()
	_drive_player_b.stop()
	_drive_active_player = _drive_player_a
	_drive_standby_player = _drive_player_b
	_drive_active_player.volume_db = DRIVE_VOLUME_DB
	_drive_active_player.play(DRIVE_SHUTDOWN_TIME)
	_stop_drive_shutdown_later(audio_id)


func _silence_drive_audio() -> void:
	_drive_audio_id += 1
	_drive_looping = false
	_drive_crossfading = false
	_kill_drive_tweens()
	if _drive_player_a != null:
		_drive_player_a.stop()
		_drive_player_a.volume_db = DRIVE_SILENT_DB
	if _drive_player_b != null:
		_drive_player_b.stop()
		_drive_player_b.volume_db = DRIVE_SILENT_DB


func _update_drive_audio(_delta: float) -> void:
	if not _drive_looping or _drive_crossfading or _drive_active_player == null:
		return
	if not _drive_active_player.playing:
		return
	if _drive_active_player.get_playback_position() >= DRIVE_LOOP_END_TIME - DRIVE_CROSSFADE_TIME:
		_crossfade_drive_loop()


func _crossfade_drive_loop() -> void:
	if _drive_active_player == null or _drive_standby_player == null:
		return
	_drive_crossfading = true
	var audio_id := _drive_audio_id
	_drive_standby_player.stop()
	_drive_standby_player.volume_db = DRIVE_SILENT_DB
	_drive_standby_player.play(DRIVE_LOOP_BEGIN_TIME)
	_tween_drive_volume(_drive_active_player, DRIVE_SILENT_DB, DRIVE_CROSSFADE_TIME)
	_tween_drive_volume(_drive_standby_player, DRIVE_VOLUME_DB, DRIVE_CROSSFADE_TIME)
	await get_tree().create_timer(DRIVE_CROSSFADE_TIME).timeout
	if audio_id != _drive_audio_id or not _drive_looping:
		return
	_drive_active_player.stop()
	var previous_active := _drive_active_player
	_drive_active_player = _drive_standby_player
	_drive_standby_player = previous_active
	_drive_crossfading = false


func _tween_drive_volume(player: AudioStreamPlayer3D, volume_db: float, duration: float) -> void:
	var tween := create_tween()
	_drive_tweens.append(tween)
	tween.tween_property(player, "volume_db", volume_db, duration)


func _kill_drive_tweens() -> void:
	for tween in _drive_tweens:
		if tween != null and tween.is_running():
			tween.kill()
	_drive_tweens.clear()


func _stop_drive_shutdown_later(audio_id: int) -> void:
	var stream_length := 0.0
	if _drive_active_player != null and _drive_active_player.stream != null:
		stream_length = _drive_active_player.stream.get_length()
	var wait_time := maxf(0.2, stream_length - DRIVE_SHUTDOWN_TIME + 0.1)
	await get_tree().create_timer(wait_time).timeout
	if audio_id == _drive_audio_id and not _drive_looping and _drive_active_player != null:
		_drive_active_player.stop()


func _setup_power_led() -> void:
	if _power_led_light == null:
		return
	_power_led_light.light_color = Color(0.1, 1.0, 0.22, 1.0)
	_power_led_light.light_energy = 0.0


func _set_power_led(enabled: bool) -> void:
	if _power_led_light == null:
		return
	if _power_led_tween != null:
		_power_led_tween.kill()
		_power_led_tween = null
	if enabled:
		_power_led_light.visible = true
		_power_led_light.light_energy = 0.18
		_power_led_tween = create_tween().set_loops()
		_power_led_tween.tween_property(_power_led_light, "light_energy", 0.42, 0.12).set_delay(4.2)
		_power_led_tween.tween_property(_power_led_light, "light_energy", 0.18, 0.24)
	else:
		_power_led_light.light_energy = 0.0


func _setup_activity_led() -> void:
	if _activity_led_light == null:
		return
	_activity_led_light.light_color = Color(1.0, 0.08, 0.04, 1.0)
	_activity_led_light.light_energy = 0.0


func _set_activity_led(enabled: bool) -> void:
	if _activity_led_light == null:
		return
	if _activity_led_tween != null:
		_activity_led_tween.kill()
		_activity_led_tween = null
	_activity_led_light.light_energy = 0.0
	if enabled:
		_activity_led_light.visible = true
		_activity_led_tween = create_tween().set_loops()
		_activity_led_tween.tween_property(_activity_led_light, "light_energy", 0.34, 0.08).set_delay(6.2)
		_activity_led_tween.tween_property(_activity_led_light, "light_energy", 0.0, 0.18)


func _blink_activity_once(energy := 0.42, hold := 0.08) -> void:
	if _activity_led_light == null:
		return
	var tween := create_tween()
	tween.tween_property(_activity_led_light, "light_energy", energy, 0.05)
	tween.tween_interval(hold)
	tween.tween_property(_activity_led_light, "light_energy", 0.0, 0.16)


func _flash_interaction_hint(message: String) -> void:
	if _prompt == null or _prompt_label == null:
		return
	_prompt_hint_id += 1
	var hint_id := _prompt_hint_id
	_prompt.visible = true
	_prompt_label.text = message
	await get_tree().create_timer(1.3).timeout
	if hint_id != _prompt_hint_id or _active or _prompt_label == null:
		return
	_prompt_label.text = "[E]  USE COMPUTER"


func _play_boot_beep(frequency: float = 880.0, duration: float = 0.13, volume: float = 0.16) -> void:
	if _beep_player == null:
		return
	_beep_id += 1
	var beep_id: int = _beep_id
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = duration + 0.08
	_beep_player.stop()
	_beep_player.stream = generator
	_beep_player.play()
	var playback := _beep_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var frames: int = int(generator.mix_rate * duration)
	var attack_frames: int = maxi(1, int(generator.mix_rate * 0.008))
	var release_frames: int = maxi(1, int(generator.mix_rate * 0.025))
	for i in range(frames):
		var t: float = float(i) / generator.mix_rate
		var attack: float = minf(1.0, float(i) / float(attack_frames))
		var release: float = minf(1.0, float(frames - i) / float(release_frames))
		var envelope: float = minf(attack, release)
		var sample: float = sin(TAU * frequency * t) * volume * envelope
		playback.push_frame(Vector2(sample, sample))
	_stop_boot_beep_later(beep_id, duration + 0.08)


func _stop_boot_beep_later(beep_id: int, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if beep_id == _beep_id and _beep_player != null:
		_beep_player.stop()


func _is_boot_current(boot_id: int) -> bool:
	return _powered_on and _booting and boot_id == _boot_id


func _boot_write(boot_id: int, line: String, delay: float, activity_blink := false) -> bool:
	if not _is_boot_current(boot_id):
		return false
	if activity_blink:
		_blink_activity_once()
	_write(line)
	await get_tree().create_timer(delay).timeout
	return _is_boot_current(boot_id)


func _boot_sequence() -> void:
	_booting = true
	_powered_on = true
	_boot_id += 1
	var boot_id := _boot_id
	_start_drive_audio()
	_set_power_led(true)
	_set_activity_led(true)
	_set_screen_emission(0.25)
	_history.clear()
	_current_command = ""
	_refresh_prompt_line()
	await get_tree().create_timer(0.25).timeout
	if not _is_boot_current(boot_id):
		return
	_play_boot_beep()
	_tween_screen_emission(1.65, 0.12)
	if not await _boot_write(boot_id, "AcerAlb BIOS v1.45", 0.42):
		return
	if not await _boot_write(boot_id, "(C) 1997 AlbSystems ROM", 0.32):
		return
	if not await _boot_write(boot_id, "CPU: Intel 486DX2 @ 66 MHz", 0.34):
		return
	if not await _boot_write(boot_id, "Base memory: 640K OK", 0.36, true):
		return
	if not await _boot_write(boot_id, "Extended memory: 8192K OK", 0.42, true):
		return
	if not await _boot_write(boot_id, "Keyboard controller... OK", 0.34):
		return
	if not await _boot_write(boot_id, "CMOS battery... weak", 0.46):
		return
	if not await _boot_write(boot_id, "Detecting IDE drives...", 0.52, true):
		return
	if not await _boot_write(boot_id, "Primary Master: ROOM45_DISK 512MB", 0.42, true):
		return
	if not await _boot_write(boot_id, "Booting from C:\\", 0.46):
		return
	if not await _boot_write(boot_id, "Loading ROOM45.SYS", 0.52, true):
		return
	if not await _boot_write(boot_id, "Starting CRT terminal...", 0.48):
		return
	_write("CRT online")
	_write("press [E] near the monitor to focus")
	_tween_screen_emission(1.4, 0.35)
	_booting = false
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
	if not _powered_on:
		_log.text = ""
		return
	var lines := PackedStringArray()
	for item in _history:
		lines.append(item)
	_log.text = "\n".join(lines)


func _refresh_prompt_line() -> void:
	if _prompt_line == null:
		return
	if not _powered_on:
		_prompt_line.text = ""
		return
	var cursor := "_" if _active else ""
	_prompt_line.text = "user@AcerAlb:~$ " + _current_command + cursor

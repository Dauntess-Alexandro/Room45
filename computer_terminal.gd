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
var _header: Label
var _header_rule: ColorRect
var _scanlines: TextureRect
var _vignette: TextureRect
var _flicker_layer: ColorRect
var _cursor_timer: Timer
var _cursor_on := true
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
var _chat: RostikChat
var _chat_mode := false
var _chat_waiting := false
var _typing_id := 0
var _delivery_id := 0
var _greeted_this_session := false
var _received_files: Dictionary = {}
var _last_idle_header := ""

@export var room_lights_path: NodePath   ## node holding room Light3D(s); empty = auto-find
## Optional retro/pixel font for the screen. Empty = system monospace (Consolas/Courier).
@export_file("*.ttf", "*.otf", "*.fnt", "*.woff", "*.woff2") var font_path: String = ""

const HEADER_IDLE := "ROOM45 // AcerAlb"
const TYPING_BASE := "Ростик печатает"
const ERASE_BASE := "Ростик стирает"
const BURST_PAUSE_MIN := 1.4   ## pause before Ростик's follow-up message
const BURST_PAUSE_MAX := 3.0
const DROPOUT_CHANCE := 0.10   ## chance a sent message hits a fake dial-up dropout
const ERASE_CHANCE := 0.22     ## chance Ростик "erases and retypes" a short message
const WORLD_EVENTS_ENABLED := true   ## #4: chat can affect the room (свет only for now)
const FILES_SAVE := "user://rostik_files.save"
const DROPOUT_EXCUSES := [
	"сорян, мамка трубку подняла, инет скинуло",
	"бля связь оборвалась, телефон занят был",
	"это я отходил, мать по телефону трепалась",
	"комп завис нахер, перезагружал",
	"сорян, провод выдернули, я обратно воткнул",
]


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
	_setup_chat()
	_setup_game_clock()
	_setup_cursor_blink()
	_set_powered(false)


func _setup_cursor_blink() -> void:
	_cursor_timer = Timer.new()
	_cursor_timer.name = "CursorBlink"
	_cursor_timer.wait_time = 0.5
	_cursor_timer.autostart = true
	add_child(_cursor_timer)
	_cursor_timer.timeout.connect(_on_cursor_blink)


func _on_cursor_blink() -> void:
	_cursor_on = not _cursor_on
	if _active:
		_refresh_prompt_line()


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
	if _flicker_layer != null:
		if _powered_on:
			var t := Time.get_ticks_msec() / 1000.0
			_flicker_layer.color.a = 0.03 + 0.025 * (0.5 + 0.5 * sin(t * 7.3)) + randf() * 0.01
		else:
			_flicker_layer.color.a = 0.0


func _setup_game_clock() -> void:
	if not GameClock.minute_changed.is_connected(_on_game_clock_minute_changed):
		GameClock.minute_changed.connect(_on_game_clock_minute_changed)


func _on_game_clock_minute_changed() -> void:
	if _powered_on and not _chat_mode and not _chat_waiting:
		_set_header(_idle_header())


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
	_set_screen_chrome_visible(value)
	_chat_mode = false
	_chat_waiting = false
	_greeted_this_session = false
	_delivery_id += 1
	if _chat != null:
		_chat.cancel()
	_history.clear()
	_current_command = ""
	_set_header("" if not value else _idle_header())
	_refresh_log()
	_refresh_prompt_line()


func close_terminal() -> void:
	if not _active:
		return
	_active = false
	_chat_mode = false
	_chat_waiting = false
	_delivery_id += 1
	_stop_typing_indicator()
	if _chat != null:
		_chat.cancel()
	_set_header(_idle_header())
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

	var font := _resolve_font()

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.01, 0.03, 0.01, 1.0)   # very dark green, not pure black
	root.add_child(bg)

	_header = Label.new()
	_header.name = "Header"
	_header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_header.offset_left = 22.0
	_header.offset_top = 8.0
	_header.offset_right = -18.0
	_header.offset_bottom = 30.0
	_header.add_theme_color_override("font_color", Color(0.45, 1.0, 0.5, 1.0))
	_header.add_theme_font_override("font", font)
	_header.add_theme_font_size_override("font_size", 14)
	root.add_child(_header)

	_header_rule = ColorRect.new()
	_header_rule.name = "HeaderRule"
	_header_rule.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_header_rule.offset_left = 22.0
	_header_rule.offset_top = 31.0
	_header_rule.offset_right = -18.0
	_header_rule.offset_bottom = 32.0
	_header_rule.color = Color(0.15, 0.55, 0.22, 0.55)
	_header_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_header_rule)

	_log = RichTextLabel.new()
	_log.name = "Log"
	_log.set_anchors_preset(Control.PRESET_FULL_RECT)
	_log.offset_left = 22.0
	_log.offset_top = 36.0
	_log.offset_right = -18.0
	_log.offset_bottom = -52.0
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_color_override("default_color", Color(0.17, 1.0, 0.27, 1.0))
	_log.add_theme_font_override("normal_font", font)
	_log.add_theme_font_size_override("normal_font_size", 16)
	# Soft green halo behind the text = phosphor glow.
	_log.add_theme_color_override("font_shadow_color", Color(0.1, 1.0, 0.2, 0.33))
	_log.add_theme_constant_override("shadow_offset_x", 0)
	_log.add_theme_constant_override("shadow_offset_y", 0)
	_log.add_theme_constant_override("shadow_outline_size", 3)
	root.add_child(_log)

	_prompt_line = Label.new()
	_prompt_line.name = "PromptLine"
	_prompt_line.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt_line.offset_left = 22.0
	_prompt_line.offset_top = -42.0
	_prompt_line.offset_right = -18.0
	_prompt_line.offset_bottom = -12.0
	_prompt_line.add_theme_color_override("font_color", Color(0.17, 1.0, 0.27, 1.0))
	_prompt_line.add_theme_color_override("font_shadow_color", Color(0.1, 1.0, 0.2, 0.33))
	_prompt_line.add_theme_constant_override("shadow_offset_x", 0)
	_prompt_line.add_theme_constant_override("shadow_offset_y", 0)
	_prompt_line.add_theme_font_override("font", font)
	_prompt_line.add_theme_font_size_override("font_size", 16)
	root.add_child(_prompt_line)

	# --- CRT overlays (drawn on top, no shader) ---
	_scanlines = TextureRect.new()
	_scanlines.name = "Scanlines"
	_scanlines.texture = _make_scanline_texture()
	_scanlines.stretch_mode = TextureRect.STRETCH_TILE
	_scanlines.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_scanlines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scanlines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_scanlines)

	_vignette = TextureRect.new()
	_vignette.name = "Vignette"
	_vignette.texture = _make_vignette_texture(160, 120)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_vignette)

	_flicker_layer = ColorRect.new()
	_flicker_layer.name = "Flicker"
	_flicker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flicker_layer.color = Color(0.0, 0.0, 0.0, 0.0)
	_flicker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flicker_layer)


func _resolve_font() -> Font:
	if not font_path.is_empty() and ResourceLoader.exists(font_path):
		var res := load(font_path)
		if res is Font:
			return res
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Px437 IBM VGA8", "Perfect DOS VGA 437", "Consolas",
		"Lucida Console", "Courier New", "monospace",
	])
	return sf


func _make_scanline_texture() -> Texture2D:
	# 1x3 strip: two clear rows + one dark row -> a scanline every 3 px when tiled.
	var img := Image.create(1, 3, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0, 0, 0, 0))
	img.set_pixel(0, 1, Color(0, 0, 0, 0))
	img.set_pixel(0, 2, Color(0, 0, 0, 0.22))
	return ImageTexture.create_from_image(img)


func _make_vignette_texture(w: int, h: int) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var nx := float(x) / float(w - 1) * 2.0 - 1.0
			var ny := float(y) / float(h - 1) * 2.0 - 1.0
			var d := sqrt(nx * nx + ny * ny) / 1.4142136
			var a := clampf(pow(d, 2.5) * 0.85, 0.0, 1.0)
			img.set_pixel(x, y, Color(0, 0, 0, a))
	return ImageTexture.create_from_image(img)


func _set_screen_chrome_visible(value: bool) -> void:
	if _header_rule != null:
		_header_rule.visible = value
	if _scanlines != null:
		_scanlines.visible = value
	if _vignette != null:
		_vignette.visible = value


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


## Short rising two-tone chirp — the "new message" дзынь for the chat.
func _play_message_chime() -> void:
	if _beep_player == null:
		return
	_beep_id += 1
	var beep_id: int = _beep_id
	var tone_a := 0.06
	var tone_b := 0.11
	var total := tone_a + tone_b
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = total + 0.08
	_beep_player.stop()
	_beep_player.stream = generator
	_beep_player.play()
	var playback := _beep_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	_push_tone(playback, generator.mix_rate, 660.0, tone_a, 0.16)
	_push_tone(playback, generator.mix_rate, 990.0, tone_b, 0.16)
	_stop_boot_beep_later(beep_id, total + 0.08)


func _push_tone(playback: AudioStreamGeneratorPlayback, rate: float, frequency: float, duration: float, volume: float) -> void:
	var frames: int = int(rate * duration)
	var attack_frames: int = maxi(1, int(rate * 0.006))
	var release_frames: int = maxi(1, int(rate * 0.02))
	for i in range(frames):
		var t: float = float(i) / rate
		var attack: float = minf(1.0, float(i) / float(attack_frames))
		var release: float = minf(1.0, float(frames - i) / float(release_frames))
		var envelope: float = minf(attack, release)
		var sample: float = sin(TAU * frequency * t) * volume * envelope
		playback.push_frame(Vector2(sample, sample))


func _push_silence(playback: AudioStreamGeneratorPlayback, rate: float, duration: float) -> void:
	for i in range(int(rate * duration)):
		playback.push_frame(Vector2(0.0, 0.0))


## Double "ring" used when Ростик triggers a [event:звонок].
func _play_ring() -> void:
	if _beep_player == null:
		return
	_beep_id += 1
	var beep_id: int = _beep_id
	var ring := 0.3
	var gap := 0.12
	var total := ring * 2.0 + gap
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = total + 0.25
	_beep_player.stop()
	_beep_player.stream = generator
	_beep_player.play()
	var playback := _beep_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	_push_tone(playback, generator.mix_rate, 1000.0, ring, 0.14)
	_push_silence(playback, generator.mix_rate, gap)
	_push_tone(playback, generator.mix_rate, 1000.0, ring, 0.14)
	_stop_boot_beep_later(beep_id, total + 0.25)


## Soft single blip when YOU send a message (distinct from the incoming chime).
func _play_send_blip() -> void:
	if _beep_player == null:
		return
	_beep_id += 1
	var beep_id: int = _beep_id
	var duration := 0.05
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = duration + 0.06
	_beep_player.stop()
	_beep_player.stream = generator
	_beep_player.play()
	var playback := _beep_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	_push_tone(playback, generator.mix_rate, 520.0, duration, 0.10)
	_stop_boot_beep_later(beep_id, duration + 0.06)


## Sad descending "бдыщ" when the connection fails.
func _play_error_buzz() -> void:
	if _beep_player == null:
		return
	_beep_id += 1
	var beep_id: int = _beep_id
	var tone_a := 0.13
	var tone_b := 0.22
	var total := tone_a + tone_b
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = total + 0.08
	_beep_player.stop()
	_beep_player.stream = generator
	_beep_player.play()
	var playback := _beep_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	_push_tone(playback, generator.mix_rate, 311.0, tone_a, 0.15)  # Eb4
	_push_tone(playback, generator.mix_rate, 196.0, tone_b, 0.16)  # G3
	_stop_boot_beep_later(beep_id, total + 0.08)


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
	_set_screen_chrome_visible(true)
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
	_set_header(_idle_header())
	if _chat != null and _chat.has_saved_conversation():
		_write("* аська: ростик писал, пока тебя не было")
		_write("  набери 'chat' чтобы открыть")
	else:
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
	if _chat_mode:
		_current_command = ""
		_refresh_prompt_line()
		_handle_chat_input(cmd)
		return
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
		_write("commands: help, ls, whoami, status, time [HH:MM], date, chat, cat <file>, sudo update, clear, exit")
	elif lower == "ls":
		var listing := "desktop  room45.log  antenna.cfg  petard_box.txt  rostik.icq"
		for f in _received_files:
			listing += "  " + str(f)
		_write(listing)
	elif lower == "whoami":
		_write("user")
	elif lower.begins_with("cat "):
		_cat_file(cmd.substr(4).strip_edges())
	elif lower == "chat" or lower == "icq" or lower == "connect":
		_enter_chat()
	elif lower == "status":
		_write("monitor: online")
		_write("datetime: " + GameClock.datetime_string(true))
		_write("lamp: unstable")
		_write("signal: waiting")
		_write("rostik: online (2005)")
	elif lower.begins_with("time "):
		var raw_time := cmd.substr(5).strip_edges()
		if GameClock.set_time_from_string(raw_time):
			_write("time set: " + GameClock.datetime_string(true))
		else:
			_write("usage: time HH:MM")
	elif lower == "time":
		_write(GameClock.time_string(true))
	elif lower == "date":
		_write(GameClock.date_string())
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


func _setup_chat() -> void:
	_chat = RostikChat.new()
	_chat.name = "RostikChat"
	add_child(_chat)
	_chat.reply_ready.connect(_on_rostik_reply)
	_chat.request_failed.connect(_on_rostik_error)
	_load_files()


func _enter_chat() -> void:
	_chat_mode = true
	_chat_waiting = false
	if _chat != null:
		_chat.cancel()
	_write("* dialing rostik...")
	_write("* online. напиши что-нибудь ('пока' — выйти)")
	_set_header("Ростик [в сети]")
	_refresh_prompt_line()
	# Once per power-on, Ростик writes first (greets / picks up where you left off).
	if _chat != null and not _greeted_this_session:
		_greeted_this_session = true
		_chat_waiting = true
		_set_header("Ростик [печатает...]")
		_start_typing_indicator()
		_chat.greet(_chat.has_saved_conversation())


func _leave_chat() -> void:
	_chat_mode = false
	_chat_waiting = false
	_delivery_id += 1
	_stop_typing_indicator()
	if _chat != null:
		_chat.cancel()
	_write("* disconnected from rostik")
	_set_header(_idle_header())
	_refresh_prompt_line()


func _handle_chat_input(text: String) -> void:
	if text.is_empty():
		return
	var lower := text.to_lower()
	if lower == "пока" or lower == "bye" or lower == "/exit" or lower == "exit":
		_leave_chat()
		return
	if _chat_waiting:
		_write("(Ростик ещё печатает...)")
		return
	_write("[%s] you> %s" % [_now(), text])
	_play_send_blip()
	_chat_waiting = true
	_set_header("Ростик [печатает...]")
	if randf() < DROPOUT_CHANCE:
		_simulate_dropout(text)
	else:
		_start_typing_indicator()
		if _chat != null:
			_chat.send_message(text)


## Fake old-internet hiccup: drop, reconnect, Ростик comes back with an excuse,
## then his real reply to the message follows.
func _simulate_dropout(text: String) -> void:
	_delivery_id += 1
	var id := _delivery_id
	_write("* message not delivered")
	_write("* reconnecting...")
	_set_header("Ростик [не в сети]")
	_play_error_buzz()
	await get_tree().create_timer(randf_range(5.0, 9.0)).timeout
	if id != _delivery_id or not _chat_mode or not _powered_on:
		return
	_set_header("Ростик [в сети]")
	_blink_activity_once()
	_play_message_chime()
	_write("[%s] Rostik> %s" % [_now(), DROPOUT_EXCUSES[randi() % DROPOUT_EXCUSES.size()]])
	_set_header("Ростик [печатает...]")
	_start_typing_indicator()
	if _chat != null:
		_chat.send_message(text)


func _on_rostik_reply(text: String) -> void:
	_chat_waiting = false
	_stop_typing_indicator()
	if not _powered_on or not _chat_mode:
		return
	_set_header("Ростик [в сети]")
	var parsed := _parse_rostik(text)
	_deliver_rostik(_split_messages(parsed.clean), parsed.files, parsed.events)


## Pull out [file:name]...[/file] blocks and [event:x] tags from Ростик's reply.
func _parse_rostik(text: String) -> Dictionary:
	var files: Dictionary = {}
	var events: Array = []
	var clean := text

	var file_re := RegEx.new()
	file_re.compile("\\[file:([^\\]]+)\\]([\\s\\S]*?)\\[/file\\]")
	for m in file_re.search_all(clean):
		var fname := m.get_string(1).strip_edges()
		var fcontent := m.get_string(2).strip_edges()
		if not fname.is_empty():
			files[fname] = fcontent
	clean = file_re.sub(clean, "", true)

	var ev_re := RegEx.new()
	ev_re.compile("\\[event:([^\\]]+)\\]")
	for m in ev_re.search_all(clean):
		events.append(m.get_string(1).strip_edges().to_lower())
	clean = ev_re.sub(clean, "", true)

	return {"clean": clean.strip_edges(), "files": files, "events": events}


## Ростик may answer in 1-2 separate messages (split on a blank line in his reply).
func _split_messages(text: String) -> Array[String]:
	var parts: Array[String] = []
	for chunk in text.split("\n\n", false):
		var c := chunk.strip_edges()
		if not c.is_empty():
			parts.append(c)
	if parts.is_empty():
		parts.append(text.strip_edges())
	# Keep it childish, not spammy: at most two bursts, extras fold into the second.
	while parts.size() > 2:
		parts[1] = parts[1] + "\n" + parts.pop_back()
	return parts


func _deliver_rostik(segments: Array[String], files: Dictionary = {}, events: Array = []) -> void:
	_delivery_id += 1
	var id := _delivery_id
	for index in segments.size():
		if id != _delivery_id or not _chat_mode or not _powered_on:
			return
		if index > 0:
			# Follow-up message: short "typing" pause + its own chime.
			_chat_waiting = true
			_set_header("Ростик [печатает...]")
			_start_typing_indicator()
			await get_tree().create_timer(randf_range(BURST_PAUSE_MIN, BURST_PAUSE_MAX)).timeout
			_chat_waiting = false
			_stop_typing_indicator()
			if id != _delivery_id or not _chat_mode or not _powered_on:
				return
			_set_header("Ростик [в сети]")
		await _emit_rostik_segment(segments[index])
		if id != _delivery_id:
			return

	# Files he "sends", then room events he triggers.
	for fname in files:
		if id != _delivery_id or not _chat_mode or not _powered_on:
			return
		await get_tree().create_timer(randf_range(0.8, 1.6)).timeout
		if id != _delivery_id:
			return
		_receive_file(str(fname), str(files[fname]))
	# #4 world events are paused — tags are still parsed out of the text above,
	# but nothing fires until WORLD_EVENTS_ENABLED is turned on.
	if WORLD_EVENTS_ENABLED:
		for ev in events:
			if id != _delivery_id or not _chat_mode or not _powered_on:
				return
			await get_tree().create_timer(0.5).timeout
			_trigger_event(str(ev))


func _emit_rostik_segment(segment: String) -> void:
	# Occasionally "erase and retype" a short message for extra liveliness.
	if segment.length() < 40 and randf() < ERASE_CHANCE:
		_start_erase_indicator()
		await get_tree().create_timer(randf_range(0.7, 1.3)).timeout
		_stop_typing_indicator()
	_blink_activity_once()
	_play_message_chime()
	for raw_line in segment.split("\n", false):
		var line := raw_line.strip_edges()
		if not line.is_empty():
			_write("[%s] Rostik> %s" % [_now(), line])


func _on_rostik_error(message: String) -> void:
	_chat_waiting = false
	_stop_typing_indicator()
	if not _powered_on or not _chat_mode:
		return
	_play_error_buzz()
	_set_header("Ростик [не в сети]")
	_write("* " + message)


func _start_typing_indicator() -> void:
	_typing_id += 1
	_history.append(TYPING_BASE + "...")
	while _history.size() > 16:
		_history.pop_front()
	_refresh_log()
	_animate_typing(_typing_id)


func _start_erase_indicator() -> void:
	_typing_id += 1   # stop any dot animation; this line is static
	_history.append(ERASE_BASE + "...")
	while _history.size() > 16:
		_history.pop_front()
	_refresh_log()


func _animate_typing(id: int) -> void:
	var dots := 0
	while id == _typing_id and _chat_waiting and _chat_mode:
		if not _history.is_empty() and (_history[_history.size() - 1] as String).begins_with(TYPING_BASE):
			_history[_history.size() - 1] = TYPING_BASE + ".".repeat(dots)
			_refresh_log()
		dots = (dots + 1) % 4
		await get_tree().create_timer(0.4).timeout


func _stop_typing_indicator() -> void:
	_typing_id += 1   # break any running _animate_typing loop
	if _history.is_empty():
		return
	var last := _history[_history.size() - 1] as String
	if last.begins_with(TYPING_BASE) or last.begins_with(ERASE_BASE):
		_history.pop_back()
		_refresh_log()


func _write(line: String) -> void:
	_history.append(line)
	while _history.size() > 16:
		_history.pop_front()
	_refresh_log()


func _set_header(text: String) -> void:
	if _header != null:
		_header.text = text


func _idle_header() -> String:
	var text := "%s // %s" % [HEADER_IDLE, GameClock.datetime_string(false)]
	_last_idle_header = text
	return text


func _show_transcript() -> void:
	if _chat == null or not _chat.has_saved_conversation():
		_write("rostik.icq: пусто")
		return
	_write("--- rostik.icq ---")
	for line in _chat.get_transcript_lines():
		_write(line)


func _cat_file(name: String) -> void:
	var lname := name.to_lower()
	if lname == "rostik.icq" or lname == "rostik":
		_show_transcript()
		return
	# Files Ростик sent (case-insensitive match).
	for f in _received_files:
		if str(f).to_lower() == lname:
			_write("--- " + str(f) + " ---")
			for line in str(_received_files[f]).split("\n", false):
				_write(line)
			return
	# A few canned built-ins for flavour.
	match lname:
		"room45.log":
			_write("...system log truncated...")
			_write("last entry: signal lost 03:14")
		"antenna.cfg":
			_write("freq=104.2")
			_write("gain=auto")
			_write("status=waiting")
		"petard_box.txt":
			_write("КОРСАР-1: 20 шт")
			_write("хранить в сухом месте")
		_:
			_write("cat: " + name + ": нет такого файла")


func _receive_file(name: String, content: String) -> void:
	_received_files[name] = content
	_save_files()
	_blink_activity_once()
	_play_message_chime()
	_write("* Ростик отправляет " + name)
	_write("  набери 'cat " + name + "' чтобы открыть")


func _trigger_event(ev: String) -> void:
	match ev:
		"свет", "light", "lights":
			_write("* ...свет в комнате мигнул*")
			_flicker_room_lights()
		"звонок", "ring", "call", "phone":
			_write("* ...где-то зазвонило*")
			_play_ring()
			_flicker_room_lights()
		_:
			pass


func _get_room_lights() -> Array:
	var lights: Array = []
	var explicit := get_node_or_null(room_lights_path)
	if explicit != null:
		if explicit is Light3D:
			lights.append(explicit)
		lights.append_array(explicit.find_children("*", "Light3D", true, false))
	else:
		lights = get_tree().root.find_children("*", "Light3D", true, false)
	# Don't flicker the computer's own status LEDs.
	lights.erase(_power_led_light)
	lights.erase(_activity_led_light)
	return lights


func _flicker_room_lights() -> void:
	for l in _get_room_lights():
		var light := l as Light3D
		if light == null or light.light_energy <= 0.0:
			continue
		var base := light.light_energy
		var tw := create_tween()
		tw.tween_property(light, "light_energy", base * 0.1, 0.05)
		tw.tween_property(light, "light_energy", base, 0.06)
		tw.tween_property(light, "light_energy", base * 0.2, 0.05)
		tw.tween_property(light, "light_energy", base, 0.10)


func _save_files() -> void:
	var f := FileAccess.open(FILES_SAVE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_received_files))
	f.close()


func _load_files() -> void:
	if not FileAccess.file_exists(FILES_SAVE):
		return
	var f := FileAccess.open(FILES_SAVE, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		_received_files = data


func _now() -> String:
	return GameClock.time_string(false)


func _refresh_log() -> void:
	if _log == null:
		return
	if not _powered_on:
		_log.text = ""
		return
	var lines := PackedStringArray()
	for item in _history:
		lines.append(_format_log_line(item))
	_log.text = "\n".join(lines)


## Colour a log line by who "said" it (BBCode). User text is escaped so stray
## brackets (timestamps, file contents) don't get parsed as tags.
func _format_log_line(raw: String) -> String:
	var color := "2bff45"
	var italic := false
	if raw.begins_with(TYPING_BASE) or raw.begins_with(ERASE_BASE):
		color = "4a8a52"
		italic = true
	elif "Rostik>" in raw:
		color = "5cff70"
	elif "you>" in raw:
		color = "37c24d"
	elif raw.begins_with("*") or raw.begins_with("(") or raw.begins_with("---"):
		color = "7aa882"
	var esc := raw.replace("[", "[lb]")
	var styled := "[color=#" + color + "]" + esc + "[/color]"
	if italic:
		styled = "[i]" + styled + "[/i]"
	return styled


func _refresh_prompt_line() -> void:
	if _prompt_line == null:
		return
	if not _powered_on:
		_prompt_line.text = ""
		return
	var cursor := ("_" if _cursor_on else " ") if _active else ""
	var prefix := "you> " if _chat_mode else "user@AcerAlb:~$ "
	_prompt_line.text = prefix + _current_command + cursor

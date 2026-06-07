extends DirectionalLight3D

@export var world_environment_path: NodePath
@export var window_light_path: NodePath
@export var window_beam_path: NodePath
@export var daylight_mesh_path: NodePath
## Extra window-fill lights (e.g. another room's) dimmed straight with daylight.
@export var extra_window_light_paths: Array[NodePath] = []

@export var sunrise_hour := 6.0
@export var sunset_hour := 20.5
@export var night_hour := 21.5
@export var max_sun_energy := 1.45
@export var max_window_energy := 1.15
@export var max_beam_energy := 2.1

var _environment: Environment
var _window_lights: Array[OmniLight3D] = []
var _window_beam: SpotLight3D
var _daylight_mats: Array[StandardMaterial3D] = []
var _extra_window_lights: Array[OmniLight3D] = []
var _extra_window_base: Array[float] = []


func _ready() -> void:
	_resolve_targets()
	_apply_time_of_day()


func _process(_delta: float) -> void:
	_apply_time_of_day()


func _resolve_targets() -> void:
	var world := get_node_or_null(world_environment_path) as WorldEnvironment
	if world != null:
		_environment = world.environment

	_resolve_window_lights()
	_resolve_extra_window_lights()
	_window_beam = get_node_or_null(window_beam_path) as SpotLight3D
	_resolve_daylight_meshes()


func _resolve_daylight_meshes() -> void:
	# Dim every "*Daylight" panel in the scene (both rooms), not just one room's.
	_daylight_mats.clear()
	var root: Node = get_tree().current_scene if get_tree() != null else null
	if root == null:
		root = get_parent()
	if root == null:
		return
	for node in root.find_children("*Daylight", "MeshInstance3D", true, false):
		_prepare_daylight_mesh(node as MeshInstance3D)


func _resolve_extra_window_lights() -> void:
	_extra_window_lights.clear()
	_extra_window_base.clear()
	for path in extra_window_light_paths:
		var target := get_node_or_null(path)
		if target == null:
			continue
		if target is OmniLight3D:
			_extra_window_lights.append(target)
			_extra_window_base.append((target as OmniLight3D).light_energy)
		for child in target.find_children("*", "OmniLight3D", true, false):
			_extra_window_lights.append(child as OmniLight3D)
			_extra_window_base.append((child as OmniLight3D).light_energy)


func _prepare_daylight_mesh(daylight: MeshInstance3D) -> void:
	if daylight == null:
		return
	var mat := daylight.material_override as StandardMaterial3D
	if mat == null:
		return
	var daylight_mat := mat.duplicate()
	daylight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	daylight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	daylight.material_override = daylight_mat
	_daylight_mats.append(daylight_mat)


func _apply_time_of_day() -> void:
	var hour := _game_hour()
	var daylight := _daylight_amount(hour)
	var day_t := clampf((hour - sunrise_hour) / maxf(sunset_hour - sunrise_hour, 0.001), 0.0, 1.0)
	var height := sin(day_t * PI) * daylight
	var horizon_warmth := pow(clampf(1.0 - height, 0.0, 1.0), 1.2)
	var color := _sun_color(day_t, horizon_warmth, daylight)
	var ray_dir := _sun_ray_direction(day_t, height)

	look_at(global_position + ray_dir, Vector3.UP)
	light_color = color
	light_energy = max_sun_energy * pow(maxf(height, 0.0), 0.72)
	shadow_enabled = daylight > 0.02

	if not _window_lights.is_empty():
		var fill_color := _ambient_window_color(daylight, color)
		var fill_energy := lerpf(0.03, max_window_energy, daylight * (0.24 + height * 0.46))
		for l in _window_lights:
			l.light_color = fill_color
			l.light_energy = fill_energy / float(_window_lights.size())

	if _window_beam != null:
		_window_beam.light_color = color
		_window_beam.light_energy = max_beam_energy * daylight * pow(maxf(height, 0.0), 0.55)
		_window_beam.shadow_enabled = _window_beam.light_energy > 0.05
		_window_beam.look_at(_window_beam.global_position + ray_dir, Vector3.UP)

	for i in _extra_window_lights.size():
		_extra_window_lights[i].light_energy = _extra_window_base[i] * daylight

	if _environment != null:
		_environment.ambient_light_color = _ambient_color(daylight, color)
		_environment.ambient_light_energy = lerpf(0.08, 0.5, daylight)
		_environment.background_color = _background_color(daylight, day_t, horizon_warmth)

	if not _daylight_mats.is_empty():
		var alpha := lerpf(0.05, 0.72, daylight)
		for mat in _daylight_mats:
			mat.albedo_color = Color(color.r, color.g, color.b, alpha)


func _resolve_window_lights() -> void:
	_window_lights.clear()
	var target := get_node_or_null(window_light_path)
	if target == null:
		return
	if target is OmniLight3D:
		_window_lights.append(target)
	for child in target.find_children("*", "OmniLight3D", true, false):
		_window_lights.append(child as OmniLight3D)


func _game_hour() -> float:
	var dt := GameClock.get_datetime()
	return float(dt.hour) + float(dt.minute) / 60.0 + float(dt.second) / 3600.0


func _daylight_amount(hour: float) -> float:
	var rise := _smoothstep(sunrise_hour - 0.35, sunrise_hour + 0.75, hour)
	var set := 1.0 - _smoothstep(sunset_hour - 0.65, night_hour, hour)
	return clampf(rise * set, 0.0, 1.0)


func _sun_ray_direction(day_t: float, height: float) -> Vector3:
	var side_sweep := lerpf(-0.75, 0.75, day_t)
	var downward := lerpf(0.08, 1.55, clampf(height, 0.0, 1.0))
	return Vector3(side_sweep, -downward, 1.0).normalized()


func _sun_color(day_t: float, horizon_warmth: float, daylight: float) -> Color:
	var day := Color(1.0, 0.92, 0.78, 1.0)
	var dawn := Color(1.0, 0.55, 0.46, 1.0)
	var dusk := Color(1.0, 0.45, 0.18, 1.0)
	var horizon := dawn if day_t < 0.5 else dusk
	var sun := day.lerp(horizon, horizon_warmth)
	return Color(0.2, 0.25, 0.45, 1.0).lerp(sun, daylight)


func _ambient_color(daylight: float, sun_color: Color) -> Color:
	var night := Color(0.08, 0.10, 0.18, 1.0)
	var day := Color(0.36, 0.36, 0.40, 1.0).lerp(sun_color, 0.28)
	return night.lerp(day, daylight)


func _ambient_window_color(daylight: float, sun_color: Color) -> Color:
	var night := Color(0.12, 0.16, 0.30, 1.0)
	return night.lerp(sun_color, daylight)


func _background_color(daylight: float, day_t: float, horizon_warmth: float) -> Color:
	var night := Color(0.012, 0.016, 0.035, 1.0)
	var sky := Color(0.45, 0.58, 0.78, 1.0)
	var sunset := Color(0.78, 0.34, 0.18, 1.0)
	var day_bg := sky.lerp(sunset, horizon_warmth * (0.3 if day_t < 0.5 else 0.75))
	return night.lerp(day_bg, daylight)


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var x := clampf((value - edge0) / maxf(edge1 - edge0, 0.001), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

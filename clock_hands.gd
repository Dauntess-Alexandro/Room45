extends Node3D

const FACE_Z := 0.021
const FACE_RADIUS := 0.171
const HOUR_LENGTH := 0.105
const MINUTE_LENGTH := 0.152

const FACE_TEXTURE := preload("res://models/clock_face_ai_draft.png")

var _hour_pivot: Node3D
var _minute_pivot: Node3D


func _ready() -> void:
	_build_clock_face()
	_update_hands()
	GameClock.second_changed.connect(_update_hands)


func _exit_tree() -> void:
	if GameClock.second_changed.is_connected(_update_hands):
		GameClock.second_changed.disconnect(_update_hands)


func _build_clock_face() -> void:
	_make_face_plate()
	_hour_pivot = _make_hand("HourHand", HOUR_LENGTH, 0.018, 0.030, 0.0025)
	_minute_pivot = _make_hand("MinuteHand", MINUTE_LENGTH, 0.013, 0.038, 0.004)
	_make_center_cap()


func _make_face_plate() -> void:
	var face := MeshInstance3D.new()
	face.name = "CleanFace"
	face.position = Vector3(0.0, 0.0, FACE_Z)
	face.mesh = _make_face_mesh()
	face.material_override = _face_material()
	add_child(face)


func _make_face_mesh() -> ArrayMesh:
	var segments := 128
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	vertices.append(Vector3.ZERO)
	normals.append(Vector3.BACK)
	uvs.append(Vector2(0.5, 0.5))

	for i in range(segments + 1):
		var angle := TAU * float(i) / float(segments)
		var x := sin(angle) * FACE_RADIUS
		var y := cos(angle) * FACE_RADIUS
		vertices.append(Vector3(x, y, 0.0))
		normals.append(Vector3.BACK)
		uvs.append(Vector2(
			0.5 + x / (FACE_RADIUS * 2.0),
			0.5 - y / (FACE_RADIUS * 2.0)
		))

	for i in range(1, segments + 1):
		indices.append(0)
		indices.append(i)
		indices.append(i + 1)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_hand(hand_name: String, length: float, width: float, counter_length: float, z_offset: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = hand_name
	pivot.position = Vector3(0.0, 0.0, FACE_Z + z_offset)
	add_child(pivot)

	var silhouette := MeshInstance3D.new()
	silhouette.name = "Silhouette"
	silhouette.mesh = _make_hand_mesh(length, width, counter_length)
	silhouette.material_override = _hand_material(Color(0.018, 0.014, 0.011, 1.0), 0.62, 0.18)
	pivot.add_child(silhouette)

	var ridge := MeshInstance3D.new()
	ridge.name = "CenterRidge"
	var ridge_mesh := BoxMesh.new()
	ridge_mesh.size = Vector3(width * 0.16, length * 0.68, 0.001)
	ridge.mesh = ridge_mesh
	ridge.position = Vector3(0.0, length * 0.38, 0.001)
	ridge.material_override = _hand_material(Color(0.45, 0.34, 0.20, 1.0), 0.72, 0.35)
	pivot.add_child(ridge)

	var tail := MeshInstance3D.new()
	tail.name = "TailWeight"
	tail.mesh = _make_ellipse_mesh(width * 0.42, counter_length * 0.35)
	tail.position = Vector3(0.0, -counter_length * 0.62, 0.0015)
	tail.material_override = _hand_material(Color(0.018, 0.014, 0.011, 1.0), 0.62, 0.18)
	pivot.add_child(tail)
	return pivot


func _make_hand_mesh(length: float, width: float, counter_length: float) -> ArrayMesh:
	var points := PackedVector2Array([
		Vector2(0.0, length),
		Vector2(-width * 0.22, length * 0.88),
		Vector2(-width * 0.40, length * 0.56),
		Vector2(-width * 0.28, length * 0.12),
		Vector2(-width * 0.72, -counter_length * 0.22),
		Vector2(-width * 0.30, -counter_length),
		Vector2(0.0, -counter_length * 0.74),
		Vector2(width * 0.30, -counter_length),
		Vector2(width * 0.72, -counter_length * 0.22),
		Vector2(width * 0.28, length * 0.12),
		Vector2(width * 0.40, length * 0.56),
		Vector2(width * 0.22, length * 0.88),
	])
	return _make_fan_mesh(points)


func _make_ellipse_mesh(rx: float, ry: float) -> ArrayMesh:
	var points := PackedVector2Array()
	for i in range(32):
		var a := TAU * float(i) / 32.0
		points.append(Vector2(sin(a) * rx, cos(a) * ry))
	return _make_fan_mesh(points)


func _make_fan_mesh(points: PackedVector2Array) -> ArrayMesh:
	var vertices := PackedVector3Array([Vector3.ZERO])
	var normals := PackedVector3Array([Vector3.BACK])
	var indices := PackedInt32Array()
	for p in points:
		vertices.append(Vector3(p.x, p.y, 0.0))
		normals.append(Vector3.BACK)
	for i in range(1, points.size()):
		indices.append(0)
		indices.append(i)
		indices.append(i + 1)
	indices.append(0)
	indices.append(points.size())
	indices.append(1)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_center_cap() -> void:
	var cap := MeshInstance3D.new()
	cap.name = "HandCap"
	cap.position = Vector3(0.0, 0.0, FACE_Z + 0.007)
	cap.rotation_degrees.x = 90.0
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.012
	mesh.bottom_radius = 0.015
	mesh.height = 0.005
	mesh.radial_segments = 28
	cap.mesh = mesh
	cap.material_override = _hand_material(Color(0.06, 0.045, 0.03, 1.0), 0.7, 0.25)
	add_child(cap)


func _hand_material(color: Color, roughness := 0.78, metallic := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _face_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = FACE_TEXTURE
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _update_hands() -> void:
	if _hour_pivot == null:
		return
	_hour_pivot.rotation.z = -TAU * GameClock.hour_12() / 12.0
	_minute_pivot.rotation.z = -TAU * GameClock.minute() / 60.0

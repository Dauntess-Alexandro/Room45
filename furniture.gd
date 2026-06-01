@tool
extends Node3D
## Procedurally builds all the room props (desk, shelves, wardrobe, sofa,
## chair, chandelier, monitors, pull-up bar, window dressing, rug and the wall
## decals) from low-poly primitives, using the sliced Nano-Banana textures.
##
## Kept out of main.tscn on purpose: parametric primitives are far more compact
## and tweakable here than hundreds of hand-written SubResources, and the blocky
## low-poly result is exactly the Voices-of-the-Void / PS1 look we want.
##
## The Furniture node sits at the world origin, so every position below is in
## room coordinates: interior X [-1.31, 1.31], Z [-2.3, 2.3], floor Y = 0.

# Room half-extents / faces (interior).
const HALF_W := 1.31   # +/- X (walls)
const HALF_L := 2.30   # +/- Z (walls)

## Drop an exported .glb here (see models/README.txt) to replace the blocky placeholder.
const SOFA_GLB := "res://models/sofa.glb"
## Real-world size for the imported sofa (depth X, height Y, length Z).
const SOFA_TARGET_SIZE := Vector3(1.10, 0.95, 2.35)
const SOFA_CENTER_Z := -0.55
const SOFA_WALL_GAP := 0.04

const PILLOW_GLB := "res://models/pillow.glb"
const BLANKET_GLB := "res://models/blanket.glb"
## Sketchfab exports are often ~1000× too large — pre-shrink then match sofa size.
const GLB_UNIT_SCALE := 0.001

const SCREEN_SIZE := Vector2(0.46, 0.30)

## Single old PC model on the desk (replaces the two procedural CRT boxes).
const COMPUTER_GLB := "res://models/old_computer.glb"
const COMPUTER_TARGET_H := 0.42   # overall height in metres (tweak to taste)
const COMPUTER_YAW := 180.0       # face the screen into the room (−X); flip 180 if backwards
# The glowing CRT overlay lives in main.tscn as the "ComputerScreen" node so it
# can be dragged onto the monitor by hand in the editor (this script is @tool, so
# the desk + PC render in-editor as an alignment reference).

var _mats := {}


func _ready() -> void:
	if Engine.is_editor_hint():
		# Lightweight editor preview: just the desk + PC, so the ComputerScreen
		# node has something to align against. Generated nodes are left unowned,
		# so they show in the viewport but are never saved into the scene.
		for c in get_children():
			c.free()
		_build_materials()
		_build_desk()
		return
	_build_materials()
	_build_rug()
	_build_desk()
	_build_shelf()
	_build_wardrobe()
	_build_sofa()
	_build_pullup_bar()
	_build_window()
	_build_chandelier()
	_build_decals()


# =============================================================================
# Material helpers
# =============================================================================
func _tex(path: String, uv_scale := Vector3.ONE, rough := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR    # soft retro, not crunchy nearest
	m.roughness = rough
	m.metallic = 0.0
	m.uv1_scale = uv_scale
	return m


func _col(color: Color, rough := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.roughness = rough
	m.metallic = metallic
	return m


func _build_materials() -> void:
	_mats["counter"]   = _tex("res://tex_countertop.jpg", Vector3(1, 1, 2))
	_mats["shelf"]     = _tex("res://tex_shelf_white.jpg")
	_mats["wardrobe"]  = _tex("res://tex_wardrobe.jpg", Vector3(1, 2, 1))
	_mats["sofa_navy"] = _tex("res://tex_sofa_navy.jpg")
	_mats["sofa_beige"] = _tex("res://tex_sofa_beige.jpg")
	_mats["sofa_blue"] = _col(Color(0.10, 0.38, 0.78), 0.88)   # pillow + blanket
	_mats["rug"]       = _tex("res://tex_rug.jpg", Vector3(1, 1, 3))
	_mats["curtain"]   = _tex("res://tex_curtain.jpg", Vector3(1, 2, 1))
	_mats["metal"]     = _col(Color(0.08, 0.08, 0.09), 0.4, 0.6)   # black frames
	_mats["chrome"]    = _col(Color(0.8, 0.82, 0.85), 0.15, 1.0)
	_mats["chair"]     = _col(Color(0.9, 0.9, 0.92), 0.6)
	_mats["pillow"]    = _col(Color(0.1, 0.7, 0.75), 0.9)          # cyan accent

	# Tulle: semi-transparent floral net.
	var tulle := _tex("res://tex_tulle.jpg")
	tulle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tulle.albedo_color = Color(1, 1, 1, 0.55)
	_mats["tulle"] = tulle

	# Glowing monitor display (Windows desktop) — opaque, unshaded, no see-through.
	var screen := StandardMaterial3D.new()
	screen.albedo_texture = load("res://tex_monitor.jpg")
	screen.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	screen.cull_mode = BaseMaterial3D.CULL_DISABLED
	screen.emission_enabled = true
	screen.emission_texture = load("res://tex_monitor.jpg")
	screen.emission = Color(1, 1, 1, 1)
	screen.emission_energy_multiplier = 2.0
	screen.render_priority = 10
	_mats["screen"] = screen

	# Window daylight panel: bright unshaded.
	var glow := _col(Color(0.85, 0.92, 1.0))
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.emission_enabled = true
	glow.emission = Color(0.85, 0.92, 1.0)
	glow.emission_energy_multiplier = 2.0
	_mats["glow"] = glow

	# Green chandelier glass.
	var glass := _col(Color(0.4, 0.9, 0.5, 0.5), 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.emission_enabled = true
	glass.emission = Color(0.4, 1.0, 0.5)
	glass.emission_energy_multiplier = 1.2
	_mats["glass"] = glass


# =============================================================================
# Primitive helpers
# =============================================================================
func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, nm := "Box") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.name = nm
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, nm := "Cyl") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 8          # low-poly
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.name = nm
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material, nm := "Sphere") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 8          # low-poly
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.name = nm
	parent.add_child(mi)
	return mi


## A flat textured quad (wall art). Faces +Z by default; pass rotation in degrees.
func _decal(parent: Node3D, path: String, size: Vector2, pos: Vector3, rot_deg: Vector3, nm := "Decal", soft_alpha := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	if soft_alpha:
		# Smooth edges for photo decals (scissor eats semi-transparent pixels).
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.name = nm
	parent.add_child(mi)
	return mi


## Static collision box so the player can't walk through major furniture.
func _collider(parent: Node3D, size: Vector3, pos: Vector3, nm := "Body") -> void:
	var body := StaticBody3D.new()
	body.name = nm
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
	parent.add_child(body)


## A cylinder (rod) spanning from point a to point b, oriented along its axis.
func _rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material, nm := "Rod") -> void:
	var mid := (a + b) * 0.5
	var mi := _cyl(parent, radius, a.distance_to(b), mid, mat, nm)
	var y_axis := (b - a).normalized()
	var ref := Vector3(0, 0, 1) if absf(y_axis.dot(Vector3(0, 0, 1))) < 0.99 else Vector3(1, 0, 0)
	var x_axis := y_axis.cross(ref).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	# Set the whole transform at once (cylinder's local +Y runs a -> b).
	mi.transform = Transform3D(Basis(x_axis, y_axis, z_axis), mid)


# =============================================================================
# Props
# =============================================================================
func _build_rug() -> void:
	# Grey zigzag runner down the centre walkway.
	_box(self, Vector3(0.85, 0.012, 2.6), Vector3(0, 0.007, -0.2), _mats["rug"], "Rug")


func _build_desk() -> void:
	var desk := Node3D.new()
	desk.name = "Desk"
	add_child(desk)
	var depth := 0.70          # X (into the room) — wider so the PC + keyboard fit
	var length := 1.80         # Z (along the wall)
	var cx := HALF_W - depth * 0.5   # back edge flush with the east wall
	var cz := -1.20            # near the window end
	# Top.
	_box(desk, Vector3(depth, 0.04, length), Vector3(cx, 0.74, cz), _mats["counter"], "Top")
	# Black metal legs.
	for sx in [-(depth * 0.5 - 0.04), depth * 0.5 - 0.04]:
		for sz in [-(length * 0.5 - 0.05), length * 0.5 - 0.05]:
			_box(desk, Vector3(0.05, 0.72, 0.05), Vector3(cx + sx, 0.36, cz + sz), _mats["metal"], "Leg")
	_collider(desk, Vector3(depth, 0.74, length), Vector3(cx, 0.37, cz), "DeskBody")
	_build_monitors(desk, cx, cz)


func _build_monitors(parent: Node3D, cx: float, cz: float) -> void:
	# One old PC model on the desk. Falls back to nothing if the GLB is missing.
	if not ResourceLoader.exists(COMPUTER_GLB):
		return
	var pc: Node3D = (load(COMPUTER_GLB) as PackedScene).instantiate()
	pc.name = "Computer"
	parent.add_child(pc)
	# Defer sizing/placement so the instanced GLB's transforms are settled.
	call_deferred("_finalize_computer", pc, cx, cz)


func _finalize_computer(pc: Node3D, cx: float, cz: float) -> void:
	if not is_instance_valid(pc):
		return
	pc.rotation_degrees = Vector3(0.0, COMPUTER_YAW, 0.0)
	var box := _mesh_aabb_in_space(pc, self)
	pc.scale = Vector3.ONE * (COMPUTER_TARGET_H / maxf(box.size.y, 0.001))
	box = _mesh_aabb_in_space(pc, self)
	var desk_top_y := 0.76    # desk top: centre 0.74 + half of 0.04 thickness
	pc.position = Vector3(
		cx - box.get_center().x,
		desk_top_y - box.position.y,
		cz - box.get_center().z,
	)


func _build_shelf() -> void:
	# White cube shelf (Kallax-style), east wall, between desk and door end.
	var shelf := Node3D.new()
	shelf.name = "Shelf"
	add_child(shelf)
	var cx := HALF_W - 0.175
	var cz := 0.25
	var t := 0.03
	var mat: Material = _mats["shelf"]
	# Outer shell.
	_box(shelf, Vector3(0.35, t, 0.75), Vector3(cx, 0.015, cz), mat, "Bottom")
	_box(shelf, Vector3(0.35, t, 0.75), Vector3(cx, 1.485, cz), mat, "Top")
	_box(shelf, Vector3(0.35, 1.5, t), Vector3(cx, 0.75, cz - 0.36), mat, "SideA")
	_box(shelf, Vector3(0.35, 1.5, t), Vector3(cx, 0.75, cz + 0.36), mat, "SideB")
	_box(shelf, Vector3(0.04, 1.5, 0.75), Vector3(cx + 0.155, 0.75, cz), mat, "Back")
	# Internal grid -> 2 columns x 4 rows of cubbies.
	_box(shelf, Vector3(0.33, 1.5, t), Vector3(cx, 0.75, cz), mat, "Divider")
	for y in [0.375, 0.75, 1.125]:
		_box(shelf, Vector3(0.33, t, 0.75), Vector3(cx, y, cz), mat, "Shelf")
	_collider(shelf, Vector3(0.35, 1.5, 0.75), Vector3(cx, 0.75, cz), "ShelfBody")


func _build_wardrobe() -> void:
	# Tall cream wardrobe, west wall near the door corner.
	var w := Node3D.new()
	w.name = "Wardrobe"
	add_child(w)
	var cx := -HALF_W + 0.275
	var cz := 1.50
	_box(w, Vector3(0.55, 2.3, 1.0), Vector3(cx, 1.15, cz), _mats["wardrobe"], "Body")
	# Door seam + two handles.
	_box(w, Vector3(0.56, 2.3, 0.02), Vector3(cx, 1.15, cz), _mats["metal"], "Seam")
	_box(w, Vector3(0.04, 0.18, 0.03), Vector3(cx + 0.28, 1.2, cz - 0.06), _mats["metal"], "HandleA")
	_box(w, Vector3(0.04, 0.18, 0.03), Vector3(cx + 0.28, 1.2, cz + 0.06), _mats["metal"], "HandleB")
	_collider(w, Vector3(0.55, 2.3, 1.0), Vector3(cx, 1.15, cz), "WardrobeBody")


func _build_sofa() -> void:
	if ResourceLoader.exists(SOFA_GLB):
		_build_sofa_from_glb()
		return
	_build_sofa_placeholder()


func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p := aabb.position
	var e := p + aabb.size
	return [
		Vector3(p.x, p.y, p.z), Vector3(e.x, p.y, p.z),
		Vector3(p.x, e.y, p.z), Vector3(e.x, e.y, p.z),
		Vector3(p.x, p.y, e.z), Vector3(e.x, p.y, e.z),
		Vector3(p.x, e.y, e.z), Vector3(e.x, e.y, e.z),
	]


## Axis-aligned bounds of all meshes under `root`, in `space` node's local coordinates.
func _mesh_aabb_in_space(root: Node3D, space: Node3D) -> AABB:
	var inv := space.global_transform.affine_inverse()
	var box := AABB()
	var has := false
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for corner in _aabb_corners(mi.mesh.get_aabb()):
			var p: Vector3 = inv * mi.global_transform * corner
			if not has:
				box = AABB(p, Vector3.ZERO)
				has = true
			else:
				box = box.expand(p)
	if not has:
		return AABB(Vector3.ZERO, Vector3.ONE)
	return box


func _pick_sofa_y_rotation(s: Node3D) -> float:
	# Long edge should run along room Z (parallel to the west wall).
	var best_deg := 0.0
	var best_len := 0.0
	for deg in [0.0, 90.0, -90.0, 180.0]:
		s.rotation_degrees = Vector3(0.0, deg, 0.0)
		var box := _mesh_aabb_in_space(s, self)
		if box.size.z > best_len:
			best_len = box.size.z
			best_deg = deg
	return best_deg


func _build_sofa_from_glb() -> void:
	var s: Node3D = (load(SOFA_GLB) as PackedScene).instantiate()
	s.name = "Sofa"
	add_child(s)
	call_deferred("_finalize_sofa_glb")


func _finalize_sofa_glb() -> void:
	var s: Node3D = get_node_or_null("Sofa") as Node3D
	if s == null:
		return
	s.rotation_degrees = Vector3(0.0, _pick_sofa_y_rotation(s), 0.0)
	var box := _mesh_aabb_in_space(s, self)
	var sc := Vector3(
		SOFA_TARGET_SIZE.x / maxf(box.size.x, 0.001),
		SOFA_TARGET_SIZE.y / maxf(box.size.y, 0.001),
		SOFA_TARGET_SIZE.z / maxf(box.size.z, 0.001),
	)
	s.scale = sc
	box = _mesh_aabb_in_space(s, self)
	var wall_x := -HALF_W + SOFA_WALL_GAP
	s.position = Vector3(
		wall_x - box.position.x,
		-box.position.y,
		SOFA_CENTER_Z - (box.position.z + box.size.z * 0.5),
	)
	_collider(s, box.size, box.get_center(), "SofaBody")
	_attach_sofa_accessories(s)


func _style_glb_meshes(root: Node3D, mat: Material) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat


func _sofa_seat_metrics(sofa: Node3D) -> Dictionary:
	# Measured in ROOM space: this already bakes in the sofa's (non-uniform)
	# scale + rotation, so accessories parented to `self` stay un-sheared.
	var b := _mesh_aabb_in_space(sofa, self)
	# West wall = min X; seat cushion is the forward (+X, room-facing) part.
	return {
		"top_y": b.position.y + b.size.y * 0.42,
		"cx": b.position.x + b.size.x * 0.62,
		"cz": b.position.z + b.size.z * 0.50,
		"half_z": b.size.z * 0.44,
		"window_z": b.position.z + b.size.z * 0.24,
	}


func _pick_flat_rotation_deg(item: Node3D, parent: Node3D) -> Vector3:
	var best := Vector3.ZERO
	var best_h := INF
	parent.add_child(item)
	item.position = Vector3.ZERO
	for rot: Vector3 in [
		Vector3.ZERO,
		Vector3(-90, 0, 0), Vector3(90, 0, 0),
		Vector3(0, -90, 0), Vector3(0, 90, 0),
		Vector3(0, 0, -90), Vector3(0, 0, 90),
	]:
		item.rotation_degrees = rot
		item.scale = Vector3.ONE * GLB_UNIT_SCALE
		var h: float = _mesh_aabb_in_space(item, parent).size.y
		if h < best_h:
			best_h = h
			best = rot
	item.rotation_degrees = best
	return best


func _fit_glb_flat_on_seat(item: Node3D, parent: Node3D, xz_size: Vector2) -> AABB:
	_pick_flat_rotation_deg(item, parent)
	var box := _mesh_aabb_in_space(item, parent)
	var src := maxf(box.size.x, box.size.z)
	if src < 0.02:
		src = maxf(box.size.x, maxf(box.size.y, box.size.z))
	var dst := maxf(xz_size.x, xz_size.y)
	var s := dst / maxf(src, 0.001)
	item.scale = Vector3.ONE * (GLB_UNIT_SCALE * s)
	return _mesh_aabb_in_space(item, parent)


func _seat_bottom_position(box: AABB, seat: Dictionary, offset: Vector3) -> Vector3:
	# Sit on the cushion: align the mesh bottom to seat_top_y.
	return Vector3(
		seat["cx"] - box.get_center().x + offset.x,
		seat["top_y"] - box.position.y + offset.y,
		seat["cz"] - box.get_center().z + offset.z,
	)


func _attach_sofa_accessories(sofa: Node3D) -> void:
	var blue: Material = _mats["sofa_blue"]
	var seat := _sofa_seat_metrics(sofa)
	# Real-world (room-space) footprint of the sofa, so sizes are in metres.
	var sb := _mesh_aabb_in_space(sofa, self)
	var pillow_xz := Vector2(sb.size.x * 0.42, sb.size.z * 0.22)    # ~0.46 × 0.52 m cushion

	# Parent to `self` (uniform scale) — NOT to the non-uniformly scaled sofa,
	# otherwise the items get sheared/stretched.
	if ResourceLoader.exists(PILLOW_GLB):
		var pillow: Node3D = (load(PILLOW_GLB) as PackedScene).instantiate()
		pillow.name = "Pillow"
		_style_glb_meshes(pillow, blue)
		var p_box := _fit_glb_flat_on_seat(pillow, self, pillow_xz)
		# Window end of the daybed (−Z), resting on the cushion by the backrest.
		pillow.position = Vector3(
			seat["cx"] - p_box.get_center().x - 0.06,
			seat["top_y"] - p_box.position.y + 0.02,
			seat["window_z"] - p_box.get_center().z,
		)


func _build_sofa_placeholder() -> void:
	# Fallback until res://models/sofa.glb exists.
	var s := Node3D.new()
	s.name = "Sofa"
	add_child(s)
	var cx := -HALF_W + 0.44
	var cz := -0.55
	var beige: Material = _mats["sofa_beige"]
	# Pull-out base slab.
	_box(s, Vector3(0.74, 0.22, 1.90), Vector3(cx, 0.11, cz), beige, "Base")
	# Back rest against the wall.
	_box(s, Vector3(0.12, 0.40, 1.72), Vector3(cx - 0.31, 0.37, cz), beige, "Back")
	# Seat cushion (flush with base — reads as one piece).
	_box(s, Vector3(0.62, 0.14, 1.38), Vector3(cx + 0.02, 0.30, cz), beige, "Seat")
	# Rounded end caps (barrels along Z, low-poly).
	for z in [cz - 0.80, cz + 0.80]:
		var end_cap := _cyl(s, 0.19, 0.68, Vector3(cx + 0.04, 0.34, z), beige, "EndCap")
		end_cap.rotation_degrees = Vector3(90, 0, 0)
	# Chrome legs.
	for lx in [cx - 0.26, cx + 0.04]:
		for lz in [cz - 0.78, cz + 0.78]:
			_cyl(s, 0.025, 0.09, Vector3(lx, 0.045, lz), _mats["chrome"], "Leg")
	_collider(s, Vector3(0.76, 0.52, 1.90), Vector3(cx, 0.26, cz), "SofaBody")
	_attach_sofa_accessories(s)


func _build_pullup_bar() -> void:
	# Pull-up bar above the wardrobe end of the west wall (not over the sofa).
	var bar := Node3D.new()
	bar.name = "PullUpBar"
	add_child(bar)
	var wall_x := -HALF_W + 0.01
	for bz in [0.75, 1.45]:
		_box(bar, Vector3(0.28, 0.04, 0.04), Vector3(wall_x + 0.14, 2.38, bz), _mats["metal"], "Bracket")
	_rod(bar, Vector3(wall_x + 0.26, 2.38, 0.55), Vector3(wall_x + 0.26, 2.38, 1.65), 0.025, _mats["metal"], "Bar")


func _build_window() -> void:
	# Balcony window on the north wall (-Z): glow panel, tulle, side drapes.
	var win := Node3D.new()
	win.name = "Window"
	add_child(win)
	var z := -HALF_L
	_box(win, Vector3(1.5, 1.5, 0.02), Vector3(0, 1.5, z + 0.02), _mats["glow"], "Daylight")
	var tl := _decal(win, "res://tex_tulle.jpg", Vector2(1.6, 1.7), Vector3(0, 1.5, z + 0.14), Vector3.ZERO, "Tulle")
	tl.material_override = _mats["tulle"]
	# Brown side drapes + valance.
	for dx in [-0.85, 0.85]:
		_box(win, Vector3(0.38, 2.2, 0.06), Vector3(dx, 1.35, z + 0.18), _mats["curtain"], "Drape")
	_box(win, Vector3(1.95, 0.28, 0.12), Vector3(0, 2.45, z + 0.16), _mats["curtain"], "Valance")
	# White sill.
	_box(win, Vector3(1.7, 0.06, 0.12), Vector3(0, 0.72, z + 0.1), _mats["chair"], "Sill")


func _build_chandelier() -> void:
	# Chrome ceiling light with three green glass shades, centred under the lamp.
	var ch := Node3D.new()
	ch.name = "Chandelier"
	add_child(ch)
	var hub := Vector3(0, 2.43, 0)
	_cyl(ch, 0.08, 0.05, Vector3(0, 2.66, 0), _mats["chrome"], "Canopy")
	_cyl(ch, 0.015, 0.2, Vector3(0, 2.54, 0), _mats["chrome"], "Rod")
	_sphere(ch, 0.07, hub, _mats["chrome"], "Hub")
	for i in 3:
		var ang := deg_to_rad(float(i) * 120.0)
		var shade := Vector3(cos(ang) * 0.28, 2.33, sin(ang) * 0.28)
		_rod(ch, hub, shade, 0.012, _mats["chrome"], "Arm")
		_sphere(ch, 0.09, shade, _mats["glass"], "Shade")


func _build_decals() -> void:
	# Wall art on the east wall above the desk (faces -X into the room).
	var x := HALF_W - 0.015
	_decal(self, "res://decal_worldmap.png", Vector2(1.6, 0.95), Vector3(x, 1.78, -0.7), Vector3(0, -90, 0), "WorldMap")
	_decal(self, "res://decal_clock.png", Vector2(0.4, 0.4), Vector3(x, 1.95, 0.78), Vector3(0, -90, 0), "Clock")
	_decal(self, "res://decal_frames.png", Vector2(0.35, 0.42), Vector3(x, 1.68, 1.35), Vector3(0, -90, 0), "Portrait", true)

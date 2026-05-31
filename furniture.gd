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

var _mats := {}


func _ready() -> void:
	_build_materials()
	_build_rug()
	_build_desk()
	_build_chair()
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
func _tex(path: String, scale := Vector3.ONE, rough := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # crisp PS1 pixels
	m.roughness = rough
	m.metallic = 0.0
	m.uv1_scale = scale
	return m


func _col(color: Color, rough := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = rough
	m.metallic = metallic
	return m


func _build_materials() -> void:
	_mats["counter"]   = _tex("res://tex_countertop.jpg", Vector3(1, 1, 2))
	_mats["shelf"]     = _tex("res://tex_shelf_white.jpg")
	_mats["wardrobe"]  = _tex("res://tex_wardrobe.jpg", Vector3(1, 2, 1))
	_mats["sofa_navy"] = _tex("res://tex_sofa_navy.jpg")
	_mats["sofa_beige"] = _tex("res://tex_sofa_beige.jpg")
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

	# Monitor screen: lightly self-lit so it reads like a glowing display.
	var screen := _tex("res://tex_monitor.jpg")
	screen.emission_enabled = true
	screen.emission_texture = load("res://tex_monitor.jpg")
	screen.emission_energy_multiplier = 0.5
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
func _decal(parent: Node3D, path: String, size: Vector2, pos: Vector3, rot_deg: Vector3, nm := "Decal") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
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
	var cx := -HALF_W + 0.30   # against the west wall
	var cz := -1.20            # near the window end
	# Top.
	_box(desk, Vector3(0.6, 0.04, 1.5), Vector3(cx, 0.74, cz), _mats["counter"], "Top")
	# Black metal legs.
	for sx in [-0.27, 0.27]:
		for sz in [-0.71, 0.71]:
			_box(desk, Vector3(0.05, 0.72, 0.05), Vector3(cx + sx, 0.36, cz + sz), _mats["metal"], "Leg")
	_collider(desk, Vector3(0.6, 0.74, 1.5), Vector3(cx, 0.37, cz), "DeskBody")
	_build_monitors(desk, cx, cz)


func _build_monitors(parent: Node3D, cx: float, cz: float) -> void:
	# Two monitors on the desk, screens facing +X (toward the chair).
	for mz in [cz - 0.35, cz + 0.30]:
		var px := cx - 0.16
		# Stand + bezel.
		_box(parent, Vector3(0.04, 0.04, 0.18), Vector3(px, 0.78, mz), _mats["metal"], "MonStand")
		_box(parent, Vector3(0.03, 0.34, 0.5), Vector3(px, 1.0, mz), _mats["metal"], "MonBezel")
		# Glowing screen quad on the +X face (emissive screen material).
		var scr := _decal(parent, "res://tex_monitor.jpg", Vector2(0.46, 0.30), Vector3(px + 0.02, 1.0, mz), Vector3(0, 90, 0), "Screen")
		scr.material_override = _mats["screen"]


func _build_chair() -> void:
	var chair := Node3D.new()
	chair.name = "Chair"
	add_child(chair)
	var cx := -0.55
	var cz := -1.05
	_box(chair, Vector3(0.45, 0.08, 0.45), Vector3(cx, 0.5, cz), _mats["chair"], "Seat")
	_box(chair, Vector3(0.08, 0.5, 0.45), Vector3(cx + 0.20, 0.78, cz), _mats["chair"], "Back")
	_cyl(chair, 0.035, 0.42, Vector3(cx, 0.27, cz), _mats["metal"], "Post")
	_cyl(chair, 0.26, 0.04, Vector3(cx, 0.06, cz), _mats["metal"], "Base")


func _build_shelf() -> void:
	# White cube shelf (Kallax-style), west wall, between desk and door end.
	var shelf := Node3D.new()
	shelf.name = "Shelf"
	add_child(shelf)
	var cx := -HALF_W + 0.175
	var cz := 0.25
	var t := 0.03
	var mat: Material = _mats["shelf"]
	# Outer shell.
	_box(shelf, Vector3(0.35, t, 0.75), Vector3(cx, 0.015, cz), mat, "Bottom")
	_box(shelf, Vector3(0.35, t, 0.75), Vector3(cx, 1.485, cz), mat, "Top")
	_box(shelf, Vector3(0.35, 1.5, t), Vector3(cx, 0.75, cz - 0.36), mat, "SideA")
	_box(shelf, Vector3(0.35, 1.5, t), Vector3(cx, 0.75, cz + 0.36), mat, "SideB")
	_box(shelf, Vector3(0.04, 1.5, 0.75), Vector3(cx - 0.155, 0.75, cz), mat, "Back")
	# Internal grid -> 2 columns x 4 rows of cubbies.
	_box(shelf, Vector3(0.33, 1.5, t), Vector3(cx, 0.75, cz), mat, "Divider")
	for y in [0.375, 0.75, 1.125]:
		_box(shelf, Vector3(0.33, t, 0.75), Vector3(cx, y, cz), mat, "Shelf")
	_collider(shelf, Vector3(0.35, 1.5, 0.75), Vector3(cx, 0.75, cz), "ShelfBody")


func _build_wardrobe() -> void:
	# Tall cream wardrobe, east wall near the door corner.
	var w := Node3D.new()
	w.name = "Wardrobe"
	add_child(w)
	var cx := HALF_W - 0.275
	var cz := 1.50
	_box(w, Vector3(0.55, 2.3, 1.0), Vector3(cx, 1.15, cz), _mats["wardrobe"], "Body")
	# Door seam + two handles.
	_box(w, Vector3(0.56, 2.3, 0.02), Vector3(cx, 1.15, cz), _mats["metal"], "Seam")
	_box(w, Vector3(0.04, 0.18, 0.03), Vector3(cx - 0.28, 1.2, cz - 0.06), _mats["metal"], "HandleA")
	_box(w, Vector3(0.04, 0.18, 0.03), Vector3(cx - 0.28, 1.2, cz + 0.06), _mats["metal"], "HandleB")
	_collider(w, Vector3(0.55, 2.3, 1.0), Vector3(cx, 1.15, cz), "WardrobeBody")


func _build_sofa() -> void:
	# Blue day-bed / sofa, east wall.
	var s := Node3D.new()
	s.name = "Sofa"
	add_child(s)
	var cx := HALF_W - 0.45
	var cz := -0.55
	_box(s, Vector3(0.85, 0.35, 1.95), Vector3(cx, 0.175, cz), _mats["sofa_beige"], "Base")
	_box(s, Vector3(0.8, 0.16, 1.9), Vector3(cx, 0.43, cz), _mats["sofa_navy"], "Seat")
	_box(s, Vector3(0.18, 0.55, 1.95), Vector3(cx + 0.33, 0.6, cz), _mats["sofa_navy"], "Back")
	# Arms at both ends.
	for az in [cz - 0.9, cz + 0.9]:
		_box(s, Vector3(0.85, 0.45, 0.16), Vector3(cx, 0.33, az), _mats["sofa_beige"], "Arm")
	# Accent pillow.
	_box(s, Vector3(0.5, 0.18, 0.42), Vector3(cx, 0.62, cz + 0.6), _mats["pillow"], "Pillow")
	_collider(s, Vector3(0.85, 0.6, 1.95), Vector3(cx, 0.3, cz), "SofaBody")


func _build_pullup_bar() -> void:
	# Black wall-mounted pull-up bar above the sofa (east wall).
	var bar := Node3D.new()
	bar.name = "PullUpBar"
	add_child(bar)
	var wall_x := HALF_W - 0.01
	for bz in [-1.2, 0.0]:
		_box(bar, Vector3(0.28, 0.04, 0.04), Vector3(wall_x - 0.14, 2.0, bz), _mats["metal"], "Bracket")
	_rod(bar, Vector3(wall_x - 0.26, 2.0, -1.25), Vector3(wall_x - 0.26, 2.0, 0.05), 0.025, _mats["metal"], "Bar")


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
	# Wall art on the west wall (faces +X into the room).
	var x := -HALF_W + 0.015
	_decal(self, "res://decal_worldmap.png", Vector2(1.6, 0.95), Vector3(x, 1.78, -0.7), Vector3(0, 90, 0), "WorldMap")
	_decal(self, "res://decal_clock.png", Vector2(0.4, 0.4), Vector3(x, 1.95, 0.78), Vector3(0, 90, 0), "Clock")
	_decal(self, "res://decal_frames.png", Vector2(0.62, 0.5), Vector3(x, 1.68, 1.35), Vector3(0, 90, 0), "Frames")

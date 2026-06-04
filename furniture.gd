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

## Real old computer desk model. It is scaled as a child of Desk so the Computer rig
## keeps its own scale/children and can be dragged together with the terminal
## hitboxes.
const COMPUTER_OLD_DESK_GLB := "res://models/computer_old_desk.glb"
const COMPUTER_OLD_DESK_TARGET_H := 0.76
const COMPUTER_OLD_DESK_TARGET_DEPTH := 0.84
const COMPUTER_OLD_DESK_TARGET_L := 1.34

## Single retro PC model on the desk (replaces the two procedural CRT boxes).
const COMPUTER_GLB := "res://models/retro_computer.glb"
const COMPUTER_TARGET_H := 0.42   # overall height in metres (tweak to taste)
const COMPUTER_YAW := 90.0        # face the screen toward the sofa

const PORTRAIT_GLB := "res://models/portrait.glb"
const PORTRAIT_TARGET_H := 0.62
const PORTRAIT_WIDTH_STRETCH := 1.1314758
const PORTRAIT_CENTER_Y := 1.68
const PORTRAIT_CENTER_Z := 1.35

const WOODEN_SHELF_GLB := "res://models/wooden_shelf.glb"
const WOODEN_SHELF_TARGET_H := 1.55
const WOODEN_SHELF_CENTER_Z := 0.56
const WOODEN_SHELF_WALL_GAP := 0.0

const CLOCK_GLB := "res://models/clock.glb"
const CLOCK_HANDS_SCRIPT := preload("res://clock_hands.gd")
const CLOCK_CENTER := Vector3(HALF_W - 0.015, 1.95, 0.78)
const CLOCK_YAW := -90.0

## Optional hanging-lamp model. Drop models/chandelier.glb in and it replaces the
## procedural chandelier (auto-scaled, hung from the ceiling, centred in the room).
const CHANDELIER_GLB := "res://models/chandelier.glb"
const CHANDELIER_TARGET_H := 0.55   # model height in metres
const CHANDELIER_CEILING_Y := 2.70  # interior ceiling surface (room is 2.75 − half slab)
const CHANDELIER_DROP := 0.0        # extra metres to lower it below the ceiling

## Optional radiator model under the balcony window. Drop models/radiator.glb in.
const RADIATOR_GLB := "res://models/radiator.glb"
const RADIATOR_TARGET_W := 0.70     # width along the wall (X) in metres
const RADIATOR_YAW := 0.0           # spin if it faces the wrong way

## Optional balcony-door model (replaces the procedural door leaf on the right).
const BALCONY_DOOR_GLB := "res://models/balcony_door.glb"
const BALCONY_DOOR_TARGET_H := 2.05 # door height in metres (fills the opening)
const BALCONY_DOOR_YAW := 0.0       # spin 180 if it faces the balcony, not the room

## Optional curtains model hung over the balcony window (auto-fit).
const CURTAINS_GLB := "res://models/curtains.glb"
const CURTAINS_TARGET_H := 2.20     # curtain height in metres
const CURTAINS_YAW := 90.0          # rotate so the wide span runs across the window
const CURTAINS_TOP_Y := 2.32        # where the TOP of the curtains hangs

## Wardrobe model (replaces the procedural cream box on the west wall).
const WARDROBE_GLB := "res://models/wardrobe.glb"
const WARDROBE_TARGET_H := 2.30     # height in metres
const WARDROBE_YAW := 0.0           # spin (90/180) if the front faces the wrong way
const WARDROBE_CENTER_Z := 1.50     # position along the west wall
const WARDROBE_WALL_GAP := 0.02     # gap from the west wall

## "КОРСАР1" firecracker box — a re-textured, decimated version of the scanned GLB
## with the КОРСАР1 dieline baked onto box-projected UVs (built by
## tools/texture_petard.py). Auto-laid flat on the desk and shrunk to a small prop.
const PETARD_GLB := "res://models/korobka_dlya_petard_tex.glb"
const PETARD_TARGET_L := 0.14      # longest footprint dimension in metres (small box)
# The glowing CRT overlay lives in main.tscn as the "ComputerScreen" node.
#
# Editing model: this script is @tool and runs ONCE to populate the scene with
# real, editable nodes (see _ready / _finish_editor_populate). Anything any
# _build_* function adds — including future GLB models — automatically becomes a
# saved, draggable node, so new props are editable by default with no extra work:
# just write a _build_* that adds it, open the scene, and Ctrl+S.

var _mats := {}

## Editor button: tick this in the Inspector to (re)build just the КОРСАР1 box on
## the desk without reloading the scene or touching the rest of the furniture.
@export var rebuild_petard_box := false:
	set(value):
		rebuild_petard_box = false          # one-shot: never actually stays on
		if not value:
			return                           # ignore the false written on scene load
		if not Engine.is_editor_hint():
			return
		for nm in ["PetardBox", "PetardLabel"]:
			var old := get_node_or_null(nm)
			if old:
				old.free()
		_build_petard_box()
		call_deferred("_finish_editor_populate")


func _ready() -> void:
	# The furniture is generated ONCE as real, editable scene nodes. Once it has
	# been built in the editor and saved (Ctrl+S), the nodes live in main.tscn and
	# this guard leaves them alone — so your hand tweaks are never overwritten.
	# (At runtime, if the scene was never populated, it falls back to an ephemeral
	# build so the game still looks right.)
	if get_child_count() > 0:
		# Already baked into the scene. Don't rebuild — but DO add any newly
		# introduced prop that isn't present yet, and swap out superseded ones, so
		# changes appear without nuking the hand-tweaked nodes saved in main.tscn.
		var changed := _migrate_wardrobe_if_needed()
		if not has_node("PetardBox"):
			_build_petard_box()
			changed = true
		if not has_node("WallCalendar"):
			if _mats.is_empty():
				_build_materials()
			_build_wall_calendar()
			changed = true
		if not has_node("Portrait") and ResourceLoader.exists(PORTRAIT_GLB):
			_build_wall_portrait()
			changed = true
		if changed and Engine.is_editor_hint():
			call_deferred("_finish_editor_populate")
		return
	_build_materials()
	_build_rug()
	_build_desk()
	_build_shelf()
	_build_wardrobe()
	_build_sofa()
	_build_pullup_bar()
	_build_window()
	_build_radiator()
	_build_curtains()
	_build_chandelier()
	_build_petard_box()
	_build_decals()
	if Engine.is_editor_hint():
		# Runs after the deferred GLB finalizers (FIFO): turns every generated node
		# into a saved, selectable, draggable part of the scene.
		call_deferred("_finish_editor_populate")


## Editor only: make all generated furniture owned by the scene root so it saves
## into main.tscn and becomes selectable / draggable. After the first Ctrl+S the
## _ready() guard keeps this from ever running again (delete the Furniture node's
## children and reopen the scene if you ever want to regenerate from scratch).
func _finish_editor_populate() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var root := tree.edited_scene_root
	if root == null:
		return
	for child in get_children():
		_own_recursive(child, root)
	print("[Furniture] Built editable furniture nodes — press Ctrl+S to bake them ",
		"into the scene. After saving, this script no longer touches them.")


func _own_recursive(node: Node, root: Node) -> void:
	node.owner = root
	# An instanced scene (GLB) saves as a clean instance reference and brings its
	# own internal nodes from the resource. Owning those internals too would write
	# duplicates and cause "node name conflicts" on load — so stop at the instance.
	if node.scene_file_path != "":
		return
	for c in node.get_children():
		_own_recursive(c, root)


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
	_mats["pvc"]       = _col(Color(0.93, 0.94, 0.96), 0.5)        # white PVC window/door frames

	# Window glass: faint blue, see-through (bright daylight shows behind it).
	var gwin := _col(Color(0.7, 0.85, 1.0, 0.16), 0.05)
	gwin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gwin.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["glass_win"] = gwin

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
	if ResourceLoader.exists(COMPUTER_OLD_DESK_GLB):
		var desk_length := COMPUTER_OLD_DESK_TARGET_L
		var desk_cz := -1.20
		var table: Node3D = (load(COMPUTER_OLD_DESK_GLB) as PackedScene).instantiate()
		table.name = "ComputerOldDesk"
		desk.add_child(table)
		call_deferred("_finalize_computer_old_desk", table, desk_cz)
		var collider_cx := HALF_W - COMPUTER_OLD_DESK_TARGET_DEPTH * 0.5
		_collider(desk, Vector3(COMPUTER_OLD_DESK_TARGET_DEPTH, 0.74, desk_length), Vector3(collider_cx, 0.37, desk_cz), "DeskBody")
		var computer_cx := HALF_W - 0.70 * 0.5
		_build_monitors(desk, computer_cx, desk_cz)
		return
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
	var lbox := _local_aabb(pc)
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(COMPUTER_YAW), 0.0))
	var rbox := _aabb_transformed(lbox, Transform3D(basis, Vector3.ZERO))
	var k := COMPUTER_TARGET_H / maxf(rbox.size.y, 0.001)
	var sbox := AABB(rbox.position * k, rbox.size * k)
	pc.rotation_degrees = Vector3(0.0, COMPUTER_YAW, 0.0)
	pc.scale = Vector3.ONE * k
	var desk_top_y := 0.76    # desk top: centre 0.74 + half of 0.04 thickness
	pc.position = Vector3(
		cx - sbox.get_center().x,
		desk_top_y - sbox.position.y,
		cz - sbox.get_center().z,
	)


func _finalize_computer_old_desk(table: Node3D, cz: float) -> void:
	if not is_instance_valid(table):
		return
	var lbox := _local_aabb(table)
	var k := COMPUTER_OLD_DESK_TARGET_H / maxf(lbox.size.y, 0.001)
	table.scale = Vector3.ONE * k
	var sbox := AABB(lbox.position * k, lbox.size * k)
	table.position = Vector3(
		HALF_W - sbox.end.x,
		-sbox.position.y,
		cz - sbox.get_center().z,
	)


func _build_shelf() -> void:
	if ResourceLoader.exists(WOODEN_SHELF_GLB):
		var shelf: Node3D = (load(WOODEN_SHELF_GLB) as PackedScene).instantiate()
		shelf.name = "Shelf"
		add_child(shelf)
		call_deferred("_finalize_wooden_shelf", shelf)
		return
	_build_shelf_procedural()


func _build_shelf_procedural() -> void:
	var shelf := Node3D.new()
	shelf.name = "Shelf"
	add_child(shelf)
	var cx := HALF_W - 0.175
	var cz := 0.25
	var t := 0.03
	var mat: Material = _mats["shelf"]
	_box(shelf, Vector3(0.35, t, 0.75), Vector3(cx, 0.015, cz), mat, "Bottom")
	_box(shelf, Vector3(0.35, t, 0.75), Vector3(cx, 1.485, cz), mat, "Top")
	_box(shelf, Vector3(0.35, 1.5, t), Vector3(cx, 0.75, cz - 0.36), mat, "SideA")
	_box(shelf, Vector3(0.35, 1.5, t), Vector3(cx, 0.75, cz + 0.36), mat, "SideB")
	_box(shelf, Vector3(0.04, 1.5, 0.75), Vector3(cx + 0.155, 0.75, cz), mat, "Back")
	_box(shelf, Vector3(0.33, 1.5, t), Vector3(cx, 0.75, cz), mat, "Divider")
	for y in [0.375, 0.75, 1.125]:
		_box(shelf, Vector3(0.33, t, 0.75), Vector3(cx, y, cz), mat, "Shelf")
	_collider(shelf, Vector3(0.35, 1.5, 0.75), Vector3(cx, 0.75, cz), "ShelfBody")


func _finalize_wooden_shelf(shelf: Node3D) -> void:
	if not is_instance_valid(shelf):
		return
	var lbox := _local_aabb(shelf)
	var k := WOODEN_SHELF_TARGET_H / maxf(lbox.size.y, 0.001)
	var sbox := AABB(lbox.position * k, lbox.size * k)
	shelf.scale = Vector3.ONE * k
	shelf.position = Vector3(
		HALF_W - WOODEN_SHELF_WALL_GAP - sbox.end.x,
		-sbox.position.y,
		WOODEN_SHELF_CENTER_Z - sbox.get_center().z,
	)
	_collider(self, sbox.size, Vector3(
		shelf.position.x + sbox.get_center().x,
		shelf.position.y + sbox.get_center().y,
		shelf.position.z + sbox.get_center().z
	), "ShelfBody")


func _build_wardrobe() -> void:
	# Prefer a real GLB wardrobe if present; otherwise the procedural cream box.
	if ResourceLoader.exists(WARDROBE_GLB):
		_build_wardrobe_from_glb()
		return
	_build_wardrobe_procedural()


func _build_wardrobe_procedural() -> void:
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


func _build_wardrobe_from_glb() -> void:
	var w: Node3D = (load(WARDROBE_GLB) as PackedScene).instantiate()
	w.name = "Wardrobe"
	add_child(w)
	# Defer sizing/placement so the instanced GLB's transforms are settled.
	call_deferred("_finalize_wardrobe", w)


func _finalize_wardrobe(w: Node3D) -> void:
	if not is_instance_valid(w):
		return
	var lbox := _local_aabb(w)
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(WARDROBE_YAW), 0.0))
	var rbox := _aabb_transformed(lbox, Transform3D(basis, Vector3.ZERO))
	var k := WARDROBE_TARGET_H / maxf(rbox.size.y, 0.001)
	var sbox := AABB(rbox.position * k, rbox.size * k)   # final bounds at position 0
	w.rotation_degrees = Vector3(0.0, WARDROBE_YAW, 0.0)
	w.scale = Vector3.ONE * k
	var wall_x := -HALF_W + WARDROBE_WALL_GAP
	w.position = Vector3(
		wall_x - sbox.position.x,                  # back flush against the west wall
		0.0 - sbox.position.y,                     # bottom on the floor
		WARDROBE_CENTER_Z - sbox.get_center().z,   # centred along the wall
	)
	# Room-space collider as a sibling so the GLB's scale doesn't shear it.
	var room_box := AABB(sbox.position + w.position, sbox.size)
	_collider(self, room_box.size, room_box.get_center(), "WardrobeBody")


## Replace the old procedural box wardrobe (baked in main.tscn) with the GLB once
## the model exists. Returns true if it swapped anything. Self-healing: after the
## scene is re-saved with the GLB instance, this becomes a no-op.
func _migrate_wardrobe_if_needed() -> bool:
	if not ResourceLoader.exists(WARDROBE_GLB):
		return false
	var old := get_node_or_null("Wardrobe")
	# The procedural version is a plain Node3D with a "Body" box child; the GLB
	# version is an instanced scene (scene_file_path set). Only replace the box.
	var is_procedural := old != null and old.scene_file_path == "" and old.has_node("Body")
	if old != null and not is_procedural:
		return false
	if old != null:
		old.free()
	var old_body := get_node_or_null("WardrobeBody")
	if old_body != null:
		old_body.free()
	_build_wardrobe_from_glb()
	return true


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


## Mesh bounds in a node's OWN local space. Unlike measuring against another node,
## this cancels the node's global transform exactly, so it's reliable even inside
## a deferred editor call where global_transform may not be flushed yet.
func _local_aabb(root: Node3D) -> AABB:
	return _mesh_aabb_in_space(root, root)


## AABB of `box` after applying a transform (corner-by-corner).
func _aabb_transformed(box: AABB, xform: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	for c in _aabb_corners(box):
		var p: Vector3 = xform * c
		if first:
			out = AABB(p, Vector3.ZERO)
			first = false
		else:
			out = out.expand(p)
	return out


func _pick_sofa_y_rotation(s: Node3D) -> float:
	# Long edge should run along room Z (parallel to the west wall). Tested via
	# arithmetic on the local bounds (reliable in this deferred editor call).
	var lbox := _local_aabb(s)
	var best_deg := 0.0
	var best_len := 0.0
	for deg in [0.0, 90.0, -90.0, 180.0]:
		var b := Basis.from_euler(Vector3(0.0, deg_to_rad(deg), 0.0))
		var rb := _aabb_transformed(lbox, Transform3D(b, Vector3.ZERO))
		if rb.size.z > best_len:
			best_len = rb.size.z
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
	var rot := _pick_sofa_y_rotation(s)
	var lbox := _local_aabb(s)
	# Rotated (scale 1) bounds → per-axis scale to hit the target size.
	var rbox := _aabb_transformed(lbox, Transform3D(Basis.from_euler(Vector3(0.0, deg_to_rad(rot), 0.0)), Vector3.ZERO))
	var sc := Vector3(
		SOFA_TARGET_SIZE.x / maxf(rbox.size.x, 0.001),
		SOFA_TARGET_SIZE.y / maxf(rbox.size.y, 0.001),
		SOFA_TARGET_SIZE.z / maxf(rbox.size.z, 0.001),
	)
	s.rotation_degrees = Vector3(0.0, rot, 0.0)
	s.scale = sc
	# Final bounds at position 0, from the just-set LOCAL basis (reliable — only
	# global_transform is flaky inside this deferred call, the local one is not).
	var box := _aabb_transformed(lbox, Transform3D(s.transform.basis, Vector3.ZERO))
	var wall_x := -HALF_W + SOFA_WALL_GAP
	var s_pos := Vector3(
		wall_x - box.position.x,
		-box.position.y,
		SOFA_CENTER_Z - (box.position.z + box.size.z * 0.5),
	)
	s.position = s_pos
	# NOTE: the sofa's collision lives as a permanent, hand-editable "SofaBody"
	# node in main.tscn (under Main), so it is NOT regenerated here — tweak it by
	# hand and it stays put across furniture rebuilds.
	# Sofa bounds in room space (pos-0 bounds shifted by the translation).
	_attach_sofa_accessories(s, AABB(box.position + s_pos, box.size))


func _style_glb_meshes(root: Node3D, mat: Material) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat


func _sofa_seat_metrics(b: AABB) -> Dictionary:
	# `b` is the sofa's room-space bounds (already includes its non-uniform scale
	# + rotation), so accessories parented to `self` stay un-sheared.
	# West wall = min X; seat cushion is the forward (+X, room-facing) part.
	return {
		"top_y": b.position.y + b.size.y * 0.42,
		"cx": b.position.x + b.size.x * 0.62,
		"cz": b.position.z + b.size.z * 0.50,
		"half_z": b.size.z * 0.44,
		"window_z": b.position.z + b.size.z * 0.24,
	}


func _euler_basis(rot_deg: Vector3) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))


func _pick_flat_rotation_deg(item: Node3D, parent: Node3D) -> Vector3:
	# Lay the item as flat as possible (smallest Y), tested on the local bounds.
	parent.add_child(item)
	item.position = Vector3.ZERO
	var lbox := _local_aabb(item)
	var best := Vector3.ZERO
	var best_h := INF
	for rot: Vector3 in [
		Vector3.ZERO,
		Vector3(-90, 0, 0), Vector3(90, 0, 0),
		Vector3(0, -90, 0), Vector3(0, 90, 0),
		Vector3(0, 0, -90), Vector3(0, 0, 90),
	]:
		var h: float = _aabb_transformed(lbox, Transform3D(_euler_basis(rot), Vector3.ZERO)).size.y
		if h < best_h:
			best_h = h
			best = rot
	item.rotation_degrees = best
	return best


func _fit_glb_flat_on_seat(item: Node3D, parent: Node3D, xz_size: Vector2) -> AABB:
	var rot := _pick_flat_rotation_deg(item, parent)
	var lbox := _local_aabb(item)
	var rbox := _aabb_transformed(lbox, Transform3D(_euler_basis(rot), Vector3.ZERO))
	var src := maxf(rbox.size.x, rbox.size.z)
	if src < 0.02:
		src = maxf(rbox.size.x, maxf(rbox.size.y, rbox.size.z))
	var dst := maxf(xz_size.x, xz_size.y)
	item.scale = Vector3.ONE * (dst / maxf(src, 0.001))
	# Final bounds at position 0, from the just-set local basis (reliable).
	return _aabb_transformed(lbox, Transform3D(item.transform.basis, Vector3.ZERO))


func _seat_bottom_position(box: AABB, seat: Dictionary, offset: Vector3) -> Vector3:
	# Sit on the cushion: align the mesh bottom to seat_top_y.
	return Vector3(
		seat["cx"] - box.get_center().x + offset.x,
		seat["top_y"] - box.position.y + offset.y,
		seat["cz"] - box.get_center().z + offset.z,
	)


func _attach_sofa_accessories(sofa: Node3D, sb: AABB) -> void:
	var blue: Material = _mats["sofa_blue"]
	var seat := _sofa_seat_metrics(sb)
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
	_attach_sofa_accessories(s, AABB(Vector3(cx - 0.38, 0.0, cz - 0.95), Vector3(0.76, 0.52, 1.90)))


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
	# Balcony block on the north wall (−Z): a fixed window on the left + a
	# full-height PVC balcony door on the right. All faux/visual, built in front
	# of the solid wall (bright daylight glows through the glass).
	var win := Node3D.new()
	win.name = "Balcony"
	add_child(win)
	var z := -HALF_L                 # wall plane
	var glow_z := z + 0.02
	var glass_z := z + 0.06
	var fr_z := z + 0.10             # frames sit in front of the glass
	var x0 := -0.85                  # block left edge
	var x1 := 0.85                   # block right edge
	var mull := -0.05               # divider between window and door
	var top := 2.15                 # block top
	var sill_y := 0.85              # window sill height (left)
	var panel_top := 0.95           # door solid-panel top (right)
	var pvc: Material = _mats["pvc"]
	var glass: Material = _mats["glass_win"]

	# Bright daylight behind the whole block (only shows through the glass).
	_box(win, Vector3(x1 - x0, top, 0.02), Vector3((x0 + x1) * 0.5, top * 0.5, glow_z), _mats["glow"], "Daylight")

	# --- Left: fixed window (glazed above the sill) ---
	var wl := mull - x0
	var xcw := (x0 + mull) * 0.5
	_box(win, Vector3(wl, top - sill_y, 0.015), Vector3(xcw, (sill_y + top) * 0.5, glass_z), glass, "WindowGlass")
	_box(win, Vector3(wl + 0.06, 0.05, 0.20), Vector3(xcw, sill_y, fr_z + 0.04), pvc, "Sill")

	# --- Right: balcony door (GLB model if present, else a procedural leaf) ---
	var wd := x1 - mull
	var xcd := (mull + x1) * 0.5
	var has_door_glb := ResourceLoader.exists(BALCONY_DOOR_GLB)
	if has_door_glb:
		var bdoor: Node3D = (load(BALCONY_DOOR_GLB) as PackedScene).instantiate()
		bdoor.name = "BalconyDoor"
		win.add_child(bdoor)
		call_deferred("_finalize_balcony_door", bdoor, xcd, z)
	else:
		_box(win, Vector3(wd - 0.10, panel_top - 0.06, 0.04), Vector3(xcd, panel_top * 0.5 + 0.03, glass_z + 0.01), pvc, "DoorPanel")
		_box(win, Vector3(wd - 0.10, top - panel_top - 0.06, 0.015), Vector3(xcd, (panel_top + top) * 0.5, glass_z), glass, "DoorGlass")
		_box(win, Vector3(0.03, 0.20, 0.04), Vector3(mull + 0.08, 1.0, fr_z + 0.03), _mats["chrome"], "Handle")

	# --- White PVC frame: outer jambs/head/base + mullion + transoms ---
	var f := 0.05
	_box(win, Vector3(f, top, 0.06), Vector3(x0, top * 0.5, fr_z), pvc, "JambL")
	_box(win, Vector3(f, top, 0.06), Vector3(x1, top * 0.5, fr_z), pvc, "JambR")
	_box(win, Vector3(x1 - x0 + f, f, 0.06), Vector3((x0 + x1) * 0.5, top, fr_z), pvc, "Head")
	_box(win, Vector3(x1 - x0 + f, f, 0.06), Vector3((x0 + x1) * 0.5, 0.02, fr_z), pvc, "Base")
	_box(win, Vector3(f, top, 0.06), Vector3(mull, top * 0.5, fr_z), pvc, "Mullion")
	_box(win, Vector3(wl, f, 0.06), Vector3(xcw, sill_y, fr_z), pvc, "WindowTransom")
	if not has_door_glb:
		_box(win, Vector3(wd, f, 0.06), Vector3(xcd, panel_top, fr_z), pvc, "DoorTransom")

	# Net curtain over the glazing. The side drapes + valance are NOT built here
	# anymore — hang the curtains.glb model by hand as a permanent node under Main.
	var tl := _decal(win, "res://tex_tulle.jpg", Vector2(1.5, 1.35), Vector3(0, 1.5, fr_z + 0.02), Vector3.ZERO, "Tulle")
	tl.material_override = _mats["tulle"]


func _build_radiator() -> void:
	# Optional radiator under the left balcony window (auto-fit GLB).
	if not ResourceLoader.exists(RADIATOR_GLB):
		return
	var r: Node3D = (load(RADIATOR_GLB) as PackedScene).instantiate()
	r.name = "Radiator"
	add_child(r)
	call_deferred("_finalize_radiator", r)


func _finalize_radiator(r: Node3D) -> void:
	if not is_instance_valid(r):
		return
	# Reliable raw bounds (local space), then scale/position by arithmetic — no
	# re-measuring against the world (which is flaky in this deferred editor call).
	var lbox := _local_aabb(r)
	# Auto-orient: put the WIDEST horizontal side along the wall (room X), so the
	# fit divides by the real width (not the thin depth) and never blows up.
	var yaw := RADIATOR_YAW + (90.0 if lbox.size.z > lbox.size.x else 0.0)
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(yaw), 0.0))
	var rbox := _aabb_transformed(lbox, Transform3D(basis, Vector3.ZERO))
	var k := RADIATOR_TARGET_W / maxf(rbox.size.x, 0.001)
	var sbox := AABB(rbox.position * k, rbox.size * k)   # final bounds at position 0
	r.rotation_degrees = Vector3(0.0, yaw, 0.0)
	r.scale = Vector3.ONE * k
	var xcw := -0.45                  # centred under the left window
	var wall_z := -HALF_L + 0.05      # back close to the wall
	r.position = Vector3(
		xcw - sbox.get_center().x,
		0.15 - sbox.position.y,       # mounted a little off the floor
		wall_z - sbox.position.z,
	)


func _finalize_balcony_door(door: Node3D, x_center: float, wall_z: float) -> void:
	# `door` is a child of the Balcony node, which sits at the origin, so room-space
	# measurements map straight onto its local position.
	if not is_instance_valid(door):
		return
	var lbox := _local_aabb(door)
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(BALCONY_DOOR_YAW), 0.0))
	var rbox := _aabb_transformed(lbox, Transform3D(basis, Vector3.ZERO))
	var k := BALCONY_DOOR_TARGET_H / maxf(rbox.size.y, 0.001)
	var sbox := AABB(rbox.position * k, rbox.size * k)
	door.rotation_degrees = Vector3(0.0, BALCONY_DOOR_YAW, 0.0)
	door.scale = Vector3.ONE * k
	door.position = Vector3(
		x_center - sbox.get_center().x,
		0.0 - sbox.position.y,                 # bottom on the floor
		(wall_z + 0.08) - sbox.get_center().z, # standing in the opening, near the wall
	)


func _build_curtains() -> void:
	# Optional curtains over the balcony window (auto-fit GLB).
	if not ResourceLoader.exists(CURTAINS_GLB):
		return
	var c: Node3D = (load(CURTAINS_GLB) as PackedScene).instantiate()
	c.name = "Curtains"
	add_child(c)
	call_deferred("_finalize_curtains", c)


func _finalize_curtains(c: Node3D) -> void:
	if not is_instance_valid(c):
		return
	var lbox := _local_aabb(c)
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(CURTAINS_YAW), 0.0))
	var rbox := _aabb_transformed(lbox, Transform3D(basis, Vector3.ZERO))
	var k := CURTAINS_TARGET_H / maxf(rbox.size.y, 0.001)
	var sbox := AABB(rbox.position * k, rbox.size * k)
	c.rotation_degrees = Vector3(0.0, CURTAINS_YAW, 0.0)
	c.scale = Vector3.ONE * k
	var back_z := -HALF_L + 0.16       # hang just in front of the window frame
	c.position = Vector3(
		0.0 - sbox.get_center().x,                          # centred on the window
		CURTAINS_TOP_Y - (sbox.position.y + sbox.size.y),   # top at CURTAINS_TOP_Y
		back_z - sbox.position.z,
	)


func _build_chandelier() -> void:
	# Prefer a real GLB lamp if present; otherwise the procedural chrome version.
	if ResourceLoader.exists(CHANDELIER_GLB):
		_build_chandelier_from_glb()
		return
	_build_chandelier_procedural()


func _build_chandelier_from_glb() -> void:
	var c: Node3D = (load(CHANDELIER_GLB) as PackedScene).instantiate()
	c.name = "Chandelier"
	add_child(c)
	# Defer sizing/placement so the instanced GLB's transforms are settled.
	call_deferred("_finalize_chandelier", c)


func _finalize_chandelier(c: Node3D) -> void:
	if not is_instance_valid(c):
		return
	var lbox := _local_aabb(c)
	var k := CHANDELIER_TARGET_H / maxf(lbox.size.y, 0.001)
	var sbox := AABB(lbox.position * k, lbox.size * k)
	c.scale = Vector3.ONE * k
	# Centre on the room; hang so the model's TOP meets the ceiling, then drop.
	c.position = Vector3(
		-sbox.get_center().x,
		CHANDELIER_CEILING_Y - (sbox.position.y + sbox.size.y) - CHANDELIER_DROP,
		-sbox.get_center().z,
	)


func _build_chandelier_procedural() -> void:
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


func _build_petard_box() -> void:
	# "КОРСАР1" firecracker box (imported GLB). Falls back to nothing if missing.
	if not ResourceLoader.exists(PETARD_GLB):
		return
	var b: Node3D = (load(PETARD_GLB) as PackedScene).instantiate()
	b.name = "PetardBox"
	add_child(b)
	# Defer sizing/placement so the instanced GLB's transforms are settled.
	call_deferred("_finalize_petard_box")


func _finalize_petard_box() -> void:
	var b: Node3D = get_node_or_null("PetardBox") as Node3D
	if b == null:
		return
	# Lay the flattest side down (smallest Y bound), then shrink to a small box.
	# (b is already in the tree, so we can't reuse _pick_flat_rotation_deg, which
	# re-parents — pick the rotation inline from the local bounds instead.)
	var lbox := _local_aabb(b)
	var rot := Vector3.ZERO
	var best_h := INF
	for cand: Vector3 in [Vector3.ZERO, Vector3(90, 0, 0), Vector3(0, 0, 90)]:
		var h: float = _aabb_transformed(lbox, Transform3D(_euler_basis(cand), Vector3.ZERO)).size.y
		if h < best_h:
			best_h = h
			rot = cand
	b.rotation_degrees = rot
	var rbox := _aabb_transformed(lbox, Transform3D(_euler_basis(rot), Vector3.ZERO))
	var k := PETARD_TARGET_L / maxf(maxf(rbox.size.x, rbox.size.z), 0.001)
	b.scale = Vector3.ONE * k
	var sbox := AABB(rbox.position * k, rbox.size * k)   # final bounds at position 0
	var desk_cx := HALF_W - 0.35      # desk top centre X (see _build_desk)
	var desk_top_y := 0.76            # desk surface (top centre 0.74 + half 0.04)
	var cx := desk_cx - 0.18
	var cz := -0.70                              # near the door end, clear of the PC
	b.position = Vector3(
		cx - sbox.get_center().x,
		desk_top_y - sbox.position.y,            # sit flat on the desk
		cz - sbox.get_center().z,
	)


func _build_decals() -> void:
	# Wall art on the east wall above the desk (faces -X into the room).
	var x := HALF_W - 0.015
	_decal(self, "res://decal_worldmap.png", Vector2(1.6, 0.95), Vector3(x, 1.78, -0.7), Vector3(0, -90, 0), "WorldMap")
	_build_wall_clock()
	_build_wall_calendar()
	_build_wall_portrait()


func _build_wall_clock() -> void:
	if not ResourceLoader.exists(CLOCK_GLB):
		return
	var clock: Node3D = (load(CLOCK_GLB) as PackedScene).instantiate()
	clock.name = "Clock"
	clock.set_script(CLOCK_HANDS_SCRIPT)
	add_child(clock)
	clock.rotation_degrees = Vector3(0.0, CLOCK_YAW, 0.0)
	clock.position = CLOCK_CENTER


func _build_wall_calendar() -> void:
	var cal := _decal(self, "res://_raw/calendar.png", Vector2(0.56, 0.75), Vector3(-0.88, 1.55, HALF_L - 0.015), Vector3(0, 180, 0), "WallCalendar")
	var mat := cal.material_override as StandardMaterial3D
	if mat != null:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED


func _build_wall_portrait() -> void:
	if not ResourceLoader.exists(PORTRAIT_GLB):
		return
	var portrait: Node3D = (load(PORTRAIT_GLB) as PackedScene).instantiate()
	portrait.name = "Portrait"
	add_child(portrait)
	call_deferred("_finalize_wall_portrait", portrait)


func _finalize_wall_portrait(portrait: Node3D) -> void:
	if not is_instance_valid(portrait):
		return
	var lbox := _local_aabb(portrait)
	var basis := Basis.from_euler(Vector3(0.0, PI, 0.0))
	var stretched_basis := basis.scaled(Vector3(1.0, 1.0, PORTRAIT_WIDTH_STRETCH))
	var rbox := _aabb_transformed(lbox, Transform3D(stretched_basis, Vector3.ZERO))
	var k := PORTRAIT_TARGET_H / maxf(rbox.size.y, 0.001)
	var sbox := AABB(rbox.position * k, rbox.size * k)
	portrait.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	portrait.scale = Vector3(k, k, k * PORTRAIT_WIDTH_STRETCH)
	portrait.position = Vector3(
		HALF_W - 0.015 - sbox.end.x,
		PORTRAIT_CENTER_Y - sbox.get_center().y,
		PORTRAIT_CENTER_Z - sbox.get_center().z,
	)

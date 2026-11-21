class_name EnvKit
extends RefCounted

## Environment asset kit (graphics pass 5): meshes from Blender kits in assets/env/*.glb
## (art/blender/env/*.py), looked up by object name and cached; plus a chunked, two-level
## MultiMesh helper: each 100 m cell gets the detailed mesh near the camera and the light
## "<name>_lod1" mesh beyond LOD_M (visibility ranges, switched per cell).

const CELL: float = 100.0
const LOD_M: float = 85.0 # camera distance to a cell centre where the light mesh takes over
const LOD_MARGIN: float = 10.0
const FAR_PROP_M: float = 140.0

static var _meshes: Dictionary = {}
static var _foliage_mat: ShaderMaterial = null
static var _solid_mat: StandardMaterial3D = null


## Mesh of object `name` in res://assets/env/<kit>.glb (null if missing).
static func mesh(kit: String, name: String) -> Mesh:
	var key: String = kit + "/" + name
	if _meshes.has(key):
		return _meshes[key] as Mesh
	var path: String = "res://assets/env/%s.glb" % kit
	if not ResourceLoader.exists(path):
		return null
	var root: Node = (load(path) as PackedScene).instantiate()
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		_meshes[kit + "/" + str(n.name)] = (n as MeshInstance3D).mesh
	root.free()
	return _meshes.get(key, null) as Mesh


## Vertex-coloured foliage with a gentle wind sway (tips move, the base stays put).
static func foliage_material() -> ShaderMaterial:
	if _foliage_mat == null:
		_foliage_mat = ShaderMaterial.new()
		_foliage_mat.shader = preload("res://src/render/foliage.gdshader")
	return _foliage_mat


## Vertex-coloured, no sway (rocks).
static func solid_material() -> StandardMaterial3D:
	if _solid_mat == null:
		_solid_mat = StandardMaterial3D.new()
		_solid_mat.vertex_color_use_as_albedo = true
		_solid_mat.roughness = 0.95
	return _solid_mat


## Adds MultiMesh cells for `name` (and "<name>_lod1" if the kit has it) under `node`.
## Instance colours give each copy a slightly different tint.
static func scatter(node: Node3D, kit: String, name: String, xforms: Array[Transform3D], rng: Rng,
		mat: Material, shadows: bool = true) -> void:
	var m0: Mesh = mesh(kit, name)
	if m0 == null or xforms.is_empty():
		return
	var m1: Mesh = mesh(kit, name + "_lod1")
	var cells: Dictionary = {}
	for t: Transform3D in xforms:
		var key: Vector2i = Vector2i(floori(t.origin.x / CELL), floori(t.origin.z / CELL))
		if not cells.has(key):
			cells[key] = [] as Array[Transform3D]
		(cells[key] as Array[Transform3D]).append(t)
	for key: Vector2i in cells:
		var list: Array[Transform3D] = cells[key] as Array[Transform3D]
		var centre: Vector3 = Vector3((float(key.x) + 0.5) * CELL, 0.0, (float(key.y) + 0.5) * CELL)
		var tints: PackedColorArray = PackedColorArray()
		for i: int in list.size():
			var k: float = 0.86 + rng.next_float() * 0.24
			tints.append(Color(k * (0.97 + rng.next_float() * 0.06), k, k * (0.95 + rng.next_float() * 0.08)))
		var near: MultiMeshInstance3D = _cell(name, m0, list, tints, centre, mat)
		near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(near)
		if m1 == null: # small props without a light mesh: not drawn far away
			near.visibility_range_end = FAR_PROP_M
			near.visibility_range_end_margin = LOD_MARGIN
		if m1 != null:
			near.visibility_range_end = LOD_M
			near.visibility_range_end_margin = LOD_MARGIN
			var far: MultiMeshInstance3D = _cell(name + "_lod1", m1, list, tints, centre, mat)
			far.visibility_range_begin = LOD_M
			far.visibility_range_begin_margin = LOD_MARGIN
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # beyond the shadow distance anyway
			node.add_child(far)


static func _cell(name: String, m: Mesh, list: Array[Transform3D], tints: PackedColorArray, centre: Vector3,
		mat: Material) -> MultiMeshInstance3D:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = m
	mm.instance_count = list.size()
	for i: int in list.size():
		var t: Transform3D = list[i]
		t.origin -= centre # the node sits at the cell centre: visibility ranges measure from there
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, tints[i])
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.position = centre
	mmi.material_override = mat
	return mmi

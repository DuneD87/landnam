extends Node3D

## Diseñador de los árboles Branching: genera cada escena de tools/vegetation/tree_presets.gd
## en código y guarda una hoja por árbol en build/tree_quality/designer_<tag>_<escena>.png:
## LOD0 a mediodía, LOD0 a contraluz, vista desde debajo de la copa y LOD1-LOD3.
##   godot --path . res://tests/vegetation/tree_designer.tscn -- --tag=v1 [--only=olive_01,pine_01]
## Imprime los triángulos de cada LOD.

const Presets = preload("res://tools/vegetation/tree_presets.gd")
const GrassPreview = preload("res://tests/vegetation/grass_lod_preview.gd")
const OUT_DIR := "res://build/tree_quality"
const PANEL := Vector2i(720, 1080)
const PLANET_POSITION := Vector3(0, -100000, 0)

var _tag := "designer"
var _only: PackedStringArray = []
var _sun: DirectionalLight3D
var _vp: SubViewport
var _cam: Camera3D
var _materials: Array[ShaderMaterial] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.substr(6)
		elif arg.begins_with("--only="):
			_only = arg.substr(7).split(",")
	var world := WorldEnvironment.new()
	var field = GrassPreview.new()
	world.environment = field._build_environment()
	field.free()
	world.environment.fog_enabled = false
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 60.0
	add_child(_sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	ground.mesh = plane
	ground.material_override = GrassPreview.meadow_ground_material()
	add_child(ground)
	_vp = SubViewport.new()
	_vp.size = PANEL
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_vp.add_child(_cam)
	_cam.current = true
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await get_tree().process_frame
	for scene_name in Presets.SCENES:
		if not _only.is_empty() and scene_name not in _only:
			continue
		await _design(scene_name)
	print("TREE DESIGNER COMPLETE")
	get_tree().quit()


func _process(_delta: float) -> void:
	for material in _materials:
		material.set_shader_parameter("planet_position", PLANET_POSITION)
		material.set_shader_parameter("wind_speed", 0.0)


func _design(scene_name: String) -> void:
	var tree := Tree3D.new()
	add_child(tree)
	var t0 := Time.get_ticks_usec()
	Presets.configure(tree, scene_name)
	var lods: Array = tree.bake_lods()
	var line := "%s: %.0f ms" % [scene_name, (Time.get_ticks_usec() - t0) / 1000.0]
	for lod in lods:
		line += "  %d" % _triangles(lod)
	print(line, " tris")
	tree.queue_free()
	_materials.clear()
	for lod in lods:
		for s in lod.get_surface_count():
			var material = lod.surface_get_material(s)
			if material is ShaderMaterial and material not in _materials:
				_materials.append(material)
	var inst := MeshInstance3D.new()
	add_child(inst)
	var human := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = 1.8
	human.mesh = capsule
	var human_material := StandardMaterial3D.new()
	human_material.albedo_color = Color(0.75, 0.3, 0.25)
	human.material_override = human_material
	add_child(human)
	var aabb: AABB = lods[0].get_aabb()
	human.position = Vector3(maxf(aabb.size.x, aabb.size.z) * 0.5 + 1.0, 0.9, 0.0)

	var shots: Array[Image] = []
	inst.mesh = lods[0]
	_set_sun(Vector3(0.4, 0.8, 0.3))
	_frame(aabb)
	shots.append(await _grab())
	_set_sun(Vector3(0.15, 0.25, -1.0))
	shots.append(await _grab())
	# Desde debajo de la copa, a la altura de los ojos, mirando hacia arriba.
	_set_sun(Vector3(0.4, 0.8, 0.3))
	var crown_radius := maxf(aabb.size.x, aabb.size.z) * 0.5
	_cam.position = Vector3(crown_radius * 0.45, 1.7, crown_radius * 0.45)
	_cam.look_at(Vector3(-crown_radius * 0.3, aabb.end.y * 0.75, -crown_radius * 0.3))
	shots.append(await _grab())
	for lod_i in range(1, 4):
		inst.mesh = lods[lod_i]
		_frame(aabb)
		shots.append(await _grab())
	inst.queue_free()
	human.queue_free()
	_save_sheet(shots, 3, "designer_%s_%s" % [_tag, scene_name])


func _set_sun(direction: Vector3) -> void:
	direction = direction.normalized()
	_sun.look_at_from_position(Vector3.ZERO, -direction, Vector3.UP)
	for material in _materials:
		material.set_shader_parameter("light_direction", direction)


func _frame(aabb: AABB) -> void:
	var height := aabb.end.y
	var width := maxf(aabb.size.x, aabb.size.z) + 2.0
	var half_fov := deg_to_rad(_cam.fov * 0.5)
	var aspect := float(PANEL.x) / PANEL.y
	var dist := maxf(height * 0.58 / tan(half_fov), width * 0.6 / (tan(half_fov) * aspect))
	var target := Vector3(0.5, height * 0.5, 0.0)
	_cam.position = target + Vector3(0.0, height * 0.08, dist)
	_cam.look_at(target)


func _grab() -> Image:
	for i in 4:
		await RenderingServer.frame_post_draw
	return _vp.get_texture().get_image()


func _save_sheet(shots: Array[Image], columns: int, name: String) -> void:
	var w := PANEL.x / 2
	var h := PANEL.y / 2
	var rows := ceili(shots.size() / float(columns))
	var sheet := Image.create(w * columns, h * rows, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var img := shots[i]
		img.convert(Image.FORMAT_RGBA8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % columns) * w, (i / columns) * h))
	var path := "%s/%s.png" % [OUT_DIR, name]
	sheet.save_png(path)
	print("CAPTURE ", path)


static func _triangles(mesh: Mesh) -> int:
	var tris := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var index = arrays[Mesh.ARRAY_INDEX]
		tris += (index.size() if index != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return tris

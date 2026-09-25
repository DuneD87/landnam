extends Node3D

## Comparación reproducible de modelo, paleta y luz. --capture guarda cuatro luces.
## --baseline usa la copia local anterior a esta revisión, si está disponible.
const GrassLods = preload("res://scripts/planet/grass_geometry_lods.gd")
const FieldPreview = preload("res://tests/vegetation/grass_lod_preview.gd")
const VARIANTS := ["low_poly_grass", "low_poly_grass_green_yellow", "low_poly_grass_yellow"]
var _materials: Array[ShaderMaterial] = []
var _camera: Camera3D
var _sun: DirectionalLight3D
var _environment: Environment
var _torch: OmniLight3D
var _baseline: bool
var _occluder: MeshInstance3D


func _ready() -> void:
	_baseline = "--baseline" in OS.get_cmdline_user_args()
	if _baseline and not FileAccess.file_exists("res://build/grass_quality/opus/geometry.gd"):
		push_error("--baseline necesita la copia local en build/grass_quality/opus/")
		get_tree().quit(1)
		return
	var world := WorldEnvironment.new()
	var field = FieldPreview.new()
	_environment = field._build_environment()
	field.free()
	_environment.fog_enabled = false
	_environment.background_color = Color(0.28, 0.36, 0.43)
	world.environment = _environment
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 30.0
	add_child(_sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	ground.material_override = preload("res://tests/vegetation/grass_lod_preview.gd").meadow_ground_material()
	add_child(ground)
	var builder = load("res://build/grass_quality/opus/geometry.gd") if _baseline else GrassLods
	for variant in 3:
		var scene_path := "res://scenes/planet/planet_items/vegetation/grass/%s.tscn" % VARIANTS[variant]
		if _baseline:
			scene_path = "res://build/grass_quality/opus/%s.tscn" % VARIANTS[variant]
		var source: Node = load(scene_path).instantiate()
		var mesh: Mesh = source.get_child(0).mesh
		var lods: Array = builder.build(mesh)
		var material: ShaderMaterial = mesh.surface_get_material(0).duplicate()
		if _baseline:
			material.shader = load("res://build/grass_quality/opus/grass.gdshader")
		material.set_shader_parameter("planet_position", Vector3(0, -30000, 0))
		material.set_shader_parameter("wind_speed", 0.0)
		material.set_shader_parameter("fade_start", 0.0)
		material.set_shader_parameter("fade_end", 0.0)
		_materials.append(material)
		for lod in lods:
			lod.surface_set_material(0, material)
		# Tres matas aisladas delante y grupos de la variante verde al fondo.
		var clump := MeshInstance3D.new()
		clump.mesh = lods[0]
		clump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		clump.position = Vector3((variant - 1) * 1.35, 0, 0)
		add_child(clump)
		if variant == 0:
			var rng := RandomNumberGenerator.new()
			rng.seed = 7891
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = lods[0]
			multi.instance_count = 450
			for i in multi.instance_count:
				var pos := Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-16, -3))
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.65, 1.3))
				multi.set_instance_transform(i, Transform3D(basis, pos))
			var field_instance := MultiMeshInstance3D.new()
			field_instance.multimesh = multi
			field_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(field_instance)
		source.free()
	_camera = Camera3D.new()
	_camera.fov = 43.0
	add_child(_camera)
	_camera.position = Vector3(2.7, 1.65, 4.3)
	_camera.look_at(Vector3(0, 0.38, -0.3))
	_camera.current = true
	_torch = OmniLight3D.new()
	_torch.position = Vector3(-0.9, 1.0, 1.0)
	_torch.omni_range = 4.5
	_torch.light_color = Color(1.0, 0.62, 0.32)
	_torch.light_energy = 2.0
	_torch.visible = false
	add_child(_torch)
	_occluder = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(6, 0.25, 6)
	_occluder.mesh = box
	_occluder.position = Vector3(0, 1.7, 0)
	_occluder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_occluder.visible = false
	add_child(_occluder)
	_set_sun(Vector3(-0.4, 0.8, 0.6))
	if "--capture" in OS.get_cmdline_user_args():
		await _capture()


func _set_sun(direction: Vector3) -> void:
	direction = direction.normalized()
	_sun.look_at(-direction)
	for material in _materials:
		material.set_shader_parameter("light_direction", direction)


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/grass_quality")
	await get_tree().create_timer(1.0).timeout
	await _save("day")
	var original_camera: Transform3D = _camera.transform
	_camera.position = Vector3(-0.6, 0.8, 1.45)
	_camera.look_at(Vector3(-1.35, 0.38, 0))
	await _save("detail")
	_camera.transform = original_camera
	_set_sun(Vector3(-0.4, 0.20, -1.0))
	_sun.light_color = Color(1.0, 0.87, 0.68)
	await _save("backlit")
	_set_sun(Vector3(0.05, 1.0, 0.1))
	_sun.light_color = Color.WHITE
	_occluder.visible = true
	await _save("shadow")
	_occluder.visible = false
	_set_sun(Vector3(0.3, -0.8, -1.0))
	_sun.light_energy = 0.0
	_environment.background_color = Color(0.015, 0.025, 0.05)
	_environment.ambient_light_energy = 0.01
	_torch.visible = true
	await _save("night_torch")
	print("GRASS QUALITY PREVIEW COMPLETE")
	get_tree().quit()


func _save(view: String) -> void:
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var name := "%s_%s" % ["before" if _baseline else "after", view]
	get_viewport().get_texture().get_image().save_png("res://build/grass_quality/%s.png" % name)
	print("CAPTURE ", name)

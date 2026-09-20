extends Node3D

## Catálogo y grupo mixto sobre hierba. --capture guarda imágenes y sale.
const Builder = preload("res://scripts/planet/understory_geometry.gd")
const GrassLods = preload("res://scripts/planet/grass_geometry_lods.gd")
const FieldPreview = preload("res://tests/vegetation/grass_lod_preview.gd")
const NAMES := ["Helecho de bosque", "Helecho alto", "Arbusto redondo", "Arbusto de hoja larga",
	"Arbusto florido", "Esparraguera", "Hojas anchas", "Flores silvestres"]
var _camera: Camera3D
var _sun: DirectionalLight3D
var _materials: Array[ShaderMaterial] = []
var _catalog := Node3D.new()
var _group := Node3D.new()
var _plants: Array[MeshInstance3D] = []


func _ready() -> void:
	var template = FieldPreview.new()
	var world := WorldEnvironment.new()
	world.environment = template._build_environment()
	template.free()
	world.environment.fog_enabled = false
	world.environment.background_color = Color(0.34, 0.43, 0.48)
	add_child(world)
	_sun = DirectionalLight3D.new()
	add_child(_sun)
	_sun.look_at(-Vector3(-0.4, 0.85, 0.5).normalized())
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.26, 0.30, 0.20)
	ground.material_override = mat
	add_child(ground)
	add_child(_catalog)
	add_child(_group)
	_group.visible = false
	for i in Builder.SPECIES.size():
		var species: String = Builder.SPECIES[i]
		var meshes: Array = Builder.build(species)
		var material: ShaderMaterial = meshes[0].surface_get_material(0)
		_prepare_material(material)
		var plant := MeshInstance3D.new()
		plant.mesh = meshes[0]
		plant.position = Vector3((i % 4 - 1.5) * 2.4, 0.025, -4.1 if i < 4 else 0.4)
		_catalog.add_child(plant)
		_plants.append(plant)
		var label := Label3D.new()
		label.text = NAMES[i]
		label.font_size = 40
		label.pixel_size = 0.0045
		label.modulate = Color(0.9, 0.94, 0.86)
		label.outline_modulate = Color(0.12, 0.17, 0.14)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = plant.position + Vector3(0, 1.85, 0)
		_catalog.add_child(label)
	_build_group()
	_camera = Camera3D.new()
	_camera.fov = 45.0
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 7.7
	add_child(_camera)
	_camera.position = Vector3(0, 9.0, 10.0)
	_camera.look_at(Vector3(0, 0.60, -1.9))
	_camera.current = true
	if "--capture" in OS.get_cmdline_user_args():
		await _capture()


func _prepare_material(material: ShaderMaterial) -> void:
	material.set_shader_parameter("planet_position", Vector3(0, -30000, 0))
	material.set_shader_parameter("light_direction", Vector3(-0.4, 0.85, 0.5).normalized())
	material.set_shader_parameter("wind_speed", 0.0)
	material.set_shader_parameter("fade_start", 0.0)
	material.set_shader_parameter("fade_end", 0.0)
	_materials.append(material)


func _build_group() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11218
	var source: Node = load("res://scenes/planet/planet_items/vegetation/grass/low_poly_grass.tscn").instantiate()
	var grass: Mesh = GrassLods.build(source.get_child(0).mesh)[0]
	var mat: ShaderMaterial = grass.surface_get_material(0).duplicate()
	grass.surface_set_material(0, mat)
	_prepare_material(mat)
	source.free()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = grass
	multi.instance_count = 280
	for i in multi.instance_count:
		var pos := Vector3(rng.randf_range(-7, 7), 0, rng.randf_range(-8, 2))
		var scale_value: float = rng.randf_range(0.35, 0.75)
		multi.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale_value), pos))
	var grass_instance := MultiMeshInstance3D.new()
	grass_instance.multimesh = multi
	_group.add_child(grass_instance)
	# Composición mixta para juzgar tamaños y colores junto a la hierba.
	for i in 26:
		var plant := MeshInstance3D.new()
		plant.mesh = Builder.build(Builder.SPECIES[i % 8])[0]
		plant.position = Vector3(rng.randf_range(-4.5, 4.5), 0.02, rng.randf_range(-5.5, 0.5))
		plant.rotation.y = rng.randf() * TAU
		plant.scale = Vector3.ONE * rng.randf_range(0.80, 1.20)
		_group.add_child(plant)


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/understory")
	await get_tree().create_timer(1.0).timeout
	await _save("catalog")
	for lod in range(1, 4):
		for i in _plants.size():
			_plants[i].mesh = Builder.build(Builder.SPECIES[i])[lod]
		await _save("catalog_lod%d" % lod)
	for i in _plants.size():
		_plants[i].mesh = Builder.build(Builder.SPECIES[i])[0]
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.position = Vector3(-5.1, 1.4, -1.7)
	_camera.look_at(_plants[0].position + Vector3.UP * 0.32)
	await _save("fern_detail")
	_catalog.visible = false
	_group.visible = true
	_camera.position = Vector3(6.8, 3.8, 7.2)
	_camera.look_at(Vector3(0, 0.35, -2))
	await _save("meadow")
	var low_sun := Vector3(-0.5, 0.22, -1).normalized()
	_sun.look_at(-low_sun)
	_sun.light_color = Color(1.0, 0.9, 0.75)
	for material in _materials:
		material.set_shader_parameter("light_direction", low_sun)
	await _save("meadow_backlit")
	print("UNDERSTORY PREVIEW COMPLETE")
	get_tree().quit()


func _save(view: String) -> void:
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/understory/%s.png" % view)
	print("CAPTURE ", view)

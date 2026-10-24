extends Node3D

## Cabaña construida con las grids reales. Arrastrar para orbitar; rueda para acercarse.
## godot --path . res://tests/building/thatch_roof_preview.tscn -- --capture [--background]
const OUTPUT := "res://build/building/thatch/"
var _camera: Camera3D
var _yaw := 0.75
var _pitch := 0.38
var _distance := 14.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if "--background" in OS.get_cmdline_user_args():
		get_window().position = Vector2i(-4000, -4000)
		get_window().unfocusable = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("b9c8ce")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d5dddf")
	environment.environment.ambient_light_energy = 0.35
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	ground.mesh = plane
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color("566247")
	grass.roughness = 1.0
	ground.material_override = grass
	add_child(ground)
	GridBlueprint.instantiate(cabin_blueprint(), self, Vector3(-3.5, 0, -3.5), Basis.IDENTITY)
	_camera = Camera3D.new()
	_camera.fov = 48.0
	add_child(_camera)
	_camera.current = true
	_update_camera()
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch + event.relative.y * 0.006, -0.1, 1.3)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(3.0, _distance - 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(30.0, _distance + 1.0)
		_update_camera()


func _update_camera() -> void:
	var target := Vector3(0, 2.6, 0)
	_camera.position = target + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
	_camera.look_at(target)


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + "cabana.png")
	_yaw = -0.8
	_pitch = 0.2
	_distance = 8.0
	_update_camera()
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + "detalle.png")
	_yaw = PI * 0.5
	_pitch = 0.08
	_distance = 10.5
	_update_camera()
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + "fronton.png")
	print("Capturas: ", ProjectSettings.globalize_path(OUTPUT))
	get_tree().quit()


## Suelo y paredes de 5×5 con alero lateral de un metro. Los paneles cierran las caras
## exteriores de los frontones, en las celdas vecinas a los extremos del tejado.
static func cabin_blueprint() -> Dictionary:
	var blocks := {}
	for x in range(1, 6):
		for z in range(1, 6):
			blocks["%d,0,%d" % [x, z]] = _block(0, "stone")
			if x == 1 or x == 5 or z == 1 or z == 5:
				for y in [1, 2]:
					if not (x == 5 and z == 3):
						blocks["%d,%d,%d" % [x, y, z]] = _block(0, "wood")
	for x in range(1, 6):
		for z in 3:
			blocks["%d,%d,%d" % [x, 2 + z, z]] = _block(BlockDatabase.BLOCK_THATCH_SLOPE_ID, "thatch")
			blocks["%d,%d,%d" % [x, 2 + z, 6 - z]] = _block(BlockDatabase.BLOCK_THATCH_SLOPE_ID,
				"thatch", Basis(Vector3.UP, PI))
		blocks["%d,5,3" % x] = _block(BlockDatabase.BLOCK_THATCH_RIDGE_ID, "thatch")
	for x in [0, 6]:
		var facing := Basis(Vector3.UP, -PI * 0.5 if x == 0 else PI * 0.5)
		# El triángulo alto a +Z cierra el faldón que sube; un giro sobre su normal cierra
		# el faldón de la otra agua. Los cuadrados rellenan la parte central del frontón.
		var rising := facing if x == 6 else facing * Basis(Vector3.BACK, PI * 0.5)
		var falling := facing * Basis(Vector3.BACK, PI * 0.5) if x == 6 else facing
		for z in [1, 2]:
			blocks["%d,%d,%d" % [x, 2 + z, z]] = _block(BlockDatabase.BLOCK_PANE_TRIANGLE_ID, "wood", rising)
			blocks["%d,%d,%d" % [x, 2 + z, 6 - z]] = _block(BlockDatabase.BLOCK_PANE_TRIANGLE_ID, "wood", falling)
		for z in [2, 3, 4]:
			blocks["%d,3,%d" % [x, z]] = _block(BlockDatabase.BLOCK_PANE_ID, "wood", facing)
		blocks["%d,4,3" % x] = _block(BlockDatabase.BLOCK_PANE_ID, "wood", facing)
	return {"version": 1, "dynamic": false, "bounds_min": [0, 0, 0], "bounds_max": [7, 6, 7],
		"block_count": blocks.size(), "prop_count": 0,
		"grids": [{"cell_size": 1.0, "blocks": blocks, "materials": {}, "props": []}]}


static func _block(id: int, material: String, rot := Basis.IDENTITY) -> Dictionary:
	return {"block_id": id, "material_id": material, "rotation_basis": GridBase._basis_to_array(rot)}

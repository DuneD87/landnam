extends Node3D

## Astillero aislado, sin cargar el planeta. B abre el editor; al elegir una pieza
## se reconstruye la muestra con sus medidas. Arrastrar para orbitar; rueda para zoom.
## godot --path . res://tests/building/naval_pieces_preview.tscn -- --capture [--background] [--floor-preview]
const OUTPUT := "res://build/building/naval/"
var _camera: Camera3D
var _building: BuildingSystem
var _menu: BuildMenu
var _grid: GridBase
var _yaw := 0.7
var _pitch := 0.65
var _distance := 12.0
var _target := Vector3.ZERO


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if "--background" in OS.get_cmdline_user_args():
		get_window().position = Vector2i(-4000, -4000)
		get_window().unfocusable = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("75858c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d2dde4")
	environment.environment.ambient_light_energy = 0.5
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	ground.mesh = plane
	ground.position.y = -0.08
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("5e6664")
	material.roughness = 1.0
	ground.material_override = material
	add_child(ground)
	var player := Node3D.new()
	add_child(player)
	player.add_child(Inventory.new())
	player.add_child(BuildPreview.new())
	_building = BuildingSystem.new()
	_building.current_planet = self
	player.add_child(_building)
	_building.set_cell_size_index(0)
	_building.pick_naval_piece(NavalPiece.Kind.BOW, NavalPiece.DEFAULT_SIZE)
	BuildingSystem.free_build = true
	_menu = BuildMenu.new()
	add_child(_menu)
	_menu.setup(_building)
	_menu._naval_panel.piece_picked.connect(_rebuild)
	_camera = Camera3D.new()
	_camera.fov = 48.0
	add_child(_camera)
	_camera.current = true
	_rebuild()
	var hud := CanvasLayer.new()
	add_child(hud)
	var hint := Label.new()
	hint.text = "NAVAL_WORKSHOP_HINT"
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 32
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 25)
	hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint.add_theme_constant_override("shadow_outline_size", 5)
	hud.add_child(hint)
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()
	elif "--merge-preview" in OS.get_cmdline_user_args():
		_prepare_merge_preview.call_deferred()
	elif "--floor-preview" in OS.get_cmdline_user_args():
		_prepare_floor_preview.call_deferred()


func _rebuild() -> void:
	if _grid:
		GridManager.remove_grid_group(_grid.grid_id)
	var dimensions := _building.naval_size
	var cell := _building.cell_size
	var total_length := dimensions.z * 2 + 3
	var origin := Vector3(-dimensions.x * cell * 0.5, 0, -total_length * cell * 0.5)
	_grid = GridManager.create_grid_exact(self, origin, Basis.IDENTITY, cell)
	var material := BlockDatabase.get_material_by_id("wood")
	_grid.mesh_materials["wood"] = material.surface_material
	_grid.begin_bulk_edit()
	for part in [[NavalPiece.Kind.STERN, Vector3i(dimensions.x, dimensions.y, 3), 0],
		[NavalPiece.Kind.HULL, dimensions, 3], [NavalPiece.Kind.BOW, dimensions, dimensions.z + 3]]:
		var blocks := NavalPiece.generate(part[0], part[1], _building.naval_profile)
		for block_cell: Vector3i in blocks:
			var position := block_cell + Vector3i(0, 0, part[2])
			var info: Dictionary = blocks[block_cell]
			_grid.place_block(position, BlockDatabase.get_block(int(info["block_id"])), Basis.IDENTITY,
				Transform3D(Basis.IDENTITY, _grid.grid_to_world(position)), "wood", info)
	_grid.end_bulk_edit()
	_target = Vector3(0, dimensions.y * cell * 0.45, 0)
	_distance = maxf(dimensions.x, total_length) * cell * 1.65
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_B:
		_menu.toggle()
	elif event.is_action_pressed("ui_cancel"):
		_menu.close()
	if _menu.visible:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch + event.relative.y * 0.006, 0.05, 1.5)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(2.0, _distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance *= 1.1
		_update_camera()


func _update_camera() -> void:
	_camera.position = _target + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
	_camera.look_at(_target)


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var merge_preview := "--merge-preview" in OS.get_cmdline_user_args()
	var floor_preview := "--floor-preview" in OS.get_cmdline_user_args()
	if merge_preview:
		await _prepare_merge_preview()
	elif floor_preview:
		_prepare_floor_preview()
	var prefix := "suelo" if floor_preview else ("fusion" if merge_preview else "casco")
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + prefix + ".png")
	_yaw = 0.15
	_pitch = 1.3
	_update_camera()
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var interior_file := prefix + "_interior.png" if floor_preview or merge_preview else "interior.png"
	get_viewport().get_texture().get_image().save_png(OUTPUT + interior_file)
	if merge_preview or floor_preview:
		print("Capturas: ", ProjectSettings.globalize_path(OUTPUT))
		get_tree().quit()
		return
	_menu.open()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + "editor.png")
	print("Capturas: ", ProjectSettings.globalize_path(OUTPUT))
	get_tree().quit()


func _prepare_merge_preview() -> void:
	_building.pick_block(BlockDatabase.get_block_material_item(0, "wood"))
	_building.set_cell_size_index(0)
	_building.set_build_mode(true)
	var focus := _grid.grid_to_world(Vector3i(2, 1, 8)) + Vector3.ONE * 0.125
	(_building.get_parent() as Node3D).global_position = focus + Vector3.UP * 2
	_target = focus
	_distance = 4.0
	_yaw = 0.7
	_pitch = 1.0
	_update_camera()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ray := PhysicsRayQueryParameters3D.create(focus + Vector3.UP * 3, focus + Vector3.DOWN * 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		_building.process_raycast(hit.collider, hit.normal, hit.position, hit)
		print("Cubo: ", "verde" if _building._can_place and _building._can_afford else "rojo")


func _prepare_floor_preview() -> void:
	_building.pick_block(BlockDatabase.get_block_material_item(0, "wood"))
	_building.set_cell_size_index(0)
	_building.current_rotation_basis = Basis(Vector3.UP, PI * 0.5)
	for x in range(2, 10):
		for z in range(4, 20):
			var cell := Vector3i(x, 1, z)
			_building._target_grid = _grid
			_building._cached_grid_for_placement = _grid
			_building._hit_grid_for_alignment = _grid
			_building._target_grid_pos = cell
			_building._target_world_pos = _grid.grid_to_world(cell)
			_building._target_basis = _grid.get_basis_world()
			_building._has_target = true
			_building._can_place = true
			_building._can_afford = true
			_building.try_place_block()
	_building.set_build_mode(false)

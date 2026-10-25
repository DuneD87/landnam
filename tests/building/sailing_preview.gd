extends Node3D

## godot --path . res://tests/building/sailing_preview.tscn -- --capture --background
## Flechas: despliegue; A/D: viento; arrastrar: cámara; rueda: zoom.
var global_pos := Vector3(0, -1000, 0)
var _grid: GridBase
var _sailing := BoatSailing.new()
var _camera: Camera3D
var _hud: SailingHUD
var _air_angle := -0.3
var _yaw := 0.6
var _pitch := 0.28
var _distance := 13.5


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if "--background" in OS.get_cmdline_user_args():
		get_window().position = Vector2i(-4000, -4000)
		get_window().unfocusable = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("829aa6")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c1cdd1")
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	sea.mesh = plane
	sea.position.y = 0.35
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("345c68")
	material.metallic = 0.35
	material.roughness = 0.28
	sea.material_override = material
	add_child(sea)
	_build_boat()
	_camera = Camera3D.new()
	_camera.fov = 45
	add_child(_camera)
	_camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = SailingHUD.new()
	_hud.navigation = _sailing
	layer.add_child(_hud)
	var hint := Label.new()
	hint.text = "SAIL_PREVIEW_HINT"
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 30
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_override("font", GameTheme.body_font())
	hint.add_theme_font_size_override("font_size", 25)
	hint.add_theme_color_override("font_color", GameTheme.BONE)
	hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint.add_theme_constant_override("shadow_outline_size", 5)
	layer.add_child(hint)
	_sailing.set_level(3)
	if "--headwind" in OS.get_cmdline_user_args():
		_air_angle = PI
	if "--furled" in OS.get_cmdline_user_args():
		_sailing.set_level(0)
	if "--sail-editor" in OS.get_cmdline_user_args():
		_open_sail_editor()
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()


func _build_boat() -> void:
	_grid = GridManager.create_grid_exact(self, Vector3(-1.125, 0, -3.375), Basis.IDENTITY, 0.25)
	var wood := BlockDatabase.get_material_by_id("wood")
	_grid.mesh_materials["wood"] = wood.surface_material
	_grid.begin_bulk_edit()
	for part in [[NavalPiece.Kind.STERN, Vector3i(9, 5, 3), 0],
			[NavalPiece.Kind.HULL, Vector3i(9, 5, 12), 3], [NavalPiece.Kind.BOW, Vector3i(9, 5, 12), 15]]:
		var cells := NavalPiece.generate(part[0], part[1])
		for cell: Vector3i in cells:
			var info: Dictionary = cells[cell]
			var target := cell + Vector3i(0, 0, part[2])
			_grid.place_block(target, GridBase.block_data_for_info(info).for_material("wood"), Basis.IDENTITY,
				Transform3D(Basis.IDENTITY, _grid.grid_to_world(target)), "wood", info)
	for x in range(2, 7):
		for z in range(4, 16):
			var cell := Vector3i(x, 3, z)
			_grid.place_block(cell, BlockDatabase.get_block(0).for_material("wood"), Basis.IDENTITY,
				Transform3D(Basis.IDENTITY, _grid.grid_to_world(cell)), "wood")
	_grid.end_bulk_edit()
	var state := {}
	if "--large-sail" in OS.get_cmdline_user_args():
		state["design"] = {"width": 6.0, "height": 4.0, "mast_height": 7.25}
		_distance = 18.0
	_grid.place_prop(Vector3i(4, 3, 12), Vector3i.UP, &"hide_sail",
		Transform3D(Basis.IDENTITY, Vector3(4.5, 4, 12.5) * 0.25), state)
	_sailing.rebuild([_grid])


func _open_sail_editor() -> void:
	var builder := Node3D.new()
	add_child(builder)
	var inventory := Inventory.new(100)
	builder.add_child(inventory)
	for id in [&"raw_hide", &"sinew", &"plant_fiber", &"branch_01"]:
		inventory.add_item(ItemCatalog.get_item(id), 40)
	builder.add_child(BuildPreview.new())
	var building := BuildingSystem.new()
	builder.add_child(building)
	building.current_planet = self
	building.set_build_mode(true)
	var menu := BuildMenu.new()
	add_child(menu)
	menu.setup(building, inventory)
	menu.open()
	menu._set_material(BuildMenu.NAVAL_CATEGORY)
	var panel := menu._naval_panel
	panel._types[NavalBuildPanel.SAIL_KIND].pressed.emit()
	panel._dimensions[0].value = 3.5
	panel._dimensions[1].value = 2.25
	panel._dimensions[2].value = 4.75


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("boat_sail_raise"):
		_sailing.set_level(_sailing.level + 1)
	if Input.is_action_just_pressed("boat_sail_lower"):
		_sailing.set_level(_sailing.level - 1)
	if Input.is_physical_key_pressed(KEY_A):
		_air_angle -= delta
	if Input.is_physical_key_pressed(KEY_D):
		_air_angle += delta
	var air := Vector3(sin(_air_angle), 0, cos(_air_angle)) * 8.0
	_sailing.step(delta, air, Vector3.ZERO, Vector3.BACK, Vector3.UP)
	_hud.scale = Vector2.ONE * GameTheme.scale_for(get_viewport())
	_hud.position = Vector2(get_viewport().get_visible_rect().size.x - 364 * _hud.scale.x, 250 * _hud.scale.y)
	_hud.queue_redraw()
	_camera.position = Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance + Vector3(0, 2.6, 0)
	_camera.look_at(Vector3(0, 2.6, 0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch + event.relative.y * 0.006, -0.1, 1.2)
	if event.is_action_pressed("camera_zoom_in"):
		_distance = maxf(6, _distance - 1)
	if event.is_action_pressed("camera_zoom_out"):
		_distance = minf(30, _distance + 1)


func _capture() -> void:
	_sailing.step(3.0, Vector3(sin(_air_angle), 0, cos(_air_angle)) * 8.0, Vector3.ZERO, Vector3.BACK, Vector3.UP)
	for frame in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var suffix := "furled" if "--furled" in OS.get_cmdline_user_args() else "headwind" if "--headwind" in OS.get_cmdline_user_args() else "sailing"
	if "--sail-editor" in OS.get_cmdline_user_args():
		suffix = "editor"
	elif "--large-sail" in OS.get_cmdline_user_args():
		suffix = "large"
	var dir := "res://build/building/sailing/"
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir + suffix + ".png")
	print("SAILING CAPTURE: ", dir + suffix + ".png")
	set_process(false)
	_sailing.rebuild([])
	GridManager.clear_all()
	await get_tree().process_frame
	get_tree().quit()

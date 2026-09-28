extends Node3D

var models: Array[SimpleSmallAnimalModel] = []
var elapsed: float = 0.0
var _motion_demo: bool = false
var _motion_label: Label


func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("202b32")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("b4c9df")
	world.environment.ambient_light_energy = 0.30
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment.ssao_enabled = true
	world.environment.ssao_radius = 0.3
	world.environment.ssao_intensity = 2.0
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, -35, 0)
	light.light_color = Color("fff0d7")
	light.light_energy = 1.6
	light.directional_shadow_max_distance = 10.0
	light.shadow_enabled = false
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 125, 0)
	fill.light_color = Color("bfd8e9")
	fill.light_energy = 0.55
	add_child(fill)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.8
	camera.position = Vector3(0, 1.8, 4)
	add_child(camera)
	camera.look_at(Vector3(0, 0.2, 0))
	camera.current = true
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("424a4b")
	mat.roughness = 0.95
	plane.material = mat
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var winter := 3 if "--winter" in OS.get_cmdline_user_args() else 0
	for i in 3:
		var animal := SimpleSmallAnimalModel.new()
		animal.position.x = (i - 1) * 1.15
		animal.rotation_degrees.y = -140
		add_child(animal)
		animal.set_species(i + winter)
		models.append(animal)
		var label := Label3D.new()
		label.text = SimpleSmallAnimalModel.NAMES[i + winter]
		label.font_size = 48
		label.pixel_size = 0.0018
		label.outline_size = 0
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(animal.position.x, 0.035, 0.65)
		add_child(label)
	_motion_demo = "--motion" in OS.get_cmdline_user_args()
	if _motion_demo:
		for child in get_children():
			if child is Label3D:
				child.hide()
		models[0].hide()
		models[2].hide()
		camera.size = 1.35
		camera.position = Vector3(0, 0.72, 2)
		camera.look_at(Vector3(0, 0.30, 0))
		var canvas := CanvasLayer.new()
		add_child(canvas)
		_motion_label = Label.new()
		_motion_label.position = Vector2(28, 24)
		_motion_label.add_theme_font_size_override("font_size", 26)
		canvas.add_child(_motion_label)
	if "--capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://build/fauna")
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://build/fauna/small_ground_species.png")
		for child in get_children():
			if child is Label3D:
				child.hide()
		for i in models.size():
			for model in models:
				model.visible = model == models[i]
			var target := models[i].position + Vector3(0, [0.30, 0.38, 0.10][i], 0)
			camera.size = [0.9, 1.25, 0.38][i]
			camera.position = target + Vector3(0, 0.35, 2)
			camera.look_at(target)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://build/fauna/small_ground_detail_%d.png" % i)
			var triangles := 0
			for part in models[i].get_children():
				triangles += part.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3
			print("MODEL: %s — %d triangles, %d mesh instances" % [SimpleSmallAnimalModel.NAMES[i], triangles, models[i].get_child_count()])
			# Inspect the actual GPU deformation, including foot lift and joint blends.
			set_process(false)
			for phase in 3:
				if i == 0:
					models[i]._apply_pose(phase * 0.28, phase * 0.28, 2.0, 1.0 if phase < 2 else 0.0, 1.8 if phase == 0 else -1.0, 0.0, 1.0 if phase == 2 else 0.0)
				else:
					models[i].animate(phase * 0.28, 2.0)
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://build/fauna/small_ground_motion_%d_%d.png" % [i, phase])
			models[i].animate(0.0, 0.0)
		await _detail_board(world.environment)
		get_tree().quit()


func _process(delta: float) -> void:
	elapsed += delta
	if _motion_demo:
		var t := fposmod(elapsed, 12.0)
		var speed := 0.0 if t < 2.0 or t >= 10.0 else (4.5 if t >= 5.0 and t < 8.0 else 1.4)
		var slow := t >= 5.0 and t < 8.0
		var turn := 0.7 if t >= 8.0 and t < 10.0 else 0.0
		models[1].advance(delta * (0.5 if slow else 1.0), speed, true, 0.0, turn)
		_motion_label.text = "Zorro · " + ("reposo" if speed == 0.0 else ("carrera · cámara lenta ×0,5" if slow else ("giro" if turn > 0.0 else "trote")))
		return
	for model in models:
		model.advance(delta, 0.0)


func _detail_board(environment: Environment) -> void:
	# Three independent Godot renders, framed for inspection rather than relative size.
	for child in get_children():
		if child is Node3D:
			child.hide()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := ColorRect.new()
	panel.color = Color("202b32")
	panel.size = Vector2(1280, 720)
	canvas.add_child(panel)
	var title := Label.new()
	title.text = "FAUNA TERRESTRE"
	title.position = Vector2(36, 24)
	title.add_theme_font_size_override("font_size", 25)
	panel.add_child(title)
	# --winter enseña las especies de invierno (liebre ártica, zorro ártico y lemming).
	var first := 3 if "--winter" in OS.get_cmdline_user_args() else 0
	for i in 3:
		var container := SubViewportContainer.new()
		container.position = Vector2(12 + i * 424, 80)
		container.size = Vector2(408, 530)
		panel.add_child(container)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(408, 530)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.msaa_3d = Viewport.MSAA_4X
		container.add_child(viewport)
		var root := Node3D.new()
		viewport.add_child(root)
		var env := WorldEnvironment.new()
		env.environment = environment
		root.add_child(env)
		for angles in [Vector3(-38, -35, 0), Vector3(-25, 125, 0)]:
			var light := DirectionalLight3D.new()
			light.rotation_degrees = angles
			light.light_energy = 1.6 if angles.y < 0 else 0.55
			light.light_color = Color("fff0d7") if angles.y < 0 else Color("bfd8e9")
			root.add_child(light)
		var animal := SimpleSmallAnimalModel.new()
		root.add_child(animal)
		animal.set_species(first + i)
		animal.rotation_degrees.y = -140
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.size = [0.68, 1.0, 0.46][i]
		var target := animal.transform * animal.body.mesh.get_aabb().get_center()
		camera.position = target + Vector3(0, 0.32, 2)
		root.add_child(camera)
		camera.look_at(target)
		var label := Label.new()
		label.text = SimpleSmallAnimalModel.NAMES[first + i]
		label.position = Vector2(12 + i * 424, 624)
		label.size.x = 408
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 27)
		panel.add_child(label)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/fauna/small_ground_%s.png"
		% ("winter" if first > 0 else "rebuilt"))

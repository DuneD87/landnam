extends RefCounted

## Render común de iconos con materiales del juego, luz de estudio (IconStudio) y fondo
## transparente. Lo comparten el horneado de armas y la actualización de iconos de la interfaz.

const SIZE := 384


static func prepare_model(model: MeshInstance3D, item_name: String) -> void:
	# Un perfil de menos de un píxel desaparece al reducirlo. Ensancha solo el render del icono.
	if item_name == "hunting_bow":
		model.scale = Vector3(1.6, 1.0, 1.9)
	elif item_name in ["spear", "flint_spear", "arrow", "branch"]:
		model.scale = Vector3(1.65, 1.0, 1.65)


## [exposure] escala la luz del estudio (IconStudio.light): menos para lo claro y mate, que se quema.
static func render(tree: SceneTree, model: Node3D, angles: Array, output: String, bow: bool, pitch := 0.0,
		exposure := 1.0) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var holder := Node3D.new()
	stage.add_child(holder)
	holder.add_child(model)
	holder.rotation_degrees = Vector3(0, angles[1], 0)
	holder.basis = Basis(Vector3.BACK, deg_to_rad(angles[0])) * Basis(Vector3.RIGHT, deg_to_rad(pitch)) * holder.basis
	var bounds: AABB
	var first := true
	for node in [model] + model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part == null or part.mesh == null:
			continue
		var box := holder.global_transform.affine_inverse() * part.global_transform * part.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if bow:
		var cord := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		var top := model.transform * WeaponMeshes.bow_tip(true)
		var bottom := model.transform * WeaponMeshes.bow_tip(false)
		cylinder.top_radius = 0.008
		cylinder.bottom_radius = 0.008
		cylinder.height = top.distance_to(bottom)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("d5c6a8")
		material.roughness = 0.85
		cylinder.material = material
		cord.mesh = cylinder
		cord.position = (top + bottom) * 0.5
		holder.add_child(cord)
		bounds = bounds.merge(cord.transform * cylinder.get_aabb())
	bounds = holder.transform * bounds
	var extent := maxf(bounds.size.x, bounds.size.y)
	# Centra y normaliza: las herramientas antiguas tienen una escala distinta a las armas.
	holder.position = -bounds.get_center()
	holder.scale = Vector3.ONE / extent
	holder.position /= extent
	IconStudio.light(stage, exposure)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.14
	camera.position = Vector3(0, 0, 4)
	stage.add_child(camera)
	camera.current = true
	for frame in 6:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	# Tras girar el modelo, su caja 3D puede dejar mucho aire (sobre todo en lanzas y pares).
	var used := image.get_used_rect()
	if not used.has_area():
		push_error("Icono vacío: " + output)
		tree.quit(1)
		return
	var silhouette := image.get_region(used)
	var factor := SIZE * 0.89 / maxf(used.size.x, used.size.y)
	silhouette.resize(maxi(1, roundi(used.size.x * factor)), maxi(1, roundi(used.size.y * factor)), Image.INTERPOLATE_LANCZOS)
	image.fill(Color.TRANSPARENT)
	image.blit_rect(silhouette, Rect2i(Vector2i.ZERO, silhouette.get_size()), (image.get_size() - silhouette.get_size()) / 2)
	if image.save_png(output) != OK:
		push_error("No se pudo guardar el icono: " + output)
		tree.quit(1)
		return
	print("Icono: ", output)
	# Los renders se reducen mucho en la barra: los mipmaps conservan el filo sin parpadeo.
	var options := ConfigFile.new()
	if options.load(output + ".import") == OK:
		options.set_value("params", "mipmaps/generate", true)
		options.save(output + ".import")
	viewport.queue_free()
	await tree.process_frame

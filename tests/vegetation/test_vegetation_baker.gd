extends Node3D

## Necesita render real: verifica las dos rutas asíncronas de horneado y sus materiales.
var failures := 0


func _enter_tree() -> void:
	if "--background" in OS.get_cmdline_user_args():
		get_window().unfocusable = true
		get_window().position = Vector2i(-4000, -4000)


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	var terrain := VoxelLodTerrain.new()
	add_child(terrain)
	var planet := Planet.new(terrain)
	add_child(planet)
	var source: Node = load("res://scenes/planet/planet_items/vegetation/grass/low_poly_grass.tscn").instantiate()
	var mesh: Mesh = source.get_child(0).mesh
	var baker := VegetationBaker.new(planet)
	var tree := await baker.bake_tree_impostor(mesh, 64)
	check(tree != null and tree.get_surface_count() == 1, "Se hornea el impostor con su malla")
	if tree != null:
		check(is_equal_approx(tree.get_aabb().size.y, mesh.get_aabb().size.y),
			"El impostor conserva la altura del modelo")
		var material := tree.surface_get_material(0) as ShaderMaterial
		check(material.get_shader_parameter("albedo_texture") != null, "El impostor tiene su textura horneada")
	var card := await baker.bake_grass_patch(mesh,
		{"tex_size": 64, "size_m": 1.0, "clump_count": 4, "handoff_end_m": 50.0})
	check(card != null and card.get_surface_count() == 1, "Se hornea la tarjeta de hierba")
	if card != null:
		var material := card.surface_get_material(0) as ShaderMaterial
		var atlas: Texture2DArray = material.get_shader_parameter("patch_atlas")
		check(atlas.get_layers() == 2 and atlas.get_width() == 64, "La tarjeta mantiene separadas sus dos vistas")
	check(planet.item_transparent_materials.size() == 2, "Ambos materiales reciben las actualizaciones planetarias")
	await get_tree().process_frame
	check(planet.voxel_instancer.get_child_count() == 0, "Los viewports temporales se retiran al acabar")
	source.free()
	planet.free()
	terrain.free()
	print("VEGETATION BAKER: %d failures" % failures)
	get_tree().quit(1 if failures else 0)

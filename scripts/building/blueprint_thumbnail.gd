class_name BlueprintThumbnail
extends Node

## Miniaturas de las construcciones y los blueprints, con la luz de estudio de los iconos
## (IconStudio) y en la misma isométrica que los iconos de bloque. Una construcción en pie se pinta
## copiando las mallas de sus chunks, que ya existen, así que cuesta lo mismo una caseta que un
## barco; un blueprint guardado sin miniatura (de antes) se malla de sus datos, hasta
## DATA_BLOCK_LIMIT bloques. Las miniaturas se guardan junto al blueprint (GridBlueprint).
##
## Los renders van de uno en uno (cada uno es un SubViewport propio durante unos frames).

## Lado de la miniatura en píxeles.
const SIZE := 384
const YAW := 45.0
const PITCH := 30.0
const MARGIN := 0.06
## Por encima de esto un blueprint sin miniatura se queda sin ella: mallarlo entero cuesta segundos.
const DATA_BLOCK_LIMIT := 6000
## Frames que se deja correr el viewport antes de leerlo (el cielo del reflejo tarda en hacerse).
const WARMUP_FRAMES := 4

var _busy := false


## Miniatura de una construcción en pie (sus grids). Con [bp_name] se guarda como la de ese
## blueprint. null si no hay nada que pintar.
func render_grids(grids: Array, bp_name: String = "") -> Texture2D:
	if not can_render():
		return null
	return await _render(_parts_from_grids(grids), bp_name)


## Miniatura de un blueprint leído de disco, que se guarda con él. null si es demasiado grande o no
## tiene bloques.
func render_data(data: Dictionary, bp_name: String) -> Texture2D:
	if not can_render() or int(data.get("block_count", 0)) > DATA_BLOCK_LIMIT:
		return null
	return await _render(_parts_from_data(data), bp_name)


## Sin ventana no se dibuja nada y frame_post_draw no llega nunca (las pruebas headless).
static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"


## [malla, transform respecto a la primera grid] de cada chunk. El cristal se pinta con su
## sucedáneo opaco, como en su icono.
func _parts_from_grids(grids: Array) -> Array:
	var parts: Array = []
	var reference: GridBase = null
	for grid: GridBase in grids:
		if grid.get_block_count() > 0 and (reference == null or grid.get_block_count() > reference.get_block_count()):
			reference = grid
	if reference == null:
		return parts
	var to_local := reference.get_grid_world_transform().affine_inverse()
	for grid: GridBase in grids:
		for instance in grid.get_chunk_mesh_instances():
			var world := instance.global_transform if instance.is_inside_tree() \
				else grid.get_grid_world_transform() * instance.transform
			parts.append([instance.mesh, to_local * world])
	return parts


func _parts_from_data(data: Dictionary) -> Array:
	var parts: Array = []
	for grid_data: Dictionary in data.get("grids", []):
		var blocks := GridBlueprint.blocks_dict(grid_data)
		# Lo que ya no se puede reconstruir tampoco se pinta.
		for grid_pos: Vector3i in blocks.keys():
			if BlockDatabase.get_block(blocks[grid_pos]["block_id"]) == null:
				blocks.erase(grid_pos)
		if blocks.is_empty():
			continue
		var materials := {}
		for info: Dictionary in blocks.values():
			var mat_id: String = info["material_id"]
			var mat := BlockDatabase.get_material_by_id(mat_id)
			if mat and not materials.has(mat_id):
				materials[mat_id] = mat.surface_material
		var mesh := ChunkMeshBuilder.build_mesh(blocks, float(grid_data.get("cell_size", 1.0)),
			Transform3D.IDENTITY, materials)
		if mesh:
			parts.append([mesh, Transform3D.IDENTITY])
	return parts


func _render(parts: Array, bp_name: String) -> Texture2D:
	if parts.is_empty():
		return null
	while _busy:
		await get_tree().process_frame
	_busy = true

	var viewport := IconStudio.make_viewport(SIZE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	IconStudio.light(stage, IconStudio.BLOCK_EXPOSURE, IconStudio.BLOCK_FILL)
	var holder := Node3D.new()
	stage.add_child(holder)

	var bounds := AABB()
	var first := true
	for part: Array in parts:
		var mesh: Mesh = part[0]
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.transform = part[1]
		for s in mesh.get_surface_count():
			var surface := mesh.surface_get_material(s)
			if surface:
				instance.set_surface_override_material(s, BlockDatabase.icon_material_for_surface(surface))
		holder.add_child(instance)
		var box: AABB = instance.transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false

	for child: Node3D in holder.get_children():
		child.position -= bounds.get_center()
	holder.basis = IconStudio.view_basis(YAW, PITCH)
	var view := IconStudio.projected_bounds(AABB(-bounds.size * 0.5, bounds.size), holder.basis)
	var extent := maxf(view.size.x, view.size.y) * (1.0 + 2.0 * MARGIN)
	var camera := IconStudio.make_camera(maxf(extent, 0.01))
	camera.position.x = view.get_center().x
	camera.position.y = view.get_center().y
	stage.add_child(camera)
	camera.current = true

	for frame in WARMUP_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	_busy = false

	if image == null or image.is_empty():
		return null
	image.convert(Image.FORMAT_RGBA8)
	if bp_name != "":
		GridBlueprint._ensure_dir()
		if image.save_png(GridBlueprint.thumbnail_path_for(bp_name)) != OK:
			push_warning("[BlueprintThumbnail] No se pudo guardar la miniatura de '%s'." % bp_name)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

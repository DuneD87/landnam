class_name PlanetGrid
extends GridBase

## Grid estática de construcción anclada a un planeta. Los cubos macizos colisionan mediante
## cajas fusionadas en un StaticBody3D único de la grid; los bloques con forma propia
## (rampas, esquinas) mantienen su StaticBody3D individual hijo del planeta.

## Profundidad total del sondeo bajo el bloque; se muestrea el SDF a la mitad de esta distancia por
## debajo de su cara inferior. Generoso a propósito: la superficie que se ve y se pisa es la
## isosuperficie del SDF, que cae ENTRE centros de vóxel, así que muestrear justo bajo la cara puede
## caer todavía en aire aunque el bloque esté apoyado. Subirlo hace que un bloque suspendido a esa
## altura cuente como cimentado, que es el error tolerable de los dos.
const ANCHOR_PROBE := 2.0

var origin_local: Vector3 = Vector3.ZERO
var basis_local: Basis = Basis.IDENTITY

var _collision_body: StaticBody3D = null


## {ok, cells}: 'ok' dice si se PUDO consultar el terreno, y 'cells' qué se encontró. Distinguirlo
## importa porque cero apoyos significa dos cosas opuestas —la estructura flota de verdad, o no
## había con qué preguntar— y una manda derrumbar mientras la otra manda no tocar nada.
##
## Celdas apoyadas en el TERRENO. No se lanza ningún rayo: la pregunta es solo "¿hay roca aquí?",
## que es una consulta puntual al SDF. Con rayos de física esto costaba ~200 ms en el hilo de física
## de un casco grande, y además fallaba en los dos casos que importan (ver más abajo).
##
## El rayo va hacia el ABAJO GRAVITACIONAL, no el -Y de la grid, que solo coincide si se construyó
## alineada a la superficie. Otras grids no cuentan como cimiento: apoyarse en otro edificio no es
## estar en el suelo.
func compute_anchor_cells() -> Dictionary:
	var anchors: Dictionary = {}
	if _blocks.is_empty():
		return {"ok": true, "cells": anchors}
	if not planet_node or not planet_node.is_inside_tree():
		return {"ok": false, "cells": anchors}

	var xform := get_grid_world_transform()
	var down_world : Vector3 = (planet_node.global_pos - xform.origin).normalized()
	if down_world.is_zero_approx():
		return {"ok": false, "cells": anchors}
	var terrain: VoxelLodTerrain = planet_node.voxel_terrain
	if not terrain:
		return {"ok": false, "cells": anchors}
	var voxel_tool: VoxelTool = terrain.get_voxel_tool()
	if not voxel_tool:
		return {"ok": false, "cells": anchors}

	var down_cell := -up_cell()
	# VoxelTool trabaja en el espacio del terreno, no en el del mundo: el planeta se mueve con el
	# rebase del origen flotante, así que hay que convertir en vez de pasar coordenadas globales.
	var to_terrain := terrain.global_transform.affine_inverse()

	# Solo se sondea el bloque MÁS BAJO de cada columna. Cualquiera por encima tiene otro bloque de
	# la propia grid entre él y el suelo, así que no puede estar cimentado. Sondear "toda celda sin
	# bloque justo debajo" significaba, en un casco hueco, sondear todos los techos y huecos
	# interiores: miles de rayos para averiguar algo que solo depende de la huella. La excepción que
	# se pierde —roca colada en una cavidad interior— no compensa el coste.
	var lowest: Dictionary = {}
	for cell: Vector3i in _blocks:
		var key := _column_key(cell, down_cell)
		var below := _depth_along(cell, down_cell)
		if not lowest.has(key) or below > _depth_along(lowest[key], down_cell):
			lowest[key] = cell

	# Consulta PUNTUAL al SDF, no un raycast. Un rayo busca la transición aire->sólido, y el bloque
	# más bajo de un casco medio enterrado arranca ya DENTRO de la roca: bajando desde ahí no hay
	# ninguna transición que encontrar y devolvía null siempre (medido: 0 anclajes en un barco de
	# 23.000 bloques apoyado en piedra). Preguntar "¿hay roca en este punto?" funciona igual esté
	# el bloque enterrado o posado, y de paso es O(1) en vez de recorrer vóxeles.
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	for cell: Vector3i in lowest.values():
		var center_local := (Vector3(cell) + Vector3.ONE * 0.5) * cell_size
		var below := xform * center_local + down_world * (cell_size * 0.5 + ANCHOR_PROBE * 0.5)
		if _is_solid_terrain(voxel_tool, to_terrain * below):
			anchors[cell] = true

	return {"ok": true, "cells": anchors}


## True si hay materia de terreno en ese punto (en espacio del terreno). En godot_voxel el SDF es
## negativo dentro de la materia y positivo en el aire.
static func _is_solid_terrain(voxel_tool: VoxelTool, point_terrain: Vector3) -> bool:
	return voxel_tool.get_voxel_f(Vector3i(point_terrain.round())) < 0.0


## Muestra en crudo del sondeo, para el comando 'anchors'. Sirve para confirmar con datos el signo
## del SDF y que las coordenadas caen donde deben, en vez de darlo por supuesto.
func debug_anchor_sample(count: int = 5) -> String:
	if _blocks.is_empty() or not planet_node:
		return "sin bloques"
	var terrain: VoxelLodTerrain = planet_node.voxel_terrain
	if not terrain:
		return "planet_node no tiene voxel_terrain"
	var voxel_tool: VoxelTool = terrain.get_voxel_tool()
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF

	var xform := get_grid_world_transform()
	var down_world: Vector3 = (planet_node.global_pos - xform.origin).normalized()
	var to_terrain := terrain.global_transform.affine_inverse()
	var down_cell := -up_cell()

	var lowest: Dictionary = {}
	for cell: Vector3i in _blocks:
		var key := _column_key(cell, down_cell)
		if not lowest.has(key) or _depth_along(cell, down_cell) > _depth_along(lowest[key], down_cell):
			lowest[key] = cell

	var out := "  terreno en %v · identidad: %s
" % [
		terrain.global_position, terrain.global_transform.is_equal_approx(Transform3D.IDENTITY)]
	# Se muestrea el SDF en las DOS convenciones. dig_hole pasa coordenadas de mundo directas a
	# VoxelTool y funciona, pero la API documenta espacio del terreno: con la transform del planeta
	# lejos de la identidad solo una puede ser la buena, y a ojo son indistinguibles.
	var shown := 0
	for cell: Vector3i in lowest.values():
		if shown >= count:
			break
		var center_local := (Vector3(cell) + Vector3.ONE * 0.5) * cell_size
		var below := xform * center_local + down_world * (cell_size * 0.5 + ANCHOR_PROBE * 0.5)
		var p_local := to_terrain * below
		out += "  celda %v
    mundo   %v -> sdf %.3f
    terreno %v -> sdf %.3f
" % [
			cell,
			below, voxel_tool.get_voxel_f(Vector3i(below.round())),
			p_local, voxel_tool.get_voxel_f(Vector3i(p_local.round()))]
		shown += 1
	return out


## Celda proyectada quitando el eje de la gravedad: identifica la columna a la que pertenece.
static func _column_key(cell: Vector3i, down: Vector3i) -> Vector3i:
	if down.x != 0:
		return Vector3i(0, cell.y, cell.z)
	if down.y != 0:
		return Vector3i(cell.x, 0, cell.z)
	return Vector3i(cell.x, cell.y, 0)


## Cuánto desciende una celda a lo largo del eje de gravedad; a mayor valor, más abajo.
static func _depth_along(cell: Vector3i, down: Vector3i) -> int:
	return cell.x * down.x + cell.y * down.y + cell.z * down.z


## Celda vecina en la dirección del ARRIBA gravitacional, en coordenadas de grid. No es +Y salvo
## que la grid se construyera alineada a la superficie.
func up_cell() -> Vector3i:
	if not planet_node:
		return Vector3i(0, 1, 0)
	var xform := get_grid_world_transform()
	var up_world : Vector3 = (xform.origin - planet_node.global_pos).normalized()
	if up_world.is_zero_approx():
		return Vector3i(0, 1, 0)
	return _dominant_axis(xform.basis.inverse() * up_world)


## Celda vecina en la dirección dominante de un vector en espacio de grid.
static func _dominant_axis(v: Vector3) -> Vector3i:
	var a := v.abs()
	if a.x >= a.y and a.x >= a.z:
		return Vector3i(1 if v.x > 0.0 else -1, 0, 0)
	if a.y >= a.z:
		return Vector3i(0, 1 if v.y > 0.0 else -1, 0)
	return Vector3i(0, 0, 1 if v.z > 0.0 else -1)


func setup(id: String, planet: Node3D, origin_world: Vector3, basis_world: Basis, size: float = 1.0) -> void:
	grid_id = id
	planet_node = planet
	cell_size = size

	var planet_inv := planet.global_transform.affine_inverse()
	origin_local = planet_inv * origin_world
	basis_local = planet_inv.basis * basis_world

func is_same_origin_basis(other: GridBase) -> bool:
	if other is PlanetGrid:
		return origin_local.is_equal_approx(other.origin_local) \
			and basis_local.is_equal_approx(other.basis_local)
	return false
	
func setup_aligned(id: String, planet: Node3D, ref_origin_local: Vector3, ref_basis_local: Basis, size: float) -> void:
	grid_id = id
	planet_node = planet
	cell_size = size
	origin_local = ref_origin_local
	basis_local = ref_basis_local


func get_grid_world_transform() -> Transform3D:
	return planet_node.global_transform * Transform3D(basis_local, origin_local)


func _get_mesh_local_transform() -> Transform3D:
	return Transform3D(basis_local, origin_local)


func _get_mesh_parent() -> Node3D:
	return planet_node


func _get_collision_parent() -> Node3D:
	if _collision_body and is_instance_valid(_collision_body):
		return _collision_body

	_collision_body = StaticBody3D.new()
	_collision_body.name = "GridBody_%s" % grid_id
	_collision_body.transform = Transform3D(basis_local, origin_local)
	_collision_body.set_meta("grid_id", grid_id)
	planet_node.add_child(_collision_body)
	return _collision_body


## Quitar un bloque puede dejar parte de la estructura sin apoyo; colocarlo nunca.
func _on_block_removed_hook(_info: Dictionary) -> void:
	GridManager.mark_collapse_check(self)


func clear() -> void:
	super.clear()
	if _collision_body and is_instance_valid(_collision_body):
		_collision_body.queue_free()
		_collision_body = null


func _create_block_node(grid_pos: Vector3i, block_data: BlockData, rotation_basis: Basis, world_transform: Transform3D) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "Block_%s_%s" % [grid_id, grid_pos]
	body.transform = planet_node.global_transform.affine_inverse() * world_transform

	var collider := CollisionShape3D.new()
	var shape: Shape3D = block_data.collision_shape.duplicate()

	if shape is BoxShape3D:
		shape.size = shape.size * cell_size
	else:
		collider.scale = Vector3.ONE * cell_size

	collider.shape = shape
	var c := Vector3.ONE * cell_size * 0.5
	collider.position = rotation_basis.inverse() * c
	body.add_child(collider)

	body.set_meta("grid_id", grid_id)
	body.set_meta("grid_pos", grid_pos)
	body.set_meta("block_id", block_data.block_id)
	body.set_meta("rotation_basis", rotation_basis)

	planet_node.add_child(body)
	return body


func _create_prop_anchor(key: String, anchor_local: Transform3D, collider_size: Vector3) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "Prop_%s_%s" % [grid_id, key]
	body.transform = Transform3D(basis_local, origin_local) * anchor_local

	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = collider_size
	collider.shape = shape
	body.add_child(collider)

	body.set_meta("grid_id", grid_id)
	body.set_meta("prop_key", key)
	planet_node.add_child(body)
	return body


func serialize() -> Dictionary:
	var blocks_data: Dictionary = {}

	for grid_pos in _blocks:
		var info: Dictionary = _blocks[grid_pos]
		var key := "%d,%d,%d" % [grid_pos.x, grid_pos.y, grid_pos.z]
		var node: Node3D = info["node"]

		var t: Transform3D
		if node and is_instance_valid(node):
			t = node.transform
		else:
			var rot: Basis = info.get("rotation_basis", Basis.IDENTITY)
			t = Transform3D(basis_local * rot, origin_local + basis_local * (Vector3(grid_pos) * cell_size))

		blocks_data[key] = {
			"block_id": info["block_id"],
			"rotation_basis": _basis_to_array(info["rotation_basis"]),
			"transform": _transform_to_array(t),
			"material_id": info.get("material_id", ""),
			"mirrored": info.get("mirrored", false),
			"mirror_axis": info.get("mirror_axis", -1),
		}
		# La vida solo se escribe si el bloque está tocado: así una partida vieja, sin la clave,
		# se lee como bloques intactos y el formato queda compatible hacia atrás.
		if info.get("hp", 1.0) < 1.0:
			blocks_data[key]["hp"] = info["hp"]

	var materials_data: Dictionary = {}
	for mat_id in mesh_materials:
		var mat: Material = mesh_materials[mat_id]
		if mat and mat.resource_path != "":
			materials_data[mat_id] = mat.resource_path

	return {
		"type": "static",
		"planet_path": str(planet_node.get_path()),
		"origin_local": _vec3_to_array(origin_local),
		"basis_local": _basis_to_array(basis_local),
		"cell_size": cell_size,
		"blocks": blocks_data,
		"materials": materials_data,
		"props": _serialize_props(),
	}


func deserialize(id: String, planet: Node3D, data: Dictionary) -> void:
	grid_id = id
	planet_node = planet
	cell_size = data.get("cell_size", 1.0)
	origin_local = _array_to_vec3(data.get("origin_local", [0, 0, 0]))
	basis_local = _array_to_basis(data.get("basis_local", [1,0,0, 0,1,0, 0,0,1]))

	var materials_data: Dictionary = data.get("materials", {})
	for mat_id in materials_data:
		var path: String = materials_data[mat_id]
		if ResourceLoader.exists(path):
			mesh_materials[mat_id] = load(path)
		else:
			push_warning("[PlanetGrid] Material resource not found: %s" % path)

	_suppress_rebuild = true
	var blocks_data: Dictionary = data.get("blocks", {})
	for key in blocks_data:
		var parts := (key as String).split(",")
		var grid_pos := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		var block_info: Dictionary = blocks_data[key]

		var block_id: int = block_info.get("block_id", 0)
		var block_data: BlockData = BlockDatabase.get_block(block_id)
		if not block_data:
			push_warning("[PlanetGrid] Block ID %d no encontrado al cargar" % block_id)
			continue

		var saved_transform := _array_to_transform(block_info.get("transform", []))
		var world_transform := planet_node.global_transform * saved_transform
		var rotation_basis := _array_to_basis(block_info.get("rotation_basis", [1,0,0, 0,1,0, 0,0,1]))
		var material_id: String = block_info.get("material_id", "")

		var mirror_data := {
			"mirrored": block_info.get("mirrored", false),
			"mirror_axis": block_info.get("mirror_axis", -1),
		}

		place_block(grid_pos, block_data, rotation_basis, world_transform, material_id, mirror_data)
		var hp: float = block_info.get("hp", 1.0)
		if hp < 1.0 and _blocks.has(grid_pos):
			_blocks[grid_pos]["hp"] = hp
	_suppress_rebuild = false

	_deserialize_props(data.get("props", {}))
	rebuild_mesh()

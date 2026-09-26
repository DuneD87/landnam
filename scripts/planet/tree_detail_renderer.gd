class_name TreeDetailRenderer
extends Node3D

## Geometría cercana de los árboles Branching, en las MISMAS posiciones que sus impostores.
##
## Todos los árboles salen de una sola banda del instancer (la lejana), que dibuja el
## impostor octaédrico y crea un VoxelInstancerRigidBody por árbol cercano (colisión, tala,
## posaderos) con el transform exacto de la instancia. Este nodo lee esos cuerpos y dibuja
## con MultiMesh el LOD0/LOD1/LOD2 de cada árbol según su distancia real a la cámara.
## Antes había una banda cercana aparte y el instancer genera posiciones distintas por
## item (su semilla lleva el id): en el relevo unos árboles se desvanecían y aparecían
## otros, además de cambiar de aspecto.
##
## Cada LOD y el impostor se funden con tramado sobre el mismo árbol (fade_in/fade_out de
## tree_wind.gdshaderinc, por distancia a la cámara del jugador). Aquí solo se decide qué
## árboles entran en cada MultiMesh, con margen: el shader hace el corte exacto cada frame.
## El reparto lo hace TreeInstanceIndex (C++, extensión Tree3D): en GDScript costaba varios
## milisegundos por barrido en un bosque denso.

## [inicio, fin] del fundido de salida de LOD0, LOD1 y LOD2 (el impostor entra en el último).
## Tramos cortos: sin TAA el tramado se ve como un punteado mientras dura.
const LOD_FADES := [Vector2(28.0, 32.0), Vector2(55.0, 59.0), Vector2(90.0, 95.0)]
## Margen de pertenencia: cuánto puede moverse la cámara entre dos repartos.
const MARGIN := 4.0
const REFRESH_MOVE := 2.0
## Celdas de los MultiMesh. Godot recorta un MultiMesh entero por su AABB: con uno solo por
## LOD se dibujaban todos sus árboles (y en cada cascada de sombra) aunque casi todos
## quedaran fuera de cámara.
const CELL_SIZE := 32.0

var instancer: VoxelInstancer
## Coste del último reparto (µs), para las medidas.
var last_sweep_usec := 0
## library id -> {"meshes": [Mesh x3], "cells": {Vector4i(celda, lod): MultiMeshInstance3D}}
var _items: Dictionary = {}
var _index := TreeInstanceIndex.new()
## Cuerpos recién creados: su transform se lee en el siguiente reparto.
var _pending: Array[VoxelInstancerRigidBody] = []
var _dirty := true
var _last_camera := Vector3(INF, INF, INF)
var _lod_ranges := PackedFloat32Array()


func _init(p_instancer: VoxelInstancer) -> void:
	name = "TreeDetailRenderer"
	instancer = p_instancer
	top_level = true
	_index.cell_size = CELL_SIZE
	for lod in 3:
		_lod_ranges.append(0.0 if lod == 0 else LOD_FADES[lod - 1].x - MARGIN)
		_lod_ranges.append(LOD_FADES[lod].y + MARGIN)
	instancer.child_entered_tree.connect(_on_instancer_child_entered)
	instancer.child_exiting_tree.connect(_on_instancer_child_exiting)


## Fundido de un LOD de geometría: sale en su tramo y entra en el del LOD anterior.
static func lod_fade(lod: int) -> Dictionary:
	var fade := {"fade_out_start": LOD_FADES[lod].x, "fade_out_end": LOD_FADES[lod].y}
	if lod > 0:
		fade["fade_in_start"] = LOD_FADES[lod - 1].x
		fade["fade_in_end"] = LOD_FADES[lod - 1].y
	return fade


## Fundido de entrada del impostor: el mismo tramo en que sale el LOD2.
static func impostor_fade() -> Dictionary:
	return {"fade_in_start": LOD_FADES[2].x, "fade_in_end": LOD_FADES[2].y}


func register_item(library_id: int, lod_meshes: Array) -> void:
	_items[library_id] = {"meshes": lod_meshes, "cells": {}}
	_index.reset_changes()
	# Cuerpos que ya existían antes del registro (recarga de la vegetación).
	for child in instancer.get_children():
		_on_instancer_child_entered(child)


## Mallas de detalle (LOD0-LOD2) de un item registrado, con sus materiales de fundido.
func lod_meshes(library_id: int) -> Array:
	return _items.get(library_id, {}).get("meshes", [])


func _on_instancer_child_entered(node: Node) -> void:
	var body := node as VoxelInstancerRigidBody
	if body != null and _items.has(body.get_library_item_id()):
		_pending.append(body)
		_dirty = true


func _on_instancer_child_exiting(node: Node) -> void:
	var body := node as VoxelInstancerRigidBody
	if body == null:
		return
	var id := body.get_instance_id()
	if _index.has(id):
		_index.remove(id)
		_dirty = true
	else:
		_pending.erase(body)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _items.is_empty():
		return
	var eye := camera.global_position
	if _dirty or eye.distance_to(_last_camera) >= REFRESH_MOVE:
		refresh(eye)


## Reparte los árboles cercanos entre los MultiMesh de su celda y LOD.
func refresh(eye: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	_dirty = false
	_last_camera = eye
	for body in _pending:
		if is_instance_valid(body) and body.is_inside_tree():
			_index.add(body.get_instance_id(), body.get_library_item_id(), body.global_transform)
	_pending.clear()

	# Solo llegan las celdas que cambian (y las que se vacían, con el buffer vacío).
	for result in _index.collect_changes(eye, LOD_FADES[2].y + MARGIN, _lod_ranges):
		_set_cell(result[0], result[1], result[2])
	last_sweep_usec = Time.get_ticks_usec() - t0


## Sube `buffer` al MultiMesh de la celda (lo crea si hace falta) o lo oculta si está vacío.
func _set_cell(library_id: int, slot: Vector4i, buffer: PackedFloat32Array) -> void:
	var cells: Dictionary = _items[library_id].cells
	var mmi: MultiMeshInstance3D = cells.get(slot)
	if buffer.is_empty():
		if mmi != null:
			mmi.multimesh.instance_count = 0
			mmi.visible = false
		return
	if mmi == null:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _items[library_id].meshes[slot.w]
		mmi = MultiMeshInstance3D.new()
		mmi.multimesh = multimesh
		add_child(mmi)
		cells[slot] = mmi
	var count: int = buffer.size() / 12
	if mmi.multimesh.instance_count != count:
		mmi.multimesh.instance_count = count
	mmi.multimesh.buffer = buffer
	mmi.visible = true

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
const LOD_FADES := [Vector2(28.0, 32.0), Vector2(55.0, 59.0), Vector2(140.0, 155.0)]
## Margen de pertenencia: cuánto puede moverse la cámara entre dos repartos.
const MARGIN := 4.0
const REFRESH_MOVE := 3.0
## Presupuesto por fotograma para subir celdas cambiadas (µs). Un reparto cambia ~200 celdas
## y subirlas de golpe costaba ~1 ms en un solo fotograma; MARGIN cubre el retraso.
## Solo mientras la cámara va despacio: el retraso de la subida diferida es REFRESH_MOVE más lo
## que avanza durante la subida, y al volar deprisa pasaba de MARGIN y los árboles de los
## bordes de cada LOD quedaban en la celda de otro (a 80 m/s, huecos de hasta 240 árboles
## que parpadeaban). Entonces el reparto se sube entero en su fotograma.
const UPLOAD_BUDGET_USEC := 350
## Celdas de los MultiMesh. Godot recorta un MultiMesh entero por su AABB: con uno solo por
## LOD se dibujaban todos sus árboles (y en cada cascada de sombra) aunque casi todos
## quedaran fuera de cámara.
const CELL_SIZE := 32.0
## Multiplicador de celda por LOD: el anillo del LOD2 tiene la mayoría de los árboles, y con
## celdas de 32 m eran ~1.200 MultiMesh (9 especies x 3 LODs).
const LOD_CELL_SCALES: Array[int] = [1, 1, 2]
## LODs que proyectan sombra. Desde el LOD2 la sombra la proyecta el impostor (un quad visto
## desde la luz) con el mismo tramado con que sale la del LOD1: la geometría del LOD2 en las
## cascadas eran 12 M de primitivas y ~1 ms de GPU en un bosque denso.
const SHADOW_LODS := 2

var instancer: VoxelInstancer
## LODs que proyectan sombra con las opciones gráficas: todos los de SHADOW_LODS, solo el LOD0
## (sombras de vegetación cercanas) o ninguno.
var _shadow_lods := SHADOW_LODS
## Coste del último reparto (µs) y del último _process (µs), para las medidas.
var last_sweep_usec := 0
var last_frame_usec := 0
## Parte del reparto que se va en el índice (C++) y número de celdas subidas.
var last_collect_usec := 0
var last_changed_cells := 0
## library id -> {"meshes": [Mesh x3], "cells": {Vector4i(celda, lod): MultiMeshInstance3D}}
var _items: Dictionary = {}
var _index := TreeInstanceIndex.new()
## Cuerpos recién creados: su transform se lee en el siguiente reparto.
var _pending: Array[VoxelInstancerRigidBody] = []
var _dirty := true
var _last_camera := Vector3(INF, INF, INF)
var _previous_eye := Vector3(INF, INF, INF)
## Fotogramas que lleva la subida diferida en curso y los que tardó la última.
var _upload_frames := 0
var _last_upload_frames := 3
var _lod_ranges := PackedFloat32Array()
## Celdas cambiadas pendientes de subir: [library id, Vector4i, PackedFloat32Array].
var _uploads: Array = []


func _init(p_instancer: VoxelInstancer) -> void:
	name = "TreeDetailRenderer"
	instancer = p_instancer
	_shadow_lods = [0, 1, SHADOW_LODS][SettingsManager.vegetation_shadows()]
	top_level = true
	# El proyecto tiene la interpolación física activada: un MultiMesh interpolado mezcla cada
	# instancia con la del mismo índice en el buffer anterior. Al rehacer el reparto de una
	# celda cambia qué árbol ocupa cada índice, y durante un fotograma los árboles aparecían a
	# medio camino entre dos árboles distintos (parpadeo, árboles de otro tamaño).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_index.cell_size = CELL_SIZE
	_index.lod_cell_scales = PackedInt32Array(LOD_CELL_SCALES)
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


## Fundido de entrada del impostor: el mismo tramo en que sale el LOD2. Su sombra entra
## donde deja de proyectarla la geometría (ver SHADOW_LODS).
static func impostor_fade() -> Dictionary:
	return {"fade_in_start": LOD_FADES[2].x, "fade_in_end": LOD_FADES[2].y,
		"shadow_fade_in_start": LOD_FADES[SHADOW_LODS - 1].x,
		"shadow_fade_in_end": LOD_FADES[SHADOW_LODS - 1].y}


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
	var frame_start := Time.get_ticks_usec()
	var step := eye.distance_to(_previous_eye) if _previous_eye.is_finite() else 0.0
	_previous_eye = eye
	var due := _dirty or eye.distance_to(_last_camera) >= REFRESH_MOVE
	if step * (_last_upload_frames + 1) > MARGIN - REFRESH_MOVE:
		_flush_uploads(-1)
		if due:
			refresh(eye, true)
	# El reparto y la subida van en fotogramas distintos: juntos sumaban ~1,5 ms en uno.
	elif _uploads.is_empty() and due:
		refresh(eye, false)
		_upload_frames = 0
	elif not _uploads.is_empty():
		_flush_uploads(UPLOAD_BUDGET_USEC)
		_upload_frames += 1
		if _uploads.is_empty():
			_last_upload_frames = _upload_frames
	last_frame_usec = Time.get_ticks_usec() - frame_start


## Reparte los árboles cercanos entre los MultiMesh de su celda y LOD. Con immediate = false
## las celdas cambiadas se suben en los fotogramas siguientes (ver UPLOAD_BUDGET_USEC).
func refresh(eye: Vector3, immediate: bool = true) -> void:
	var t0 := Time.get_ticks_usec()
	_dirty = false
	_last_camera = eye
	for body in _pending:
		if is_instance_valid(body) and body.is_inside_tree():
			_index.add(body.get_instance_id(), body.get_library_item_id(), body.global_transform)
	_pending.clear()

	# Solo llegan las celdas que cambian (y las que se vacían, con el buffer vacío).
	var t1 := Time.get_ticks_usec()
	var changes: Array = _index.collect_changes(eye, LOD_FADES[2].y + MARGIN, _lod_ranges)
	last_collect_usec = Time.get_ticks_usec() - t1
	last_changed_cells = changes.size()
	_uploads.append_array(changes)
	if immediate:
		_flush_uploads(-1)
	last_sweep_usec = Time.get_ticks_usec() - t0


## Sube celdas pendientes hasta agotar el presupuesto (µs); -1 = todas.
func _flush_uploads(budget_usec: int) -> void:
	var start := Time.get_ticks_usec()
	var done := 0
	while done < _uploads.size():
		var result: Array = _uploads[done]
		_set_cell(result[0], result[1], result[2])
		done += 1
		if budget_usec >= 0 and Time.get_ticks_usec() - start >= budget_usec:
			break
	_uploads = _uploads.slice(done)


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
		if slot.w >= _shadow_lods:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		cells[slot] = mmi
	var count: int = buffer.size() / 12
	if mmi.multimesh.instance_count != count:
		mmi.multimesh.instance_count = count
	mmi.multimesh.buffer = buffer
	mmi.visible = true

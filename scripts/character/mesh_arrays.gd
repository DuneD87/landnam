class_name MeshArrays

## A mesh's surface arrays and LODs without reading them back from the GPU.
##
## surface_get_arrays() and RenderingServer.mesh_get_surface() read the mesh's buffers back from the
## renderer: each read stalls the GPU and holds the rendering device, so even from a worker thread
## the main thread waits on it (18-20 ms frames in a village while its people were being dressed,
## 2026-11-24). Dressing and merging a human read some fifty surfaces.
##
## - A mesh built with add_surface() keeps what it was built from (metadata on the mesh, until
##   forget()); read() and lods() hand that back.
## - A mesh loaded from disk (the body, the garments: shared by everyone) is read back once and kept.
## - Anything else is read back as before.
## Safe from any thread.

const META := &"cpu_surfaces"

## Loaded mesh -> [[arrays, lods] per surface].
static var _shared := {}
static var _lock := Mutex.new()


## add_surface_from_arrays() that keeps `arrays` and `lods` for read() and lods().
static func add_surface(mesh: ArrayMesh, primitive: Mesh.PrimitiveType, arrays: Array, blend_shapes: Array = [],
		lods: Dictionary = {}, flags := 0) -> void:
	var kept: Array = mesh.get_meta(META) if mesh.has_meta(META) else []
	var aligned := kept.size() == mesh.get_surface_count()
	mesh.add_surface_from_arrays(primitive, arrays, blend_shapes, lods, flags)
	if aligned:
		# Deep: packed arrays go by reference, and the caller may still write into them.
		kept.append([arrays.duplicate(true), lods.duplicate(true)])
		mesh.set_meta(META, kept)
	elif mesh.has_meta(META):
		mesh.remove_meta(META)


## clear_surfaces(), and what add_surface() kept.
static func clear(mesh: ArrayMesh) -> void:
	mesh.clear_surfaces()
	if mesh.has_meta(META):
		mesh.remove_meta(META)


## Whether read() and lods() of `mesh` need no read back.
static func is_kept(mesh: ArrayMesh) -> bool:
	if _own(mesh) != null:
		return true
	_lock.lock()
	var shared := _shared.has(mesh)
	_lock.unlock()
	return shared


## Surface `s` of `mesh`, as surface_get_arrays() gives it (a copy: change it freely, even in place).
static func read(mesh: ArrayMesh, s: int) -> Array:
	var entry := _entry(mesh, s)
	if entry.is_empty():
		return mesh.surface_get_arrays(s)
	# Deep (each packed array copied on write): a shallow copy would share them with the cache.
	return (entry[0] as Array).duplicate(true)


## The LODs of surface `s` of `mesh`, as add_surface_from_arrays() takes them: {error: PackedInt32Array}.
static func lods(mesh: ArrayMesh, s: int) -> Dictionary:
	var entry := _entry(mesh, s)
	if entry.is_empty():
		return _read_lods(mesh, s)
	return (entry[1] as Dictionary).duplicate(true)


## Drops what the meshes under `root` kept (once nothing needs to read them any more).
static func forget(root: Node) -> void:
	for instance: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if instance.mesh != null and instance.mesh.has_meta(META):
			instance.mesh.remove_meta(META)


## Reads every surface of the loaded `meshes` now, so nobody reads them later in the middle of play.
static func warm(meshes: Array) -> void:
	for mesh: ArrayMesh in meshes:
		if mesh != null and mesh.get_surface_count() > 0:
			_entry(mesh, 0)


static func _own(mesh: ArrayMesh) -> Array:
	if not mesh.has_meta(META):
		return []
	var kept: Array = mesh.get_meta(META)
	return kept if kept.size() == mesh.get_surface_count() else []


## [arrays, lods] of surface `s`, or [] if `mesh` must be read back each time.
static func _entry(mesh: ArrayMesh, s: int) -> Array:
	var own := _own(mesh)
	if not own.is_empty():
		return own[s]
	if mesh.resource_path.is_empty():
		return []
	_lock.lock()
	var surfaces: Array = _shared.get(mesh, [])
	_lock.unlock()
	if surfaces.is_empty():
		for i in mesh.get_surface_count():
			surfaces.append([mesh.surface_get_arrays(i), _read_lods(mesh, i)])
		_lock.lock()
		_shared[mesh] = surfaces
		_lock.unlock()
	return surfaces[s]


static func _read_lods(mesh: ArrayMesh, s: int) -> Dictionary:
	var data := RenderingServer.mesh_get_surface(mesh.get_rid(), s)
	var result := {}
	var index_count: int = data.get("index_count", 0)
	if index_count == 0:
		return result
	var width: int = (data.index_data as PackedByteArray).size() / index_count
	for lod: Dictionary in data.get("lods", []):
		var bytes: PackedByteArray = lod.index_data
		var indices := PackedInt32Array()
		if width == 4:
			indices = bytes.to_int32_array()
		else:
			indices.resize(bytes.size() / 2)
			for k in indices.size():
				indices[k] = bytes.decode_u16(k * 2)
		result[lod.edge_length] = indices
	return result

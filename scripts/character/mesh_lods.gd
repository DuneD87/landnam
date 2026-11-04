class_name MeshLods

## Niveles de detalle (LOD) de una malla con meshoptimizer (ImporterMesh.generate_lods): los mismos
## vértices y menos triángulos. El renderer elige el nivel por el error que se vería en pantalla
## (rendering/mesh_lod/lod_change/threshold_pixels), así que de cerca se ve la malla entera.
##
## El error va en unidades de la malla y el renderer lo escala con la de la instancia. El humano y lo
## que lleva puesto cuelgan de un Armature a 0,01 (los binds devuelven la malla a metros): su
## lod_bias lo deshace (CharacterAppearanceRig).

## Dos vértices en el mismo sitio con las normales a menos de esto (°) se simplifican como uno (lo que
## usa el importador de escenas).
const NORMAL_MERGE_ANGLE := 60.0


## Los LODs de una superficie de triángulos ([arrays] como los da surface_get_arrays), como los toma
## add_surface_from_arrays: {error: PackedInt32Array}. {} si no tiene índices o no se simplifica.
static func generate(arrays: Array) -> Dictionary:
	var result := {}
	if arrays[Mesh.ARRAY_INDEX] == null or (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
		return result
	# Solo lo que mira la simplificación: los huesos y los pesos no le hacen falta.
	var plain := []
	plain.resize(Mesh.ARRAY_MAX)
	for a in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
		plain[a] = arrays[a]
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, plain)
	importer.generate_lods(NORMAL_MERGE_ANGLE, 0.0, [])
	for lod in importer.get_surface_lod_count(0):
		result[importer.get_surface_lod_size(0, lod)] = importer.get_surface_lod_indices(0, lod)
	return result


## Pone LODs a cada superficie de triángulos de [mesh], sin tocar sus vértices (se cambian los
## _surfaces en crudo: rehacerlos desde los arrays volvería a cuantizar normales y tangentes). Las que
## ya los tienen se rehacen. El número de superficies con LODs.
static func add_to(mesh: ArrayMesh) -> int:
	var packed: Array = mesh.get("_surfaces")
	var count := 0
	for s in packed.size():
		var surface: Dictionary = packed[s]
		surface.erase("lods")
		var index_count: int = surface.get("index_count", 0)
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES or index_count == 0:
			continue
		var lods := generate(mesh.surface_get_arrays(s))
		if lods.is_empty():
			continue
		var wide := (surface.index_data as PackedByteArray).size() / index_count == 4
		var flat := []
		for error: float in lods:
			var indices: PackedInt32Array = lods[error]
			var bytes := PackedByteArray()
			if wide:
				bytes = indices.to_byte_array()
			else:
				bytes.resize(indices.size() * 2)
				for k in indices.size():
					bytes.encode_u16(k * 2, indices[k])
			flat.append(error)
			flat.append(bytes)
		surface.lods = flat
		count += 1
	var name := mesh.resource_name
	mesh.clear_surfaces()
	mesh.set("_surfaces", packed)
	mesh.resource_name = name
	return count

extends SceneTree

## Discos repujados sobre la piel. Cada disco rígido sigue al hueso de mayor peso en el broche,
## de modo que sigue al cuerpo también después del ajuste a otro personaje.
const FITTINGS := {
	"coat": [Vector3(0.0, 0.39, 0.23), 0.108, false],
	"breeches": [Vector3(0.133, -0.18, 0.16), 0.052, true],
	"gauntlets": [Vector3(0.517, 0.215, 0.052), 0.042, true],
	"boots": [Vector3(0.147, -0.61, 0.02), 0.049, true],
}
const RINGS := [
	# Radio, relieve y color: cerco, ocho rayos sobre pátina y botón central.
	[1.0, 0.0, "754b30"], [0.96, 0.10, "f4c783"], [0.89, 0.13, "d99754"],
	[0.84, 0.05, "40776b"], [0.70, 0.07, "326459"], [0.41, 0.18, "f3c781"],
	[0.32, 0.12, "77502f"], [0.27, 0.20, "efba68"], [0.008, 0.31, "fada98"],
]
const SEGMENTS := 32


func _initialize() -> void:
	for part in FITTINGS:
		var garment: ArrayMesh = load("res://models/equipable/stone_age/antler_%s.res" % part)
		var fitting: Array = FITTINGS[part]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var at: Vector3 = fitting[0]
		_add_disc(st, garment, at, fitting[1])
		if fitting[2]:
			_add_disc(st, garment, Vector3(-at.x, at.y, at.z), fitting[1])
		st.generate_normals()
		var metal := StandardMaterial3D.new()
		metal.vertex_color_use_as_albedo = true
		metal.vertex_color_is_srgb = true
		metal.metallic = 0.62
		metal.roughness = 0.37
		st.set_material(metal)
		var path := "res://models/equipable/bronze_age/sunscale_%s_boss.res" % part
		if ResourceSaver.save(st.commit(), path, ResourceSaver.FLAG_COMPRESS) != OK:
			quit(1)
			return
	quit()


func _add_disc(st: SurfaceTool, garment: Mesh, target: Vector3, radius: float) -> void:
	var nearest := INF
	var anchor := Vector3.ZERO
	var normal := Vector3.BACK
	var bind_index := 0
	for surface in garment.get_surface_count():
		if garment.surface_get_material(surface).resource_name not in ["pelt", "leather", "bone"]:
			continue
		var arrays := garment.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bind_indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var influences: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for i in vertices.size():
			var distance := target.distance_squared_to(vertices[i])
			if distance < nearest and normals[i].z > 0.4:
				nearest = distance
				anchor = vertices[i]
				normal = normals[i]
				var stride := bind_indices.size() / vertices.size()
				var first := i * stride
				var strongest := first
				for j in range(first + 1, first + stride):
					if influences[j] > influences[strongest]:
						strongest = j
				bind_index = bind_indices[strongest]
	var bones := PackedInt32Array([bind_index, 0, 0, 0])
	var weights := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
	var tangent := Vector3.UP.cross(normal).normalized()
	var up := normal.cross(tangent)
	var start := ProcMesh.vertex_count(st)
	for row in RINGS.size():
		var ring: Array = RINGS[row]
		for i in SEGMENTS:
			var theta := TAU * i / SEGMENTS
			var ray := row == 5 and i % 4 == 0
			var reach: float = 0.79 if ray else ring[0]
			st.set_color(Color(ring[2]))
			st.set_bones(bones)
			st.set_weights(weights)
			ProcMesh.emit(st, Vector2.ZERO, anchor + radius * (reach * (tangent * cos(theta) + up * sin(theta))
				+ normal * (0.16 + float(ring[1]))))
			if row > 0:
				var a := start + (row - 1) * SEGMENTS + i
				var b := start + (row - 1) * SEGMENTS + (i + 1) % SEGMENTS
				for index in [a, a + SEGMENTS, b, b, a + SEGMENTS, b + SEGMENTS]:
					st.add_index(index)

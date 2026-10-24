class_name ThatchRoofMesh
extends RefCounted

## Faldón a 45° y cumbrera de una celda, extruidos sobre X. Los cantos de unión mantienen
## exactamente su perfil: la cara inferior sigue la pendiente de la grid y el grosor sube
## sobre ella, dejando el espacio completo para los triángulos y los muros de madera.
## La misma geometría alimenta iconos, fantasmas y chunks; la colisión usa su envolvente convexa.
const THICKNESS := 0.18
const COURSE_LIFT := 0.035
const COURSES := 4


static func generate_mesh(ridge: bool = false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	emit(st, ridge, Vector3(-0.5, 0.0, -0.5), Basis.IDENTITY, 1.0)
	st.generate_tangents()
	return st.commit()


static func generate_collision(ridge: bool = false) -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	for p: Vector2 in profile(ridge):
		for x: float in [-0.5, 0.5]:
			points.append(Vector3(x, p.y - 0.5, p.x - 0.5))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape


## Perfil (Z, Y), antihorario. La cumbrera une dos faldones separados por una celda:
## su cara inferior queda a Y=0 y el caballete a Y=0,5 + THICKNESS.
static func profile(ridge: bool = false) -> PackedVector2Array:
	var result := PackedVector2Array([Vector2(0, 0)])
	if ridge:
		result.append(Vector2(1, 0))
		result.append(Vector2(1, THICKNESS))
		result.append(Vector2(0.8, 0.31 + THICKNESS))
		result.append(Vector2(0.6, 0.48 + THICKNESS))
		result.append(Vector2(0.5, 0.5 + THICKNESS))
		result.append(Vector2(0.4, 0.48 + THICKNESS))
		result.append(Vector2(0.2, 0.31 + THICKNESS))
	else:
		result.append(Vector2(1, 1))
		result.append(Vector2(1, 1.0 + THICKNESS))
		for i in range(COURSES - 1, 0, -1):
			var z := float(i) / COURSES
			result.append(Vector2(z, z + COURSE_LIFT + THICKNESS))
			result.append(Vector2(z, z + THICKNESS))
	result.append(Vector2(0, THICKNESS))
	return result


static func volume_factor(ridge: bool = false) -> float:
	var outline := profile(ridge)
	var area := 0.0
	for i in outline.size():
		area += outline[i].cross(outline[(i + 1) % outline.size()])
	return absf(area) * 0.5


static func emit(st: SurfaceTool, ridge: bool, offset: Vector3, rot: Basis,
	size: float, flip: bool = false) -> void:
	var outline := profile(ridge)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		_quad(st, Vector3(0, a.y, a.x), Vector3(1, a.y, a.x),
			Vector3(1, b.y, b.x), Vector3(0, b.y, b.x), offset, rot, size, flip)

	# Las capas hacen cóncavo el perfil del faldón; un abanico de triángulos lo rellenaría mal.
	var indices := Geometry2D.triangulate_polygon(outline)
	for i in range(0, indices.size(), 3):
		var a := outline[indices[i]]
		var b := outline[indices[i + 1]]
		var c := outline[indices[i + 2]]
		_triangle(st, Vector3(0, a.y, a.x), Vector3(0, b.y, b.x), Vector3(0, c.y, c.x),
			offset, rot, size, flip)
		_triangle(st, Vector3(1, c.y, c.x), Vector3(1, b.y, b.x), Vector3(1, a.y, a.x),
			offset, rot, size, flip)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	offset: Vector3, rot: Basis, size: float, flip: bool) -> void:
	_triangle(st, a, b, c, offset, rot, size, flip)
	_triangle(st, a, c, d, offset, rot, size, flip)


static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
	offset: Vector3, rot: Basis, size: float, flip: bool) -> void:
	var local_normal := (b - a).cross(c - a).normalized()
	var normal := (rot * local_normal).normalized()
	# Proyectar sobre los ejes girados conserva las fibras a favor de la pendiente incluso
	# al girar o reflejar la pieza. Las UV en metros continúan entre módulos vecinos.
	var local_u := ChunkMeshBuilder.uv_tangent(local_normal)
	var u := rot * local_u
	var v := rot * local_u.cross(local_normal)
	var center := Vector3.ONE * size * 0.5
	var vertices := [a, b, c] if flip else [a, c, b]
	for p: Vector3 in vertices:
		var position := rot * (p * size - center) + center + offset
		st.set_normal(normal)
		st.set_uv(Vector2(position.dot(u), position.dot(v)))
		st.add_vertex(position)

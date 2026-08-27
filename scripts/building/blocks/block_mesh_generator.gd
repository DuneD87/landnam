class_name BlockMeshGenerator
extends RefCounted

## Genera las meshes (y sus shapes de colisión) de los bloques base con SurfaceTool.
## Todas encajan en una celda size×size×size con el origen en el centro de la base.


## Cubo size×size×size con el origen en el centro de la base.
static func generate_cube(size: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var h := size
	var s := size * 0.5

	var v0 := Vector3(-s, 0, +s)
	var v1 := Vector3(+s, 0, +s)
	var v2 := Vector3(+s, 0, -s)
	var v3 := Vector3(-s, 0, -s)
	var v4 := Vector3(-s, h, +s)
	var v5 := Vector3(+s, h, +s)
	var v6 := Vector3(+s, h, -s)
	var v7 := Vector3(-s, h, -s)

	_add_quad(st, v0, v1, v5, v4, Vector3.FORWARD)
	_add_quad(st, v2, v3, v7, v6, Vector3.BACK)
	_add_quad(st, v1, v2, v6, v5, Vector3.RIGHT)
	_add_quad(st, v3, v0, v4, v7, Vector3.LEFT)
	_add_quad(st, v4, v5, v6, v7, Vector3.UP)
	_add_quad(st, v3, v2, v1, v0, Vector3.DOWN)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()


## Rampa (prisma triangular) que sube de -Z a +Z; origen en el centro de la base.
static func generate_slope(size: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var h := size
	var s := size * 0.5

	var v0 := Vector3(-s, 0, +s)
	var v1 := Vector3(+s, 0, +s)
	var v2 := Vector3(+s, 0, -s)
	var v3 := Vector3(-s, 0, -s)
	var v4 := Vector3(-s, h, +s)
	var v5 := Vector3(+s, h, +s)

	_add_quad(st, v3, v2, v1, v0, Vector3.DOWN)
	_add_quad(st, v0, v1, v5, v4, Vector3.FORWARD)

	var slope_normal := Vector3(0, 1, 1).normalized()
	_add_quad(st, v4, v5, v2, v3, slope_normal)

	var left_normal := Vector3.LEFT
	_add_triangle(st, v3, v0, v4, left_normal)

	var right_normal := Vector3.RIGHT
	_add_triangle(st, v1, v2, v5, right_normal)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


## Esquina (tetraedro) con el único vértice superior en frontal-izquierda (+Z, -X).
static func generate_corner(size: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var h := size
	var s := size * 0.5

	var v0 := Vector3(-s, 0, +s)
	var v1 := Vector3(+s, 0, +s)
	var v2 := Vector3(+s, 0, -s)
	var v3 := Vector3(-s, 0, -s)
	var v4 := Vector3(-s, h, +s)

	_add_quad(st, v3, v2, v1, v0, Vector3.DOWN)
	_add_triangle(st, v0, v1, v4, Vector3.FORWARD)
	_add_triangle(st, v3, v0, v4, Vector3.LEFT)

	var slope_normal := (v2 - v4).cross(v1 - v4).normalized()
	_add_triangle(st, v4, v1, v2, slope_normal)
	_add_triangle(st, v4, v2, v3, slope_normal)
	st.generate_normals()
	st.generate_tangents()

	return st.commit()


## Fracción de celda que el panel se retranquea desde su cara. Pegado al borde para encadenar con
## el panel inclinado, pero no exactamente EN el borde: ahí sería coplanar con la cara del vecino
## macizo, que nunca se cullea contra algo no sólido, y las dos pelearían por la profundidad.
const PANE_INSET := 0.02

## Panel plano perpendicular a Z, pegado a la cara -Z de la celda; origen en el centro de la base.
## Es la pieza de ventana: una lámina en vez de un bloque macizo, para que el cristal no apile dos
## caras por bloque. Se emite por las dos caras porque los materiales opacos culean la trasera.
static func generate_pane(size: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var h := size
	var s := size * 0.5
	var z := -s + size * PANE_INSET

	var v0 := Vector3(-s, 0, z)
	var v1 := Vector3(+s, 0, z)
	var v2 := Vector3(+s, h, z)
	var v3 := Vector3(-s, h, z)

	_add_quad(st, v0, v1, v2, v3, Vector3.BACK)
	_add_quad(st, v3, v2, v1, v0, Vector3.FORWARD)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()


## Panel inclinado: la lámina ocupa exactamente el plano de la cara inclinada de la rampa, para que
## encaje contra una rampa maciza sin escalón. Origen en el centro de la base, dos caras.
static func generate_pane_slope(size: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var h := size
	var s := size * 0.5

	var v0 := Vector3(-s, h, +s)
	var v1 := Vector3(+s, h, +s)
	var v2 := Vector3(+s, 0, -s)
	var v3 := Vector3(-s, 0, -s)

	_add_quad(st, v0, v1, v2, v3, Vector3.UP)
	_add_quad(st, v3, v2, v1, v0, Vector3.DOWN)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()


## Losa fina en el plano de la rampa. Convexa porque una caja habría que girarla 45° y la forma se
## coloca con la rotación del bloque, no con una propia.
static func generate_pane_slope_collision(size: float = 1.0, thickness: float = 0.1) -> ConvexPolygonShape3D:
	var s := size * 0.5
	var n := Vector3(0, 1, -1).normalized() * (thickness * 0.5)
	var corners := [
		Vector3(-s, +s, +s), Vector3(+s, +s, +s),
		Vector3(+s, -s, -s), Vector3(-s, -s, -s),
	]
	var points := PackedVector3Array()
	for corner: Vector3 in corners:
		points.append(corner + n)
		points.append(corner - n)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape


## Losa fina en el plano del panel: no tiene grosor visible, pero la colisión sí. Convexa y no caja
## porque la forma se coloca centrada en la celda y una BoxShape3D no se puede desplazar dentro de
## ella: la colisión se quedaría en el centro y chocarías media celda antes del cristal.
static func generate_pane_collision(size: float = 1.0, thickness: float = 0.1) -> ConvexPolygonShape3D:
	var s := size * 0.5
	var z := -s + size * PANE_INSET
	var t := thickness * 0.5
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(-s, -s, z - t), Vector3(+s, -s, z - t),
		Vector3(+s, +s, z - t), Vector3(-s, +s, z - t),
		Vector3(-s, -s, z + t), Vector3(+s, -s, z + t),
		Vector3(+s, +s, z + t), Vector3(-s, +s, z + t),
	])
	return shape


static func generate_cube_collision(size: float = 1.0) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(size, size, size)
	return shape


static func generate_slope_collision(size: float = 1.0) -> ConvexPolygonShape3D:
	var s := size * 0.5
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(-s, -s, +s), Vector3(+s, -s, +s),
		Vector3(+s, -s, -s), Vector3(-s, -s, -s),
		Vector3(-s, +s, +s), Vector3(+s, +s, +s),
	])
	return shape


static func generate_corner_collision(size: float = 1.0) -> ConvexPolygonShape3D:
	var s := size * 0.5
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(-s, -s, +s), Vector3(+s, -s, +s),
		Vector3(+s, -s, -s), Vector3(-s, -s, -s),
		Vector3(-s, +s, +s),
	])
	return shape


## Cubo al que le falta el vértice frontal-izquierdo-superior (v4): 3 caras cuadradas y 4 triangulares.
static func generate_inv_corner(size: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var h := size
	var s := size * 0.5

	var v0 := Vector3(-s, 0, +s)
	var v1 := Vector3(+s, 0, +s)
	var v2 := Vector3(+s, 0, -s)
	var v3 := Vector3(-s, 0, -s)
	var v5 := Vector3(+s, h, +s)
	var v6 := Vector3(+s, h, -s)
	var v7 := Vector3(-s, h, -s)

	_add_quad(st, v3, v2, v1, v0, Vector3.DOWN)
	_add_quad(st, v2, v3, v7, v6, Vector3.BACK)
	_add_quad(st, v1, v2, v6, v5, Vector3.RIGHT)

	_add_triangle(st, v5, v6, v7, Vector3.UP)
	_add_triangle(st, v3, v0, v7, Vector3.LEFT)
	_add_triangle(st, v0, v1, v5, Vector3.FORWARD)

	var slope_normal := (v5 - v0).cross(v7 - v0).normalized()
	_add_triangle(st, v0, v5, v7, slope_normal)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()


static func generate_inv_corner_collision(size: float = 1.0) -> ConvexPolygonShape3D:
	var s := size * 0.5
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(-s, -s, +s), Vector3(+s, -s, +s),
		Vector3(+s, -s, -s), Vector3(-s, -s, -s),
		Vector3(+s, +s, +s), Vector3(+s, +s, -s),
		Vector3(-s, +s, -s)
	])
	return shape


## Añade un quad (2 triángulos) al SurfaceTool; vértices en orden CCW vistos desde fuera.
static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	var uv_a := Vector2(0, 0)
	var uv_b := Vector2(1, 0)
	var uv_c := Vector2(1, 1)
	var uv_d := Vector2(0, 1)

	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_c)
	st.add_vertex(c)
	st.set_uv(uv_b)
	st.add_vertex(b)

	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_d)
	st.add_vertex(d)
	st.set_uv(uv_c)
	st.add_vertex(c)


## Añade un triángulo al SurfaceTool.
static func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	var uv_a := Vector2(0, 0)
	var uv_b := Vector2(1, 0)
	var uv_c := Vector2(0.5, 1)

	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_c)
	st.add_vertex(c)
	st.set_uv(uv_b)
	st.add_vertex(b)

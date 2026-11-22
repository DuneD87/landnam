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
## Materiales cuyo panel va a ras de la cara de la celda cuando no tiene un macizo detrás: los que
## cierran frontones y tabiques, que tienen que seguir el plano del muro. El cristal no: se retranquea.
const FLUSH_PANE_MATERIALS: Array[String] = ["wood", "planks", "plaster"]
## Grosor relativo a la celda del cerramiento triangular de los frontones.
const PANE_TRIANGLE_THICKNESS := 0.10


## Triángulo rectángulo en la cara -Z, con el ángulo recto abajo a la izquierda.
## Se comparten vértices con el mallador y la física para conservar la silueta exacta.
static func pane_triangle_vertices(size: float = 1.0) -> PackedVector3Array:
	var s := size * 0.5
	var t := size * PANE_TRIANGLE_THICKNESS * 0.5
	# La cara exterior coincide con la cara de la pared. Todo el grosor queda hacia dentro.
	var z := -s - t
	return PackedVector3Array([
		Vector3(-s, 0, z - t), Vector3(s, 0, z - t), Vector3(-s, size, z - t),
		Vector3(-s, 0, z + t), Vector3(s, 0, z + t), Vector3(-s, size, z + t),
	])


static func generate_pane_triangle(size: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	ChunkMeshBuilder._emit_pane_triangle(st, Vector3(-0.5, 0, -0.5) * size, Basis.IDENTITY, size, false)
	st.generate_tangents()
	return st.commit()


static func generate_pane_triangle_collision(size: float = 1.0) -> ConvexPolygonShape3D:
	var points := pane_triangle_vertices(size)
	for i in points.size():
		points[i] -= Vector3.UP * size * 0.5
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape

## Panel plano perpendicular a Z, pegado a la cara -Z de la celda; origen en el centro de la base.
## Es la pieza de ventana: una lámina en vez de un bloque macizo, para que el cristal no apile dos
## caras por bloque. Se emite por las dos caras porque los materiales opacos culean la trasera.
static func generate_pane(size: float = 1.0, inset: float = PANE_INSET) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var h := size
	var s := size * 0.5
	var z := -s + size * inset

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
static func generate_pane_collision(size: float = 1.0, thickness: float = 0.1, inset: float = PANE_INSET) -> ConvexPolygonShape3D:
	var s := size * 0.5
	var z := -s + size * inset
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
## Las UV son las mismas que emite ChunkMeshBuilder, para que el icono enseñe la textura a la escala
## del bloque colocado. Se proyectan con la normal de la geometría: `normal` no siempre es la de fuera.
static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	var n := (b - a).cross(d - a).normalized()
	var u := ChunkMeshBuilder.uv_tangent(n)
	var uv_a := ChunkMeshBuilder.planar_uv(a, u, n)
	var uv_b := ChunkMeshBuilder.planar_uv(b, u, n)
	var uv_c := ChunkMeshBuilder.planar_uv(c, u, n)
	var uv_d := ChunkMeshBuilder.planar_uv(d, u, n)

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
	var n := (b - a).cross(c - a).normalized()
	var u := ChunkMeshBuilder.uv_tangent(n)
	var uv_a := ChunkMeshBuilder.planar_uv(a, u, n)
	var uv_b := ChunkMeshBuilder.planar_uv(b, u, n)
	var uv_c := ChunkMeshBuilder.planar_uv(c, u, n)

	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_c)
	st.add_vertex(c)
	st.set_uv(uv_b)
	st.add_vertex(b)


# --- Carpintería y losa --------------------------------------------------------------------------
# Cajas dentro de la celda, en fracciones de celda (0-1), con la cara -Z de la celda en z = 0 como el
# panel. Las comparten el mallador de chunks (ChunkMeshBuilder._emit_box), los iconos y la física.

## Poste: un madero de pie en el centro de la celda. Tumbado (girado en X o Z) es una viga.
const POST_BOX: Array[Vector3] = [Vector3(0.39, 0.0, 0.39), Vector3(0.61, 1.0, 0.61)]
## Listón de fachada: un madero pegado a la cara -Z de su celda y a su canto -X, de pie. En la celda de
## fuera de un muro, girado con la -Z hacia él, hace el entramado: las líneas van por los cantos de las
## celdas, así que siguen de una celda a la de al lado sin hueco. Tumbado (girado en el eje de la cara)
## va por el canto de abajo: soleras, dinteles y peanas.
const BEAM_BOX: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(0.18, 1.0, 0.12)]
## Escuadra: el listón de pie y otro tumbado por el canto de abajo, para los cruces del entramado.
const BEAM_L_BOXES: Array = [[Vector3(0.0, 0.0, 0.0), Vector3(0.18, 1.0, 0.12)],
	[Vector3(0.18, 0.0, 0.0), Vector3(1.0, 0.18, 0.12)]]
## Losa: la mitad de abajo de la celda. De lado es medio muro; arriba, un mostrador o un banco.
const SLAB_BOX: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.5, 1.0)]
## Riostra: el madero en diagonal de la esquina de abajo a la izquierda (-X) a la de arriba a la
## derecha, pegado a la cara -Z como el listón: ancho (de canto a canto) y grueso.
const BRACE_WIDTH := 0.2
const BRACE_DEPTH := 0.12


## Volumen de las piezas nuevas, en fracción de celda (GridBase._block_volume_factor). -1 si no es una.
static func carpentry_volume(block_id: int) -> float:
	match block_id:
		BlockDatabase.BLOCK_POST_ID: return _box_volume(POST_BOX)
		BlockDatabase.BLOCK_BEAM_ID: return _box_volume(BEAM_BOX)
		BlockDatabase.BLOCK_SLAB_ID: return _box_volume(SLAB_BOX)
		BlockDatabase.BLOCK_BRACE_ID: return BRACE_WIDTH * sqrt(2.0) * BRACE_DEPTH
		BlockDatabase.BLOCK_BEAM_L_ID: return _box_volume(BEAM_L_BOXES[0]) + _box_volume(BEAM_L_BOXES[1])
	return -1.0


static func _box_volume(box: Array) -> float:
	var d: Vector3 = box[1] - box[0]
	return d.x * d.y * d.z


## Los ocho vértices de la riostra (0-1): la cara de atrás (z = 0) y la de delante.
static func brace_points() -> PackedVector3Array:
	var w := BRACE_WIDTH * sqrt(2.0)
	var out := PackedVector3Array()
	for z: float in [0.0, BRACE_DEPTH]:
		for q: Vector2 in [Vector2(0, 0), Vector2(w, 0), Vector2(1, 1), Vector2(1 - w, 1)]:
			out.append(Vector3(q.x, q.y, z))
	return out


static func generate_box_mesh(box: Array, size: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	ChunkMeshBuilder._emit_box(st, Vector3(-0.5, 0, -0.5) * size, Basis.IDENTITY, size, false, box)
	st.generate_tangents()
	return st.commit()


static func generate_beam_l_mesh(size: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	for box: Array in BEAM_L_BOXES:
		ChunkMeshBuilder._emit_box(st, Vector3(-0.5, 0, -0.5) * size, Basis.IDENTITY, size, false, box)
	st.generate_tangents()
	return st.commit()


## La envolvente de la escuadra: un triángulo con grosor que cubre las dos piezas. Para chocar basta.
static func generate_beam_l_collision(size: float = 1.0) -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	for z: float in [0.0, 0.12]:
		for q: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.18), Vector2(0.18, 1), Vector2(0, 1)]:
			points.append((Vector3(q.x, q.y, z) - Vector3.ONE * 0.5) * size)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape


static func generate_brace_mesh(size: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	ChunkMeshBuilder._emit_brace(st, Vector3(-0.5, 0, -0.5) * size, Basis.IDENTITY, size, false)
	st.generate_tangents()
	return st.commit()


## Colisión centrada en la celda, como las demás formas.
static func generate_box_collision(box: Array, size: float = 1.0) -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	for x: float in [box[0].x, box[1].x]:
		for y: float in [box[0].y, box[1].y]:
			for z: float in [box[0].z, box[1].z]:
				points.append((Vector3(x, y, z) - Vector3.ONE * 0.5) * size)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape


static func generate_brace_collision(size: float = 1.0) -> ConvexPolygonShape3D:
	var points := brace_points()
	for i in points.size():
		points[i] = (points[i] - Vector3.ONE * 0.5) * size
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape

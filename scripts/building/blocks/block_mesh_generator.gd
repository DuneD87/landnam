class_name BlockMeshGenerator
extends RefCounted

## Genera las meshes de los bloques base usando SurfaceTool.
## Todas las meshes encajan en una celda de 1x1x1 (configurable via size).
## El origen (0,0,0) está en el centro de la base del bloque.

# ============================================================
#  CUBE
# ============================================================
# Cubo estándar 1x1x1. Origen en el centro de la base.
#
#   Y (up)
#   |   
#   |  7------6
#   | /|     /|
#   |/ |    / |
#   4------5  |
#   |  3---|--2
#   | /    | /
#   |/     |/
#   0------1 --- X
#  /
# Z
#
# Vértices (con origen en centro de base):
#   0: (-0.5, 0, +0.5)   1: (+0.5, 0, +0.5)
#   2: (+0.5, 0, -0.5)   3: (-0.5, 0, -0.5)
#   4: (-0.5, 1, +0.5)   5: (+0.5, 1, +0.5)
#   6: (+0.5, 1, -0.5)   7: (-0.5, 1, -0.5)

static func generate_cube(size: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var h := size  # altura
	var s := size * 0.5  # mitad del lado
	
	# --- Definir los 8 vértices ---
	var v0 := Vector3(-s, 0, +s)
	var v1 := Vector3(+s, 0, +s)
	var v2 := Vector3(+s, 0, -s)
	var v3 := Vector3(-s, 0, -s)
	var v4 := Vector3(-s, h, +s)
	var v5 := Vector3(+s, h, +s)
	var v6 := Vector3(+s, h, -s)
	var v7 := Vector3(-s, h, -s)
	
	# Front face (+Z): v0, v1, v5, v4
	_add_quad(st, v0, v1, v5, v4, Vector3.FORWARD)
	# Back face (-Z): v2, v3, v7, v6
	_add_quad(st, v2, v3, v7, v6, Vector3.BACK)
	# Right face (+X): v1, v2, v6, v5
	_add_quad(st, v1, v2, v6, v5, Vector3.RIGHT)
	# Left face (-X): v3, v0, v4, v7
	_add_quad(st, v3, v0, v4, v7, Vector3.LEFT)
	# Top face (+Y): v4, v5, v6, v7
	_add_quad(st, v4, v5, v6, v7, Vector3.UP)
	# Bottom face (-Y): v3, v2, v1, v0
	_add_quad(st, v3, v2, v1, v0, Vector3.DOWN)
	
	st.generate_tangents()
	return st.commit()


# ============================================================
#  SLOPE (Rampa)
# ============================================================
# Prisma triangular: la cara frontal (+Z) es completa,
# la trasera (-Z) solo tiene la base. La pendiente va de
# la arista superior frontal hacia la arista inferior trasera.
#
#   Vista lateral (X = constante):
#
#   4/5 ___
#   |      \___
#   |          \___
#   0/1-----------2/3
#
# La rampa sube desde -Z (suelo) hasta +Z (arriba).
# Así al rotarla 0° la pendiente mira hacia +Z.
#
#   Vértices:
#   0: (-0.5, 0, +0.5)   1: (+0.5, 0, +0.5)
#   2: (+0.5, 0, -0.5)   3: (-0.5, 0, -0.5)
#   4: (-0.5, 1, +0.5)   5: (+0.5, 1, +0.5)

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
	
	# Bottom face: v3, v2, v1, v0
	_add_quad(st, v3, v2, v1, v0, Vector3.DOWN)
	
	# Front face (+Z) - cuadrado completo: v0, v1, v5, v4
	_add_quad(st, v0, v1, v5, v4, Vector3.FORWARD)
	
	# Slope face (diagonal): v4, v5, v2, v3
	var slope_normal := Vector3(0, 1, 1).normalized()
	_add_quad(st, v4, v5, v2, v3, slope_normal)
	
	# Left triangle: v3, v0, v4
	var left_normal := Vector3.LEFT
	_add_triangle(st, v3, v0, v4, left_normal)
	
	# Right triangle: v1, v2, v5
	var right_normal := Vector3.RIGHT
	_add_triangle(st, v1, v2, v5, right_normal)
	
	st.generate_tangents()
	return st.commit()


# ============================================================
#  CORNER (Esquina entre slopes)
# ============================================================
# Tetraedro en una esquina: solo queda el vértice superior
# en la posición frontal-izquierda (+Z, -X).
#
#   Vértices:
#   0: (-0.5, 0, +0.5)   1: (+0.5, 0, +0.5)
#   2: (+0.5, 0, -0.5)   3: (-0.5, 0, -0.5)
#   4: (-0.5, 1, +0.5)   <- único vértice superior

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
	
	# Bottom face: v3, v2, v1, v0
	_add_quad(st, v3, v2, v1, v0, Vector3.DOWN)
	
	# Front face (+Z) - triángulo: v0, v1, v4
	_add_triangle(st, v0, v1, v4, Vector3.FORWARD)
	
	# Left face (-X) - triángulo: v3, v0, v4
	_add_triangle(st, v3, v0, v4, Vector3.LEFT)
	
	# Slope face (diagonal): v4, v1, v2, v3 (triángulo grande)
	# Normal apunta hacia arriba-derecha-atrás
	var slope_normal := (v1 - v4).cross(v3 - v4).normalized()
	_add_triangle(st, v4, v1, v2, slope_normal)
	_add_triangle(st, v4, v2, v3, slope_normal)
	
	st.generate_tangents()
	return st.commit()


# ============================================================
#  COLLISION SHAPES
# ============================================================

static func generate_cube_collision(size: float = 1.0) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(size, size, size)
	return shape


## Genera un ConvexPolygonShape3D para el slope.
static func generate_slope_collision(size: float = 1.0) -> ConvexPolygonShape3D:
	var s := size * 0.5
	var h := size
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(-s, 0, +s), Vector3(+s, 0, +s),
		Vector3(+s, 0, -s), Vector3(-s, 0, -s),
		Vector3(-s, h, +s), Vector3(+s, h, +s),
	])
	return shape


## Genera un ConvexPolygonShape3D para el corner.
static func generate_corner_collision(size: float = 1.0) -> ConvexPolygonShape3D:
	var s := size * 0.5
	var h := size
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(-s, 0, +s), Vector3(+s, 0, +s),
		Vector3(+s, 0, -s), Vector3(-s, 0, -s),
		Vector3(-s, h, +s),
	])
	return shape


# ============================================================
#  HELPERS
# ============================================================

## Añade un quad (dos triángulos) al SurfaceTool.
## Vértices en orden counter-clockwise vistos desde fuera.
## a--b
## |  |
## d--c  => triángulos: (a,b,c) y (a,c,d)
static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	# UVs para el quad
	var uv_a := Vector2(0, 0)
	var uv_b := Vector2(1, 0)
	var uv_c := Vector2(1, 1)
	var uv_d := Vector2(0, 1)
	
	st.set_normal(normal)
	
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
	
	st.set_normal(normal)
	
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_c)
	st.add_vertex(c)
	st.set_uv(uv_b)
	st.add_vertex(b)

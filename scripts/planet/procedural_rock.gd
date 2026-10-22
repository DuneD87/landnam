@tool
class_name ProceduralRock
extends Node3D

## Roca procedural del planeta: las grandes, las piedras sueltas, los afloramientos de mena y los
## bloques de hielo. Sustituye a Rock3D del addon, que era una esfera estirada con bultos de ruido
## suaves y se leía como un canto rodado.
##
## Parte de una icoesfera estirada con bultos, la recorta con planos (las caras planas y las aristas
## son lo que la hace roca), la escalona en estratos si se pide y le marca grietas. La base queda en
## y = 0 con la fracción [member sink] de la altura por debajo, porque el instancer planta la escena
## por su origen.
##
## La malla lleva en COLOR.r la oclusión de las cavidades y en COLOR.g si la cara es la de fuera,
## curtida (1). shaders/planet_rock.gdshader las usa, y RockFracture deja la g a 0 en las caras de
## los cortes al picarla.
##
## Se genera al pedirla (get_rock_instance) y la comparten las escenas con los mismos parámetros. En
## el editor se rehace al tocar cualquier parámetro.

## Mallas ya hechas, por firma de parámetros. Fuera del editor: allí cada retoque daría una nueva.
static var _meshes: Dictionary = {}

@export var rock_seed := 1:
	set(v):
		rock_seed = v
		_changed()
## Subdivisiones de la icoesfera: 2 = 162 vértices (piedras sueltas), 4 = 2562 (rocas grandes).
@export_range(1, 5) var subdivisions := 4:
	set(v):
		subdivisions = v
		_changed()
@export_range(0.02, 10.0, 0.01) var radius := 0.5:
	set(v):
		radius = v
		_changed()

@export_group("Shape")
## Estiramiento por eje antes de recortar.
@export var size := Vector3(1.0, 0.8, 1.2):
	set(v):
		size = v
		_changed()
## Cuánto varía cada eje de [member size] con la semilla (fracción).
@export_range(0.0, 0.6, 0.01) var size_variance := 0.15:
	set(v):
		size_variance = v
		_changed()
## Bultos de ruido sobre el radio (fracción) y su frecuencia (sobre la esfera unidad).
@export_range(0.0, 1.0, 0.01) var lump_amount := 0.25:
	set(v):
		lump_amount = v
		_changed()
@export_range(0.1, 6.0, 0.01) var lump_frequency := 1.1:
	set(v):
		lump_frequency = v
		_changed()

@export_group("Facets")
## Planos de corte. Cada uno deja una cara plana con aristas.
@export_range(0, 32) var facet_count := 9:
	set(v):
		facet_count = v
		_changed()
## Lo que se come cada corte: fracción del radio de la roca en su dirección.
@export_range(0.0, 0.8, 0.01) var facet_depth := 0.22:
	set(v):
		facet_depth = v
		_changed()
## Variación de la profundidad de un corte a otro (fracción de [member facet_depth]).
@export_range(0.0, 1.0, 0.01) var facet_variance := 0.6:
	set(v):
		facet_variance = v
		_changed()
## Inclinación de los cortes hacia arriba: 0 = en cualquier dirección, 1 = sobre todo de lado y por
## encima (la cara de abajo queda enterrada y un corte ahí no se ve).
@export_range(0.0, 1.0, 0.01) var facet_upward := 0.6:
	set(v):
		facet_upward = v
		_changed()

@export_group("Strata")
## Estratos a lo alto de la roca (0 = sin estratos): repisas de roca sedimentaria.
@export_range(0, 12) var strata_layers := 0:
	set(v):
		strata_layers = v
		_changed()
## Cuánto entra cada estrato respecto al de al lado (fracción del ancho).
@export_range(0.0, 0.5, 0.01) var strata_inset := 0.12:
	set(v):
		strata_inset = v
		_changed()
## Cuánto se aplana cada estrato en terraza (0 = solo entrantes, 1 = escalones planos).
@export_range(0.0, 1.0, 0.01) var strata_terrace := 0.5:
	set(v):
		strata_terrace = v
		_changed()
## Inclinación de los estratos (grados).
@export_range(0.0, 60.0, 0.1) var strata_tilt := 12.0:
	set(v):
		strata_tilt = v
		_changed()

@export_group("Cracks")
## Profundidad de las grietas (fracción del radio) y su frecuencia (sobre la esfera unidad).
@export_range(0.0, 0.2, 0.001) var crack_depth := 0.0:
	set(v):
		crack_depth = v
		_changed()
@export_range(0.5, 12.0, 0.01) var crack_frequency := 2.5:
	set(v):
		crack_frequency = v
		_changed()

@export_group("Base")
## Fracción de la altura que queda bajo el suelo (por debajo de y = 0).
@export_range(0.0, 0.7, 0.01) var sink := 0.25:
	set(v):
		sink = v
		_changed()
## Oscurece las cavidades (COLOR.r): 0 = nada.
@export_range(0.0, 2.0, 0.01) var cavity_ao := 1.0:
	set(v):
		cavity_ao = v
		_changed()
## Escala de las UV de caja (unidades de malla), para los materiales que texturizan por UV (el hielo).
## El de roca es triplanar y no las usa.
@export_range(0.05, 20.0, 0.01) var uv_scale := 1.0:
	set(v):
		uv_scale = v
		_changed()

@export_group("Materials")
@export var material_rock: Material:
	set(v):
		material_rock = v
		_instance.material_override = v

var _instance := MeshInstance3D.new()
var _dirty := true
var _queued := false


func _init() -> void:
	add_child(_instance, false, Node.INTERNAL_MODE_FRONT)


func _ready() -> void:
	if _dirty:
		_rebuild()


## La malla de la roca, generada si hace falta.
func get_rock_instance() -> MeshInstance3D:
	if _dirty:
		_rebuild()
	return _instance


func _changed() -> void:
	_dirty = true
	if is_inside_tree() and not _queued:
		_queued = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	if not _dirty:
		return
	_dirty = false
	var key := var_to_str([rock_seed, subdivisions, radius, size, size_variance, lump_amount,
		lump_frequency, facet_count, facet_depth, facet_variance, facet_upward, strata_layers,
		strata_inset, strata_terrace, strata_tilt, crack_depth, crack_frequency, sink, cavity_ao, uv_scale])
	var mesh: ArrayMesh = _meshes.get(key)
	if mesh == null:
		mesh = build_mesh()
		if not Engine.is_editor_hint():
			_meshes[key] = mesh
	_instance.mesh = mesh


func build_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = rock_seed
	var verts := PackedVector3Array()
	var faces := PackedInt32Array()
	_icosphere(subdivisions, verts, faces)

	var stretch := size * Vector3(1.0 + rng.randf_range(-1.0, 1.0) * size_variance,
		1.0 + rng.randf_range(-1.0, 1.0) * size_variance, 1.0 + rng.randf_range(-1.0, 1.0) * size_variance)
	var lumps := _noise(rng.randi(), lump_frequency, 4)
	for i in verts.size():
		var d := verts[i]
		verts[i] = d * (radius * (1.0 + lumps.get_noise_3dv(d) * lump_amount)) * stretch

	_cut_facets(verts, rng)
	if strata_layers > 0:
		_terrace(verts, rng)
	if crack_depth > 0.0:
		_crack(verts, rng)

	# Base: la fracción sink de la altura por debajo de y = 0.
	var low := INF
	var high := -INF
	for v in verts:
		low = minf(low, v.y)
		high = maxf(high, v.y)
	var shift := Vector3(0.0, -(low + sink * (high - low)), 0.0)
	for i in verts.size():
		verts[i] += shift

	var normals := _normals(verts, faces)
	var colors := _cavity(verts, normals, _neighbors(verts.size(), faces))
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	for i in verts.size():
		var n := normals[i].abs()
		var p := verts[i] * uv_scale
		if n.x >= n.y and n.x >= n.z:
			uvs[i] = Vector2(p.z, -p.y)
		elif n.y >= n.z:
			uvs[i] = Vector2(p.x, p.z)
		else:
			uvs[i] = Vector2(p.x, -p.y)

	# La icoesfera va en sentido antihorario visto desde fuera; Godot dibuja de frente el horario.
	var indices := PackedInt32Array()
	indices.resize(faces.size())
	for t in range(0, faces.size(), 3):
		indices[t] = faces[t]
		indices[t + 1] = faces[t + 2]
		indices[t + 2] = faces[t + 1]

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	# Tangentes para los materiales con normal map por UV (el de roca no las necesita).
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_tangents()
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	# LOD automáticos: una roca grande lleva miles de triángulos y se ve desde cientos de metros.
	if subdivisions >= 3:
		importer.generate_lods(25.0, 60.0, [])
	return importer.get_mesh()


## Icoesfera unidad de [level] subdivisiones en [verts] y [faces] (tríos, antihorario desde fuera).
static func _icosphere(level: int, verts: PackedVector3Array, faces: PackedInt32Array) -> void:
	var t := (1.0 + sqrt(5.0)) * 0.5
	for p in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append((p as Vector3).normalized())
	faces.append_array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2,
		10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10,
		8, 6, 7, 9, 8, 1])
	for _level in level:
		var mids := {}
		var next := PackedInt32Array()
		for f in range(0, faces.size(), 3):
			var a := faces[f]
			var b := faces[f + 1]
			var c := faces[f + 2]
			var ab := _midpoint(a, b, verts, mids)
			var bc := _midpoint(b, c, verts, mids)
			var ca := _midpoint(c, a, verts, mids)
			next.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
		faces.clear()
		faces.append_array(next)


static func _midpoint(a: int, b: int, verts: PackedVector3Array, mids: Dictionary) -> int:
	var key := mini(a, b) * 1048576 + maxi(a, b)
	if mids.has(key):
		return mids[key]
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	mids[key] = verts.size() - 1
	return verts.size() - 1


static func _noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	noise.fractal_octaves = octaves
	return noise


## Recorta la roca con [member facet_count] planos repartidos alrededor: lo que queda fuera de cada
## uno se lleva sobre él por su rayo desde el centro. Proyectarlo en perpendicular plegaba
## triángulos donde los bultos cruzan el plano; por el rayo, cada punto cae en un sitio distinto y la
## roca sigue siendo estrellada desde su centro (RockFracture lo supone). Cada plano entra una
## fracción de lo que la roca sobresale en su dirección.
func _cut_facets(verts: PackedVector3Array, rng: RandomNumberGenerator) -> void:
	var dirs: Array[Vector3] = []
	for _k in facet_count:
		# De unas cuantas candidatas, la más apartada de las ya elegidas: cortes repartidos.
		var best := Vector3.UP
		var best_score := -INF
		for _candidate in 8:
			var y := rng.randf_range(lerpf(-1.0, -0.25, facet_upward), 1.0)
			var a := rng.randf() * TAU
			var r := sqrt(maxf(1.0 - y * y, 0.0))
			var d := Vector3(cos(a) * r, y, sin(a) * r)
			var score := 0.0
			if not dirs.is_empty():
				score = INF
				for e in dirs:
					score = minf(score, 1.0 - d.dot(e))
			if score > best_score:
				best_score = score
				best = d
		dirs.append(best)
	for n in dirs:
		var top := 0.0
		for v in verts:
			top = maxf(top, v.dot(n))
		var depth := clampf(facet_depth * (1.0 + facet_variance * rng.randf_range(-1.0, 1.0)), 0.0, 0.8)
		var plane := top * (1.0 - depth)
		for i in verts.size():
			var h := verts[i].dot(n)
			if h > plane:
				verts[i] *= plane / h


## Estratos: la altura (sobre un eje algo inclinado) se parte en capas; cada capa entra o sale un
## poco respecto al eje y se aplana hacia su suelo, así que quedan repisas.
func _terrace(verts: PackedVector3Array, rng: RandomNumberGenerator) -> void:
	var pivot := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
	pivot = pivot.normalized() if pivot.length_squared() > 1e-6 else Vector3.RIGHT
	var axis := Vector3.UP.rotated(pivot, deg_to_rad(strata_tilt))
	var low := INF
	var high := -INF
	for v in verts:
		low = minf(low, v.dot(axis))
		high = maxf(high, v.dot(axis))
	var thickness := (high - low) / float(strata_layers)
	var insets := PackedFloat32Array()
	for k in strata_layers + 2:
		insets.append(rng.randf())
	for i in verts.size():
		var v := verts[i]
		var h := v.dot(axis)
		var s := clampf((h - low) / thickness, 0.0, float(strata_layers) - 0.0001)
		var k := floori(s)
		# El salto de una capa a la siguiente se hace en el último cuarto de la capa. La de arriba no
		# tiene siguiente: se aplana entera (si saltara, lo más alto se quedaría de pico).
		var step := smoothstep(0.7, 1.0, s - float(k)) if k < strata_layers - 1 else 0.0
		var inset := lerpf(insets[k], insets[k + 1], step)
		var flat := v - axis * h
		var stepped := lerpf(h, low + (float(k) + step) * thickness, strata_terrace)
		verts[i] = axis * stepped + flat * (1.0 - strata_inset * inset)


## Grietas: surcos a lo largo de las líneas donde un ruido cruza el cero.
func _crack(verts: PackedVector3Array, rng: RandomNumberGenerator) -> void:
	var noise := _noise(rng.randi(), crack_frequency, 2)
	var reach := 0.0
	for v in verts:
		reach = maxf(reach, v.length())
	for i in verts.size():
		var v := verts[i]
		var line := 1.0 - clampf(absf(noise.get_noise_3dv(v / reach)) / 0.08, 0.0, 1.0)
		verts[i] = v - v.normalized() * (line * line * crack_depth * radius)


static func _normals(verts: PackedVector3Array, faces: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for t in range(0, faces.size(), 3):
		var a := faces[t]
		var b := faces[t + 1]
		var c := faces[t + 2]
		var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		normals[a] += n
		normals[b] += n
		normals[c] += n
	for i in normals.size():
		normals[i] = normals[i].normalized()
	return normals


static func _neighbors(count: int, faces: PackedInt32Array) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	out.resize(count)
	for t in range(0, faces.size(), 3):
		for k in 3:
			var a := faces[t + k]
			var b := faces[t + (k + 1) % 3]
			if not out[a].has(b):
				out[a].append(b)
			if not out[b].has(a):
				out[b].append(a)
	return out


## COLOR: r = oclusión de las cavidades (cuánto se hunde cada vértice respecto a sus vecinos, contra
## su normal, suavizado una vez), g = cara curtida (toda la roca entera lo es).
func _cavity(verts: PackedVector3Array, normals: PackedVector3Array,
		neighbors: Array[PackedInt32Array]) -> PackedColorArray:
	var ao := PackedFloat32Array()
	ao.resize(verts.size())
	for i in verts.size():
		var ring := neighbors[i]
		var mean := Vector3.ZERO
		var edge := 0.0
		for j in ring:
			mean += verts[j]
			edge += verts[i].distance_to(verts[j])
		var n := float(maxi(ring.size(), 1))
		var depth := (mean / n - verts[i]).dot(normals[i]) / maxf(edge / n, 1e-6)
		ao[i] = clampf(1.0 - cavity_ao * maxf(depth, 0.0) * 2.5, 0.3, 1.0)
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for i in verts.size():
		var sum := ao[i]
		for j in neighbors[i]:
			sum += ao[j]
		colors[i] = Color(sum / float(neighbors[i].size() + 1), 1.0, 0.0, 1.0)
	return colors

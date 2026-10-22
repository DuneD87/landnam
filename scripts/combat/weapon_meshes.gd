@tool
class_name WeaponMeshes
extends RefCounted

## Mallas de las armas de combate, generadas por código y horneadas a recursos por
## tools/combat/bake_weapons.gd (el alta de un arma nunca ejecuta el SurfaceTool).
##
## Convención de todas: metros, el origen es el punto de agarre de la mano, +Y recorre el arma
## hacia la punta (o hacia arriba, en el arco), +Z es hacia donde mira el filo (o hacia el
## blanco, en el arco y el tirachinas) y X es el plano de la hoja.

const WOOD := &"wood"
const DARK_WOOD := &"dark_wood"
const STEEL := &"steel"
const IRON := &"iron"
const LEATHER := &"leather"
const FLINT := &"flint"
const FEATHER := &"feather"
const CORD := &"cord"
const STONE := &"stone"
const BARK := &"bark"
const BONE := &"bone"
const OBSIDIAN := &"obsidian"
const RAWHIDE := &"rawhide"


## Materiales compartidos, uno por tipo. El grano va en la textura de ruido y las UV lo estiran
## a lo largo de la pieza, así que la madera parece veta y no manchas.
static func make_material(kind: StringName) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = String(kind)
	match kind:
		WOOD:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.22, 0.13, 0.07), Color(0.42, 0.28, 0.16), 0.9, 7)
			mat.roughness = 0.72
		DARK_WOOD:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.16, 0.09, 0.05), Color(0.36, 0.22, 0.12), 0.9, 11)
			mat.roughness = 0.55
		STEEL:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.50, 0.52, 0.55), Color(0.72, 0.74, 0.77), 3.0, 3)
			mat.metallic = 0.92
			mat.roughness = 0.32
			mat.roughness_texture = ProcMesh.noise_texture(Color(0.55, 0.55, 0.55), Color(0.95, 0.95, 0.95), 6.0, 5)
		IRON:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.22, 0.22, 0.23), Color(0.40, 0.39, 0.38), 2.5, 13)
			mat.metallic = 0.85
			mat.roughness = 0.5
		LEATHER:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.18, 0.10, 0.06), Color(0.32, 0.19, 0.11), 4.0, 17)
			mat.roughness = 0.85
		FLINT:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.16, 0.16, 0.17), Color(0.42, 0.40, 0.38), 5.0, 19)
			mat.roughness = 0.38
			mat.metallic = 0.1
		FEATHER:
			mat.albedo_color = Color(0.86, 0.84, 0.78)
			mat.roughness = 0.9
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		CORD:
			mat.albedo_color = Color(0.62, 0.55, 0.42)
			mat.roughness = 0.95
		STONE:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.22, 0.20, 0.18), Color(0.42, 0.39, 0.35), 6.0, 23)
			mat.roughness = 0.9
		BARK:
			# Corteza gris parda, con el grano a lo largo como la madera.
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.10, 0.08, 0.06), Color(0.30, 0.26, 0.21), 1.6, 29)
			mat.roughness = 0.92
		BONE:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.72, 0.68, 0.56), Color(0.92, 0.89, 0.8), 2.0, 31)
			mat.roughness = 0.65
		OBSIDIAN:
			mat.albedo_color = Color(0.03, 0.03, 0.04)
			mat.roughness = 0.08
			mat.metallic_specular = 0.7
		RAWHIDE:
			# Piel cruda tensada y seca: parda clara y translúcida a manchas.
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.42, 0.30, 0.17), Color(0.70, 0.55, 0.36), 2.5, 37)
			mat.roughness = 0.75
	return mat


# ---------------------------------------------------------------------------------------------
# Piezas


## Un pedrusco: una esfera de facetas planas deformada (cada vértice a su distancia), de
## [radius] y achatada en Y por [squash].
static func lump(st: SurfaceTool, center: Vector3, radius: float, seed_value: int, squash: float = 0.8,
		bumps: float = 0.28, basis: Basis = Basis.IDENTITY) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 9
	mesh.rings = 5
	var arrays := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Cada punto del mismo sitio se mueve igual (la costura de la esfera no se abre).
	var offsets := {}
	var moved := PackedVector3Array()
	moved.resize(verts.size())
	for i in verts.size():
		var key := Vector3i((verts[i] * 1000.0).round())
		if not offsets.has(key):
			offsets[key] = 1.0 + rng.randf_range(-bumps, bumps)
		var v: Vector3 = verts[i] * float(offsets[key]) * radius
		v.y *= squash
		moved[i] = center + basis * v
	ProcMesh.set_flat(st, true)
	for t in range(0, indices.size(), 3):
		var a := moved[indices[t]]
		var b := moved[indices[t + 1]]
		var c := moved[indices[t + 2]]
		if (b - a).cross(c - a).length_squared() < 1e-12:
			continue
		ProcMesh.tri(st, a, c, b)
	ProcMesh.set_flat(st, false)


## Empuñadura con vendas: radio que sube y baja en espiral para que se vea el cuero enrollado.
static func wrapped_grip(st: SurfaceTool, y0: float, y1: float, radius: float, turns: int = 9) -> void:
	var profile := []
	var steps := turns * 4
	for i in steps + 1:
		var t := float(i) / steps
		var bump := 0.12 * radius * absf(sin(t * turns * PI))
		profile.append(Vector2(radius + bump, lerpf(y0, y1, t)))
	ProcMesh.lathe(st, profile, 10, Vector3.ZERO, 1.0, 12.0)


## Hoja de sección romboidal (aristas en ±Z, lomo en ±X) de [y0] a la punta. [width] es la
## anchura total en Z en el arranque; el perfil hace una ligera hoja de laurel.
static func blade(st: SurfaceTool, y0: float, length: float, width: float, thickness: float,
		tip: float, fuller: bool = true) -> void:
	var rings := []
	var steps := 14
	for i in steps + 1:
		var t := float(i) / steps
		var y := y0 + length * t
		# Anchura: se ensancha un poco al 60 % (laurel) y se estrecha hacia la punta.
		var w := width * 0.5 * (1.0 + 0.10 * sin(t * PI * 0.95)) * (1.0 - 0.25 * t)
		var th := thickness * 0.5 * (1.0 - 0.45 * t)
		var ring := PackedVector3Array()
		ring.append(Vector3(0, y, w))
		if fuller:
			ring.append(Vector3(th * 0.8, y, w * 0.35))
		ring.append(Vector3(th, y, 0))
		if fuller:
			ring.append(Vector3(th * 0.8, y, -w * 0.35))
		ring.append(Vector3(0, y, -w))
		if fuller:
			ring.append(Vector3(-th * 0.8, y, -w * 0.35))
		ring.append(Vector3(-th, y, 0))
		if fuller:
			ring.append(Vector3(-th * 0.8, y, w * 0.35))
		rings.append(ring)
	# Punta: todos los vértices convergen.
	var last: PackedVector3Array = rings[rings.size() - 1]
	var point := Vector3(0, y0 + length + tip, 0)
	for j in last.size():
		var k := (j + 1) % last.size()
		ProcMesh.tri(st, last[j], last[k], point)
	ProcMesh.loft(st, rings, true, false)


# ---------------------------------------------------------------------------------------------
# Armas


static func sword() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var steel := b.st(STEEL)
	ProcMesh.set_flat(steel, true)
	blade(steel, 0.115, 0.70, 0.054, 0.011, 0.11)
	var iron := b.st(IRON)
	ProcMesh.set_flat(iron, true)
	# Guarda: barra que se afina hacia las puntas, un poco curvada hacia la hoja.
	var guard_rings := []
	for i in 9:
		var t := float(i) / 8.0 * 2.0 - 1.0
		var z := t * 0.105
		var y := 0.100 + 0.012 * t * t
		var h := 0.013 * (1.0 - 0.45 * absf(t))
		var th := 0.015 * (1.0 - 0.35 * absf(t))
		guard_rings.append(PackedVector3Array([
			Vector3(-th, y - h, z), Vector3(th, y - h, z), Vector3(th, y + h, z), Vector3(-th, y + h, z)]))
	for i in guard_rings.size():
		var ring: PackedVector3Array = guard_rings[i]
		# Reordena: el loft va a lo largo de Z, así que cada anillo es una sección en XY.
		guard_rings[i] = ring
	ProcMesh.loft(iron, guard_rings)
	# Pomo facetado.
	ProcMesh.set_flat(iron, false)
	ProcMesh.lathe(iron, [Vector2(0.0, -0.165), Vector2(0.022, -0.158), Vector2(0.030, -0.140),
		Vector2(0.026, -0.122), Vector2(0.014, -0.112)], 8)
	ProcMesh.lathe(iron, [Vector2(0.019, 0.078), Vector2(0.022, 0.086), Vector2(0.016, 0.092)], 8)
	wrapped_grip(b.st(LEATHER), -0.115, 0.080, 0.0165, 10)
	return b.commit(make_material)


static func battle_axe() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	# Astil de madera, un poco más grueso al pie para que no se escurra.
	ProcMesh.lathe(b.st(WOOD), [Vector2(0.0, -0.22), Vector2(0.021, -0.22), Vector2(0.023, -0.19),
		Vector2(0.019, -0.10), Vector2(0.018, 0.30), Vector2(0.019, 0.56), Vector2(0.0, 0.575)], 10, Vector3.ZERO, 1.0, 1.5)
	wrapped_grip(b.st(LEATHER), -0.12, 0.10, 0.0205, 8)
	var iron := b.st(IRON)
	ProcMesh.set_flat(iron, true)
	# Cabeza barbada: perfil en el plano YZ, extruido en X con grosor que baja hacia el filo.
	var cols := 12
	var rings := []
	for i in cols + 1:
		var t := float(i) / cols
		var z := lerpf(-0.035, 0.155, t)
		# Arriba casi recto; abajo la barba cae hacia el filo.
		var top := 0.545 + 0.02 * t * t
		var bottom := 0.470 - 0.11 * pow(t, 2.2)
		# Grueso junto al ojo y casi cuchilla en el filo.
		var th := lerpf(0.012, 0.0014, smoothstep(0.2, 1.0, t))
		var ring := PackedVector3Array([
			Vector3(-th, bottom, z), Vector3(th, bottom, z), Vector3(th, top, z), Vector3(-th, top, z)])
		rings.append(ring)
	# El loft va a lo largo de Z: cada anillo es la sección XY de esa columna.
	ProcMesh.loft(iron, rings)
	# Ojo del hacha alrededor del astil y un pequeño martillo trasero.
	ProcMesh.box(iron, Vector3(0, 0.51, -0.005), Vector3(0.05, 0.085, 0.06))
	ProcMesh.box(iron, Vector3(0, 0.51, -0.05), Vector3(0.036, 0.05, 0.03))
	return b.commit(make_material)


static func mace() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	ProcMesh.lathe(b.st(DARK_WOOD), [Vector2(0.0, -0.17), Vector2(0.020, -0.17), Vector2(0.022, -0.15),
		Vector2(0.018, -0.08), Vector2(0.017, 0.40), Vector2(0.0, 0.41)], 10, Vector3.ZERO, 1.0, 1.5)
	wrapped_grip(b.st(LEATHER), -0.13, 0.09, 0.0195, 9)
	var iron := b.st(IRON)
	# Collar y núcleo de la cabeza.
	ProcMesh.lathe(iron, [Vector2(0.024, 0.34), Vector2(0.028, 0.36), Vector2(0.034, 0.39), Vector2(0.040, 0.43),
		Vector2(0.042, 0.47), Vector2(0.036, 0.51), Vector2(0.020, 0.535), Vector2(0.0, 0.54)], 12)
	ProcMesh.set_flat(iron, true)
	# Seis pestañas: trapecios gruesos radiales, con el borde exterior en punta roma.
	for k in 6:
		var a := TAU * k / 6.0
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a))
		var th := 0.006
		var inner_lo := Vector3(0, 0.375, 0) + dir * 0.030
		var inner_hi := Vector3(0, 0.515, 0) + dir * 0.030
		var outer_lo := Vector3(0, 0.392, 0) + dir * 0.078
		var outer_hi := Vector3(0, 0.500, 0) + dir * 0.082
		var ring_a := PackedVector3Array([inner_lo - side * th, outer_lo - side * th * 0.4,
			outer_hi - side * th * 0.4, inner_hi - side * th])
		var ring_b := PackedVector3Array([inner_lo + side * th, outer_lo + side * th * 0.4,
			outer_hi + side * th * 0.4, inner_hi + side * th])
		ProcMesh.loft(iron, [ring_a, ring_b])
	ProcMesh.set_flat(iron, false)
	# Remate.
	ProcMesh.lathe(iron, [Vector2(0.0, 0.53), Vector2(0.014, 0.535), Vector2(0.010, 0.56), Vector2(0.0, 0.575)], 8)
	ProcMesh.lathe(iron, [Vector2(0.0, -0.19), Vector2(0.021, -0.185), Vector2(0.024, -0.170), Vector2(0.019, -0.160)], 8)
	return b.commit(make_material)


## Espadón a dos manos: hoja larga y ancha, guarda recta, puño largo para las dos manos
## (la izquierda va 0,13 m por debajo de la derecha) y pomo de disco.
static func greatsword() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var steel := b.st(STEEL)
	ProcMesh.set_flat(steel, true)
	blade(steel, 0.135, 1.05, 0.064, 0.013, 0.13)
	var iron := b.st(IRON)
	ProcMesh.box(iron, Vector3(0, 0.112, 0), Vector3(0.032, 0.026, 0.30))
	# Remates de la guarda.
	for z in [-0.155, 0.155]:
		ProcMesh.box(iron, Vector3(0, 0.112, z), Vector3(0.036, 0.036, 0.02))
	ProcMesh.set_flat(iron, false)
	ProcMesh.lathe(iron, [Vector2(0.021, 0.086), Vector2(0.024, 0.094), Vector2(0.018, 0.100)], 8)
	# Pomo de disco.
	ProcMesh.lathe(iron, [Vector2(0.0, -0.335), Vector2(0.018, -0.332), Vector2(0.034, -0.318),
		Vector2(0.034, -0.300), Vector2(0.018, -0.288), Vector2(0.014, -0.280)], 12)
	wrapped_grip(b.st(LEATHER), -0.282, 0.088, 0.018, 16)
	return b.commit(make_material)


## Astil largo de las armas grandes a dos manos, de [y0] a [y1], con vendas donde van las manos.
static func _long_haft(b: ProcMesh.Builder, y0: float, y1: float, radius: float) -> void:
	ProcMesh.lathe(b.st(WOOD), [Vector2(0.0, y0), Vector2(radius * 1.05, y0), Vector2(radius * 1.12, y0 + 0.03),
		Vector2(radius, y0 + 0.12), Vector2(radius * 0.95, y1 - 0.05), Vector2(0.0, y1)], 10, Vector3.ZERO, 1.0, 1.0)
	wrapped_grip(b.st(LEATHER), -0.34, 0.08, radius * 1.1, 14)
	# Regatón de hierro al pie.
	ProcMesh.lathe(b.st(IRON), [Vector2(0.0, y0 - 0.03), Vector2(radius * 1.2, y0 - 0.02), Vector2(radius * 1.2, y0 + 0.02),
		Vector2(radius * 1.05, y0 + 0.03)], 8)


## Hacha grande a dos manos: la cabeza del hacha de guerra, mayor, al final de un astil largo.
static func great_axe() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	_long_haft(b, -0.40, 0.99, 0.021)
	var iron := b.st(IRON)
	ProcMesh.set_flat(iron, true)
	var cols := 14
	var rings := []
	for i in cols + 1:
		var t := float(i) / cols
		var z := lerpf(-0.045, 0.235, t)
		var top := 0.955 + 0.05 * t * t
		var bottom := 0.835 - 0.19 * pow(t, 2.0)
		var th := lerpf(0.016, 0.0016, smoothstep(0.2, 1.0, t))
		rings.append(PackedVector3Array([
			Vector3(-th, bottom, z), Vector3(th, bottom, z), Vector3(th, top, z), Vector3(-th, top, z)]))
	ProcMesh.loft(iron, rings)
	ProcMesh.box(iron, Vector3(0, 0.90, -0.005), Vector3(0.058, 0.12, 0.07))
	# Pico trasero.
	ProcMesh.loft(iron, [
		PackedVector3Array([Vector3(-0.014, 0.87, -0.04), Vector3(0.014, 0.87, -0.04), Vector3(0.014, 0.93, -0.04), Vector3(-0.014, 0.93, -0.04)]),
		PackedVector3Array([Vector3(-0.003, 0.885, -0.13), Vector3(0.003, 0.885, -0.13), Vector3(0.003, 0.895, -0.13), Vector3(-0.003, 0.895, -0.13)]),
	])
	return b.commit(make_material)


## Martillo de guerra a dos manos: mazo de hierro con la cara hacia el filo (+Z) y un pico
## detrás, sobre un astil largo con barras de hierro bajo la cabeza.
static func war_hammer() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	_long_haft(b, -0.40, 0.98, 0.022)
	var iron := b.st(IRON)
	ProcMesh.set_flat(iron, true)
	# Mazo: prisma de sección octogonal a lo largo de Z.
	var faces := []
	for z in [-0.02, 0.10, 0.125]:
		var r := 0.058 if z < 0.12 else 0.050
		var ring := PackedVector3Array()
		for k in 8:
			var a := TAU * (k + 0.5) / 8.0
			ring.append(Vector3(cos(a) * r, 0.90 + sin(a) * r, z))
		faces.append(ring)
	ProcMesh.loft(iron, faces)
	# Pico trasero, curvado hacia abajo.
	ProcMesh.loft(iron, [
		PackedVector3Array([Vector3(-0.022, 0.87, -0.02), Vector3(0.022, 0.87, -0.02), Vector3(0.022, 0.93, -0.02), Vector3(-0.022, 0.93, -0.02)]),
		PackedVector3Array([Vector3(-0.012, 0.875, -0.10), Vector3(0.012, 0.875, -0.10), Vector3(0.012, 0.905, -0.10), Vector3(-0.012, 0.905, -0.10)]),
		PackedVector3Array([Vector3(-0.002, 0.855, -0.17), Vector3(0.002, 0.855, -0.17), Vector3(0.002, 0.862, -0.17), Vector3(-0.002, 0.862, -0.17)]),
	])
	# Barras de refuerzo bajo la cabeza y remate.
	for side in [-1.0, 1.0]:
		ProcMesh.box(iron, Vector3(side * 0.024, 0.78, 0), Vector3(0.006, 0.18, 0.02))
	ProcMesh.set_flat(iron, false)
	ProcMesh.lathe(iron, [Vector2(0.0, 0.955), Vector2(0.016, 0.96), Vector2(0.010, 0.99), Vector2(0.0, 1.01)], 8)
	return b.commit(make_material)


# ---------------------------------------------------------------------------------------------
# Escudos: origen en el centro de la cara de atrás (donde va el antebrazo), +Z hacia fuera (la cara
# que para los golpes) y +Y hacia el canto de arriba. CombatPose los pone sobre el antebrazo.


## Anillo en el plano XY a la altura [z], en el sentido de las agujas del reloj visto desde
## delante (+Z): así loft deja las caras hacia fuera y la tapa final hacia delante.
static func _circle(radius: float, z: float, segments: int) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for i in segments:
		var a := -TAU * float(i) / float(segments)
		ring.append(Vector3(cos(a) * radius, sin(a) * radius, z))
	return ring


## Escudo de hierro: rodela de tablas encoladas algo abombadas, umbo de hierro y canto de cuero.
## Ø 0,62 m.
static func round_shield() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var r := 0.31
	var t := 0.014
	var wood := b.st(WOOD)
	ProcMesh.loft(wood, [_circle(r, 0.0, 32), _circle(r, t, 32), _circle(r * 0.7, t + 0.008, 32),
		_circle(0.09, t + 0.012, 32)], true, false)
	var iron := b.st(IRON)
	ProcMesh.loft(iron, [_circle(0.092, t + 0.010, 20), _circle(0.085, t + 0.03, 20), _circle(0.065, t + 0.05, 20),
		_circle(0.03, t + 0.06, 20)], false, true)
	ProcMesh.loft(b.st(LEATHER), [_circle(r - 0.006, -0.004, 32), _circle(r + 0.006, -0.002, 32),
		_circle(r + 0.006, t + 0.002, 32), _circle(r - 0.006, t + 0.006, 32)], false, false)
	# Asa por detrás, de lado a lado del umbo.
	ProcMesh.box(b.st(DARK_WOOD), Vector3(0.0, 0.0, -0.016), Vector3(0.22, 0.03, 0.024), Basis(Vector3.BACK, PI * 0.5))
	return b.commit(make_material)



## Escudo de madera: cuatro tablas planas cortadas en redondo y atadas por detrás a dos travesaños,
## con un asidero de madera. Nada de metal. Ø 0,54 m.
static func plank_shield() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var r := 0.27
	var t := 0.018
	var planks := 4
	var gap := 0.004
	var width := 2.0 * r / planks
	var wood := b.st(WOOD)
	ProcMesh.set_flat(wood, true)
	for i in planks:
		var x0 := -r + width * i + gap * 0.5
		var x1 := x0 + width - gap
		# Cada tabla de un grueso: se nota que son tablas sueltas.
		var front := t + 0.003 * float((i * 7) % 3 - 1)
		ProcMesh.loft(wood, [_plank_ring(r, x0, x1, 0.0), _plank_ring(r, x0, x1, front)])
	var back := b.st(DARK_WOOD)
	for y: float in [-0.12, 0.12]:
		var half := sqrt(r * r - y * y) - 0.03
		ProcMesh.box(back, Vector3(0.0, y, -0.008), Vector3(half * 2.0, 0.05, 0.016))
	ProcMesh.box(back, Vector3(0.0, 0.0, -0.016), Vector3(0.2, 0.03, 0.022), Basis(Vector3.BACK, PI * 0.5))
	return b.commit(make_material)


## Contorno de la tabla que va de [x0] a [x1] en un redondo de radio [r], a la altura [z]: el arco de
## arriba de izquierda a derecha y el de abajo de vuelta, en el sentido de _circle.
static func _plank_ring(r: float, x0: float, x1: float, z: float, steps: int = 6) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for k in steps + 1:
		var x := lerpf(x0, x1, float(k) / steps)
		ring.append(Vector3(x, sqrt(maxf(r * r - x * x, 0.0)), z))
	for k in steps + 1:
		var x := lerpf(x1, x0, float(k) / steps)
		ring.append(Vector3(x, -sqrt(maxf(r * r - x * x, 0.0)), z))
	return ring

## Contorno de un escudo heráldico (canto de arriba recto, lados que bajan curvos hasta la punta),
## combado hacia atrás por los lados para abrazar el cuerpo. [grow] lo agranda (el canto).
static func _heater_ring(z: float, grow: float) -> PackedVector3Array:
	var w := 0.27 + grow
	var top := 0.30 + grow
	var tip := 0.42 + grow
	var points := PackedVector3Array()
	# Como _circle, en el sentido de las agujas del reloj visto desde delante: arriba de izquierda
	# a derecha, y luego por la derecha hasta la punta y de vuelta por la izquierda.
	for i in 6:
		points.append(Vector3(w - 2.0 * w * float(i) / 6.0, top, 0.0))
	for i in 10:
		var u := float(i) / 10.0
		points.append(Vector3(-w * sqrt(maxf(0.0, 1.0 - pow(u, 2.2))), top - (top + tip) * u, 0.0))
	for i in 10:
		var u := 1.0 - float(i) / 10.0
		points.append(Vector3(w * sqrt(maxf(0.0, 1.0 - pow(u, 2.2))), top - (top + tip) * u, 0.0))
	points.reverse()
	for i in points.size():
		var p := points[i]
		points[i] = Vector3(p.x, p.y, z - 0.05 * pow(p.x / 0.27, 2.0))
	return points


## Escudo de roble con canto de hierro: heráldico, 0,54 × 0,72 m, con un refuerzo de hierro de
## arriba abajo y umbo pequeño.
static func heater_shield() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var t := 0.018
	ProcMesh.loft(b.st(DARK_WOOD), [_heater_ring(0.0, 0.0), _heater_ring(t, 0.0)])
	var iron := b.st(IRON)
	ProcMesh.loft(iron, [_heater_ring(-0.004, -0.008), _heater_ring(-0.002, 0.008), _heater_ring(t + 0.002, 0.008),
		_heater_ring(t + 0.006, -0.008)], false, false)
	ProcMesh.box(iron, Vector3(0.0, -0.06, t + 0.003), Vector3(0.045, 0.62, 0.006))
	ProcMesh.loft(iron, [_circle(0.07, t + 0.004, 18), _circle(0.06, t + 0.022, 18), _circle(0.03, t + 0.034, 18)], false, true)
	ProcMesh.box(b.st(LEATHER), Vector3(0.0, 0.0, -0.016), Vector3(0.24, 0.035, 0.02), Basis(Vector3.BACK, PI * 0.5))
	return b.commit(make_material)


static func spear() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	ProcMesh.lathe(b.st(WOOD), [Vector2(0.0, -0.92), Vector2(0.014, -0.92), Vector2(0.016, -0.88),
		Vector2(0.017, 0.0), Vector2(0.0155, 0.90), Vector2(0.0, 0.905)], 8, Vector3.ZERO, 1.0, 0.8)
	wrapped_grip(b.st(LEATHER), -0.10, 0.12, 0.0185, 8)
	# Ataduras de cuerda bajo la moharra.
	wrapped_grip(b.st(CORD), 0.83, 0.90, 0.0175, 6)
	var steel := b.st(STEEL)
	ProcMesh.lathe(steel, [Vector2(0.017, 0.88), Vector2(0.020, 0.93), Vector2(0.013, 0.965)], 8)
	ProcMesh.set_flat(steel, true)
	blade(steel, 0.955, 0.21, 0.066, 0.014, 0.08)
	# Regatón.
	ProcMesh.lathe(b.st(IRON), [Vector2(0.0, -0.965), Vector2(0.010, -0.94), Vector2(0.0155, -0.905)], 8)
	return b.commit(make_material)



# ---------------------------------------------------------------------------------------------
# Edad de piedra: sin metal, madera, sílex y ataduras de piel.


## Espada de sílex: una pala de madera dura con lascas de sílex encajadas a lo largo de los dos
## filos (como el macuahuitl), puño forrado de piel y pomo de madera. Con [flakes] = OBSIDIAN, la
## de obsidiana.
static func flint_sword(flakes: StringName = FLINT) -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var wood := b.st(DARK_WOOD)
	ProcMesh.set_flat(wood, true)
	var y0 := 0.07
	var length := 0.72
	var thick := 0.0095
	var rings := []
	var steps := 16
	for i in steps + 1:
		var t := float(i) / steps
		var y := y0 + length * t
		# Se ensancha hacia arriba y acaba redonda.
		var w := lerpf(0.034, 0.043, t) * (sqrt(maxf(1.0 - pow((t - 0.86) / 0.14, 2.0), 0.0)) if t > 0.86 else 1.0)
		w = maxf(w, 0.006)
		rings.append(PackedVector3Array([Vector3(0, y, w), Vector3(thick, y, w * 0.75), Vector3(thick, y, -w * 0.75),
			Vector3(0, y, -w), Vector3(-thick, y, -w * 0.75), Vector3(-thick, y, w * 0.75)]))
	ProcMesh.loft(wood, rings, true, true)
	# Lascas: dos hileras, una por filo, de donde acaba el puño a casi la punta.
	var flint := b.st(flakes)
	ProcMesh.set_flat(flint, true)
	var count := 10
	for side: float in [1.0, -1.0]:
		for i in count:
			var t := (float(i) + 0.5) / count * 0.84
			var y := y0 + 0.05 + (length - 0.08) * t
			var w := lerpf(0.034, 0.043, (y - y0) / length)
			var size := 0.85 + 0.3 * absf(sin(float(i) * 2.3 + side))
			_flint_point(flint, Vector3(0, y, side * (w - 0.004)), Vector3(0, 0, side), Vector3.UP,
				0.022 * size, 0.0045, 0.022 * size)
	# Puño y pomo.
	ProcMesh.lathe(b.st(WOOD), [Vector2(0.0, -0.165), Vector2(0.02, -0.16), Vector2(0.027, -0.145), Vector2(0.024, -0.128),
		Vector2(0.015, -0.12), Vector2(0.014, y0 + 0.01)], 8)
	wrapped_grip(b.st(LEATHER), -0.118, y0 + 0.005, 0.0165, 9)
	return b.commit(make_material)


## Lanza de sílex: asta de madera con una punta de sílex tallada en hoja de laurel y atada con
## tiras de piel. Se arroja como la de hierro.
static func flint_spear() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	ProcMesh.lathe(b.st(WOOD), [Vector2(0.0, -0.93), Vector2(0.013, -0.925), Vector2(0.016, -0.89),
		Vector2(0.017, 0.0), Vector2(0.0155, 0.88), Vector2(0.0, 0.90)], 8, Vector3.ZERO, 1.0, 0.8)
	wrapped_grip(b.st(LEATHER), -0.10, 0.12, 0.0185, 8)
	wrapped_grip(b.st(CORD), 0.79, 0.90, 0.021, 7)
	var flint := b.st(FLINT)
	ProcMesh.set_flat(flint, true)
	blade(flint, 0.86, 0.18, 0.074, 0.02, 0.055, false)
	return b.commit(make_material)


## Cuchillo de sílex: una hoja de sílex tallada, de un filo, encajada en un mango de madera atado con
## tendón. Despelleja como el seax.
static func flint_knife() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	ProcMesh.lathe(b.st(WOOD), [Vector2(0.0, -0.085), Vector2(0.014, -0.08), Vector2(0.017, -0.06),
		Vector2(0.015, 0.03), Vector2(0.017, 0.055), Vector2(0.0, 0.06)], 8)
	wrapped_grip(b.st(CORD), 0.02, 0.06, 0.0175, 6)
	var flint := b.st(FLINT)
	ProcMesh.set_flat(flint, true)
	blade(flint, 0.05, 0.13, 0.036, 0.009, 0.03, false)
	return b.commit(make_material)


## Puñal de hueso: la caña de un hueso largo afilada en punta, con la cabeza del hueso de pomo y el
## puño atado con tendón. Pica entre las placas.
static func bone_dagger() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var bone := b.st(BONE)
	var points := PackedVector3Array()
	var radii := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		points.append(Vector3(0.0, lerpf(-0.06, 0.26, t), 0.004 * sin(t * PI)))
		var r := lerpf(0.016, 0.0015, pow(t, 1.4))
		radii.append(Vector2(r, r * 0.7))
	ProcMesh.tube(bone, points, radii, 7)
	# La cabeza del hueso: dos cóndilos de pomo.
	for side in [-1.0, 1.0]:
		ProcMesh.lathe(bone, [Vector2(0.0, -0.016), Vector2(0.014, -0.01), Vector2(0.017, 0.0), Vector2(0.012, 0.012),
			Vector2(0.0, 0.016)], 8, Vector3(side * 0.01, -0.075, 0.0))
	wrapped_grip(b.st(CORD), -0.055, 0.05, 0.0165, 8)
	return b.commit(make_material)


## Herramientas de piedra: mismo agarre, materiales y escala que las armas primitivas. La
## cabeza queda entre 0,40 y 0,62 m sobre el puño, dentro de su tramo de golpe en ItemData.
static func stone_axe() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	_stone_tool_haft(b)
	# Cuña tallada: gruesa en el enmangue y abierta hacia un filo ancho, casi sin espesor.
	_stone_tool_head(b.st(STONE), [
		Vector4(-0.080, 0.520, 0.040, 0.012), Vector4(-0.055, 0.525, 0.060, 0.030),
		Vector4(0.005, 0.530, 0.066, 0.039), Vector4(0.070, 0.520, 0.086, 0.030),
		Vector4(0.145, 0.505, 0.105, 0.016), Vector4(0.205, 0.500, 0.098, 0.0015),
	])
	_stone_tool_binding(b)
	return b.commit(make_material, true)


## Pico lítico: piedra alargada de dos puntas, curvada hacia el golpe y atada al astil.
static func stone_pickaxe() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	_stone_tool_haft(b)
	_stone_tool_head(b.st(STONE), [
		Vector4(-0.200, 0.465, 0.0015, 0.0015), Vector4(-0.150, 0.505, 0.018, 0.012),
		Vector4(-0.080, 0.535, 0.031, 0.024), Vector4(0.000, 0.545, 0.045, 0.037),
		Vector4(0.065, 0.540, 0.036, 0.030), Vector4(0.140, 0.510, 0.021, 0.016),
		Vector4(0.240, 0.455, 0.0015, 0.0015),
	])
	_stone_tool_binding(b, 0.586, 0.542)
	return b.commit(make_material, true)


static func _stone_tool_haft(b: ProcMesh.Builder) -> void:
	ProcMesh.lathe(b.st(WOOD), [Vector2(0.0, -0.17), Vector2(0.019, -0.165),
		Vector2(0.022, -0.14), Vector2(0.0175, 0.0), Vector2(0.019, 0.30),
		Vector2(0.023, 0.48), Vector2(0.021, 0.585), Vector2(0.0, 0.595)],
		9, Vector3.ZERO, 1.0, 1.5)
	wrapped_grip(b.st(LEATHER), -0.12, 0.08, 0.019, 9)


## Secciones XY a lo largo de Z: (z, altura central, semialtura, semigrosor). Los hombros
## forman las facetas de talla y el perfil irregular rompe el aspecto de una hoja de metal.
static func _stone_tool_head(st: SurfaceTool, sections: Array) -> void:
	ProcMesh.set_flat(st, true)
	var rings := []
	for i in sections.size():
		var p: Vector4 = sections[i]
		var h := p.z
		var w := p.w
		var ridge := 0.08 * h * sin(float(i) * 2.3)
		rings.append(PackedVector3Array([
			Vector3(-w * 0.35, p.y - h, p.x), Vector3(w * 0.35, p.y - h, p.x),
			Vector3(w, p.y - h * 0.45 + ridge, p.x), Vector3(w * 0.92, p.y + h * 0.50 + ridge, p.x),
			Vector3(w * 0.30, p.y + h, p.x), Vector3(-w * 0.30, p.y + h, p.x),
			Vector3(-w * 0.95, p.y + h * 0.42 - ridge, p.x), Vector3(-w, p.y - h * 0.52 - ridge, p.x),
		]))
	ProcMesh.loft(st, rings)


static func _stone_tool_binding(b: ProcMesh.Builder, top: float = 0.600, middle: float = 0.530) -> void:
	var cord := b.st(CORD)
	wrapped_grip(cord, 0.405, 0.475, 0.024, 8)
	# Dos lazadas diagonales abrazan la piedra y vuelven bajo el enmangue.
	for side in [-1.0, 1.0]:
		var points := PackedVector3Array([
			Vector3(-0.022, 0.465, -side * 0.016),
			Vector3(-0.039, middle - 0.030, -side * 0.012),
			Vector3(-0.037, middle + 0.025, side * 0.012),
			Vector3(-0.012, top, side * 0.025), Vector3(0.012, top, side * 0.025),
			Vector3(0.037, middle + 0.025, side * 0.012),
			Vector3(0.039, middle - 0.030, -side * 0.012),
			Vector3(0.022, 0.465, -side * 0.016),
		])
		points.append(points[0])
		var radii := PackedVector2Array()
		for k in points.size():
			radii.append(Vector2(0.0035, 0.0035))
		ProcMesh.tube(cord, points, radii, 5, Vector3.BACK, false)


## Maza de piedra: un canto rodado atado en la punta de un mango de madera, con tendón cruzado sobre
## la piedra y vueltas por debajo. Contundente.
static func stone_club() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	ProcMesh.lathe(b.st(WOOD), [Vector2(0.0, -0.17), Vector2(0.019, -0.17), Vector2(0.021, -0.15),
		Vector2(0.018, 0.0), Vector2(0.02, 0.44), Vector2(0.0, 0.46)], 9, Vector3.ZERO, 1.0, 1.5)
	wrapped_grip(b.st(LEATHER), -0.13, 0.08, 0.0195, 9)
	lump(b.st(STONE), Vector3(0.0, 0.5, 0.0), 0.072, 307, 0.95, 0.16, Basis.from_scale(Vector3(1.0, 1.0, 1.3)))
	var cord := b.st(CORD)
	wrapped_grip(cord, 0.37, 0.45, 0.022, 7)
	for a in [0.0, PI * 0.5]:
		var side := Vector3(cos(a), 0.0, sin(a))
		var strap := PackedVector3Array()
		var radii := PackedVector2Array()
		for k in 9:
			var u := lerpf(-PI * 0.42, PI * 0.42, float(k) / 8.0)
			strap.append(Vector3(0.0, 0.5, 0.0) + side * sin(u) * 0.08 + Vector3.UP * cos(u) * 0.075)
			radii.append(Vector2(0.004, 0.004))
		ProcMesh.tube(cord, strap, radii, 5)
	return b.commit(make_material)


## Mazo de piedra a dos manos: una piedra grande, alargada y atada en cruz a la punta de un astil
## largo. Lento, pero lo que alcanza cae.
static func stone_maul() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	_long_haft(b, -0.40, 0.96, 0.022)
	lump(b.st(STONE), Vector3(0.0, 0.92, 0.0), 0.1, 311, 0.85, 0.14, Basis.from_scale(Vector3(0.95, 1.0, 1.6)))
	var cord := b.st(CORD)
	wrapped_grip(cord, 0.78, 0.87, 0.025, 8)
	for x in [-0.03, 0.03]:
		var strap := PackedVector3Array()
		var radii := PackedVector2Array()
		for k in 9:
			var u := lerpf(-PI * 0.45, PI * 0.45, float(k) / 8.0)
			strap.append(Vector3(x, 0.92 + cos(u) * 0.09, sin(u) * 0.16))
			radii.append(Vector2(0.0045, 0.0045))
		ProcMesh.tube(cord, strap, radii, 5)
	return b.commit(make_material)


## Escudo de piel: un aro de varas con piel cruda tensada encima, cosida al aro con tendón, algo
## abombado. Ligero; para poco, pero deja hacer paradas rápidas. Ø 0,56 m.
static func hide_shield() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var r := 0.28
	ProcMesh.loft(b.st(RAWHIDE), [_circle(r, 0.0, 28), _circle(r * 0.8, 0.025, 28), _circle(r * 0.45, 0.04, 28),
		_circle(0.02, 0.045, 28)], true, true)
	var rim := b.st(WOOD)
	var hoop := PackedVector3Array()
	var radii := PackedVector2Array()
	for k in 33:
		var a := -TAU * k / 32.0
		hoop.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
		radii.append(Vector2(0.011, 0.011))
	ProcMesh.tube(rim, hoop, radii, 6, Vector3.BACK, false)
	# Puntadas de tendón sobre el aro.
	var cord := b.st(CORD)
	for k in 16:
		var a := TAU * (k + 0.5) / 16.0
		var dir := Vector3(cos(a), sin(a), 0.0)
		ProcMesh.tube(cord, PackedVector3Array([dir * (r - 0.02) + Vector3(0, 0, 0.012), dir * (r + 0.012),
			dir * (r - 0.02) - Vector3(0, 0, 0.012)]),
			PackedVector2Array([Vector2(0.003, 0.003), Vector2(0.003, 0.003), Vector2(0.003, 0.003)]), 4)
	ProcMesh.box(b.st(DARK_WOOD), Vector3(0.0, 0.0, -0.016), Vector3(0.2, 0.028, 0.022), Basis(Vector3.BACK, PI * 0.5))
	return b.commit(make_material)


## Escudo de placas de hueso: una tabla forrada de piel con hileras de placas de hueso cosidas que se
## montan unas sobre otras, como el del guerrero de Yakutia de final de la Edad de piedra. 0,44 ×
## 0,62 m.
static func bone_shield() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var w := 0.22
	var h := 0.31
	var t := 0.016
	var board := PackedVector3Array()
	for k in 24:
		var a := -TAU * k / 24.0
		# Un rectángulo de esquinas redondas (superelipse).
		var c := cos(a)
		var sn := sin(a)
		board.append(Vector3(signf(c) * pow(absf(c), 0.45) * w, signf(sn) * pow(absf(sn), 0.45) * h, 0.0))
	var front := PackedVector3Array()
	for p in board:
		front.append(p + Vector3(0, 0, t))
	ProcMesh.loft(b.st(LEATHER), [board, front])
	var bone := b.st(BONE)
	ProcMesh.set_flat(bone, true)
	var rows := 8
	var cols := 6
	for row in rows:
		for col in cols:
			var x := lerpf(-w + 0.035, w - 0.035, (float(col) + 0.5 * (row % 2)) / (cols - 0.5))
			var y := lerpf(h - 0.04, -h + 0.04, float(row) / (rows - 1))
			if absf(x) > w - 0.03:
				continue
			# Cada fila monta sobre la de debajo: algo más adelantada e inclinada.
			var tilt := Basis(Vector3.RIGHT, -0.12) * Basis(Vector3.BACK, sin(float(row * 7 + col) * 1.7) * 0.06)
			ProcMesh.box(bone, Vector3(x, y, t + 0.004 + 0.002 * (rows - row) * 0.25), Vector3(0.062, 0.07, 0.006), tilt)
	ProcMesh.set_flat(bone, false)
	# Las costuras de cada hilera.
	var cord := b.st(CORD)
	for row in rows:
		var y := lerpf(h - 0.04, -h + 0.04, float(row) / (rows - 1)) + 0.03
		ProcMesh.box(cord, Vector3(0.0, y, t + 0.009), Vector3(w * 1.8, 0.004, 0.003))
	ProcMesh.box(b.st(DARK_WOOD), Vector3(0.0, 0.0, -0.016), Vector3(0.22, 0.03, 0.022), Basis(Vector3.BACK, PI * 0.5))
	return b.commit(make_material)


## Lasca de sílex: una pirámide de cuatro caras clavada en [base] que asoma [height] hacia
## [outward], con [half_length] a lo largo de [along] y [half_thick] de grueso.
static func _flint_point(st: SurfaceTool, base: Vector3, outward: Vector3, along: Vector3,
		half_length: float, half_thick: float, height: float) -> void:
	# Como la punta de la flecha (su anillo va de +X a +Z y la punta, en +Y): X = along, Y = outward.
	var side := along.cross(outward)
	var ring := [base + along * half_length, base + side * half_thick, base - along * half_length,
		base - side * half_thick]
	var tip := base + outward * height
	var neck := base - outward * 0.004
	for j in 4:
		var k := (j + 1) % 4
		ProcMesh.tri(st, ring[j], ring[k], tip)
		ProcMesh.tri(st, ring[k], ring[j], neck)

## Curva de las palas del arco: z (hacia el blanco) según y. Las puntas vuelven hacia delante
## (recurvo). [draw] 0..1 dobla más las palas al tensar.
static func bow_limb_z(y: float, half: float, draw: float = 0.0) -> float:
	var t := absf(y) / half
	var bend := -(0.15 + 0.15 * draw) * t * t
	var recurve := 0.055 * pow(maxf(t - 0.78, 0.0) / 0.22, 2.0)
	return bend + recurve


const BOW_HALF := 0.68


## Punta de la pala (donde engancha la cuerda). [draw] 0..1: al tensar, las puntas vienen
## hacia el arquero y se acercan entre sí (las palas giran, no se estiran).
static func bow_tip(top: bool, draw: float = 0.0) -> Vector3:
	var y := BOW_HALF if top else -BOW_HALF
	var z := bow_limb_z(y, BOW_HALF, draw)
	var rest_z := bow_limb_z(y, BOW_HALF)
	return Vector3(0, y * (1.0 - 0.5 * (z - rest_z) * (z - rest_z) / (BOW_HALF * BOW_HALF)), z)


## Arco con una forma de mezcla "drawn" (palas dobladas a tope): el visual la mueve con la
## tensión. Misma topología en las dos formas.
static func bow_flexing() -> ArrayMesh:
	var rest := bow(0.0)
	var drawn := bow(1.0)
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	mesh.add_blend_shape(&"drawn")
	for i in rest.get_surface_count():
		var arrays := rest.surface_get_arrays(i)
		var target := drawn.surface_get_arrays(i)
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = target[Mesh.ARRAY_VERTEX]
		shape[Mesh.ARRAY_NORMAL] = target[Mesh.ARRAY_NORMAL]
		shape[Mesh.ARRAY_TANGENT] = target[Mesh.ARRAY_TANGENT]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [shape])
		mesh.surface_set_material(i, rest.surface_get_material(i))
	return mesh


static func bow(draw: float = 0.0) -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var wood := b.st(DARK_WOOD)
	for sign in [1.0, -1.0]:
		var points := PackedVector3Array()
		var radii := PackedVector2Array()
		var steps := 16
		for i in steps + 1:
			var t := float(i) / steps
			var y: float = sign * lerpf(0.05, BOW_HALF, t)
			var z := bow_limb_z(y, BOW_HALF, draw)
			var rest_z := bow_limb_z(y, BOW_HALF)
			points.append(Vector3(0, y * (1.0 - 0.5 * (z - rest_z) * (z - rest_z) / (BOW_HALF * BOW_HALF)), z))
			# Pala ancha en X y fina en Z; se afina hacia la punta.
			radii.append(Vector2(lerpf(0.020, 0.007, t), lerpf(0.011, 0.005, t)))
		ProcMesh.tube(wood, points, radii, 8, Vector3.RIGHT)
	# Puño y ventana de flecha.
	ProcMesh.lathe(b.st(LEATHER), [Vector2(0.0, -0.075), Vector2(0.019, -0.07), Vector2(0.021, -0.05),
		Vector2(0.021, 0.05), Vector2(0.019, 0.07), Vector2(0.0, 0.075)], 10, Vector3(0, 0, 0.004), 1.0, 12.0)
	for sign in [1.0, -1.0]:
		var tip := bow_tip(sign > 0.0, draw)
		ProcMesh.lathe(b.st(CORD), [Vector2(0.0, -0.012), Vector2(0.009, -0.008), Vector2(0.009, 0.008),
			Vector2(0.0, 0.012)], 6, tip)
	return b.commit(make_material)


## Aljaba de cuero: boca en el origen, el fondo hacia -Y (ArcheryPose.QUIVER_LENGTH).
static func quiver() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var h := ArcheryPose.QUIVER_LENGTH
	# Tubo algo más ancho arriba, con el borde vuelto hacia dentro para que se vea el hueco.
	ProcMesh.lathe(b.st(LEATHER), [Vector2(0.0, -h), Vector2(0.036, -h + 0.004), Vector2(0.042, -h + 0.03),
		Vector2(0.046, -0.3), Vector2(0.052, -0.03), Vector2(0.056, -0.012), Vector2(0.056, 0.0),
		Vector2(0.049, 0.004), Vector2(0.046, -0.02), Vector2(0.044, -0.08), Vector2(0.0, -0.08)], 14, Vector3.ZERO, 1.0, 3.0)
	# Refuerzos y la correa que cruza el pecho sale de las dos argollas.
	for y in [-0.05, -h * 0.55, -h + 0.05]:
		ProcMesh.lathe(b.st(CORD), [Vector2(0.0, y - 0.018), Vector2(0.050 if y > -0.3 else 0.047, y - 0.016),
			Vector2(0.051 if y > -0.3 else 0.048, y + 0.016), Vector2(0.0, y + 0.018)], 14)
	return b.commit(make_material)


## Puntas de las horquillas del tirachinas (donde se ata la goma).
const SLING_PRONG_TIPS := [Vector3(-0.045, 0.125, 0.0), Vector3(0.045, 0.125, 0.0)]


static func slingshot() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var wood := b.st(WOOD)
	ProcMesh.lathe(wood, [Vector2(0.0, -0.105), Vector2(0.015, -0.10), Vector2(0.016, -0.06),
		Vector2(0.015, 0.0), Vector2(0.017, 0.03), Vector2(0.0, 0.05)], 10, Vector3.ZERO, 1.0, 2.0)
	for tip in SLING_PRONG_TIPS:
		var points := PackedVector3Array([Vector3(tip.x * 0.08, 0.01, 0), Vector3(tip.x * 0.5, 0.068, 0),
			Vector3(tip.x * 0.9, 0.105, 0), tip])
		var radii := PackedVector2Array([Vector2(0.012, 0.012), Vector2(0.0105, 0.0105),
			Vector2(0.0095, 0.0095), Vector2(0.009, 0.009)])
		ProcMesh.tube(wood, points, radii, 8, Vector3.FORWARD, false)
		ProcMesh.lathe(wood, [Vector2(0.009, -0.004), Vector2(0.0085, 0.0), Vector2(0.0, 0.004)], 8, tip)
	wrapped_grip(b.st(LEATHER), -0.09, -0.01, 0.0165, 6)
	for tip in SLING_PRONG_TIPS:
		ProcMesh.lathe(b.st(CORD), [Vector2(0.0, -0.012), Vector2(0.0105, -0.01), Vector2(0.0105, 0.004),
			Vector2(0.0, 0.006)], 6, tip - Vector3(0, 0.012, 0))
	return b.commit(make_material)


## Largo de la flecha: el origen es el centro, la punta en +Y.
const ARROW_LENGTH := 0.74


static func arrow() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var h := ARROW_LENGTH * 0.5
	ProcMesh.lathe(b.st(WOOD), [Vector2(0.0, -h), Vector2(0.0045, -h + 0.004), Vector2(0.0045, h - 0.045),
		Vector2(0.0, h - 0.04)], 6, Vector3.ZERO, 1.0, 1.0)
	# Punta de sílex de cuatro caras.
	var flint := b.st(FLINT)
	var tip := Vector3(0, h + 0.012, 0)
	var y0 := h - 0.05
	var ring := [Vector3(0.014, y0 + 0.012, 0), Vector3(0, y0 + 0.004, 0.004), Vector3(-0.014, y0 + 0.012, 0),
		Vector3(0, y0 + 0.004, -0.004)]
	var neck := Vector3(0, y0 - 0.004, 0)
	for j in 4:
		var k := (j + 1) % 4
		ProcMesh.tri(flint, ring[j], ring[k], tip)
		ProcMesh.tri(flint, ring[k], ring[j], neck)
	# Atadura de la punta.
	ProcMesh.lathe(b.st(CORD), [Vector2(0.005, y0 - 0.012), Vector2(0.0055, y0 - 0.006), Vector2(0.005, y0)], 6)
	# Tres plumas.
	var feather := b.st(FEATHER)
	for k in 3:
		var a := TAU * k / 3.0
		var d := Vector3(cos(a), 0, sin(a))
		var f0 := Vector3(0, -h + 0.03, 0) + d * 0.004
		var f1 := Vector3(0, -h + 0.16, 0) + d * 0.004
		var f2 := Vector3(0, -h + 0.07, 0) + d * 0.026
		var f3 := Vector3(0, -h + 0.035, 0) + d * 0.022
		ProcMesh.quad(feather, f0, f3, f2, f1)
	# Culatín.
	ProcMesh.lathe(b.st(CORD), [Vector2(0.0, -h - 0.012), Vector2(0.0055, -h - 0.01), Vector2(0.0055, -h + 0.01),
		Vector2(0.0045, -h + 0.012)], 6)
	return b.commit(_arrow_material)


static func _arrow_material(kind: StringName) -> Material:
	var mat := make_material(kind)
	if kind == FEATHER:
		mat.albedo_color = Color(0.78, 0.22, 0.14)
	return mat


static func pebble() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var st := b.st(STONE)
	var sphere := SphereMesh.new()
	sphere.radius = 0.028
	sphere.height = 0.05
	sphere.radial_segments = 10
	sphere.rings = 6
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 60.0
	for i in verts.size():
		var v := verts[i]
		var bump := 1.0 + 0.18 * noise.get_noise_3dv(v)
		ProcMesh.emit(st, uvs[i], Vector3(v.x * 1.15, v.y, v.z * 0.9) * bump)
	for i in indices:
		st.add_index(i)
	return b.commit(make_material)


## Rama caída: un palo torcido de corteza con un par de ramitas, para recoger del suelo. Se empuña
## por el origen, cerca del extremo grueso, y +Y va hacia la punta. [variant] cambia la forma y el
## largo (la 0 es la que se lleva en la mano).
static func branch(variant: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + variant * 104729
	var length := 1.3 if variant == 0 else rng.randf_range(0.95, 1.5)
	var b := ProcMesh.Builder.new()
	var bark := b.st(BARK)
	var points := PackedVector3Array()
	var radii := PackedVector2Array()
	var steps := 9
	var bend := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	for i in steps + 1:
		var t := float(i) / steps
		# Curva suave de un lado y nudos que tuercen un poco el palo.
		var wobble := bend * sin(t * PI) * 0.045 + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.008
		points.append(Vector3(0, -0.18 + length * t, 0) + wobble)
		var r := lerpf(0.026, 0.012, t) * rng.randf_range(0.92, 1.08)
		radii.append(Vector2(r, r * rng.randf_range(0.85, 1.0)))
	ProcMesh.tube(bark, points, radii, 8, Vector3.RIGHT, true)
	# Ramitas: salen hacia la punta, finas y cortas, alguna partida.
	for k in rng.randi_range(2, 3):
		var at := rng.randf_range(0.35, 0.85)
		var i := int(at * steps)
		var base := points[i]
		var around := rng.randf() * TAU
		var dir := (Vector3(cos(around), 0, sin(around)) * rng.randf_range(0.6, 1.0) + Vector3.UP * rng.randf_range(0.6, 1.1)).normalized()
		var twig_length := rng.randf_range(0.08, 0.26)
		var twig := PackedVector3Array([base, base + dir * twig_length * 0.5 + Vector3(0, 0.01, 0), base + dir * twig_length])
		var r0 := radii[i].x * 0.45
		ProcMesh.tube(bark, twig, PackedVector2Array([Vector2(r0, r0), Vector2(r0 * 0.7, r0 * 0.7), Vector2(r0 * 0.4, r0 * 0.4)]), 5, Vector3.RIGHT, true)
	return b.commit(make_material)



## La rama tirada en el suelo (objeto del planeta): tumbada, con el palo a lo largo de -Z, centrada
## en el origen y con lo más bajo un centímetro por debajo de y = 0.
static func lying_branch(variant: int) -> ArrayMesh:
	var source := branch(variant)
	var length := source.get_aabb().size.y
	var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, length * 0.5 - 0.18))
	xf.origin.y = -(xf * source.get_aabb()).position.y - 0.01
	var mesh := ArrayMesh.new()
	for surface in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, surface, xf)
		st.set_material(source.surface_get_material(surface))
		st.commit(mesh)
	return mesh

@tool
class_name SurvivalMeshes
extends RefCounted

## Mallas de los objetos de supervivencia (el seax, la carne, la piel, lo que dan los animales al
## despiezarlos (también las plumas de las aves), la fibra de los arbustos, el odre, la hoguera y el banco de trabajo; de los dos últimos solo sale el icono: en
## el mundo se ven con sus modelos),
## generadas por código con los ayudantes de WeaponMeshes y horneadas a recursos, con sus iconos,
## por tools/combat/bake_weapons.gd. Metros; las de mano, con el origen en el agarre y +Y hacia la
## punta, como las armas.

const RAW_MEAT := &"raw_meat"
const COOKED_MEAT := &"cooked_meat"
const BONE := &"bone"
const HIDE := &"hide"
const ASH := &"ash"
const SINEW := &"sinew"
const ANTLER := &"antler"
const IVORY := &"ivory"
const HORN := &"horn"
const PLANT_FIBER := &"plant_fiber"
const PLUME := &"plume"
const HERB := &"herb"
const BLOSSOM := &"blossom"
const POULTICE := &"poultice"
# Menas (ore_chunk).
const CORTEX := &"cortex"
const OBSIDIAN := &"obsidian"
const MALACHITE := &"malachite"
const CASSITERITE := &"cassiterite"
const LIMONITE := &"limonite"
const HEMATITE := &"hematite"
const COAL := &"coal"
const GALENA := &"galena"
const GOLD := &"gold"
const SULFUR := &"sulfur"
const ORE_ROCK := &"ore_rock"


static func make_material(kind: StringName) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = String(kind)
	match kind:
		RAW_MEAT:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.45, 0.06, 0.07), Color(0.78, 0.30, 0.30), 5.0, 31)
			mat.roughness = 0.45
		COOKED_MEAT:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.20, 0.09, 0.04), Color(0.52, 0.28, 0.12), 5.0, 37)
			mat.roughness = 0.6
		BONE:
			mat.albedo_color = Color(0.86, 0.82, 0.72)
			mat.roughness = 0.7
		HIDE:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.30, 0.20, 0.12), Color(0.56, 0.42, 0.28), 3.0, 41)
			mat.roughness = 0.9
		ASH:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.05, 0.05, 0.05), Color(0.22, 0.21, 0.2), 4.0, 43)
			mat.roughness = 1.0
		SINEW:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.60, 0.48, 0.30), Color(0.86, 0.76, 0.56), 6.0, 47)
			mat.roughness = 0.5
		ANTLER:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.30, 0.22, 0.14), Color(0.62, 0.52, 0.38), 2.0, 53)
			mat.roughness = 0.8
		IVORY:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.78, 0.72, 0.58), Color(0.95, 0.91, 0.82), 1.5, 59)
			mat.roughness = 0.4
		HORN:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.10, 0.08, 0.07), Color(0.40, 0.34, 0.26), 1.2, 61)
			mat.roughness = 0.45
		PLANT_FIBER:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.36, 0.34, 0.18), Color(0.66, 0.60, 0.38), 3.0, 67)
			mat.roughness = 0.9
		PLUME:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.36, 0.30, 0.24), Color(0.74, 0.70, 0.62), 4.0, 71)
			mat.roughness = 0.85
		HERB:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.20, 0.32, 0.14), Color(0.42, 0.56, 0.28), 4.0, 73)
			mat.roughness = 0.8
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		BLOSSOM:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.80, 0.78, 0.70), Color(0.97, 0.96, 0.92), 8.0, 79)
			mat.roughness = 0.75
		POULTICE:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.14, 0.20, 0.08), Color(0.34, 0.40, 0.18), 7.0, 83)
			mat.roughness = 0.55
		CORTEX:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.62, 0.60, 0.54), Color(0.86, 0.84, 0.78), 8.0, 89)
			mat.roughness = 0.95
		OBSIDIAN:
			mat.albedo_color = Color(0.03, 0.03, 0.04)
			mat.roughness = 0.08
			mat.metallic_specular = 0.7
		MALACHITE:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.04, 0.26, 0.15), Color(0.2, 0.55, 0.36), 9.0, 97)
			mat.roughness = 0.5
		CASSITERITE:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.08, 0.05, 0.04), Color(0.26, 0.17, 0.11), 6.0, 101)
			mat.roughness = 0.3
			mat.metallic = 0.25
		LIMONITE:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.30, 0.14, 0.05), Color(0.70, 0.42, 0.16), 5.0, 103)
			mat.roughness = 0.95
		HEMATITE:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.22, 0.09, 0.08), Color(0.46, 0.28, 0.26), 5.0, 107)
			mat.roughness = 0.6
			mat.metallic = 0.3
		COAL:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.02, 0.02, 0.02), Color(0.10, 0.10, 0.11), 7.0, 109)
			mat.roughness = 0.45
		GALENA:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.34, 0.35, 0.38), Color(0.62, 0.64, 0.68), 4.0, 113)
			mat.roughness = 0.25
			mat.metallic = 0.85
		GOLD:
			mat.albedo_color = Color(0.95, 0.72, 0.28)
			mat.roughness = 0.3
			mat.metallic = 1.0
		SULFUR:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.78, 0.62, 0.08), Color(0.98, 0.9, 0.3), 9.0, 127)
			mat.roughness = 0.7
		ORE_ROCK:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.24, 0.22, 0.2), Color(0.46, 0.43, 0.39), 6.0, 131)
			mat.roughness = 0.9
		_:
			return WeaponMeshes.make_material(kind)
	return mat


## Seax: cuchillo de un filo con el lomo quebrado (recto y, cerca de la punta, en bajada hasta
## ella), virola de hierro y mango de madera. El filo mira a +Z.
static func seax() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var steel := b.st(WeaponMeshes.STEEL)
	ProcMesh.set_flat(steel, true)
	var y0 := 0.075
	var length := 0.205
	var rings := []
	var steps := 12
	for i in steps + 1:
		var t := float(i) / steps
		var y := y0 + length * t
		var edge := 0.023 - 0.005 * t
		# El lomo va recto hasta la quiebra y de ahí baja hasta el filo.
		var spine := -0.017 if t < 0.58 else lerpf(-0.017, edge - 0.003, (t - 0.58) / 0.42)
		var thick := 0.0042 * (1.0 - 0.55 * t)
		var mid := spine + (edge - spine) * 0.3
		rings.append(PackedVector3Array([Vector3(0, y, edge), Vector3(thick, y, mid), Vector3(0, y, spine),
			Vector3(-thick, y, mid)]))
	var last: PackedVector3Array = rings[rings.size() - 1]
	var tip := Vector3(0, y0 + length + 0.012, 0.012)
	for j in last.size():
		ProcMesh.tri(steel, last[j], last[(j + 1) % last.size()], tip)
	ProcMesh.loft(steel, rings, true, false)
	var iron := b.st(WeaponMeshes.IRON)
	ProcMesh.lathe(iron, [Vector2(0.0145, 0.058), Vector2(0.0165, 0.064), Vector2(0.0160, 0.074),
		Vector2(0.0120, 0.077)], 10)
	ProcMesh.lathe(iron, [Vector2(0.0, -0.112), Vector2(0.0125, -0.108), Vector2(0.0140, -0.100)], 10)
	var grip := []
	for i in 9:
		var t := float(i) / 8.0
		grip.append(Vector2(0.0128 + 0.0022 * sin(t * PI), lerpf(-0.100, 0.060, t)))
	ProcMesh.lathe(b.st(WeaponMeshes.DARK_WOOD), grip, 10, Vector3.ZERO, 1.0, 6.0)
	return b.commit(make_material)


## Pieza de carne con su hueso (un muslo), cruda o asada.
static func meat(cooked: bool) -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var flesh := b.st(COOKED_MEAT if cooked else RAW_MEAT)
	var shrink := 0.92 if cooked else 1.0
	var profile := []
	for p in [Vector2(0.0, 0.0), Vector2(0.026, 0.006), Vector2(0.046, 0.03), Vector2(0.058, 0.065),
			Vector2(0.060, 0.10), Vector2(0.052, 0.135), Vector2(0.034, 0.16), Vector2(0.0, 0.172)]:
		profile.append(Vector2(p.x * shrink, p.y))
	ProcMesh.lathe(flesh, profile, 14)
	var bone := b.st(BONE)
	ProcMesh.lathe(bone, [Vector2(0.011, -0.07), Vector2(0.010, -0.03), Vector2(0.012, 0.01)], 10)
	# Cabeza del hueso: dos bultos.
	for side in [-1.0, 1.0]:
		ProcMesh.lathe(bone, [Vector2(0.0, -0.104), Vector2(0.012, -0.098), Vector2(0.016, -0.086),
			Vector2(0.012, -0.074), Vector2(0.0, -0.068)], 10, Vector3(side * 0.011, 0, 0))
	return b.commit(make_material)


## Piel estirada: el contorno de un animal abierto (cuerpo, cuatro patas, cuello y rabo), plana
## en XY y con algo de grosor.
static func hide() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var st := b.st(HIDE)
	ProcMesh.set_flat(st, true)
	var outline := PackedVector2Array()
	var n := 72
	for i in n:
		var a := TAU * float(i) / n
		var r := Vector2(0.2 * cos(a), 0.34 * sin(a))
		var bump := 0.0
		for leg in [0.55, PI - 0.55, PI + 0.6, TAU - 0.6]:
			bump += 0.75 * exp(-pow(angle_difference(a, leg) / 0.12, 2.0))
		bump += 0.22 * exp(-pow(angle_difference(a, PI * 0.5) / 0.2, 2.0))
		bump += 0.2 * exp(-pow(angle_difference(a, PI * 1.5) / 0.09, 2.0))
		var wobble := 0.012 * sin(a * 7.0) + 0.008 * sin(a * 13.0 + 1.0)
		outline.append(r * (1.0 + bump + wobble))
	var front := PackedVector3Array()
	var back := PackedVector3Array()
	for p in outline:
		front.append(Vector3(p.x, p.y, 0.006))
		back.append(Vector3(p.x, p.y, -0.006))
	ProcMesh.loft(st, [back, front])
	return b.commit(make_material)


## Hueso largo (un fémur de ciervo): la caña, más estrecha en medio, y dos cabezas en cada punta.
static func bone() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var st := b.st(BONE)
	var shaft := []
	for i in 9:
		var t := float(i) / 8.0
		shaft.append(Vector2(0.012 + 0.008 * pow(absf(t - 0.5) * 2.0, 3.0), lerpf(-0.12, 0.12, t)))
	ProcMesh.lathe(st, shaft, 10)
	for end in [-1.0, 1.0]:
		for side in [-1.0, 1.0]:
			ProcMesh.lathe(st, [Vector2(0.0, -0.016), Vector2(0.012, -0.012), Vector2(0.016, 0.0),
				Vector2(0.012, 0.012), Vector2(0.0, 0.016)], 10, Vector3(side * 0.011, end * 0.128, side * end * 0.003))
	return b.commit(make_material)


## Tendón seco: un manojo de hebras pálidas, algo retorcidas, atado por el medio y abierto en las
## puntas como un pincel.
static func sinew() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	_strands(b.st(SINEW), 5, 7, 0.13, 0.0028, 0.009)
	ProcMesh.lathe(b.st(WeaponMeshes.CORD), [Vector2(0.0085, -0.012), Vector2(0.0095, 0.0),
		Vector2(0.0085, 0.012)], 10)
	return b.commit(make_material)


## Fibra vegetal: un manojo de tiras de corteza y tallos arrancados de un arbusto, más largo y
## basto que el tendón, atado con dos vueltas de lo mismo.
static func plant_fiber() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var st := b.st(PLANT_FIBER)
	_strands(st, 9, 10, 0.16, 0.0032, 0.012)
	for y in [-0.05, 0.05]:
		ProcMesh.lathe(st, [Vector2(0.0095, y - 0.006), Vector2(0.0108, y), Vector2(0.0095, y + 0.006)], 10)
	return b.commit(make_material)


## Pluma de ala: el cañón, pelado abajo, afinándose hasta la punta y algo curvado, y las barbas a los
## dos lados, la de delante estrecha, inclinadas hacia la punta y algo combadas. Las barbas van por
## las dos caras (el icono no pinta las de atrás). El cañón en el origen y la punta hacia +Y; de cara
## a +Z.
static func feather() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var steps := 16
	var length := 0.2
	var spine := PackedVector3Array()
	var radii := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / steps
		spine.append(Vector3(0.014 * t * t, t * length, 0.0))
		var r := lerpf(0.0024, 0.0006, t)
		radii.append(Vector2(r, r))
	ProcMesh.tube(b.st(BONE), spine, radii, 6)
	var vane := b.st(PLUME)
	# Cada lado: su anchura (m) y hacia dónde (X).
	for side in [[0.024, 1.0], [0.009, -1.0]]:
		var rows: Array[PackedVector3Array] = []
		for i in steps + 1:
			var t := float(i) / steps
			# Pelada hasta el 14 %; la más ancha pasada la mitad y redonda en la punta.
			var u := clampf((t - 0.14) / 0.86, 0.0, 1.0)
			var w: float = side[0] * pow(sin(pow(u, 1.3) * PI), 0.6)
			var row := PackedVector3Array()
			for k in 3:
				var f := k / 2.0
				row.append(spine[i] + Vector3(side[1] * w * f, w * f * 0.35, -0.004 * f * f * w / side[0]))
			rows.append(row)
		for i in steps:
			for k in 2:
				var a := rows[i][k]
				var c := rows[i + 1][k + 1]
				var p := rows[i][k + 1]
				var q := rows[i + 1][k]
				ProcMesh.quad(vane, a, p, c, q)
				ProcMesh.quad(vane, a, q, c, p)
	return b.commit(make_material)


## [count] hebras de [half] de largo a cada lado del centro, algo retorcidas, juntas en el medio y
## abiertas hacia las puntas como un pincel (hasta [spread]).
static func _strands(st: SurfaceTool, seed_value: int, count: int, half: float, radius: float,
		spread: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for k in count:
		var phase := TAU * k / count
		var open_to := rng.randf_range(spread * 0.45, spread)
		var y0 := -half + rng.randf_range(-0.12, 0.12) * half
		var y1 := half + rng.randf_range(-0.12, 0.12) * half
		var points := PackedVector3Array()
		var radii := PackedVector2Array()
		var steps := 16
		for i in steps + 1:
			var t := float(i) / steps
			var open := open_to * (0.35 + 1.6 * absf(t - 0.5))
			var a := phase + t * 2.4
			points.append(Vector3(cos(a) * open, lerpf(y0, y1, t), sin(a) * open))
			var r := radius * (1.0 - 0.6 * absf(t - 0.5) * 2.0)
			radii.append(Vector2(r, r * 0.7))
		ProcMesh.tube(st, points, radii, 5)


## Asta de ciervo: la vara curvada hacia atrás con la roseta en la base, la luchadera, la punta
## media y la de en medio hacia delante, y una corona de tres puntas. La base en el origen, la vara
## hacia +Y y las puntas hacia +Z.
static func antler() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var st := b.st(ANTLER)
	var p0 := Vector3.ZERO
	var c1 := Vector3(0.01, 0.22, -0.10)
	var c2 := Vector3(-0.01, 0.42, -0.04)
	var p1 := Vector3(0.0, 0.56, 0.04)
	_tapered(st, _bezier(p0, c1, c2, p1, 14), 0.023, 0.011, 9)
	# Roseta: el anillo rugoso donde se une al cráneo.
	ProcMesh.lathe(st, [Vector2(0.0, -0.012), Vector2(0.026, -0.008), Vector2(0.028, 0.0),
		Vector2(0.02, 0.008)], 10)
	# Cada punta: dónde arranca de la vara (0-1), hacia dónde va y su grosor.
	var up := Vector3.UP
	for tine in [[0.07, Vector3(0.0, 0.06, 0.19), 0.014], [0.17, Vector3(0.015, 0.07, 0.15), 0.012],
			[0.58, Vector3(-0.015, 0.06, 0.14), 0.011], [1.0, Vector3(0.06, 0.11, 0.02), 0.010],
			[1.0, Vector3(-0.055, 0.11, 0.03), 0.010], [1.0, Vector3(0.0, 0.09, 0.10), 0.010]]:
		var root: Vector3 = p0.bezier_interpolate(c1, c2, p1, tine[0])
		var dir: Vector3 = tine[1]
		_tapered(st, _bezier(root, root + dir * 0.4, root + dir * 0.75 + up * 0.015, root + dir + up * 0.035, 6),
			tine[2], 0.0015, 7)
	return b.commit(make_material)


## Colmillo de jabalí: corto y muy enroscado (más de media vuelta, cerrándose), de sección
## aplastada, grueso en la raíz y con la punta afilada.
static func boar_tusk() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var points := PackedVector3Array()
	var steps := 18
	for i in steps + 1:
		var t := float(i) / steps
		var a := lerpf(-0.3, PI * 1.15, t)
		var r := 0.05 * (1.0 - 0.3 * t)
		points.append(Vector3(0.008 * t, sin(a) * r, -cos(a) * r))
	_tapered(b.st(IVORY), points, 0.012, 0.0012, 7, 0.0, 0.7)
	return b.commit(make_material)


## Colmillo de mamut: largo y grueso en la raíz, curvado hacia arriba y abriéndose hacia fuera,
## romo en la punta.
static func ivory() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var points := PackedVector3Array()
	var steps := 20
	for i in steps + 1:
		var t := float(i) / steps
		var a := t * PI * 0.55
		points.append(Vector3(0.3 * t * t, sin(a) * 0.6, (1.0 - cos(a)) * 0.6))
	_tapered(b.st(IVORY), points, 0.075, 0.022, 12)
	return b.commit(make_material)


## Cuerno de bóvido o de cabra: un cono curvado hacia atrás y hacia fuera, con los anillos de
## crecimiento marcados en la base.
static func horn() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var points := PackedVector3Array()
	var steps := 18
	for i in steps + 1:
		var t := float(i) / steps
		var a := t * PI * 0.7
		points.append(Vector3(0.04 * t * t, sin(a) * 0.14, -(1.0 - cos(a)) * 0.14))
	_tapered(b.st(HORN), points, 0.03, 0.002, 10, 9.0, 0.85)
	return b.commit(make_material)


## Pieza que se afila a lo largo de [points] (astas, cuernos, colmillos): radio [r0] en la base y
## [r1] en la punta. [ridges] marca anillos que se borran hacia la punta; [flatten] aplasta la
## sección.
static func _tapered(st: SurfaceTool, points: PackedVector3Array, r0: float, r1: float, segments: int = 8,
		ridges: float = 0.0, flatten: float = 1.0) -> void:
	var radii := PackedVector2Array()
	var n := points.size()
	for i in n:
		var t := float(i) / float(n - 1)
		var r := lerpf(r0, r1, t)
		if ridges > 0.0:
			r *= 1.0 + 0.08 * (1.0 - t) * absf(sin(t * ridges * PI))
		radii.append(Vector2(r, r * flatten))
	ProcMesh.tube(st, points, radii, segments)


static func _bezier(p0: Vector3, c1: Vector3, c2: Vector3, p1: Vector3, steps: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in steps + 1:
		points.append(p0.bezier_interpolate(c1, c2, p1, float(i) / steps))
	return points


## Milenrama: un manojo de tallos con las hojas finas como plumas y, arriba, las umbelas planas de
## florecillas blancas. Los tallos se juntan en el origen y suben por +Y.
static func yarrow() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 211
	var stem := b.st(HERB)
	var flowers := b.st(BLOSSOM)
	for k in 4:
		var a := TAU * k / 4.0 + rng.randf_range(-0.3, 0.3)
		var lean := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.035, 0.06)
		var top := lean + Vector3.UP * rng.randf_range(0.19, 0.24)
		var points := PackedVector3Array([Vector3.ZERO, top * 0.5 + lean * 0.2, top])
		ProcMesh.tube(stem, points, PackedVector2Array([Vector2(0.004, 0.004), Vector2(0.0034, 0.0034),
			Vector2(0.0028, 0.0028)]), 6)
		# Hojas: un raquis con hojuelas a los dos lados, como una pluma.
		for leaf in 2:
			var t := 0.3 + 0.25 * leaf
			var root := Vector3.ZERO.lerp(top, t)
			var out := Vector3(cos(a + 1.2 + leaf * 2.4), 0.3, sin(a + 1.2 + leaf * 2.4)).normalized()
			var side := out.cross(Vector3.UP).normalized()
			for f in 6:
				var p := root + out * (0.012 + f * 0.012)
				var w := 0.018 * (1.0 - f / 7.0)
				ProcMesh.tri(stem, p, p + side * w + out * 0.007, p + out * 0.012)
				ProcMesh.tri(stem, p, p + out * 0.012, p - side * w + out * 0.007)
		# Umbela: una cúpula aplastada de cabezuelas.
		for f in 11:
			var fa := TAU * f / 11.0 + rng.randf()
			var r := 0.0 if f == 0 else sqrt(f / 11.0) * 0.03
			ProcMesh.lathe(flowers, [Vector2(0.0, -0.004), Vector2(0.008, 0.0), Vector2(0.0, 0.004)], 7,
				top + Vector3(cos(fa) * r, -r * 0.3, sin(fa) * r))
	# Atado con fibra.
	ProcMesh.lathe(b.st(WeaponMeshes.CORD), [Vector2(0.01, 0.03), Vector2(0.011, 0.037),
		Vector2(0.01, 0.044)], 8)
	return b.commit(make_material)


## Emplasto: la milenrama machacada sobre una hoja ancha y atada en cruz con fibra. Tumbado, de
## cara a +Y.
static func poultice() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var leaf := b.st(HERB)
	var w := 0.055
	var h := 0.075
	# La hoja: un óvalo algo combado hacia arriba en los bordes.
	var rim := PackedVector3Array()
	for i in 14:
		var a := TAU * i / 14.0
		rim.append(Vector3(cos(a) * w, 0.006 * (1.0 - absf(sin(a))), sin(a) * h))
	for i in 14:
		ProcMesh.tri(leaf, Vector3(0, -0.002, 0), rim[(i + 1) % 14], rim[i])
		ProcMesh.tri(leaf, Vector3(0, -0.003, 0), rim[i], rim[(i + 1) % 14])
	# La pasta, un bulto oscuro en medio.
	ProcMesh.lathe(b.st(POULTICE), [Vector2(0.040, 0.0), Vector2(0.036, 0.008), Vector2(0.026, 0.014),
		Vector2(0.0, 0.017)], 12)
	# Las ataduras, en cruz por encima de la pasta.
	var cord := b.st(WeaponMeshes.CORD)
	for dir in [Vector3.RIGHT, Vector3.BACK]:
		var span: float = w if dir == Vector3.RIGHT else h
		ProcMesh.tube(cord, PackedVector3Array([-dir * span * 0.95, -dir * span * 0.5 + Vector3.UP * 0.012,
			Vector3.UP * 0.019, dir * span * 0.5 + Vector3.UP * 0.012, dir * span * 0.95]),
			PackedVector2Array([Vector2(0.0022, 0.0022), Vector2(0.0022, 0.0022), Vector2(0.0022, 0.0022),
			Vector2(0.0022, 0.0022), Vector2(0.0022, 0.0022)]), 5, Vector3.UP)
	return b.commit(make_material)


## Bebedizo: un cuerno hueco tapado con madera y colgado de una tira, con el bebedizo dentro.
## La punta abajo y la boca hacia +Y.
static func draught() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var points := PackedVector3Array()
	var steps := 12
	for i in steps + 1:
		var t := float(i) / steps
		var a := (1.0 - t) * PI * 0.35
		points.append(Vector3(0.0, 0.16 * t, -sin(a) * 0.05 * (1.0 - t)))
	points.reverse()
	_tapered(b.st(HORN), points, 0.026, 0.004, 10, 6.0)
	points.reverse()
	ProcMesh.lathe(b.st(WeaponMeshes.WOOD), [Vector2(0.0, 0.155), Vector2(0.022, 0.155),
		Vector2(0.024, 0.17), Vector2(0.016, 0.182), Vector2(0.0, 0.184)], 10)
	ProcMesh.lathe(b.st(WeaponMeshes.LEATHER), [Vector2(0.027, 0.13), Vector2(0.029, 0.136),
		Vector2(0.027, 0.142)], 10)
	return b.commit(make_material)


## Tablilla: dos palos rectos atados con tres vueltas de fibra, para sujetar un hueso roto.
static func splint() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var wood := b.st(WeaponMeshes.WOOD)
	for x in [-0.022, 0.022]:
		ProcMesh.lathe(wood, [Vector2(0.0, -0.17), Vector2(0.008, -0.168), Vector2(0.009, 0.0),
			Vector2(0.008, 0.168), Vector2(0.0, 0.17)], 7, Vector3(x, 0, 0))
	var fiber := b.st(PLANT_FIBER)
	for y in [-0.11, 0.0, 0.11]:
		# Cada atadura: unas vueltas apretadas alrededor de los dos palos (un lazo aplastado).
		for turn in 3:
			var loop := PackedVector3Array()
			var radii := PackedVector2Array()
			for i in 17:
				var a := TAU * i / 16.0
				loop.append(Vector3(cos(a) * 0.034, y + (turn - 1) * 0.006, sin(a) * 0.012))
				radii.append(Vector2(0.0028, 0.0028))
			ProcMesh.tube(fiber, loop, radii, 5, Vector3.UP, false)
	return b.commit(make_material)


## Lasca afilada: una pirámide aplanada de punta, como las de la obsidiana.
static func _shard(st: SurfaceTool, base: Vector3, direction: Vector3, length: float, width: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var frame := Basis.looking_at(direction.normalized(), Vector3.UP if absf(direction.normalized().y) < 0.9 else Vector3.RIGHT)
	var ring := PackedVector3Array()
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)
		ring.append(base + frame * Vector3(cos(a) * width, sin(a) * width * 0.45, 0.0))
	var tip := base + direction.normalized() * length
	ProcMesh.set_flat(st, true)
	for k in 5:
		ProcMesh.tri(st, ring[k], ring[(k + 1) % 5], tip)
	ProcMesh.fan(st, ring, true)
	ProcMesh.set_flat(st, false)


## Lo que da cada mena al picarla, en trozos que caben en la mano (unos 6-9 cm).
static func ore_chunk(ore: StringName) -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	match ore:
		&"flint":
			# Nódulo de sílex: corteza blanca de creta y, por donde se partió, el sílex negro.
			WeaponMeshes.lump(b.st(CORTEX), Vector3.ZERO, 0.045, 3, 0.85, 0.18)
			WeaponMeshes.lump(b.st(WeaponMeshes.FLINT), Vector3(0.012, 0.004, 0.018), 0.038, 5, 0.75, 0.1,
				Basis(Vector3.UP, 0.4))
		&"obsidian":
			# Un bloque de vidrio de aristas vivas y un par de lascas anchas a punto de saltar.
			WeaponMeshes.lump(b.st(OBSIDIAN), Vector3.ZERO, 0.042, 19, 0.7, 0.42)
			for k in 2:
				var dir := Vector3(cos(k * 2.6 + 0.4), 0.35, sin(k * 2.6 + 0.4))
				_shard(b.st(OBSIDIAN), dir * 0.02, dir, 0.05, 0.03, 17 + k)
		&"copper_ore":
			WeaponMeshes.lump(b.st(ORE_ROCK), Vector3.ZERO, 0.045, 23, 0.8, 0.25)
			for k in 4:
				var a := k * 1.9
				WeaponMeshes.lump(b.st(MALACHITE), Vector3(cos(a), 0.4, sin(a)) * 0.032, 0.016, 29 + k, 0.5, 0.35)
		&"tin_ore":
			WeaponMeshes.lump(b.st(ORE_ROCK), Vector3.ZERO, 0.04, 31, 0.75, 0.25)
			for k in 6:
				var dir := Vector3(cos(k * 1.1), 0.9, sin(k * 1.1)).normalized()
				_shard(b.st(CASSITERITE), dir * 0.025, dir + Vector3(0, 0.3, 0), 0.028, 0.012, 37 + k)
		&"bog_iron":
			WeaponMeshes.lump(b.st(LIMONITE), Vector3.ZERO, 0.04, 41, 0.7, 0.32)
			WeaponMeshes.lump(b.st(LIMONITE), Vector3(0.035, -0.008, 0.01), 0.026, 43, 0.75, 0.3)
			WeaponMeshes.lump(b.st(LIMONITE), Vector3(-0.03, -0.01, -0.02), 0.022, 47, 0.8, 0.3)
		&"iron_ore":
			WeaponMeshes.lump(b.st(HEMATITE), Vector3.ZERO, 0.048, 53, 0.78, 0.2)
		&"coal":
			WeaponMeshes.lump(b.st(COAL), Vector3.ZERO, 0.045, 59, 0.7, 0.34)
			WeaponMeshes.lump(b.st(COAL), Vector3(0.04, -0.01, 0.0), 0.025, 61, 0.7, 0.34)
		&"silver_ore":
			WeaponMeshes.lump(b.st(ORE_ROCK), Vector3.ZERO, 0.042, 67, 0.75, 0.22)
			for k in 3:
				var at := Vector3(cos(k * 2.1) * 0.026, 0.024, sin(k * 2.1) * 0.026)
				ProcMesh.box(b.st(GALENA), at, Vector3.ONE * (0.018 - k * 0.003),
					Basis(Vector3(0.3, 1, 0.2).normalized(), k * 0.7))
		&"gold":
			WeaponMeshes.lump(b.st(GOLD), Vector3.ZERO, 0.03, 71, 0.6, 0.4)
			WeaponMeshes.lump(b.st(GOLD), Vector3(0.022, 0.004, 0.006), 0.017, 73, 0.7, 0.4)
		&"sulfur":
			WeaponMeshes.lump(b.st(ORE_ROCK), Vector3(0, -0.01, 0), 0.04, 79, 0.6, 0.2)
			for k in 7:
				var a := k * 0.9
				WeaponMeshes.lump(b.st(SULFUR), Vector3(cos(a) * 0.022, 0.012 + 0.004 * (k % 3), sin(a) * 0.022), 0.014,
					83 + k, 0.8, 0.35)
	return b.commit(make_material)


## Odre: una bolsa de cuero con el cuello atado, un tapón de madera y la correa.
static func waterskin() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	ProcMesh.lathe(b.st(WeaponMeshes.LEATHER), [Vector2(0.0, 0.0), Vector2(0.05, 0.008),
		Vector2(0.084, 0.045), Vector2(0.092, 0.095), Vector2(0.08, 0.145), Vector2(0.048, 0.185),
		Vector2(0.024, 0.205), Vector2(0.022, 0.235)], 16)
	ProcMesh.lathe(b.st(WeaponMeshes.CORD), [Vector2(0.026, 0.207), Vector2(0.029, 0.213),
		Vector2(0.026, 0.219)], 12)
	ProcMesh.lathe(b.st(WeaponMeshes.WOOD), [Vector2(0.017, 0.232), Vector2(0.02, 0.262),
		Vector2(0.0, 0.268)], 10)
	var strap := PackedVector3Array()
	var radii := PackedVector2Array()
	for i in 17:
		var t := float(i) / 16.0
		var a := lerpf(-0.2, PI + 0.2, t)
		strap.append(Vector3(cos(a) * 0.1, 0.2 + sin(a) * 0.09, 0.0))
		radii.append(Vector2(0.006, 0.004))
	ProcMesh.tube(b.st(WeaponMeshes.LEATHER), strap, radii, 6, Vector3.BACK)
	return b.commit(make_material)


## Hoguera: un corro de piedras alrededor de la ceniza y unos leños en tienda. El origen es el
## suelo, en el centro.
static func campfire() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var stone := b.st(WeaponMeshes.STONE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var count := 10
	for i in count:
		var a := TAU * (float(i) + rng.randf_range(-0.15, 0.15)) / count
		var r := rng.randf_range(0.075, 0.095)
		var h := r * rng.randf_range(0.75, 1.0)
		var at := Vector3(cos(a), 0.0, sin(a)) * 0.38
		ProcMesh.lathe(stone, [Vector2(0.0, -0.01), Vector2(r * 0.9, 0.0), Vector2(r, h * 0.45),
			Vector2(r * 0.7, h * 0.85), Vector2(0.0, h)], 7, at)
	ProcMesh.lathe(b.st(ASH), [Vector2(0.0, 0.012), Vector2(0.24, 0.01), Vector2(0.31, 0.0)], 18)
	var bark := b.st(WeaponMeshes.BARK)
	for i in 4:
		var a := TAU * (float(i) + 0.125) / 4.0
		var foot := Vector3(cos(a), 0.0, sin(a)) * 0.27 + Vector3(0, 0.03, 0)
		var head := Vector3(cos(a), 0.0, sin(a)) * 0.04 + Vector3(0, 0.34, 0)
		ProcMesh.tube(bark, PackedVector3Array([foot, foot.lerp(head, 0.5), head]),
			PackedVector2Array([Vector2(0.03, 0.03), Vector2(0.028, 0.028), Vector2(0.022, 0.022)]), 7)
	for i in 2:
		var a := PI * 0.5 * i + 0.3
		var dir := Vector3(cos(a), 0.0, sin(a))
		ProcMesh.tube(bark, PackedVector3Array([dir * -0.22 + Vector3(0, 0.035, 0), dir * 0.22 + Vector3(0, 0.035, 0)]),
			PackedVector2Array([Vector2(0.032, 0.032), Vector2(0.03, 0.03)]), 7)
	return b.commit(make_material)


## Banco de trabajo de la Edad de piedra, para el icono: tablero tosco sobre cuatro patas abiertas y,
## encima, la losa de tallar con una lasca, el percutor y un cuenco. El origen es el suelo, en el
## centro; el largo va en X.
static func workbench() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var top := 0.76
	ProcMesh.box(b.st(WeaponMeshes.WOOD), Vector3(0.0, top - 0.05, 0.0), Vector3(1.22, 0.1, 0.46))
	var legs := b.st(WeaponMeshes.DARK_WOOD)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var foot := Vector3(corner.x * 0.46, 0.0, corner.y * 0.34)
		var head := Vector3(corner.x * 0.38, top - 0.08, corner.y * 0.14)
		ProcMesh.tube(legs, PackedVector3Array([foot, head]), PackedVector2Array([Vector2(0.05, 0.05), Vector2(0.045, 0.045)]), 6)
	var stone := b.st(WeaponMeshes.STONE)
	ProcMesh.lathe(stone, [Vector2(0.0, top), Vector2(0.16, top), Vector2(0.17, top + 0.04), Vector2(0.14, top + 0.075),
		Vector2(0.0, top + 0.08)], 8, Vector3(-0.27, 0.0, 0.0))
	ProcMesh.lathe(stone, [Vector2(0.0, top), Vector2(0.06, top + 0.01), Vector2(0.065, top + 0.045),
		Vector2(0.0, top + 0.08)], 7, Vector3(0.03, 0.0, 0.12))
	ProcMesh.lathe(b.st(WeaponMeshes.FLINT), [Vector2(0.0, top + 0.075), Vector2(0.06, top + 0.08),
		Vector2(0.0, top + 0.1)], 5, Vector3(-0.3, 0.0, 0.0))
	ProcMesh.lathe(b.st(WeaponMeshes.DARK_WOOD), [Vector2(0.0, top), Vector2(0.06, top), Vector2(0.1, top + 0.06),
		Vector2(0.105, top + 0.09), Vector2(0.0, top + 0.09)], 10, Vector3(0.38, 0.0, -0.02))
	return b.commit(make_material)

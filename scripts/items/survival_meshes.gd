@tool
class_name SurvivalMeshes
extends RefCounted

## Mallas de los objetos de supervivencia (el seax, la carne, la piel, el odre, la hoguera y el banco
## de trabajo; de los dos últimos solo sale el icono: en el mundo se ven con sus modelos),
## generadas por código con los ayudantes de WeaponMeshes y horneadas a recursos, con sus iconos,
## por tools/combat/bake_weapons.gd. Metros; las de mano, con el origen en el agarre y +Y hacia la
## punta, como las armas.

const RAW_MEAT := &"raw_meat"
const COOKED_MEAT := &"cooked_meat"
const BONE := &"bone"
const HIDE := &"hide"
const ASH := &"ash"


static func make_material(kind: StringName) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = String(kind)
	match kind:
		RAW_MEAT:
			mat.albedo_texture = WeaponMeshes._noise_texture(Color(0.45, 0.06, 0.07), Color(0.78, 0.30, 0.30), 5.0, 31)
			mat.roughness = 0.45
		COOKED_MEAT:
			mat.albedo_texture = WeaponMeshes._noise_texture(Color(0.20, 0.09, 0.04), Color(0.52, 0.28, 0.12), 5.0, 37)
			mat.roughness = 0.6
		BONE:
			mat.albedo_color = Color(0.86, 0.82, 0.72)
			mat.roughness = 0.7
		HIDE:
			mat.albedo_texture = WeaponMeshes._noise_texture(Color(0.30, 0.20, 0.12), Color(0.56, 0.42, 0.28), 3.0, 41)
			mat.roughness = 0.9
		ASH:
			mat.albedo_texture = WeaponMeshes._noise_texture(Color(0.05, 0.05, 0.05), Color(0.22, 0.21, 0.2), 4.0, 43)
			mat.roughness = 1.0
		_:
			return WeaponMeshes.make_material(kind)
	return mat


## Seax: cuchillo de un filo con el lomo quebrado (recto y, cerca de la punta, en bajada hasta
## ella), virola de hierro y mango de madera. El filo mira a +Z.
static func seax() -> ArrayMesh:
	var b := WeaponMeshes.Builder.new()
	var steel := b.st(WeaponMeshes.STEEL)
	WeaponMeshes.set_flat(steel, true)
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
		WeaponMeshes.tri(steel, last[j], last[(j + 1) % last.size()], tip)
	WeaponMeshes.loft(steel, rings, true, false)
	var iron := b.st(WeaponMeshes.IRON)
	WeaponMeshes.lathe(iron, [Vector2(0.0145, 0.058), Vector2(0.0165, 0.064), Vector2(0.0160, 0.074),
		Vector2(0.0120, 0.077)], 10)
	WeaponMeshes.lathe(iron, [Vector2(0.0, -0.112), Vector2(0.0125, -0.108), Vector2(0.0140, -0.100)], 10)
	var grip := []
	for i in 9:
		var t := float(i) / 8.0
		grip.append(Vector2(0.0128 + 0.0022 * sin(t * PI), lerpf(-0.100, 0.060, t)))
	WeaponMeshes.lathe(b.st(WeaponMeshes.DARK_WOOD), grip, 10, Vector3.ZERO, 1.0, 6.0)
	return b.commit(make_material)


## Pieza de carne con su hueso (un muslo), cruda o asada.
static func meat(cooked: bool) -> ArrayMesh:
	var b := WeaponMeshes.Builder.new()
	var flesh := b.st(COOKED_MEAT if cooked else RAW_MEAT)
	var shrink := 0.92 if cooked else 1.0
	var profile := []
	for p in [Vector2(0.0, 0.0), Vector2(0.026, 0.006), Vector2(0.046, 0.03), Vector2(0.058, 0.065),
			Vector2(0.060, 0.10), Vector2(0.052, 0.135), Vector2(0.034, 0.16), Vector2(0.0, 0.172)]:
		profile.append(Vector2(p.x * shrink, p.y))
	WeaponMeshes.lathe(flesh, profile, 14)
	var bone := b.st(BONE)
	WeaponMeshes.lathe(bone, [Vector2(0.011, -0.07), Vector2(0.010, -0.03), Vector2(0.012, 0.01)], 10)
	# Cabeza del hueso: dos bultos.
	for side in [-1.0, 1.0]:
		WeaponMeshes.lathe(bone, [Vector2(0.0, -0.104), Vector2(0.012, -0.098), Vector2(0.016, -0.086),
			Vector2(0.012, -0.074), Vector2(0.0, -0.068)], 10, Vector3(side * 0.011, 0, 0))
	return b.commit(make_material)


## Piel estirada: el contorno de un animal abierto (cuerpo, cuatro patas, cuello y rabo), plana
## en XY y con algo de grosor.
static func hide() -> ArrayMesh:
	var b := WeaponMeshes.Builder.new()
	var st := b.st(HIDE)
	WeaponMeshes.set_flat(st, true)
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
	WeaponMeshes.loft(st, [back, front])
	return b.commit(make_material)


## Odre: una bolsa de cuero con el cuello atado, un tapón de madera y la correa.
static func waterskin() -> ArrayMesh:
	var b := WeaponMeshes.Builder.new()
	WeaponMeshes.lathe(b.st(WeaponMeshes.LEATHER), [Vector2(0.0, 0.0), Vector2(0.05, 0.008),
		Vector2(0.084, 0.045), Vector2(0.092, 0.095), Vector2(0.08, 0.145), Vector2(0.048, 0.185),
		Vector2(0.024, 0.205), Vector2(0.022, 0.235)], 16)
	WeaponMeshes.lathe(b.st(WeaponMeshes.CORD), [Vector2(0.026, 0.207), Vector2(0.029, 0.213),
		Vector2(0.026, 0.219)], 12)
	WeaponMeshes.lathe(b.st(WeaponMeshes.WOOD), [Vector2(0.017, 0.232), Vector2(0.02, 0.262),
		Vector2(0.0, 0.268)], 10)
	var strap := PackedVector3Array()
	var radii := PackedVector2Array()
	for i in 17:
		var t := float(i) / 16.0
		var a := lerpf(-0.2, PI + 0.2, t)
		strap.append(Vector3(cos(a) * 0.1, 0.2 + sin(a) * 0.09, 0.0))
		radii.append(Vector2(0.006, 0.004))
	WeaponMeshes.tube(b.st(WeaponMeshes.LEATHER), strap, radii, 6, Vector3.BACK)
	return b.commit(make_material)


## Hoguera: un corro de piedras alrededor de la ceniza y unos leños en tienda. El origen es el
## suelo, en el centro.
static func campfire() -> ArrayMesh:
	var b := WeaponMeshes.Builder.new()
	var stone := b.st(WeaponMeshes.STONE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var count := 10
	for i in count:
		var a := TAU * (float(i) + rng.randf_range(-0.15, 0.15)) / count
		var r := rng.randf_range(0.075, 0.095)
		var h := r * rng.randf_range(0.75, 1.0)
		var at := Vector3(cos(a), 0.0, sin(a)) * 0.38
		WeaponMeshes.lathe(stone, [Vector2(0.0, -0.01), Vector2(r * 0.9, 0.0), Vector2(r, h * 0.45),
			Vector2(r * 0.7, h * 0.85), Vector2(0.0, h)], 7, at)
	WeaponMeshes.lathe(b.st(ASH), [Vector2(0.0, 0.012), Vector2(0.24, 0.01), Vector2(0.31, 0.0)], 18)
	var bark := b.st(WeaponMeshes.BARK)
	for i in 4:
		var a := TAU * (float(i) + 0.125) / 4.0
		var foot := Vector3(cos(a), 0.0, sin(a)) * 0.27 + Vector3(0, 0.03, 0)
		var head := Vector3(cos(a), 0.0, sin(a)) * 0.04 + Vector3(0, 0.34, 0)
		WeaponMeshes.tube(bark, PackedVector3Array([foot, foot.lerp(head, 0.5), head]),
			PackedVector2Array([Vector2(0.03, 0.03), Vector2(0.028, 0.028), Vector2(0.022, 0.022)]), 7)
	for i in 2:
		var a := PI * 0.5 * i + 0.3
		var dir := Vector3(cos(a), 0.0, sin(a))
		WeaponMeshes.tube(bark, PackedVector3Array([dir * -0.22 + Vector3(0, 0.035, 0), dir * 0.22 + Vector3(0, 0.035, 0)]),
			PackedVector2Array([Vector2(0.032, 0.032), Vector2(0.03, 0.03)]), 7)
	return b.commit(make_material)


## Banco de trabajo de la Edad de piedra, para el icono: tablero tosco sobre cuatro patas abiertas y,
## encima, la losa de tallar con una lasca, el percutor y un cuenco. El origen es el suelo, en el
## centro; el largo va en X.
static func workbench() -> ArrayMesh:
	var b := WeaponMeshes.Builder.new()
	var top := 0.76
	WeaponMeshes.box(b.st(WeaponMeshes.WOOD), Vector3(0.0, top - 0.05, 0.0), Vector3(1.22, 0.1, 0.46))
	var legs := b.st(WeaponMeshes.DARK_WOOD)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var foot := Vector3(corner.x * 0.46, 0.0, corner.y * 0.34)
		var head := Vector3(corner.x * 0.38, top - 0.08, corner.y * 0.14)
		WeaponMeshes.tube(legs, PackedVector3Array([foot, head]), PackedVector2Array([Vector2(0.05, 0.05), Vector2(0.045, 0.045)]), 6)
	var stone := b.st(WeaponMeshes.STONE)
	WeaponMeshes.lathe(stone, [Vector2(0.0, top), Vector2(0.16, top), Vector2(0.17, top + 0.04), Vector2(0.14, top + 0.075),
		Vector2(0.0, top + 0.08)], 8, Vector3(-0.27, 0.0, 0.0))
	WeaponMeshes.lathe(stone, [Vector2(0.0, top), Vector2(0.06, top + 0.01), Vector2(0.065, top + 0.045),
		Vector2(0.0, top + 0.08)], 7, Vector3(0.03, 0.0, 0.12))
	WeaponMeshes.lathe(b.st(WeaponMeshes.FLINT), [Vector2(0.0, top + 0.075), Vector2(0.06, top + 0.08),
		Vector2(0.0, top + 0.1)], 5, Vector3(-0.3, 0.0, 0.0))
	WeaponMeshes.lathe(b.st(WeaponMeshes.DARK_WOOD), [Vector2(0.0, top), Vector2(0.06, top), Vector2(0.1, top + 0.06),
		Vector2(0.105, top + 0.09), Vector2(0.0, top + 0.09)], 10, Vector3(0.38, 0.0, -0.02))
	return b.commit(make_material)

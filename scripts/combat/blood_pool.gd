class_name BloodPool
extends Decal

## Sangre en el suelo: un charco que crece despacio (bajo un miembro cortado, bajo un cuerpo) o una
## salpicadura (las gotas que caen de un muñón, el rastro de una presa herida). Un Decal apoyado en
## el suelo bajo el punto, en la dirección de la gravedad del planeta, que pinta lo que haya a unos
## centímetros: el terreno y lo que esté tirado encima (el miembro, el cuerpo, las botas del que lo
## pisa). Donde es fina empapa el suelo y lo deja ver; donde se encharca es casi negra y brilla. Se
## va oscureciendo al secarse y desaparece pasado un rato. Las texturas (varias de cada, una al azar) las hornea
## tools/combat/bake_blood_decals.gd.

## Las texturas de cada tipo: [color, relieve, oclusión-rugosidad-metal].
const POOL_TEXTURES := [
	[preload("res://textures/combat/blood_pool_0.png"),
		preload("res://textures/combat/blood_pool_0_normal.png"),
		preload("res://textures/combat/blood_pool_0_orm.png")],
	[preload("res://textures/combat/blood_pool_1.png"),
		preload("res://textures/combat/blood_pool_1_normal.png"),
		preload("res://textures/combat/blood_pool_1_orm.png")],
	[preload("res://textures/combat/blood_pool_2.png"),
		preload("res://textures/combat/blood_pool_2_normal.png"),
		preload("res://textures/combat/blood_pool_2_orm.png")],
]
const SPLAT_TEXTURES := [
	[preload("res://textures/combat/blood_splat_0.png"),
		preload("res://textures/combat/blood_splat_0_normal.png"),
		preload("res://textures/combat/blood_splat_0_orm.png")],
	[preload("res://textures/combat/blood_splat_1.png"),
		preload("res://textures/combat/blood_splat_1_normal.png"),
		preload("res://textures/combat/blood_splat_1_orm.png")],
	[preload("res://textures/combat/blood_splat_2.png"),
		preload("res://textures/combat/blood_splat_2_normal.png"),
		preload("res://textures/combat/blood_splat_2_orm.png")],
	[preload("res://textures/combat/blood_splat_3.png"),
		preload("res://textures/combat/blood_splat_3_normal.png"),
		preload("res://textures/combat/blood_splat_3_orm.png")],
]
const SMEAR_TEXTURES := [
	[preload("res://textures/combat/blood_smear_0.png"),
		preload("res://textures/combat/blood_smear_0_normal.png"),
		preload("res://textures/combat/blood_smear_0_orm.png")],
	[preload("res://textures/combat/blood_smear_1.png"),
		preload("res://textures/combat/blood_smear_1_normal.png"),
		preload("res://textures/combat/blood_smear_1_orm.png")],
	[preload("res://textures/combat/blood_smear_2.png"),
		preload("res://textures/combat/blood_smear_2_normal.png"),
		preload("res://textures/combat/blood_smear_2_orm.png")],
]

## Los que caben a la vez de cada tipo: al pasar, se va el más viejo.
const MAX_POOLS := 24
const MAX_SPLATS := 96
const LIFETIME := 180.0
const FADE := 15.0
## El rastro de una criatura herida (CreatureWounds) va aparte, para que la sangre de una pelea no
## se lleve las gotas que hay que seguir, y dura más: da tiempo a ir tras él.
const MAX_TRAIL := 160
const TRAIL_LIFETIME := 420.0
## Lo que tarda en secarse (se oscurece).
const DRY_TIME := 90.0
## Alto de la caja que proyecta: el suelo y lo que esté tirado en él, no las rodillas del que pasa.
const DEPTH := 0.24
## Hasta dónde busca el suelo bajo el punto (m).
const REACH := 3.0
## Ya extendida, secarse es lento: basta con repasarla cada tanto (s).
const SETTLED_STEP := 0.5

static var _pools: Array[BloodPool] = []
static var _splats: Array[BloodPool] = []
static var _trail: Array[BloodPool] = []

var _target := Vector2.ONE
var _grow_time := 1.0
var _lifetime := LIFETIME
var _age := 0.0
var _since := 0.0


## Deja sangre en el suelo bajo [point], buscándolo hacia [gravity] contra [mask]: un charco de
## [size] m que tarda [grow_time] s en extenderse, o una salpicadura si [splat]. Si es del rastro
## de una criatura herida, [trail]. null si no hay suelo cerca.
static func spawn(context: Node3D, point: Vector3, gravity: Vector3, size: float, grow_time: float,
		mask: int, splat := false, trail := false) -> BloodPool:
	if context == null or not context.is_inside_tree() \
			or SettingsManager.gore_level() == SettingsManager.GORE_OFF:
		return null
	var host := context.get_tree().current_scene
	if host == null:
		return null
	# Sin gravedad no hay abajo (en una esfera no hay uno fijo): sin charco.
	if gravity.length_squared() < 1e-6:
		return null
	var down := gravity.normalized()
	var hit := Raycast.ground(context, point, -down, 0.3, REACH, mask)
	if hit.is_empty():
		return null
	var pool := BloodPool.new()
	pool.name = "BloodSplat" if splat else "BloodPool"
	var textures: Array = (SPLAT_TEXTURES if splat else POOL_TEXTURES).pick_random()
	pool.texture_albedo = textures[0]
	pool.texture_normal = textures[1]
	pool.texture_orm = textures[2]
	# No pinta paredes: solo lo que mira hacia arriba.
	pool.normal_fade = 0.35
	pool.upper_fade = 0.15
	pool.lower_fade = 0.3
	pool.distance_fade_enabled = true
	pool.distance_fade_begin = 45.0
	pool.distance_fade_length = 15.0
	pool._grow_time = maxf(grow_time, 0.05)
	pool._lifetime = TRAIL_LIFETIME if trail else LIFETIME
	var aspect := randf_range(0.8, 1.25)
	pool._target = Vector2(size * aspect, size / aspect)
	pool.size = Vector3(size * 0.08, DEPTH, size * 0.08)
	host.add_child(pool, true)
	# +Y del decal según la normal del suelo, girado al azar sobre ella. La colisión del terreno puede
	# dar la normal de la cara de atrás: un decal boca abajo se desvanece del todo (normal_fade).
	var up: Vector3 = hit.normal
	if up.dot(-down) < 0.2:
		up = -down
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	side = side.rotated(up, randf() * TAU)
	pool.global_transform = Transform3D(Basis(side, up, side.cross(up)), hit.position)
	pool.add_to_group(&"floating_origin")
	# Las hojas de la hierba y los arbustos de encima también se manchan.
	BloodFoliage.add(hit.position, size * (0.8 if splat else 0.55), pool._lifetime)
	var list := _trail if trail else (_splats if splat else _pools)
	list.append(pool)
	while list.size() > (MAX_TRAIL if trail else (MAX_SPLATS if splat else MAX_POOLS)):
		var old: BloodPool = list.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	return pool


## Cuántos charcos y salpicaduras hay (las del rastro, con las salpicaduras) y el más cercano a
## [from] (consola, `blood`).
static func report(from: Vector3) -> String:
	var nearest := INF
	var near_size := Vector3.ZERO
	for list in [_pools, _splats, _trail]:
		for pool: BloodPool in list:
			if is_instance_valid(pool) and pool.global_position.distance_to(from) < nearest:
				nearest = pool.global_position.distance_to(from)
				near_size = pool.size
	if nearest == INF:
		return TranslationServer.translate(&"CON_BLOOD_NONE")
	return TranslationServer.translate(&"CON_BLOOD_REPORT") % [_pools.size(),
			_splats.size() + _trail.size(), nearest, near_size.x, near_size.z]


func _exit_tree() -> void:
	_pools.erase(self)
	_splats.erase(self)
	_trail.erase(self)


func _process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime:
		queue_free()
		return
	if _age > _grow_time and _age < _lifetime - FADE:
		_since += delta
		if _since < SETTLED_STEP:
			return
		_since = 0.0
	# Se extiende deprisa al principio y cada vez más despacio.
	var grow := 1.0 - pow(1.0 - clampf(_age / _grow_time, 0.0, 1.0), 2.5)
	var extent := _target * lerpf(0.08, 1.0, grow)
	size = Vector3(extent.x, DEPTH, extent.y)
	var dry := clampf(_age / DRY_TIME, 0.0, 1.0)
	var fade := clampf((_lifetime - _age) / FADE, 0.0, 1.0)
	modulate = Color(1.0, 1.0, 1.0).lerp(Color(0.55, 0.42, 0.42), dry)
	modulate.a = fade

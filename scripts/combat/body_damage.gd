class_name BodyDamage
extends Node

## Daño por partes del cuerpo, al estilo Kenshi: cabeza, pecho, vientre, brazos y piernas llevan su
## propia vida, aparte de la general (que sigue siendo la que mata). Cada golpe de combate cae en la
## parte cuyo tramo del esqueleto queda más cerca del punto por donde entra. Un tajo fuerte en un
## brazo o una pierna puede cercenarlo (Dismemberment), y toda herida sangra un rato restando vida
## general; un muñón sangra mucho más, a borbotones.
##
## Una parte por debajo de cero está inutilizada; las consecuencias (cojear, soltar el arma) y las
## curas llegarán después: de momento solo se curan con restore() (reaparecer, `heal`).

## Una parte ha recibido un golpe.
signal zone_damaged(zone: StringName)
## Una parte ha perdido un miembro.
signal limb_lost(zone: StringName, cut: Dictionary)

const ZONES: Array[StringName] = [&"head", &"chest", &"stomach", &"left_arm", &"right_arm",
		&"left_leg", &"right_leg"]
## Vida de cada parte, en fracción de la vida general.
const ZONE_HEALTH := {
	&"head": 0.5, &"chest": 1.0, &"stomach": 0.8,
	&"left_arm": 0.6, &"right_arm": 0.6, &"left_leg": 0.7, &"right_leg": 0.7,
}
## Tramos del esqueleto para saber dónde entra un golpe: [parte, hueso, hasta qué hueso, radio (m),
## hueso que se corta si lo cercena ("" si no se corta), altura del corte en ese hueso (-1: por
## donde entra el golpe)]. Un golpe en la mano o el pie corta la muñeca o el tobillo.
const SEGMENTS := [
	[&"head", "mixamorig_Neck", "mixamorig_Head", 0.06, "", -1.0],
	[&"head", "mixamorig_Head", "mixamorig_HeadTop_End", 0.1, "", -1.0],
	[&"chest", "mixamorig_Spine2", "mixamorig_Neck", 0.15, "", -1.0],
	[&"chest", "mixamorig_LeftShoulder", "mixamorig_LeftArm", 0.07, "", -1.0],
	[&"chest", "mixamorig_RightShoulder", "mixamorig_RightArm", 0.07, "", -1.0],
	[&"stomach", "mixamorig_Hips", "mixamorig_Spine1", 0.14, "", -1.0],
	[&"stomach", "mixamorig_Spine1", "mixamorig_Spine2", 0.13, "", -1.0],
	[&"left_arm", "mixamorig_LeftArm", "mixamorig_LeftForeArm", 0.05, "mixamorig_LeftArm", -1.0],
	[&"left_arm", "mixamorig_LeftForeArm", "mixamorig_LeftHand", 0.045, "mixamorig_LeftForeArm", -1.0],
	[&"left_arm", "mixamorig_LeftHand", "mixamorig_LeftHandMiddle2", 0.04, "mixamorig_LeftForeArm", 0.72],
	[&"right_arm", "mixamorig_RightArm", "mixamorig_RightForeArm", 0.05, "mixamorig_RightArm", -1.0],
	[&"right_arm", "mixamorig_RightForeArm", "mixamorig_RightHand", 0.045, "mixamorig_RightForeArm", -1.0],
	[&"right_arm", "mixamorig_RightHand", "mixamorig_RightHandMiddle2", 0.04, "mixamorig_RightForeArm", 0.72],
	[&"left_leg", "mixamorig_LeftUpLeg", "mixamorig_LeftLeg", 0.08, "mixamorig_LeftUpLeg", -1.0],
	[&"left_leg", "mixamorig_LeftLeg", "mixamorig_LeftFoot", 0.055, "mixamorig_LeftLeg", -1.0],
	[&"left_leg", "mixamorig_LeftFoot", "mixamorig_LeftToeBase", 0.045, "mixamorig_LeftLeg", 0.72],
	[&"right_leg", "mixamorig_RightUpLeg", "mixamorig_RightLeg", 0.08, "mixamorig_RightUpLeg", -1.0],
	[&"right_leg", "mixamorig_RightLeg", "mixamorig_RightFoot", 0.055, "mixamorig_RightLeg", -1.0],
	[&"right_leg", "mixamorig_RightFoot", "mixamorig_RightToeBase", 0.045, "mixamorig_RightLeg", 0.72],
]

## Probabilidad de que un tajo que cae en un brazo o una pierna lo cercene. Negativa: la natural
## (solo si deja el miembro por debajo de cero, y más cuanto más fuerte y más hondo). Alta mientras
## se prueba; `mutilar` en la consola la cambia.
static var sever_chance: float = 0.75
## Daño mínimo de un tajo (ya descontada la armadura) para poder cercenar.
const SEVER_MIN_DAMAGE := 14.0

## Sangrado de una herida por punto de daño (vida/s) según el tipo de golpe, y su vida media (s).
const BLEED_PER_DAMAGE := {
	ItemData.DamageKind.SLASH: 0.012, ItemData.DamageKind.PIERCE: 0.01, ItemData.DamageKind.BLUNT: 0.002,
}
const WOUND_HALF_LIFE := 12.0
## Un muñón: vida/s al principio, su vida media, y cada cuánto late un borbotón (s).
const STUMP_BLEED := 1.0
const STUMP_HALF_LIFE := 18.0
const PULSE := 0.32
## Por debajo de esto una herida ya no sangra.
const BLEED_STOP := 0.03
## Lo que gotea un muñón deja manchas en el suelo: una cada tanto (s), o antes si se ha movido esto
## (m), así que andando deja reguero.
const SPLAT_EVERY := 1.2
const SPLAT_STEP := 0.4

var health: HealthComponent
var skeleton: Skeleton3D
## El cuerpo que lleva el esqueleto (su velocidad y su gravedad las heredan los miembros que caen).
var owner_body: Node3D
var dismemberment: Dismemberment
## La última parte golpeada, para el HUD.
var last_zone: StringName = &""

var _hp := {}
## Miembros perdidos: parte → corte.
var _severed := {}
## Heridas abiertas: {rate (vida/s), half_life, cut (si es un muñón), pulse}.
var _wounds: Array[Dictionary] = []
var _bleed_debt := 0.0
var _bones := {}


func setup(health_: HealthComponent, skeleton_: Skeleton3D, body: Node3D) -> void:
	health = health_
	skeleton = skeleton_
	owner_body = body
	dismemberment = Dismemberment.new()
	dismemberment.name = "Dismemberment"
	dismemberment.skeleton = skeleton
	add_child(dismemberment)
	health.hit_received.connect(_on_hit)
	restore()


## Todo sano y entero otra vez.
func restore() -> void:
	for zone in ZONES:
		_hp[zone] = zone_max(zone)
	_severed.clear()
	_wounds.clear()
	_bleed_debt = 0.0
	last_zone = &""
	if dismemberment != null:
		dismemberment.restore()
	if owner_body != null:
		BloodStains.clear(owner_body)


func zone_max(zone: StringName) -> float:
	return (health.max_health if health != null else 100.0) * float(ZONE_HEALTH[zone])


## Vida de la parte en fracción de la suya: 1 sana, 0 inutilizada, -1 lo peor.
func zone_ratio(zone: StringName) -> float:
	return float(_hp[zone]) / zone_max(zone)


func is_severed(zone: StringName) -> bool:
	return _severed.has(zone)


func is_hurt() -> bool:
	for zone in ZONES:
		if _hp[zone] < zone_max(zone):
			return true
	return not _wounds.is_empty()


## Vida por segundo que se va en sangre.
func bleed_rate() -> float:
	var total := 0.0
	for wound in _wounds:
		total += wound.rate
	return total


## La parte del cuerpo que recibe un golpe que entra por [point] (mundo): {zone, cut_bone,
## fraction}, o {} si no hay esqueleto.
func locate(point: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	var xf := skeleton.global_transform
	for seg in SEGMENTS:
		var a_bone := _bone(seg[1])
		var b_bone := _bone(seg[2])
		if a_bone < 0 or b_bone < 0 or dismemberment.is_lost(a_bone):
			continue
		var a := xf * skeleton.get_bone_global_pose(a_bone).origin
		var b := xf * skeleton.get_bone_global_pose(b_bone).origin
		# Del hueso cortado solo queda hasta el corte.
		var c := dismemberment.cut_on(a_bone)
		if not c.is_empty():
			b = a.lerp(b, c.t)
		var d := Geometry3D.get_closest_point_to_segment(point, a, b).distance_to(point) - float(seg[3])
		if d < best_d:
			best_d = d
			best = {zone = seg[0], cut_bone = StringName(seg[4]), fraction = seg[5]}
	return best


## Cercena [zone] a propósito (consola, pruebas): por el brazo o el muslo si [upper], si no por el
## antebrazo o la pierna.
func sever_zone(zone: StringName, upper: bool) -> bool:
	if not ZONE_HEALTH.has(zone) or is_severed(zone) \
			or SettingsManager.gore_level() != SettingsManager.GORE_FULL:
		return false
	var side := "Left" if String(zone).begins_with("left") else "Right"
	var part := ""
	if String(zone).ends_with("arm"):
		part = "Arm" if upper else "ForeArm"
	elif String(zone).ends_with("leg"):
		part = "UpLeg" if upper else "Leg"
	else:
		return false
	var bone_name := StringName("mixamorig_" + side + part)
	var bone := _bone(bone_name)
	var tip := _bone(String(Dismemberment.CUTTABLE[bone_name][0]))
	var xf := skeleton.global_transform
	var point := (xf * skeleton.get_bone_global_pose(bone).origin).lerp(
			xf * skeleton.get_bone_global_pose(tip).origin, 0.55)
	var up := -_gravity().normalized()
	var blow := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	blow -= up * blow.dot(up)
	return _sever(zone, bone_name, -1.0, point, blow.normalized(), 1.0)


func _on_hit(info: DamageInfo, _applied: float) -> void:
	if skeleton == null or health.is_dead:
		return
	var hit := locate(info.point)
	if hit.is_empty():
		return
	var zone: StringName = hit.zone
	var amount := info.amount * info.part_multiplier * (1.0 - clampf(health.defense, 0.0, 80.0) / 100.0)
	_hp[zone] = maxf(_hp[zone] - amount, -zone_max(zone))
	last_zone = zone
	var rate := amount * float(BLEED_PER_DAMAGE.get(info.kind, 0.01))
	if rate > BLEED_STOP:
		_wounds.append({rate = rate, half_life = WOUND_HALF_LIFE})
	if hit.cut_bone != &"" and info.kind == ItemData.DamageKind.SLASH and amount >= SEVER_MIN_DAMAGE \
			and not is_severed(zone) and SettingsManager.gore_level() == SettingsManager.GORE_FULL:
		var chance := sever_chance if sever_chance >= 0.0 else _natural_chance(zone, amount)
		if randf() < chance:
			_sever(zone, hit.cut_bone, hit.fraction, info.point, info.direction, clampf(amount / 30.0, 0.6, 1.6))
	zone_damaged.emit(zone)


## Probabilidad natural: solo si el golpe deja el miembro por debajo de cero, y más cuanto más
## fuerte es y más hondo lo deja.
func _natural_chance(zone: StringName, amount: float) -> float:
	var hp: float = _hp[zone]
	if hp > 0.0:
		return 0.0
	var max_hp := zone_max(zone)
	return clampf(amount / max_hp * 0.3 + (-hp / max_hp) * 0.6, 0.0, 0.85)


func _sever(zone: StringName, bone: StringName, fraction: float, point: Vector3, blow: Vector3,
		power: float) -> bool:
	var down := _gravity()
	var up := -down.normalized()
	var flat := blow - up * blow.dot(up)
	var fling := flat.normalized() * randf_range(2.0, 3.5) * power + up * randf_range(1.2, 2.4)
	var velocity: Variant = owner_body.get(&"velocity")
	if velocity is Vector3:
		fling += velocity
	dismemberment.gravity = down
	var c := dismemberment.cut(bone, point, blow, fling, fraction)
	if c.is_empty():
		return false
	_severed[zone] = c
	_hp[zone] = -zone_max(zone)
	_wounds.append({rate = STUMP_BLEED, half_life = STUMP_HALF_LIFE, cut = c, pulse = 0.0})
	var ends := dismemberment.stump(c)
	CombatFx.sever_burst(owner_body, ends[0], ends[1])
	limb_lost.emit(zone, c)
	return true


func _process(delta: float) -> void:
	if health == null or health.is_dead or _wounds.is_empty():
		return
	var total := 0.0
	for wound in _wounds:
		wound.rate *= pow(0.5, delta / float(wound.half_life))
		total += wound.rate
		if wound.has("cut"):
			wound.pulse -= delta
			if wound.pulse <= 0.0:
				wound.pulse = PULSE * randf_range(0.85, 1.15)
				var ends := dismemberment.stump(wound.cut)
				var strength := clampf(wound.rate / STUMP_BLEED, 0.0, 1.0)
				CombatFx.spurt(owner_body, ends[0], ends[1], strength)
				_drip_on_ground(wound, ends[0], strength)
	_wounds = _wounds.filter(func(wound: Dictionary) -> bool: return wound.rate > BLEED_STOP)
	_bleed_debt += total * delta
	if _bleed_debt >= 1.0:
		var amount := floorf(_bleed_debt)
		_bleed_debt -= amount
		health.take_damage(amount)


## Mancha en el suelo bajo el muñón de [wound], si toca (ver SPLAT_EVERY).
func _drip_on_ground(wound: Dictionary, point: Vector3, strength: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var last: float = wound.get("splat_time", -INF)
	var moved := point.distance_to(wound.get("splat_at", point)) if wound.has("splat_at") else INF
	if now - last < SPLAT_EVERY and moved < SPLAT_STEP:
		return
	var splat := BloodPool.spawn(owner_body, point, _gravity(), lerpf(0.3, 0.65, strength), 0.25,
			dismemberment.world_mask, true)
	if splat != null:
		wound.splat_time = now
		wound.splat_at = point


func _gravity() -> Vector3:
	var direction: Variant = owner_body.get(&"gravity_direction") if owner_body != null else null
	if not direction is Vector3:
		return Vector3(0, -9.8, 0)
	var strength := 9.8
	var planet: Variant = owner_body.get(&"planet")
	if planet is Object and is_instance_valid(planet) and &"gravity_strength" in planet:
		strength = planet.gravity_strength
	return (direction as Vector3).normalized() * strength


func _bone(bone_name: String) -> int:
	if not _bones.has(bone_name):
		_bones[bone_name] = skeleton.find_bone(bone_name)
	return _bones[bone_name]

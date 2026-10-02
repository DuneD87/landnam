class_name AnimalGore
extends Node

## Mutilaciones de los animales al morir: el golpe que lo mata (un tajo, o un porrazo muy fuerte)
## puede cortarle el tramo de pata, el cuello o la cola más cercano a donde entra. Lo cortado cae
## de una pieza (Dismemberment con rigid_parts → SeveredChunk) y el muñón queda tapado. Al volver
## del pool el animal está entero.
##
## Cada esqueleto trae su tabla, en el formato de Dismemberment.CUTTABLE; se elige la primera cuyos
## huesos tenga el esqueleto.

## Probabilidad de cortar con el golpe que mata.
static var sever_chance := 0.5
## Daño mínimo del golpe; un golpe que pincha (flecha, lanza) necesita bastante más.
const MIN_DAMAGE := 14.0
const PIERCE_MIN_DAMAGE := 45.0
## El golpe tiene que haber llegado justo antes de morir (s).
const HIT_WINDOW := 0.3
## Velocidad con la que sale lo cortado (m/s): en la dirección del golpe y algo hacia arriba.
const FLING := 3.5
const FLING_UP := 2.0

const TABLES := [
	# Oso (Rig*).
	{
		&"RigLFLeg1": [&"RigLFLeg2", Vector2(0.4, 0.75), 16.0],
		&"RigLFLeg2": [&"RigLFLegAnkle", Vector2(0.3, 0.75), 22.0],
		&"RigRFLeg1": [&"RigRFLeg2", Vector2(0.4, 0.75), 16.0],
		&"RigRFLeg2": [&"RigRFLegAnkle", Vector2(0.3, 0.75), 22.0],
		&"RigLBLeg1": [&"RigLBLeg2", Vector2(0.45, 0.75), 16.0],
		&"RigLBLeg2": [&"RigLBLegAnkle", Vector2(0.3, 0.75), 22.0],
		&"RigRBLeg1": [&"RigRBLeg2", Vector2(0.45, 0.75), 16.0],
		&"RigRBLeg2": [&"RigRBLegAnkle", Vector2(0.3, 0.75), 22.0],
		&"RigNeck2": [&"RigHead", Vector2(0.2, 0.8), 18.0],
		&"RigTail1": [&"RigTail2", Vector2(0.3, 0.8), 20.0],
	},
	# Ciervo y búfalo (mismo rig).
	{
		&"LegFL1": [&"LegFL2", Vector2(0.4, 0.75), 16.0],
		&"LegFL2": [&"LegFL3", Vector2(0.3, 0.75), 22.0],
		&"LegFR1": [&"LegFR2", Vector2(0.4, 0.75), 16.0],
		&"LegFR2": [&"LegFR3", Vector2(0.3, 0.75), 22.0],
		&"LegBL1": [&"LegBL2", Vector2(0.45, 0.75), 16.0],
		&"LegBL2": [&"LegBL3", Vector2(0.3, 0.75), 22.0],
		&"LegBR1": [&"LegBR2", Vector2(0.45, 0.75), 16.0],
		&"LegBR2": [&"LegBR3", Vector2(0.3, 0.75), 22.0],
		&"Neck2": [&"Neck3", Vector2(0.2, 0.8), 18.0],
		&"Tail1": [&"Tail2", Vector2(0.3, 0.8), 20.0],
	},
	# León (patas con nombres de brazo y pierna).
	{
		&"LeftArm": [&"LeftForeArm", Vector2(0.4, 0.75), 16.0],
		&"LeftForeArm": [&"LeftHand", Vector2(0.3, 0.75), 22.0],
		&"RightArm": [&"RightForeArm", Vector2(0.4, 0.75), 16.0],
		&"RightForeArm": [&"RightHand", Vector2(0.3, 0.75), 22.0],
		&"LeftUpLeg": [&"LeftLeg", Vector2(0.45, 0.75), 16.0],
		&"LeftLeg": [&"LeftFoot", Vector2(0.3, 0.75), 22.0],
		&"RightUpLeg": [&"RightLeg", Vector2(0.45, 0.75), 16.0],
		&"RightLeg": [&"RightFoot", Vector2(0.3, 0.75), 22.0],
		&"Neck02": [&"Neck03", Vector2(0.2, 0.8), 18.0],
		&"Tail01": [&"Tail02", Vector2(0.3, 0.8), 20.0],
	},
]

var npc: Node3D
var dismemberment: Dismemberment
var _last_hit: DamageInfo
var _last_hit_time := -INF


## Prepara [body] (NPCController) si su esqueleto tiene tabla; si no, null.
static func attach(body: Node3D, model: Node3D, health: HealthComponent) -> AnimalGore:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return null
	var skeleton := skeletons[0] as Skeleton3D
	var table: Dictionary = {}
	for candidate: Dictionary in TABLES:
		var complete := true
		for bone: StringName in candidate:
			if skeleton.find_bone(bone) < 0 or skeleton.find_bone(candidate[bone][0]) < 0:
				complete = false
				break
		if complete:
			table = candidate
			break
	if table.is_empty():
		return null
	var gore := AnimalGore.new()
	gore.name = "AnimalGore"
	gore.npc = body
	body.add_child(gore)
	var dm := Dismemberment.new()
	dm.name = "Dismemberment"
	dm.skeleton = skeleton
	dm.cuttable = table
	dm.rigid_parts = true
	dm.frame_node = model
	dm.world_mask = 1
	dm.exclude_body = body as PhysicsBody3D
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.skin != null:
			dm.capped.append(mi)
	gore.add_child(dm)
	gore.dismemberment = dm
	health.hit_received.connect(gore._on_hit)
	health.died.connect(gore._on_died)
	return gore


## Golpe sin DamageInfo (un cañonazo que lo mata de una): cuenta como un porrazo enorme en [point].
func note_blast(point: Vector3) -> void:
	var info := DamageInfo.new()
	info.amount = 999.0
	info.point = point
	info.kind = ItemData.DamageKind.BLUNT
	info.direction = (npc.global_position - point).normalized()
	_on_hit(info, 999.0)


## Vuelve a estar entero (al salir del pool).
func reset() -> void:
	dismemberment.restore()
	_last_hit = null
	_last_hit_time = -INF


func _on_hit(info: DamageInfo, _applied: float) -> void:
	_last_hit = info
	_last_hit_time = Time.get_ticks_msec() / 1000.0


func _on_died() -> void:
	var info := _last_hit
	if info == null or Time.get_ticks_msec() / 1000.0 - _last_hit_time > HIT_WINDOW:
		return
	if SettingsManager.gore_level() != SettingsManager.GORE_FULL or randf() >= sever_chance:
		return
	var needed := PIERCE_MIN_DAMAGE if info.kind == ItemData.DamageKind.PIERCE else MIN_DAMAGE
	if info.amount < needed:
		return
	var bone := _nearest(info.point)
	if bone == &"":
		return
	# La gravedad con la que camina el animal.
	var g: Variant = npc.get(&"gravity_direction")
	if not g is Vector3 or (g as Vector3).length_squared() < 1e-6:
		return
	var gravity := (g as Vector3).normalized() * 9.8
	dismemberment.gravity = gravity
	var blow := info.direction if info.direction.length_squared() > 1e-6 else -gravity.normalized()
	var fling := blow.normalized() * FLING - gravity.normalized() * FLING_UP
	if not dismemberment.cut(bone, info.point, blow, fling).is_empty():
		CombatFx.sever_burst(npc, info.point, -gravity.normalized())


## El hueso de la tabla cuyo tramo pasa más cerca de [point] (mundo).
func _nearest(point: Vector3) -> StringName:
	var skel := dismemberment.skeleton
	var best := &""
	var best_d := INF
	for bone: StringName in dismemberment.cuttable:
		var a := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone)).origin
		var b := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(dismemberment.cuttable[bone][0])).origin
		var d := Geometry3D.get_closest_point_to_segment(point, a, b).distance_to(point)
		if d < best_d:
			best_d = d
			best = bone
	return best

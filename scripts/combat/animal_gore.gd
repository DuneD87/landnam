class_name AnimalGore
extends Node

## Mutilaciones de los animales al morir: el golpe que lo mata (un tajo, o un porrazo muy fuerte)
## puede cortarle el tramo de pata, el cuello o la cola más cercano a donde entra. Lo cortado cae
## de una pieza (Dismemberment con rigid_parts → SeveredChunk) y el muñón queda tapado. Al volver
## del pool el animal está entero.
##
## Cada esqueleto trae su tabla, en el formato de Dismemberment.CUTTABLE; se elige la primera cuyos
## huesos tenga el esqueleto, y si no hay ninguna se saca de sus huesos (_auto_table: cada pata por
## arriba y por abajo, el cuello y la cola).
##
## Al despiezarlo (Butchering) se le cortan, de uno en uno, los miembros que le queden
## (butcher_cuts, butcher_cut): cada pata por arriba, el cuello y la cola.

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
## Al despiezarlo, lo cortado sale con un empujón suave, apartándose del cuerpo (m/s; cada vez
## entre BUTCHER_JITTER veces eso).
const BUTCHER_FLING := 1.6
const BUTCHER_FLING_UP := 1.3
const BUTCHER_JITTER := Vector2(0.8, 1.2)
## Tabla sacada de los huesos: los pies son las hojas por debajo de esta parte del alto; dos son
## de la misma pata (las pezuñas y los dedos) si se juntan por debajo de esta otra parte del alto.
## Cada pata se corta arriba y abajo a estas partes de su largo, desde donde sale del cuerpo.
const AUTO_FEET := 0.2
const AUTO_SAME_LEG := 0.5
const AUTO_UPPER := 0.3
const AUTO_LOWER := 0.65

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
		table = _auto_table(skeleton, body)
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


## Los miembros que se le pueden cortar al despiezarlo: de cada pata, el corte de más arriba, el
## cuello y la cola, salvo los que ya ha perdido (del todo o en parte: lo que queda de una pata ya
## cortada no se vuelve a cortar).
func butcher_cuts() -> Array[StringName]:
	var skel := dismemberment.skeleton
	var out: Array[StringName] = []
	for bone: StringName in dismemberment.cuttable:
		var b := skel.find_bone(bone)
		var top := true
		for other: StringName in dismemberment.cuttable:
			if other != bone and _descends(skel, b, skel.find_bone(other)):
				top = false
				break
		if not top or dismemberment.is_lost(b):
			continue
		var touched := false
		for c in dismemberment.cuts():
			if c.bone == b or _descends(skel, c.bone, b):
				touched = true
				break
		if not touched:
			out.append(bone)
	return out


## Dónde iría el corte de [bone] (mundo): a media altura de su tramo.
func butcher_point(bone: StringName) -> Vector3:
	var skel := dismemberment.skeleton
	var spec: Array = dismemberment.cuttable[bone]
	var a := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone)).origin
	var b := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(spec[0])).origin
	var span: Vector2 = spec[1]
	return a.lerp(b, (span.x + span.y) * 0.5)


## Corta [bone] (uno de butcher_cuts) al despiezarlo: lo cortado sale con un empujón suave,
## apartándose de [center], y cae junto al cuerpo. Devuelve el corte, o {} si no se ha podido.
func butcher_cut(bone: StringName, center: Vector3) -> Dictionary:
	var g: Variant = npc.get(&"gravity_direction")
	if not g is Vector3 or (g as Vector3).length_squared() < 1e-6:
		return {}
	var down := (g as Vector3).normalized()
	dismemberment.gravity = down * 9.8
	var spec: Array = dismemberment.cuttable[bone]
	var span: Vector2 = spec[1]
	var point := butcher_point(bone)
	var away := point - center
	away -= down * away.dot(down)
	away = away.normalized() if away.length_squared() > 1e-6 else -down
	var fling := (away * BUTCHER_FLING - down * BUTCHER_FLING_UP) * randf_range(BUTCHER_JITTER.x, BUTCHER_JITTER.y)
	return dismemberment.cut(bone, point, away, fling, (span.x + span.y) * 0.5)


static func _descends(skel: Skeleton3D, bone: int, ancestor: int) -> bool:
	var parent := skel.get_bone_parent(bone)
	while parent >= 0:
		if parent == ancestor:
			return true
		parent = skel.get_bone_parent(parent)
	return false


## La tabla de cortes de un esqueleto sin la suya, sacada de sus huesos en reposo, con [body] de pie
## (+Y arriba): el cuello justo antes de la cabeza (el hueso que acaba en "head" con más huesos
## debajo), la cola en su raíz (la rama "tail" con más huesos) y cada pata (lo que baja hasta el
## suelo desde el camino de la raíz a la cabeza) por arriba y por abajo. {} si no encuentra patas.
static func _auto_table(skel: Skeleton3D, body: Node3D) -> Dictionary:
	var count := skel.get_bone_count()
	if count == 0:
		return {}
	# Del esqueleto al cuerpo, por los padres (puede no estar aún en el árbol).
	var to_body := Transform3D.IDENTITY
	var node: Node = skel
	while node != null and node != body:
		if node is Node3D:
			to_body = (node as Node3D).transform * to_body
		node = node.get_parent()
	var pos := PackedVector3Array()
	pos.resize(count)
	for b in count:
		pos[b] = to_body * skel.get_bone_global_rest(b).origin
	var head := -1
	var best := -1
	for b in count:
		var name := skel.get_bone_name(b).to_lower()
		if not name.ends_with("head") or name.contains("end") or name.contains("slider"):
			continue
		var below := 0
		for c in count:
			if _descends(skel, c, b):
				below += 1
		if below > best:
			best = below
			head = b
	if head < 0 or skel.get_bone_parent(head) < 0:
		return {}
	var spine := {}
	var at := head
	while at >= 0:
		spine[at] = true
		at = skel.get_bone_parent(at)
	var table := {}
	table[StringName(skel.get_bone_name(skel.get_bone_parent(head)))] = [StringName(skel.get_bone_name(head)), Vector2(0.2, 0.8), 18.0]
	# La cola: la raíz de la rama "tail" con más huesos.
	var tail := -1
	best = -1
	for b in count:
		var parent := skel.get_bone_parent(b)
		if not skel.get_bone_name(b).to_lower().contains("tail") or \
				(parent >= 0 and skel.get_bone_name(parent).to_lower().contains("tail")):
			continue
		var below := 0
		for c in count:
			if _descends(skel, c, b):
				below += 1
		if below > best:
			best = below
			tail = b
	if tail >= 0:
		for child in skel.get_bone_children(tail):
			if skel.get_bone_name(child).to_lower().contains("tail"):
				table[StringName(skel.get_bone_name(tail))] = [StringName(skel.get_bone_name(child)), Vector2(0.3, 0.8), 20.0]
				break
	# Los pies: hojas cerca del suelo, juntadas si se unen abajo (una pata, varios dedos); las patas
	# de un par pueden ir muy juntas, así que no vale la distancia.
	var low := INF
	var high := -INF
	for b in count:
		low = minf(low, pos[b].y)
		high = maxf(high, pos[b].y)
	var height := high - low
	var groups: Array[Array] = []
	for b in count:
		if not skel.get_bone_children(b).is_empty() or pos[b].y > low + height * AUTO_FEET or spine.has(b):
			continue
		var joined := false
		for group in groups:
			var common := _common_ancestor(skel, group[0], b)
			if common >= 0 and not spine.has(common) and pos[common].y < low + height * AUTO_SAME_LEG:
				group.append(b)
				joined = true
				break
		if not joined:
			groups.append([b])
	var legs := 0
	for group in groups:
		# El tobillo: el antepasado común de los dedos; de ahí arriba hasta el camino de la cabeza,
		# sin pasar por donde salen otras patas.
		var ankle: int = group[0]
		for b: int in group:
			while ankle >= 0 and b != ankle and not _descends(skel, b, ankle):
				ankle = skel.get_bone_parent(ankle)
		var chain: Array[int] = []
		at = ankle
		while at >= 0 and not spine.has(at):
			var shared := false
			for other in groups:
				if other != group and _descends(skel, other[0], at):
					shared = true
			if shared:
				break
			chain.push_front(at)
			at = skel.get_bone_parent(at)
		if chain.size() < 3:
			continue
		var names := chain.map(func(b: int) -> String: return skel.get_bone_name(b).to_lower())
		if names.any(func(n: String) -> bool: return n.contains("tail")):
			continue
		var lengths: Array[float] = []
		var total := 0.0
		for i in chain.size() - 1:
			lengths.append(pos[chain[i]].distance_to(pos[chain[i + 1]]))
			total += lengths[-1]
		var upper := _bone_at(lengths, total * AUTO_UPPER)
		var lower := _bone_at(lengths, total * AUTO_LOWER)
		table[StringName(skel.get_bone_name(chain[upper]))] = [StringName(skel.get_bone_name(chain[upper + 1])), Vector2(0.4, 0.75), 16.0]
		if lower != upper:
			table[StringName(skel.get_bone_name(chain[lower]))] = [StringName(skel.get_bone_name(chain[lower + 1])), Vector2(0.3, 0.75), 22.0]
		legs += 1
	return table if legs > 0 else {}


## El primer hueso del que cuelgan [a] y [b] (o uno de ellos), o -1.
static func _common_ancestor(skel: Skeleton3D, a: int, b: int) -> int:
	var at := a
	while at >= 0:
		if at == b or _descends(skel, b, at):
			return at
		at = skel.get_bone_parent(at)
	return -1


## El tramo de la cadena ([lengths] de cada uno) en el que cae [along] (m desde arriba).
static func _bone_at(lengths: Array[float], along: float) -> int:
	var sum := 0.0
	for i in lengths.size():
		sum += lengths[i]
		if along <= sum:
			return i
	return lengths.size() - 1


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

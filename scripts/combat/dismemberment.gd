class_name Dismemberment
extends Node

## Miembros cercenados de un esqueleto. Corta todas sus mallas con piel (cuerpo y armadura) por el
## plano de cada corte (LimbCutter), tapa el muñón y suelta lo cortado como un SeveredLimb.
##
## Los cortes se guardan en el marco de su hueso, así que se rehacen solos cuando alguien cambia una
## malla (la armadura se reajusta al cuerpo, el aspecto se vuelve a hornear, se viste otra pieza):
## mientras haya cortes, cada fotograma mira si alguna malla ya no es la que dejó cortada y la vuelve
## a cortar desde la nueva. Cortar va en un hilo; leer y montar las mallas, en el principal. Un
## guante de una mano que ya no está se queda sin triángulos, así que no se ve.
##
## Cada miembro se corta una sola vez: el brazo o la pierna que ya ha perdido algo no se vuelve a
## cortar más arriba.

## Lo cortado ya ha caído y el muñón ya está tapado ([limb]: SeveredLimb, o SeveredChunk con
## rigid_parts).
signal limb_dropped(cut: Dictionary, limb: Node3D)

## Huesos que se pueden cortar: [hueso hacia el que apunta, tramo del hueso por el que puede ir el
## corte (fracción), inclinación máxima del corte (grados)]. Los tramos dejan lejos las
## articulaciones, donde los pesos de la piel se mezclan con el hueso de al lado; los de arriba se
## inclinan menos para no rozar el tronco (axila, ingle). Lo que cae lo mueve un Ragdoll con sus
## segmentos (radios y masas los suyos).
const CUTTABLE := {
	&"mixamorig_LeftArm": [&"mixamorig_LeftForeArm", Vector2(0.4, 0.7), 14.0],
	&"mixamorig_LeftForeArm": [&"mixamorig_LeftHand", Vector2(0.3, 0.75), 22.0],
	&"mixamorig_RightArm": [&"mixamorig_RightForeArm", Vector2(0.4, 0.7), 14.0],
	&"mixamorig_RightForeArm": [&"mixamorig_RightHand", Vector2(0.3, 0.75), 22.0],
	&"mixamorig_LeftUpLeg": [&"mixamorig_LeftLeg", Vector2(0.45, 0.7), 14.0],
	&"mixamorig_LeftLeg": [&"mixamorig_LeftFoot", Vector2(0.3, 0.75), 22.0],
	&"mixamorig_RightUpLeg": [&"mixamorig_RightLeg", Vector2(0.45, 0.7), 14.0],
	&"mixamorig_RightLeg": [&"mixamorig_RightFoot", Vector2(0.3, 0.75), 22.0],
}

## Meta de las mallas que no se cortan nunca (pelo, ojos, dientes...: no llegan a los miembros).
const NO_CUT_META := &"no_dismember"
const CAP_META := &"stump_cap"
const STUMP_SHADER := preload("res://shaders/combat/stump_flesh.gdshader")

var skeleton: Skeleton3D
## Qué se puede cortar (como CUTTABLE, que es lo del jugador): los animales traen su tabla.
var cuttable: Dictionary = CUTTABLE
## Lo cortado cae de una pieza (SeveredChunk) en vez de como muñeco de trapo (SeveredLimb, que
## necesita los segmentos humanos de Ragdoll).
var rigid_parts := false
## Mallas que llevan tapa en el muñón (el cuerpo); la armadura solo se corta.
var capped: Array[MeshInstance3D] = []
## Para lo que cae: el marco del cuerpo (+Z adelante, hacia dónde doblan codos y rodillas; ver
## Ragdoll.frame_node), gravedad (mundo), máscara del suelo y cuerpo que no debe tocar.
var frame_node: Node3D
## La del cuerpo (la pone el dueño). Sin ella lo cortado no cae: se queda sin soltar.
var gravity := Vector3.ZERO
var world_mask := 1
var exclude_body: PhysicsBody3D

var _cuts: Array[Dictionary] = []
## MeshInstance3D → {source (la malla sin cortar), result (la que dejó puesta), pending (cortes en
## marcha), stale (hay que volver a cortarla cuando acaben)}.
var _entries := {}
## Malla sin cortar → lo leído de ella (LimbCutter.source).
var _sources := {}
## MeshInstance3D con tapa → sus tapas.
var _caps := {}
## Skin → hueso del esqueleto de cada bind.
var _skin_bones := {}
var _jobs: Array[Dictionary] = []
## Sube al restaurar: lo que estuviera cortándose ya no vale.
var _generation := 0
## Cuenta atrás para leer por adelantado la siguiente malla (ver _prewarm).
var _prewarm_wait := 0.0
## Mallas sueltas pegadas a lo cortado (cuernos en la cabeza) que se han escondido: se van con el
## trozo y vuelven al restaurar.
var _hidden: Array[Node3D] = []

static var _stump_material: ShaderMaterial


func _ready() -> void:
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for job in _jobs:
			WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.clear()


## Corta [bone_name] (uno de CUTTABLE) por donde ha entrado el golpe ([hit], mundo), inclinado hacia
## donde iba ([blow]); lo cortado sale con [fling] (m/s). [fraction] fuerza la altura del corte en
## el hueso (0 su articulación, 1 la siguiente). Devuelve el corte, o {} si ese miembro ya había
## perdido algo.
func cut(bone_name: StringName, hit: Vector3, blow: Vector3, fling: Vector3, fraction := -1.0) -> Dictionary:
	if skeleton == null or not cuttable.has(bone_name):
		return {}
	var spec: Array = cuttable[bone_name]
	var bone := skeleton.find_bone(bone_name)
	var tip := skeleton.find_bone(spec[0])
	if bone < 0 or tip < 0:
		return {}
	for other in _cuts:
		if other.bone == bone or _descends(bone, other.bone) or _descends(other.bone, bone):
			return {}
	var pose := skeleton.get_bone_global_pose(bone)
	var to_tip := pose.affine_inverse() * skeleton.get_bone_global_pose(tip).origin
	var length := to_tip.length()
	if length < 1e-5:
		return {}
	var axis := to_tip / length
	var span: Vector2 = spec[1]
	var t := fraction
	if t < 0.0:
		t = ((skeleton.global_transform * pose).affine_inverse() * hit).dot(axis) / length
	t = clampf(t, span.x, span.y)
	# Inclinado hacia donde iba el golpe: el tajo entra por un lado y sale algo más abajo por el otro.
	var across := (skeleton.global_transform.basis * pose.basis).inverse() * blow
	across -= axis * across.dot(axis)
	if across.length_squared() < 1e-10:
		across = axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT)
	var tilt := deg_to_rad(randf_range(0.35, 1.0) * float(spec[2]))
	var new_cut := {
		bone = bone,
		name = bone_name,
		t = t,
		origin = axis * length * t,
		normal = (axis * cos(tilt) + across.normalized() * sin(tilt)).normalized(),
		fling = fling,
	}
	_cuts.append(new_cut)
	for entry: Dictionary in _entries.values():
		entry.stale = true
	_queue(_candidates(), new_cut)
	return new_cut


func cuts() -> Array[Dictionary]:
	return _cuts


## El hueso [bone] se ha ido con algún corte (cuelga de un hueso cortado).
func is_lost(bone: int) -> bool:
	for c in _cuts:
		if _descends(bone, c.bone):
			return true
	return false


## El corte que pasa por el hueso [bone], o {}.
func cut_on(bone: int) -> Dictionary:
	for c in _cuts:
		if c.bone == bone:
			return c
	return {}


## Nombres de los huesos que se han ido con los cortes (para que el muñeco no los simule).
func lost_bone_names() -> PackedStringArray:
	var names := PackedStringArray()
	if skeleton == null:
		return names
	for b in skeleton.get_bone_count():
		if is_lost(b):
			names.append(skeleton.get_bone_name(b))
	return names


## Punto (mundo) del muñón de [c] y hacia dónde mira.
func stump(c: Dictionary) -> Array:
	var xf := skeleton.global_transform * skeleton.get_bone_global_pose(c.bone)
	return [xf * (c.origin as Vector3), (xf.basis * (c.normal as Vector3)).normalized()]


## Vuelve a poner cada malla entera y quita los cortes y las tapas.
func restore() -> void:
	_generation += 1
	for inst in _entries:
		var entry: Dictionary = _entries[inst]
		if is_instance_valid(inst) and entry.source != null and inst.mesh == entry.result:
			inst.mesh = entry.source
	for list in _caps.values():
		for cap in list:
			if is_instance_valid(cap):
				cap.queue_free()
	_entries.clear()
	_caps.clear()
	_cuts.clear()
	for node in _hidden:
		if is_instance_valid(node):
			node.visible = true
	_hidden.clear()


func _process(_delta: float) -> void:
	for job in _jobs.duplicate():
		if not WorkerThreadPool.is_task_completed(job.task):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.erase(job)
		_finish(job)
	if _cuts.is_empty():
		_prewarm(_delta)
		return
	var stale: Array[MeshInstance3D] = []
	for inst in _candidates():
		var entry: Dictionary = _entries.get(inst, {})
		if entry.is_empty() or (entry.pending == 0 and (entry.stale or inst.mesh != entry.result)):
			stale.append(inst)
	if not stale.is_empty():
		_queue(stale, {})
	for inst in _entries.keys():
		if not is_instance_valid(inst) or not skeleton.is_ancestor_of(inst):
			_forget(inst)
	for inst in _caps:
		if is_instance_valid(inst):
			for cap in _caps[inst]:
				if is_instance_valid(cap):
					cap.visible = inst.visible


## Lee por adelantado, de una en una y sin prisa, las mallas que se podrían cortar: leer los arrays
## de una malla los trae de la GPU y frena ese fotograma, y mejor que no sea el del tajo. Olvida las
## que ya no lleva nadie (armadura quitada).
func _prewarm(delta: float) -> void:
	_prewarm_wait -= delta
	if _prewarm_wait > 0.0 or skeleton == null:
		return
	_prewarm_wait = 1.0
	var worn := {}
	var missing: MeshInstance3D = null
	for inst in _candidates():
		worn[inst.mesh] = true
		if missing == null and not _sources.has(inst.mesh):
			missing = inst
	for mesh in _sources.keys():
		if not worn.has(mesh):
			_sources.erase(mesh)
	if missing != null:
		_sources[missing.mesh] = LimbCutter.source(missing.mesh, missing)


## Mallas con piel del esqueleto que se pueden cortar.
func _candidates() -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if skeleton == null:
		return found
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.skin == null or not (mi.mesh is ArrayMesh) or mi.has_meta(NO_CUT_META) or mi.has_meta(CAP_META):
			continue
		found.append(mi)
	return found


## Una malla que ha salido del esqueleto (armadura quitada): vuelve a estar entera.
func _forget(inst: Object) -> void:
	var entry: Dictionary = _entries[inst]
	if is_instance_valid(inst) and entry.source != null and (inst as MeshInstance3D).mesh == entry.result:
		(inst as MeshInstance3D).mesh = entry.source
	_entries.erase(inst)
	for cap in _caps.get(inst, []):
		if is_instance_valid(cap):
			cap.queue_free()
	_caps.erase(inst)


## Lanza en un hilo el corte de [instances] con todos los cortes; [new_cut] es el que acaba de
## pasar, del que hay que sacar el miembro. Si una malla ya se estaba cortando (dos tajos casi a la
## vez), se corta igual para sacar el miembro nuevo, y al acabar todo se vuelve a cortar una vez
## más: los resultados pueden llegar en cualquier orden.
func _queue(instances: Array[MeshInstance3D], new_cut: Dictionary) -> void:
	var items := []
	for inst in instances:
		if not _entries.has(inst):
			_entries[inst] = {source = null, result = null, pending = 0, stale = true}
		var entry: Dictionary = _entries[inst]
		if entry.pending > 0 and new_cut.is_empty():
			entry.stale = true
			continue
		# Ni la que dejó cortada ni la de antes: alguien ha puesto otra malla.
		if inst.mesh != entry.result and inst.mesh != entry.source:
			entry.source = inst.mesh
		entry.stale = entry.pending > 0
		var source: ArrayMesh = entry.source
		if not _sources.has(source):
			_sources[source] = LimbCutter.source(source, inst)
		var specs := []
		for c in _cuts:
			specs.append(_spec(inst.skin, c))
		items.append({
			instance = inst, expect = inst.mesh, source = source, data = _sources[source],
			specs = specs, capped = capped.has(inst),
			new_index = _cuts.find(new_cut) if not new_cut.is_empty() else -1,
			# Lo que cae de una pieza se hornea en el hilo, en la pose del corte.
			pose = SeveredChunk.pose_matrices(inst.skin, skeleton) if rigid_parts and not new_cut.is_empty() else [],
		})
		entry.pending += 1
	if items.is_empty():
		return
	var job := {items = items, cut = new_cut, generation = _generation}
	job.task = WorkerThreadPool.add_task(_run.bind(job), false, "Dismemberment")
	_jobs.append(job)
	set_process(true)


## El corte [c] visto desde la piel [skin]: qué binds son del hueso cortado y cuáles cuelgan de él,
## y cómo llevar cada uno al marco del hueso cortado (ver LimbCutter.cut()).
func _spec(skin: Skin, c: Dictionary) -> Dictionary:
	if not _skin_bones.has(skin):
		var bones := PackedInt32Array()
		bones.resize(skin.get_bind_count())
		for b in skin.get_bind_count():
			var bind_name := skin.get_bind_name(b)
			bones[b] = skeleton.find_bone(bind_name) if bind_name != &"" else skin.get_bind_bone(b)
		_skin_bones[skin] = bones
	var skin_bones: PackedInt32Array = _skin_bones[skin]
	var marks := PackedByteArray()
	marks.resize(skin_bones.size())
	var to_bone := []
	to_bone.resize(skin_bones.size())
	var bind := -1
	for b in skin_bones.size():
		var bone := skin_bones[b]
		to_bone[b] = Transform3D.IDENTITY
		if bone == c.bone:
			marks[b] = LimbCutter.OWN
			to_bone[b] = skin.get_bind_pose(b)
			if bind < 0:
				bind = b
		elif bone >= 0 and _descends(bone, c.bone):
			marks[b] = LimbCutter.BELOW
			to_bone[b] = _straight(bone, c.bone) * skin.get_bind_pose(b)
	return {marks = marks, to_bone = to_bone, bind = bind, origin = c.origin, normal = c.normal}


## Marco de [bone] en el de su antepasado [ancestor] con las articulaciones de en medio en su giro
## de reposo (el miembro estirado) pero en su sitio de ahora, que lleva las proporciones del cuerpo
## (BodyProportions mueve las articulaciones; el giro de un hueso no mueve las suyas).
func _straight(bone: int, ancestor: int) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var current := bone
	while current >= 0 and current != ancestor:
		var parent := skeleton.get_bone_parent(current)
		var at := (skeleton.get_bone_global_pose(parent).affine_inverse() * skeleton.get_bone_global_pose(current)).origin
		xf = Transform3D(skeleton.get_bone_rest(current).basis, at) * xf
		current = parent
	return xf


## En el hilo: cada malla, cortada por todos los cortes uno tras otro (no se solapan: cada uno es
## de un miembro distinto).
func _run(job: Dictionary) -> void:
	for item: Dictionary in job.items:
		var surfaces: Array = item.data.surfaces
		var caps := []
		var severed := []
		var severed_cap: Variant = null
		var touched := false
		for ci in item.specs.size():
			var is_new: bool = ci == item.new_index
			var next := []
			var cap: Variant = null
			for surface: Dictionary in surfaces:
				var r := LimbCutter.cut(surface, item.specs[ci], is_new, item.capped)
				if not r.touched:
					next.append(surface)
					continue
				touched = true
				next.append(r.kept)
				if is_new:
					severed.append(r.severed)
					if r.has("cap_severed"):
						severed_cap = r.cap_severed
				if r.has("cap_kept"):
					cap = r.cap_kept
			surfaces = next
			caps.append(cap)
		var pose: Array[Transform3D] = []
		pose.assign(item.pose)
		if not pose.is_empty():
			severed = severed.map(func(surface: Dictionary) -> Dictionary: return SeveredChunk.bake_surface(surface, pose))
			if severed_cap != null:
				severed_cap = SeveredChunk.bake_surface(severed_cap, pose)
		item.result = {
			touched = touched, surfaces = surfaces, caps = caps, severed = severed,
			severed_cap = severed_cap, baked = not pose.is_empty(),
		}


## En el hilo principal: pone las mallas cortadas, las tapas y suelta el miembro.
func _finish(job: Dictionary) -> void:
	var current: bool = job.generation == _generation
	var parts := []
	for item: Dictionary in job.items:
		var inst: MeshInstance3D = item.instance
		if not is_instance_valid(inst):
			continue
		var entry: Dictionary = _entries.get(inst, {})
		if not entry.is_empty():
			entry.pending -= 1
		if not current or entry.is_empty():
			continue
		var res: Dictionary = item.result
		var data: Dictionary = item.data
		# Si la malla ha cambiado mientras tanto (otro corte, la armadura), la siguiente pasada la
		# vuelve a cortar; el miembro sale igual.
		if inst.mesh == item.expect:
			if res.touched:
				inst.mesh = LimbCutter.build(res.surfaces, data.blend_names, data.blend_mode, data.name, true)
			else:
				inst.mesh = item.source
			entry.result = inst.mesh
			if item.capped:
				_set_caps(inst, res.caps)
		else:
			entry.stale = true
		if job.cut.is_empty():
			continue
		var relative := skeleton.global_transform.affine_inverse() * inst.global_transform
		if not res.severed.is_empty():
			parts.append({
				mesh = LimbCutter.build(res.severed, PackedStringArray() if res.baked else data.blend_names,
						data.blend_mode, data.name + "_severed", false),
				skin = null if res.baked else inst.skin, transform = relative,
				material_override = inst.material_override,
			})
		if res.severed_cap != null:
			parts.append({
				mesh = LimbCutter.build([res.severed_cap], PackedStringArray(), 0, "StumpCap", false),
				skin = null if res.baked else inst.skin, transform = relative, material_override = _stump(),
			})
	if current and not job.cut.is_empty() and not parts.is_empty():
		_drop(job.cut, parts)


func _set_caps(inst: MeshInstance3D, caps: Array) -> void:
	for old in _caps.get(inst, []):
		if is_instance_valid(old):
			old.queue_free()
	var list := []
	for i in caps.size():
		var cap: Variant = caps[i]
		if cap == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "StumpCap_" + String(_cuts[i].name).trim_prefix("mixamorig_") if i < _cuts.size() else "StumpCap"
		mi.set_meta(CAP_META, true)
		mi.mesh = LimbCutter.build([cap], PackedStringArray(), 0, "StumpCap", false)
		mi.material_override = _stump()
		mi.skin = inst.skin
		mi.lod_bias = inst.lod_bias
		skeleton.add_child(mi, true)
		mi.transform = skeleton.global_transform.affine_inverse() * inst.global_transform
		list.append(mi)
	_caps[inst] = list


func _drop(c: Dictionary, parts: Array) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	# Los segmentos del muñeco que se lleva: el del corte y los que cuelgan de él.
	var chain := PackedStringArray()
	for part in Ragdoll.PARTS:
		var bone := skeleton.find_bone(part[0])
		if bone == c.bone or (bone >= 0 and _descends(bone, c.bone)):
			chain.append(part[0])
	var ends := stump(c)
	var fall := gravity
	if fall.length_squared() < 1e-6:
		return
	if rigid_parts:
		var extras: Array[Node3D] = []
		for node in skeleton.find_children("*", "BoneAttachment3D", false, false):
			var attachment := node as BoneAttachment3D
			var bone := skeleton.find_bone(attachment.bone_name)
			if bone < 0 or not (bone == c.bone or _descends(bone, c.bone)):
				continue
			for child in attachment.get_children():
				if child is MeshInstance3D and (child as MeshInstance3D).visible:
					extras.append(child)
		var chunk := SeveredChunk.spawn(host, skeleton, parts, extras, ends[0], -ends[1], c.fling,
				fall, world_mask, exclude_body)
		for node in extras:
			node.visible = false
			_hidden.append(node)
		limb_dropped.emit(c, chunk)
		return
	var limb := SeveredLimb.spawn(host, skeleton, frame_node, parts, c.name, chain, ends[0], -ends[1],
			c.fling, fall, world_mask, exclude_body)
	limb_dropped.emit(c, limb)


func _descends(bone: int, ancestor: int) -> bool:
	var parent := skeleton.get_bone_parent(bone)
	while parent >= 0:
		if parent == ancestor:
			return true
		parent = skeleton.get_bone_parent(parent)
	return false


static func _stump() -> ShaderMaterial:
	if _stump_material == null:
		_stump_material = ShaderMaterial.new()
		_stump_material.shader = STUMP_SHADER
	return _stump_material

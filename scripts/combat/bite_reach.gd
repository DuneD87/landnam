class_name BiteReach
extends SkeletonModifier3D

## Lleva la boca de una fiera a lo que muerde: gira la cabeza, el cuello y algo el pecho, de la cabeza
## hacia atrás (CCD), lo justo para que la punta de la mandíbula llegue a [target], sin pasar de lo
## que da cada hueso (MAX_HEAD, MAX_NECK, MAX_CHEST). Entra y sale fundiéndose (BLEND) según [wanted].
##
## La boca es la punta de la mandíbula, sacada de la propia malla: el vértice de la mandíbula (y lo
## que cuelga de ella: labios, dientes) más adelantado, en su marco (ver tip_of). Sirve igual para
## una especie con huesos hasta el morro que para una sin ellos (el caimán). Va la última de los
## modificadores del esqueleto (se monta al usarse: for_npc), y deja dónde ha quedado la boca con
## todo aplicado (mouth), para quien lleve algo en ella (SeveredLimb.grab). Fuera de la
## actualización del esqueleto, este da la pose sin modificadores: animal_mouth() es la de la
## animación, la que sirve para colocar el cuerpo.

## Grados que puede girar la cabeza, cada hueso del cuello y el pecho del que sale para llegar.
const MAX_HEAD := 40.0
const MAX_NECK := 32.0
const MAX_CHEST := 12.0
## Huesos de la cabeza y el cuello que entran, como mucho (más el pecho), y vueltas del CCD.
const MAX_CHAIN := 4
const ITERATIONS := 8
## Lo que tarda en entrar o salir del todo (s).
const BLEND := 0.25

## Dónde morder (mundo); INF = nada.
var target := Vector3.INF
## Cuánto manda (0-1) hacia lo que se pide: se funde hacia ello en BLEND.
var wanted := 0.0
var weight := 0.0
## Dónde está la boca (mundo, mirando como la mandíbula), con todo aplicado.
var mouth := Transform3D()

var _jaw := -1
var _tip := Vector3.ZERO
## La cabeza primero, luego el cuello hacia atrás.
var _chain := PackedInt32Array()
var _limits := PackedFloat32Array()

## Malla → {hueso de la mandíbula → punta en su marco}: se lee una vez por especie.
static var _tips := {}
## Muestras de un clip para la boca media (clip_mouth), y lo ya calculado.
const CLIP_SAMPLES := 24
var _clip_mouths := {}


## El de [npc], montado en su esqueleto la primera vez. null si no tiene cabeza ni mandíbula.
static func for_npc(npc: NPCController) -> BiteReach:
	var skel := npc.get_skeleton()
	if skel == null:
		return null
	var existing := skel.get_node_or_null(^"BiteReach") as BiteReach
	if existing != null:
		return existing
	var head := skel.find_bone(npc.head_bone) if npc.head_bone != &"" else -1
	if head < 0:
		return null
	var reach := BiteReach.new()
	reach.name = "BiteReach"
	reach._jaw = _find_jaw(skel, head)
	if reach._jaw < 0:
		reach._jaw = head
	reach._tip = tip_of(skel, reach._jaw, npc.npc_model, skel.global_basis.inverse() * npc.global_basis.z)
	reach._chain.append(head)
	reach._limits.append(MAX_HEAD)
	var bone := skel.get_bone_parent(head)
	while bone >= 0 and reach._chain.size() < MAX_CHAIN and String(skel.get_bone_name(bone)).to_lower().contains("neck"):
		reach._chain.append(bone)
		reach._limits.append(MAX_NECK)
		bone = skel.get_bone_parent(bone)
	# Y el pecho del que sale el cuello, poco: baja la cabeza un poco más.
	if bone >= 0:
		reach._chain.append(bone)
		reach._limits.append(MAX_CHEST)
	skel.add_child(reach)
	return reach


## La mandíbula de abajo: el hueso bajo la cabeza que se llama "jaw" (no la de arriba).
static func _find_jaw(skel: Skeleton3D, head: int) -> int:
	for b in skel.get_bone_count():
		var bone_name := String(skel.get_bone_name(b)).to_lower()
		if bone_name.contains("jaw") and not bone_name.contains("upper") and _descends(skel, b, head):
			return b
	return -1


static func _descends(skel: Skeleton3D, bone: int, ancestor: int) -> bool:
	var parent := skel.get_bone_parent(bone)
	while parent >= 0:
		if parent == ancestor:
			return true
		parent = skel.get_bone_parent(parent)
	return false


## La punta de [jaw] en su marco: de los vértices de las mallas de [model] que mueve sobre todo la
## mandíbula (o lo que cuelga de ella), el más adelantado hacia [forward] (marco del esqueleto). Sin
## malla que la mueva, el hueso mismo.
static func tip_of(skel: Skeleton3D, jaw: int, model: Node, forward: Vector3) -> Vector3:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var inst := node as MeshInstance3D
		if inst.skin == null or not (inst.mesh is ArrayMesh):
			continue
		var key := "%d:%d" % [inst.mesh.get_rid().get_id(), jaw]
		if _tips.has(key):
			return _tips[key]
		var tip: Variant = _scan_tip(skel, jaw, inst, forward)
		if tip != null:
			_tips[key] = tip
			return tip
	return Vector3.ZERO


static func _scan_tip(skel: Skeleton3D, jaw: int, inst: MeshInstance3D, forward: Vector3) -> Variant:
	var skin := inst.skin
	var jaw_bind := -1
	var binds := {}
	for b in skin.get_bind_count():
		var bind_name := skin.get_bind_name(b)
		var bone := skel.find_bone(bind_name) if bind_name != &"" else skin.get_bind_bone(b)
		if bone == jaw:
			jaw_bind = b
		if bone == jaw or (bone >= 0 and _descends(skel, bone, jaw)):
			binds[b] = true
	if jaw_bind < 0:
		return null
	var bind_pose := skin.get_bind_pose(jaw_bind)
	# Hacia delante en el marco de la mandíbula, en reposo.
	var ahead := (skel.get_bone_global_rest(jaw).basis.orthonormalized().inverse() * forward).normalized()
	var best := -INF
	var tip: Variant = null
	var mesh := inst.mesh as ArrayMesh
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		if vertices.is_empty() or bones.is_empty():
			continue
		var per := bones.size() / vertices.size()
		for v in vertices.size():
			var on_jaw := 0.0
			for k in per:
				if binds.has(bones[v * per + k]):
					on_jaw += weights[v * per + k]
			if on_jaw < 0.5:
				continue
			var local := bind_pose * vertices[v]
			var along := local.dot(ahead)
			if along > best:
				best = along
				tip = local
	return tip


## Dónde queda la boca de media en [clip] de [player] entre [span].x y [span].y (s; sin y, hasta el
## final), en el marco del esqueleto: se saca de las pistas del clip (la cadena de huesos de la raíz
## a la mandíbula, con su reposo donde el clip no dice nada), sin reproducirlo. INF si no hay clip.
func clip_mouth(player: AnimationPlayer, clip: StringName, span: Vector2) -> Vector3:
	var skel := get_skeleton()
	if skel == null or _jaw < 0 or player == null or not player.has_animation(clip):
		return Vector3.INF
	var key := "%s:%s:%s:%s" % [skel.get_instance_id(), clip, span, _jaw]
	if _clip_mouths.has(key):
		return _clip_mouths[key]
	var anim := player.get_animation(clip)
	var prefix := String(player.get_node(player.root_node).get_path_to(skel))
	var chain: Array[int] = []
	var bone := _jaw
	while bone >= 0:
		chain.push_front(bone)
		bone = skel.get_bone_parent(bone)
	var tracks := {}
	for b in chain:
		var path := NodePath(prefix + ":" + String(skel.get_bone_name(b)))
		tracks[b] = [anim.find_track(path, Animation.TYPE_POSITION_3D), anim.find_track(path, Animation.TYPE_ROTATION_3D),
			anim.find_track(path, Animation.TYPE_SCALE_3D)]
	var end := span.y if span.y > span.x else anim.length
	var sum := Vector3.ZERO
	for i in CLIP_SAMPLES:
		var time := lerpf(span.x, end, (i + 0.5) / CLIP_SAMPLES)
		var pose := Transform3D.IDENTITY
		for b in chain:
			var rest := skel.get_bone_rest(b)
			var found: Array = tracks[b]
			var origin: Vector3 = anim.position_track_interpolate(found[0], time) if found[0] >= 0 else rest.origin
			var rotation: Quaternion = anim.rotation_track_interpolate(found[1], time) if found[1] >= 0 \
				else rest.basis.get_rotation_quaternion()
			var scale: Vector3 = anim.scale_track_interpolate(found[2], time) if found[2] >= 0 else rest.basis.get_scale()
			pose = pose * Transform3D(Basis(rotation).scaled(scale), origin)
		sum += pose * _tip
	_clip_mouths[key] = sum / CLIP_SAMPLES
	return _clip_mouths[key]


## Dónde está la boca en la pose de la animación (mundo), sin lo que la mueve este modificador.
func animal_mouth() -> Vector3:
	var skel := get_skeleton()
	if skel == null or _jaw < 0:
		return Vector3.INF
	return skel.global_transform * (skel.get_bone_global_pose(_jaw) * _tip)


func _process_modification_with_delta(delta: float) -> void:
	weight = move_toward(weight, wanted if target != Vector3.INF else 0.0, delta / BLEND)
	_apply()


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	var skel := get_skeleton()
	if skel == null or _jaw < 0:
		return
	if weight > 0.001 and target != Vector3.INF:
		var goal := skel.global_transform.affine_inverse() * target
		for iteration in ITERATIONS:
			for i in _chain.size():
				var bone := _chain[i]
				var pose := skel.get_bone_global_pose(bone)
				var from := skel.get_bone_global_pose(_jaw) * _tip - pose.origin
				var to := goal - pose.origin
				var axis := from.cross(to)
				if axis.length_squared() < 1e-12:
					continue
				var angle := minf(from.angle_to(to), deg_to_rad(_limits[i]) / ITERATIONS) * weight
				var rotation := Quaternion(axis.normalized(), angle) * pose.basis.get_rotation_quaternion()
				var parent := skel.get_bone_parent(bone)
				var parent_rotation := skel.get_bone_global_pose(parent).basis.get_rotation_quaternion() \
					if parent >= 0 else Quaternion.IDENTITY
				skel.set_bone_pose_rotation(bone, parent_rotation.inverse() * rotation)
	var jaw := skel.get_bone_global_pose(_jaw)
	mouth = skel.global_transform * Transform3D(jaw.basis, jaw * _tip)

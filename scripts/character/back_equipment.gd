class_name BackEquipment
extends BoneAttachment3D

## Equipo rígido en la espalda, en metros. Compensa la escala y orientación del esqueleto
## importado y comparte el mismo ajuste entre el jugador y el muñeco de equipo. Va encima de la
## capa: con una puesta se aparta de la espalda lo que esta abulta (OVER_CLOAK).
## Cuelga de Spine2, pero no rígida: cuando la espalda se curva (el torso se inclina sobre las
## lumbares) se gira con lo que gira la parte baja, FOLLOW_LUMBAR de ello, sobre donde apoya arriba
## (PIVOT, en el espacio de la mochila), para que el fondo no se despegue de los riñones.

## Metros que se aparta de la espalda con una capa puesta.
const OVER_CLOAK := 0.035
const FOLLOW_LUMBAR := 0.8
const PIVOT := Vector3(0.0, 0.1, 0.11)

var item_data: ItemData
var visual: Node3D
var _base := Transform3D.IDENTITY
var _skeleton: Skeleton3D
var _spine := -1
var _lumbar := -1
## Giro de Spine respecto a Spine2 en reposo.
var _rest_bend := Quaternion.IDENTITY


static func attach(skeleton: Skeleton3D, scene: PackedScene, data: ItemData,
		rig: CharacterAppearanceRig) -> BackEquipment:
	if skeleton.find_bone(HumanRig.SPINE2) < 0:
		return null
	var attachment := BackEquipment.new()
	attachment.name = "BackEquipment"
	attachment.item_data = data
	attachment.bone_name = HumanRig.SPINE2
	skeleton.add_child(attachment)
	attachment.visual = scene.instantiate()
	attachment.add_child(attachment.visual)
	attachment.fit_to_body(rig)
	return attachment


func fit_to_body(rig: CharacterAppearanceRig) -> void:
	var skeleton := get_parent() as Skeleton3D
	var model := skeleton.get_parent().get_parent() as Node3D
	var bone := skeleton.find_bone(HumanRig.SPINE2)
	var globals := BodyMeasurements.rest_globals(skeleton)
	var rest := globals[bone]
	var to_model := model.global_transform.affine_inverse() * skeleton.global_transform
	var frame := (to_model * rest).basis
	var inverse := frame.inverse()
	var back := -0.12
	if rig != null:
		var measurements := rig.measurements()
		if measurements != null and measurements.has_bone(bone):
			# El hueso no está en el centro del torso. Usa su superficie posterior medida,
			# para que el saco apoye en la espalda en vez de separarse medio pecho de ella.
			var section := measurements.section_at(bone, 0.5)
			back = minf((frame * Vector3(0, 0, section[2])).z, (frame * Vector3(0, 0, section[3])).z)
		if rig.wears(ItemData.ArmorSlot.CLOAK):
			back -= OVER_CLOAK
	_base = Transform3D(inverse, inverse * Vector3(0, -0.08, back - 0.125))
	visual.transform = _base
	_lumbar = skeleton.find_bone(HumanRig.SPINE)
	_spine = bone
	if _lumbar >= 0:
		_rest_bend = _bend(rest, globals[_lumbar])
	if _skeleton != skeleton:
		_skeleton = skeleton
		skeleton.skeleton_updated.connect(_follow_lumbar)


## El giro de la parte baja de la espalda respecto a la alta.
static func _bend(upper: Transform3D, lower: Transform3D) -> Quaternion:
	return (upper.basis.orthonormalized().inverse() * lower.basis.orthonormalized()).get_rotation_quaternion()


func _follow_lumbar() -> void:
	if visual == null or _lumbar < 0 or not is_instance_valid(_skeleton):
		return
	var bend := _bend(_skeleton.get_bone_global_pose(_spine), _skeleton.get_bone_global_pose(_lumbar))
	var turn := Quaternion.IDENTITY.slerp(bend * _rest_bend.inverse(), FOLLOW_LUMBAR)
	var pivot := _base * PIVOT
	visual.transform = Transform3D(Basis(turn), pivot - Basis(turn) * pivot) * _base

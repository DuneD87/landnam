class_name BackEquipment
extends BoneAttachment3D

## Equipo rígido en la espalda, en metros. Compensa la escala y orientación del esqueleto
## importado y comparte el mismo ajuste entre el jugador y el muñeco de equipo.
var item_data: ItemData
var visual: Node3D


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
	var rest := BodyMeasurements.rest_globals(skeleton)[bone]
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
	visual.transform = Transform3D(inverse, inverse * Vector3(0, -0.08, back - 0.125))

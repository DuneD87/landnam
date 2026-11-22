class_name WeaponCarry
extends BoneAttachment3D

## Un anclaje de transporte, compartido por el jugador y el muñeco del inventario.
## Las armas usan metros, +Y hacia la punta; el esqueleto importado usa centímetros.
## El ajuste invierte el marco de reposo para conservar esos metros y los ejes del modelo.
const CLOAK_GAP := 0.045

var data: ItemData
var mount := Transform3D.IDENTITY


static func create(skeleton: Skeleton3D, item: ItemData) -> WeaponCarry:
	var anchor := WeaponCarry.new()
	anchor.name = "WeaponCarry"
	anchor.data = item
	var hip := not item.is_shield() and not item.two_handed \
		and item.weapon_type != ItemData.WeaponType.BOW and item.weapon_type != ItemData.WeaponType.SPEAR
	anchor.bone_name = HumanRig.HIPS if hip else HumanRig.SPINE2
	if skeleton.find_bone(anchor.bone_name) < 0:
		anchor.free()
		return null
	skeleton.add_child(anchor)
	return anchor


func fit_to_body(rig: CharacterAppearanceRig) -> void:
	var skeleton := get_parent() as Skeleton3D
	var model := skeleton.get_parent().get_parent() as Node3D
	var bone := skeleton.find_bone(bone_name)
	var rest := BodyMeasurements.rest_globals(skeleton)[bone]
	var frame := (model.global_transform.affine_inverse() * skeleton.global_transform * rest).basis
	var inverse := frame.inverse()
	var back := -0.13
	var side := 0.19
	if rig != null:
		var measurements := rig.measurements()
		if measurements != null and measurements.has_bone(bone):
			var section := measurements.section_at(bone, 0.5)
			back = minf((frame * Vector3(0, 0, section[2])).z, (frame * Vector3(0, 0, section[3])).z)
			side = maxf(side, maxf(absf((frame * Vector3(section[0], 0, 0)).x),
				absf((frame * Vector3(section[1], 0, 0)).x)))
		if rig.wears(ItemData.ArmorSlot.CLOAK):
			back -= CLOAK_GAP
	var offset := Vector3.ZERO
	var rotation := Vector3.ZERO
	if data.is_shield():
		offset = Vector3(0.0, -0.08, back - 0.08)
		rotation.y = PI
	elif bone_name == HumanRig.HIPS:
		# En la cadera izquierda (+X), la punta baja hacia fuera (+X) y hacia atrás (-Z).
		# Los signos se componen con el medio giro: invertirlos mete la hoja en el muslo.
		offset = Vector3(side + 0.08, -0.02, -0.015)
		rotation = Vector3(deg_to_rad(-18.0), 0.0, PI + deg_to_rad(8.0))
	else:
		# Arma y escudo se sujetan al cuerpo; la mochila no modifica sus anclajes.
		var depth := back - 0.08
		if data.weapon_type == ItemData.WeaponType.BOW:
			offset = Vector3(-0.16, -0.14, depth)
			rotation = Vector3(0.0, PI * 0.5, deg_to_rad(-24.0))
		elif data.weapon_type == ItemData.WeaponType.SPEAR:
			offset = Vector3(side + 0.12, -0.45, depth)
			rotation.z = deg_to_rad(-12.0)
		else:
			offset = Vector3(-0.19, 0.20, depth)
			rotation.z = deg_to_rad(210.0)
			# La anchura de la hoja está en Z y su cara en ±X. El giro sobre Y deja
			# esa cara paralela a la espalda; la diagonal sobre Z por sí sola la deja de canto.
			rotation.y = PI * 0.5
	var orientation := Basis(Vector3.BACK, rotation.z) * Basis(Vector3.UP, rotation.y) \
		* Basis(Vector3.RIGHT, rotation.x)
	mount = Transform3D(inverse, inverse * offset) \
		* Transform3D(orientation, Vector3.ZERO) * data.carry_offset
	for child in get_children():
		if child is Node3D:
			child.transform = mount * child.get_meta(&"carry_source", Transform3D.IDENTITY)


## Mueve la misma instancia entre cuerpo y mano. No hay una copia del objeto transportado.
func carry(visual: Node3D) -> void:
	if not visual.has_meta(&"carry_source"):
		visual.set_meta(&"carry_source", visual.transform)
	if visual.get_parent() != null:
		visual.get_parent().remove_child(visual)
	visual.top_level = false
	add_child(visual)
	visual.transform = mount * visual.get_meta(&"carry_source")
	visual.visible = true
	if visual is RangedWeaponVisual:
		visual.flex = 0.0
		visual.set_draw_point(null)

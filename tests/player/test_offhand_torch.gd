extends Node3D

## La antorcha en cualquier mano: en la izquierda, con un arma o el martillo en la derecha. Qué cabe
## en cada hueco, la tecla de la barra, el clip reflejado del brazo izquierdo y guardar y cargar.
##   godot --headless --path . res://tests/player/test_offhand_torch.tscn

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	_check_slots()
	var menu := Control.new()
	add_child(menu)
	var save_button := Button.new()
	save_button.name = "btnSaveGame"
	menu.add_child(save_button)
	save_button.owner = menu
	var player: PlayerController = load("res://scenes/player/third_person_player.tscn").instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.main_menu = menu
	add_child(player)
	_check_mirror(player)
	_check_equip(player)
	GameManager.player = null
	print("RESULT: ", "OK" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check_slots() -> void:
	var torch := ItemCatalog.get_item(&"torch_01")
	var sword := ItemCatalog.get_item(&"iron_sword")
	var shield := ItemCatalog.get_item(&"heater_shield")
	var hammer := ItemCatalog.get_item(&"stone_hammer_01")
	check(torch.fits_slot(ItemData.ArmorSlot.RIGHT_HAND) and torch.fits_slot(ItemData.ArmorSlot.OFFHAND),
		"la antorcha cabe en las dos manos")
	check(not torch.fits_slot(ItemData.ArmorSlot.HEAD), "pero no en la cabeza")
	check(not sword.fits_slot(ItemData.ArmorSlot.OFFHAND) and not hammer.fits_slot(ItemData.ArmorSlot.OFFHAND),
		"la espada y el martillo, solo en la derecha")
	check(torch.is_offhand() and shield.is_offhand() and not sword.is_offhand() and not hammer.is_offhand(),
		"la tecla de la barra pone en la izquierda escudos y antorchas")


## Con el clip reflejado, la mano izquierda va donde la derecha en el original, al otro lado del
## plano medio (el tronco en reposo, que es simétrico).
func _check_mirror(player: PlayerController) -> void:
	var animator := player.animation_controller.animator
	check(animator.has_animation_library(Locomotion.LEFT_TORCH_LIBRARY), "están los clips de la izquierda")
	var tree := player.animation_controller.animation_tree
	check(tree.get("parameters/bLeftTorch/blend_amount") != null, "el árbol tiene la capa de la izquierda")
	var skeleton: Skeleton3D = player.player_model.get_node("Armature/Skeleton3D")
	var hips_x := skeleton.get_bone_global_rest(skeleton.find_bone(HumanRig.HIPS)).origin.x
	for clip in [[&"idle_torch", &"idle"], [&"running-torch", &"run"]]:
		var source := animator.get_animation(clip[0])
		var mirrored := animator.get_animation(StringName(Locomotion.LEFT_TORCH_LIBRARY + "/" + clip[1]))
		var only_left := mirrored.get_track_count() > 0
		for track in mirrored.get_track_count():
			only_left = only_left and _arm_of(skeleton, mirrored, track) == HumanRig.LEFT_SHOULDER
		check(only_left, "%s: solo trae el brazo izquierdo" % clip[1])
		var worst := 0.0
		for t in [0.0, source.length * 0.37, source.length * 0.81]:
			var right := _posed(skeleton, source, t, HumanRig.RIGHT_HAND_MIDDLE2)
			var left := _posed(skeleton, mirrored, t, HumanRig.LEFT_HAND_MIDDLE2)
			var expected := Vector3(2.0 * hips_x - right.x, right.y, right.z)
			worst = maxf(worst, left.distance_to(expected))
		# El esqueleto va en centímetros.
		check(worst < 1.0, "%s: la mano izquierda refleja a la derecha (%.2f cm)" % [clip[1], worst])


## El hombro del brazo del que es la pista [track] de [anim] (vacío si no es de un brazo).
func _arm_of(skeleton: Skeleton3D, anim: Animation, track: int) -> String:
	var index := skeleton.find_bone(anim.track_get_path(track).get_concatenated_subnames())
	while index >= 0:
		var bone_name := skeleton.get_bone_name(index)
		if bone_name == HumanRig.LEFT_SHOULDER or bone_name == HumanRig.RIGHT_SHOULDER:
			return bone_name
		index = skeleton.get_bone_parent(index)
	return ""


## Dónde queda [bone] (esqueleto) con [anim] puesto en el instante [time] en los brazos y el resto
## en reposo. Se compone a mano: el esqueleto aplicaría encima sus modificadores (CombatPose, IK).
func _posed(skeleton: Skeleton3D, anim: Animation, time: float, bone: String) -> Vector3:
	var local := {}
	for track in anim.get_track_count():
		var index := skeleton.find_bone(anim.track_get_path(track).get_concatenated_subnames())
		if index < 0 or _arm_of(skeleton, anim, track) == "":
			continue
		var xform: Transform3D = local.get(index, skeleton.get_bone_rest(index))
		match anim.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				xform.basis = Basis(anim.rotation_track_interpolate(track, time))
			Animation.TYPE_POSITION_3D:
				xform.origin = anim.position_track_interpolate(track, time)
		local[index] = xform
	var global := Transform3D.IDENTITY
	var index := skeleton.find_bone(bone)
	while index >= 0:
		global = (local.get(index, skeleton.get_bone_rest(index)) as Transform3D) * global
		index = skeleton.get_bone_parent(index)
	return global.origin


func _check_equip(player: PlayerController) -> void:
	var torch := ItemCatalog.get_item(&"torch_01")
	var sword := ItemCatalog.get_item(&"iron_sword")
	var bow := ItemCatalog.get_item(&"hunting_bow")
	var window := player.character_window
	var combat := player.combat
	var left: EquipmentSlot = window.get_slot(ItemData.ArmorSlot.OFFHAND)
	var right: EquipmentSlot = window.get_slot(ItemData.ArmorSlot.RIGHT_HAND)
	player.inventory.clear()
	player.inventory.add_item(torch, 3)
	player.inventory.add_item(sword, 1)
	player.inventory.add_item(bow, 1)

	# La tecla de la antorcha la pone en la izquierda.
	player._on_hotbar_offhand_toggled(torch)
	check(left.has_item() and left.equipped_item.data == torch, "la tecla pone la antorcha en la izquierda")
	check(player.inventory.get_item_count(torch) == 2, "y la saca del inventario")
	var node := combat._offhand_torch
	check(node != null and node.get_parent() == combat._left_attachment, "cuelga de la mano izquierda")
	check(combat.holds_offhand_torch(), "y se ve")
	if node != null:
		check(node.transform.basis.determinant() > 0.0, "reflejada sin escala negativa")

	# Con la espada en la derecha sigue en la izquierda.
	player._equip_from_hotbar(null, sword)
	check(right.has_item() and right.equipped_item.data == sword and player.right_hand_equipped,
		"la espada va en la derecha")
	check(left.has_item() and combat.holds_offhand_torch(), "con la antorcha en la izquierda")
	player.current_animation = AnimationController.Anim.IDLE
	player._hold_left_torch()
	check(player.animation_controller.overlay.get("bLeftTorch") == 1.0, "el brazo izquierdo la sostiene")
	player.animation_controller.snap_to(AnimationController.Anim.IDLE)
	check(is_equal_approx(player.animation_controller.animation_tree.get("parameters/bLeftTorch/blend_amount"), 1.0),
		"y la mezcla llega al árbol")
	player.current_animation = AnimationController.Anim.SWIM
	player._hold_left_torch()
	check(player.animation_controller.overlay.get("bLeftTorch") == 0.0, "nadando la suelta")

	# El arco ocupa la izquierda: la antorcha sigue puesta, pero no se ve.
	player._equip_from_hotbar(sword, bow)
	check(left.has_item() and not combat.holds_offhand_torch(), "con el arco la antorcha se esconde")
	player._unequip_right_hand()
	check(combat.holds_offhand_torch(), "y vuelve al soltarlo")
	player._equip_from_hotbar(null, sword)

	# Guardar y cargar la deja en la izquierda.
	var equipment: Dictionary = player.get_save_data().equipment
	check(equipment.get(str(int(ItemData.ArmorSlot.OFFHAND))) == "torch_01", "se guarda en la izquierda")
	player._clear_visual_equipment()
	check(combat._offhand_torch == null, "al limpiar el equipo se quita")
	player.equip_item(true, ItemData.ArmorSlot.OFFHAND, load(torch.scene_path), torch, torch.category)
	check(combat.holds_offhand_torch() and not player.right_hand_equipped,
		"al cargarla en su hueco vuelve a la izquierda, no a la derecha")
	player.equip_item(true, ItemData.ArmorSlot.RIGHT_HAND, load(sword.scene_path), sword, sword.category)

	# Otra vez la tecla: se quita y vuelve al inventario.
	player._on_hotbar_offhand_toggled(torch)
	check(not left.has_item() and combat._offhand_torch == null, "la tecla la quita")
	check(player.inventory.get_item_count(torch) == 3, "y vuelve al inventario")

	# En la derecha (desde el muñeco), la tecla la cambia de mano.
	window.unequip_item(right)
	window.equip_item(right, InventoryItem.new(torch, 1))
	player.inventory.remove_item(torch, 1)
	check(right.has_item() and right.equipped_item.data == torch, "también va en la derecha")
	player._on_hotbar_offhand_toggled(torch)
	check(not right.has_item() and left.has_item() and left.equipped_item.data == torch,
		"y su tecla la pasa a la izquierda")
	check(player.inventory.get_item_count(torch) == 2, "sin gastar otra")

	# Un escudo en la izquierda la devuelve al inventario.
	var shield := ItemCatalog.get_item(&"heater_shield")
	player.inventory.add_item(shield, 1)
	player._on_hotbar_offhand_toggled(shield)
	check(left.equipped_item.data == shield and combat._offhand_torch == null, "el escudo la sustituye")
	check(player.inventory.get_item_count(torch) == 3, "y la antorcha vuelve al inventario")

class_name PlayerLoadout
extends Node3D

## El equipo posee los objetos; este componente solo presenta sus modelos. PRIMARY permanece
## equipado al usar una herramienta (RIGHT_HAND), al guardar el arma o al elegir un consumible.
var player: PlayerController
var active_slot := -1
var hands_ready := true
var visuals := {}
var items := {}
var _original := {}
var primary_carry: WeaponCarry


func setup(owner_player: PlayerController) -> void:
	player = owner_player


func equip(slot: ItemData.ArmorSlot, visual: Node3D, data: ItemData) -> void:
	var previous := unequip(slot)
	if previous != null:
		player._unregister_worn_node(previous)
		previous.queue_free()
	visuals[slot] = visual
	items[slot] = data
	_original[slot] = visual.transform
	visual.set_meta(&"carry_source", visual.transform)
	add_child(visual)
	visual.visible = false
	if slot == ItemData.ArmorSlot.PRIMARY:
		primary_carry = WeaponCarry.create(player.player_model.get_node("Armature/Skeleton3D"), data)
		refit()
	set_active(slot)


func unequip(slot: int) -> Node3D:
	if not visuals.has(slot):
		return null
	if active_slot == slot:
		set_active(-1)
	var visual: Node3D = visuals[slot]
	if visual.get_parent() != null:
		visual.get_parent().remove_child(visual)
	visuals.erase(slot)
	items.erase(slot)
	_original.erase(slot)
	if slot == ItemData.ArmorSlot.PRIMARY and primary_carry != null:
		primary_carry.queue_free()
		primary_carry = null
	return visual


func set_active(slot: int) -> void:
	if slot >= 0 and not visuals.has(slot):
		return
	if active_slot == slot:
		return
	player.combat.detach_weapon()
	if active_slot >= 0 and visuals.has(active_slot):
		var old: Node3D = visuals[active_slot]
		if active_slot == ItemData.ArmorSlot.PRIMARY and primary_carry != null:
			primary_carry.carry(old)
		else:
			if old.get_parent() != null:
				old.get_parent().remove_child(old)
			old.top_level = false
			add_child(old)
			old.visible = false
			_set_audio_active(old, false)
	active_slot = slot
	hands_ready = slot >= 0
	player.equiped_weapon = items.get(slot)
	player.right_hand_equipped = slot >= 0
	player.is_holding_atack = false
	player.current_animation = AnimationController.Anim.IDLE
	if slot >= 0:
		var visual: Node3D = visuals[slot]
		if visual.get_parent() != null:
			visual.get_parent().remove_child(visual)
		visual.top_level = false
		visual.transform = _original[slot]
		visual.visible = true
		player.combat.attach_weapon(visual, items[slot])
		_set_audio_active(visual, true)
	player.combat._update_shield_visibility()
	player._sync_build_mode()


func toggle_weapon() -> void:
	if active_slot == ItemData.ArmorSlot.PRIMARY:
		set_active(-1)
	elif visuals.has(ItemData.ArmorSlot.PRIMARY):
		set_active(ItemData.ArmorSlot.PRIMARY)
	elif active_slot >= 0:
		set_active(-1)
	elif visuals.has(ItemData.ArmorSlot.RIGHT_HAND):
		set_active(ItemData.ArmorSlot.RIGHT_HAND)
	else:
		hands_ready = not hands_ready
		player.combat._update_shield_visibility()
	# La selección es un acceso. Sacar/guardar no debe simular otra transferencia de objetos.
	_sync_selection()
	player.building_system.select_placeable(null)
	player._sync_build_mode()


func _sync_selection() -> void:
	var selected := -1
	var data: ItemData = items.get(active_slot)
	if data != null:
		for i in player.hotbar.slots.size():
			var assigned: ItemData = player.hotbar.slots[i].assigned_data
			if assigned != null and assigned.id == data.id:
				selected = i
				break
	player.hotbar.restore_selection(selected)


func _set_audio_active(visual: Node3D, playing: bool) -> void:
	for node in visual.find_children("*", "", true, false):
		if node is EntityAudio:
			node.set_loop_active(playing)


func refit() -> void:
	if primary_carry != null:
		primary_carry.fit_to_body(player.appearance_rig)
	if player.combat != null:
		player.combat.refit_shield_carry()


func save_data() -> Dictionary:
	return {"active_slot": active_slot, "hands_ready": hands_ready}


func restore(data: Dictionary) -> void:
	var slot := int(data.get("active_slot", active_slot))
	set_active(slot if visuals.has(slot) else -1)
	hands_ready = bool(data.get("hands_ready", hands_ready))
	player.combat._update_shield_visibility()
	refit()


func clear() -> void:
	for slot: int in visuals.keys():
		var visual := unequip(slot)
		player._unregister_worn_node(visual)
		visual.queue_free()
	active_slot = -1
	hands_ready = true
	player.equiped_weapon = null
	player.right_hand_equipped = false

class_name CompanionGear extends RefCounted

## Lo que el compañero (Companion) lleva encima, sacado de su morral, como el arma (refresh_weapon):
##   - ropa y armadura: en cada hueco (WORN_SLOTS) se pone la pieza del morral que más protege y, si no
##     hay ninguna, la de su poblado (SettlementPopulation: "outfit"); quitársela le devuelve la suya;
##   - escudo: el mejor del morral, atado al antebrazo izquierdo (como el del jugador, CombatPose), con
##     su guardia (Guard) y un aguante propio (StaminaComponent);
##   - arco: el mejor del morral, en la mano izquierda; dispara las flechas del morral (ammo).
## Lo que lleva puesto sigue en el morral: no hay que guardarlo aparte.

const WORN_SLOTS: Array[ItemData.ArmorSlot] = [ItemData.ArmorSlot.HEAD, ItemData.ArmorSlot.CHEST,
	ItemData.ArmorSlot.HANDS, ItemData.ArmorSlot.LEGS, ItemData.ArmorSlot.FEET, ItemData.ArmorSlot.CLOAK]
## Su aguante para parar golpes: menos que el del jugador y se recupera más despacio.
const STAMINA := 80.0
const STAMINA_REGEN := 22.0
## El escudo en el antebrazo, como CombatPose.SHIELD_ON_FOREARM: hacia el codo y hacia fuera del dorso.
const SHIELD_ON_FOREARM := Vector2(0.13, 0.08)
const LEFT_MIDDLE1 := "mixamorig_LeftHandMiddle1"
## La flecha que se ve al tensar (la del jugador, PlayerCombat).
const ARROW_MESH := "res://data/items/meshes/weapons/arrow.res"

var guard: Guard
var stamina: StaminaComponent
## Con qué para (null: sin escudo) y con qué dispara (null: sin arco).
var shield: ItemData
var bow: ItemData

var _model: Node3D
var _skeleton: Skeleton3D
var _rig: CharacterAppearanceRig
## Hueco -> [ItemData, nodo] de lo que lleva puesto (la ropa de su poblado también).
var _worn := {}
## Hueco -> ItemData de la ropa de su poblado.
var _outfit := {}
var _shield_node: Node3D
var _bow_node: Node3D
## La flecha en la cuerda o en la mano mientras tensa (place_bow).
var _arrow: MeshInstance3D
var _left_grip: Node3D
## El antebrazo en reposo: hacia fuera del dorso y hacia el pulgar (CombatPose._shield_frame).
var _forearm_out := Vector3.ZERO
var _forearm_top := Vector3.ZERO


## [body]: el compañero (la guardia mira por su +Z); [model]: su humano vestido (Villager.build_model)
## con la ropa de [outfit] (ids).
func _init(body: Node3D, model: Node3D, outfit: Array) -> void:
	_model = model
	_skeleton = model.get_node("Armature/Skeleton3D") as Skeleton3D
	_rig = model.get_node_or_null("AppearanceRig") as CharacterAppearanceRig
	stamina = StaminaComponent.new()
	stamina.name = "GuardStamina"
	stamina.max_stamina = STAMINA
	stamina.regen_rate = STAMINA_REGEN
	body.add_child(stamina)
	guard = Guard.new()
	guard.body = body
	guard.stamina = stamina
	# Las piezas que ya lleva (build_model las cuelga del esqueleto): se reconocen por su escena.
	for id in outfit:
		var data := ItemCatalog.get_item(StringName(id))
		if data == null or not data.armor_slot in WORN_SLOTS:
			continue
		_outfit[data.armor_slot] = data
		for child in _skeleton.get_children():
			if child.scene_file_path == data.scene_path and not _is_worn_node(child):
				_worn[data.armor_slot] = [data, child]
				break


## Se pone lo mejor de [pack] (Inventory). Cierto si ha cambiado la ropa o la armadura.
func refresh(pack: Inventory) -> bool:
	var best := {}
	var best_score := {}
	var best_shield: ItemData
	var best_bow: ItemData
	for item in pack.get_all_items():
		if item == null or item.data == null:
			continue
		var data := item.data
		if data.is_shield():
			if best_shield == null or data.guard_reduction > best_shield.guard_reduction:
				best_shield = data
		elif data.weapon_type == ItemData.WeaponType.BOW and data.category == ItemData.Category.WEAPON:
			if best_bow == null or data.damage > best_bow.damage:
				best_bow = data
		elif data.category == ItemData.Category.ARMOR and data.armor_slot in WORN_SLOTS and data.scene_path != "":
			var score := _protection(data)
			if not best.has(data.armor_slot) or score > float(best_score[data.armor_slot]):
				best[data.armor_slot] = data
				best_score[data.armor_slot] = score
	var changed := false
	for slot in WORN_SLOTS:
		var want: ItemData = best.get(slot, _outfit.get(slot))
		var have: ItemData = _worn[slot][0] if _worn.has(slot) else null
		if _same(want, have):
			continue
		_take_off(slot)
		if want != null:
			_put_on(slot, want)
		changed = true
	if not _same(best_shield, shield):
		_set_shield(best_shield)
	if not _same(best_bow, bow):
		_set_bow(best_bow)
	return changed


## Lo que protege lo que lleva puesto (x tajo, y contundente, z perforante), sumado.
func armor() -> Vector3:
	var total := Vector3.ZERO
	for slot in _worn:
		total += Armor.of(_worn[slot][0])
	return total


## Lo que lleva puesto en cada hueco (ItemData), para la charla y las pruebas.
func worn() -> Dictionary:
	var out := {}
	for slot in _worn:
		out[slot] = _worn[slot][0]
	return out


## Las flechas (o lo que dispare su arco) que le quedan en [pack].
func ammo_left(pack: Inventory) -> int:
	var data := ammo()
	return pack.get_item_count(data) if data != null else 0


func ammo() -> ItemData:
	return ItemCatalog.get_item(bow.ammo_id) if bow != null and bow.ammo_id != &"" else null


## Muestra u oculta el escudo y el arco (el arco solo se ve al sacarlo).
func show(shield_on: bool, bow_on: bool) -> void:
	if _shield_node != null:
		_shield_node.visible = shield_on
	if _bow_node != null:
		_bow_node.visible = bow_on


## Dónde sale la flecha: la mano del arco (mundo).
func bow_hand() -> Vector3:
	var bone := _skeleton.find_bone(HumanRig.LEFT_HAND)
	if bone < 0:
		return _model.global_position + _model.global_basis.y * 1.4
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin


## Tras posar los brazos (CombatPose.after_pose): con el arco tensándose ([aim] > 0), el arco, la cuerda y
## la flecha donde los deja BowAnimRig, como al jugador (PlayerCombat._place_bow); si no, el arco cuelga
## de la mano. Del agarre de colgar al de tirar pasa sin saltos.
func place_bow(p: CombatPose, aim: float) -> void:
	if _bow_node == null:
		return
	var visual := _bow_node as RangedWeaponVisual
	if aim <= 0.001 or not _bow_node.visible:
		_bow_node.top_level = false
		_bow_node.transform = Transform3D.IDENTITY
		if _arrow != null:
			_arrow.visible = false
		if visual != null:
			visual.flex = 0.0
			visual.set_draw_point(null)
		return
	var rig := p.bow_rig
	_bow_node.top_level = true
	var hanging := p.bone_world_xform(HumanRig.LEFT_HAND_MIDDLE2) * CombatPose.LEFT_GRIP
	var k := smoothstep(0.0, 0.7, aim)
	_bow_node.global_transform = hanging.orthonormalized().interpolate_with(rig.bow_xform, k)
	if visual != null:
		visual.flex = rig.bow_flex
		visual.set_draw_point(rig.string_point if k > 0.95 else null)
	if _arrow == null:
		_arrow = MeshInstance3D.new()
		_arrow.name = "NockedArrow"
		_arrow.mesh = load(ARROW_MESH)
		_arrow.top_level = true
		_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_model.add_child(_arrow)
	_arrow.visible = rig.arrow_mode != &"" and k > 0.5
	if _arrow.visible:
		_arrow.global_transform = rig.arrow_xform


## Cada pose del esqueleto: el escudo, en el antebrazo.
func place() -> void:
	if _shield_node == null or not _shield_node.visible:
		return
	var frame := _shield_frame()
	if frame == Transform3D():
		return
	var elbow := (_bone(HumanRig.LEFT_FORE_ARM) - frame.origin).normalized()
	var unit := _model.global_basis.get_scale().x / _skeleton.global_basis.get_scale().x
	var center := frame.origin + (elbow * SHIELD_ON_FOREARM.x + frame.basis.z * SHIELD_ON_FOREARM.y) * unit
	var to_world := _skeleton.global_transform
	_shield_node.global_transform = Transform3D((to_world.basis.orthonormalized() * frame.basis).orthonormalized(),
		to_world * center)


func _protection(data: ItemData) -> float:
	var a := Armor.of(data)
	return a.x + a.y + a.z


static func _same(a: ItemData, b: ItemData) -> bool:
	return (a == null and b == null) or (a != null and b != null and a.id == b.id)


func _is_worn_node(node: Node) -> bool:
	for slot in _worn:
		if _worn[slot][1] == node:
			return true
	return false


func _take_off(slot: ItemData.ArmorSlot) -> void:
	if not _worn.has(slot):
		return
	var node: Node = _worn[slot][1]
	_worn.erase(slot)
	if node == null or not is_instance_valid(node):
		return
	if _rig != null:
		_rig.undress(node)
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()


func _put_on(slot: ItemData.ArmorSlot, data: ItemData) -> void:
	var scene := load(data.scene_path) as PackedScene
	if scene == null:
		return
	var node := scene.instantiate()
	if "item_data" in node:
		node.item_data = ItemData.clone(data)
	_skeleton.add_child(node)
	if _rig != null:
		_rig.dress(node, slot == ItemData.ArmorSlot.HEAD)
	_worn[slot] = [data, node]


func _set_shield(data: ItemData) -> void:
	if _shield_node != null:
		_shield_node.queue_free()
		_shield_node = null
	shield = data
	guard.lower()
	guard.item = data
	if data == null or data.scene_path == "":
		return
	var scene := load(data.scene_path) as PackedScene
	if scene == null:
		return
	_shield_node = scene.instantiate() as Node3D
	_shield_node.top_level = true
	_model.add_child(_shield_node)


func _set_bow(data: ItemData) -> void:
	if _bow_node != null:
		_bow_node.queue_free()
		_bow_node = null
	bow = data
	if data == null or data.scene_path == "":
		return
	if _left_grip == null:
		# Como el agarre izquierdo del jugador (PlayerCombat): el rig refleja el eje X de ese lado.
		var hand := BoneAttachment3D.new()
		hand.name = "BowHand"
		hand.bone_name = HumanRig.LEFT_HAND_MIDDLE2
		_skeleton.add_child(hand)
		_left_grip = Node3D.new()
		_left_grip.name = "Grip"
		_left_grip.transform = CombatPose.LEFT_GRIP
		hand.add_child(_left_grip)
	var scene := load(data.scene_path) as PackedScene
	if scene == null:
		return
	_bow_node = scene.instantiate() as Node3D
	_bow_node.visible = false
	_left_grip.add_child(_bow_node)


func _bone(bone_name: String) -> Vector3:
	var i := _skeleton.find_bone(bone_name)
	return _skeleton.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO


## El marco del antebrazo izquierdo (espacio del esqueleto), como CombatPose._shield_frame: origen en la
## muñeca, z hacia fuera del dorso, y hacia el pulgar. Transform3D() si faltan los huesos.
func _shield_frame() -> Transform3D:
	var fi := _skeleton.find_bone(HumanRig.LEFT_FORE_ARM)
	var hi := _skeleton.find_bone(HumanRig.LEFT_HAND)
	if fi < 0 or hi < 0:
		return Transform3D()
	if _forearm_out == Vector3.ZERO:
		var rest := _skeleton.get_bone_global_rest(fi).basis.inverse()
		var at := func(bone_name: String) -> Vector3:
			var i := _skeleton.find_bone(bone_name)
			return _skeleton.get_bone_global_rest(i).origin if i >= 0 else Vector3.ZERO
		var hand: Vector3 = at.call(HumanRig.LEFT_HAND)
		var d: Vector3 = (at.call(LEFT_MIDDLE1) - hand).normalized()
		var lat: Vector3 = at.call(HumanRig.LEFT_HAND_PINKY1) - at.call(HumanRig.LEFT_HAND_INDEX1)
		var n := lat.cross(d)
		n = (n - d * n.dot(d)).normalized()
		_forearm_out = rest * -n
		_forearm_top = rest * -lat
	var wrist := _skeleton.get_bone_global_pose(hi).origin
	var along := (wrist - _skeleton.get_bone_global_pose(fi).origin).normalized()
	var pose := _skeleton.get_bone_global_pose(fi).basis
	var out := pose * _forearm_out
	out = (out - along * out.dot(along)).normalized()
	var top := out.cross(along)
	if top.dot(pose * _forearm_top) < 0.0:
		top = -top
	return Transform3D(Basis(top.cross(out), top, out), wrist)

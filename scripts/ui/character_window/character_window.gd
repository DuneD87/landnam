class_name CharacterWindow
extends Node

## El equipo del personaje: sus huecos (cabeza, torso, manos, piernas, pies y las dos manos) y el
## muñeco, el propio personaje en 3D con lo que lleva puesto y esos huecos a los lados. El muñeco
## no es una ventana aparte: InventoryUI lo pone en el centro de la pantalla de equipo
## (take_doll()) y llama a refresh() al abrirla, que le pone el aspecto del personaje y le viste
## la ropa de los huecos. Equipar y quitar pasa por equip_item() / unequip_item(), que avisan
## con equipment_changed; el jugador viste o desviste su modelo al recibirlo.

signal equipment_changed(slot_type: ItemData.ArmorSlot, item: InventoryItem, equip: bool)
signal slot_clicked(slot: EquipmentSlot)
## El ratón entra en un hueco o sale de él (la pantalla enseña la ficha de lo que lleva).
signal slot_hovered(slot: EquipmentSlot, hovered: bool)

## Huecos a la izquierda del muñeco, de la cabeza a los pies, y a su derecha.
const LEFT_SLOTS: Array[ItemData.ArmorSlot] = [ItemData.ArmorSlot.HEAD, ItemData.ArmorSlot.CHEST,
	ItemData.ArmorSlot.HANDS, ItemData.ArmorSlot.LEGS, ItemData.ArmorSlot.FEET]
const RIGHT_SLOTS: Array[ItemData.ArmorSlot] = [ItemData.ArmorSlot.RIGHT_HAND, ItemData.ArmorSlot.OFFHAND]
## Clave del nombre de cada hueco.
const SLOT_NAMES := {
	ItemData.ArmorSlot.HEAD: "SLOT_HEAD",
	ItemData.ArmorSlot.CHEST: "SLOT_CHEST",
	ItemData.ArmorSlot.HANDS: "SLOT_HANDS",
	ItemData.ArmorSlot.LEGS: "SLOT_LEGS",
	ItemData.ArmorSlot.FEET: "SLOT_FEET",
	ItemData.ArmorSlot.RIGHT_HAND: "SLOT_RIGHT_HAND",
	ItemData.ArmorSlot.OFFHAND: "SLOT_LEFT_HAND",
}
## Luz que reciben en el muñeco los materiales planetarios de la ropa (opaque_planet_material):
## la del estudio, con un planeta muy lejos debajo para que sea pleno día.
const STUDIO_LIGHT := Vector3(-0.45, 0.5, 0.75)
const STUDIO_PLANET := Vector3(0, -6000000.0, 0)

@export_group("Slot Background Icons")
@export var icon_head: Texture2D
@export var icon_chest: Texture2D
@export var icon_hands: Texture2D
@export var icon_legs: Texture2D
@export var icon_feet: Texture2D
@export var icon_main_hand: Texture2D
@export var icon_off_hand: Texture2D

var equipment_slots: Dictionary = {}
## El muñeco con sus huecos. Es también la zona que cuenta como ventana al tirar cosas.
var panel: Control
var preview: CharacterPreview

var _name_label: Label
## Hueco -> la pieza que lleva puesta el muñeco (con el id del item en sus metadatos).
var _dressed := {}
## El aspecto que tiene el muñeco ahora, serializado.
var _applied_look := ""


func _ready() -> void:
	panel = _build_doll()


func _exit_tree() -> void:
	# Mientras nadie lo coloca, el muñeco no está en el árbol y se libera aquí.
	if panel != null and is_instance_valid(panel) and panel.get_parent() == null:
		panel.free()


## Entrega el muñeco a quien lo pone en pantalla.
func take_doll() -> Control:
	return panel


## Pone al muñeco el aspecto del personaje y la ropa de los huecos. Barato si nada ha cambiado.
func refresh() -> void:
	if preview == null or preview.rig == null:
		return
	var character := GameManager.character
	var appearance := character.appearance if character else CharacterAppearance.new()
	var look := JSON.stringify(appearance.to_dict())
	if look != _applied_look:
		_applied_look = look
		preview.rig.apply(appearance)
	_name_label.text = character.display_name.to_upper() if character and character.display_name != "" else tr("CHAR_DEFAULT_NAME")
	_sync_dress()


func _build_doll() -> Control:
	var doll := VBoxContainer.new()
	doll.name = "Doll"
	doll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_name_label = Label.new()
	_name_label.theme_type_variation = &"HeaderLabel"
	# Es el nombre que ha puesto el jugador: no se busca en las traducciones.
	_name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	doll.add_child(_name_label)

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	doll.add_child(row)
	var icons := {
		ItemData.ArmorSlot.HEAD: icon_head, ItemData.ArmorSlot.CHEST: icon_chest,
		ItemData.ArmorSlot.HANDS: icon_hands, ItemData.ArmorSlot.LEGS: icon_legs,
		ItemData.ArmorSlot.FEET: icon_feet, ItemData.ArmorSlot.RIGHT_HAND: icon_main_hand,
		ItemData.ArmorSlot.OFFHAND: icon_off_hand,
	}
	row.add_child(_slot_column(LEFT_SLOTS, icons, true))

	preview = CharacterPreview.new()
	preview.live = false
	preview.transparent = true
	preview.frame_offset = 0.0
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(preview)
	row.add_child(_slot_column(RIGHT_SLOTS, icons, false))

	var hint := Label.new()
	hint.text = "CHAR_DOLL_HINT"
	hint.theme_type_variation = &"HintLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	doll.add_child(hint)
	return doll


## Columna de huecos, cada uno con su nombre debajo, centrada en el alto del muñeco. Con
## [spread] los huecos se reparten por todo el alto (de la cabeza a los pies).
func _slot_column(slot_types: Array[ItemData.ArmorSlot], icons: Dictionary, spread: bool) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	for slot_type in slot_types:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var slot := EquipmentSlot.new()
		slot.slot_type = slot_type
		slot.background_icon = icons[slot_type]
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.hover_changed.connect(func(s: ItemSlotView, on: bool) -> void: slot_hovered.emit(s, on))
		cell.add_child(slot)
		var caption := Label.new()
		caption.text = SLOT_NAMES[slot_type]
		caption.theme_type_variation = &"SlotCaption"
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(caption)
		column.add_child(cell)
		equipment_slots[slot_type] = slot
		# Aire entre huecos, que crece con el muñeco si se reparten.
		if slot_type != slot_types[-1]:
			var gap := Control.new()
			gap.custom_minimum_size.y = 24
			gap.size_flags_vertical = Control.SIZE_EXPAND_FILL if spread else Control.SIZE_FILL
			column.add_child(gap)
	return column


## Lo que lleva el muñeco sigue a los huecos: las piezas de ropa se visten como en el jugador
## (ajustadas a su cuerpo por el rig). Escudos y armas no se le ponen.
func _sync_dress() -> void:
	var skeleton := preview.get_skeleton()
	if skeleton == null:
		return
	for slot_type in LEFT_SLOTS:
		var slot: EquipmentSlot = equipment_slots[slot_type]
		var wanted: ItemData = slot.equipped_item.data if slot.has_item() else null
		if wanted != null and (wanted.category != ItemData.Category.ARMOR or wanted.is_shield()
				or wanted.scene_path == ""):
			wanted = null
		var worn: Node = _dressed.get(slot_type)
		if worn != null and wanted != null and worn.get_meta(&"item_id") == wanted.id:
			continue
		if worn != null:
			preview.rig.undress(worn)
			worn.queue_free()
			_dressed.erase(slot_type)
		if wanted == null:
			continue
		var piece: Node = load(wanted.scene_path).instantiate()
		piece.set_meta(&"item_id", wanted.id)
		skeleton.add_child(piece)
		_light_for_studio(piece)
		preview.rig.dress(piece, slot_type == ItemData.ArmorSlot.HEAD)
		_dressed[slot_type] = piece


## Los materiales planetarios se reparten entre todas las copias de la pieza (también la que
## lleva el jugador, a la que el planeta mueve la luz): el muñeco usa los suyos.
func _light_for_studio(piece: Node) -> void:
	for node in piece.find_children("*", "MeshInstance3D", true, false) + [piece]:
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as ShaderMaterial
			if material == null or material.get_shader_parameter(&"light_direction") == null:
				continue
			material = material.duplicate()
			material.set_shader_parameter(&"light_direction", STUDIO_LIGHT.normalized())
			material.set_shader_parameter(&"planet_position", STUDIO_PLANET)
			mesh.set_surface_override_material(surface, material)


func _on_slot_clicked(slot: EquipmentSlot, button_index: int) -> void:
	if button_index == MOUSE_BUTTON_LEFT:
		slot_clicked.emit(slot)


func equip_item(slot: EquipmentSlot, item: InventoryItem) -> InventoryItem:
	if not slot or not item:
		return null
	if not item.data.fits_slot(slot.slot_type):
		return item
	var old_item: InventoryItem = null

	if slot.has_item():
		old_item = slot.equipped_item
		equipment_changed.emit(slot.slot_type, old_item, false)

	var equip_item = InventoryItem.new(item.data, 1)
	slot.set_item(equip_item)
	equipment_changed.emit(slot.slot_type, equip_item, true)
	_refresh_if_shown()
	return old_item


func unequip_item(slot: EquipmentSlot) -> InventoryItem:
	if not slot or not slot.has_item():
		return null

	var item = slot.equipped_item
	slot.clear()
	equipment_changed.emit(slot.slot_type, item, false)
	_refresh_if_shown()
	return item


func get_slot(slot_type: ItemData.ArmorSlot) -> EquipmentSlot:
	return equipment_slots.get(slot_type)


func get_equipped_item(slot_type: ItemData.ArmorSlot) -> InventoryItem:
	var slot = get_slot(slot_type)
	if slot:
		return slot.equipped_item
	return null


## Las piezas de ropa y armadura puestas.
func get_armor_pieces() -> Array[ItemData]:
	var pieces: Array[ItemData] = []
	for slot_type in LEFT_SLOTS:
		var item := get_equipped_item(slot_type)
		if item != null:
			pieces.append(item.data)
	return pieces


## Lo que suman las piezas puestas contra cada tipo de golpe (x tajo, y contundente, z perforante),
## cubran lo que cubran (Armor.total).
func get_armor() -> Vector3:
	return Armor.total(get_armor_pieces())


func _refresh_if_shown() -> void:
	if panel != null and panel.is_visible_in_tree():
		_sync_dress()

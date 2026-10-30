class_name DeathLoot
extends Node3D

## Bolsa de lo que se llevaba al morir, con la XP del nivel en curso (Progression.forfeit). Permanece
## hasta recuperarla o hasta la siguiente muerte, que destruye lo pendiente (objetos y XP) como
## castigo. Usa el botín común para recuperar lo que quepa; la XP vuelve al abrirla (take_xp).
const GROUP := &"death_loot"
const REACH := 2.6
const SCENE_PATH := "res://scenes/world/death_loot.tscn"

var inventory := Inventory.new()
## XP perdida al morir, que vuelve al abrir la bolsa.
var xp := 0.0
var entity_id := ""
var save_category := "remains"
var discard_on_load := true


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"floating_origin")
	add_to_group(GameManager.SAVEABLE_GROUP)
	if entity_id == "":
		entity_id = "death_loot_%d_%d" % [Time.get_unix_time_from_system(), randi()]
	add_child(inventory)
	inventory.inventory_changed.connect(_on_inventory_changed)
	var sack := DroppedItem._sack()
	sack.scale = Vector3.ONE * 2.5
	add_child(sack)
	var label := Label3D.new()
	label.text = "DEATH_LOOT_LABEL"
	label.position.y = 1.2
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.visibility_range_end = 60.0
	add_child(label)


static func spawn(player: PlayerController, content: Array[InventoryItem], lost_xp := 0.0) -> DeathLoot:
	if content.is_empty() and lost_xp <= 0.0:
		return null
	var loot := (load(SCENE_PATH) as PackedScene).instantiate() as DeathLoot
	loot.inventory.max_slots = maxi(content.size(), 1)
	loot.inventory.items.assign(content)
	loot.inventory.items.resize(loot.inventory.max_slots)
	loot.xp = lost_xp
	player.get_tree().current_scene.add_child(loot)
	loot.global_transform = player.global_transform.orthonormalized()
	return loot


## Se llama incluso al morir sin objetos. Retira también bolsas de partidas anteriores a esta regla.
static func discard_previous(tree: SceneTree) -> void:
	for node in tree.get_nodes_in_group(GROUP):
		var loot := node as DeathLoot
		if loot != null:
			loot._discard()


static func nearest(tree: SceneTree, position: Vector3) -> DeathLoot:
	var best: DeathLoot
	var distance := REACH
	for node in tree.get_nodes_in_group(GROUP):
		var loot := node as DeathLoot
		if loot == null or loot.is_queued_for_deletion() or loot.is_empty():
			continue
		var d := loot.global_position.distance_to(position)
		if d <= distance:
			best = loot
			distance = d
	return best


## Sin objetos ni XP que recuperar.
func is_empty() -> bool:
	return xp <= 0.0 and inventory.get_free_slots() == inventory.max_slots


## Saca la XP que guarda (al abrirla); si no quedan objetos, la bolsa se va.
func take_xp() -> float:
	var taken := xp
	xp = 0.0
	_discard_if_empty.call_deferred()
	return taken


func _on_inventory_changed() -> void:
	# La UI termina sus transferencias y desconecta el botín antes de retirar su nodo.
	_discard_if_empty.call_deferred()


func _discard_if_empty() -> void:
	if is_empty():
		_discard()


func _discard() -> void:
	# No se puede saquear ni guardar de nuevo en el fotograma anterior a queue_free.
	remove_from_group(GROUP)
	remove_from_group(GameManager.SAVEABLE_GROUP)
	hide()
	queue_free()


func get_save_data() -> Dictionary:
	var frame := global_transform
	var fo := get_tree().get_first_node_in_group("floating_origin_manager") as FloatingOrigin
	if fo != null:
		frame.origin = fo.to_canonical(frame.origin)
	return {"transform": DroppedItem.VisualState.encode(frame), "inventory": inventory.get_save_data(), "xp": xp}


func restore_save_data(data: Dictionary) -> void:
	var frame: Variant = DroppedItem.VisualState.decode(data.get("transform", ""))
	if frame is Transform3D:
		var fo := get_tree().get_first_node_in_group("floating_origin_manager") as FloatingOrigin
		if fo != null:
			frame.origin = fo.from_canonical(frame.origin)
		global_transform = frame
	if not inventory.restore_save_data(data.get("inventory", {})):
		push_error("DeathLoot: no se pudo restaurar '%s'" % entity_id)
	xp = maxf(float(data.get("xp", 0.0)), 0.0)

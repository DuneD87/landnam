extends Node

## Lo que da cada animal al despellejarlo lo dice su escena (NPCController.butcher_loot): que todas
## las especies lo traigan y que HuntingLoot lo escale por el tamaño y el cuchillo.
##   godot --headless --path . res://tests/items/test_hunting_loot.tscn

const Config = preload("res://scripts/config.gd")
const ANIMALS := "res://scenes/animals/"

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
	var missing: Array[String] = []
	var species := 0
	for file in DirAccess.get_files_at(ANIMALS):
		file = file.trim_suffix(".remap")
		if not file.ends_with(".tscn") or file.begins_with("ambient_"):
			continue
		var npc := (load(ANIMALS + file) as PackedScene).instantiate() as NPCController
		if npc == null:
			continue
		species += 1
		var loot := npc.butcher_loot
		if loot == null or loot.entries.is_empty() or loot.entries.any(func(e: LootEntry) -> bool:
				return e == null or Config.get_item(e.item) == null or e.amount <= 0):
			missing.append(file)
		npc.free()
	check(species >= 29, "hay especies (%d)" % species)
	check(missing.is_empty(), "todas traen lo que dan, con objetos que existen %s" % [missing])

	var deer := (load(ANIMALS + "Deer.tscn") as PackedScene).instantiate() as NPCController
	add_child(deer)
	var meat := Config.get_item(&"raw_meat")
	var hide := Config.get_item(&"raw_hide")
	deer.body_size = 1.0
	HuntingLoot.fill(deer, 1.0)
	var adult := deer.inventory.get_item_count(meat)
	check(adult >= 2 and adult <= 4 and deer.inventory.get_item_count(hide) >= 1,
		"un ciervo adulto da su carne (%d, de 3 ±20 %%) y piel" % adult)
	deer.body_size = 2.0
	HuntingLoot.fill(deer, 1.5)
	check(deer.inventory.get_item_count(meat) >= 7, "uno grande con buen cuchillo da más (%d)" % deer.inventory.get_item_count(meat))
	deer.butcher_loot = null
	HuntingLoot.fill(deer, 1.0)
	check(deer.inventory.get_item_count(meat) >= 1 and deer.inventory.get_item_count(hide) >= 1,
		"sin lo suyo, carne y piel por el grosor del cuerpo")
	print("RESULT: ", "OK" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)

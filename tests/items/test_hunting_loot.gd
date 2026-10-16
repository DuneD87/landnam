extends Node

## Lo que da cada animal al despellejarlo lo dice su escena (NPCController.butcher_loot): que todas
## las especies lo traigan y que HuntingLoot lo escale por el tamaño y el cuchillo. La fauna pequeña lo
## lleva en su perfil (AmbientFaunaProfile.butcher_loot) y lo pasa a su cadáver (FaunaCorpse): que lo
## traigan las que se despiezan, que los ratones no, y que el cadáver se llene, guarde lo que se le
## clavó y deje de contar cuando ya no le queda nada.
##   godot --headless --path . res://tests/items/test_hunting_loot.tscn

const Config = preload("res://scripts/config.gd")
const ANIMALS := "res://scenes/animals/"
const FAUNA := "res://data/fauna/"
## Los perfiles de fauna pequeña que se despiezan y los que no.
const SMALL := ["rabbits", "arctic_hares", "foxes", "arctic_foxes", "forest_birds", "coastal_gulls", "river_ducks"]
const TOO_SMALL := ["mice", "lemmings"]

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
	deer.inventory.clear()
	HuntingLoot.fill(deer, 1.5)
	check(deer.inventory.get_item_count(meat) >= 7, "uno grande con buen cuchillo da más (%d)" % deer.inventory.get_item_count(meat))
	var antlers := deer.inventory.get_item_count(Config.get_item(&"antler"))
	check(antlers == 2, "las astas van por par, sin crecer con el tamaño (%d)" % antlers)
	deer.butcher_loot = null
	deer.inventory.clear()
	HuntingLoot.fill(deer, 1.0)
	check(deer.inventory.get_item_count(meat) >= 1 and deer.inventory.get_item_count(hide) >= 1,
		"sin lo suyo, carne y piel por el grosor del cuerpo")
	var arrow := Config.get_item(&"arrow")
	deer.inventory.clear()
	deer.inventory.add_item(arrow, 1)
	HuntingLoot.fill(deer, 1.0)
	check(deer.inventory.get_item_count(arrow) == 1, "despiezarlo no quita la flecha que se le clavó")
	await _check_small()
	print("RESULT: ", "OK" if failures == 0 else "%d FAILED" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check_small() -> void:
	var missing: Array[String] = []
	for name in SMALL:
		var profile := load(FAUNA + name + ".tres") as AmbientFaunaProfile
		var loot := profile.butcher_loot if profile != null else null
		if loot == null or loot.entries.is_empty() or loot.entries.any(func(e: LootEntry) -> bool:
				return e == null or Config.get_item(e.item) == null or e.amount <= 0):
			missing.append(name)
	check(missing.is_empty(), "la fauna pequeña que se despieza trae lo que da %s" % [missing])
	var listed: Array[String] = []
	for name in TOO_SMALL:
		if (load(FAUNA + name + ".tres") as AmbientFaunaProfile).butcher_loot != null:
			listed.append(name)
	check(listed.is_empty(), "ratones y lémmings no se despiezan %s" % [listed])
	var feathers := 0
	for e in (load(FAUNA + "forest_birds.tres") as AmbientFaunaProfile).butcher_loot.entries:
		feathers += e.amount if e.item == &"feather" else 0
	check(feathers > 0, "las aves dan plumas (%d)" % feathers)

	# Un cadáver de conejo de mentira: una caja de 15 x 25 x 40 cm que mira a -Z.
	var model := Node3D.new()
	add_child(model)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.15, 0.25, 0.4)
	mesh.mesh = box
	model.add_child(mesh)
	var corpse := FaunaCorpse.spawn(self, model, Vector3.ZERO, Vector3.DOWN * 9.8, 1)
	check(corpse != null, "deja cadáver")
	if corpse == null:
		return
	var shape := corpse.butcher_shape()
	check(is_equal_approx(shape.x, 0.075) and is_equal_approx(shape.y, 0.4 * FaunaCorpse.BODY_LENGTH),
		"sin la criatura, su grueso y su largo salen de su caja (%s)" % shape)
	check(not corpse.butcherable(), "sin lo que da su especie no se despieza")
	var rabbits := load(FAUNA + "rabbits.tres") as AmbientFaunaProfile
	corpse.set_hunt(rabbits.butcher_loot, 1.0, 0.12, Color.TRANSPARENT)
	check(corpse.butcherable() and is_equal_approx(corpse.butcher_shape().x, 0.12), "con lo suyo se despieza, al grueso de la criatura")
	check(FaunaCorpse.nearest(corpse.global_position + Vector3.RIGHT, 2.5) == corpse
		and FaunaCorpse.nearest(corpse.global_position + Vector3.RIGHT * 3.0, 2.5) == null,
		"E lo encuentra cerca y no lejos")
	var arrow := Config.get_item(&"arrow")
	corpse.inventory.add_item(arrow, 1)
	corpse.butcher_progress = 0.5
	await get_tree().process_frame
	check(corpse.freeze, "despiezándolo se queda quieto")
	HuntingLoot.fill(corpse, 1.0)
	corpse.butchered = true
	var meat := corpse.inventory.get_item_count(Config.get_item(&"raw_meat"))
	check(meat == 1 and corpse.inventory.get_item_count(arrow) == 1,
		"un conejo da su carne (%d) y guarda la flecha" % meat)
	check(corpse.butcherable(), "despiezado, se saquea mientras le quede algo")
	corpse.inventory.clear()
	check(not corpse.butcherable(), "vacío, E ya no lo coge")
	corpse.queue_free()
	model.queue_free()

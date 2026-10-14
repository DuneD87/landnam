extends Node

## Al despiezar un animal se le cortan los miembros que le quedan (AnimalGore.butcher_cuts): que
## todas las especies tengan tabla de cortes (las que no traen la suya, sacada de sus huesos) con
## cuatro patas, cuello y cola, y que un miembro ya cortado no se vuelva a ofrecer.
##   godot --headless --path . res://tests/combat/test_butcher_cuts.tscn

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
	var short: Array[String] = []
	for file in DirAccess.get_files_at(ANIMALS):
		file = file.trim_suffix(".remap")
		if not file.ends_with(".tscn") or file.begins_with("ambient_"):
			continue
		var npc := (load(ANIMALS + file) as PackedScene).instantiate() as NPCController
		if npc == null:
			continue
		add_child(npc)
		var gore := npc.get_node_or_null(^"AnimalGore") as AnimalGore
		var cuts: Array[StringName] = gore.butcher_cuts() if gore != null else []
		print("  %s: %s" % [file, cuts])
		# Cuatro patas y el cuello; la cola, si la tiene (el elefante, la de unos pocos huesos).
		if cuts.size() < 5:
			short.append(file)
		npc.queue_free()
		await get_tree().process_frame
	check(short.is_empty(), "todas las especies tienen al menos cuatro patas y el cuello que cortar %s" % [short])

	var deer := (load(ANIMALS + "Deer.tscn") as PackedScene).instantiate() as NPCController
	add_child(deer)
	var gore := deer.get_node_or_null(^"AnimalGore") as AnimalGore
	var before := gore.butcher_cuts()
	var leg := before[0]
	var lower: StringName = gore.dismemberment.cuttable[leg][0]
	# Cortado por abajo (el golpe que lo mató), esa pata ya no se ofrece.
	var skel := gore.dismemberment.skeleton
	for bone: StringName in gore.dismemberment.cuttable:
		if skel.get_bone_parent(skel.find_bone(bone)) == skel.find_bone(lower) or bone == lower:
			gore.dismemberment.add_saved(bone, 0.5, Vector3.ZERO, Vector3.UP)
			break
	var after := gore.butcher_cuts()
	check(not after.has(leg) and after.size() == before.size() - 1,
		"una pata ya cortada por abajo no se vuelve a cortar (%s → %s)" % [before, after])
	deer.queue_free()
	await get_tree().process_frame
	print("RESULT: ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	get_tree().quit(failures)

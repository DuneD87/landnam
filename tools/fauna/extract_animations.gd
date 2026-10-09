extends SceneTree

## Saca las animaciones de un modelo importado (el FBX de un animal de un pack, como los de
## WildMesh) a una AnimationLibrary para el AnimationPlayer de la escena del animal:
##   - quita el prefijo de la toma ("SK-Wolf|Walk" → "Walk");
##   - pone en bucle los ciclos (los nombres que casan con --loop; comodines * y ?);
##   - cuelga las pistas de --root, el nodo del modelo instanciado bajo NPCModel, para que el
##     AnimationPlayer de NPCModel encuentre el esqueleto;
##   - con --alias="Idle:Idle_Breathing,Walk:WalkMedium_F", da además a esos clips el nombre común
##     que usan las escenas de criatura (el mismo clip, guardado una vez). Si el alias ya es un
##     clip, no lo pisa.
## Se guarda en binario (.res): son decenas de clips con todas las claves.
##   godot --headless --path . --script res://tools/fauna/extract_animations.gd -- \
##       --source=res://models/animals/wolf/wolf.fbx --out=res://models/animals/Wolf_anims.res \
##       --root=wolf --loop="Idle*,Walk*,Trot*,Run*,Sprint*,Sneak*,Lying_*,Sitting_*"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	if not args.has("source") or not args.has("out"):
		push_error("Faltan --source y --out")
		quit(1)
		return
	var loops: PackedStringArray = String(args.get("loop", "")).split(",", false)
	var aliases := {}
	for pair in String(args.get("alias", "")).split(",", false):
		aliases[pair.get_slice(":", 0).strip_edges()] = pair.get_slice(":", 1).strip_edges()
	var root_path: String = args.get("root", "")
	var scene: Node = (load(args.source) as PackedScene).instantiate()
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_error("%s no trae AnimationPlayer" % args.source)
		quit(1)
		return
	var player := players[0] as AnimationPlayer
	var library := AnimationLibrary.new()
	var looped := 0
	for take in player.get_animation_list():
		var clip_name := String(take).get_slice("|", String(take).get_slice_count("|") - 1)
		var anim := player.get_animation(take).duplicate(true) as Animation
		for pattern in loops:
			if clip_name.match(pattern.strip_edges()):
				anim.loop_mode = Animation.LOOP_LINEAR
				looped += 1
				break
		if root_path != "":
			for track in anim.get_track_count():
				anim.track_set_path(track, NodePath("%s/%s" % [root_path, anim.track_get_path(track)]))
		library.add_animation(StringName(clip_name), anim)
	for alias in aliases:
		var source := StringName(aliases[alias])
		if library.has_animation(StringName(alias)):
			continue
		if not library.has_animation(source):
			push_error("--alias %s: no hay clip %s" % [alias, source])
			quit(1)
			return
		library.add_animation(StringName(alias), library.get_animation(source))
	scene.free()
	var err := ResourceSaver.save(library, args.out, ResourceSaver.FLAG_COMPRESS)
	print("%d animaciones (%d en bucle) → %s (%s)" % [library.get_animation_list().size(), looped, args.out, error_string(err)])
	quit(0 if err == OK else 1)

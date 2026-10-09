extends SceneTree

## Saca de un FBX de un pack de animales (WildMesh) lo que el juego usa, para no meter el FBX en el
## repositorio: traen todas sus animaciones y pesan decenas o cientos de MB.
##   - El modelo (mallas, esqueleto y piel) como escena .scn, con los mismos nombres de nodo que el
##     FBX importado, así que los clips sacados de él le sirven tal cual. Sin materiales (los pone
##     cada especie) y con su AnimationPlayer vacío (SkinnedModel le pone la librería).
##   - Los clips que se piden (--clips, con comodines; sin --clips, todos) en una AnimationLibrary,
##     sin el prefijo de la toma ("SK-Wolf|Walk" → "Walk"), en bucle los que casan con --loop, con
##     los alias de --alias ("Idle:Idle_Breathing": el mismo clip con el nombre común de las
##     escenas de criatura) y, con --root, colgando las pistas del nodo del modelo bajo NPCModel.
## --add="Death:res://models/animals/horse/horse_death.res" añade a la librería clips sacados de otro
## animal con tools/fauna/retarget_clip.gd (con --track_root al nodo del modelo bajo NPCModel).
## El FBX se copia antes a models/_pack/ (fuera de git) para que Godot lo importe.
##   godot --headless --path . --script res://tools/fauna/import_pack_model.gd -- \
##       --source=res://models/_pack/boar/SK_Boar.fbx --out=res://models/animals/boar/boar.scn \
##       --anims=res://models/animals/boar/boar_anims.res --clips="Idle_Breathing,WalkMedium_F,RunFast_F" \
##       [--loop="Idle*,Walk*,Run*"] [--alias="Idle:Idle_Breathing,Run:WalkMedium_F"] [--root=boar]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	for key in ["source", "out", "anims"]:
		if not args.has(key):
			push_error("Falta --%s" % key)
			quit(1)
			return
	var scene: Node3D = (load(args.source) as PackedScene).instantiate()
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_error("%s no trae AnimationPlayer" % args.source)
		quit(1)
		return
	var player := players[0] as AnimationPlayer
	var library := _library(player, args)
	if library == null:
		quit(1)
		return
	var err := ResourceSaver.save(library, args.anims, ResourceSaver.FLAG_COMPRESS)
	print("%d clips → %s (%s)" % [library.get_animation_list().size(), args.anims, error_string(err)])
	if err != OK:
		quit(1)
		return
	# El modelo: sus recursos, copias propias, para que la escena no dependa del FBX importado.
	for library_name in player.get_animation_library_list():
		player.remove_animation_library(library_name)
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh.duplicate() as ArrayMesh
		mesh.shadow_mesh = null
		for i in mesh.get_surface_count():
			mesh.surface_set_material(i, null)
		mesh_instance.mesh = mesh
		if mesh_instance.skin != null:
			mesh_instance.skin = mesh_instance.skin.duplicate()
		for i in mesh_instance.get_surface_override_material_count():
			mesh_instance.set_surface_override_material(i, null)
	var packed := PackedScene.new()
	err = packed.pack(scene)
	if err == OK:
		err = ResourceSaver.save(packed, args.out, ResourceSaver.FLAG_COMPRESS)
	scene.free()
	var dependencies := ResourceLoader.get_dependencies(args.out)
	print("modelo → %s (%s), dependencias: %s" % [args.out, error_string(err), dependencies])
	quit(0 if err == OK and dependencies.is_empty() else 1)


func _library(player: AnimationPlayer, args: Dictionary) -> AnimationLibrary:
	var wanted: PackedStringArray = String(args.get("clips", "")).split(",", false)
	var loops: PackedStringArray = String(args.get("loop", "")).split(",", false)
	var root_path: String = args.get("root", "")
	var aliases := {}
	for pair in String(args.get("alias", "")).split(",", false):
		aliases[pair.get_slice(":", 0).strip_edges()] = pair.get_slice(":", 1).strip_edges()
	var library := AnimationLibrary.new()
	for take in player.get_animation_list():
		var clip_name := String(take).get_slice("|", String(take).get_slice_count("|") - 1)
		var keep := wanted.is_empty() or aliases.values().has(clip_name)
		for pattern in wanted:
			keep = keep or clip_name.match(pattern.strip_edges())
		if not keep:
			continue
		var anim := player.get_animation(take).duplicate(true) as Animation
		for pattern in loops:
			if clip_name.match(pattern.strip_edges()):
				anim.loop_mode = Animation.LOOP_LINEAR
				break
		if root_path != "":
			for track in anim.get_track_count():
				anim.track_set_path(track, NodePath("%s/%s" % [root_path, anim.track_get_path(track)]))
		library.add_animation(StringName(clip_name), anim)
	for pair in String(args.get("add", "")).split(",", false):
		var added := load(pair.get_slice(":", 1).strip_edges() + ":" + pair.get_slice(":", 2).strip_edges()) as Animation \
			if pair.get_slice_count(":") > 2 else null
		if added == null:
			push_error("--add: no se puede cargar %s" % pair)
			return null
		library.add_animation(StringName(pair.get_slice(":", 0).strip_edges()), added)
	for alias in aliases:
		var source := StringName(aliases[alias])
		if library.has_animation(StringName(alias)):
			continue
		if not library.has_animation(source):
			push_error("--alias %s: no hay clip %s" % [alias, source])
			return null
		library.add_animation(StringName(alias), library.get_animation(source))
	for pattern in wanted:
		if not library.get_animation_list().any(func(clip: StringName) -> bool: return String(clip).match(pattern.strip_edges())):
			push_error("--clips: ninguno casa con %s" % pattern)
			return null
	return library

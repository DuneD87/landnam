extends SceneTree

## Quita de un modelo del pack (.scn) y de su librería de clips los huesos que no hacen nada: los que
## no deforman ninguna malla, ni son ancestros de uno que sí, ni los nombra el juego. Los rigs del
## pack traen muchos (IK, ayudantes, puntas), y cada hueso cuesta en cada fotograma aunque no mueva
## un vértice: sus pistas se mezclan en el AnimationTree, se posa en el esqueleto y, si tiene bind en
## la piel, se sube al servidor de render.
##   godot --headless --path . --script res://tools/fauna/prune_skeleton.gd -- \
##       [--creature=res://scenes/animals/Wildebeest.tscn] [--dry]
## Sin --creature, todas las criaturas de scenes/animals con modelo .scn propio. --dry solo informa.
##
## Se conservan por nombre, aunque no tengan peso:
##   - cualquier texto de la escena de criatura o de sus recursos con script (perfil de combate,
##     ataques, golpes) que coincida con un hueso: head_bone, flinch_bones, CreatureHit.bones…;
##   - los huesos de las tablas de AnimalGore (mutilaciones) y sus puntas;
##   - los de los BoneAttachment3D del modelo.
## La malla no se vuelve a codificar: solo se renumeran los índices de hueso de cada vértice en su
## bloque de piel, así que se mantienen la compresión, los LOD y las formas de mezcla.

const ANIMALS_DIR := "res://scenes/animals"
## Por ruta y no por class_name: su script arrastra autoloads que aún no existen al compilar esto.
const GORE_SCRIPT := "res://scripts/combat/animal_gore.gd"
## Clave de used_binds para las mallas sin Skin: sus vértices apuntan a huesos del esqueleto.
const NO_SKIN := &"sin_skin"

var _dry := false
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--dry":
			_dry = true
		elif arg.begins_with("--creature="):
			only = arg.substr(11)
	var paths: Array[String] = []
	if only != "":
		paths.append(only)
	else:
		for file in DirAccess.get_files_at(ANIMALS_DIR):
			if file.ends_with(".tscn"):
				paths.append("%s/%s" % [ANIMALS_DIR, file])
	for path in paths:
		_prune_creature(path)
	print("PODA: %d fallos" % _failures)
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	push_error(message)


func _prune_creature(creature_path: String) -> void:
	var creature := (load(creature_path) as PackedScene).instantiate()
	var model_node: Node = null
	var npc_model := creature.get_node_or_null("NPCModel")
	if npc_model != null:
		for child in npc_model.get_children():
			if child.scene_file_path.ends_with(".scn"):
				model_node = child
	var player := npc_model.get_node_or_null("AnimationPlayer") as AnimationPlayer if npc_model else null
	if model_node == null or player == null:
		creature.free()
		return # Sin modelo .scn propio (los antiguos o el lobo, que usa el FBX).
	var model_path := model_node.scene_file_path
	var libraries: Array[AnimationLibrary] = []
	for lib_name in player.get_animation_library_list():
		libraries.append(player.get_animation_library(lib_name))
	var creature_skeleton := model_node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var names := {}
	for i in creature_skeleton.get_bone_count():
		names[creature_skeleton.get_bone_name(i)] = true
	var referenced := {}
	_collect_names(creature, names, referenced, {})
	for table in (load(GORE_SCRIPT) as Script).get_script_constant_map()["TABLES"]:
		for bone in table:
			referenced[String(bone)] = true
			referenced[String(table[bone][0])] = true
	creature.free()
	_prune_model(creature_path.get_file().get_basename(), model_path, libraries, referenced)


## Los textos de [node] y de lo que cuelga de él (propiedades de script, recursos con script y sus
## arrays) que son nombres de hueso.
func _collect_names(object: Object, bones: Dictionary, out: Dictionary, seen: Dictionary) -> void:
	if object == null or seen.has(object.get_instance_id()):
		return
	seen[object.get_instance_id()] = true
	if object is BoneAttachment3D:
		out[(object as BoneAttachment3D).bone_name] = true
	if object.get_script() != null:
		for prop in object.get_property_list():
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				_collect_value(object.get(prop.name), bones, out, seen)
	if object is Node:
		for child in (object as Node).get_children():
			_collect_names(child, bones, out, seen)


func _collect_value(value: Variant, bones: Dictionary, out: Dictionary, seen: Dictionary) -> void:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			if bones.has(String(value)):
				out[String(value)] = true
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			for item in value:
				_collect_value(item, bones, out, seen)
		TYPE_DICTIONARY:
			for key in value:
				_collect_value(key, bones, out, seen)
				_collect_value(value[key], bones, out, seen)
		TYPE_OBJECT:
			if value is Resource and (value as Resource).get_script() != null:
				_collect_names(value, bones, out, seen)


func _prune_model(id: String, model_path: String, libraries: Array[AnimationLibrary], referenced: Dictionary) -> void:
	var model := (load(model_path) as PackedScene).instantiate()
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var meshes: Array[MeshInstance3D] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh is ArrayMesh:
			meshes.append(mi)
	for node in model.find_children("*", "BoneAttachment3D", true, false):
		referenced[(node as BoneAttachment3D).bone_name] = true

	# Binds con peso en alguna superficie, por piel (o por hueso, en las mallas sin Skin).
	var used_binds := {} # Skin o NO_SKIN -> {bind: true}
	var skinned: Array[MeshInstance3D] = []
	for mi in meshes:
		if mi.mesh.get_surface_count() == 0 or mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_BONES] == null:
			continue # Rígida: no se toca.
		skinned.append(mi)
		var key: Variant = mi.skin if mi.skin != null else NO_SKIN
		var used: Dictionary = used_binds.get(key, {})
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if bones == null or bones.is_empty():
				continue
			for i in bones.size():
				if weights[i] > 0.0:
					used[bones[i]] = true
		used_binds[key] = used

	# Huesos que se quedan: los de binds con peso y los nombrados, con todos sus ancestros.
	var keep := {}
	var seeds: Array[int] = []
	for skin in used_binds:
		for bind in used_binds[skin]:
			seeds.append(_bind_bone(skin, bind, skeleton))
	for bone_name in referenced:
		var b := skeleton.find_bone(bone_name)
		if b >= 0:
			seeds.append(b)
	for b in seeds:
		while b >= 0 and not keep.has(b):
			keep[b] = true
			b = skeleton.get_bone_parent(b)
	var old_count := skeleton.get_bone_count()
	if keep.size() == old_count:
		print("%s: nada que podar (%d huesos)" % [id, old_count])
		model.free()
		return

	var kept_names := {}
	for b in keep:
		kept_names[skeleton.get_bone_name(b)] = true
	var track_total := 0
	var track_cut := 0
	# Los clips externos (muertes y mordiscos pasados de otro animal) solo los usa su librería: se
	# podan y se guardan con ella.
	var external: Array[Animation] = []
	for lib in libraries:
		for anim_name in lib.get_animation_list():
			var anim := lib.get_animation(anim_name)
			if not anim.resource_path.is_empty() and not anim.resource_path.contains("::"):
				external.append(anim)
			for t in range(anim.get_track_count() - 1, -1, -1):
				var path := anim.track_get_path(t)
				if path.get_subname_count() == 0:
					continue
				var bone_name := path.get_concatenated_subnames()
				if skeleton.find_bone(bone_name) < 0:
					continue
				track_total += 1
				if not kept_names.has(bone_name):
					track_cut += 1
					if not _dry:
						anim.remove_track(t)

	# Pieles nuevas con solo los binds usados, y cómo se renumeran.
	var remaps := {} # Skin vieja o NO_SKIN -> PackedInt32Array (bind viejo -> nuevo, -1 si se va)
	var new_skins := {}
	var bind_total := 0
	var bind_kept := 0
	if used_binds.has(NO_SKIN):
		var order: Array = keep.keys()
		order.sort()
		var remap := PackedInt32Array()
		remap.resize(old_count)
		remap.fill(-1)
		for i in order.size():
			remap[order[i]] = i
		remaps[NO_SKIN] = remap
	for skin in used_binds:
		if skin is StringName:
			continue
		var remap := PackedInt32Array()
		remap.resize(skin.get_bind_count())
		remap.fill(-1)
		var fresh := Skin.new()
		for bind in skin.get_bind_count():
			if not used_binds[skin].has(bind):
				continue
			remap[bind] = fresh.get_bind_count()
			fresh.add_named_bind(skeleton.get_bone_name(_bind_bone(skin, bind, skeleton)), skin.get_bind_pose(bind))
		bind_total += skin.get_bind_count()
		bind_kept += fresh.get_bind_count()
		remaps[skin] = remap
		new_skins[skin] = fresh

	print("%s: huesos %d -> %d, binds %d -> %d, pistas %d -> %d" % [id, old_count, keep.size(),
		bind_total, bind_kept, track_total, track_total - track_cut])

	var done := {}
	for mi in skinned:
		if done.has(mi.mesh):
			continue
		done[mi.mesh] = true
		if not _remap_mesh(id, mi.mesh as ArrayMesh, remaps[mi.skin if mi.skin != null else NO_SKIN]):
			model.free()
			return
	if _dry:
		model.free()
		return

	_rebuild_skeleton(skeleton, keep)
	for mi in skinned:
		if mi.skin != null:
			mi.skin = new_skins[mi.skin]
			_check_binds(id, mi, skeleton)
	if _failures > 0:
		model.free()
		return

	var uid := ResourceLoader.get_resource_uid(model_path)
	var packed := PackedScene.new()
	var err := packed.pack(model)
	model.free()
	if err != OK:
		_fail("%s: no se pudo empaquetar el modelo (%s)" % [id, error_string(err)])
		return
	err = ResourceSaver.save(packed, model_path)
	if err != OK:
		_fail("%s: no se pudo guardar %s (%s)" % [id, model_path, error_string(err)])
		return
	if ResourceLoader.get_resource_uid(model_path) != uid:
		_fail("%s: %s ha cambiado de UID" % [id, model_path])
	for anim in external:
		err = ResourceSaver.save(anim, anim.resource_path)
		if err != OK:
			_fail("%s: no se pudo guardar %s (%s)" % [id, anim.resource_path, error_string(err)])
	for lib in libraries:
		err = ResourceSaver.save(lib, lib.resource_path)
		if err != OK:
			_fail("%s: no se pudo guardar %s (%s)" % [id, lib.resource_path, error_string(err)])


func _bind_bone(skin: Variant, bind: int, skeleton: Skeleton3D) -> int:
	if skin is StringName:
		return bind
	var bind_name: StringName = (skin as Skin).get_bind_name(bind)
	return skeleton.find_bone(bind_name) if bind_name != &"" else (skin as Skin).get_bind_bone(bind)


## Renumera los índices de hueso del bloque de piel de cada superficie según [remap], sin tocar nada
## más. Antes comprueba que el bloque se lee igual que surface_get_arrays, y después, que lo nuevo es
## lo viejo renumerado con los mismos pesos.
func _remap_mesh(id: String, mesh: ArrayMesh, remap: PackedInt32Array) -> bool:
	var surfaces: Array = mesh.get("_surfaces")
	var before: Array = []
	for s in surfaces.size():
		var arrays := mesh.surface_get_arrays(s)
		before.append([arrays[Mesh.ARRAY_BONES], arrays[Mesh.ARRAY_WEIGHTS]])
		var surface: Dictionary = surfaces[s]
		var skin_data: PackedByteArray = surface.get("skin_data", PackedByteArray())
		if skin_data.is_empty():
			continue
		var per := 8 if (int(surface.format) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) else 4
		var stride := per * 4
		var vertices: int = surface.vertex_count
		if skin_data.size() != stride * vertices:
			_fail("%s: la superficie %d tiene un bloque de piel de %d bytes, se esperaban %d" % [id, s, skin_data.size(), stride * vertices])
			return false
		var bones: PackedInt32Array = before[s][0]
		for v in vertices:
			for k in per:
				if skin_data.decode_u16(v * stride + k * 2) != bones[v * per + k]:
					_fail("%s: el bloque de piel de la superficie %d no se lee como surface_get_arrays" % [id, s])
					return false
		var weights: PackedFloat32Array = before[s][1]
		for v in vertices:
			for k in per:
				var i := v * per + k
				var target := remap[bones[i]] if bones[i] < remap.size() else -1
				if target < 0:
					if weights[i] > 0.0:
						_fail("%s: un vértice con peso apunta a un bind que se quita" % id)
						return false
					target = 0 # Sin peso, da igual a qué hueso apunte.
				skin_data.encode_u16(v * stride + k * 2, target)
		surface["skin_data"] = skin_data
		var aabbs: Array = surface.get("bone_aabbs", [])
		if not aabbs.is_empty():
			var fresh: Array = []
			var kept := 0
			for bind in remap.size():
				if remap[bind] >= 0:
					kept += 1
			fresh.resize(kept)
			for bind in remap.size():
				if remap[bind] >= 0:
					fresh[remap[bind]] = aabbs[bind] if bind < aabbs.size() else AABB(Vector3.ZERO, Vector3(-1, -1, -1))
			surface["bone_aabbs"] = fresh
	if _dry:
		return true
	mesh.set("_surfaces", surfaces)
	for s in surfaces.size():
		var arrays := mesh.surface_get_arrays(s)
		var old_bones: PackedInt32Array = before[s][0]
		var old_weights: PackedFloat32Array = before[s][1]
		if old_bones.is_empty():
			continue
		var new_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var new_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if new_weights != old_weights or new_bones.size() != old_bones.size():
			_fail("%s: la superficie %d ha cambiado de pesos al renumerar" % [id, s])
			return false
		for i in old_bones.size():
			if old_weights[i] > 0.0 and new_bones[i] != remap[old_bones[i]]:
				_fail("%s: la superficie %d no ha quedado renumerada" % [id, s])
				return false
	return true


## Vuelve a montar el esqueleto con los huesos de [keep], en el mismo orden, con su padre, reposo y
## pose.
func _rebuild_skeleton(skeleton: Skeleton3D, keep: Dictionary) -> void:
	var order: Array = keep.keys()
	order.sort()
	var index := {}
	for b in order:
		index[b] = index.size()
	var bones: Array[Dictionary] = []
	for b in order:
		var parent := skeleton.get_bone_parent(b)
		bones.append({
			"name": skeleton.get_bone_name(b),
			"parent": index[parent] if parent >= 0 else -1,
			"rest": skeleton.get_bone_rest(b),
			"position": skeleton.get_bone_pose_position(b),
			"rotation": skeleton.get_bone_pose_rotation(b),
			"scale": skeleton.get_bone_pose_scale(b),
			"enabled": skeleton.is_bone_enabled(b),
		})
	skeleton.clear_bones()
	for bone in bones:
		skeleton.add_bone(bone.name)
	for i in bones.size():
		skeleton.set_bone_parent(i, bones[i].parent)
		skeleton.set_bone_rest(i, bones[i].rest)
		skeleton.set_bone_pose_position(i, bones[i].position)
		skeleton.set_bone_pose_rotation(i, bones[i].rotation)
		skeleton.set_bone_pose_scale(i, bones[i].scale)
		skeleton.set_bone_enabled(i, bones[i].enabled)


func _check_binds(id: String, mi: MeshInstance3D, skeleton: Skeleton3D) -> void:
	for bind in mi.skin.get_bind_count():
		if skeleton.find_bone(mi.skin.get_bind_name(bind)) < 0:
			_fail("%s: el bind %s de %s no tiene hueso" % [id, mi.skin.get_bind_name(bind), mi.name])

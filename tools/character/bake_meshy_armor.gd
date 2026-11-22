extends SceneTree

## Builds the equipable armour fitted by tools/character/blender/fit_meshy_armor.py
## or made by tools/character/blender/build_fur_armor.py:
## per piece its textures, its skinned mesh (the garment and, if it has one,
## its lining, each with its material, with LODs: MeshLods) and an
## equipable scene, a MeshItem with the piece's ItemData (ITEMS/<id>.tres,
## which must exist), laid out like the player's other armour. The mesh is in
## the space of the player scan's skin and uses that Skin, so ArmorFit carries
## it from the scan onto each body as it does every armour.
##
##   godot --headless --path . --script res://tools/character/bake_meshy_armor.gd -- [--bronze] <fit output dir> [piece ...]
##
## A piece whose textures are not there yet only gets them (and their import
## settings): import them (godot --headless --import) and run it again.
##
## A skirt that hangs from the skirt's bones (SkirtBones) gets SKIRT_SKIN: the
## scan's Skin with their binds, from their rest on the character's skeleton;
## a pelt whose forelegs swing from theirs (PeltBones), PELT_SKIN.
##
## The fur garments (build_fur_armor.py) name a shared material on each
## surface instead of bringing maps: fur_card (hair cards, fur_card.gdshader
## and its fringe pass), pelt (the coat under them, fur_pelt.gdshader),
## leather, lace or bone, written to FUR with the maps of
## tools/character/blender/render_fur_maps.py and make_fur_textures.py, which
## must be imported first (the first run writes their import settings, as
## with Meshy's maps). Their surfaces carry vertex colours: each pelt's and
## hide's own, darkened where the garment's layers shade it.
##
## To regenerate weights without the original Meshy downloads:
##   ... -- --export-weights <dir> [piece ...]
##   (fit_meshy_armor.py --reweight; see docs/character_creation.md)
##   ... -- --weights <dir> [piece ...]
## Only the garment's weights change; geometry, UVs and lining are preserved.

const SKIN := "res://models/player/xavivar/firstage_human_male_player_skin.tres"
const SKIRT_SKIN := "res://models/player/xavivar/firstage_human_male_player_skirt_skin.tres"
const PELT_SKIN := "res://models/player/xavivar/firstage_human_male_player_pelt_skin.tres"
const CLOAK_SKIN := "res://models/player/xavivar/firstage_human_male_player_cloak_skin.tres"
const MODEL := "res://scenes/character/character_model.tscn"
const MESH_ITEM := "res://scripts/items/mesh_item.gd"
const FUR := "res://models/equipable/stone_age/fur/"
const FUR_SHADERS := "res://shaders/character/fur_%s.gdshader"
## Metres one repeat of each tileable map covers (make_fur_textures.py,
## render_fur_maps.py; build_fur_armor.py lays UVs in metres, but the hair
## cards' pick a lock of the atlas).
const FUR_TILES := {pelt = 0.08, leather = 0.35, lace = 0.03, bone = 0.05}
## The maps, and which are normal maps.
const FUR_MAPS := {fur_cards = false, fur_pelt = false, fur_pelt_normal = true, fur_pelt_albedo = false,
		leather_albedo = false,
		leather_normal = true, leather_roughness = false, lace_albedo = false, lace_normal = true,
		bone_albedo = false}
## Side of each map, and its JPEG quality.
const MAPS := {albedo = [2048, 0.9], normal = [2048, 0.95], roughness = [1024, 0.9], metallic = [1024, 0.9]}
## Meshy's roughness (0.6-0.7) shines like latex on fur and rawhide: it is
## squeezed into this range, keeping its pattern.
const ROUGHNESS_RANGE := Vector2(0.8, 1.0)
## Less shine and a softer relief than Meshy's maps, which glint on every tuft.
const SPECULAR := 0.25
const NORMAL_SCALE := 0.7
## Meshy paints its metal almost black (3-5 % reflectance; bronze reflects
## most of the light) and lets a bright studio HDRI make it shine: under the
## sky it looks like dull brown paint. Where its metallic map says metal, the
## albedo is brightened this much (linear) and saturated this much;
## the rest (leather) a little, as it is a shade dark too (tone_albedo()).
const METAL_GAIN := 8.0
const METAL_SATURATION := 1.3
const DIELECTRIC_GAIN := 1.5

var _models := "res://models/equipable/stone_age/"
var _scenes := "res://scenes/items/armor/stone_age/"
var _items := "res://data/items/Armor/StoneAge/"
var _bronze := false
var _fur_materials := {}


## See _tights(): metres; skin above TIGHTS_HIPS is round the waist.
const TIGHTS_MARGIN := 0.025
const TIGHTS_WAIST := 0.06
const TIGHTS_SECTORS := 24
const TIGHTS_HIPS := -0.15


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if "--bronze" in args:
		_bronze = true
		args.remove_at(args.find("--bronze"))
		_models = "res://models/equipable/bronze_age/"
		_scenes = "res://scenes/items/armor/bronze_age/"
		_items = "res://data/items/Armor/BronzeAge/"
	if args.is_empty() or (args[0].begins_with("--") and args.size() < 2):
		push_error("Expected <fit directory>, --export-weights <directory>, or --weights <directory>, followed by optional piece ids")
		quit(1)
		return
	if args[0] == "--export-weights" or args[0] == "--weights":
		quit(_reweight(args[1], args.slice(2), args[0] == "--export-weights"))
		return
	var source: String = args[0]
	var only := args.slice(1)
	var skins := {"": load(SKIN) as Skin}
	if _bronze:
		skins[SkirtBones.PREFIX] = load(SKIRT_SKIN)
		skins[PeltBones.PREFIX] = load(PELT_SKIN)
	else:
		skins[SkirtBones.PREFIX] = _added_skin(skins[""], SkirtBones.rests, SKIRT_SKIN)
		skins[PeltBones.PREFIX] = _added_skin(skins[""], PeltBones.rests, PELT_SKIN)
	# The cloak's, made the first time a cloak is baked; its arms bound
	# hanging (CloakBones.arm_hang()).
	skins[CloakBones.PREFIX] = _cloak_skin(skins[""])
	DirAccess.make_dir_recursive_absolute(_models)
	DirAccess.make_dir_recursive_absolute(_scenes)
	var waiting := []
	for file in DirAccess.get_files_at(source):
		if file.get_extension() != "json":
			continue
		var id := file.get_basename()
		if not only.is_empty() and id not in only:
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.path_join(file)))
		# The scan dump (body.json) can share the folder.
		if not data.has("textures") and not data.has("surfaces"):
			continue
		if not (_textures(id, data.textures) if data.has("textures") else _fur_maps()):
			waiting.append(id)
			continue
		var skin: Skin = skins[_added_bones(data)]
		var binds := {}
		for b in skin.get_bind_count():
			binds[skin.get_bind_name(b)] = b
		var mesh := _mesh(id, data, binds)
		MeshLods.add_to(mesh)
		var path := _models + id + ".res"
		if ResourceSaver.save(mesh, path) != OK:
			push_error("Could not save " + path)
			continue
		_scene(id, load(path), skin)
	if not waiting.is_empty():
		print("Textures written for %s: import them (godot --headless --import) and run this again." % ", ".join(waiting))
	quit()


## The scan's Skin with bones added to the skeleton (`rests`: SkirtBones's,
## PeltBones's), saved as `path`. A bind takes a vertex from the skin's space
## to its bone's; the scan's all do it with their bone at rest, so the skin's
## space is where the hips' bind puts it.
func _added_skin(skin: Skin, rests_of: Callable, path: String) -> Skin:
	if ResourceSaver.save(_with_added(skin, rests_of), path) != OK:
		push_error("Could not save " + path)
	return load(path)


## `skin` with the bones of `rests_of` (SkirtBones.rests...) bound at their rest.
func _with_added(skin: Skin, rests_of: Callable) -> Skin:
	var model: Node3D = load(MODEL).instantiate()
	var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
	var hips := skeleton.find_bone(SkirtBones.HIPS)
	var to_skeleton := Transform3D.IDENTITY
	for b in skin.get_bind_count():
		if skin.get_bind_name(b) == SkirtBones.HIPS:
			to_skeleton = BodyMeasurements.rest_globals(skeleton)[hips] * skin.get_bind_pose(b)
	var result: Skin = skin.duplicate()
	var rests: Dictionary = rests_of.call(skeleton)
	for name: StringName in rests:
		result.add_named_bind(name, (rests[name][1] as Transform3D).affine_inverse() * to_skeleton)
	model.free()
	return result


## The cloaks' Skin (CLOAK_SKIN): the scan's with the cloak's bones added
## and its upper arms bound hanging (CloakBones.arm_hang()), as cloaks are
## made. Its binds are made anew (CloakBones' chains may have changed) but
## it is updated in place, so the scenes that use it keep it.
func _cloak_skin(player: Skin) -> Skin:
	var skin: Skin = load(CLOAK_SKIN) if ResourceLoader.exists(CLOAK_SKIN) \
			else _added_skin(player, CloakBones.rests, CLOAK_SKIN)
	var fresh := _with_added(player, CloakBones.rests)
	skin.clear_binds()
	for b in fresh.get_bind_count():
		skin.add_named_bind(fresh.get_bind_name(b), fresh.get_bind_pose(b))
	for arm in CloakBones.ARMS.size():
		var hang := CloakBones.arm_hang(player, arm)
		for b in skin.get_bind_count():
			if skin.get_bind_name(b) == CloakBones.ARMS[arm]:
				for p in player.get_bind_count():
					if player.get_bind_name(p) == CloakBones.ARMS[arm]:
						skin.set_bind_pose(b, player.get_bind_pose(p) * hang)
	if ResourceSaver.save(skin, CLOAK_SKIN) != OK:
		push_error("Could not save " + CLOAK_SKIN)
	return skin


## The prefix of the added bones the piece hangs from (SkirtBones.PREFIX,
## PeltBones.PREFIX), or "".
static func _added_bones(data: Dictionary) -> String:
	for surface: Dictionary in data.get("surfaces", [data]):
		var weights: Array = surface.weights
		var influences: Array = surface.influences
		for k in influences.size():
			var bone := String(data.bones[int(influences[k])])
			if weights[k] > 0.0:
				for prefix: String in [SkirtBones.PREFIX, PeltBones.PREFIX, CloakBones.PREFIX]:
					if bone.begins_with(prefix):
						return prefix
	return ""


## Writes the piece's maps if they are not there; whether they are imported.
func _textures(id: String, maps: Dictionary) -> bool:
	var ready := true
	for kind in MAPS:
		if kind == "metallic" and (not _bronze or not maps.has(kind)):
			continue
		var path := _models + "%s_%s.jpg" % [id, kind]
		if ResourceLoader.exists(path):
			continue
		ready = false
		if FileAccess.file_exists(path):
			continue
		var image := Image.load_from_file(maps[kind])
		var size: int = MAPS[kind][0]
		if image.get_width() != size:
			image.resize(size, size, Image.INTERPOLATE_LANCZOS)
		image.convert(Image.FORMAT_RGB8)
		if kind == "albedo" and _bronze and maps.has("metallic"):
			tone_albedo(image, Image.load_from_file(maps.metallic))
		if kind == "roughness" and not _bronze:
			for y in image.get_height():
				for x in image.get_width():
					var r := lerpf(ROUGHNESS_RANGE.x, ROUGHNESS_RANGE.y, image.get_pixel(x, y).r)
					image.set_pixel(x, y, Color(r, r, r))
		image.save_jpg(ProjectSettings.globalize_path(path), MAPS[kind][1])
		var options := ConfigFile.new()
		options.set_value("remap", "importer", "texture")
		options.set_value("remap", "type", "CompressedTexture2D")
		options.set_value("params", "compress/mode", 2)
		options.set_value("params", "compress/normal_map", 1 if kind == "normal" else 0)
		options.set_value("params", "mipmaps/generate", true)
		options.save(path + ".import")
	return ready


## Brightens Meshy's albedo (sRGB) by its metallic map (METAL_GAIN,
## DIELECTRIC_GAIN), keeping each texel's hue.
static func tone_albedo(albedo: Image, metallic: Image) -> void:
	var mask := metallic.duplicate() as Image
	mask.convert(Image.FORMAT_L8)
	if mask.get_size() != albedo.get_size():
		mask.resize(albedo.get_width(), albedo.get_height(), Image.INTERPOLATE_BILINEAR)
	for y in albedo.get_height():
		for x in albedo.get_width():
			var metal := mask.get_pixel(x, y).r
			var c := albedo.get_pixel(x, y).srgb_to_linear()
			var grey := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			var saturation := lerpf(1.0, METAL_SATURATION, metal)
			var v := Vector3(c.r, c.g, c.b)
			v = (Vector3(grey, grey, grey) + (v - Vector3(grey, grey, grey)) * saturation).maxf(0.0)
			v *= lerpf(DIELECTRIC_GAIN, METAL_GAIN, metal)
			# Past white it would lose its hue: scaled down whole.
			v /= maxf(1.0, maxf(v.x, maxf(v.y, v.z)))
			albedo.set_pixel(x, y, Color(v.x, v.y, v.z).linear_to_srgb())


func _mesh(id: String, data: Dictionary, binds: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	# The garment first, then its lining (a plain colour), if it has one.
	for surface: Dictionary in data.get("surfaces", [data]):
		var arrays := _arrays(surface, data.bones, binds)
		var flags := _weight_flags(arrays)
		if arrays[Mesh.ARRAY_TEX_UV] != null:
			var tool := SurfaceTool.new()
			tool.create_from_arrays(arrays)
			# create_from_arrays clears SurfaceTool's weight-count setting.
			if flags:
				tool.set_skin_weight_count(SurfaceTool.SKIN_8_WEIGHTS)
			tool.generate_tangents()
			arrays = tool.commit_to_arrays()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		var index := mesh.get_surface_count() - 1
		if surface.has("material"):
			# A head cut from an animal (build_fur_armor.py) keeps that animal's material.
			var material: String = surface.material
			mesh.surface_set_material(index, load(material) if material.begins_with("res://") else _fur_material(material))
		elif surface.has("color"):
			mesh.surface_set_material(index, _lining(id, surface.color))
		else:
			mesh.surface_set_material(index, _material(id))
	mesh.resource_name = id
	if data.has("tights"):
		var tights: Dictionary = _tights(data.get("surfaces", [data])[0].positions)
		var c: Array = data.tights
		tights.color = Color(c[0], c[1], c[2])
		mesh.set_meta(&"tights", tights)
	return mesh


## Where a leg piece's tights (CharacterAppearanceRig._update_tights()) end,
## from its points (player skin space, metres, Y up, origin at the hips):
## TIGHTS_MARGIN over its hem and TIGHTS_WAIST under its waist (ArmorFit
## carries it onto each body a few centimetres up or down from the scan's,
## and the waistband covers that skin anyway), where that is lowest
## round the body (a ragged or sloping waistband: what stands over the
## waist in one of TIGHTS_SECTORS sectors, a strap or a buckle, does not
## lift it).
static func _tights(positions: Array) -> Dictionary:
	var hem := INF
	var tops := PackedFloat32Array()
	tops.resize(TIGHTS_SECTORS)
	tops.fill(-INF)
	for i in positions.size() / 3:
		var p := Vector3(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2])
		hem = minf(hem, p.y)
		if p.y > TIGHTS_HIPS:
			var sector := posmod(int(floor((atan2(p.x, p.z) + PI) / TAU * TIGHTS_SECTORS)), TIGHTS_SECTORS)
			tops[sector] = maxf(tops[sector], p.y)
	var waist := INF
	for sector in TIGHTS_SECTORS:
		var around := minf(tops[posmod(sector - 1, TIGHTS_SECTORS)], tops[(sector + 1) % TIGHTS_SECTORS])
		waist = minf(waist, minf(tops[sector], around + 0.01))
	return {hem = hem + TIGHTS_MARGIN, waist = waist - TIGHTS_WAIST}


static func _weight_flags(arrays: Array) -> int:
	return Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if arrays[Mesh.ARRAY_BONES].size() == arrays[Mesh.ARRAY_VERTEX].size() * 8 else 0


## Export the garment for Blender, or apply its regenerated weights. Use
## the existing Skin's named binds: Blender's skeleton order differs.
func _reweight(directory: String, only: PackedStringArray, exporting: bool) -> int:
	DirAccess.make_dir_recursive_absolute(directory)
	var processed := 0
	for file in DirAccess.get_files_at(_models):
		if file.get_extension() != "res":
			continue
		var id := file.get_basename()
		if not only.is_empty() and id not in only:
			continue
		var scene_path := _scenes + id + "_equipable.tscn"
		if not ResourceLoader.exists(scene_path, "PackedScene"):
			continue
		var scene: MeshInstance3D = load(scene_path).instantiate()
		var surfaces := ArmorFit.source(scene.mesh)
		var arrays: Array = surfaces[0].arrays
		var path := directory.path_join(id + ".json")
		if exporting:
			var positions := PackedFloat32Array()
			for p: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				positions.append_array([p.x, p.y, p.z])
			var out := FileAccess.open(path, FileAccess.WRITE)
			if out == null:
				scene.free()
				return 1
			out.store_string(JSON.stringify({positions = Array(positions), indices = Array(arrays[Mesh.ARRAY_INDEX])}))
		else:
			var data = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not data is Dictionary or not data.has_all(["bones", "influences", "weights"]):
				push_error("Invalid weights: " + path)
				scene.free()
				return 1
			# New weights may hang it from the skirt's or a pelt's bones, or
			# no longer: the scene takes the Skin with their binds.
			var skin_path: String = {"": SKIN, SkirtBones.PREFIX: SKIRT_SKIN, PeltBones.PREFIX: PELT_SKIN,
					CloakBones.PREFIX: CLOAK_SKIN}[_added_bones(data)]
			var reskinned: bool = scene.skin == null or scene.skin.resource_path != skin_path
			if reskinned:
				scene.skin = load(skin_path)
			var binds := {}
			for b in scene.skin.get_bind_count():
				binds[String(scene.skin.get_bind_name(b))] = b
			var bones := PackedInt32Array()
			var weights := PackedFloat32Array(data.weights)
			if weights.size() != arrays[Mesh.ARRAY_VERTEX].size() * 8 or weights.size() != data.influences.size():
				push_error("Expected eight weights per vertex: " + path)
				scene.free()
				return 1
			for k in weights.size():
				var name: String = data.bones[int(data.influences[k])]
				if weights[k] > 0.0 and not binds.has(name):
					push_error("Missing bind %s in %s" % [name, id])
					scene.free()
					return 1
				bones.append(binds.get(name, 0))
			arrays[Mesh.ARRAY_BONES] = bones
			arrays[Mesh.ARRAY_WEIGHTS] = weights
			surfaces[0].flags |= _weight_flags(arrays)
			var mesh := ArmorFit.build(surfaces, scene.mesh.resource_name)
			# Keep the original packed vertex attributes and every other
			# surface verbatim. Repacking normals/tangents on each reweight
			# otherwise accumulates quantisation error.
			var packed: Array = scene.mesh.get("_surfaces")
			var updated: Array = mesh.get("_surfaces")
			packed[0].skin_data = updated[0].skin_data
			packed[0].bone_aabbs = updated[0].bone_aabbs
			packed[0].format = int(packed[0].format) | Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
			mesh = ArrayMesh.new()
			mesh.set("_surfaces", packed)
			mesh.resource_name = scene.mesh.resource_name
			if ResourceSaver.save(mesh, _models + file) != OK:
				scene.free()
				return 1
			if reskinned:
				_scene(id, load(_models + file), scene.skin)
		scene.free()
		processed += 1
		print("%s: %s weights" % [id, "exported for" if exporting else "updated"])
	return 0 if processed > 0 else 1


func _arrays(surface: Dictionary, names: Array, binds: Dictionary) -> Array:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var p: Array = surface.positions
	var n: Array = surface.normals
	for i in p.size() / 3:
		positions.append(Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]))
		normals.append(Vector3(n[i * 3], n[i * 3 + 1], n[i * 3 + 2]))
	var bones := PackedInt32Array()
	var weights: Array = surface.weights
	var influences: Array = surface.influences
	for k in influences.size():
		# An empty influence may name a bone the skin has no bind for.
		bones.append(binds.get(StringName(names[int(influences[k])]), 0) if weights[k] <= 0.0
				else binds[StringName(names[int(influences[k])])])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	if surface.has("uvs"):
		var uvs := PackedVector2Array()
		var t: Array = surface.uvs
		for i in t.size() / 2:
			uvs.append(Vector2(t[i * 2], t[i * 2 + 1]))
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	if surface.has("colors"):
		var colors := PackedColorArray()
		var c: Array = surface.colors
		for i in c.size() / 4:
			colors.append(Color(c[i * 4], c[i * 4 + 1], c[i * 4 + 2], c[i * 4 + 3]))
		arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array(surface.weights)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(surface.indices)
	return arrays


## The lining: matte, of the garment's colour.
func _lining(id: String, color: Array) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = id + "_lining"
	material.albedo_color = Color(color[0], color[1], color[2])
	material.roughness = 1.0
	material.metallic_specular = SPECULAR
	return material


func _material(id: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = id
	# Meshy's garments are shells with open edges and loose flaps.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = load(_models + id + "_albedo.jpg")
	material.normal_enabled = true
	material.normal_texture = load(_models + id + "_normal.jpg")
	material.normal_scale = NORMAL_SCALE
	material.metallic_specular = SPECULAR
	material.roughness = 1.0
	material.roughness_texture = load(_models + id + "_roughness.jpg")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	if _bronze:
		# Meshy's relief whole: the lion, the rims and the rivets.
		material.normal_scale = 1.0
		material.metallic_specular = 0.5
		var path := _models + id + "_metallic.jpg"
		if ResourceLoader.exists(path):
			material.metallic = 1.0
			material.metallic_texture = load(path)
			material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return material


## Whether the fur garments' maps are imported; writes their import
## settings if they have none.
func _fur_maps() -> bool:
	var ready := true
	for map: String in FUR_MAPS:
		var path := FUR + map + ".png"
		if ResourceLoader.exists(path):
			continue
		ready = false
		if FileAccess.file_exists(path + ".import"):
			continue
		var options := ConfigFile.new()
		options.set_value("remap", "importer", "texture")
		options.set_value("remap", "type", "CompressedTexture2D")
		options.set_value("params", "compress/mode", 2)
		options.set_value("params", "compress/normal_map", 1 if FUR_MAPS[map] else 0)
		options.set_value("params", "mipmaps/generate", true)
		options.save(path + ".import")
	return ready


## A fur garment's shared material, written to FUR the first time a run
## asks for it.
func _fur_material(name: String) -> Material:
	if _fur_materials.has(name):
		return _fur_materials[name]
	var material: Material
	match name:
		"fur_card":
			# The cards' solid cores, then their ends blended over (as the hair).
			var cards := ShaderMaterial.new()
			cards.shader = load(FUR_SHADERS % "card")
			cards.set_shader_parameter(&"lock_map", load(FUR + "fur_cards.png"))
			var fringe := ShaderMaterial.new()
			fringe.shader = load(FUR_SHADERS % "card_fringe")
			fringe.set_shader_parameter(&"lock_map", load(FUR + "fur_cards.png"))
			fringe.render_priority = 1
			cards.next_pass = fringe
			material = cards
		"pelt":
			var pelt := ShaderMaterial.new()
			pelt.shader = load(FUR_SHADERS % "pelt")
			pelt.set_shader_parameter(&"pelt_map", load(FUR + "fur_pelt.png"))
			pelt.set_shader_parameter(&"pelt_normal", load(FUR + "fur_pelt_normal.png"))
			pelt.set_shader_parameter(&"map_scale", 1.0 / FUR_TILES.pelt)
			material = pelt
		"leather", "lace", "bone":
			var plain := StandardMaterial3D.new()
			plain.albedo_texture = load(FUR + name + "_albedo.png")
			plain.vertex_color_use_as_albedo = true
			plain.metallic_specular = SPECULAR
			plain.roughness = 0.6 if name == "bone" else 0.8
			if name != "bone":
				plain.normal_enabled = true
				plain.normal_texture = load(FUR + name + "_normal.png")
			if name == "leather":
				plain.roughness = 1.0
				plain.roughness_texture = load(FUR + "leather_roughness.png")
				plain.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			var tile: float = FUR_TILES[name]
			# A cord's V goes once round it.
			plain.uv1_scale = Vector3(1.0 / tile, 1.0 if name == "lace" else 1.0 / tile, 1.0)
			material = plain
		_:
			push_error("Unknown material " + name)
			return null
	material.resource_name = name
	var path := FUR + name + ".tres"
	if ResourceSaver.save(material, path) != OK:
		push_error("Could not save " + path)
	_fur_materials[name] = load(path)
	return _fur_materials[name]


func _scene(id: String, mesh: ArrayMesh, skin: Skin) -> void:
	var root := MeshInstance3D.new()
	root.name = id
	root.mesh = mesh
	root.skin = skin
	root.set_script(load(MESH_ITEM))
	root.set("item_data", load(_items + id + ".tres"))
	var scene := PackedScene.new()
	scene.pack(root)
	var path := _scenes + id + "_equipable.tscn"
	if ResourceSaver.save(scene, path) != OK:
		push_error("Could not save " + path)
	else:
		print("%s: %d vertices -> %s" % [id, mesh.surface_get_array_len(0), path])
	root.free()

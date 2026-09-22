extends SceneTree

## Turns the Blender export of the MakeHuman human
## (tools/character/blender/export_mpfb_human.py) into Godot resources:
##
##   godot --headless --path . --script res://tools/character/bake_character_human.gd -- [export dir]
##
## (default export dir: build/character/mpfb). Writes under data/character/human/:
##  - one HumanPartData per mesh (body, eyes, teeth, tongue, each eyebrow,
##    eyelash and hair style), with its sparse morphs;
##  - rig.tres (HumanRigData): per-sex Skin and bone offsets. The joints the
##    exporter measured on each body replace the joint positions of the
##    player skeleton while its bone orientations are kept, so the player
##    animations drive the new bodies unchanged.
## Textures are copied to textures/character/human/ (MakeHuman assets, CC0).
## Run the editor once afterwards (godot --headless --editor --quit) so the
## copied textures are imported.

const DEFAULT_SOURCE := "res://build/character/mpfb"
const OUTPUT := "res://data/character/human"
const TEXTURES := "res://textures/character/human"
const MODEL := "res://scenes/character/character_model.tscn"
const ORIGINAL_SKIN := "res://models/player/xavivar/firstage_human_male_player_skin.tres"
const KINDS := {
	"body": HumanPartData.Kind.BODY, "eyes": HumanPartData.Kind.EYES, "teeth": HumanPartData.Kind.TEETH,
	"tongue": HumanPartData.Kind.TONGUE, "eyebrows": HumanPartData.Kind.EYEBROWS,
	"eyelashes": HumanPartData.Kind.EYELASHES, "hair": HumanPartData.Kind.HAIR,
}
const TEXTURE_ROLES := {"diffuseTexture": "albedo", "normalmapTexture": "normal", "bumpTexture": "bump"}

var header: Dictionary
var blob: PackedByteArray


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source := ProjectSettings.globalize_path(args[0] if args.size() > 0 else DEFAULT_SOURCE)
	header = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("human.json")))
	blob = FileAccess.get_file_as_bytes(source.path_join("human.bin"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var ok := true
	_copy_masks()
	for part_name in header.parts:
		ok = _bake_part(part_name) and ok
	ok = _bake_rig() and ok
	quit(0 if ok else 1)


func _bake_part(part_name: String) -> bool:
	var entry: Dictionary = header.parts[part_name]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vectors(entry.positions)
	arrays[Mesh.ARRAY_NORMAL] = _vectors(entry.normals)
	arrays[Mesh.ARRAY_TEX_UV] = _vectors2(entry.uvs)
	if entry.has("uv2"):
		arrays[Mesh.ARRAY_TEX_UV2] = _vectors2(entry.uv2)
	arrays[Mesh.ARRAY_BONES] = _ints(entry.bones)
	arrays[Mesh.ARRAY_WEIGHTS] = _floats(entry.weights)
	arrays[Mesh.ARRAY_INDEX] = _ints(entry.indices)
	var surface := SurfaceTool.new()
	surface.create_from_arrays(arrays)
	surface.generate_tangents()
	var mesh := surface.commit()
	if mesh.surface_get_array_len(0) != arrays[Mesh.ARRAY_VERTEX].size():
		push_error("%s: tangent generation changed the vertex count" % part_name)
		return false

	var data := HumanPartData.new()
	data.mesh = mesh
	data.kind = KINDS[entry.get("asset_type", "body")]
	var names := PackedStringArray()
	var offsets := PackedInt32Array()
	var indices := PackedInt32Array()
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	for morph in header.morphs:
		if not entry.morphs.has(morph):
			continue
		var sparse: Dictionary = entry.morphs[morph]
		names.append(morph)
		offsets.append(indices.size())
		indices.append_array(_ints(sparse.indices))
		positions.append_array(_vectors(sparse.positions))
		normals.append_array(_vectors(sparse.normals))
	offsets.append(indices.size())
	data.names = names
	data.offsets = offsets
	data.indices = indices
	data.position_deltas = positions
	data.normal_deltas = normals
	if data.kind == HumanPartData.Kind.EYES:
		data.textures = {"albedo": TEXTURES + "/eyes/iris.png"}
	else:
		data.textures = _copy_textures(part_name, header.textures.get(part_name, {}))
	if data.textures.has("albedo") and data.kind != HumanPartData.Kind.EYES:
		data.tone = _mean_tone(data.textures.albedo)
	var path := "%s/%s.res" % [OUTPUT, part_name]
	var err := ResourceSaver.save(data, path, ResourceSaver.FLAG_COMPRESS)
	print("%-14s %5d vertices %3d morphs (%d entries) -> %s" % [part_name, mesh.surface_get_array_len(0),
			names.size(), indices.size(), error_string(err)])
	return err == OK


func _bake_rig() -> bool:
	var model: Node3D = load(MODEL).instantiate()
	var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
	var original: Skin = load(ORIGINAL_SKIN)
	# Skin space -> skeleton space; the same for every bone at rest.
	var skin_to_skeleton := skeleton.get_bone_global_rest(0) * original.get_bind_pose(_bind_index(original, skeleton.get_bone_name(0)))
	var rig := HumanRigData.new()
	for sex in header.joints:
		var joints: Dictionary = header.joints[sex]
		# Joint frames in skin space: the player's orientation at the body's joint.
		var frames := {}
		for bone in skeleton.get_bone_count():
			var name := skeleton.get_bone_name(bone)
			var frame := original.get_bind_pose(_bind_index(original, name)).affine_inverse()
			if joints.has(name):
				frame.origin = _vector(joints[name])
			else:
				var parent := skeleton.get_bone_parent(bone)
				var parent_name := skeleton.get_bone_name(parent)
				var parent_original := original.get_bind_pose(_bind_index(original, parent_name)).affine_inverse()
				frame.origin = frames[parent_name].origin + frame.origin - parent_original.origin
				push_warning("%s: no measured joint for %s, kept its offset from %s" % [sex, name, parent_name])
			frames[name] = frame
		var skin := Skin.new()
		for bind in original.get_bind_count():
			var name := String(original.get_bind_name(bind))
			skin.add_named_bind(name, frames[name].affine_inverse())
		var offsets := {}
		for bone in skeleton.get_bone_count():
			var name := skeleton.get_bone_name(bone)
			var global: Transform3D = skin_to_skeleton * frames[name]
			var parent := skeleton.get_bone_parent(bone)
			var local := global.origin
			if parent >= 0:
				local = (skin_to_skeleton * frames[skeleton.get_bone_name(parent)]).affine_inverse() * global.origin
			offsets[name] = local - skeleton.get_bone_rest(bone).origin
		rig.skins[StringName(sex)] = skin
		rig.bone_offsets[StringName(sex)] = offsets
	var male: Dictionary = header.joints.male
	rig.landmarks = {
		&"hips": _vector(male.mixamorig_Hips).y,
		&"legs": (_vector(male.mixamorig_LeftUpLeg).y + _vector(male.mixamorig_RightUpLeg).y) * 0.5,
		&"chest": _vector(male.mixamorig_Spine2).y,
		&"neck": _vector(male.mixamorig_Neck).y,
	}
	for sex in ["male", "female"]:
		var path := "%s/skin/skin_%s.png" % [TEXTURES, sex]
		rig.skin_textures[StringName(sex)] = path
		rig.skin_tones[StringName(sex)] = _mean_tone(path)
	model.free()
	var err := ResourceSaver.save(rig, OUTPUT + "/rig.tres")
	print("rig -> ", error_string(err), " landmarks ", rig.landmarks)
	return err == OK


func _bind_index(skin: Skin, name: String) -> int:
	for bind in skin.get_bind_count():
		if skin.get_bind_name(bind) == name:
			return bind
	return -1


## Copies a part's textures into the project; returns role -> res:// path.
func _copy_textures(part_name: String, sources: Dictionary) -> Dictionary:
	var result := {}
	var folder := "%s/%s" % [TEXTURES, part_name.get_slice("_", 0) if part_name.begins_with("eye") else part_name]
	for key in sources:
		if not TEXTURE_ROLES.has(key):
			continue
		var file: String = sources[key].get_file()
		var target := "%s/%s" % [folder, file]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		if DirAccess.copy_absolute(sources[key], ProjectSettings.globalize_path(target)) != OK:
			push_error("Could not copy " + sources[key])
			continue
		result[TEXTURE_ROLES[key]] = target
	return result


## Skin textures (per sex), the iris and MPFB's UV masks go to fixed names the
## materials reference.
func _copy_masks() -> void:
	var files := {
		"skin/skin_male.png": header.textures.skin_male.diffuseTexture,
		"skin/skin_female.png": header.textures.skin_female.diffuseTexture,
		"eyes/iris.png": header.textures.eyes.diffuseTexture,
	}
	for mask in header.masks:
		files["skin/mask_%s.jpg" % mask] = header.masks[mask]
	for target in files:
		var path := "%s/%s" % [TEXTURES, target]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		var err := DirAccess.copy_absolute(files[target], ProjectSettings.globalize_path(path))
		print("%s <- %s (%s)" % [path, files[target].get_file(), error_string(err)])


## Mean colour of a texture, weighted by alpha (strand textures are mostly
## transparent).
func _mean_tone(path: String) -> Color:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	image.resize(256, 256, Image.INTERPOLATE_BILINEAR)
	var sum := Color(0, 0, 0, 0)
	var weight := 0.0
	for y in 256:
		for x in 256:
			var c := image.get_pixel(x, y)
			sum += Color(c.r, c.g, c.b, 0.0) * c.a
			weight += c.a
	var mean := sum / maxf(weight, 1e-6)
	return Color(mean.r, mean.g, mean.b, 1.0)


func _bytes(entry: Dictionary) -> PackedByteArray:
	return blob.slice(entry.offset, entry.offset + int(entry.count) * 4)


func _floats(entry: Dictionary) -> PackedFloat32Array:
	return _bytes(entry).to_float32_array()


func _ints(entry: Dictionary) -> PackedInt32Array:
	return _bytes(entry).to_int32_array()


func _vectors(entry: Dictionary) -> PackedVector3Array:
	var values := _floats(entry)
	var result := PackedVector3Array()
	result.resize(values.size() / 3)
	for i in result.size():
		result[i] = Vector3(values[i * 3], values[i * 3 + 1], values[i * 3 + 2])
	return result


func _vectors2(entry: Dictionary) -> PackedVector2Array:
	var values := _floats(entry)
	var result := PackedVector2Array()
	result.resize(values.size() / 2)
	for i in result.size():
		result[i] = Vector2(values[i * 2], values[i * 2 + 1])
	return result


func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

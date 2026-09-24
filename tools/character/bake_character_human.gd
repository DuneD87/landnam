extends SceneTree

## Turns the Blender export of the MakeHuman human
## (tools/character/blender/export_mpfb_human.py and make_skin_masks.py) into
## Godot resources:
##
##   godot --headless --path . --script res://tools/character/bake_character_human.gd -- [export dir]
##
## (default export dir: build/character/mpfb). Writes data/character/human/body.res
## (HumanBodyData: body, joints, anchors, skins) and one HumanProxyData per proxy
## in data/character/human/proxies/. Textures go to textures/character/human/
## (MakeHuman and community assets; see docs/character_credits.md): skins as
## JPEG, hair and masks as PNG, downscaled to what a game character needs. Run
## the editor once afterwards (godot --headless --editor --quit) so they are
## imported, then tools/character/fix_texture_imports.gd.

const DEFAULT_SOURCE := "res://build/character/mpfb"
const OUTPUT := "res://data/character/human"
const TEXTURES := "res://textures/character/human"
const MODEL := "res://scenes/character/character_model.tscn"
const ORIGINAL_SKIN := "res://models/player/xavivar/firstage_human_male_player_skin.tres"
const SKIN_SIZE := 2048
const PROXY_SIZE := 1024
## Hair textures lose the light and shade painted at scales above about
## PROXY_SIZE / STRAND_BLUR_SIZE texels, keeping this much of it (0-1)...
const STRAND_BLUR_SIZE := 128
const STRAND_SHADE := 0.2
## ...and their strands' contrast is compressed by this power...
const STRAND_CONTRAST := 0.5
## ...around this grey, which leaves room for highlights.
const STRAND_GREY := 0.45
## Soft edge: alpha blurred over about this many texels, at most this opaque.
const STRAND_HALO_SHRINK := 4
const STRAND_HALO := 0.4
const KINDS := {
	"eyes": HumanProxyData.Kind.EYES, "teeth": HumanProxyData.Kind.TEETH,
	"tongue": HumanProxyData.Kind.TONGUE, "eyebrows": HumanProxyData.Kind.EYEBROWS,
	"eyelashes": HumanProxyData.Kind.EYELASHES, "hair": HumanProxyData.Kind.HAIR,
	"clothes": HumanProxyData.Kind.BEARD, "helper": HumanProxyData.Kind.GENITALS,
}

var header: Dictionary
var blob: PackedByteArray
var source_dir: String


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	source_dir = ProjectSettings.globalize_path(args[0] if args.size() > 0 else DEFAULT_SOURCE)
	header = JSON.parse_string(FileAccess.get_file_as_string(source_dir.path_join("human.json")))
	blob = FileAccess.get_file_as_bytes(source_dir.path_join("human.bin"))
	for folder in [OUTPUT + "/proxies", TEXTURES + "/skin", TEXTURES + "/proxies"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var ok := _bake_body()
	for name in header.proxies:
		ok = _bake_proxy(name) and ok
	quit(0 if ok else 1)


# --- Body --------------------------------------------------------------------

func _bake_body() -> bool:
	var entry: Dictionary = header.body
	var data := HumanBodyData.new()
	data.mesh = _surface(entry)
	if data.mesh == null:
		return false
	var names := PackedStringArray()
	var offsets := PackedInt32Array()
	var indices := PackedInt32Array()
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	# Every morph is listed, even one that only moves anchors (the genitals
	# helper's), so the rig resolves it; those have no body entries.
	for morph in header.morphs:
		names.append(morph)
		offsets.append(indices.size())
		if not entry.morphs.has(morph):
			continue
		var sparse: Dictionary = entry.morphs[morph]
		indices.append_array(_ints(sparse.indices))
		positions.append_array(_vectors(sparse.positions))
		normals.append_array(_vectors(sparse.normals))
	offsets.append(indices.size())
	data.names = names
	data.offsets = offsets
	data.indices = indices
	data.position_deltas = positions
	data.normal_deltas = normals

	# Skeleton: the player's bone orientations at the male base joints.
	var bone_names := PackedStringArray(header.bones)
	data.bone_names = bone_names
	data.joints = _vector_list(header.joints)
	var joint_deltas := {}
	for morph in header.joint_deltas:
		joint_deltas[StringName(morph)] = _vector_list(header.joint_deltas[morph])
	data.joint_deltas = joint_deltas
	var original: Skin = load(ORIGINAL_SKIN)
	var orientations: Array[Basis] = []
	var skin := Skin.new()
	for b in bone_names.size():
		var bind := _bind_index(original, bone_names[b])
		var orientation := original.get_bind_pose(bind).affine_inverse().basis
		orientations.append(orientation)
	data.orientations = orientations
	for bind in original.get_bind_count():
		var name := String(original.get_bind_name(bind))
		var b := bone_names.find(name)
		skin.add_named_bind(name, Transform3D(orientations[b], data.joints[b]).affine_inverse())
	data.skin = skin
	var model: Node3D = load(MODEL).instantiate()
	var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
	data.skin_to_skeleton = skeleton.get_bone_global_rest(0) * original.get_bind_pose(
			_bind_index(original, skeleton.get_bone_name(0)))
	model.free()

	# Anchors and posing.
	data.anchors = _vectors(header.anchors.raw)
	var anchor_names := PackedStringArray()
	var anchor_offsets := PackedInt32Array()
	var anchor_indices := PackedInt32Array()
	var anchor_deltas := PackedVector3Array()
	for morph in header.morphs:
		if not header.anchors.morphs.has(morph):
			continue
		var sparse: Dictionary = header.anchors.morphs[morph]
		anchor_names.append(morph)
		anchor_offsets.append(anchor_indices.size())
		anchor_indices.append_array(_ints(sparse.indices))
		anchor_deltas.append_array(_vectors(sparse.positions))
	anchor_offsets.append(anchor_indices.size())
	data.anchor_names = anchor_names
	data.anchor_offsets = anchor_offsets
	data.anchor_indices = anchor_indices
	data.anchor_deltas = anchor_deltas
	var pose := {}
	for sex in header.pose:
		var transforms: Array[Transform3D] = []
		transforms.resize(bone_names.size())
		for b in bone_names.size():
			var t: Variant = header.pose[sex].get(bone_names[b])
			if t == null:
				continue
			var m: Array = t.basis
			var basis := Basis(Vector3(m[0], m[3], m[6]), Vector3(m[1], m[4], m[7]), Vector3(m[2], m[5], m[8]))
			transforms[b] = Transform3D(basis, _vector(t.origin))
		pose[StringName(sex)] = transforms
	data.pose = pose
	var ground := {}
	for sex in header.ground:
		ground[StringName(sex)] = float(header.ground[sex])
	data.ground = ground
	var ground_deltas := {}
	for morph in header.ground_deltas:
		ground_deltas[StringName(morph)] = float(header.ground_deltas[morph])
	data.ground_deltas = ground_deltas

	# Skins, relief and masks.
	var skins := {}
	for id in header.skins:
		var info: Dictionary = header.skins[id]
		var path := "%s/skin/%s.jpg" % [TEXTURES, id]
		var image := _image(info.diffuse, SKIN_SIZE)
		if image == null:
			return false
		image.save_jpg(ProjectSettings.globalize_path(path), 0.92)
		skins[StringName(id)] = {texture = path, tone = _mean_tone(image, true), sex = StringName(info.sex)}
	data.skins = skins
	var normal_maps := {}
	for sex_file in [["male", header.textures.skin_normal], ["female", source_dir.path_join("skin_normal_female.png")]]:
		var image := _image(sex_file[1], SKIN_SIZE)
		if image == null:
			continue
		var path := "%s/skin/normal_%s.png" % [TEXTURES, sex_file[0]]
		image.convert(Image.FORMAT_RGB8)
		_flatten_background(image)
		image.save_png(ProjectSettings.globalize_path(path))
		normal_maps[StringName(sex_file[0])] = path
	data.normal_maps = normal_maps
	for copy in [["masks.png", "masks"], ["stubble.png", "stubble"], ["body_masks.png", "body_masks"]]:
		var image := Image.load_from_file(source_dir.path_join(copy[0]))
		var path := "%s/skin/%s.png" % [TEXTURES, copy[1]]
		image.save_png(ProjectSettings.globalize_path(path))
		if copy[1] == "masks":
			data.masks_texture = path
		elif copy[1] == "stubble":
			data.stubble_texture = path
	for mask in header.masks:
		var image := _image(header.masks[mask], 1024)
		image.save_png(ProjectSettings.globalize_path("%s/skin/mask_%s.png" % [TEXTURES, mask]))

	var err := ResourceSaver.save(data, OUTPUT + "/body.res", ResourceSaver.FLAG_COMPRESS)
	print("body: %d vertices, %d morphs (%d entries), %d anchors (%d entries), %d joint morphs -> %s" % [
			data.mesh.surface_get_array_len(0), names.size(), indices.size(), data.anchors.size(),
			anchor_indices.size(), joint_deltas.size(), error_string(err)])
	return err == OK


# --- Proxies -----------------------------------------------------------------

func _bake_proxy(name: String) -> bool:
	var entry: Dictionary = header.proxies[name]
	var data := HumanProxyData.new()
	data.kind = KINDS[entry.folder]
	data.mesh = _surface(entry)
	if data.mesh == null:
		return false
	data.source = _ints(entry.source)
	data.pose_bones = _ints(entry.pose_bones)
	data.pose_weights = _floats(entry.pose_weights)
	if entry.has("lids"):
		var rings: Array[PackedInt32Array] = []
		for ring in entry.lids.rings:
			rings.append(_ints(ring))
		data.lid_rings = rings
		data.lid_side = _ints(entry.lids.side)
		data.lid_raw = _vectors(entry.lids.raw)
	else:
		data.fit_refs = _ints(entry.fit.refs)
		data.fit_weights = _floats(entry.fit.weights)
		data.fit_offsets = _vectors(entry.fit.offsets)
		var scales := PackedFloat32Array()
		for pair in entry.fit.get("scales", []):
			scales.append_array(PackedFloat32Array([pair[0], pair[1], pair[2]]))
		data.fit_scales = scales
	data.strand_axis = int(entry.get("strand_axis", 1))
	data.textures = _proxy_textures(name, data.kind)
	if data.textures.has("albedo") and data.kind != HumanProxyData.Kind.EYES:
		data.tone = _mean_tone(Image.load_from_file(ProjectSettings.globalize_path(data.textures.albedo)))
	var err := ResourceSaver.save(data, "%s/proxies/%s.res" % [OUTPUT, name], ResourceSaver.FLAG_COMPRESS)
	print("%-40s %6d vertices %s -> %s" % [name, data.mesh.surface_get_array_len(0), data.textures.keys(), error_string(err)])
	return err == OK


func _proxy_textures(name: String, kind: HumanProxyData.Kind) -> Dictionary:
	var sources: Dictionary = header.textures.get("eyes" if kind == HumanProxyData.Kind.EYES else name, {})
	var result := {}
	for role in [["diffuseTexture", "albedo"], ["normalmapTexture", "normal"]]:
		if not sources.has(role[0]):
			continue
		var image := _image(sources[role[0]], PROXY_SIZE)
		if image == null:
			continue
		var path := "%s/proxies/%s_%s.png" % [TEXTURES, name, role[1]]
		if role[1] == "normal":
			image.convert(Image.FORMAT_RGB8)
		elif kind == HumanProxyData.Kind.HAIR or kind == HumanProxyData.Kind.BEARD:
			image = _strand_detail(image)
		image.save_png(ProjectSettings.globalize_path(path))
		result[role[1]] = path
	return result


# --- Helpers -----------------------------------------------------------------

func _surface(entry: Dictionary) -> ArrayMesh:
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
		push_error("Tangent generation changed the vertex count")
		return null
	return mesh


## Loads an image file, downscaled to at most `size`.
func _image(path: Variant, size: int) -> Image:
	if path == null or not FileAccess.file_exists(str(path)):
		push_error("Missing texture %s" % path)
		return null
	var image := Image.load_from_file(str(path))
	if image.get_width() > size or image.get_height() > size:
		image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return image


## Hair textures come with light and shade painted in, often in blotches
## that show once the hair is recoloured (human_hair.gdshader). Keeps the
## strands: the luminance over its blurred self (weighted by alpha, so the
## background does not count), with a hint of the painted shade, as grey
## around STRAND_GREY with the texture's alpha. Faint texels are plain grey,
## so neither their colour nor the background's halos in the mipmaps.
## Unlit holes painted between strands (braids) come out as a soft shade.
func _strand_detail(image: Image) -> Image:
	image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var count := width * height
	var data := image.get_data()
	var luma := PackedFloat32Array()
	luma.resize(count)
	var weighted := PackedFloat32Array()
	weighted.resize(count * 2)
	var total := Vector2.ZERO
	for i in count:
		var alpha := data[i * 4 + 3] / 255.0
		var value := (0.2126 * data[i * 4] + 0.7152 * data[i * 4 + 1] + 0.0722 * data[i * 4 + 2]) / 255.0
		luma[i] = value
		weighted[i * 2] = value * alpha
		weighted[i * 2 + 1] = alpha
		total += Vector2(value * alpha, alpha)
	var mean := maxf(total.x / maxf(total.y, 1e-6), 0.02)
	var blurred := Image.create_from_data(width, height, false, Image.FORMAT_RGF, weighted.to_byte_array())
	while blurred.get_width() > STRAND_BLUR_SIZE and blurred.get_height() > STRAND_BLUR_SIZE:
		blurred.resize(blurred.get_width() / 2, blurred.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	blurred.resize(width, height, Image.INTERPOLATE_CUBIC)
	var low := blurred.get_data().to_float32_array()
	# A few texels of blurred alpha around the strands: a soft edge the fringe
	# pass draws, instead of the hard, stepped cut of hairlines.
	var coverage := Image.create_from_data(width, height, false, Image.FORMAT_RGF, weighted.to_byte_array())
	coverage.resize(width / STRAND_HALO_SHRINK, height / STRAND_HALO_SHRINK, Image.INTERPOLATE_BILINEAR)
	coverage.resize(width, height, Image.INTERPOLATE_CUBIC)
	var halo := coverage.get_data().to_float32_array()
	var result := PackedByteArray()
	result.resize(count * 4)
	for i in count:
		var alpha := data[i * 4 + 3] / 255.0
		var local := mean
		if low[i * 2 + 1] > 1e-3:
			local = maxf(low[i * 2] / low[i * 2 + 1], 0.01)
		var ratio := clampf((luma[i] + 0.02) / (local + 0.02), 0.25, 3.0)
		var detail := pow(ratio, STRAND_CONTRAST) * pow(clampf(local / mean, 0.25, 4.0), STRAND_SHADE)
		# Edges are painted over the background's colour: they get plain,
		# slightly dark grey, as roots and tips are.
		var grey := lerpf(STRAND_GREY * 0.8, clampf(STRAND_GREY * detail, 0.0, 1.0), smoothstep(0.5, 0.95, alpha))
		var byte := roundi(grey * 255.0)
		result[i * 4] = byte
		result[i * 4 + 1] = byte
		result[i * 4 + 2] = byte
		result[i * 4 + 3] = maxi(data[i * 4 + 3], roundi(clampf(halo[i * 2 + 1], 0.0, 1.0) * STRAND_HALO * 255.0))
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, result)


## Normal maps come black outside the atlas' islands, and a black normal
## lights like glossy plastic: parts mapped there (the genitals helper) get a
## flat normal instead.
func _flatten_background(image: Image) -> void:
	var data := image.get_data()
	for i in range(0, data.size(), 3):
		if data[i] < 16 and data[i + 1] < 16 and data[i + 2] < 16:
			data[i] = 128
			data[i + 1] = 128
			data[i + 2] = 255
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGB8, data)


## Mean colour of an image, weighted by alpha. Skin atlases have a black
## background: `skip_dark` leaves it out.
func _mean_tone(image: Image, skip_dark := false) -> Color:
	var small := image.duplicate() as Image
	small.resize(256, 256, Image.INTERPOLATE_BILINEAR)
	var sum := Color(0, 0, 0, 0)
	var weight := 0.0
	for y in 256:
		for x in 256:
			var c := small.get_pixel(x, y)
			var w := c.a
			if skip_dark and c.get_luminance() < 0.08:
				w = 0.0
			sum += Color(c.r, c.g, c.b, 0.0) * w
			weight += w
	var mean := sum / maxf(weight, 1e-6)
	return Color(mean.r, mean.g, mean.b, 1.0)


func _bind_index(skin: Skin, name: String) -> int:
	for bind in skin.get_bind_count():
		if skin.get_bind_name(bind) == name:
			return bind
	return -1


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


func _vector_list(values: Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for v in values:
		result.append(_vector(v))
	return result


func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

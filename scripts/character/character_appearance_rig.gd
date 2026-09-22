class_name CharacterAppearanceRig
extends Node

## Dresses the model it is a child of in a CharacterAppearance. The model must
## be laid out like the player's: <model>/Armature/Skeleton3D/Mesh_0 (the
## player's PlayerModel and scenes/character/character_model.tscn both are).
##
## The human is made of parts baked by tools/character/bake_character_human.gd
## (data/character/human/<part>.res): the body goes in Mesh_0 and the eyes,
## teeth, tongue, eyebrows, eyelashes and hair are added under the skeleton.
## Every part shares the morph weights, which move the proxies with the face,
## and the Skin of the chosen sex. A BodyProportions modifier moves the joints
## to that body and applies head size and shoulder width; the armature scale
## gives the height.
##
## `live` keeps one blend shape per morph so every edit shows instantly (the
## creation screen); otherwise the morphs are baked into static meshes on
## apply, which costs a moment once but nothing per frame (gameplay).

const PARTS_PATH := "res://data/character/human/%s.res"
const RIG_DATA := "res://data/character/human/rig.tres"
const MATERIALS := {
	HumanPartData.Kind.BODY: "res://data/character/materials/human_skin.tres",
	HumanPartData.Kind.EYES: "res://data/character/materials/human_eyes.tres",
	HumanPartData.Kind.TEETH: "res://data/character/materials/human_teeth.tres",
	HumanPartData.Kind.TONGUE: "res://data/character/materials/human_tongue.tres",
	HumanPartData.Kind.EYEBROWS: "res://data/character/materials/human_brows.tres",
	HumanPartData.Kind.EYELASHES: "res://data/character/materials/human_brows.tres",
	HumanPartData.Kind.HAIR: "res://data/character/materials/human_hair.tres",
}
const EYELASH_COLOR := Color("1c1612")
## Briefs from below the hip joints to above the pelvis joint, and the chest
## band around the Spine2 joint, as offsets in metres of rest height.
const BRIEFS_BAND := Vector2(-0.085, 0.085)
const TOP_BAND := Vector2(-0.075, 0.07)
const SLOTS: Array[StringName] = [&"eyes", &"teeth", &"tongue", &"eyebrows", &"eyelashes", &"hair"]

@export var live := false

var _rig_data: HumanRigData
var _armature: Node3D
var _skeleton: Skeleton3D
var _proportions: BodyProportions
var _armature_basis: Basis
## Slot -> {instance: MeshInstance3D, part: StringName, data: HumanPartData,
## material: Material, weights: Dictionary of the last bake or null}.
var _slots := {}


func _ready() -> void:
	_setup()


func apply(appearance: CharacterAppearance) -> void:
	if not _setup():
		return
	var sex := appearance.get_sex()
	var sex_data: Dictionary = AppearanceCatalog.SEXES.get(sex, {})
	var weights := _morph_weights(appearance, sex)
	var skin: Skin = _rig_data.skins[sex]
	var hair_style: Dictionary = AppearanceCatalog.HAIR_STYLES.get(appearance.get_value(AppearanceCatalog.HAIR_STYLE), {})
	var eyebrows: Dictionary = AppearanceCatalog.EYEBROW_STYLES.get(appearance.get_value(AppearanceCatalog.EYEBROWS), {})
	_show(&"body", &"body", weights, skin)
	for slot in [&"eyes", &"teeth", &"tongue"]:
		_show(slot, slot, weights, skin)
	_show(&"eyebrows", eyebrows.get("part", &""), weights, skin)
	_show(&"eyelashes", sex_data.get("eyelashes", &""), weights, skin)
	_show(&"hair", hair_style.get("part", &""), weights, skin)

	var skin_material: ShaderMaterial = _slots[&"body"].material
	skin_material.set_shader_parameter(&"albedo_texture", load(_rig_data.skin_textures[sex]))
	skin_material.set_shader_parameter(&"texture_tone", _rig_data.skin_tones[sex])
	var landmarks := _rig_data.landmarks
	skin_material.set_shader_parameter(&"briefs_band",
			Vector2(landmarks[&"legs"] + BRIEFS_BAND.x, landmarks[&"hips"] + BRIEFS_BAND.y))
	skin_material.set_shader_parameter(&"top_band",
			Vector2(landmarks[&"chest"] + TOP_BAND.x, landmarks[&"chest"] + TOP_BAND.y))
	var shader := _shader_values(appearance, sex_data)
	for param in shader:
		skin_material.set_shader_parameter(param, shader[param])
	var hair_color: Color = appearance.get_value(&"hair_color")
	_set_param(&"eyes", &"eye_color", appearance.get_value(&"eye_color"))
	_set_param(&"eyebrows", &"hair_color", hair_color)
	_set_param(&"hair", &"hair_color", hair_color)
	_set_param(&"eyelashes", &"hair_color", EYELASH_COLOR)
	_set_param(&"eyelashes", &"density", sex_data.get("eyelash_density", 1.0))

	var proportions := _proportion_values(appearance)
	var offsets := {}
	var sex_offsets: Dictionary = _rig_data.bone_offsets[sex]
	for bone_name in sex_offsets:
		var bone := _skeleton.find_bone(bone_name)
		if bone >= 0:
			offsets[bone] = sex_offsets[bone_name]
	_proportions.bone_offsets = offsets
	_proportions.head_scale = 1.0 + proportions.get(&"head_size", 0.0)
	_proportions.shoulder_width = proportions.get(&"shoulder_width", 0.0)
	_armature.basis = _armature_basis.scaled(Vector3.ONE * (1.0 + proportions.get(&"height", 0.0)))


## Morph name -> weight for every baked morph. A slider picks "<id>" or
## "<id>-" by its sign; morphs baked per sex ("<id>@female") are split
## between the sexes.
func _morph_weights(appearance: CharacterAppearance, sex: StringName) -> Dictionary:
	var available: PackedStringArray = _part(&"body").names
	var weights := {}
	for morph in available:
		weights[StringName(morph)] = 0.0
	var female := 1.0 if sex == &"female" else 0.0
	for option in AppearanceCatalog.all_options():
		if option.kind != AppearanceOption.Kind.SLIDER or not option.morph:
			continue
		var value := option.target_value(appearance.get_value(option.id))
		var side := String(option.morph) if value >= 0.0 else String(option.morph) + "-"
		var amount := absf(value)
		if not available.has(side) and not available.has(side + "@male"):
			# One-sided morph: extrapolate it backwards.
			side = String(option.morph)
			amount = value
		if available.has(side + "@male"):
			weights[StringName(side + "@male")] = amount * (1.0 - female)
			weights[StringName(side + "@female")] = amount * female
		elif available.has(side):
			weights[StringName(side)] = amount
	var sex_data: Dictionary = AppearanceCatalog.SEXES.get(sex, {})
	for morph in sex_data.get("morphs", {}):
		weights[morph] = weights.get(morph, 0.0) + sex_data.morphs[morph]
	return weights


func _shader_values(appearance: CharacterAppearance, sex_data: Dictionary) -> Dictionary:
	var values := {}
	# Values a sex adds start from zero, so switching sex undoes them.
	for sex in AppearanceCatalog.SEXES.values():
		for key in sex.get("shader", {}):
			values[key] = 0.0
	for option in AppearanceCatalog.all_options():
		if not option.shader_param:
			continue
		var value: Variant = appearance.get_value(option.id)
		values[option.shader_param] = option.target_value(value) if option.kind == AppearanceOption.Kind.SLIDER else value
	for key in sex_data.get("shader", {}):
		values[key] = values.get(key, 0.0) + sex_data.shader[key]
	return values


func _proportion_values(appearance: CharacterAppearance) -> Dictionary:
	var values := {}
	for option in AppearanceCatalog.all_options():
		if option.proportion:
			values[option.proportion] = option.target_value(appearance.get_value(option.id))
	return values


## Shows `part` in `slot` (an empty part hides the slot), with the weights
## applied the live or the baked way.
func _show(slot: StringName, part: StringName, weights: Dictionary, skin: Skin) -> void:
	var state: Dictionary = _slots[slot]
	var instance: MeshInstance3D = state.instance
	if part == &"":
		instance.visible = false
		state.part = &""
		return
	var data := _part(part)
	if state.part != part:
		state.part = part
		state.data = data
		state.weights = null
		state.material = _material_for(data)
		instance.material_override = state.material
		if live:
			instance.mesh = data.morphable()
		# The body's scanned LODs are gone; keep full detail up close.
		instance.lod_bias = 100.0 if live else 4.0
	instance.visible = true
	instance.skin = skin
	if live:
		for i in instance.get_blend_shape_count():
			instance.set_blend_shape_value(i, weights.get(StringName(instance.mesh.get_blend_shape_name(i)), 0.0))
		return
	var active := {}
	for morph in data.names:
		var w: float = weights.get(StringName(morph), 0.0)
		if not is_zero_approx(w):
			active[StringName(morph)] = w
	if state.weights == null or active != state.weights:
		instance.mesh = data.baked(active)
		state.weights = active


func _material_for(data: HumanPartData) -> Material:
	var material: Material = load(MATERIALS[data.kind]).duplicate()
	if not data.textures.has("albedo"):
		return material
	var albedo: Texture2D = load(data.textures.albedo)
	if material is ShaderMaterial:
		material.set_shader_parameter(&"albedo_texture", albedo)
		material.set_shader_parameter(&"texture_tone", data.tone)
	elif material is StandardMaterial3D:
		material.albedo_texture = albedo
	return material


func _set_param(slot: StringName, param: StringName, value: Variant) -> void:
	var material: Variant = _slots[slot].material
	if material is ShaderMaterial:
		material.set_shader_parameter(param, value)


func _part(part: StringName) -> HumanPartData:
	return load(PARTS_PATH % part)


func _setup() -> bool:
	if _skeleton != null:
		return true
	var model := get_parent()
	_armature = model.get_node_or_null("Armature") as Node3D
	_skeleton = model.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	var body := model.get_node_or_null("Armature/Skeleton3D/Mesh_0") as MeshInstance3D
	if _armature == null or _skeleton == null or body == null:
		push_error("CharacterAppearanceRig: '%s' has no Armature/Skeleton3D/Mesh_0" % model.name)
		_skeleton = null
		return false
	_rig_data = load(RIG_DATA)
	_armature_basis = _armature.basis
	_proportions = BodyProportions.new()
	_proportions.name = "BodyProportions"
	_skeleton.add_child(_proportions)
	_skeleton.move_child(_proportions, 0)
	_slots[&"body"] = {instance = body, part = &"", data = null, material = null, weights = null}
	for slot in SLOTS:
		var instance := MeshInstance3D.new()
		instance.name = "Human" + String(slot).capitalize()
		instance.visible = false
		_skeleton.add_child(instance)
		instance.skeleton = instance.get_path_to(_skeleton)
		_slots[slot] = {instance = instance, part = &"", data = null, material = null, weights = null}
	return true

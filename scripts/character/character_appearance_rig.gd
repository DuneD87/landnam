class_name CharacterAppearanceRig
extends Node

## Dresses the model it is a child of in a CharacterAppearance. The model must
## be laid out like the player's: <model>/Armature/Skeleton3D/Mesh_0 (the
## player's PlayerModel and scenes/character/character_model.tscn both are).
##
## The human (tools/character/bake_character_human.gd) is a body with morphs
## and proxies refitted to it (eyes, teeth, tongue, eyebrows, eyelashes, hair,
## beard, the male genitals, which wear the body's own skin material); HumanShape evaluates both for the appearance's morph weights. The
## body goes in Mesh_0, the proxies under the skeleton, all with one Skin. The
## joints follow the morphs too: a BodyProportions modifier moves them where
## the current body has them.
##
## `live` keeps the body's morphs as blend shapes so every edit shows at once
## and refits the proxies on each change (the creation screen); otherwise
## everything is baked into static meshes on apply, which costs a moment once
## but nothing per frame (gameplay). Either way the blink stays a blend shape
## of the body and the eyelashes, which a HumanBlink child animates.

const BODY_DATA := "res://data/character/human/body.res"
const PROXY_PATH := "res://data/character/human/proxies/%s.res"
const MATERIALS := {
	HumanProxyData.Kind.EYES: "res://data/character/materials/human_eyes.tres",
	HumanProxyData.Kind.TEETH: "res://data/character/materials/human_teeth.tres",
	HumanProxyData.Kind.TONGUE: "res://data/character/materials/human_tongue.tres",
	HumanProxyData.Kind.EYEBROWS: "res://data/character/materials/human_brows.tres",
	HumanProxyData.Kind.EYELASHES: "res://data/character/materials/human_brows.tres",
	HumanProxyData.Kind.HAIR: "res://data/character/materials/human_hair.tres",
	HumanProxyData.Kind.BEARD: "res://data/character/materials/human_hair.tres",
}
const SKIN_MATERIAL := "res://data/character/materials/human_skin.tres"
const EYELASH_COLOR := Color("1c1612")
## Buzz cut density painted on the scalp under any haircut.
const UNDER_HAIR_SCALP := 0.6
const SLOTS: Array[StringName] = [&"eyes", &"teeth", &"tongue", &"eyebrows", &"eyelashes", &"hair", &"beard",
		&"genitals"]

@export var live := false

var _data: HumanBodyData
var _shape: HumanShape
var _armature: Node3D
var _skeleton: Skeleton3D
var _body: MeshInstance3D
var _proportions: BodyProportions
var _blink: HumanBlink
var _skin_material: ShaderMaterial
## Slot -> {instance: MeshInstance3D, part: StringName, proxy: HumanProxyData,
## material: Material, mesh: ArrayMesh}.
var _slots := {}
## Weights and sex of the last geometry update, to skip it when only
## colours change.
var _applied_weights := {}
var _applied_sex := &""
var _rest_origins: PackedVector3Array
var _bone_indices: PackedInt32Array
var _parents: PackedInt32Array


func _ready() -> void:
	_setup()


func apply(appearance: CharacterAppearance) -> void:
	if not _setup():
		return
	var sex := appearance.get_sex()
	var sex_data: Dictionary = AppearanceCatalog.SEXES.get(sex, {})
	var weights := _morph_weights(appearance, sex)
	var hair_style: Dictionary = AppearanceCatalog.HAIR_STYLES.get(appearance.get_value(AppearanceCatalog.HAIR_STYLE), {})
	var beard: Dictionary = AppearanceCatalog.BEARDS.get(appearance.get_value(AppearanceCatalog.BEARD), {})
	var eyebrows: Dictionary = AppearanceCatalog.EYEBROW_STYLES.get(appearance.get_value(AppearanceCatalog.EYEBROWS), {})
	var parts := {
		&"eyes": &"eyes", &"teeth": &"teeth", &"tongue": &"tongue",
		&"eyebrows": eyebrows.get("part", &""), &"eyelashes": sex_data.get("eyelashes", &""),
		&"hair": hair_style.get("part", &""), &"beard": beard.get("part", &"") if sex == &"male" else &"",
		&"genitals": sex_data.get("genitals", &""),
	}

	var geometry_changed := weights != _applied_weights or sex != _applied_sex
	if geometry_changed:
		_shape.set_weights(weights, sex)
		_applied_weights = weights
		_applied_sex = sex
		_update_body(weights)
		_update_skeleton()
	for slot in SLOTS:
		_show(slot, parts[slot], geometry_changed)
	_update_blink()

	var shader := _shader_values(appearance)
	_apply_skin_material(appearance, sex, hair_style, shader)
	var hair_color: Color = appearance.get_value(&"hair_color")
	for slot in [&"hair", &"beard", &"eyebrows"]:
		_set_param(slot, &"hair_color", hair_color)
		_set_param(slot, &"gray", shader.get(&"gray", 0.0))
	_set_param(&"eyes", &"eye_color", appearance.get_value(&"eye_color"))
	_set_param(&"eyelashes", &"hair_color", EYELASH_COLOR)
	_set_param(&"eyelashes", &"density", sex_data.get("eyelash_density", 1.0))


## Morph name -> weight for every body morph. A slider picks "<id>" or
## "<id>-" by its sign; morphs baked per sex ("<id>@female") take the
## character's sex. Crosses ("a&b-@sex") get the product of their two
## macros when both sit on the cross's side.
func _morph_weights(appearance: CharacterAppearance, sex: StringName) -> Dictionary:
	var weights := {}
	var targets := {}
	for option in AppearanceCatalog.all_options():
		if option.kind != AppearanceOption.Kind.SLIDER or not option.morph:
			continue
		var value := option.target_value(appearance.get_value(option.id))
		targets[option.morph] = value
		if is_zero_approx(value):
			continue
		var side := String(option.morph) + ("" if value >= 0.0 else "-")
		var amount := absf(value)
		if not _data.has_morph(side) and not _data.has_morph(side + "@" + sex) and value < 0.0:
			# One-sided morph: extrapolate it backwards.
			side = String(option.morph)
			amount = value
		if _data.has_morph(side + "@" + sex):
			weights[StringName(side + "@" + sex)] = amount
		elif _data.has_morph(side):
			weights[StringName(side)] = amount
	for name in _data.names:
		var at := name.find("@")
		if name.find("&") < 0 or at < 0 or name.substr(at + 1) != sex:
			continue
		var pair := name.substr(0, at).split("&")
		var product := 1.0
		for term in pair:
			var negative := term.ends_with("-")
			var value: float = targets.get(StringName(term.trim_suffix("-")), 0.0)
			product *= absf(value) if (value < 0.0) == negative and not is_zero_approx(value) else 0.0
		if product > 0.0:
			weights[StringName(name)] = product
	var sex_data: Dictionary = AppearanceCatalog.SEXES.get(sex, {})
	for morph in sex_data.get("morphs", {}):
		weights[morph] = weights.get(morph, 0.0) + sex_data.morphs[morph]
	return weights


func _shader_values(appearance: CharacterAppearance) -> Dictionary:
	var values := {}
	for option in AppearanceCatalog.all_options():
		if option.kind == AppearanceOption.Kind.SLIDER and option.shader_param:
			values[option.shader_param] = option.target_value(appearance.get_value(option.id))
	return values


func _update_body(weights: Dictionary) -> void:
	if live:
		if _body.mesh == null or _body.mesh.get_blend_shape_count() == 0:
			_body.mesh = _shape.body_morphable()
		for i in _body.get_blend_shape_count():
			_body.set_blend_shape_value(i, weights.get(StringName(_body.mesh.get_blend_shape_name(i)), 0.0))
	else:
		_body.mesh = _shape.body_baked({HumanShape.BLINK: _shape.blink_mix()})
	_body.skin = _data.skin


## Hands the blink its blend shapes: the live body's own morphs, or the baked
## body's blink, and the proxies' blinks.
func _update_blink() -> void:
	var targets: Array[Array] = []
	if live:
		var mix := _shape.blink_mix()
		for morph in mix:
			targets.append([_body, morph, _applied_weights.get(morph, 0.0), mix[morph]])
	else:
		targets.append([_body, HumanShape.BLINK, 0.0, 1.0])
	for slot in SLOTS:
		var instance: MeshInstance3D = _slots[slot].instance
		if instance.visible:
			targets.append([instance, HumanShape.BLINK, 0.0, 1.0])
	_blink.set_targets(targets)


## Moves every joint where the current body has it (see HumanShape).
func _update_skeleton() -> void:
	var joints := _shape.joint_positions()
	var globals: Array[Transform3D] = []
	globals.resize(joints.size())
	for b in joints.size():
		globals[b] = _data.skin_to_skeleton * Transform3D(_data.orientations[b], joints[b])
	var offsets := {}
	for b in joints.size():
		var bone := _bone_indices[b]
		if bone < 0:
			continue
		var parent := _parents[b]
		var local := globals[b].origin if parent < 0 else globals[parent].affine_inverse() * globals[b].origin
		offsets[bone] = local - _rest_origins[b]
	_proportions.bone_offsets = offsets


func _apply_skin_material(appearance: CharacterAppearance, sex: StringName, hair_style: Dictionary, shader: Dictionary) -> void:
	var skin_id: StringName = appearance.get_value(AppearanceCatalog.SKIN)
	var skin: Dictionary = _data.skins.get(skin_id, _data.skins.values()[0])
	var m := _skin_material
	m.set_shader_parameter(&"albedo_texture", load(skin.texture))
	m.set_shader_parameter(&"texture_tone", skin.tone)
	m.set_shader_parameter(&"normal_texture", load(_data.normal_maps.get(sex, _data.normal_maps.values()[0])))
	m.set_shader_parameter(&"hair_color", appearance.get_value(&"hair_color"))
	# Under a haircut the scalp shows roots, so gaps and the hairline blend.
	var haircut: bool = hair_style.get("part", &"") != &""
	m.set_shader_parameter(&"scalp_hair", hair_style.get("scalp", UNDER_HAIR_SCALP if haircut else 0.0))
	m.set_shader_parameter(&"scalp_spread", 1.0 if haircut else 0.0)
	if sex != &"male":
		m.set_shader_parameter(&"stubble", 0.0)
	m.set_shader_parameter(&"male_pattern", 1.0 if sex == &"male" else 0.0)
	# Muscle brings out the relief; fat hides it.
	var muscle := AppearanceCatalog.find(&"muscle").target_value(appearance.get_value(&"muscle"))
	var weight := AppearanceCatalog.find(&"body_weight").target_value(appearance.get_value(&"body_weight"))
	var relief: float = shader.get(&"definition", 1.0) * (1.0 + 0.6 * maxf(muscle, 0.0) - 0.3 * maxf(-muscle, 0.0)) \
			* (1.0 - 0.5 * maxf(weight, 0.0))
	for option in AppearanceCatalog.all_options():
		if option.material != &"skin" or not option.shader_param:
			continue
		if option.kind == AppearanceOption.Kind.COLOR:
			m.set_shader_parameter(option.shader_param, appearance.get_value(option.id))
		elif option.kind == AppearanceOption.Kind.SLIDER:
			m.set_shader_parameter(option.shader_param, shader[option.shader_param])
	m.set_shader_parameter(&"definition", relief)


## Shows `part` in `slot` (an empty part hides it), refitted to the body.
func _show(slot: StringName, part: StringName, geometry_changed: bool) -> void:
	var state: Dictionary = _slots[slot]
	var instance: MeshInstance3D = state.instance
	if part == &"":
		instance.visible = false
		state.part = &""
		return
	var changed_part: bool = state.part != part
	if changed_part:
		var proxy: HumanProxyData = load(PROXY_PATH % part)
		state.part = part
		state.proxy = proxy
		state.material = _material_for(proxy)
		instance.material_override = state.material
	if changed_part or geometry_changed or not instance.visible:
		state.mesh = _shape.proxy_mesh(state.proxy, state.mesh)
		instance.mesh = state.mesh
	instance.skin = _data.skin
	instance.visible = true


func _material_for(proxy: HumanProxyData) -> Material:
	if proxy.kind == HumanProxyData.Kind.GENITALS:
		return _skin_material
	var material: Material = load(MATERIALS[proxy.kind]).duplicate()
	if material.next_pass != null:
		material.next_pass = material.next_pass.duplicate()
	if material is StandardMaterial3D:
		if proxy.textures.has("albedo"):
			material.albedo_texture = load(proxy.textures.albedo)
		return material
	var params := {&"texture_tone": proxy.tone, &"strand_axis": proxy.strand_axis}
	if proxy.textures.has("albedo"):
		params[&"albedo_texture"] = load(proxy.textures.albedo)
	if proxy.textures.has("normal"):
		params[&"normal_texture"] = load(proxy.textures.normal)
		params[&"use_normal"] = true
	for param in params:
		_set_material_param(material, param, params[param])
	return material


func _set_param(slot: StringName, param: StringName, value: Variant) -> void:
	_set_material_param(_slots[slot].material, param, value)


## Sets a uniform on a shader material and its further passes.
static func _set_material_param(material: Material, param: StringName, value: Variant) -> void:
	while material != null:
		if material is ShaderMaterial:
			material.set_shader_parameter(param, value)
		material = material.next_pass


func _setup() -> bool:
	if _skeleton != null:
		return true
	var model := get_parent()
	_armature = model.get_node_or_null("Armature") as Node3D
	_skeleton = model.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	_body = model.get_node_or_null("Armature/Skeleton3D/Mesh_0") as MeshInstance3D
	if _armature == null or _skeleton == null or _body == null:
		push_error("CharacterAppearanceRig: '%s' has no Armature/Skeleton3D/Mesh_0" % model.name)
		_skeleton = null
		return false
	_data = load(BODY_DATA)
	_shape = HumanShape.new(_data)
	_skin_material = load(SKIN_MATERIAL).duplicate()
	_body.material_override = _skin_material
	# Full detail up close; the body has no LODs of its own.
	_body.lod_bias = 100.0 if live else 4.0
	_bone_indices.resize(_data.bone_names.size())
	_parents.resize(_data.bone_names.size())
	_rest_origins.resize(_data.bone_names.size())
	for b in _data.bone_names.size():
		var bone := _skeleton.find_bone(_data.bone_names[b])
		_bone_indices[b] = bone
		_rest_origins[b] = _skeleton.get_bone_rest(bone).origin if bone >= 0 else Vector3.ZERO
		var parent := _skeleton.get_bone_parent(bone) if bone >= 0 else -1
		_parents[b] = _data.bone_names.find(_skeleton.get_bone_name(parent)) if parent >= 0 else -1
	_proportions = BodyProportions.new()
	_proportions.name = "BodyProportions"
	_skeleton.add_child(_proportions)
	_skeleton.move_child(_proportions, 0)
	_blink = HumanBlink.new()
	_blink.name = "HumanBlink"
	add_child(_blink)
	_slots[&"body"] = {instance = _body}
	for slot in SLOTS:
		var instance := MeshInstance3D.new()
		instance.name = "Human" + String(slot).capitalize()
		instance.visible = false
		_skeleton.add_child(instance)
		instance.skeleton = instance.get_path_to(_skeleton)
		instance.lod_bias = _body.lod_bias
		_slots[slot] = {instance = instance, part = &"", proxy = null, material = null, mesh = null}
	return true

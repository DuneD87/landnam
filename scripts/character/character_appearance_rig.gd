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
##
## Armour made for the player scan is fitted to the body with dress(): the
## body is measured (BodyMeasurements) and ArmorFit carries each piece from
## the scan's measurements to its own. Dressed pieces are fitted again when
## the body changes.

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
## Slots tucked under hoods and helmets.
const HAIR_SLOTS: Array[StringName] = [&"hair", &"beard"]
const HEAD_BONE := &"mixamorig_Head"
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
## Measurements of the current body; null until asked for after a change.
var _measurements: BodyMeasurements
## Bumped on every change of the body, to tell fitted armour that is stale.
var _body_version := 0
## Armour pieces handed to dress().
var _dressed: Array[Node] = []
## Source armour mesh -> {version, mesh, points}: the last fit of each.
var _fitted := {}
## Source armour mesh -> {task, version, surfaces}: the fit running for it.
var _fitting := {}
## Fits whose body changed while they ran, still to be waited for.
var _stale_tasks: Array[int] = []
## Dressed pieces that cover the hair -> true.
var _covering := {}
## The hair must be tucked again; each change bumps the version, so a tuck
## that started before it is dropped.
var _hair_dirty := false
var _hair_version := 0
var _hair_task := -1
## {version, slots: slot -> surfaces (ArmorFit.source())} of the running tuck.
var _hair_job := {}
## Measurements, joints and skin of the current body for ArmorFit.
var _fit_context: ArmorFit

static var _reference: BodyMeasurements


func _ready() -> void:
	set_process(false)
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
	var hair_changed: bool = geometry_changed or parts[&"hair"] != _slots[&"hair"].part \
			or parts[&"beard"] != _slots[&"beard"].part
	if geometry_changed:
		_shape.set_weights(weights, sex)
		_applied_weights = weights
		_applied_sex = sex
		_update_body(weights)
		_update_skeleton()
		_measurements = null
		_body_version += 1
	for slot in SLOTS:
		_show(slot, parts[slot], geometry_changed)
	if geometry_changed:
		# After the proxies: the armour clears the genitals too.
		_refit_dressed()
	if hair_changed and not _covering.is_empty():
		_hair_changed()
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


## The current body's measurements, taken in the skeleton's rest pose.
func measurements() -> BodyMeasurements:
	if _measurements == null and _setup():
		# The live body keeps its morphs as blend shapes; measure them baked.
		var mesh: ArrayMesh = _shape.body_baked() if live else _body.mesh
		_measurements = BodyMeasurements.measure([[mesh, _data.skin]], _skeleton, _body_globals(),
				_armature.transform * _skeleton.transform)
	return _measurements


## Fits the armour `item` (a MeshInstance3D and its children skinned to this
## model's skeleton, made for the player scan) to the body, and keeps it
## fitted while it stays under the skeleton. A piece that `covers_hair`
## (a hood, a helmet) also tucks the hair and beard under it (HairTuck). The
## work runs on worker threads; until it is done the piece is hidden (see
## is_dressing()).
func dress(item: Node, covers_hair := false) -> void:
	if not _setup():
		return
	if not _dressed.has(item):
		_dressed.append(item)
	if covers_hair:
		_covering[item] = true
		_hair_changed()
	_fit(item)


## Forgets a piece taken off, and lets the hair out if it covered it.
func undress(item: Node) -> void:
	_dressed.erase(item)
	if _covering.erase(item):
		_hair_changed()


## Whether some armour is still being fitted, or the hair tucked under it.
func is_dressing() -> bool:
	return not _fitting.is_empty() or _hair_task >= 0 or _hair_dirty


func _refit_dressed() -> void:
	_fit_context = null
	_dressed = _dressed.filter(func(item: Node) -> bool:
			return is_instance_valid(item) and _skeleton.is_ancestor_of(item))
	for item in _covering.keys():
		if not _dressed.has(item):
			_covering.erase(item)
	for item in _dressed:
		_fit(item)


func _hair_changed() -> void:
	_hair_dirty = true
	_hair_version += 1
	set_process(true)


func _fit(item: Node) -> void:
	for instance in _armour_meshes(item):
		if not instance.has_meta(&"armor_source"):
			instance.set_meta(&"armor_source", instance.mesh)
		var source: ArrayMesh = instance.get_meta(&"armor_source")
		var fitted: Dictionary = _fitted.get(source, {})
		if fitted.get("version", -1) == _body_version:
			instance.mesh = fitted.mesh
			continue
		if instance.visible:
			instance.visible = false
			instance.set_meta(&"armor_hidden", true)
		var running: Dictionary = _fitting.get(source, {})
		if running.get("version", -1) == _body_version:
			continue
		var surfaces := ArmorFit.source(source)
		var binds: Array[Transform3D] = []
		for b in instance.skin.get_bind_count():
			binds.append(instance.skin.get_bind_pose(b))
		var bones := BodyMeasurements.bind_bones(instance.skin, _skeleton)
		var task := WorkerThreadPool.add_task(_context().fit.bind(surfaces, binds, bones), false,
				"Armour fit")
		if running.has("task"):
			_stale_tasks.append(running.task)
		_fitting[source] = {task = task, version = _body_version, surfaces = surfaces}
		set_process(true)


## Picks up the fits that are done and hands their meshes to the armour,
## then tucks the hair under what covers it, then shows the pieces.
func _process(_delta: float) -> void:
	_stale_tasks = _stale_tasks.filter(func(task: int) -> bool:
			if not WorkerThreadPool.is_task_completed(task):
				return true
			WorkerThreadPool.wait_for_task_completion(task)
			return false)
	for source: ArrayMesh in _fitting.keys():
		var running: Dictionary = _fitting[source]
		if not WorkerThreadPool.is_task_completed(running.task):
			continue
		WorkerThreadPool.wait_for_task_completion(running.task)
		_fitting.erase(source)
		if running.version != _body_version:
			continue
		var mesh := ArmorFit.build(running.surfaces, source.resource_name)
		# Its points at rest, for tucking the hair under it.
		var points := PackedVector3Array()
		for surface in running.surfaces:
			points.append_array(surface.points)
		_fitted[source] = {version = running.version, mesh = mesh, points = points}
		for item in _dressed:
			if not is_instance_valid(item):
				continue
			for instance in _armour_meshes(item):
				if instance.has_meta(&"armor_source") and instance.get_meta(&"armor_source") == source:
					instance.mesh = mesh
					if _covering.has(item):
						_hair_changed()
	if _fitting.is_empty():
		if _hair_task >= 0 and WorkerThreadPool.is_task_completed(_hair_task):
			WorkerThreadPool.wait_for_task_completion(_hair_task)
			_hair_task = -1
			if _hair_job.version == _hair_version:
				for slot in _hair_job.slots:
					var instance: MeshInstance3D = _slots[slot].instance
					instance.mesh = ArmorFit.build(_hair_job.slots[slot], _slots[slot].mesh.resource_name)
		if _hair_dirty and _hair_task < 0:
			_tuck_hair()
		if _hair_task < 0 and not _hair_dirty:
			_reveal()
	if _fitting.is_empty() and _stale_tasks.is_empty() and _hair_task < 0 and not _hair_dirty:
		set_process(false)


## Starts tucking the hair and beard under the covering pieces, or lets them
## out when there are none.
func _tuck_hair() -> void:
	_hair_dirty = false
	var cover := PackedVector3Array()
	for item in _covering:
		if not is_instance_valid(item) or not _skeleton.is_ancestor_of(item):
			continue
		for instance in _armour_meshes(item):
			var fitted: Dictionary = _fitted.get(instance.get_meta(&"armor_source") if instance.has_meta(&"armor_source") else null, {})
			if fitted.get("version", -1) != _body_version:
				continue
			cover.append_array(fitted.points)
	var slots := {}
	for slot in HAIR_SLOTS:
		var state: Dictionary = _slots[slot]
		if state.mesh == null or not state.instance.visible:
			continue
		if cover.is_empty():
			state.instance.mesh = state.mesh
		else:
			slots[slot] = ArmorFit.source(state.mesh)
	if slots.is_empty():
		return
	var context := _context()
	var head := _skeleton.find_bone(HEAD_BONE)
	var span := context.body.spans[head]
	var middle := context.body.section_at(head, 0.5)
	var centre := context.body_globals[head] * Vector3((middle[0] + middle[1]) * 0.5, (span.x + span.y) * 0.5,
			(middle[2] + middle[3]) * 0.5)
	var binds: Array[Transform3D] = []
	for b in _data.skin.get_bind_count():
		binds.append(_data.skin.get_bind_pose(b))
	_hair_job = {version = _hair_version, slots = slots}
	_hair_task = WorkerThreadPool.add_task(_tuck.bind(slots, cover, centre, context.body_globals[head].basis,
			context.body_globals, context.units, binds, BodyMeasurements.bind_bones(_data.skin, _skeleton)),
			false, "Hair tuck")


static func _tuck(slots: Dictionary, cover: PackedVector3Array, centre: Vector3, head_basis: Basis,
		globals: Array[Transform3D], units: float, binds: Array[Transform3D], bones: PackedInt32Array) -> void:
	var tuck := HairTuck.new(cover, centre, head_basis, globals, units)
	for slot in slots:
		for surface in slots[slot]:
			tuck.tuck(surface.arrays, binds, bones)


## Shows the pieces hidden while they were fitted.
func _reveal() -> void:
	for item in _dressed:
		if not is_instance_valid(item):
			continue
		for instance in _armour_meshes(item):
			if instance.get_meta(&"armor_hidden", false):
				instance.visible = true
				instance.remove_meta(&"armor_hidden")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for running in _fitting.values():
			WorkerThreadPool.wait_for_task_completion(running.task)
		for task in _stale_tasks:
			WorkerThreadPool.wait_for_task_completion(task)
		if _hair_task >= 0:
			WorkerThreadPool.wait_for_task_completion(_hair_task)


## The skinned meshes of an armour piece.
func _armour_meshes(item: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var nodes: Array[Node] = [item]
	nodes.append_array(item.find_children("*", "MeshInstance3D", true, false))
	for node in nodes:
		var instance := node as MeshInstance3D
		if instance != null and instance.skin != null and (instance.mesh != null or instance.has_meta(&"armor_source")):
			result.append(instance)
	return result


## What the armour is fitted with for the current body.
func _context() -> ArmorFit:
	if _fit_context != null:
		return _fit_context
	if _reference == null:
		_reference = load(BodyMeasurements.REFERENCE)
	var context := ArmorFit.new()
	context.reference = _reference
	context.reference_globals = BodyMeasurements.rest_globals(_skeleton)
	context.body = measurements()
	context.body_globals = _body_globals()
	context.units = 1.0 / (_armature.transform * _skeleton.transform).basis.get_scale().x
	# The skin it must clear: the body and the genitals, which sit on it.
	var mesh: ArrayMesh = _shape.body_baked() if live else _body.mesh
	var skin_meshes := [[mesh, _data.skin]]
	var genitals: MeshInstance3D = _slots[&"genitals"].instance
	if genitals.visible and genitals.mesh != null:
		skin_meshes.append([genitals.mesh, _data.skin])
	context.surface = ArmorFit.body_surface(skin_meshes, _skeleton, context.body_globals, context.units)
	_fit_context = context
	return context


## Every bone at rest in skeleton space, with the body's joints.
func _body_globals() -> Array[Transform3D]:
	return BodyMeasurements.rest_globals(_skeleton, _proportions.bone_offsets)


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
		# Ojos, pelo, dientes...: no llegan a ningún miembro que se pueda cercenar (Dismemberment).
		instance.set_meta(&"no_dismember", true)
		_skeleton.add_child(instance)
		instance.skeleton = instance.get_path_to(_skeleton)
		instance.lod_bias = _body.lod_bias
		_slots[slot] = {instance = instance, part = &"", proxy = null, material = null, mesh = null}
	return true

extends SceneTree

## Checks the character appearance data against the baked human and the rig
## that applies it:
##   godot --headless --path . --script res://tests/character/test_character_appearance.gd

const BODY := "res://data/character/human/body.res"
const PROXIES := "res://data/character/human/proxies/%s.res"
## Styles without `sexes` (every sex is offered them); the rest name theirs.
const SHARED_STYLES: Array[StringName] = [&"buzz", &"bald"]
## Least choices per sex.
const STYLES_PER_SEX := 20

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)


func _run() -> void:
	var body: HumanBodyData = load(BODY)
	_check_catalog(body)
	_check_appearance()
	_check_shape(body)
	_check_hair_styles(body)
	_check_rig()
	_check_first_person()
	print("CHARACTER APPEARANCE TESTS: %d failures" % failures)
	quit(1 if failures else 0)


## A morph the rig can resolve: either side of the slider, possibly per sex.
func _is_baked(body: HumanBodyData, morph: StringName) -> bool:
	for side in ["", "-"]:
		for sex in ["", "@male", "@female"]:
			if body.has_morph(StringName(String(morph) + side + sex)):
				return true
	return false


func _check_catalog(body: HumanBodyData) -> void:
	var missing := []
	for option in AppearanceCatalog.all_options():
		if option.morph and not _is_baked(body, option.morph):
			missing.append(option.morph)
	for sex in AppearanceCatalog.SEXES.values():
		for morph in sex.get("morphs", {}):
			if not body.has_morph(morph):
				missing.append(morph)
	check(missing.is_empty(), "every morph the catalog uses is baked %s" % [missing])

	var parts: Array[StringName] = []
	for table in [AppearanceCatalog.HAIR_STYLES, AppearanceCatalog.BEARDS, AppearanceCatalog.EYEBROW_STYLES]:
		for entry in table.values():
			if entry.part != &"":
				parts.append(entry.part)
	for sex in AppearanceCatalog.SEXES.values():
		parts.append(sex.eyelashes)
		if sex.has("genitals"):
			parts.append(sex.genitals)
	var broken := []
	for part in parts:
		if not load(PROXIES % part) is HumanProxyData:
			broken.append(part)
	check(broken.is_empty(), "every proxy the catalog names is baked %s" % [broken])
	var unused_hair := []
	for file in DirAccess.get_files_at("res://data/character/human/proxies"):
		if file.begins_with("hair_") and file.ends_with(".res") and not StringName(file.get_basename()) in parts:
			unused_hair.append(file)
	check(unused_hair.is_empty(), "every baked hair style is offered in the creator %s" % [unused_hair])

	var skins_ok := true
	for id in AppearanceCatalog.SKINS:
		var skin: Dictionary = body.skins.get(id, {})
		skins_ok = skins_ok and skin.has("texture") and ResourceLoader.exists(skin.texture)
		skins_ok = skins_ok and skin.get("sex") in AppearanceCatalog.SKINS[id].sexes
	check(skins_ok, "every skin the catalog offers is baked for its sex")

	var unoffered := []
	var cuts := {}
	for id in AppearanceCatalog.HAIR_STYLES:
		var sexes: Array = AppearanceCatalog.HAIR_STYLES[id].get("sexes", [])
		if sexes.is_empty() and not id in SHARED_STYLES:
			unoffered.append(id)
		for sex in sexes:
			cuts[sex] = cuts.get(sex, 0) + 1
	check(unoffered.is_empty(), "every cut names its sexes, besides buzz and bald %s" % [unoffered])
	check(cuts.get(&"male", 0) >= STYLES_PER_SEX and cuts.get(&"female", 0) >= STYLES_PER_SEX,
		"each sex has at least %d cuts %s" % [STYLES_PER_SEX, cuts])

	var scope := AppearanceCatalog.preset_scope(AppearanceCatalog.FACE_PRESET)
	var stray := []
	var per_sex := {}
	for preset in AppearanceCatalog.FACE_PRESETS:
		for id in preset.values:
			if not id in scope:
				stray.append(id)
		for sex in preset.sexes:
			per_sex[sex] = per_sex.get(sex, 0) + 1
	check(stray.is_empty(), "face presets only set face sliders %s" % [stray])
	check(per_sex.get(&"male", 0) >= 4 and per_sex.get(&"female", 0) >= 4, "each sex has several face presets")

	var defaults_ok := true
	for option in AppearanceCatalog.all_options():
		for sex in AppearanceCatalog.SEXES:
			var value: Variant = option.default_for(sex)
			if option.kind == AppearanceOption.Kind.SLIDER:
				defaults_ok = defaults_ok and value >= option.min_value and value <= option.max_value
			elif option.kind == AppearanceOption.Kind.CHOICE and option.is_available(sex):
				defaults_ok = defaults_ok and option.offers(value, sex)
	check(defaults_ok, "slider and choice defaults are within their options for each sex")


func _check_appearance() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var character := CharacterData.new()
	character.display_name = "Aila"
	character.appearance.set_sex(&"female")
	character.appearance.randomize_values(rng)
	var restored := CharacterData.from_dict(JSON.parse_string(JSON.stringify(character.to_dict())))
	check(restored.display_name == "Aila", "the name survives a JSON round trip")
	var same := true
	for option in AppearanceCatalog.all_options():
		var a: Variant = character.appearance.get_value(option.id)
		var b: Variant = restored.appearance.get_value(option.id)
		if a is Color:
			same = same and (a as Color).is_equal_approx(b)
		elif a is float:
			same = same and is_equal_approx(a, b)
		else:
			same = same and a == b
	check(same, "every appearance value survives a JSON round trip")
	var style: StringName = character.appearance.get_value(AppearanceCatalog.HAIR_STYLE)
	check(AppearanceCatalog.find(AppearanceCatalog.HAIR_STYLE).offers(style, &"female"),
			"a random woman gets a hair style offered to women (%s)" % style)

	var appearance := CharacterAppearance.new()
	appearance.set_value(&"breast_size", 0.6)
	check(is_zero_approx(appearance.get_value(&"breast_size")), "a male body ignores the bust slider")
	appearance.set_value(AppearanceCatalog.HAIR_STYLE, &"pompadour")
	appearance.set_value(&"jaw_width", 0.9)
	appearance.set_sex(&"female")
	check(is_equal_approx(appearance.get_value(&"breast_size"), AppearanceCatalog.find(&"breast_size").default_for(&"female")),
			"switching to female starts from her default bust")
	appearance.set_value(&"breast_size", 0.6)
	check(is_equal_approx(appearance.get_value(&"breast_size"), 0.6), "a female body uses the bust slider")
	check(appearance.get_value(AppearanceCatalog.HAIR_STYLE) == &"long_straight", "switching to female takes her default hair")
	var female_face: Dictionary = AppearanceCatalog.FACE_PRESETS.filter(func(p): return p.id == &"f_default")[0].values
	check(is_equal_approx(appearance.get_value(&"jaw_width"), female_face[&"jaw_width"]),
			"switching sex starts from that sex's default face")
	appearance.apply_preset(AppearanceCatalog.find(AppearanceCatalog.FACE_PRESET), &"f_soft")
	check(appearance.get_value(AppearanceCatalog.FACE_PRESET) == &"f_soft" and is_equal_approx(appearance.get_value(&"head_round"), 0.5),
			"a face preset sets its sliders")
	appearance.set_value(&"nose_size", 0.4)
	appearance.reset()
	check(appearance.get_sex() == &"female" and is_equal_approx(appearance.get_value(&"nose_size"), female_face[&"nose_size"]),
			"reset keeps the sex and returns to the default face")
	var legacy := CharacterAppearance.from_dict({"nose_size": 9.0, "unknown_trait": 1.0, "hair_style": "mohawk"})
	check(is_equal_approx(legacy.get_value(&"nose_size"), 1.0) and legacy.get_value(AppearanceCatalog.HAIR_STYLE) == &"regular",
			"loading clamps sliders and falls back from unknown choices")


func _check_shape(body: HumanBodyData) -> void:
	var morphable := body.mesh
	var shape := HumanShape.new(body)
	var live := shape.body_morphable()
	check(live.get_blend_shape_count() == body.names.size(), "the live body has one blend shape per morph")
	check(live.surface_get_array_len(0) == morphable.surface_get_array_len(0), "the live body keeps the base vertices")

	var hair: HumanProxyData = load(PROXIES % "hair_ht_long_straight")
	shape.set_weights({}, &"female")
	var rest_hair := shape.proxy_positions(hair)
	shape.set_weights({&"sex_female": 1.0, &"muscle@female": 1.0, &"head_size": 1.0}, &"female")
	var baked := shape.body_baked()
	var arrays := baked.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var base: PackedVector3Array = morphable.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var moved := 0
	var finite := true
	for i in vertices.size():
		if vertices[i].distance_to(base[i]) > 1e-5:
			moved += 1
		finite = finite and vertices[i].is_finite() and normals[i].is_finite() and absf(normals[i].length() - 1.0) < 1e-3
	check(baked.get_blend_shape_count() == 0 and moved > 5000, "a baked body has the morphs in its vertices (%d moved)" % moved)
	check(finite, "baked positions and normals are finite and normals unit length")

	var fitted := shape.proxy_positions(hair)
	var hair_ok := fitted.size() == hair.mesh.surface_get_array_len(0)
	var grown := 0
	for i in fitted.size():
		hair_ok = hair_ok and fitted[i].is_finite()
		if fitted[i].distance_to(rest_hair[i]) > 0.002:
			grown += 1
	check(hair_ok and grown > fitted.size() / 2, "the hair refits to a bigger head (%d of %d moved)" % [grown, fitted.size()])
	var joints := shape.joint_positions()
	check(joints.size() == body.bone_names.size(), "the joints follow the morphs")


## Every hair needs valid textures and anchors after a fresh export, and must
## survive a save and refit to both ends of its offered body's head-size slider.
func _check_hair_styles(body: HumanBodyData) -> void:
	var shape := HumanShape.new(body)
	var option := AppearanceCatalog.find(AppearanceCatalog.HAIR_STYLE)
	var broken := []
	var untranslated := []
	for locale in ["en", "es"]:
		var translation: Translation = load("res://localization/translations.%s.translation" % locale)
		if translation == null:
			untranslated.append(locale)
			continue
		for entry in AppearanceCatalog.HAIR_STYLES.values():
			if translation.get_message(entry.label).is_empty():
				untranslated.append("%s/%s" % [locale, entry.label])
	check(untranslated.is_empty(), "every hair style has an English and Spanish name %s" % [untranslated])
	for sex in AppearanceCatalog.SEXES:
		for choice in option.choices_for(sex):
			var appearance := CharacterAppearance.new()
			appearance.set_sex(sex)
			appearance.set_value(AppearanceCatalog.HAIR_STYLE, choice.id)
			var restored := CharacterAppearance.from_dict(appearance.to_dict())
			var ok: bool = restored.get_value(AppearanceCatalog.HAIR_STYLE) == choice.id
			var part: StringName = AppearanceCatalog.HAIR_STYLES[choice.id].part
			if part == &"":
				if not ok:
					broken.append(choice.id)
				continue
			var hair: HumanProxyData = load(PROXIES % part)
			if hair == null:
				broken.append(part)
				continue
			ok = ok and hair.kind == HumanProxyData.Kind.HAIR and hair.textures.has("albedo")
			for texture in hair.textures.values():
				ok = ok and ResourceLoader.exists(texture)
			for head_morph in [&"head_size", &"head_size-"]:
				var weights := {head_morph: 1.0}
				if sex == &"female":
					weights[&"sex_female"] = 1.0
				shape.set_weights(weights, sex)
				var points := shape.proxy_positions(hair)
				ok = ok and points.size() == hair.mesh.surface_get_array_len(0) and not points.is_empty()
				for point in points:
					ok = ok and point.is_finite()
			if not ok:
				broken.append(part)
	check(broken.is_empty(), "all hair styles save, load textures and fit small and large heads %s" % [broken])


func _check_rig() -> void:
	var model: Node3D = load("res://scenes/character/character_model.tscn").instantiate()
	root.add_child(model)
	var rig: CharacterAppearanceRig = model.get_node("AppearanceRig")
	var body: MeshInstance3D = model.get_node("Armature/Skeleton3D/Mesh_0")
	var appearance := CharacterAppearance.new()
	appearance.set_sex(&"female")
	appearance.set_value(&"height", 1.0)
	rig.apply(appearance)
	var hair: MeshInstance3D = model.get_node("Armature/Skeleton3D/HumanHair")
	var eyes: MeshInstance3D = model.get_node("Armature/Skeleton3D/HumanEyes")
	check(body.mesh.get_blend_shape_count() == 1 and body.mesh.get_blend_shape_name(0) == HumanShape.BLINK
			and body.material_override is ShaderMaterial, "gameplay rig bakes the body but for the blink")
	check(eyes.skin == body.skin and hair.skin == body.skin, "every part shares the body's skin")
	var lashes: MeshInstance3D = model.get_node("Armature/Skeleton3D/HumanEyelashes")
	check(lashes.find_blend_shape_by_name(HumanShape.BLINK) >= 0 and eyes.find_blend_shape_by_name(HumanShape.BLINK) < 0
			and hair.find_blend_shape_by_name(HumanShape.BLINK) < 0, "the eyelashes blink with the lids, the eyeballs do not")
	var open: PackedVector3Array = lashes.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var shut: PackedVector3Array = lashes.mesh.surface_get_blend_shape_arrays(0)[0][Mesh.ARRAY_VERTEX]
	var lowest := 0.0
	for i in open.size():
		lowest = minf(lowest, shut[i].y - open[i].y)
	check(lowest < -0.005, "the upper eyelashes come down to shut the eyes (%.1f mm)" % (lowest * 1000.0))
	check(hair.visible and hair.mesh != null and eyes.visible, "the female default hair and the eyes are shown")
	check(not model.get_node("Armature/Skeleton3D/HumanGenitals").visible, "a female body has no male genitals")
	var hair_material := hair.material_override as ShaderMaterial
	check(hair_material != null and hair_material.next_pass is ShaderMaterial
			and hair_material.next_pass.get_shader_parameter(&"albedo_texture") != null,
			"the hair's fringe pass gets the hair's texture too")
	var material: ShaderMaterial = body.material_override
	appearance.set_sex(&"male")
	appearance.set_value(AppearanceCatalog.HAIR_STYLE, &"buzz")
	rig.apply(appearance)
	var scalp: Variant = material.get_shader_parameter(&"scalp_hair")
	check(not hair.visible and scalp is float and is_equal_approx(scalp, 1.0),
			"a buzz cut hides the hair and paints the scalp")
	check(is_equal_approx(material.get_shader_parameter(&"male_pattern"), 1.0)
			and material.get_shader_parameter(&"body_masks_texture") != null
			and is_equal_approx(material.get_shader_parameter(&"pubic_hair"), 0.5),
			"the pubic hair follows its slider, in the man's pattern")
	var genitals: MeshInstance3D = model.get_node("Armature/Skeleton3D/HumanGenitals")
	check(genitals.visible and genitals.material_override == body.material_override,
			"a male body shows its genitals, in the body's own skin material")
	model.queue_free()


func _check_first_person() -> void:
	var model: Node3D = load("res://scenes/character/character_model.tscn").instantiate()
	root.add_child(model)
	var rig: CharacterAppearanceRig = model.get_node("AppearanceRig")
	var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
	var body: MeshInstance3D = skeleton.get_node("Mesh_0")
	var hair: MeshInstance3D = skeleton.get_node("HumanHair")
	var eyes: MeshInstance3D = skeleton.get_node("HumanEyes")
	var genitals: MeshInstance3D = skeleton.get_node("HumanGenitals")
	var appearance := CharacterAppearance.new()
	appearance.set_sex(&"male")
	rig.apply(appearance)
	rig.set_first_person(true)
	var fp: MeshInstance3D = skeleton.get_node_or_null("FirstPersonBody")
	check(fp != null and fp.visible and fp.mesh == body.mesh and fp.material_override == body.material_override
			and fp.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and fp.has_meta(&"no_dismember"),
			"first person shows the body again, without a shadow of its own, out of the dismemberment's reach")
	var shadows_only := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	check(body.cast_shadow == shadows_only and hair.cast_shadow == shadows_only and eyes.cast_shadow == shadows_only
			and genitals.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			"in first person the whole body and the head's parts only cast the shadow")
	var head := skeleton.find_bone(CharacterAppearanceRig.HEAD_BONE)
	var spine := skeleton.find_bone(&"mixamorig_Spine2")
	var head_scale := -1.0
	var spine_kept := false
	for b in fp.skin.get_bind_count():
		var bone := skeleton.find_bone(fp.skin.get_bind_name(b))
		if bone == head:
			head_scale = fp.skin.get_bind_pose(b).basis.get_scale().x / body.skin.get_bind_pose(b).basis.get_scale().x
		elif bone == spine:
			spine_kept = fp.skin.get_bind_pose(b).is_equal_approx(body.skin.get_bind_pose(b))
	check(is_equal_approx(head_scale, CharacterAppearanceRig.FOLDED_HEAD_SCALE) and spine_kept,
			"the first-person skin folds the head and leaves the rest of the body alone")
	var eye := rig.first_person_eye()
	var to_model := model.global_transform.affine_inverse() * skeleton.global_transform
	# The rest pose stands with the hips on the ground (the animations lift them): measured from
	# the head joint, at the top of the neck.
	var from_head := to_model * (skeleton.get_bone_global_rest(head) * eye) - to_model * skeleton.get_bone_global_rest(head).origin
	check(not is_nan(eye.x) and absf(from_head.x) < 0.01 and from_head.y > 0.02 and from_head.y < 0.15
			and from_head.z > 0.04 and from_head.z < 0.15,
			"the first-person eye sits between the eyes, above and ahead of the head joint (%s)" % from_head)
	var back := to_model.basis * (skeleton.get_bone_global_rest(head).basis * (rig.first_person_eye(-0.1) - eye))
	check(back.is_equal_approx(Vector3(0, 0, -0.1)), "the eye moves back along the face, into the head (%s)" % back)
	rig.set_first_person(false)
	var on := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	check(not fp.visible and body.cast_shadow == on and hair.cast_shadow == on and eyes.cast_shadow == on,
			"leaving first person gives the head back to the camera")
	model.queue_free()

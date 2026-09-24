extends SceneTree

## Checks the character appearance data against the baked human and the rig
## that applies it:
##   godot --headless --path . --script res://tests/character/test_character_appearance.gd

const BODY := "res://data/character/human/body.res"
const PROXIES := "res://data/character/human/proxies/%s.res"
## Styles every sex is offered; the rest are cut for one sex.
const SHARED_STYLES: Array[StringName] = [&"buzz", &"bald"]

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
	_check_rig()
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

	var skins_ok := true
	for id in AppearanceCatalog.SKINS:
		var skin: Dictionary = body.skins.get(id, {})
		skins_ok = skins_ok and skin.has("texture") and ResourceLoader.exists(skin.texture)
		skins_ok = skins_ok and skin.get("sex") in AppearanceCatalog.SKINS[id].sexes
	check(skins_ok, "every skin the catalog offers is baked for its sex")

	var shared := []
	for id in AppearanceCatalog.HAIR_STYLES:
		var sexes: Array = AppearanceCatalog.HAIR_STYLES[id].get("sexes", [])
		if sexes.size() != 1 and not id in SHARED_STYLES:
			shared.append(id)
	check(shared.is_empty(), "hair styles are cut for one sex, besides buzz and bald %s" % [shared])

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
	check(is_equal_approx(legacy.get_value(&"nose_size"), 1.0) and legacy.get_value(AppearanceCatalog.HAIR_STYLE) == &"textured",
			"loading clamps sliders and falls back from unknown choices")


func _check_shape(body: HumanBodyData) -> void:
	var morphable := body.mesh
	var shape := HumanShape.new(body)
	var live := shape.body_morphable()
	check(live.get_blend_shape_count() == body.names.size(), "the live body has one blend shape per morph")
	check(live.surface_get_array_len(0) == morphable.surface_get_array_len(0), "the live body keeps the base vertices")

	var hair: HumanProxyData = load(PROXIES % "hair_long01")
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

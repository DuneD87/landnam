extends SceneTree

## Checks the character appearance data against the baked human and the rig
## that applies it:
##   godot --headless --path . --script res://tests/character/test_character_appearance.gd

const PARTS := "res://data/character/human/%s.res"

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
	_check_catalog()
	_check_appearance()
	_check_parts()
	_check_rig()
	print("CHARACTER APPEARANCE TESTS: %d failures" % failures)
	quit(1 if failures else 0)


func _check_catalog() -> void:
	var body: HumanPartData = load(PARTS % "body")
	var missing := []
	for option in AppearanceCatalog.all_options():
		if not option.morph:
			continue
		var found := false
		for name in [option.morph, String(option.morph) + "@male"]:
			found = found or body.has_morph(name)
		if not found:
			missing.append(option.morph)
	for sex in AppearanceCatalog.SEXES.values():
		for morph in sex.get("morphs", {}):
			if not body.has_morph(morph):
				missing.append(morph)
	check(missing.is_empty(), "every morph the catalog uses is baked %s" % [missing])
	var parts: Array[StringName] = []
	for table in [AppearanceCatalog.HAIR_STYLES, AppearanceCatalog.EYEBROW_STYLES]:
		for entry in table.values():
			if entry.part != &"":
				parts.append(entry.part)
	for sex in AppearanceCatalog.SEXES.values():
		parts.append(sex.eyelashes)
	var broken := []
	for part in parts:
		if not load(PARTS % part) is HumanPartData:
			broken.append(part)
	check(broken.is_empty(), "every part the catalog names is baked %s" % [broken])
	var defaults_ok := true
	for option in AppearanceCatalog.all_options():
		if option.kind == AppearanceOption.Kind.SLIDER:
			defaults_ok = defaults_ok and option.default_value >= option.min_value and option.default_value <= option.max_value
		elif option.kind == AppearanceOption.Kind.CHOICE:
			for sex in AppearanceCatalog.SEXES:
				defaults_ok = defaults_ok and option.choice_index(option.default_for(sex)) >= 0
	check(defaults_ok, "slider and choice defaults are within their options")


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

	var appearance := CharacterAppearance.new()
	appearance.set_value(&"breast_size", 0.6)
	check(is_zero_approx(appearance.get_value(&"breast_size")), "a male body ignores the bust slider")
	appearance.set_sex(&"female")
	check(is_equal_approx(appearance.get_value(&"breast_size"), 0.6), "a female body uses it")
	check(appearance.get_value(AppearanceCatalog.HAIR_STYLE) == &"long01", "switching to female takes her default hair")
	appearance.set_value(&"nose_size", 0.4)
	appearance.reset()
	check(appearance.get_sex() == &"female" and is_zero_approx(appearance.get_value(&"nose_size")),
			"reset keeps the sex and clears the sliders")
	var legacy := CharacterAppearance.from_dict({"nose_size": 9.0, "unknown_trait": 1.0, "hair_style": "mohawk"})
	check(is_equal_approx(legacy.get_value(&"nose_size"), 1.0) and legacy.get_value(AppearanceCatalog.HAIR_STYLE) == &"short02",
			"loading clamps sliders and falls back from unknown choices")


func _check_parts() -> void:
	var body: HumanPartData = load(PARTS % "body")
	var morphable := body.morphable()
	check(morphable.get_blend_shape_count() == body.names.size(), "the live body has one blend shape per morph")
	check(morphable.surface_get_array_len(0) == body.mesh.surface_get_array_len(0), "the live body keeps the base vertices")
	var baked := body.baked({&"body_weight@male": 1.0, &"sex_female": 1.0})
	var arrays := baked.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var base: PackedVector3Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var moved := 0
	var finite := true
	for i in vertices.size():
		if vertices[i].distance_to(base[i]) > 1e-5:
			moved += 1
		finite = finite and vertices[i].is_finite() and normals[i].is_finite() and absf(normals[i].length() - 1.0) < 1e-3
	check(baked.get_blend_shape_count() == 0 and moved > 5000, "a baked body has the morphs in its vertices (%d moved)" % moved)
	check(finite, "baked positions and normals are finite and normals unit length")
	var eyes: HumanPartData = load(PARTS % "eyes")
	check(eyes.has_morph(&"eye_size") and eyes.has_morph(&"sex_female"), "the eyes follow the face morphs")

	var rig: HumanRigData = load("res://data/character/human/rig.tres")
	var skins_ok := true
	for sex in AppearanceCatalog.SEXES:
		var skin: Skin = rig.skins.get(sex)
		skins_ok = skins_ok and skin != null and skin.get_bind_count() == 65 and rig.bone_offsets[sex].size() == 65
	check(skins_ok, "each sex has a full skin and bone offsets")
	var female_hips: Vector3 = rig.bone_offsets[&"female"][&"mixamorig_Hips"]
	var male_hips: Vector3 = rig.bone_offsets[&"male"][&"mixamorig_Hips"]
	check(female_hips != male_hips, "the female hips sit elsewhere than the male ones")


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
	var data: HumanRigData = load("res://data/character/human/rig.tres")
	check(body.mesh.get_blend_shape_count() == 0 and body.material_override is ShaderMaterial, "gameplay rig bakes the body")
	check(body.skin == data.skins[&"female"] and eyes.skin == body.skin and hair.skin == body.skin,
			"every part uses the skin of the chosen sex")
	check(hair.visible and hair.mesh != null and eyes.visible, "the female default hair and the eyes are shown")
	var armature: Node3D = model.get_node("Armature")
	check(armature.basis.get_scale().x > 0.01 * 1.01, "height scales the armature")
	var material: ShaderMaterial = body.material_override
	check(is_zero_approx(float(material.get_shader_parameter(&"top_cover"))), "a female body goes topless")
	appearance.set_sex(&"male")
	appearance.set_value(AppearanceCatalog.HAIR_STYLE, &"bald")
	rig.apply(appearance)
	check(not hair.visible and body.skin == data.skins[&"male"], "switching to a bald male swaps skin and hides the hair")
	model.queue_free()

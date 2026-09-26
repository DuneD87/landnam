extends SceneTree

## Checks the body measurements and the armour fit (BodyMeasurements,
## ArmorFit, CharacterAppearanceRig.dress()):
##   godot --headless --path . --script res://tests/character/test_armor_fit.gd

const MODEL := "res://scenes/character/character_model.tscn"
const CHEST := "res://scenes/items/armor/leather_armor/leather_chest_equipable.tscn"
const PANTS := "res://scenes/items/armor/firstage_skin_set/firstage_skin_pants_equipable.tscn"
const HOODS := ["res://scenes/items/armor/leather_armor/leather_hood_equipable.tscn",
		"res://scenes/items/armor/firstage_skin_set/firstage_skin_hood_equipable.tscn"]

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
	var model: Node3D = load(MODEL).instantiate()
	root.add_child(model)
	var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
	var rig: CharacterAppearanceRig = model.get_node("AppearanceRig")
	_check_reference(skeleton)
	_check_identity(skeleton)
	_check_measurements(rig)
	_check_clearance(rig, skeleton)
	await _check_dress(rig, skeleton)
	await _check_hair(rig, skeleton)
	model.free()
	print("ARMOR FIT TESTS: %d failures" % failures)
	quit(1 if failures else 0)


func _body(values: Dictionary) -> CharacterAppearance:
	var appearance := CharacterAppearance.new()
	appearance.set_sex(values.get(&"sex", &"male"))
	for id in values:
		if id != &"sex":
			appearance.set_value(id, values[id])
	return appearance


func _check_reference(skeleton: Skeleton3D) -> void:
	var reference: BodyMeasurements = load(BodyMeasurements.REFERENCE)
	check(reference != null and reference.bone_names.size() == skeleton.get_bone_count(),
			"the reference body is baked for the player skeleton")
	var missing := []
	for name in ["Hips", "Spine", "Spine1", "Spine2", "Head", "LeftArm", "RightForeArm", "LeftUpLeg", "RightLeg", "LeftFoot"]:
		if not reference.has_bone(skeleton.find_bone("mixamorig_" + name)):
			missing.append(name)
	check(missing.is_empty(), "the reference measures torso, head and limbs %s" % [missing])
	var height: float = reference.summary.get(&"height", 0.0)
	check(height > 1.7 and height < 2.1, "the scan is %.2f m tall" % height)


## Fitting a body onto itself leaves the armour where it was.
func _check_identity(skeleton: Skeleton3D) -> void:
	var fit := ArmorFit.new()
	fit.reference = load(BodyMeasurements.REFERENCE)
	fit.body = fit.reference
	fit.reference_globals = BodyMeasurements.rest_globals(skeleton)
	fit.body_globals = fit.reference_globals
	var item: MeshInstance3D = load(CHEST).instantiate()
	var surfaces := ArmorFit.source(item.mesh)
	var before: PackedVector3Array = surfaces[0].arrays[Mesh.ARRAY_VERTEX].duplicate()
	fit.fit(surfaces, _binds(item.skin), BodyMeasurements.bind_bones(item.skin, skeleton))
	var after: PackedVector3Array = surfaces[0].arrays[Mesh.ARRAY_VERTEX]
	var moved := 0.0
	for i in before.size():
		moved = maxf(moved, before[i].distance_to(after[i]))
	check(moved < 1e-4, "fitting the scan onto itself moves no vertex (%.6f)" % moved)
	var mesh := ArmorFit.build(surfaces, item.mesh.resource_name)
	check(mesh.get_surface_count() == item.mesh.get_surface_count()
			and mesh.surface_get_material(0) == item.mesh.surface_get_material(0),
			"the fitted mesh keeps the surfaces and materials")
	var lods: int = RenderingServer.mesh_get_surface(mesh.get_rid(), 0).get("lods", []).size()
	var source_lods: int = RenderingServer.mesh_get_surface(item.mesh.get_rid(), 0).get("lods", []).size()
	check(lods == source_lods, "the fitted mesh keeps its LODs (%d of %d)" % [lods, source_lods])
	item.free()


func _check_measurements(rig: CharacterAppearanceRig) -> void:
	var sizes := {}
	for id in [&"male", &"female", &"heavy", &"muscular", &"thin", &"tall"]:
		var values := {}
		match id:
			&"female": values = {&"sex": &"female"}
			&"heavy": values = {&"body_weight": 1.0}
			&"muscular": values = {&"muscle": 1.0}
			&"thin": values = {&"body_weight": -1.0, &"muscle": -1.0}
			&"tall": values = {&"height": 1.0}
		rig.apply(_body(values))
		sizes[id] = rig.measurements().summary
	var male: Dictionary = sizes[&"male"]
	print("  default male: ", _format(male))
	check(male.height > 1.6 and male.height < 2.0, "the default man is %.2f m tall" % male.height)
	check(male.chest > 0.8 and male.chest < 1.2, "his chest is %.0f cm" % (male.chest * 100.0))
	check(male.waist < male.chest, "his waist (%.0f cm) is under his chest" % (male.waist * 100.0))
	check(sizes[&"female"].height < male.height, "the default woman is shorter")
	check(sizes[&"female"].shoulders < male.shoulders, "and narrower in the shoulders")
	check(sizes[&"heavy"].waist > male.waist + 0.05, "weight widens the waist (%.0f -> %.0f cm)"
			% [male.waist * 100.0, sizes[&"heavy"].waist * 100.0])
	check(sizes[&"muscular"].upper_arm > sizes[&"thin"].upper_arm, "muscle thickens the arms")
	check(sizes[&"tall"].height > male.height + 0.05, "height makes him taller (%.2f m)" % sizes[&"tall"].height)
	check(sizes[&"tall"].leg > male.leg, "and his legs longer")


## The fitted armour stays out of the body; as it was made, it does not.
func _check_clearance(rig: CharacterAppearanceRig, skeleton: Skeleton3D) -> void:
	for values in [{&"muscle": 1.0, &"chest_depth": 1.0}, {&"sex": &"female", &"breast_size": 1.0}, {&"body_weight": 1.0}]:
		rig.apply(_body(values))
		var context := rig._context()
		for path in [CHEST, PANTS]:
			var item: MeshInstance3D = load(path).instantiate()
			var bones := BodyMeasurements.bind_bones(item.skin, skeleton)
			var surfaces := ArmorFit.source(item.mesh)
			var unfitted := _inside(context, surfaces[0].arrays, item.skin, skeleton)
			context.fit(surfaces, _binds(item.skin), bones)
			var fitted := _inside(context, surfaces[0].arrays, item.skin, skeleton)
			check(fitted <= 0.002 and fitted <= unfitted, "%s on %s: %.1f%% of it inside the body (%.1f%% unfitted)"
					% [path.get_file().get_basename(), values, fitted * 100.0, unfitted * 100.0])
			item.free()


## Share of the vertices inside the body at rest.
func _inside(context: ArmorFit, arrays: Array, skin: Skin, skeleton: Skeleton3D) -> float:
	var binds := BodyMeasurements.bind_transforms(skin, skeleton, context.body_globals)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / vertices.size()
	var inside := 0
	for i in vertices.size():
		var p := Vector3.ZERO
		for k in range(i * per, i * per + per):
			p += binds[bones[k]] * vertices[i] * weights[k]
		var nearest := context.surface.nearest(p)
		if nearest >= 0 and (p - context.surface.positions[nearest]).dot(context.surface.normals[nearest]) < 0.0:
			inside += 1
	return float(inside) / vertices.size()


func _check_dress(rig: CharacterAppearanceRig, skeleton: Skeleton3D) -> void:
	rig.apply(_body({}))
	var item: MeshInstance3D = load(CHEST).instantiate()
	var source := item.mesh
	skeleton.add_child(item)
	rig.dress(item)
	check(rig.is_dressing() and not item.visible, "a piece stays hidden while it is fitted")
	await _dressed(rig)
	check(item.visible and item.mesh != source, "then it shows, fitted")
	var first := item.mesh
	rig.apply(_body({&"body_weight": 1.0}))
	await _dressed(rig)
	check(item.visible and item.mesh != first and item.mesh != source, "a new body fits it again")
	rig.apply(_body({&"body_weight": 1.0}))
	check(not rig.is_dressing(), "the same body does not")
	item.free()


## Under a hood the hair stays inside it, the hair it does not cover stays
## where it was, and taking the hood off lets it all out.
func _check_hair(rig: CharacterAppearanceRig, skeleton: Skeleton3D) -> void:
	var hair: MeshInstance3D = rig._slots[&"hair"].instance
	for hood_path in HOODS:
		for style in [&"afro_puffs", &"layered", &"long_straight"]:
			rig.apply(_body({&"sex": &"female", &"hair_style": style}))
			var loose: ArrayMesh = rig._slots[&"hair"].mesh
			var hood: MeshInstance3D = load(hood_path).instantiate()
			skeleton.add_child(hood)
			rig.dress(hood, true)
			await _dressed(rig)
			var context := rig._context()
			var fitted: Dictionary = rig._fitted[hood.get_meta(&"armor_source")]
			var head := skeleton.find_bone(CharacterAppearanceRig.HEAD_BONE)
			var span := context.body.spans[head]
			var middle := context.body.section_at(head, 0.5)
			var centre := context.body_globals[head] * Vector3((middle[0] + middle[1]) * 0.5,
					(span.x + span.y) * 0.5, (middle[2] + middle[3]) * 0.5)
			var tuck := HairTuck.new(fitted.points, centre, context.body_globals[head].basis,
					context.body_globals, context.units)
			var before := _rest_points(rig, skeleton, loose, context)
			var after := _rest_points(rig, skeleton, hair.mesh, context)
			var poking_before := 0
			var poking_after := 0
			var covered := 0
			var moved_uncovered := 0
			for i in before.size():
				var cover := tuck.coverage_at(before[i])
				if cover >= 0.99:
					covered += 1
					if tuck.beyond(before[i]) > 0.0:
						poking_before += 1
					if tuck.beyond(after[i]) > 0.0:
						poking_after += 1
				elif cover <= 0.0 and before[i].distance_to(after[i]) > 1e-3:
					moved_uncovered += 1
			var name := "%s, %s" % [hood_path.get_file().get_basename(), style]
			check(poking_after <= covered / 200, "%s: %d hair vertices out of the hood (%d loose)"
					% [name, poking_after, poking_before])
			check(moved_uncovered == 0, "%s: the hair it does not cover stays put" % name)
			rig.undress(hood)
			hood.free()
			await _dressed(rig)
			check(hair.mesh == loose, "%s: without the hood the hair is loose again" % name)


func _rest_points(rig: CharacterAppearanceRig, skeleton: Skeleton3D, mesh: ArrayMesh, context: ArmorFit) -> PackedVector3Array:
	var binds := BodyMeasurements.bind_transforms(rig._data.skin, skeleton, context.body_globals)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / vertices.size()
	var points := PackedVector3Array()
	for i in vertices.size():
		var p := Vector3.ZERO
		for k in range(i * per, i * per + per):
			p += binds[bones[k]] * vertices[i] * weights[k]
		points.append(p)
	return points


func _dressed(rig: CharacterAppearanceRig) -> void:
	var frames := 0
	while rig.is_dressing() and frames < 600:
		await process_frame
		frames += 1


func _binds(skin: Skin) -> Array[Transform3D]:
	var binds: Array[Transform3D] = []
	for b in skin.get_bind_count():
		binds.append(skin.get_bind_pose(b))
	return binds


func _format(summary: Dictionary) -> String:
	var parts := []
	for name in summary:
		parts.append("%s %.0f" % [name, summary[name] * 100.0])
	return ", ".join(parts)

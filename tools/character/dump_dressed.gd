extends SceneTree

## Dresses the character model as the game does (CharacterAppearanceRig,
## ArmorFit), poses it at a moment of an animation and writes every mesh the
## camera would see, bent by the skeleton, for
## tools/character/blender/render_dressed.py. A look at armour on a body
## without opening a window.
##
##   godot --headless --path . --script res://tools/character/dump_dressed.gd -- <out.json>
##       [--appearance=<main_save_player.json>] [--armor=<scene>,<scene>...]
##       [--anim=running|none] [--time=0.3] [--play] [--frames=3] [--still]
##
## <out.json> lists the meshes (model space: Y up, +Z forward, metres) and
## their albedo; the vertex data goes in <out>.bin. It is taken after
## --frames frames, the animation held at --time or, with --play, playing on
## from it: what swings (SkirtSwing) needs some to hang or to move, best
## with godot's --fixed-fps 60. --still leaves it hanging as it was fitted.

const MODEL := "res://scenes/character/character_model.tscn"


## Gives up (and quits) after this many seconds of real time (with
## --fixed-fps the game's own runs far ahead), so an error does not leave it
## hanging.
const TIMEOUT := 120.0


func _initialize() -> void:
	var start := Time.get_ticks_msec()
	process_frame.connect(func() -> void:
		if Time.get_ticks_msec() - start > TIMEOUT * 1000.0:
			push_error("dump_dressed: timed out")
			quit(1))
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var look := CharacterAppearance.new()
	var armor: PackedStringArray = []
	var anim_name := ""
	var time := 0.0
	var play := false
	var frames := 3
	var still := false
	for arg in args.slice(1):
		if arg.begins_with("--appearance="):
			var save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(arg.get_slice("=", 1)))
			look = CharacterAppearance.from_dict(save.player.data.character.appearance)
		elif arg.begins_with("--armor="):
			armor = arg.get_slice("=", 1).split(",")
		elif arg.begins_with("--anim="):
			anim_name = arg.get_slice("=", 1)
		elif arg.begins_with("--time="):
			time = float(arg.get_slice("=", 1))
		elif arg == "--play":
			play = true
		elif arg.begins_with("--frames="):
			frames = int(arg.get_slice("=", 1))
		elif arg == "--still":
			still = true
	var model: Node3D = load(MODEL).instantiate()
	root.add_child(model)
	var rig: CharacterAppearanceRig = model.get_node("AppearanceRig")
	var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
	rig.apply(look)
	for path in armor:
		var item: Node = load(path).instantiate()
		skeleton.add_child(item)
		rig.dress(item, path.contains("hood") or path.contains("helmet"))
	while rig.is_dressing():
		await process_frame
	if still:
		for child in skeleton.get_children():
			if child is SkirtSwing:
				child.active = false
	var player: AnimationPlayer = model.get_node("AnimationPlayer")
	if anim_name == "none":
		# The skeleton's rest: the pose the armour was fitted in.
		player.stop()
		player.active = false
		skeleton.reset_bone_poses()
	elif anim_name != "":
		player.play(anim_name)
		player.seek(time, true)
		if not play:
			player.speed_scale = 0.0
	# The poses as the skin sees them: with the modifiers (the body's joints,
	# BodyProportions), which only hold while the skeleton updates.
	var poses: Array[Transform3D] = []
	skeleton.skeleton_updated.connect(func() -> void:
		poses.clear()
		for bone in skeleton.get_bone_count():
			poses.append(skeleton.get_bone_global_pose(bone)))
	for i in maxi(frames, 3):
		await process_frame
	var meshes := []
	var data := PackedByteArray()
	var to_model := model.global_transform.affine_inverse()
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if not instance.is_visible_in_tree() or instance.mesh == null \
				or instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var mesh := instance.mesh
		var binds := _binds(instance, skeleton, poses)
		var transform := to_model * (skeleton.global_transform if not binds.is_empty() else instance.global_transform)
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if not binds.is_empty():
				vertices = _skinned(vertices, arrays, binds)
			var positions := PackedFloat32Array()
			for p in vertices:
				var q: Vector3 = transform * p
				positions.append_array([q.x, q.y, q.z])
			var uvs := PackedFloat32Array()
			if arrays[Mesh.ARRAY_TEX_UV] != null:
				var coords: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				for uv in coords:
					uvs.append_array([uv.x, uv.y])
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var entry := {name = "%s_%d" % [instance.name, s], vertices = positions.size() / 3,
					indices = indices.size(), offset = data.size(), uv = not uvs.is_empty()}
			data.append_array(positions.to_byte_array())
			data.append_array(uvs.to_byte_array())
			data.append_array(indices.to_byte_array())
			_albedo(instance.get_active_material(s), entry)
			meshes.append(entry)
	var file := FileAccess.open(out.get_basename() + ".bin", FileAccess.WRITE)
	file.store_buffer(data)
	file.close()
	file = FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify({meshes = meshes, bin = out.get_basename().get_file() + ".bin"}))
	file.close()
	print("Dressed model written to %s (%d meshes)" % [out, meshes.size()])
	model.free()
	quit()


## Per bind of the instance's skin, what takes a vertex to skeleton space in
## the current pose; empty if it is not skinned.
static func _binds(instance: MeshInstance3D, skeleton: Skeleton3D, poses: Array[Transform3D]) -> Array[Transform3D]:
	var binds: Array[Transform3D] = []
	if instance.skin == null:
		return binds
	for b in instance.skin.get_bind_count():
		var name := instance.skin.get_bind_name(b)
		var bone := skeleton.find_bone(name) if name != &"" else instance.skin.get_bind_bone(b)
		binds.append(poses[bone] * instance.skin.get_bind_pose(b) if bone >= 0 else Transform3D.IDENTITY)
	return binds


## The vertices bent by the skeleton (skeleton space), as the GPU skins them.
static func _skinned(vertices: PackedVector3Array, arrays: Array, binds: Array[Transform3D]) -> PackedVector3Array:
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / vertices.size()
	var out := PackedVector3Array()
	out.resize(vertices.size())
	for i in vertices.size():
		var p := Vector3.ZERO
		for k in range(i * per, i * per + per):
			if weights[k] > 0.0:
				p += binds[bones[k]] * vertices[i] * weights[k]
		out[i] = p
	return out


## The material's albedo texture (an absolute path) or colour.
static func _albedo(material: Material, entry: Dictionary) -> void:
	var texture: Texture2D = null
	var color := Color(0.8, 0.65, 0.55)
	if material is BaseMaterial3D:
		texture = material.albedo_texture
		color = material.albedo_color
	elif material is ShaderMaterial:
		for name in [&"albedo_texture", &"texture_albedo", &"albedo"]:
			var value = material.get_shader_parameter(name)
			if value is Texture2D:
				texture = value
			elif value is Color:
				color = value
	if texture != null and texture.resource_path.begins_with("res://"):
		entry.texture = ProjectSettings.globalize_path(texture.resource_path)
	entry.color = [color.r, color.g, color.b]

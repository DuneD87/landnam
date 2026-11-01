extends SceneTree

## Writes an animal of the game's fauna, at rest, for
## tools/character/blender/build_fur_armor.py (its pelts worn with their
## heads), which cannot read Godot's scenes: every mesh skinned to its
## skeleton (or held by a BoneAttachment3D, as a deer's antlers) with its
## triangles, UVs, the bone each vertex follows (names and weights) and the
## path of its material, and every bone's joint. Positions in metres, in
## the scene's space (Y up). A material that only lives in the scene is
## saved next to the output's materials, in MATERIALS, so the garment can
## use it.
##
##   godot --headless --path . --script res://tools/character/export_animal.gd -- <scene> <output.json>

const MATERIALS := "res://models/equipable/stone_age/pelts/"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Expected <scene> <output.json>")
		quit(1)
		return
	var scene: PackedScene = load(args[0])
	var root: Node = scene.instantiate()
	var skeleton := _find_skeleton(root)
	if skeleton == null:
		push_error("No skeleton in " + args[0])
		root.free()
		quit(1)
		return
	var name := args[1].get_file().get_basename()
	var to_world := _global(skeleton)
	var rests := BodyMeasurements.rest_globals(skeleton)
	var bones := []
	for b in skeleton.get_bone_count():
		var joint := to_world * rests[b].origin
		bones.append({name = skeleton.get_bone_name(b), parent = skeleton.get_bone_parent(b),
				joint = [joint.x, joint.y, joint.z]})
	var meshes := []
	for instance: MeshInstance3D in _meshes(root):
		meshes.append(_mesh(instance, skeleton, rests, to_world, name, meshes.size()))
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify({bones = bones, meshes = meshes}))
	file.close()
	for mesh: Dictionary in meshes:
		print("%s: %d vertices, %d triangles, %s" % [mesh.name, mesh.positions.size() / 3, mesh.indices.size() / 3,
				", ".join(mesh.materials)])
	print("%d bones written to %s" % [bones.size(), args[1]])
	root.free()
	quit()


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


## A node's transform from the scene's root, without the tree (it is not in one).
static func _global(node: Node3D) -> Transform3D:
	var out := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		out = (parent as Node3D).transform * out
		parent = parent.get_parent()
	return out


## The mesh at rest: skinned, each vertex where its bones' rests put it;
## held by a BoneAttachment3D, where that bone's rest puts it.
func _mesh(instance: MeshInstance3D, skeleton: Skeleton3D, rests: Array[Transform3D], to_world: Transform3D,
		animal: String, index: int) -> Dictionary:
	var positions := []
	var uvs := []
	var indices := []
	var influences := []
	var weights := []
	var materials := []
	var surface_of := []
	var attached := instance.get_parent() as BoneAttachment3D
	var held := -1
	if attached != null:
		held = skeleton.find_bone(attached.bone_name)
	var binds: Array[Transform3D] = []
	var bind_bones := PackedInt32Array()
	if instance.skin != null:
		for b in instance.skin.get_bind_count():
			var bone := instance.skin.get_bind_bone(b)
			if bone < 0:
				bone = skeleton.find_bone(instance.skin.get_bind_name(b))
			bind_bones.append(bone)
			binds.append(rests[bone] * instance.skin.get_bind_pose(b))
	for s in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var surface_uvs = arrays[Mesh.ARRAY_TEX_UV]
		var bones = arrays[Mesh.ARRAY_BONES]
		var vertex_weights = arrays[Mesh.ARRAY_WEIGHTS]
		var first := positions.size() / 3
		var per := 0 if bones == null else (bones as PackedInt32Array).size() / vertices.size()
		for i in vertices.size():
			var at := Vector3.ZERO
			var vertex_bones := []
			var vertex_weights_out := []
			if held >= 0:
				at = to_world * rests[held] * (_global(attached).affine_inverse() * _global(instance)) * vertices[i]
				vertex_bones = [held]
				vertex_weights_out = [1.0]
			elif per > 0 and not binds.is_empty():
				for k in range(i * per, i * per + per):
					var w: float = vertex_weights[k]
					if w <= 0.0:
						continue
					var bind: int = bones[k]
					at += (binds[bind] * vertices[i]) * w
					vertex_bones.append(bind_bones[bind])
					vertex_weights_out.append(w)
				at = to_world * at
			else:
				at = _global(instance) * vertices[i]
			positions.append_array([at.x, at.y, at.z])
			influences.append(vertex_bones)
			weights.append(vertex_weights_out)
			var uv: Vector2 = surface_uvs[i] if surface_uvs != null else Vector2.ZERO
			uvs.append_array([uv.x, uv.y])
		var surface_indices = arrays[Mesh.ARRAY_INDEX]
		if surface_indices == null:
			surface_indices = range(vertices.size())
		for k in surface_indices:
			indices.append(first + k)
		for t in surface_indices.size() / 3:
			surface_of.append(s)
		materials.append(_material_path(instance.get_active_material(s), animal, index, s))
	return {name = String(instance.name), positions = positions, uvs = uvs, indices = indices,
			influences = influences, weights = weights, surfaces = surface_of, materials = materials}


## Where a material is, saving it to MATERIALS if it only lives in a scene.
static func _material_path(material: Material, animal: String, mesh: int, surface: int) -> String:
	if material == null:
		return ""
	if material.resource_path != "" and not material.resource_path.contains("::"):
		return material.resource_path
	DirAccess.make_dir_recursive_absolute(MATERIALS)
	var path := MATERIALS + "%s_%d_%d.tres" % [animal, mesh, surface]
	if ResourceSaver.save(material, path) != OK:
		push_error("Could not save " + path)
	return path

extends SceneTree

## Hornea el modelo con esqueleto de un pack (un pez de WildMesh) como malla estática: la pose de
## reposo, en metros, girada --yaw grados (los del pack miran a +Z; los peces de AmbientFish nadan
## hacia -Z) y centrada en su caja. Sin huesos ni pesos: lo anima un shader (pack_fish.gdshader),
## que para un banco de peces cuesta mucho menos que un esqueleto por pez. Cada superficie conserva
## sus UV; los materiales los pone FishSpecies.
##   godot --headless --path . --script res://tools/fauna/bake_static_mesh.gd -- \
##       --source=res://models/animals/fish/tuna.fbx --out=res://models/animals/fish/tuna_mesh.res [--yaw=180]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	if not args.has("source") or not args.has("out"):
		push_error("Faltan --source y --out")
		quit(1)
		return
	var scene: Node3D = (load(args.source) as PackedScene).instantiate()
	root.add_child(scene)
	var turn := Basis(Vector3.UP, deg_to_rad(float(args.get("yaw", "180"))))
	var to_root := scene.global_transform.affine_inverse()
	var surfaces: Array = []
	var box := AABB()
	var first := true
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var skeleton := instance.get_node_or_null(instance.skeleton) as Skeleton3D
		for s in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			var binds := _bind_transforms(instance, skeleton)
			var stride: int = bones.size() / vertices.size() if bones != null and not binds.is_empty() else 0
			var turned := Transform3D(turn, Vector3.ZERO) * to_root
			for i in vertices.size():
				var point := Vector3.ZERO
				var normal := Vector3.ZERO
				var tangent := Vector3.ZERO
				var raw_tangent := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2]) \
					if not tangents.is_empty() else Vector3.ZERO
				if stride > 0:
					# Piel en la pose de reposo: lo que pone cada hueso que la mueve, por su peso.
					for j in stride:
						var w: float = weights[i * stride + j]
						if w > 0.0:
							var bind: Transform3D = binds[bones[i * stride + j]]
							point += (bind * vertices[i]) * w
							normal += (bind.basis * normals[i]) * w
							tangent += (bind.basis * raw_tangent) * w
				else:
					point = instance.global_transform * vertices[i]
					normal = instance.global_transform.basis * normals[i]
					tangent = instance.global_transform.basis * raw_tangent
				vertices[i] = turned * point
				normals[i] = (turned.basis * normal).normalized()
				if not tangents.is_empty():
					var t := (turned.basis * tangent).normalized()
					tangents[i * 4] = t.x
					tangents[i * 4 + 1] = t.y
					tangents[i * 4 + 2] = t.z
				box = AABB(vertices[i], Vector3.ZERO) if first else box.expand(vertices[i])
				first = false
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			if not tangents.is_empty():
				arrays[Mesh.ARRAY_TANGENT] = tangents
			arrays[Mesh.ARRAY_BONES] = null
			arrays[Mesh.ARRAY_WEIGHTS] = null
			surfaces.append(arrays)
	# Centrada en su caja: el pez gira y choca alrededor de su mitad.
	var center := box.get_center()
	var mesh := ArrayMesh.new()
	for arrays in surfaces:
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			vertices[i] -= center
		arrays[Mesh.ARRAY_VERTEX] = vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var err := ResourceSaver.save(mesh, args.out, ResourceSaver.FLAG_COMPRESS)
	print("%s → %s: %d superficies, caja %s (%s)" % [args.source, args.out, mesh.get_surface_count(),
		AABB(box.position - center, box.size), error_string(err)])
	quit(0 if err == OK else 1)


## Para cada bind de la piel, de la malla en reposo al espacio del mundo.
func _bind_transforms(instance: MeshInstance3D, skeleton: Skeleton3D) -> Array:
	var skin := instance.skin
	if skin == null or skeleton == null:
		return []
	var result := []
	for i in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(i))
		result.append(skeleton.global_transform * skeleton.get_bone_global_rest(bone) * skin.get_bind_pose(i))
	return result

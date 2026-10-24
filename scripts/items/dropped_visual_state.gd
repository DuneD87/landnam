extends RefCounted

## Mallas pequeñas de leña y piedras: solo geometría, transformaciones y materiales, sin scripts.
## Los arrays se codifican como variantes sin objetos para conservar sus tipos y precisión en JSON.
static func encode(value: Variant) -> String:
	return Marshalls.raw_to_base64(var_to_bytes(value))


static func decode(value: String) -> Variant:
	return bytes_to_var(Marshalls.base64_to_raw(value))


static func capture(root: Node3D) -> Array:
	var result := []
	if root == null:
		return result
	var frame := (root.get_parent() as Node3D).global_transform.affine_inverse()
	for node in [root] + root.find_children("*", "MeshInstance3D", true, false):
		var visual := node as MeshInstance3D
		if visual == null or visual.mesh == null:
			continue
		var surfaces := []
		for i in visual.mesh.get_surface_count():
			surfaces.append({"arrays": encode(visual.mesh.surface_get_arrays(i)),
				"primitive": visual.mesh.surface_get_primitive_type(i),
				"material": _capture_material(visual.get_active_material(i))})
		result.append({"transform": encode(frame * visual.global_transform),
			"surfaces": surfaces, "rock_offset": encode(visual.get_instance_shader_parameter(&"rock_offset"))})
	return result


static func restore(saved: Array) -> Node3D:
	var root := Node3D.new()
	for entry: Dictionary in saved:
		var mesh := ArrayMesh.new()
		for surface: Dictionary in entry.get("surfaces", []):
			var arrays: Variant = decode(surface.get("arrays", ""))
			if not arrays is Array or arrays.size() != Mesh.ARRAY_MAX \
					or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				continue
			mesh.add_surface_from_arrays(int(surface.get("primitive", Mesh.PRIMITIVE_TRIANGLES)), arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _restore_material(surface.get("material", {})))
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		var xform: Variant = decode(entry.get("transform", ""))
		if xform is Transform3D:
			visual.transform = xform
		var offset: Variant = decode(entry.get("rock_offset", ""))
		if offset is Vector3:
			visual.set_instance_shader_parameter(&"rock_offset", offset)
		root.add_child(visual)
	return root


static func _capture_material(material: Material) -> Dictionary:
	if material == null:
		return {}
	if material.resource_path != "":
		return {"path": material.resource_path}
	if material == TreeFelling._cut_material:
		return {"tree_cut": true}
	if material is StandardMaterial3D:
		return {"albedo": encode(material.albedo_color), "roughness": material.roughness}
	return {}


static func _restore_material(saved: Dictionary) -> Material:
	if saved.has("path") and ResourceLoader.exists(saved.path):
		return load(saved.path) as Material
	if saved.get("tree_cut", false):
		return TreeFelling.cut_material()
	if saved.has("albedo"):
		var material := StandardMaterial3D.new()
		material.albedo_color = decode(saved.albedo)
		material.roughness = float(saved.get("roughness", 1.0))
		return material
	return null

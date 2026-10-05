extends SceneTree

const WATER_PASS := preload("res://scripts/water/underwater_render_pass.gd")
var failures := 0


func _initialize() -> void:
	var pass_data := WATER_PASS.new()
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/liquid/underwater.gdshader")
	var centers := PackedVector4Array()
	var axes_x := PackedVector4Array()
	var axes_y := PackedVector4Array()
	var axes_z := PackedVector4Array()
	for i in 128:
		centers.append(Vector4(i * 10.0, 0.0, 0.0, 0.0))
		axes_x.append(Vector4(1.0, 0.0, 0.0, 2.0))
		axes_y.append(Vector4(0.0, 1.0, 0.0, 2.0))
		axes_z.append(Vector4(0.0, 0.0, 1.0, 2.0))
	material.set_shader_parameter("interior_center", centers)
	material.set_shader_parameter("interior_axis_x", axes_x)
	material.set_shader_parameter("interior_axis_y", axes_y)
	material.set_shader_parameter("interior_axis_z", axes_z)
	material.set_shader_parameter("storm_body_ids", PackedInt32Array([9, 8, 7, 6, 5, 4, 3, 2]))
	for active in [0, 1, 2, 128, 0]:
		material.set_shader_parameter("interior_count", active)
		pass_data.update_material(material)
		var bytes: PackedByteArray = pass_data._snapshot
		_check(bytes.size() == int(pass_data.layout.slots) * 16, "Snapshot size with %d interiors" % active)
		for index in active:
			_check(pass_data._inside_interior(bytes, Vector3(index * 10.0, 0.0, 0.0)), "Active interior %d/%d" % [index, active])
		_check(not pass_data._inside_interior(bytes, Vector3(0.0, 5.0, 0.0)), "Outside active boxes")
		if active < 128:
			_check(not pass_data._inside_interior(bytes, Vector3(active * 10.0, 0.0, 0.0)), "Inactive box excluded")
			for param in ["interior_center", "interior_axis_x", "interior_axis_y", "interior_axis_z"]:
				var offset: int = (int(pass_data._slots[param]) + active) * 16
				_check(bytes.slice(offset, offset + 16) == PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), "Unused %s cleared" % param)
		_check(bytes.decode_s32(int(pass_data._slots.storm_body_ids) * 16 + 7 * 16) == 2, "Other arrays retained")
	pass_data.update_material(null)
	_check(pass_data._snapshot.decode_float(12 * 16) == 0.0, "Null material disables water")
	print("UNDERWATER_SNAPSHOT_RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)

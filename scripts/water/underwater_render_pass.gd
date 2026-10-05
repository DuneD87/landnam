@tool
extends RefCounted
class_name UnderwaterRenderPass

## Owns the small wave cache consumed by the fused atmosphere/water pass.
## The scene depth is read-only throughout. Material data is captured on the main
## thread; only immutable snapshots cross into the rendering thread.
const LAYOUT_PATH := "res://data/resources/underwater_layout.json"
var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
var _mutex := Mutex.new()
var _snapshot := PackedByteArray()
var _textures: Array[Texture2D] = []
var _rd: RenderingDevice
var _prepare_shader: RID
var _prepare_pipeline: RID
var _linear: RID
var _nearest: RID
var _fallback: RID
var _field_sampler: RID
var _detail_sampler: RID
var _views: Array[Dictionary] = []
var _slots := {}

func _init() -> void:
	for entry in layout.uniforms:
		if entry.has("slot"):
			_slots[entry.name] = int(entry.slot)


func update_material(material: ShaderMaterial) -> void:
	var bytes := PackedByteArray()
	bytes.resize(int(layout.slots) * 16)
	var textures: Array[Texture2D] = []
	bytes.encode_float(12 * 16, 1.0 if material != null else 0.0)
	for entry in layout.uniforms:
		var value: Variant = null
		if material != null:
			value = material.get_shader_parameter(entry.name)
			if value == null:
				value = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), entry.name)
		if entry.type == "sampler2D":
			textures.append(value as Texture2D)
			continue
		if value == null:
			continue
		var count := int(entry.count)
		# Los consumidores solo leen los interiores activos. El resto del buffer ya
		# está a cero: no copiar las 128 plazas de cada array en tierra firme.
		if count > 1 and String(entry.name).begins_with("interior_"):
			count = mini(count, clampi(bytes.decode_s32(int(_slots.interior_count) * 16), 0, 128))
		for index in count:
			var item: Variant = value
			if int(entry.count) > 1:
				if index >= value.size():
					break
				item = value[index]
			var offset := (int(entry.slot) + index) * 16
			match String(entry.type):
				"int": bytes.encode_s32(offset, int(item))
				"bool": bytes.encode_float(offset, 1.0 if item else 0.0)
				"float": bytes.encode_float(offset, float(item))
				"vec2":
					bytes.encode_float(offset, item.x)
					bytes.encode_float(offset + 4, item.y)
				"vec3": _put_vec4(bytes, offset, Vector4(item.x, item.y, item.z, 0.0))
				"vec4":
					if item is Color:
						var color: Color = item.srgb_to_linear() if entry.color else item
						_put_vec4(bytes, offset, Vector4(color.r, color.g, color.b, color.a))
					else:
						_put_vec4(bytes, offset, item)
	_mutex.lock()
	_snapshot = bytes
	_textures = textures
	_mutex.unlock()


static func _put_vec4(bytes: PackedByteArray, offset: int, v: Vector4) -> void:
	for component in 4:
		bytes.encode_float(offset + component * 4, v[component])


static func _uniform(type: int, binding: int, ids: Array[RID]) -> RDUniform:
	var result := RDUniform.new()
	result.uniform_type = type
	result.binding = binding
	for id in ids:
		result.add_id(id)
	return result


func _shader(path: String) -> RID:
	var imported := load(path) as RDShaderFile
	if imported != null:
		var compiled := imported.get_spirv()
		if compiled.compile_error_compute.is_empty() and not compiled.bytecode_compute.is_empty():
			return _rd.shader_create_from_spirv(compiled)
	# Source fallback also works before the editor has imported new compute assets.
	var source := FileAccess.get_file_as_string(path).replace("#[compute]", "")
	source = source.replace('#include "underwater_shared.glslinc"',
		FileAccess.get_file_as_string("res://shaders/liquid/underwater_shared.glslinc"))
	var shader_source := RDShaderSource.new()
	shader_source.source_compute = source
	var spirv := _rd.shader_compile_spirv_from_source(shader_source)
	if not spirv.compile_error_compute.is_empty():
		push_error("Underwater compute: " + spirv.compile_error_compute)
		return RID()
	return _rd.shader_create_from_spirv(spirv)


func _initialize(device: RenderingDevice) -> bool:
	if _rd != null:
		return _prepare_pipeline.is_valid()
	_rd = device
	_prepare_shader = _shader("res://shaders/liquid/underwater_surface_cache.glsl")
	if not _prepare_shader.is_valid():
		return false
	_prepare_pipeline = _rd.compute_pipeline_create(_prepare_shader)
	var sampler := RDSamplerState.new()
	sampler.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	_nearest = _rd.sampler_create(sampler)
	sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	_linear = _rd.sampler_create(sampler)
	sampler.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_field_sampler = _rd.sampler_create(sampler)
	# El detalle del techo elige su mip por la huella del píxel, así que necesita
	# interpolar entre niveles: con mip NEAREST el salto se ve al acercarse.
	sampler.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	_detail_sampler = _rd.sampler_create(sampler)
	var format := RDTextureFormat.new()
	format.width = 1
	format.height = 1
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	_fallback = _rd.texture_create(format, RDTextureView.new(), [PackedByteArray([0, 0, 0, 255])])
	return _prepare_pipeline.is_valid()


func _ensure_view(view: int) -> Dictionary:
	while _views.size() <= view:
		var format := RDTextureFormat.new()
		format.width = 256
		format.height = 256
		format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
		format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		# Dos niveles del mismo campo: el cercano resuelve la ventana de Snell cuando la
		# cámara está a poca profundidad, el lejano mantiene el oleaje del techo lejos.
		_views.append({"surface": _rd.texture_create(format, RDTextureView.new()),
			"surface_near": _rd.texture_create(format, RDTextureView.new()),
			"params": _rd.storage_buffer_create(int(layout.slots) * 16)})
		format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		format.width = 512
		format.height = 512
		_views.back()["background"] = _rd.texture_create(format, RDTextureView.new())
	return _views[view]


func prepare(device: RenderingDevice, _size: Vector2i, scene_data, projection: Projection, view: int, depth: RID, color: RID) -> Dictionary:
	if not _initialize(device):
		return {}
	_mutex.lock()
	var bytes := _snapshot.duplicate()
	var textures := _textures.duplicate()
	_mutex.unlock()
	if bytes.is_empty():
		bytes.resize(int(layout.slots) * 16)
	var transform: Transform3D = scene_data.get_cam_transform()
	if scene_data.get_view_count() > 1:
		transform.origin += transform.basis * scene_data.get_view_eye_offset(view)
	var active := _camera_near_water(bytes, transform.origin) and not _inside_interior(bytes, transform.origin)
	bytes.encode_float(12 * 16, 1.0 if active else 0.0)
	var images := _ensure_view(view)
	var inv_projection := projection.inverse()
	var inv_view := Projection(transform)
	for column in 4:
		_put_vec4(bytes, column * 16, inv_projection[column])
		_put_vec4(bytes, (column + 4) * 16, projection[column])
		_put_vec4(bytes, (column + 8) * 16, inv_view[column])
	var center := _vector(bytes, "planet_center")
	var up := (transform.origin - center).normalized()
	if up.is_zero_approx():
		up = Vector3.UP
	var tx := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var ty := up.cross(tx)
	# Resolve the nearby water roof rather than spending most cache texels far
	# beyond the Snell window. Keep the same texture size and dispatch count.
	# Concentrarlo más cerca gana téxeles en la ventana pero ACORTA la distancia a la
	# que la superficie tiene olas: fuera del campo la normal cae a la esfera analítica,
	# que es un espejo liso. Se probó 4 + 1.6*prof y el techo dejó de distorsionarse.
	var camera_depth := maxf((_vector(bytes, "waterline_point") - transform.origin).dot(up), 0.0)
	var amplitude := maxf(bytes.decode_float(int(_slots.wave_amplitude) * 16), bytes.decode_float(int(_slots.wave_calm_amplitude) * 16))
	var field_extent := clampf(48.0 + camera_depth * 3.0 + amplitude * 2.0, 48.0, 160.0)
	_put_vec4(bytes, 13 * 16, Vector4(tx.x, tx.y, tx.z, field_extent))
	_put_vec4(bytes, 14 * 16, Vector4(ty.x, ty.y, ty.z, 0.0))
	# Radio de la ventana = 1.135 * profundidad, más lo que la desplaza el oleaje. Con el
	# campo lejano solo le tocaba una docena de téxeles a dos metros; aquí son cientos.
	var near_extent := clampf(9.0 + camera_depth * 1.6 + amplitude * 0.5, 9.0, 32.0)
	bytes.encode_float(12 * 16 + 4, near_extent)
	var field_center := center + up * bytes.decode_float(int(_slots.water_radius) * 16)
	_put_vec4(bytes, 15 * 16, Vector4(field_center.x, field_center.y, field_center.z, 0.0))
	var uniforms: Array[RDUniform] = [
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [images.surface]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 5, [images.params]),
	]
	var near_uniforms: Array[RDUniform] = [
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [images.surface_near]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 5, [images.params]),
	]
	for list_uniforms in [uniforms, near_uniforms]:
		list_uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 2, [images.background]))
		list_uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_field_sampler, color]))
		list_uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, [_field_sampler, depth]))
	var caustics := _fallback
	var detail1 := _fallback
	var detail2 := _fallback
	var texture_index := 0
	for entry in layout.uniforms:
		if entry.type != "sampler2D":
			continue
		var texture := _fallback
		if texture_index < textures.size() and textures[texture_index] != null:
			var candidate := RenderingServer.texture_get_rd_texture(textures[texture_index].get_rid())
			if candidate.is_valid():
				texture = candidate
		var sampler := _nearest if entry.name == "storm_body_map" else _linear
		var entry_uniform := _uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, int(entry.binding), [sampler, texture])
		uniforms.append(entry_uniform)
		near_uniforms.append(entry_uniform)
		if entry.name == "caustics_texture":
			caustics = texture
		if entry.name == "texture_normal":
			detail1 = texture
			bytes.encode_float(14 * 16 + 12, 1.0 if texture != _fallback else 0.0)
		if entry.name == "texture_normal2":
			detail2 = texture
			bytes.encode_float(15 * 16 + 12, 1.0 if texture != _fallback else 0.0)
		texture_index += 1
	bytes.encode_float(12 * 16 + 8, 1.0 if caustics != _fallback else 0.0)
	_rd.buffer_update(images.params, 0, bytes.size(), bytes)
	if active:
		# El mismo shader, una vez por nivel: la extensión va por push constant porque el
		# buffer de parámetros es común a los dos despachos.
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _prepare_pipeline)
		for level: Array in [[uniforms, field_extent, 1.0], [near_uniforms, near_extent, 0.0]]:
			var push := PackedByteArray()
			push.resize(16)
			push.encode_float(0, level[1])
			push.encode_float(4, level[2])
			_rd.compute_list_bind_uniform_set(list, UniformSetCacheRD.get_cache(_prepare_shader, 0, level[0]), 0)
			_rd.compute_list_set_push_constant(list, push, push.size())
			_rd.compute_list_dispatch(list, 32, 32, 1)
			_rd.compute_list_add_barrier(list)
		_rd.compute_list_end()
	var result := images.duplicate()
	result["caustics"] = caustics
	result["detail1"] = detail1
	result["detail2"] = detail2
	return result


func bind_optics(shader: RID, images: Dictionary) -> RID:
	return UniformSetCacheRD.get_cache(shader, 1, [
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0, [images.params]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_field_sampler, images.surface]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_linear, images.caustics]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_field_sampler, images.surface_near]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, [_detail_sampler, images.detail1]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 5, [_detail_sampler, images.detail2]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 6, [_field_sampler, images.background])])


func _vector(bytes: PackedByteArray, name: String, index: int = 0) -> Vector3:
	var offset := (int(_slots[name]) + index) * 16
	return Vector3(bytes.decode_float(offset), bytes.decode_float(offset + 4), bytes.decode_float(offset + 8))


func _inside_interior(bytes: PackedByteArray, origin: Vector3) -> bool:
	var count := clampi(bytes.decode_s32(int(_slots.interior_count) * 16), 0, 128)
	for i in count:
		var delta := origin - _vector(bytes, "interior_center", i)
		var inside := true
		for axis in ["interior_axis_x", "interior_axis_y", "interior_axis_z"]:
			var extent := bytes.decode_float((int(_slots[axis]) + i) * 16 + 12)
			if absf(delta.dot(_vector(bytes, axis, i))) >= extent:
				inside = false
				break
		if inside:
			return true
	return false


func free_render_resources() -> void:
	if _rd == null:
		return
	for images in _views:
		for rid: RID in images.values():
			if rid.is_valid():
				_rd.free_rid(rid)
	_views.clear()
	for rid in [_prepare_shader, _linear, _nearest, _fallback, _field_sampler, _detail_sampler]:
		if rid.is_valid():
			_rd.free_rid(rid)
	_rd = null


static func release_owned_resources(device: RenderingDevice, water: UnderwaterRenderPass, resources: Array[RID]) -> void:
	water.free_render_resources()
	for rid in resources:
		if rid.is_valid():
			device.free_rid(rid)


func _camera_near_water(bytes: PackedByteArray, origin: Vector3) -> bool:
	if bytes.decode_float(12 * 16) < 0.5:
		return false
	var values := {}
	for entry in layout.uniforms:
		if entry.type == "float":
			values[entry.name] = bytes.decode_float(int(entry.slot) * 16)
		elif entry.name == "planet_center":
			var offset := int(entry.slot) * 16
			values[entry.name] = Vector3(bytes.decode_float(offset), bytes.decode_float(offset + 4), bytes.decode_float(offset + 8))
	var band: float = maxf(values.wave_amplitude, values.wave_calm_amplitude) * 5.2 \
		+ minf(values.shore_amplitude * values.shore_shoal_max, values.shore_length * 0.08) * 1.5 \
		+ values.waterline_seal_distance + 1.0
	return origin.distance_to(values.planet_center) <= values.water_radius + band

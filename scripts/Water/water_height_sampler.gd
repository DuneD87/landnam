class_name WaterHeightSampler extends Node

## Réplica en CPU de sample_water_height() de water_shader.gdshader: triplanar
## de la textura de olas en espacio mundo más ola procedural. Debe mantenerse
## en sincronía con el shader para que física y visual coincidan.

var wave_image: Image
var time_scale: float
var height_scale: float
var wave_speed: float
var wave_amplitude: float
var wave_frequency: float
var wave_world_scale: float
var wave_direction: Vector2
var texture_size: Vector2i

var _material: ShaderMaterial

## Lee del material los parámetros que intervienen en la altura de ola.
func setup(water_material: ShaderMaterial) -> void:
	_material = water_material
	var wave_tex: NoiseTexture2D = water_material.get_shader_parameter("wave")

	if wave_tex.get_image() == null:
		await wave_tex.changed

	wave_image = wave_tex.get_image()
	texture_size = Vector2i(wave_image.get_width(), wave_image.get_height())

	time_scale = water_material.get_shader_parameter("time_scale")
	height_scale = water_material.get_shader_parameter("height_scale")
	wave_frequency = water_material.get_shader_parameter("wave_frequency")
	wave_world_scale = water_material.get_shader_parameter("wave_world_scale")
	wave_direction = water_material.get_shader_parameter("wave_direction")
	_refresh_dynamic_params()

## Relee los parámetros que el weather muta en caliente sobre el material.
func _refresh_dynamic_params() -> void:
	wave_speed = _material.get_shader_parameter("wave_speed")
	wave_amplitude = _material.get_shader_parameter("wave_amplitude")

## Altura de ola en world_pos, idéntica al desplazamiento de vértices del shader.
func get_height_at(world_pos: Vector3, time: float, planet_center: Vector3) -> float:
	if wave_image == null:
		return 0.0
	_refresh_dynamic_params()

	var tri_pos := world_pos - planet_center
	var radial := tri_pos.normalized()

	var a := radial.abs()
	var w := a * a * a * a
	w /= (w.x + w.y + w.z)

	var time_offset := wave_direction * time * time_scale
	var h_xz := _sample_texture(Vector2(tri_pos.x, tri_pos.z) / wave_world_scale + time_offset)
	var h_xy := _sample_texture(Vector2(tri_pos.x, tri_pos.y) / wave_world_scale + time_offset)
	var h_yz := _sample_texture(Vector2(tri_pos.y, tri_pos.z) / wave_world_scale + time_offset)
	var tex_height := h_xz * w.y + h_xy * w.z + h_yz * w.x

	var proc_height := _generate_wave_world(tri_pos, radial, time)

	return (tex_height + proc_height) * height_scale

## Réplica de generate_wave_world(): senos sobre coordenadas del plano tangente.
func _generate_wave_world(local: Vector3, radial: Vector3, time: float) -> float:
	var seed_axis := Vector3(0, 1, 0) if absf(radial.y) < 0.99 else Vector3(1, 0, 0)
	var tangent := seed_axis.cross(radial).normalized()
	var bitangent := radial.cross(tangent).normalized()
	var p := Vector2(local.dot(tangent), local.dot(bitangent))

	var w1 := sin(p.x * wave_frequency + time * wave_speed) * wave_amplitude
	var w2 := sin(p.y * wave_frequency * 0.7 + time * wave_speed * 0.8) * wave_amplitude * 0.5
	var w3 := sin((p.x + p.y) * wave_frequency * 0.5 + time * wave_speed * 1.2) * wave_amplitude * 0.3
	return (w1 + w2 + w3) * 0.1

## Muestreo bilineal del canal R con repetición, como texture() con repeat_enable.
func _sample_texture(uv: Vector2) -> float:
	var x := fposmod(uv.x, 1.0)
	var y := fposmod(uv.y, 1.0)

	var fx := x * texture_size.x
	var fy := y * texture_size.y

	var x0 := int(fx) % texture_size.x
	var y0 := int(fy) % texture_size.y
	var x1 := (x0 + 1) % texture_size.x
	var y1 := (y0 + 1) % texture_size.y
	var frac_x :float = fx - floor(fx)
	var frac_y :float = fy - floor(fy)

	var c00 := wave_image.get_pixel(x0, y0).r
	var c10 := wave_image.get_pixel(x1, y0).r
	var c01 := wave_image.get_pixel(x0, y1).r
	var c11 := wave_image.get_pixel(x1, y1).r

	var top := lerpf(c00, c10, frac_x)
	var bottom := lerpf(c01, c11, frac_x)
	return lerpf(top, bottom, frac_y)

class_name WaterHeightSampler

var wave_image: Image
var noise_scale: float
var time_scale: float
var height_scale: float
var wave_speed: float
var wave_amplitude: float
var wave_frequency: float
var texture_size: Vector2i
var current_time: float = 0.0

func setup(water_material: ShaderMaterial) -> void:
	var wave_tex: NoiseTexture2D = water_material.get_shader_parameter("wave")
	
	if wave_tex.get_image() == null:
		await wave_tex.changed
	
	wave_image = wave_tex.get_image()
	texture_size = Vector2i(wave_image.get_width(), wave_image.get_height())
	
	noise_scale = water_material.get_shader_parameter("noise_scale")
	time_scale = water_material.get_shader_parameter("time_scale")
	height_scale = water_material.get_shader_parameter("height_scale")
	wave_speed = water_material.get_shader_parameter("wave_speed")
	wave_amplitude = water_material.get_shader_parameter("wave_amplitude")
	wave_frequency = water_material.get_shader_parameter("wave_frequency")

func get_height_at(world_pos: Vector3, time: float) -> float:
	if wave_image == null:
		return 0.0
	var uv := Vector2(world_pos.x, world_pos.z)

	var time_offset := time * time_scale
	var sample_uv := uv / noise_scale + Vector2(time_offset, time_offset)
	
	var tex_height := _sample_texture(sample_uv)
	var proc_height := _generate_wave(uv, time)

	return (tex_height + proc_height) * height_scale

func _generate_wave(pos: Vector2, time: float) -> float:
	var w1 := sin(pos.x * wave_frequency + time * wave_speed) * wave_amplitude
	var w2 := sin(pos.y * wave_frequency * 0.7 + time * wave_speed * 0.8) * wave_amplitude * 0.5
	var w3 := sin((pos.x + pos.y) * wave_frequency * 0.5 + time * wave_speed * 1.2) * wave_amplitude * 0.3
	return (w1 + w2 + w3) * 0.1

func _sample_texture(uv: Vector2) -> float:
	var x := fposmod(uv.x, 1.0)
	var y := fposmod(uv.y, 1.0)
	
	var fx := x * texture_size.x
	var fy := y * texture_size.y
	
	var x0 := int(fx) % texture_size.x
	var y0 := int(fy) % texture_size.y
	var x1 := (x0 + 1) % texture_size.x
	var y1 := (y0 + 1) % texture_size.y
	var frac_x :int = fx - floor(fx)
	var frac_y :int = fy - floor(fy)
	
	var c00 := wave_image.get_pixel(x0, y0).r
	var c10 := wave_image.get_pixel(x1, y0).r
	var c01 := wave_image.get_pixel(x0, y1).r
	var c11 := wave_image.get_pixel(x1, y1).r
	
	var top := lerpf(c00, c10, frac_x)
	var bottom := lerpf(c01, c11, frac_x)
	return lerpf(top, bottom, frac_y)

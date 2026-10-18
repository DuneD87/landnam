extends Node

## Compara la función de producción con valores de referencia en la GPU, sin depender del gamma:
## rojo = resultado, verde = referencia. Necesita render real.
var failures := 0


func _enter_tree() -> void:
	if "--background" in OS.get_cmdline_user_args():
		get_window().unfocusable = true
		get_window().position = Vector2i(-4000, -4000)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 16)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/lib/toon_light.gdshaderinc"
uniform float expected_amount;
void fragment() {
	int sample_index = int(UV.x * 4.0);
	float lit = sample_index == 3 ? 0.0 : 0.8;
	float att = sample_index == 0 ? 0.25 : (sample_index == 1 ? 0.15 : 1.0);
	// Luz local atenuada, sombra plena del sol, cara iluminada y cara opuesta a la luz.
	float band = sample_index == 0 ? 0.2375 : (sample_index == 1 ? 0.1425 : (sample_index == 2 ? 0.95 : 0.0));
	float reference = mix(lit * att, band, expected_amount);
	COLOR = vec4(toon_direct(lit, att, toon_shadow_floor, sample_index != 0), reference, 0.0, 1.0);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	var rect := ColorRect.new()
	rect.size = Vector2(64, 16)
	rect.material = material
	viewport.add_child(rect)
	RenderingServer.global_shader_parameter_set(&"toon_shadow_floor", 0.15)
	for amount in [0.0, 0.5, 1.0]:
		Console._cmd_toon([str(amount), "threshold", "0.12", "softness", "0.04", "gradient", "0.25"])
		material.set_shader_parameter("expected_amount", amount)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image.get_pixel(40, 8).g < 0.5:
			failures += 1
			push_error("El viewport no dibujó la referencia iluminada")
		for x in [8, 24, 40, 56]:
			var pixel := image.get_pixel(x, 8)
			if absf(pixel.r - pixel.g) > 0.01:
				failures += 1
				push_error("Toon %.1f, muestra %d: resultado=%f, referencia=%f" % [amount, x, pixel.r, pixel.g])
	Console._cmd_toon(["off"])
	viewport.queue_free()
	await get_tree().process_frame
	print("TOON SHADING GPU: %d failures" % failures)
	get_tree().quit(1 if failures else 0)

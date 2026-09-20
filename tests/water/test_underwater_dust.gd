extends SceneTree

## El polvo en suspensión tiene que ser ESTÁTICO: anclado al mundo, sin deriva ni vida.
## Se comprueba renderizando el mismo encuadre dos veces con segundos de diferencia.
## Necesita ventana: en --headless no hay rasterizador que capturar.

var failures := 0
var dust: UnderwaterDust
var camera: Camera3D
var water := ShaderMaterial.new()


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)


func _frame() -> Image:
	for frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


static func _differences(a: Image, b: Image) -> int:
	var count := 0
	for y in b.get_height():
		for x in b.get_width():
			if a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				continue
			count += 1
	return count


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("12414f")
	environment.environment = settings
	world.add_child(environment)
	camera = Camera3D.new()
	camera.current = true
	world.add_child(camera)
	# Superficie a 12 m sobre la cámara: la misma pareja de uniforms que publica el agua.
	water.set_shader_parameter(&"waterline_point", Vector3(0, 12, 0))
	water.set_shader_parameter(&"waterline_normal", Vector3.UP)
	dust = UnderwaterDust.new()
	world.add_child(dust)
	dust.camera = camera
	dust.water_material = water

	var first := await _frame()
	_check(dust.visible, "Bajo el agua el polvo se dibuja")
	var lit := 0
	var background := Color("12414f")
	for y in first.get_height():
		for x in first.get_width():
			if not first.get_pixel(x, y).is_equal_approx(background):
				lit += 1
	_check(lit > 20, "Hay motas en pantalla (%d píxeles)" % lit)

	await create_timer(1.5).timeout
	var second := await _frame()
	# Cero diferencias: ni deriva, ni ciclo de vida, ni parpadeo.
	_check(_differences(first, second) == 0, "El mismo encuadre no cambia con el tiempo")

	# Al desplazarse, las motas se quedan donde estaban: volver al sitio da la misma imagen.
	camera.position += Vector3(0, 0, -3.0)
	var moved := await _frame()
	_check(_differences(first, moved) > 0, "Al moverse cambia lo que se ve (hay paralaje)")
	camera.position = Vector3.ZERO
	var returned := await _frame()
	_check(_differences(first, returned) == 0, "El polvo está anclado al mundo, no a la cámara")

	# Fuera del agua no hay nada que ver.
	camera.position = Vector3(0, 20, 0)
	await _frame()
	_check(not dust.visible, "Sobre la superficie el polvo se apaga")

	print("UNDERWATER DUST TESTS: %d failures" % failures)
	quit(1 if failures else 0)

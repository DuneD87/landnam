extends SceneTree

const Mipmaps = preload("res://scripts/planet/grass_patch_mipmaps.gd")
var _failures: int = 0


func _initialize() -> void:
	# Silueta irregular con briznas finas: sus mips normales pierden cobertura.
	var silhouette := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for y in 64:
		for x in 64:
			var density: float = 0.8 * (1.0 - float(y) / 64.0) * (1.0 - float(x) / 64.0)
			silhouette.set_pixel(x, y, Color(0.15, 0.6, 0.08, 1.0 if rng.randf() < density else 0.0))
	_test_image(silhouette, 0.25, true)
	_test_image(silhouette, 0.7, true)
	for alpha in [0.0, 1.0]:
		var solid := Image.create(32, 16, false, Image.FORMAT_RGBA8)
		solid.fill(Color(0.2, 0.6, 0.1, alpha))
		_test_image(solid, 0.25, false)
	var narrow := Image.create(1, 32, false, Image.FORMAT_RGBA8)
	narrow.fill(Color(0.2, 0.6, 0.1, 0.0))
	for y in 9:
		narrow.set_pixel(0, y, Color(0.2, 0.6, 0.1, 1.0))
	_test_image(narrow, 0.25, false)
	print("GRASS MIPMAP TESTS: %d failures" % _failures)
	quit(1 if _failures else 0)


func _test_image(source: Image, threshold: float, expect_improvement: bool) -> void:
	var source_bytes := source.get_data()
	var regular := source.duplicate() as Image
	regular.generate_mipmaps()
	var corrected: Image = Mipmaps.generate(source, threshold)
	var ordinary_data := regular.get_data()
	var corrected_data := corrected.get_data()
	_check(source.get_data() == source_bytes, "No se modifica la imagen de entrada")
	_check(corrected_data.slice(0, source_bytes.size()) == source_bytes, "El nivel original permanece intacto")
	_check(corrected.get_mipmap_count() == regular.get_mipmap_count(), "La cadena de mips está completa")
	var rgb_matches: bool = true
	for index in ordinary_data.size():
		if index % 4 != 3 and ordinary_data[index] != corrected_data[index]:
			rgb_matches = false
	_check(rgb_matches, "El color no cambia en ningún nivel")
	var target: float = _coverage(source_bytes, 0, source.get_width() * source.get_height(), threshold)
	var improved: bool = false
	for level in range(1, corrected.get_mipmap_count() + 1):
		var pixels: int = maxi(source.get_width() >> level, 1) * maxi(source.get_height() >> level, 1)
		var offset: int = corrected.get_mipmap_offset(level)
		var original_error: float = absf(_coverage(ordinary_data, offset, pixels, threshold) - target)
		var corrected_error: float = absf(_coverage(corrected_data, offset, pixels, threshold) - target)
		_check(corrected_error <= original_error + 0.00001, "Mip %d: conserva al menos la cobertura original" % level)
		improved = improved or corrected_error + 0.01 < original_error
		for pixel in pixels:
			if ordinary_data[offset + pixel * 4 + 3] == 0:
				_check(corrected_data[offset + pixel * 4 + 3] == 0, "El fondo transparente sigue vacío")
	if expect_improvement:
		_check(improved, "La cobertura mejora en la silueta fina (umbral %.2f)" % threshold)


func _coverage(data: PackedByteArray, offset: int, pixels: int, threshold: float) -> float:
	var covered: int = 0
	for pixel in pixels:
		if float(data[offset + pixel * 4 + 3]) / 255.0 >= threshold:
			covered += 1
	return float(covered) / float(pixels)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

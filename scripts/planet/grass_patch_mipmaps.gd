extends RefCounted

## Conserva aproximadamente la superficie que supera el recorte en cada mip.
## Solo modifica alfa: el color y el nivel original del horneado se mantienen.
## Se ejecuta una vez al hornear, nunca durante el dibujo de cada frame.

static func generate(image: Image, alpha_threshold: float) -> Image:
	var result := image.duplicate() as Image
	result.convert(Image.FORMAT_RGBA8)
	result.generate_mipmaps()
	var data := result.get_data()
	var cutoff: int = clampi(int(ceil(alpha_threshold * 255.0)), 1, 255)
	var base_pixels: int = result.get_width() * result.get_height()
	var covered: int = 0
	for pixel in base_pixels:
		if data[pixel * 4 + 3] >= cutoff:
			covered += 1
	var coverage: float = float(covered) / float(base_pixels)
	for level in range(1, result.get_mipmap_count() + 1):
		var offset: int = result.get_mipmap_offset(level)
		var pixels: int = maxi(result.get_width() >> level, 1) * maxi(result.get_height() >> level, 1)
		var histogram := PackedInt32Array()
		histogram.resize(256)
		for pixel in pixels:
			histogram[data[offset + pixel * 4 + 3]] += 1
		# Buscar el corte con cobertura más próxima. En los últimos mips la
		# resolución limita lo representable; no forzar todos los píxeles a opacos.
		var target: float = coverage * float(pixels)
		var remaining: int = pixels - histogram[0]
		var best_cutoff: int = cutoff
		var best_error: float = INF
		for candidate in range(1, 257):
			var error: float = absf(float(remaining) - target)
			if error < best_error or (is_equal_approx(error, best_error)
					and absi(candidate - cutoff) < absi(best_cutoff - cutoff)):
				best_error = error
				best_cutoff = candidate
			if candidate < 256:
				remaining -= histogram[candidate]
		if best_cutoff == cutoff:
			continue
		for pixel in pixels:
			var alpha_index: int = offset + pixel * 4 + 3
			# División entera para que el corte elegido se respete también en RGBA8.
			@warning_ignore("integer_division")
			data[alpha_index] = mini(data[alpha_index] * cutoff / best_cutoff, 255)
	return Image.create_from_data(result.get_width(), result.get_height(), true, Image.FORMAT_RGBA8, data)

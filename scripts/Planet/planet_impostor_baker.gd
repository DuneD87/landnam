class_name PlanetImpostorBaker extends RefCounted

## Prepara los datos de superficie del impostor a partir del planeta real: el mapa de alturas lo
## hornea el propio VoxelGeneratorGraph (bake_sphere_bumpmap, en C++) y las texturas de bioma se
## reducen a su color medio, que es justo lo que se ve cuando el tileado cae por debajo del píxel.
##
## El reparto es a propósito: aquí solo va lo que necesita el generador. La escalera de biomas la
## resuelve planet_impostor.gdshader por fragmento, con la latitud sacada de la normal 3D, así no
## depende de la convención de téxeles del equirect (que es de godot_voxel, no nuestra).

## Devuelve los datos listos para el shader, o un diccionario vacío si no se pudo hornear.
## 'height_range' es el semirrango de búsqueda del SDF alrededor del radio: la superficie debe
## caer dentro de [radius - height_range, radius + height_range].
static func bake(planet: Planet, size: Vector2i, height_range: float) -> Dictionary:
	var generator = planet.voxel_terrain.generator
	if generator == null:
		push_warning("[impostor-bake] generador nulo.")
		return {}

	var argc := _method_arg_count(generator, "bake_sphere_bumpmap")
	if argc < 0:
		push_warning("[impostor-bake] %s no expone bake_sphere_bumpmap; sin mapa de superficie."
			% generator.get_class())
		return {}

	var t_start := Time.get_ticks_msec()
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RF)

	# La firma cambia entre builds: unas piden (im, ref_radius, sdf_min, sdf_max) y otras
	# (im, ref_radius, strength). Se elige por el número de argumentos declarado, en vez de
	# asumir uno y comerse un error de llamada.
	if argc >= 4:
		generator.bake_sphere_bumpmap(img, planet.radius, -height_range, height_range)
	else:
		generator.bake_sphere_bumpmap(img, planet.radius, height_range)

	var vmin := INF
	var vmax := -INF
	for y in size.y:
		for x in size.x:
			var v := img.get_pixel(x, y).r
			vmin = minf(vmin, v)
			vmax = maxf(vmax, v)

	print("[impostor-bake] bumpmap %s en %d ms; valores %.4f..%.4f (argc %d)" % [
		size, Time.get_ticks_msec() - t_start, vmin, vmax, argc])
	if vmax - vmin < 0.0001:
		push_warning("[impostor-bake] el bumpmap salió constante: el rango de búsqueda " +
			"(height_range = %.1f) no cruza la superficie, o el formato de imagen no vale."
			% height_range)
		return {}

	return {
		"texture": ImageTexture.create_from_image(img),
		# El bumpmap viene normalizado en [0,1] sobre el rango de búsqueda: con esto el shader
		# reconstruye la altura en unidades de mundo, que es lo que compara con max_heights.
		"height_min": -height_range,
		"height_range": height_range * 2.0,
		"biome_colors": _average_colors(planet.textures),
	}


## Número de argumentos declarados de un método, o -1 si el objeto no lo expone.
static func _method_arg_count(obj: Object, method: String) -> int:
	for m in obj.get_method_list():
		if m.name == method:
			return m.get("args", []).size()
	return -1


## Color medio de cada textura de albedo, ya en espacio lineal. A distancia de impostor el
## tileado se promedia igual, así que la media es literalmente lo que se ve. Se linealiza aquí
## porque 'source_color' no vale como hint en un uniform de array.
static func _average_colors(textures: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for t in textures:
		var c := Color(0.5, 0.5, 0.5).srgb_to_linear()
		if t is Texture2D:
			var img: Image = t.get_image()
			if img != null:
				img = img.duplicate()
				if img.is_compressed():
					img.decompress()
				# Reducir a 1x1 no promedia igual en todos los filtros; a 8x8 y media a mano sí.
				if not img.is_compressed():
					img.resize(8, 8, Image.INTERPOLATE_LANCZOS)
					var acc := Color(0.0, 0.0, 0.0, 0.0)
					for y in 8:
						for x in 8:
							acc += img.get_pixel(x, y).srgb_to_linear()
					c = acc / 64.0
		out.append(Vector3(c.r, c.g, c.b))
	print("[impostor-bake] colores medios (lineal) de %d texturas: %s" % [out.size(), out])
	return out

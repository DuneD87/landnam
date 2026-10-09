class_name TerrainMaterialData extends RefCounted

## Media del mismo mip 1×1 que antes leía el shader en cada fragmento. Se extrae
## y descomprime solo ese mip; los albedos grandes no se recorren píxel a píxel.
static var _mean_luma_cache: Dictionary = {}


static func mean_luma(texture: Texture2D) -> float:
	if texture == null:
		return 0.5
	if _mean_luma_cache.has(texture):
		return _mean_luma_cache[texture]
	var image := texture.get_image()
	if image == null or image.is_empty():
		push_error("TerrainMaterialData: no se puede leer el albedo %s" % texture.resource_path)
		return 0.5
	var mip := image.get_mipmap_count()
	if mip > 0:
		image = Image.create_from_data(maxi(1, image.get_width() >> mip),
			maxi(1, image.get_height() >> mip), false, image.get_format(),
			image.get_data().slice(image.get_mipmap_offset(mip)))
	if image.is_compressed() and image.decompress() != OK:
		push_error("TerrainMaterialData: no se puede descomprimir el albedo %s" % texture.resource_path)
		return 0.5
	# Si una textura no tiene mips (o tiene un límite), textureLod usa el centro del último.
	var x := (image.get_width() - 1) * 0.5
	var y := (image.get_height() - 1) * 0.5
	var x0 := int(floor(x))
	var y0 := int(floor(y))
	var x1 := mini(x0 + 1, image.get_width() - 1)
	var y1 := mini(y0 + 1, image.get_height() - 1)
	var a := image.get_pixel(x0, y0).srgb_to_linear().lerp(image.get_pixel(x1, y0).srgb_to_linear(), x - x0)
	var b := image.get_pixel(x0, y1).srgb_to_linear().lerp(image.get_pixel(x1, y1).srgb_to_linear(), x - x0)
	var color := a.lerp(b, y - y0)
	var mean := Vector3(color.r, color.g, color.b).dot(Vector3(0.2126, 0.7152, 0.0722))
	_mean_luma_cache[texture] = mean
	return mean

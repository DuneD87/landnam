class_name WorldMapData extends RefCounted

## Mapa equirectangular precomputado de un planeta: altura de la superficie por téxel y etiquetado
## de los cuerpos de agua conectados. Alimenta el mapa que ve el jugador y las consultas de gameplay
## desde el mismo dato.
##
## Equirect: u = 0.5 - atan2(z, x) / TAU, v = acos(y) / PI, norte arriba. No es la convención de
## planet_impostor.gdshader; ver la cabecera de WorldMapBaker.bake_heights.

const FILE_MAGIC := "GVWM"
const FILE_VERSION := 3

enum WaterType { OCEAN, SEA, LAKE, POND }

const TYPE_NAMES := {
	WaterType.OCEAN: "Océano",
	WaterType.SEA: "Mar",
	WaterType.LAKE: "Lago",
	WaterType.POND: "Charca",
}

var size: Vector2i = Vector2i.ZERO
var radius: float = 0.0
## Radio de la superficie del agua en calma; igual al radio nominal si el planeta no tiene agua.
var sea_level_radius: float = 0.0
var has_water: bool = false

## Alturas normalizadas [0,1] tal y como salen del bake, fila a fila desde el polo norte. La altura
## de mundo sobre el radio nominal es height_min + n * height_span; se guardan crudas porque así el
## mismo array sirve de textura RF para el shader del mapa sin recorrerlo en GDScript.
var heights: PackedFloat32Array = PackedFloat32Array()
var height_min: float = 0.0
var height_span: float = 1.0

## Índice en 'bodies' del cuerpo de agua de cada téxel, o -1 si es tierra.
var body_ids: PackedInt32Array = PackedInt32Array()
## Un diccionario por cuerpo de agua; ver WorldMapBaker._measure_bodies para las claves.
var bodies: Array[Dictionary] = []

## Campo de orilla: cuatro floats por téxel. xyz = dirección tangente unitaria hacia tierra y
## w = distancia firmada al litoral en metros (positiva en mar, negativa en tierra). Se guardan
## separados para que el filtrado bilineal no hunda la distancia cuando se encuentran direcciones
## opuestas en una bahía o un estrecho. El módulo de xyz interpolado queda entonces como medida
## gratuita de coherencia: puede reducir el arrastre horizontal sin apagar la amplitud.
var shore_size: Vector2i = Vector2i.ZERO
var shore_offsets: PackedFloat32Array = PackedFloat32Array()
## Alcance en metros con el que se horneó el campo; los téxeles sin campo guardan esta distancia.
var shore_range: float = 0.0

var _height_texture: ImageTexture
var _body_texture: ImageTexture
var _shore_texture: ImageTexture
var _percentiles: Dictionary = {}


## Dirección unitaria (en espacio del planeta) a coordenada equirect.
static func dir_to_uv(d: Vector3) -> Vector2:
	var n := d.normalized()
	return Vector2(
		fposmod(0.5 - atan2(n.z, n.x) / TAU, 1.0),
		acos(clampf(n.y, -1.0, 1.0)) / PI
	)


## Coordenada equirect a dirección unitaria. Inversa exacta de dir_to_uv.
static func uv_to_dir(uv: Vector2) -> Vector3:
	var theta := uv.y * PI
	var lon := (uv.x - 0.5) * TAU
	var st := sin(theta)
	return Vector3(st * cos(lon), cos(theta), -st * sin(lon))


## Latitud/longitud en grados: x = latitud (+N), y = longitud (+E, que en el mapa es hacia la
## derecha). El meridiano 0 es el del eje +X.
static func dir_to_latlon(d: Vector3) -> Vector2:
	var n := d.normalized()
	return Vector2(rad_to_deg(asin(clampf(n.y, -1.0, 1.0))), rad_to_deg(-atan2(n.z, n.x)))


static func latlon_to_dir(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	var cl := cos(lat)
	return Vector3(cl * cos(lon), sin(lat), -cl * sin(lon))


## Etiqueta legible de una latitud/longitud, en el formato que espera la UI.
static func format_latlon(latlon: Vector2) -> String:
	return "%.2f°%s  %.2f°%s" % [
		absf(latlon.x), "N" if latlon.x >= 0.0 else "S",
		absf(latlon.y), "E" if latlon.y >= 0.0 else "O",
	]


func is_valid() -> bool:
	return size.x > 0 and size.y > 0 and heights.size() == size.x * size.y


## Índice de téxel de una dirección. Envuelve en longitud y recorta en latitud, así los polos no
## necesitan un caso aparte.
func texel_of_dir(d: Vector3) -> int:
	var uv := dir_to_uv(d)
	var x := wrapi(int(floor(uv.x * size.x)), 0, size.x)
	var y := clampi(int(floor(uv.y * size.y)), 0, size.y - 1)
	return y * size.x + x


## Altura de la superficie sobre el radio nominal, interpolada. Es la misma magnitud que la
## 'height' del shader del terreno: length(pos - centro) - radius.
func height_at_dir(d: Vector3) -> float:
	if not is_valid():
		return 0.0
	var uv := dir_to_uv(d)
	var fx := uv.x * size.x - 0.5
	var fy := uv.y * size.y - 0.5
	var x0 := floori(fx)
	var y0 := floori(fy)
	var tx := fx - x0
	var ty := fy - y0
	var h00 := _texel_norm(x0, y0)
	var h10 := _texel_norm(x0 + 1, y0)
	var h01 := _texel_norm(x0, y0 + 1)
	var h11 := _texel_norm(x0 + 1, y0 + 1)
	var n := lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), ty)
	return height_min + n * height_span


## Radio de la superficie del terreno en esa dirección, desde el centro del planeta.
func surface_radius_at_dir(d: Vector3) -> float:
	return radius + height_at_dir(d)


## Profundidad de agua sobre el terreno; <= 0 en tierra firme.
func depth_at_dir(d: Vector3) -> float:
	if not has_water:
		return 0.0
	return sea_level_radius - surface_radius_at_dir(d)


func is_water_at_dir(d: Vector3) -> bool:
	return has_water and not body_ids.is_empty() and body_ids[texel_of_dir(d)] >= 0


## Cuerpo de agua en esa dirección, o {} si es tierra.
func water_body_at_dir(d: Vector3) -> Dictionary:
	if not has_water or body_ids.is_empty():
		return {}
	var id := body_ids[texel_of_dir(d)]
	if id < 0 or id >= bodies.size():
		return {}
	return bodies[id]


## Permite la costera salvo cuando el téxel identifica POSITIVAMENTE agua interior. Tierra (-1) es
## incierta cerca del litoral: el mapa grueso puede marcarla donde la malla visible aún es agua, y
## vetarla produciría exactamente un corte rectangular con la forma del téxel.
func shore_waves_allowed_at_dir(d: Vector3, flags: PackedByteArray) -> bool:
	if not has_water or body_ids.is_empty():
		return false
	var id := body_ids[texel_of_dir(d)]
	return id < 0 or (id < flags.size() and flags[id] != 0)


## Textura RF con las alturas normalizadas, para el shader del mapa. Se construye una sola vez y
## sin recorrer téxeles: el array de alturas ya está en el layout que espera FORMAT_RF.
func height_texture() -> ImageTexture:
	if _height_texture != null:
		return _height_texture
	if not is_valid():
		return null
	var img := Image.create_from_data(
		size.x, size.y, false, Image.FORMAT_RF, heights.to_byte_array())
	_height_texture = ImageTexture.create_from_image(img)
	return _height_texture


## Los cinco cortes de altura que reparten la rampa de color del mapa, en metros sobre el nivel del
## mar. Son percentiles de la tierra real, no fracciones de un rango fijo: así cada color cubre un
## trozo parecido de superficie y la rampa no se satura en ningún planeta.
func land_height_stops() -> PackedFloat32Array:
	var samples := _sorted_samples(true)
	var out := PackedFloat32Array()
	for p in [0.05, 0.30, 0.60, 0.85, 0.97]:
		out.append(_pick(samples, p))
	# Cortes estrictamente crecientes: si no, los smoothstep del shader se vuelven escalones.
	for i in range(1, out.size()):
		out[i] = maxf(out[i], out[i - 1] + 0.5)
	return out


## Percentil alto de la profundidad del agua, para escalar el degradado del océano.
func water_depth_percentile(p: float = 0.90) -> float:
	return _pick(_sorted_samples(false), p)


## Alturas sobre el mar (o profundidades) ordenadas, muestreando uno de cada 97 téxeles. Con dos
## millones de téxeles son ~21 000 muestras: de sobra para escalas de color y barato al vuelo.
func _sorted_samples(above_sea: bool) -> PackedFloat32Array:
	var key := "l" if above_sea else "w"
	if _percentiles.has(key):
		return _percentiles[key]

	var sea := sea_level_radius - radius
	var samples := PackedFloat32Array()
	var i := 0
	while i < heights.size():
		var h := height_min + heights[i] * height_span
		if above_sea and h > sea:
			samples.append(h - sea)
		elif not above_sea and h < sea:
			samples.append(sea - h)
		i += 97
	samples.sort()
	_percentiles[key] = samples
	return samples


static func _pick(sorted: PackedFloat32Array, p: float) -> float:
	if sorted.is_empty():
		return 1.0
	return maxf(sorted[clampi(int(sorted.size() * p), 0, sorted.size() - 1)], 0.5)


## Exposición a temporal en una dirección: 0 en tierra, lagos y charcas; rampa con la profundidad
## entre depth_start y depth_full. 'storm_flags' lleva un 1 por id de cuerpo con temporal.
## Camino caliente (flotabilidad de cada barco): un índice de téxel sirve para el id y la altura, y
## se muestrea al más cercano en vez de bilineal.
func storm_exposure_at_dir(dir: Vector3, storm_flags: PackedByteArray,
		depth_start: float, depth_full: float) -> float:
	if not has_water or body_ids.is_empty():
		return 1.0
	var i := texel_of_dir(dir)
	var id := body_ids[i]
	if id < 0 or id >= storm_flags.size() or storm_flags[id] == 0:
		return 0.0
	var depth := sea_level_radius - (radius + height_min + heights[i] * height_span)
	return smoothstep(depth_start, depth_full, depth)


## Textura con el id de cuerpo de agua de cada téxel: el int32 reinterpretado como RGBA8, sin
## recorrer el array. Quien la muestree DEBE hacerlo con filter_nearest y recomponer los cuatro
## bytes; con filtrado lineal se mezclan y el id sale inventado. Tierra = -1 = todo 255.
func body_texture() -> ImageTexture:
	if _body_texture != null:
		return _body_texture
	if not is_valid() or body_ids.size() != size.x * size.y:
		return null
	var img := Image.create_from_data(
		size.x, size.y, false, Image.FORMAT_RGBA8, body_ids.to_byte_array())
	_body_texture = ImageTexture.create_from_image(img)
	return _body_texture


func has_shore_field() -> bool:
	return shore_size.x > 0 and shore_offsets.size() == shore_size.x * shore_size.y * 4


## Muestra del campo: xyz = dirección hacia tierra, w = distancia firmada en metros. Bilineal
## a propósito: la distancia es la fase de la ola y al vecino las crestas saldrían escalonadas en
## saltos de un téxel. Réplica CPU de shore_offset_map en gerstner_waves.gdshaderinc.
func shore_sample_at_dir(d: Vector3) -> Vector4:
	if not has_shore_field():
		return Vector4.ZERO
	var uv := dir_to_uv(d)
	var fx := uv.x * shore_size.x - 0.5
	var fy := uv.y * shore_size.y - 0.5
	var x0 := floori(fx)
	var y0 := floori(fy)
	var tx := fx - x0
	var ty := fy - y0
	var top := _shore_texel(x0, y0).lerp(_shore_texel(x0 + 1, y0), tx)
	var bottom := _shore_texel(x0, y0 + 1).lerp(_shore_texel(x0 + 1, y0 + 1), tx)
	return top.lerp(bottom, ty)


func _shore_texel(x: int, y: int) -> Vector4:
	var i := (clampi(y, 0, shore_size.y - 1) * shore_size.x + wrapi(x, 0, shore_size.x)) * 4
	return Vector4(shore_offsets[i], shore_offsets[i + 1], shore_offsets[i + 2], shore_offsets[i + 3])


## Textura con el campo de orilla, para el shader del agua. Igual que las otras, sin recorrer
## téxeles: el array ya está en el layout de FORMAT_RGBAF. Se muestrea con filtro lineal.
##
## Se convierte a media precisión: W guarda la distancia EN METROS, y un half a 2 km da ~1 m de
## resolución, o sea 5 grados de fase contra una longitud de onda de 70 m. Eso no se ve, y a cambio
## la VRAM baja a la mitad (32 -> 16 MB a 2048x1024). Además el filtrado lineal de
## texturas de 32 bits en coma flotante NO está garantizado en Vulkan y el de 16 sí, así que esto
## también quita un riesgo de compatibilidad. La conversión va en C++, no por téxel desde GDScript.
func shore_texture() -> ImageTexture:
	if _shore_texture != null:
		return _shore_texture
	if not has_shore_field():
		return null
	var img := Image.create_from_data(
		shore_size.x, shore_size.y, false, Image.FORMAT_RGBAF, shore_offsets.to_byte_array())
	img.convert(Image.FORMAT_RGBAH)
	_shore_texture = ImageTexture.create_from_image(img)
	return _shore_texture


## Altura normalizada de un téxel, envolviendo en x y recortando en y.
func _texel_norm(x: int, y: int) -> float:
	return heights[clampi(y, 0, size.y - 1) * size.x + wrapi(x, 0, size.x)]


## Vuelca el mapa a disco. 'key' identifica la configuración con la que se horneó: al cargar se
## compara y un mapa de otro generador/resolución se descarta en vez de mostrarse mal.
func save_to(path: String, key: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("[world-map] no se pudo escribir el caché en %s (error %d)"
			% [path, FileAccess.get_open_error()])
		return false
	f.store_buffer(FILE_MAGIC.to_ascii_buffer())
	f.store_32(FILE_VERSION)
	f.store_pascal_string(key)
	f.store_32(size.x)
	f.store_32(size.y)
	f.store_double(radius)
	f.store_double(sea_level_radius)
	f.store_8(1 if has_water else 0)
	f.store_double(height_min)
	f.store_double(height_span)
	f.store_buffer(heights.to_byte_array())
	f.store_buffer(body_ids.to_byte_array())
	var meta := var_to_bytes(bodies)
	f.store_32(meta.size())
	f.store_buffer(meta)
	f.store_32(shore_size.x)
	f.store_32(shore_size.y)
	f.store_double(shore_range)
	f.store_buffer(shore_offsets.to_byte_array())
	f.close()
	return true


## Lee un mapa cacheado, o null si no existe, está corrupto o se horneó con otra configuración.
static func load_from(path: String, key: String) -> WorldMapData:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return null
	if f.get_buffer(4).get_string_from_ascii() != FILE_MAGIC or f.get_32() != FILE_VERSION:
		return null
	if f.get_pascal_string() != key:
		return null

	var out := WorldMapData.new()
	out.size = Vector2i(f.get_32(), f.get_32())
	out.radius = f.get_double()
	out.sea_level_radius = f.get_double()
	out.has_water = f.get_8() != 0
	out.height_min = f.get_double()
	out.height_span = f.get_double()

	var count := out.size.x * out.size.y
	if count <= 0 or count > 64 * 1024 * 1024:
		return null
	out.heights = f.get_buffer(count * 4).to_float32_array()
	out.body_ids = f.get_buffer(count * 4).to_int32_array()
	var meta_size := f.get_32()
	var meta = bytes_to_var(f.get_buffer(meta_size))

	out.shore_size = Vector2i(f.get_32(), f.get_32())
	out.shore_range = f.get_double()
	var shore_count := out.shore_size.x * out.shore_size.y * 4
	if shore_count > 0 and shore_count <= 192 * 1024 * 1024:
		out.shore_offsets = f.get_buffer(shore_count * 4).to_float32_array()
	f.close()

	if out.heights.size() != count or out.body_ids.size() != count or not (meta is Array):
		return null
	# Un campo de orilla truncado se descarta entero: el agua se queda sin olas de costa, que es
	# degradarse, en vez de leer fase de un array a medias.
	if not out.has_shore_field():
		out.shore_size = Vector2i.ZERO
		out.shore_offsets = PackedFloat32Array()
	out.bodies.assign(meta)
	return out

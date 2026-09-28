class_name SurfaceAudio
extends RefCounted

## Resuelve la familia de sonido del suelo que pisa una entidad, a partir del rayo que el IK de
## pies ya lanza. Decide por capas: rejilla de construcción, agua, pendiente y bioma del terreno.
## El tramo del terreno replica la selección de planet_biomes.gdshader (peso de bioma por latitud
## y escalera de max_heights) quedándose con la banda que más pesa, y traduce el índice de textura
## con Planet.sound_materials: un bioma nuevo suena bien añadiendo su familia al JSON del planeta.

## Familia con la que se responde cuando no hay nada con que decidir. Existe en la biblioteca y
## es el suelo más neutro, así que un fallo de configuración suena a tierra, no a silencio.
const DEFAULT_MATERIAL := &"dirtyground"
## Cuánto se mete la sonda por debajo del punto de contacto para caer dentro de la celda pisada
## y no en la de al lado.
const CELL_PROBE_BIAS := 0.05


## Familia de sonido del punto de contacto [hit] (un resultado de intersect_ray). [planet_root] es
## el nodo cargador del planeta (PlanetaryBody.planet) y [up] el arriba gravitacional.
static func resolve(hit: Dictionary, planet_root: Node3D, up: Vector3) -> StringName:
	if hit.is_empty():
		return DEFAULT_MATERIAL

	var from_grid := _grid_family(hit)
	if from_grid != &"":
		return from_grid

	if planet_root == null:
		return DEFAULT_MATERIAL
	var planet: Planet = planet_root.get(&"planet")
	if planet == null:
		return DEFAULT_MATERIAL

	var pos: Vector3 = hit["position"]
	var center: Vector3 = planet_root.global_position
	var normal: Vector3 = hit.get("normal", up)
	var snow := _snow_family(planet, planet_root, pos, center, normal, up)
	if snow != &"":
		return snow
	if _is_wet(planet, planet_root, pos, center):
		return &"water"

	if 1.0 - normal.dot(up) > planet.slope_threshold:
		return _family(planet.slope_sound_material)

	return _biome_family(planet, pos, center)


## Nieve del clima frío (la misma cobertura que pinta el terreno, sin sus manchas finas) y la
## banquisa, que también suena a nieve. Vacío si no hay nieve bajo los pies.
static func _snow_family(planet: Planet, planet_root: Node3D, pos: Vector3, center: Vector3,
		normal: Vector3, up: Vector3) -> StringName:
	var climate: ClimateField = planet.climate
	if climate == null or not climate.enabled:
		return &""
	var local := pos - center
	var sea_radius := planet.radius - planet.water_radius
	if planet.has_water and absf(local.length() - sea_radius) < 1.0:
		var map = planet_root.get(&"world_map")
		var water: bool = map != null and map.is_ready() and map.is_water_at(pos)
		if water and climate.sea_ice(local, 0.0) > 0.5:
			return &"snow"
	# Misma sujeción por pendiente que el shader (snow_slope_limit ~ 0,26 de 1 - cos).
	if 1.0 - normal.dot(up) > 0.3:
		return &""
	return &"snow" if climate.snow_cover(climate.coldness(local)) > 0.55 else &""


## Familia de sonido dominante entre los bloques que devuelve GridBase.damage_sphere. Un impacto
## es un golpe único: mezclar dos familias sonaría a dos choques, así que manda la que más
## bloques puso en el boquete. Devuelve vacío solo si no había material que reconocer, que es
## la señal para que suene el evento genérico.
static func dominant_family(destroyed_blocks: Array) -> StringName:
	var tally: Dictionary = {}
	var best_id := ""
	var best_count := 0
	for block: Dictionary in destroyed_blocks:
		var mat_id := String(block.get("material_id", ""))
		var n := int(tally.get(mat_id, 0)) + 1
		tally[mat_id] = n
		if n > best_count:
			best_count = n
			best_id = mat_id
	var mat := BlockDatabase.get_material_by_id(best_id)
	return _family(mat.sound_material) if mat != null else &""


## Familia del bloque pisado, o vacío si el rayo no dio en una rejilla de construcción.
static func _grid_family(hit: Dictionary) -> StringName:
	var collider := hit.get("collider") as Node3D
	if collider == null:
		return &""
	# En un cuerpo dinámico (un barco) el grid_id vive en el nodo de la forma, no en el cuerpo.
	var node := collider
	if collider is DynamicGridBody:
		var owner_id : int = collider.shape_find_owner(int(hit.get("shape", 0)))
		node = collider.shape_owner_get_owner(owner_id) as Node3D
	if node == null or not node.has_meta("grid_id"):
		return &""

	var grid := GridManager.get_grid_for_block(node)
	if grid == null:
		return &""
	var info := grid.get_block(_cell_of(node, grid, hit))
	if info.is_empty():
		return &""
	var mat := BlockDatabase.get_material_by_id(String(info.get("material_id", "")))
	return _family(mat.sound_material) if mat != null else &""


## Celda pisada. Rampas, esquinas y props llevan la suya en el propio colisionador; los cubos
## macizos van fusionados en cajas que cubren varias celdas, y ahí hay que deducirla del punto
## de contacto. Tiene que ser world_to_cell: un bloque ocupa [grid_pos, grid_pos+1), mientras que
## world_to_grid redondea al centro más cercano y sobre una cara plana devuelve la celda vacía
## de encima. El sesgo mete la sonda dentro del bloque, sin pasarse con celdas pequeñas.
static func _cell_of(node: Node3D, grid: GridBase, hit: Dictionary) -> Vector3i:
	if node.has_meta("grid_pos"):
		return node.get_meta("grid_pos")
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var bias := minf(CELL_PROBE_BIAS, grid.cell_size * 0.25)
	return grid.world_to_cell(hit["position"] - normal * bias)


## True si el punto de contacto está bajo el nivel del mar y ahí hay agua de verdad. Sin el mapa
## horneado se conforma con el nivel del mar, que es lo mismo salvo en cuencas secas.
static func _is_wet(planet: Planet, planet_root: Node3D, pos: Vector3, center: Vector3) -> bool:
	if not planet.has_water:
		return false
	if (pos - center).length() > planet.radius - planet.water_radius:
		return false
	if GridManager.is_point_in_dry_interior(pos):
		return false
	var map = planet_root.get(&"world_map")
	if map == null or not map.is_ready():
		return true
	return map.is_water_at(pos)


## Banda de bioma que más pesa en ese punto, traducida a familia de sonido. Es el acumulador de
## planet_biomes.gdshader quedándose con el máximo en vez de mezclar: dos pisadas no se promedian.
static func _biome_family(planet: Planet, pos: Vector3, center: Vector3) -> StringName:
	var d := pos - center
	if d.length_squared() <= 0.0:
		return DEFAULT_MATERIAL
	var latitude := rad_to_deg(asin(clampf(d.normalized().y, -1.0, 1.0)))
	var height := d.length() - planet.radius
	var smoothness := planet.transition_smoothness

	var best := -1
	var best_factor := 0.0
	for b in planet.biome_count:
		if b + 1 >= planet.biome_latitude_ranges.size():
			break
		var lower: float = planet.biome_latitude_ranges[b]
		var upper: float = planet.biome_latitude_ranges[b + 1]
		var span := upper - lower
		var w := 1.0 - absf(latitude - (lower + upper) * 0.5) \
				/ maxf(span * planet.biome_transition_smoothness, 0.0001)
		var biome_weight := smoothstep(0.0, 1.0, clampf(w, 0.0, 1.0))
		if biome_weight < 0.01:
			continue

		var offset := b * planet.textures_per_biome
		for j in planet.textures_per_biome:
			if offset + j >= planet.max_heights.size():
				break
			var factor: float
			if j == 0:
				factor = smoothstep(-smoothness, smoothness, planet.max_heights[offset] - height)
			else:
				var lo: float = planet.max_heights[offset + j - 1]
				var hi: float = planet.max_heights[offset + j]
				factor = smoothstep(-smoothness, smoothness, hi - height) \
						* (1.0 - smoothstep(-smoothness, smoothness, lo - height))
			factor *= biome_weight
			if factor > best_factor:
				best_factor = factor
				best = offset + j

	if best < 0 or best >= planet.biome_texture_indices.size():
		return DEFAULT_MATERIAL
	return _texture_family(planet, planet.biome_texture_indices[best])


static func _texture_family(planet: Planet, texture_index: int) -> StringName:
	if texture_index < 0 or texture_index >= planet.sound_materials.size():
		return DEFAULT_MATERIAL
	return _family(planet.sound_materials[texture_index])


static func _family(value: StringName) -> StringName:
	return value if value != &"" else DEFAULT_MATERIAL

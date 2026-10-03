class_name UndergroundDepth
extends RefCounted

## Profundidad bajo tierra: los metros de roca que tiene encima un punto, medidos contra la superficie
## del planeta ANTES de tallar las cuevas (con los ríos ya tallados). Un valle o una cumbre son
## superficie y valen 0; solo lo que vació una cueva queda por debajo. La escribe el generador
## (earth_terrain_terraces.tres, nodos underground_depth_*) como el peso de la capa LAYER, y viaja con
## el vóxel hasta la malla (CUSTOM1, como las menas): la leen planet_biomes.gdshader y Planet.
##
## Codificación: el grafo saca sqrt(profundidad / RANGE) + 1/30 y el módulo lo guarda en 4 bits
## (nivel = floor(peso * 15)), así que el nivel n (0..15) vale (n / 15)² · RANGE metros. Pasos finos
## cerca de la superficie (0,3 · 1,1 · 2,6 · 4,6 m), donde se ve la boca de la cueva, y gruesos
## abajo; satura en RANGE. Tiene que coincidir con el grafo y con UNDERGROUND_DEPTH_* del shader.
##
## Los 4 huecos de pesos del vóxel los comparten las menas (capas 1-3) y esta capa: con una cuarta
## mena empezarían a competir y el vóxel se quedaría con las 4 de más peso.

const LAYER := 15
const RANGE := 64.0


## Profundidad (m) a partir de los canales INDICES y WEIGHTS de un vóxel. 0 si no la lleva (un
## cuerpo cuyo grafo no la escribe, o un bloque guardado en la partida antes de que existiera).
static func decode(indices_u16: int, weights_u16: int) -> float:
	var indices := VoxelTool.u16_indices_to_vec4i(indices_u16)
	var weights := VoxelTool.u16_weights_to_color(weights_u16)
	var idx := [indices.x, indices.y, indices.z, indices.w]
	var w := [weights.r, weights.g, weights.b, weights.a]
	for slot in 4:
		if idx[slot] == LAYER:
			# u16_weights_to_color devuelve el nivel de 4 bits como (nivel << 4) / 255.
			var level := clampf(roundf(w[slot] * 255.0 / 16.0), 0.0, 15.0)
			var s := level / 15.0
			return s * s * RANGE
	return 0.0


## Profundidad (m) del vóxel de LOD 0 en `world_pos`, o -1 si ese trozo de terreno no está cargado.
## Vale también en el aire de una cueva: el generador la escribe en todos los vóxeles, no solo en la
## roca, y excavar no la cambia (solo toca el SDF).
static func at(terrain: VoxelLodTerrain, tool: VoxelTool, world_pos: Vector3) -> float:
	var local := terrain.to_local(world_pos)
	if not tool.is_area_editable(AABB(local - Vector3.ONE, Vector3.ONE * 2.0)):
		return -1.0
	var p := Vector3i(local.round())
	tool.channel = VoxelBuffer.CHANNEL_INDICES
	var indices := tool.get_voxel(p)
	tool.channel = VoxelBuffer.CHANNEL_WEIGHTS
	var weights := tool.get_voxel(p)
	return decode(indices, weights)

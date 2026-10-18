# Mapas del material del terreno

`planet_biomes.gdshader` comparte las lecturas triplanares de los mapas escalares:

| Canal | Dato | Espacio |
|-------|------|---------|
| R | Roughness | Lineal |
| G | Oclusión ambiental (AO) | Lineal |
| B | Altura | Lineal |

Los JSON de Tierra y Luna declaran `biome_settings.packed_material_textures`, en el mismo orden que
`textures`, y `slope_packed_material_texture`. `reef_settings.packed_material_texture` reutiliza un
mapa compatible para R/G. Los archivos originales y sus rutas se conservan para regenerar los mapas.
Un JSON sin los campos nuevos carga los mapas separados. No se empaquetan imágenes durante la carga
del planeta, y los mapas separados no se cargan cuando existe la versión empaquetada.

Para regenerar los ocho materiales (Python 3 y Pillow):

```sh
python3 tools/terrain/pack_material_maps.py
python3 tools/terrain/pack_material_maps.py --check
```

Después hay que abrir el proyecto en Godot para importar los PNG, o usar el ejecutable compatible
con Voxel Tools con `--headless --editor --path . --import`. La importación usa compresión VRAM de
alta calidad y mipmaps; los mapas empaquetados no llevan `source_color` ni importación de normales.
R/G/B reproducen exactamente el canal rojo de cada PNG original antes de la compresión VRAM.

Por cada material activo, roughness/AO/altura pasan de hasta nueve lecturas a tres. El parallax
mantiene sus tres muestras de altura previas al desplazamiento de UV, leyendo B. Biomas, pendientes,
nieve, hielo y escollos usan la misma codificación. Albedo y normales mantienen sus muestras.

`TerrainMaterialData.mean_luma()` extrae el último mip del albedo importado al cargar el planeta,
lo convierte de sRGB a lineal y cachea la luminancia. El detalle cercano y la capa lejana reutilizan
ese escalar, evitando leer el mip 1×1 por fragmento. Un `ShaderMaterial` creado fuera de `Planet`
puede mantener el comportamiento anterior dejando `albedo_means_ready=false`.

**Material del terreno**, en Opciones → Gráficos, controla el detalle cercano, parallax y antitiling
independientemente de la geometría. Ver [options.md](options.md). La calidad Alta conserva los
efectos del planeta; el empaquetado y las medias precalculadas se usan en las tres calidades.

## Menas

Los diez materiales del mundo, de la Edad de piedra a la del Hierro:

| Material | Objeto | Dónde | Cómo sale |
|---|---|---|---|
| Sílex | `flint` | Bioma templado, de la orilla a 200 m, en campos de rocas de creta | Afloramiento |
| Obsidiana | `obsidian` | Norte frío (latitud > 41°), de 150 a 900 m | Afloramiento |
| Cobre (malaquita) | `copper_ore` | Cualquier bioma, de 60 a 600 m | Afloramiento |
| Hierro de pantano (limonita) | `bog_iron` | Tierras bajas, hasta 15 m sobre el radio | Veta |
| Carbón | `coal` | Llanuras y colinas, de 15 a 110 m | Veta |
| Estaño (casiterita) | `tin_ore` | Colinas, de 110 a 210 m | Veta |
| Plata (galena) | `silver_ore` | Montañas, de 210 a 320 m | Veta |
| Oro | `gold_01` | Montañas altas, de 320 a 420 m | Veta |
| Azufre | `sulfur` | Cumbres, por encima de 420 m | Veta |
| Hierro (hematites) | `iron_01` | En cualquier sitio, en manchas propias | Veta (y en las cuevas, de 30 a 120 m de hondo) |

Las alturas son sobre el radio del planeta, como las de la vegetación (el mar está en −50). En tierra
firme la mitad queda por debajo de 88 m, tres cuartos por debajo de 186 y solo un 5 % por encima de
343, así que cuanto más alta la franja, más rara la mena: el hierro de pantano y el carbón abundan,
el oro y el azufre escasean.

### Afloramientos

Rocas del instancer (`scenes/planet/planet_items/rocks/outcrop_*.tscn`, `Rock3D` con su textura) que
se pican con el pico como las demás (`RockMining`). Dan su mena en vez de piedra, en menos trozos
(`Item.mining_yield`: 0,6 el sílex, 0,5 la obsidiana y el cobre). Salen en campos: sus generadores
(`*_outcrop_generator`) llevan un ruido con umbral, así que donde hay una suele haber más.

### Vetas

Parches en el terreno (pesos de vóxel, una capa por `type_id`) que el pico excava y que dan su mena
(`ActionController.dig_hole`, la tabla `ore_drops` de cada `type_id`). Se ven con la textura de su mena
(`planet_biomes.gdshader`, hasta 8 tipos: `MAX_ORE_TYPES`).

- **`ore_settings`** en `planet_earth.json`: una por `type_id`, en orden (el shader coge la textura de
  cada una por su posición). Las de cueva llevan `depth_min`.
- **Grupos** (`spot_group`): el hierro de pantano, el carbón, el estaño, la plata, el oro y el azufre
  comparten manchas (`ore_spots_metal`, las pone la primera del grupo: el oro) y se reparten las
  alturas en franjas seguidas (`min_height`, `max_height`; la suavidad de los bordes,
  `height_softness`). Cada `Spots3D` es lo más caro de una veta: así seis vetas cuestan una red de
  manchas. Con las siete vetas de superficie el generador de la Tierra pasa de 2,25 a 2,40 µs por
  vóxel (`VoxelGeneratorGraph.debug_measure_microseconds_per_voxel`).
- **El grafo** (`data/graph_functions/earth_ore_field.tres`) lo genera
  `tools/terrain/build_ore_field.py` desde el JSON, y conecta cada salida a su `OutputWeight` en
  `earth_terrain_terraces.tres`. `Planet._apply_ore_params` vuelve a poner al cargar los valores del
  JSON (semillas, celdas, profundidad y franjas), así que retocarlos no pide regenerar; añadir o
  quitar vetas, o cambiar sus grupos, sí. Cambiar el grafo cambia la huella del generador: la primera
  carga vuelve a hornear el mapa del mundo y los ríos.

### Texturas

`tools/terrain/make_ore_textures.py` las hace sobre las rocas que ya hay, recoloreadas y con su
mineral pintado donde le toca (en las grietas, en las crestas, en manchas o en vetas de ruido
periódico, para que repitan sin costura): casiterita en granito, limonita, capas de carbón en
pizarra, galena, costras de azufre; y para los afloramientos, nódulos de sílex en creta, obsidiana y
malaquita con algo de azurita.

```sh
python3 tools/terrain/make_ore_textures.py [--only=tin,flint]
python3 tools/terrain/build_ore_field.py
godot --headless --editor --quit --path .   # importa
```

Los trozos de cada mena (los objetos, sus escenas y sus iconos) salen de `SurvivalMeshes.ore_chunk` con
`tools/combat/bake_weapons.gd`.

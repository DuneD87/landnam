# Bioma nevado

Taiga, tundra, alta montaña y casquetes polares de la Tierra, con su vegetación, su fauna, el mar
helado y auroras. Todo sale de **un solo campo de frío**, así que la nieve del suelo, la de las copas,
dónde crece cada planta, dónde vive cada animal y dónde se hiela el agua coinciden siempre.

## Campo de frío

```
frío = |latitud| + lapse · max(altura - lapse_base, 0) + ruido   (grados de latitud equivalente)
```

La altura suma frío como si fuera latitud: la alta montaña es el mismo bioma que el polo, sin una
banda aparte. El ruido son dos octavas de OpenSimplex2 (1800 m y 260 m) que rompen los límites de
las zonas.

| Frío | Zona | Suelo | Vida |
|---|---|---|---|
| < 41 | templado | el de siempre | lo de siempre |
| 41–53 | taiga | nieve con calvas | piceas, pinos, abedules; enebro, brezo, juncia |
| 53–67 | tundra y alta montaña | nieve, roca y turba asomando | piceas enanas hasta ~56; abedul enano, algodoncillo, liquen, amapola ártica |
| > 67 | casquete | nieve y hielo glaciar | bloques de hielo, rocas nevadas |

Con la configuración actual (`climate_settings` en `planet_earth.json`: lapse 0,085 °/m desde 30 m
sobre el mar) la taiga empieza a nivel del mar hacia los 41° y, a 25° de latitud, por encima de
~210 m. La cota de nieve (`snow.start`/`full`: 37 → 50) va algo por delante de la taiga.

Tres implementaciones del mismo campo, comprobadas entre sí por los tests:

- **GPU**: `shaders/lib/climate.gdshaderinc`, con uniforms globales (`climate_*` en
  `project.godot`) que escribe `ClimateField.push_shader_globals()`. Solo los empuja un planeta con
  `climate_settings`: la luna no los toca. El ruido es la réplica de FastNoiseLite que ya usaba el
  terreno, movida a `shaders/lib/fnl_simplex.gdshaderinc`.
- **CPU**: `ClimateField` (`scripts/planet/climate_field.gd`), `planet.climate`. Lo usan la fauna,
  las pisadas, el clima, el hielo marino y el suelo de la banquisa.
- **Grafos de vegetación**: `ClimateGraph` (`scripts/planet/climate_graph.gd`) añade el mismo frío
  en nodos a la máscara de densidad de un generador con `"climate": {"min", "max", "soft"}`.

Diferencias medidas: CPU/GPU < 0,01°, grafo/CPU < 0,004° (`tests/climate/`).

`climate_snow_coldness` es la variante barata para la nieve: si ni con el ruido a favor ni con la
nevada llega a la cota, no evalúa el ruido. Los objetos (hierba, árboles, rocas) usan solo la octava
ancha.

## Terreno

`planet_biomes.gdshader`, sección 8.5: una capa de nieve encima del reparto de biomas, no una banda
de textura.

- Cobertura por frío más manchas (dos fBm) que rompen el borde en ventisqueros y calvas.
- Resbala de las pendientes (`snow_slope_limit`, más permisivo en el casquete).
- Rellena primero los huecos del suelo (height blend con la textura de debajo).
- En el casquete, las laderas que no sostienen nieve enseñan hielo glaciar (`ice_field`).
- Las vetas de mena la atraviesan: se siguen viendo para minarlas.
- Destellos de cristales al sol (`snow_sparkle_*`), solo de cerca.
- La textura de nieve se usa solo por su relieve de luminancia sobre un blanco real: su albedo era
  ~0,5 y a la sombra la nieve salía azul oscuro.

Los biomas polares y la franja alta templada llevan ahora debajo turba de tundra
(`mud_with_vegetation`) y roca en lugar de nieve pintada: lo blanco lo pone la capa de nieve.

Depuración: `--debug-snow` en la línea de comandos pinta cobertura (R), sujeción (G) y nieve (B).
Tiene que estar desde el arranque: los bloques ya mallados no ven cambios del material.

## Vegetación

Los generadores templados llevan `"climate": {"max": 41}`: el bosque verde se para donde empieza la
taiga. Los fríos usan `earth_terrain_surface.tres`, la puerta de superficie del grafo verde (fuera
de cuevas y cauces) sin banda de latitud, derivada con `tools/vegetation/build_surface_mask.gd`.

**Árboles** (generador Branching, presets en `tools/vegetation/tree_presets.gd`):

- `spruce_01..03`: picea, un solo guía, verticilos casi hasta el suelo y ramillas colgantes. Corteza
  `knotted_pine_bark` de Poly Haven (CC0). La ramita la pinta `tools/vegetation/paint_cold_twigs.gd`.
- `birch_01..02`: abedul de tronco blanco y copa dorada de otoño boreal. Corteza procedural
  (`tools/vegetation/paint_birch_bark.py`) y ramita pintada.
- Los pinos existentes también crecen en la taiga, y `spruce_02` se repite a 2,5–5 m como picea enana
  en la línea de árboles.
- Impostores octaédricos horneados como los demás (`bake_tree_impostors.tscn`).

**Sotobosque** (`understory_geometry.gd`, mismos LODs y relevo que el resto): enebro rastrero,
abedul enano, brezo, algodoncillo, liquen de los renos y amapola ártica. **Hierba de tundra**:
`low_poly_grass_tundra.tscn`, juncia pajiza con las bandas cercana y lejana de siempre.

**Rocas**: las verdes vuelven a salir en frío (`large_rock_generator_cold`,
`small_rocks_generator_cold`) y `ice_block_01` (Rock3D con material de hielo) en el casquete.

**Nieve sobre todo lo anterior**, por shader y según el frío del sitio: corteza (caras al cielo y
ventisca al pie), copas (nieve en la parte alta y sobre las ramas horizontales, que además deja de
transmitir luz), impostores lejanos (con su normal horneada), rocas (con escarcha en el casquete;
`climate_snow_amount` en el material, así las armaduras que comparten shader no nievan), y hierba y
sotobosque (escarcha en las puntas y matas medio enterradas: `snow_burial`).

## Agua helada

`gerstner_waves.gdshaderinc`: `sea_ice_fraction` (latitud y distancia a la costa, sin ruido porque la
niebla submarina la evalúa decenas de veces por píxel) entra en `wave_context` y apaga el oleaje. Por
estar ahí, el compute submarino lo hereda al regenerarlo (`tools/water/build_underwater_shared.py`)
y `WaterHeightSampler` lo replica en CPU (`last_ice`). Costas, bahías, ríos y lagos se hielan unos
grados antes que el mar abierto.

`water_shader.gdshader` dibuja la banquisa: témpanos (celdas de Voronoi) que se sueldan al enfriar,
grietas recongeladas, crestas de presión entre placas grandes, nieve venteada y hielo azul desnudo.
El agua recibe ahora sombras (árboles y jugador sobre el hielo).

### Témpanos e icebergs con volumen

`SeaIceFloes` (`scripts/water/sea_ice_floes.gd`, colgado del PlanetLoader) pone la banquisa en 3D
alrededor de la cámara, hasta 480 m. Los últimos 100 m los témpanos encogen mientras el agua dibuja
los suyos (`ice_geometry_start/end` en `water_shader`).

- **Reparto** (`SeaIceLayout`): las mismas celdas de Voronoi 3D, el mismo hash y el mismo umbral por
  celda que la banquisa dibujada de lejos, cortadas por el plano del mar (un diagrama de potencias,
  así que cada témpano es un polígono convexo exacto). En el borde de la banquisa se parten en
  trozos y los cantos se rompen hacia dentro, sin invadir al vecino; cerrada, encajan con grietas
  finas que suelda el hielo nuevo del agua. Determinista: nada se guarda.
- **Mallas** (`SeaIceMeshes`): un ArrayMesh por bloque de 4×4×4 celdas, construido en hilos (unos
  7 ms por bloque). Losa biselada con unas cuatro quintas partes bajo el agua.
- **Flotación** (`shaders/liquid/sea_ice.gdshader`): cada témpano se mueve entero con la ola en su
  centro (el mismo Gerstner que el agua, sin las olas más cortas que él), cabecea con la normal del
  agua y deriva y gira despacio donde la banquisa está abierta. `SeaIceFloes._pose` es la réplica
  CPU (`WaterHeightSampler.rest_displacement`).
- **Colisión**: solo los témpanos a menos de 10 m del jugador, cuerpos animables que siguen a
  `_pose` en cada tick. Van en la capa 17, como el suelo de la banquisa: el jugador camina encima y
  los barcos los atraviesan. Nadando junto a uno, saltar sube encima (`_try_haul_out`).
- **Icebergs**: uno como mucho por celda de 700 m, en la banquisa y en el mar abierto hasta 5° por
  delante de ella, donde hay fondo para su calado. Tabulares (paredes con estratos, techo plano) o
  en cúpula, con el doble de lo que asoma bajo el agua. Colisión estática en la capa del mundo: los
  barcos chocan. Se ven hasta 5 km.

**Física**: `SeaIceFloor` (`scripts/water/sea_ice_floor.gd`) coloca un bloque plano bajo el jugador
donde la banquisa está cerrada (hielo desde 0,97 con témpanos; 0,75 sin ellos), para las grietas y
los huecos entre esquinas. Va en la capa 17, que solo añade a su máscara el jugador. Sobre el hielo
no se nada, no hay chapoteo y las pisadas suenan a nieve.

## Fauna

`GroundFaunaProfile` admite `climate_min`/`climate_max` (y `hemisphere`); la fauna templada lleva ya
su tope (el ciervo y el oso pardo llegan a la taiga, el conejo no).

| Especie | Perfil | Frío | Modelo |
|---|---|---|---|
| Oso polar | `polar_bear.tres` | > 58 | `PolarBear.tscn` (hereda del oso, pelaje recoloreado, caza caribús) |
| Caribú | `caribou.tres` | 45–66 | `Caribou.tscn` (hereda del ciervo, huye de los osos) |
| Liebre ártica | `arctic_hares.tres` | 46–68 | esculpida, anatomía y animación del conejo |
| Zorro ártico | `arctic_foxes.tres` | 52–74 | esculpido, orejas cortas y cola más tupida |
| Lemming | `lemmings.tres` | 52–66 | esculpido, rechoncho y de cola corta |

Pelajes: `tools/fauna/recolor_cold_fauna.py` (oso polar y caribú) y
`tools/fauna/sculpt_small_animals.py 3 4 5` + `bake_small_animal_meshes.gd` (pequeños). Censo medido
en la tundra (`snow_capture --fauna`): 2 osos polares, 11 caribús, 7 liebres, 3 zorros árticos, 10
lemmings.

## Clima y cielo

- En tierra fría la lluvia del temporal cae como nieve, y la nevada baja la cota de nieve de todo
  (`climate_fresh_snow`, 9°). La taiga refuerza nieve y niebla; tundra y casquete usan el perfil de
  cumbres.
- **Aurora** (`space_sky.gdshader`): arcos con cortinas verdes y violáceas, en el óvalo de 55–80° de
  latitud, de noche, con una actividad que sube y baja en ciclos de decenas de minutos y que las
  nubes tapan (`SkyLighting._aurora_intensity`).

## Pruebas y capturas

```sh
godot --path . -s res://tests/climate/test_climate_field.gd          # CPU = GPU (necesita renderer)
godot --headless --path . -s res://tests/climate/test_climate_graph.gd  # grafo = CPU, bandas
godot --path . res://tests/climate/snow_capture.tscn -- --spots=taiga,tundra --times=noon,night
godot --headless --path . -s res://tests/climate/test_sea_ice_layout.gd  # témpanos e icebergs
```

`snow_capture` busca en el mapa un sitio de cada zona (taiga, treeline, tundra, icecap, alpine,
coast, river, sea, floes, forest) y guarda `build/lighting/snow_<sitio>_<toma>_<hora>.png`. En
`floes` (borde de la banquisa) también fotografía el iceberg más cercano, por fuera y bajo el agua.
Opciones: `--list`, `--fauna` (censo), `--counts` (instancias por item), `--probe` (alturas reales),
`--perf`, `--debug-snow`. El arnés mueve también la cámara del jugador, que es la que refina la
malla del océano.

## Coste

Bosque templado de referencia a 3840×2160: 5,98 ms antes y 6,27 ms después (vegetación 0,65 →
0,70 ms). Esa vista está cerca de la cota de nieve (28°, lomas): en el trópico los shaders no
evalúan el ruido. Taiga y línea de árboles: 7,2–8,5 ms en las mismas condiciones.

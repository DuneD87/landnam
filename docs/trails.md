# Sendas del mundo

Sendas de unos 4 m que vienen con el planeta: se trazan sobre el relieve la primera vez que se carga,
como los ríos, y el generador del terreno las pinta, las hunde un poco y aparta de ellas la
vegetación. Las del jugador (pisadas, empedradas) no son esto: irían en los vóxeles editados.

| Pieza | Qué hace |
|---|---|
| `TrailNetwork` (`scripts/world/trail_network.gd`) | Traza la red sobre el relieve y la convierte en trazos suaves |
| `TrailField` (`scripts/world/trail_field.gd`) | Reparte los trazos en capas, los rasteriza en las imágenes del grafo, los lee en CPU y los guarda en caché |
| `TrailGenerator` (`scripts/world/trail_generator.gd`) | Hornea el campo, lo mete por nombre en los grafos y aparta la vegetación |
| `tools/build_trail_carve.gd` | Genera `data/graph_functions/trail_carve.tres` (terreno) y `trail_clearance.tres` (vegetación) |
| `planet_biomes.gdshader` (6c) | Pinta la tierra pisada donde pesa la capa de senda, y de lejos con `trail_far.gdshaderinc` |
| `shaders/terrain/trail_far.gdshaderinc` | Lee el campo por píxel: la distancia al eje para dibujarlas de lejos |

`Planet._setup_trails` lo hace todo después de los ríos (las sendas se trazan con los valles ya
tallados y los cruzan por vados) y deja el campo en `Planet.get_trail_network()`.

## Trazado

Sobre el relieve horneado con `bake_sphere_bumpmap` (`routing_size`, 2048×1024: celdas de ~92 m):

1. **Coste por celda:** `1 + slope_cost · pendiente²`; el mar, más allá de `max_latitude` o más
   empinado que `max_slope` no se pisa; un cauce cuesta `ford_cost` veces más (se cruza por vados).
2. **Puntos de paso:** una espiral de Fibonacci con un punto cada `anchor_spacing` m, cada uno movido
   al azar y llevado a la celda más llana de alrededor entre `anchor_min_height` y `anchor_max_height`.
3. **Pares:** el árbol de expansión mínima de los vecinos a menos de `link_radius` × la separación y
   una parte (`loop_fraction`) de los demás, que cierran vueltas.
4. **Caminos:** `AStar3D` (en C++, con las celdas en 3D, así que la distancia sale bien a cualquier
   latitud). Lo pisado pasa a costar `reuse_factor`: las sendas siguientes se juntan con las de antes
   en troncos y ramas en vez de correr paralelas. Un camino que rodea más de `max_detour` veces la
   recta se descarta.
5. **Ramales:** otra espiral, a `spur_spacing`; cada punto a más de `spur_min_distance` de lo ya
   pisado (contando los ramales de antes) se une al punto de paso más cercano. Como lo pisado cuesta
   menos, el camino se arrima a la senda en cuanto puede y sale un ramal que se aparta de ella y
   acaba en el punto. Sin `spur_spacing` no hay ramales.
6. **Trazos:** en cada cruce, los dos brazos más enfrentados siguen de largo como un solo trazo y el
   resto acaba en él. El que pasa de largo se suaviza suelto (`smooth_sigma`, sin codo en el cruce) y
   el que llega se engancha después a él ya suavizado. Lleva un serpenteo suave
   (`meander_amplitude`, `meander_wavelength`) y se remuestrea cada 12 m.

En la Tierra (ramales cada 2000 m, a más de 700 m de la red) salen 282 trazos, 215 de ellos
ramales, con 275 cruces y unos 990 km, en un segundo. Sin ramales eran 124 trazos, 127 cruces y
620 km; con ramales cada 1500 m, 392 cruces y 1180 km, ya una maraña.

## Las imágenes

Una senda mide unos 4 m y un téxel de la imagen, unos 25 (8192×4096 en 30 km de radio). Guardar la
distancia, como los ríos, no vale: el nodo interpola entre téxeles y redondea la uve de la distancia
sobre la línea hasta medio téxel, así que una senda estrecha se borra o cambia de ancho según por
dónde pase. Por capa se guardan tres imágenes R8:

- **U y V:** el vector del téxel al punto más cercano de la senda, al este y al norte. A un lado y al
  otro de la línea apunta en sentidos contrarios y pasa por cero sobre ella, y eso sí se interpola
  bien: milímetros en recta y unos 0,3 m en una curva de 200 m de radio, más la cuantización (0,56 m
  el paso). Su módulo es la distancia al eje.
- **D, la compuerta:** la distancia de siempre. Lejos de la senda U y V valen 0 (el neutro: el nodo
  lee como 0 las zonas constantes), y al interpolar entre un vector de la banda y ese neutro se cruza
  el cero en un lado. Con D por debajo de g0 los cuatro téxeles de alrededor están en la banda y el
  vector vale; pasado g1 no cuenta (`TrailField.params`).
- **Capas:** en un cruce, un téxel a la misma distancia de dos sendas solo puede apuntar a una, y al
  interpolar salen huecos y manchas. Los trazos se parten en trozos (`piece_length`) y los que están a
  menos de `layer_reach` (por defecto 2·g1 + un téxel, unos 90 m) van a capas distintas: en cada
  cruce, el que sigue en una y el que llega en otra. Dos trozos seguidos en capas distintas se tocan
  por la punta y la unión no se nota. El grafo se queda con lo más cercano de todas las capas.
  Con dos capas quedan unos 28 trozos de 2600 sin capa libre (tres sendas a menos de 90 m entre
  sí); con tres (medido sin ramales) no quedaba ninguno, pero los defectos apenas bajaban y costaba
  100 MB más.
- **Puntas:** más allá de la punta de un trazo el vector apuntaría a la punta y se perderían casi
  30 m de senda. En las puntas el vector va a la prolongación de la línea, la que corta es la
  compuerta D y cada punta se recorta g0 para que la senda acabe en su sitio.
- **Poda:** más allá de la compuerta de cada capa, un `Select` da 1000 m sin leer U y V. El módulo
  poda la rama que no elige cuando la condición no cambia en el trozo de imagen que cubre el bloque
  (su rejilla de rangos), que lejos de las sendas es casi siempre. Una compuerta de todas las capas
  en una imagen pequeña no poda nada (cada trozo suyo abarca kilómetros, casi siempre con alguna
  senda dentro) y sale más caro.

Medido contra la geometría exacta alrededor de cruces, puntas y cortes de trozo: el 1,1 % de los
puntos del eje se lee a más de 1,6 m (casi la mitad en los últimos 40 m de las puntas, que con los
ramales son muchas, y luego junto a los cruces) y unos pocos metros cuadrados por cruce se leen como senda sin serlo.

La vegetación apartada por su grafo (los árboles) lee otro juego igual a 4096×2048: ±1 m le basta a
un árbol y compilarlo cuesta cuatro veces menos por generador.

### El factor de SdfSphereHeightmap

El nodo solo lee la imagen cerca de su propia superficie: si `|p| - radio` cae fuera de
`[mín, máx] ± 1,2 · (máx - mín)`, con mín y máx el rango de la imagen por el factor, devuelve la
esfera sin leerla (medido contra el nodo). Con el factor del tamaño de la banda (72) la senda
desaparecía por encima de 86 m de altura. Los nodos llevan factor 1000 (`TrailGenerator.FACTOR`, de
-1200 a 2200 m con imágenes en [0, 1]) y la escala de verdad va en el nodo `trail_scale_*` de detrás.
Los ríos usan el de su alcance (150) en el mapa de distancias, que llega hasta unos 330 m: sus
lechos están todos por debajo del mar, así que no les afecta.

## En el terreno

`trail_carve.tres` va entre los ríos y las cuevas (`earth_terrain_terraces.tres`, nodo 120) y saca:

- **`trail_field`:** la superficie con la senda hundida `dip` m.
- **Capa 14 (`TrailGenerator.TRAIL_LAYER`):** cuánto es senda, con el ancho (`half_width`,
  `edge_softness`) variando por un ruido (`width_variation`, `edge_noise_period`).
- **Capa 13 (`OPEN_LAYER`):** cuánto es suelo libre: 1 fuera de las sendas y 0 sobre ellas.

Las dos solo cerca de la superficie de antes de las cuevas (a menos de 16-24 m): bajo tierra no le
quitan huecos de peso a las menas ni a la profundidad. Ninguna es una mena:
`TrailGenerator.is_trail_layer` (la azada, el pico y la nieve del shader las descartan).

El shader pinta encima del reparto de biomas la textura `texture_index` de las del terreno (la 3, la
tierra pisada) con su calibración (`albedo`). El borde se mezcla con el suelo de alrededor por la
altura de los materiales, como la nieve: la tierra entra primero por los huecos del suelo y lo alto
del suelo asoma en la senda (`edge_blend`, cuánto pesa eso frente al peso liso; `edge_sharpness`, lo
nítido). El peso va por (1 + nitidez), así que en el eje gana siempre la senda y fuera el suelo; con
`edge_softness` 0,7 la Tierra lleva 1,4 m de borde mezclado. El peso llega por vértice, con un metro de resolución a LOD 0 (hasta unos
50-60 m) y dos a LOD 1 (hasta unos 130 m); a LOD 2 hay un vértice cada 4 m y la senda saldría a
trozos, así que la de la malla se apaga entre `fade_start` y `fade_end`.

**De lejos** (`trail_far.gdshaderinc`) entra, en ese mismo tramo, la senda dibujada por píxel: el
shader lee el juego de imágenes de los árboles (4096×2048, subido por `Planet._setup_trail_far_images`
como un `Texture2DArray`) igual que el grafo y `TrailField.distance_at(field, up, "trees")`, y pone la
senda con el ancho y el borde del grafo (`half_width`, `edge_softness`, `width_variation`,
`edge_noise_period`; el ruido del borde es otro). El borde se suaviza al menos lo que mide el píxel,
así que una senda que ya no llena un píxel se aclara en vez de parpadear, y se apaga hacia
`far_distance` (1500 m). No se pinta bajo tierra (en el suelo de una cueva). Medido en la GPU contra
la CPU: 0,045 m de diferencia media; esas imágenes ponen el eje a ±0,5 m (pasos de 1 m), que de
lejos son pocos píxeles. Es solo color: de lejos no se ve el hundido.

Con nieve la senda sigue viéndose, nevada y pisada: sobre ella la nieve cubre `snow_clear` menos
(la mitad) y el contacto por altura de la nieve usa la del material de la senda, así que la tierra
asoma primero por las rodadas. Lo que queda de nieve va teñido de `snow_tint` (más gris y pardo) y
sin destellos.

## Vegetación

`Planet._build_generator`:

- **Lo de malla fina (LOD 0-2: hierba, helechos, matas, flores, ramas, piedras):** el filtro por
  textura del `VoxelInstanceGenerator` en la capa 13 con umbral 0,5. Solo brota donde el suelo es
  libre. No cuesta nada al cargar.
- **Lo que lleva `"trail_clearance"` en su generador (los árboles, LOD 4):** en una malla de 16 m el
  filtro no ve una senda de 4 m. Su grafo de densidad se multiplica por `trail_clearance.tres`: 0
  hasta esos metros del eje y 1 a uno más. Cuesta ~0,14 s por generador al cargar (24 en la Tierra). Las bandas
  lejanas de impostores (más allá de `clearance_max_lod`) no se apartan.
- **`"trail_filter": false`:** lo que no es de superficie (las cuevas). Lo que no tiene grafo de
  densidad (el fondo del mar) no se filtra.

En una partida de antes de las sendas, los bloques que ya se habían editado se cargan del SQLite sin
la capa 13: ahí no brota la vegetación de suelo.

## En el mapa

Las sendas van como líneas encima del mapa grande y del minimapa, no en `world_map.gdshader`: a
unos 92 m por téxel una imagen más saldría borrosa en los 3 km del minimapa. `TrailMap` prepara una
vez los trazos (65 ms, se guardan en el propio campo): simplificados sobre la esfera
(Douglas-Peucker) a 6 m y a 60 m, en trozos de 1,5 km con su centro y su alcance y en tramos de UV
del mapa con su caja, cortados en el antimeridiano. Quedan unos 8000 puntos los finos y 2500 los
gruesos.

- **Mapa grande** (`WorldMapUI._draw_trails`): debajo de rótulos y marcadores. Con más de 40 m por
  píxel usa los gruesos; el grosor crece con el zoom, de 1 a 2,5 px. Solo los tramos cuya caja cae
  en el marco.
- **Minimapa** (`Minimap._draw_trails`): los trozos finos cuyo alcance toca el aro, con la misma
  proyección que el shader y recortados en su borde. Debajo de los marcadores.

Dibujarlas cuesta unos 0,1 ms por fotograma en cualquiera de los dos.

## Caché y costes

`user://maps/<planeta>_trails.bin` (zstd, ~3 MB), con la huella del generador y la configuración de
ríos y sendas en la clave, menos las claves que solo tocan el grafo, la vegetación o el shader
(`TrailGenerator.LOOK_KEYS`: ancho, hundido, texturas, nieve…), que se cambian sin volver a trazar.
Cambiar el grafo del terreno lo rehornea, y también los ríos y el mapa del mundo.

| | |
|---|---|
| Primera carga | 6,1 s (relieve 1,4, red 0,9, imágenes 3,8); con la huella nueva, también los ríos (8 s) |
| Cargas siguientes | caché 0,2 s y compilar el generador 0,8 s; los 24 generadores de árboles, 3,4 s |
| Memoria | ~100 MB las imágenes del terreno, ~50 MB las de los árboles; 48 MB de vídeo las de lejos |
| GPU, sendas de lejos | ~0,02 ms por fotograma con toda la pantalla calculándolas (2560×1440, RTX 4080 SUPER, prueba sintética); en el juego solo el terreno a más de 70 m |
| Generador del terreno (bloques de 16³ en superficie) | +13 % lejos de las sendas, +89 % en los que tienen senda (~1,5 %) |

## Configuración

`trail_settings` en `data/planet/planet_earth.json`. Los tamaños son pares `[ancho, alto]`. La
Tierra lleva sendas más anchas que el valor por defecto (`half_width` 2,1: unos 4,2 m, de 3 a 5,5
con el ruido) y de borde más blando (`edge_softness` 0,7), ramales cada 2000 m a más de 700 m de la
red y los árboles a 4 m del eje (`"trail_clearance"` de cada generador).

| Clave | Por defecto | |
|---|---|---|
| `enabled` | true | |
| `seed` | 1 | Reparto de los puntos de paso y vueltas |
| `routing_size` | 2048×1024 | Rejilla del trazado |
| `field_size`, `tree_field_size` | 8192×4096, 4096×2048 | Imágenes |
| `layers`, `piece_length`, `layer_reach` | 2, 400, 2·g1 + téxel | Capas y trozos |
| `anchor_spacing`, `anchor_min_height`, `anchor_max_height` | 3000, 2, 450 | Puntos de paso (m) |
| `link_radius`, `loop_fraction` | 1,9, 0,2 | Pares |
| `spur_spacing`, `spur_min_distance` | 0 (sin ramales), 600 | Ramales (m) |
| `max_latitude`, `max_slope`, `slope_cost`, `ford_cost`, `shore_margin` | 66, 0,6, 30, 10, 1,5 | Coste |
| `reuse_factor`, `max_detour` | 0,5, 2,2 | Trazado |
| `smooth_sigma`, `meander_amplitude`, `meander_wavelength` | 110, 4, 180 | Forma (m) |
| `half_width`, `edge_softness`, `width_variation`, `edge_noise_period`, `dip` | 1,2, 0,35, 0,3, 30, 0,12 | Senda (m) |
| `clearance_max_lod` | 4 | Hasta qué banda se aparta la vegetación por su grafo |
| `texture_index`, `albedo`, `fade_start`, `fade_end` | -1, —, 70, 130 | Shader |
| `edge_blend`, `edge_sharpness` | 0,7, 0,25 | Borde contra el suelo por altura |
| `snow_clear`, `snow_tint` | 0,5, [0,86, 0,84, 0,81] | La senda en la nieve |
| `far_distance` | 1500 | Hasta dónde se dibujan de lejos (m) |

Tocar `tools/build_trail_carve.gd` pide regenerar los grafos (cambia la huella del generador):

```sh
godot --headless --path . -s tools/build_trail_carve.gd
```

## Consola

`trail` dice a cuántos metros y en qué rumbo (0° = norte, 90° = este) queda la senda más cercana;
`trail tp` deja al jugador de pie sobre ella (`NewGameLanding.surface_radius_at`, la misma búsqueda
del suelo que el aterrizaje de una partida nueva).

## Comprobaciones

```sh
godot --headless --path . res://tests/world/test_trails.tscn
```

Sendas sintéticas (una que pasa de largo, otra que llega en cruce, una curva y una punta suelta) en
el grafo de verdad a 0, 150 y 400 m de altura, la lectura en CPU, la caché, la limpieza de los
árboles y una red trazada sobre un relieve con medio planeta de mar.

## Pendiente

- Velocidad y sonido al pisar la senda (`TrailField.distance_at` ya lee lo mismo que el grafo).

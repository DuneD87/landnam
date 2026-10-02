# Árboles

Pinos, olivos, manzanos y almendros salen del generador **Branching** de la extensión
Tree3D (repositorio `~/ProceduralPlanetItems`, `src/BranchingTree.cpp`). Las palmeras siguen
con el generador de palmera de Tree3D y el impostor en aspa de siempre.

## Generador Branching

Tree3D con `shape = 3`. Sustituye a proctree, que bifurcaba siempre en dos con tubos de
4 lados, ponía un ramillete por punta y regeneraba el árbol con menos niveles en cada LOD
(cada LOD tenía otra estructura).

- **Esqueleto** generado una vez por semilla: tronco (con división en líderes a
  `branch_split_height`), ramas principales repartidas por la copa con la envolvente de
  Weber-Penn (`branch_crown_shape`), y ramas secundarias con filotaxis, curvatura y
  gravitropismo.
- **Tronco** con ensanche de raíz, contrafuertes y lóbulos retorcidos (`branch_gnarl`, olivo);
  las ramas nacen dentro del eje del padre; anillos con transporte paralelo; UV de corteza en
  metros (`branch_bark_tile`).
- **Ramilletes**: tarjetas con la textura de ramita, orientadas hacia fuera de la copa. Sus
  normales se mezclan con las de un elipsoide que envuelve la copa (`branch_crown_normal`).
- **LODs** del mismo esqueleto: menos lados y anillos, ramas finas fuera, y menos tarjetas
  pero más grandes (1 / 0,5 / 0,26 / 0,14 de las tarjetas).

Datos horneados por vértice (los leen `tree_bark`, `tree_foliage` y `tree_wind`):

| Canal | Madera | Tarjeta |
|---|---|---|
| COLOR.r | oclusión (base del tronco, interior de la copa) | oclusión de copa |
| COLOR.g | fase de viento de la rama principal | la de su rama |
| COLOR.b | peso de rama (0 tronco, 1 puntas) | el de su rama + su largo |
| COLOR.a | 1 | aleatorio por tarjeta en [0, 0,9) |
| UV2.x | (altura / altura del árbol)² | igual |
| UV2.y | nivel / 2 | posición a lo largo de la tarjeta |

## Presets y herramientas

Los parámetros de cada especie y variante están en `tools/vegetation/tree_presets.gd`.
Flujo al cambiar un árbol:

1. Iterar con `tests/vegetation/tree_designer.tscn -- --tag=x [--only=olive_01]`: hoja por
   árbol con LOD0 a mediodía y a contraluz, vista bajo la copa y LOD1-3, y los triángulos.
2. Escribir los presets en las escenas:
   `godot --headless --path . -s res://tools/vegetation/apply_tree_presets.gd`.
3. Rehornear los impostores (necesita renderer):
   `godot --path . res://tools/vegetation/bake_tree_impostors.tscn`. Todos son caducos y
   hornean además el atlas sin hoja del invierno ([seasons.md](seasons.md)).
4. Si se ha tocado el C++: `scons platform=linux target=template_debug` en
   `~/ProceduralPlanetItems` y copiar `demo/addons/Tree3D/libTree3D.linux.template_debug.x86_64.so`
   a `addons/Tree3D/`. La DLL de Windows del repositorio no se ha recompilado.

`height_m: [min, max]` en `planet_earth.json` fija la altura real de cada item (planet.gd la
convierte en escala a partir de su LOD0): pinos 11-19 m, olivos 4-7 m, manzanos 4-7,5 m,
almendros 5-8 m, palmeras 8-15 m. La escala común de 2,5 a 7,5 del generador dejaba pinos de
90 m y olivos de 22 m.

## Distribución

`tree_generator_green` emite por área (0,007 árboles/m², `lod_density_falloff` 1) con manchas
de ruido que forman bosquetes y claros (`threshold` 0,25). Antes emitía por vértices en la
banda 4: filas regulares y, con el `lod_density_falloff` por defecto, 16 veces menos
densidad de la que decía el JSON. Con 0,01 el sotobosque quedaba cerrado (a ras de suelo la
cámara acababa dentro de una copa en cualquier dirección) y costaba ~6 fps más corriendo a
2560×1440; con 0,007 hay troncos, claros y cielo entre las copas, y desde arriba la cubierta
sigue cerrada.

Almendros y manzanos no salen de él sino de sus bosquetes (`tree_generator_almond_grove`,
`tree_generator_apple_grove`): pocas manchas de ~80 m con 0,009 árboles/m² por variante, cada especie
con su semilla de ruido, para que en flor se lean como cúmulos ([seasons.md](seasons.md)).

## LODs y relevo al impostor

`"tree_lods": {}` en el item activa `Planet._register_tree_item`. Cada árbol se registra
**una sola vez**, en la banda 4 del instancer, con el impostor octaédrico, la colisión, la
tala y los posaderos. El instancer crea un `VoxelInstancerRigidBody` por árbol a menos de
`collision_distance_m` (160 m) con el transform exacto de la instancia, y
`TreeDetailRenderer` (`scripts/planet/tree_detail_renderer.gd`) dibuja la geometría en esas
mismas posiciones. El instancer crea cuerpos en todo bloque cuyo punto más cercano esté a
menos de `collision_distance_m` (200 m), así que todos los árboles hasta el relevo tienen
cuerpo y geometría:

| Distancia al árbol | Malla | Fundido |
|---|---|---|
| < 30 m | LOD0 | 28-32 m |
| 30-57 m | LOD1 | 55-59 m |
| 57-150 m | LOD2 | 140-155 m |
| > 150 m | impostor | hasta ~768 m |

Cada relevo es un tramado complementario sobre **el mismo árbol** (`tree_band_fades` /
`tree_band_discard`): el que sale y el que entra se reparten los píxeles, sin huecos ni
solapes. Antes había una banda cercana aparte y el instancer genera posiciones distintas
en cada item (su semilla lleva el id), así que en el relevo unos árboles se desvanecían y
aparecían otros; además el LOD se elegía por centro de bloque.

`TreeDetailRenderer` indexa los cuerpos en `TreeInstanceIndex` (C++, extensión Tree3D) y,
cuando la cámara se mueve 3 m, reparte los árboles cercanos en MultiMesh por celda y LOD
(32 m; 64 m para el LOD2, que tiene la mayoría de los árboles) con 4 m de margen, y sube
solo las celdas que cambian, repartidas entre fotogramas (0,35 ms por fotograma, nunca en el
del reparto). Peor fotograma medido paseando y volando por el bosque: ~1 ms de CPU, cada 3 m.

Ajuste al suelo: las instancias salen sobre la malla del LOD 4, que cerca de la cámara se
separa del terreno que se dibuja (LOD 0) entre −1,6 y +1,6 m. Los generadores de árboles
activan `snap_to_generator_sdf` (`"snap_to_sdf"` en el JSON, 4 m de búsqueda): medido en el
bosque, la base queda entre −0,6 y −0,05 m (los 0,4 m de hundimiento previstos).

El renderizador tiene la interpolación física desactivada (el proyecto la activa): un
MultiMesh interpolado mezcla cada instancia con la del mismo índice en el buffer anterior y,
al rehacer una celda, cada índice pasa a ser otro árbol. Se veía como parpadeo: árboles de
otros tamaños a medio camino entre dos árboles durante un fotograma.

Más allá, items solo de impostores en las bandas 5 y 6 (`_register_far_tree_item`, sin
colisión, tala ni sombra) llevan el bosque hasta ~2,2 km. La banda 4 oculta bloques de 256 m
enteros por la distancia a su centro (su borde era escalonado entre ~550 y ~950 m), así que
cada banda se desvanece árbol a árbol antes de que le falte ningún bloque
(`_tree_band_reach`: alcance menos media diagonal del bloque) y la siguiente entra en el mismo
tramo con el tramado complementario: 506-546 m (4 → 5), 1.053-1.093 m (5 → 6) y final en
2.145-2.185 m, con borde redondo. Sus árboles están en otras posiciones (la semilla lleva el
id del item), pero a 500 m cada árbol son unos pocos píxeles.

- La búsqueda de `snap_to_sdf` se dobla en cada banda: su malla se separa el doble del SDF.
- Se registran después de toda la vegetación (`_register_far_tree_items`). Intercalados
  desplazaban los ids de los items siguientes, y con ellos las posiciones de todos los
  árboles; con ids fuera de la secuencia (10000+) el instancer no generaba ninguno.
- `"tree_lods": {"far_bands": N, "far_density": [..]}`: número de bandas lejanas (2 por
  defecto, 0 las quita) y densidad de cada una respecto al bosque (con menos densidad los
  árboles crecen para cubrir lo mismo).
- Coste: ~0,7 ms de GPU con la banda 6 a 2560×1440 (unos 5 fps quieto, 1-3 en movimiento);
  la banda 4 deja de proyectar sombra desde 546 m. La caja de la banda 6 llega hasta la
  cámara: ~390.000 instancias, casi todas colapsadas fuera de su tramo.
- El bosque solo crece hasta 125 m de altura (`max_height` de `tree_generator_green`): las
  laderas altas lejanas quedan sin árboles.

Un solo item por árbol en la banda 4 no es "solo lejos": el instancer genera sus instancias
en los bloques de LOD 4, que llegan hasta la cámara, así que los mismos árboles existen en
todos los anillos y solo cambia la malla con la que se dibujan.

Para que el impostor tenga el mismo tono que la geometría (medido en la misma vista con
`tree_walk_capture --tone`: ±3 % de color medio a mediodía y al atardecer):

- Texturas de ramita con el color de las zonas transparentes rellenado
  (`tools/vegetation/fill_transparent_color.py`). Tenían negro donde alfa = 0 y Godot solo
  rellena unos píxeles junto al borde: los mipmaps pequeños, que usan el horneado y la
  geometría lejana, salían un ~35 % más oscuros.
- En `fragment()`, `MODEL_MATRIX` de un MultiMesh no incluye el transform de la instancia:
  el impostor recibe la base de cada árbol por varyings para girar las normales del atlas.
  Sin ello la copa se iluminaba como si mirase a la cámara.
- La misma función de luz que el follaje y sombra completa del impostor.

Además: las tarjetas del LOD2 miran más hacia fuera,
conservan el 32 % de tarjetas y los planos cruzados; el impostor no hornea la oclusión en
el color (el shader ya la aplica) y oscurece la corteza, que en la geometría queda a la
sombra de la copa.

En el pase de sombras se descarta una fracción de tarjetas (70 % se quedan cerca, 25 % desde
100 m) y las ramas secundarias a más de 12 m (`tree_shadow_skip`).

Desde el LOD2 (55-59 m) la sombra la proyecta el impostor, un quad visto desde la luz, y la
geometría del LOD2 no proyecta (`TreeDetailRenderer.SHADOW_LODS`, `shadow_fade_in_*` del
impostor, con el mismo tramado con que sale la sombra del LOD1). Sus ~4.400 árboles eran
12 M de primitivas en las cascadas y ~0,6 ms de GPU; en la misma vista elevada con sol bajo
no se distingue. Llevar también el LOD1 al impostor solo ahorraba ~0,1 ms más.

## Impostores octaédricos

`TreeOctaImpostor` (`scripts/planet/tree_octa_impostor.gd`): 8×8 vistas del hemisferio
superior de 192 px (horneadas a 384 px) en dos atlas por árbol,
`textures/planet/vegetation/tree/impostors/<escena>_albedo.png` (color, cobertura) y
`_normal.png` (normal de copa octaédrica en RG, oclusión en B; importado sin compresión de
normal map). El shader `tree_octa_impostor` orienta un quad hacia la cámara (hacia la luz en
el pase de sombras), mezcla las cuatro vistas vecinas y se ilumina con el sol real con el
mismo modelo que el follaje, así que el bosque lejano cambia con la hora como el cercano.

## Shaders

- `vegetation/tree_bark`: corteza con normal y rugosidad, oclusión horneada, musgo en caras al
  cielo y en la base, variación de tono por árbol.
- `vegetation/tree_foliage` (`lib/tree_foliage_body`): doble cara en todos los LODs (muchas
  tarjetas miran arriba y, con una cara, la copa se vaciaba vista de lado), difuso envolvente,
  transmisión que atraviesa en parte la sombra de la copa, oclusión de copa también sobre el
  sol directo.
- `lib/tree_wind`: inclinación del tronco, oscilación por rama principal (ramas y tarjetas
  comparten fase) y aleteo de tarjetas; relevo de bandas; pase de sombras aligerado.

## Coste medido

GPU, RTX 4080 SUPER, Godot 4.6 Forward+.

Moviéndose por el juego, 2560×1440, mismo recorrido en la versión anterior a los árboles
Branching (8d1d984) y en esta: andando 122 → 122 fps, corriendo 101 → 98, volando 87 → 78
(con 0,01 árboles/m² y la hierba hasta 184 m: 119, 91 y 75). Menos árboles dejan más hierba
a la vista: la banda lejana de la hierba era lo más caro de la vegetación (docs/grass_lods.md).
Lo que queda es sobre todo el pre-pase de profundidad (+0,6-0,8 ms: tarjetas con recorte
alfa y MSAA 2x, con ~10 veces más árboles cerca por los bosquetes) y ~0,25 ms de CPU de
render por ~1.000 draw calls más. Los ~11.000 cuerpos del instancer están congelados (0
activos en la física). Moverse cuesta +3,5-4 ms sobre estar quieto en las dos versiones
(streaming del terreno); no viene del detalle de árboles.

Juego (`tests/lighting/lighting_capture.tscn --views=forest --times=noon --perf`, 1920×1080,
misma vista que antes del cambio, aún con 0,01 árboles/m²): fotograma 5,1-5,4 ms antes y 5,9 ms después, con unas
cuatro veces más árboles en el bosque y la geometría hasta 150 m (con el relevo a 90 m eran
5,3 ms). Vegetación del planeta (fotograma menos el mismo con el instancer y el detalle
ocultos): 1,17 → 1,79 ms.

Bosque plano de prueba (`tests/vegetation/tree_quality_preview.tscn -- --perf`, 2560×1440, solo
árboles, sin máscara de bioma: bosque en el ~70 % del terreno hasta el horizonte):

| Vista | Antes (29.052 árboles) | Después (288.029 árboles) |
|---|---:|---:|
| A ras de suelo | 1,30 ms | 2,17 ms |
| Elevada (25 m) | 1,36 ms | 1,29 ms |
| Alta (90 m) | 1,05 ms | 0,50 ms |

Descartado: tarjetas con un polígono de 8 lados ajustado al alfa. Quitaban un 20 % de
píxeles pero costaban 0,4 ms más en el bosque: el coste está en los vértices de miles de
tarjetas, no en los píxeles.

## Pruebas

`tests/vegetation/test_trees.gd` (headless): forma, presupuesto de triángulos por LOD,
silueta estable, datos por vértice, normales de copa, atlas presentes, registro en una sola
banda y fundidos encadenados LOD0 → LOD1 → LOD2 → impostor. Capturas de comparación:
`tree_quality_preview.tscn` (`--capture`, `--lineup` con figura de 1,8 m, `--relay` con el
LOD2 junto al impostor a 110 m y un recorrido cruzando el relevo) en `build/tree_quality/`.

`tree_walk_capture.tscn` recorre el bosque del juego real en PLAYING (con el origen flotante
activo) y guarda fotogramas en `build/tree_walk/`. En cada uno imprime `DIAG`: árboles a
menos de 88 m sin geometría (`missing`), geometría sin árbol (`ghosts`) y cuerpos que se han
movido; los tres deben ser 0. `EVENTS` lista los cuerpos que el instancer crea y destruye.

## Texturas de corteza

CC0 de Poly Haven (polyhaven.com), 1k, color, normal (OpenGL) y rugosidad: `pine_bark`
(pino), `tree_bark_03` (olivo), `trident_maple_bark` (manzano) y `jolcham_oak_bark_01`
(almendro), en `textures/planet/vegetation/tree/trunk/bark_<especie>_*.jpg`.

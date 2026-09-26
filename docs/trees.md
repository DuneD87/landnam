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
   `godot --path . res://tools/vegetation/bake_tree_impostors.tscn`.
4. Si se ha tocado el C++: `scons platform=linux target=template_debug` en
   `~/ProceduralPlanetItems` y copiar `demo/addons/Tree3D/libTree3D.linux.template_debug.x86_64.so`
   a `addons/Tree3D/`. La DLL de Windows del repositorio no se ha recompilado.

`height_m: [min, max]` en `planet_earth.json` fija la altura real de cada item (planet.gd la
convierte en escala a partir de su LOD0): pinos 11-19 m, olivos 4-7 m, manzanos 4-7,5 m,
almendros 5-8 m, palmeras 8-15 m. La escala común de 2,5 a 7,5 del generador dejaba pinos de
90 m y olivos de 22 m.

## Distribución

`tree_generator_green` emite por área (0,01 árboles/m², `lod_density_falloff` 1) con manchas
de ruido que forman bosquetes y claros (`threshold` 0,25). Antes emitía por vértices en la
banda 4: filas regulares y, con el `lod_density_falloff` por defecto, 16 veces menos
densidad de la que decía el JSON.

## LODs y relevo al impostor

`"tree_lods": {}` en el item activa `Planet._register_tree_item`. Cada árbol se registra
**una sola vez**, en la banda 4 del instancer, con el impostor octaédrico, la colisión, la
tala y los posaderos. El instancer crea un `VoxelInstancerRigidBody` por árbol a menos de
`collision_distance_m` (160 m) con el transform exacto de la instancia, y
`TreeDetailRenderer` (`scripts/planet/tree_detail_renderer.gd`) dibuja la geometría en esas
mismas posiciones:

| Distancia al árbol | Malla | Fundido |
|---|---|---|
| < 30 m | LOD0 | 28-32 m |
| 30-57 m | LOD1 | 55-59 m |
| 57-92 m | LOD2 | 90-95 m |
| > 92 m | impostor | hasta ~768 m |

Cada relevo es un tramado complementario sobre **el mismo árbol** (`tree_band_fades` /
`tree_band_discard`): el que sale y el que entra se reparten los píxeles, sin huecos ni
solapes. Antes había una banda cercana aparte y el instancer genera posiciones distintas
en cada item (su semilla lleva el id), así que en el relevo unos árboles se desvanecían y
aparecían otros; además el LOD se elegía por centro de bloque.

`TreeDetailRenderer` indexa los cuerpos en `TreeInstanceIndex` (C++, extensión Tree3D) y,
cuando la cámara se mueve 2 m, reparte los árboles cercanos en MultiMesh por celda de 32 m
y LOD (con uno solo por LOD, Godot no recortaba nada) y sube solo las celdas que cambian.
Coste de CPU: ~0,4-0,7 ms por reparto en el bosque de prueba (9.800 cuerpos), 0,65 ms en el
juego a ras de suelo.

Para que el LOD2 y el impostor se parezcan: las tarjetas del LOD2 miran más hacia fuera,
conservan el 32 % de tarjetas y los planos cruzados; el impostor no hornea la oclusión en
el color (el shader ya la aplica) y oscurece la corteza, que en la geometría queda a la
sombra de la copa.

En el pase de sombras se descarta una fracción de tarjetas (70 % se quedan cerca, 25 % desde
100 m) y las ramas secundarias a más de 12 m (`tree_shadow_skip`).

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

Juego (`tests/lighting/lighting_capture.tscn --views=forest --times=noon --perf`, 1920×1080,
misma vista que antes del cambio): fotograma 5,1-5,4 ms antes y 5,34 ms después, con unas
cuatro veces más árboles en el bosque. Vegetación del planeta (fotograma menos el mismo con
el instancer y el detalle ocultos): 1,17 → 1,29 ms.

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

## Texturas de corteza

CC0 de Poly Haven (polyhaven.com), 1k, color, normal (OpenGL) y rugosidad: `pine_bark`
(pino), `tree_bark_03` (olivo), `trident_maple_bark` (manzano) y `jolcham_oak_bark_01`
(almendro), en `textures/planet/vegetation/tree/trunk/bark_<especie>_*.jpg`.

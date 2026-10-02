# Sotobosque estilizado

Ocho prefabs en `scenes/planet/planet_items/vegetation/understory/`.
Se añaden al final de los items terrestres de `planet_earth.json`, conservando
los identificadores de registro de las rocas, árboles, hierba y plantas existentes.
Son decoración: no crean nodos, colisiones ni objetos recolectables por instancia.

| Especie | Prefab | Densidad nominal/m² | LOD0 | LOD1 | LOD2 | LOD3 |
|---|---|---:|---:|---:|---:|---:|
| Helecho de bosque | wood_fern | 0,035 | 2886 | 1103 | 557 | 167 |
| Helecho alto | royal_fern | 0,015 | 2028 | 848 | 475 | 138 |
| Arbusto redondo | round_shrub | 0,016 | 4473 | 1041 | 507 | 135 |
| Arbusto de hoja larga | willow_shrub | 0,008 | 2530 | 1480 | 309 | 87 |
| Arbusto florido | flowering_shrub | 0,020 | 4323 | 967 | 504 | 160 |
| Esparraguera | wild_asparagus | 0,020 | 3018 | 1012 | 309 | 187 |
| Planta de hojas anchas | broadleaf | 0,023 | 554 | 264 | 156 | 32 |
| Flores silvestres | wildflowers | 0,030 | 792 | 486 | 270 | 90 |

Las columnas de LOD cuentan triángulos por planta. Las densidades son anteriores
a los filtros de ruido, bioma, altura y pendiente; no son una cuenta final de
plantas por metro cuadrado.

## Modelo y material

`scripts/planet/understory_geometry.gd` construye hojas curvas con pliegue,
tallos y pétalos opacos, sin texturas ni recortes alfa. Los helechos tienen
frondes con pares de hojuelas algo arqueadas; las esparragueras tienen tallos,
ramillos y hojas finas.

- **Arbusto redondo y florido**: seis tallos leñosos abiertos desde la base, con dos
  ramas cada uno, y 62 grupos de seis hojas pequeñas repartidos en espiral sobre un
  domo, en una capa exterior y otra interior. Las ramillas asoman desde dentro de la
  copa. El florido lleva racimos de cinco flores de cuatro pétalos en los brotes altos.
- **Sauce arbustivo**: varas largas con hojas estrechas que salen hacia arriba y
  cuelgan en la punta.
- **Hojas anchas**: roseta de trece hojas, las exteriores más viejas, grandes,
  oscuras y caídas; las del centro, tiernas y erguidas. Cuatro tramos de curva en
  LOD0.

Cada especie define su copa como un elipsoide. Las hojas se orientan hacia fuera de
la copa y sus normales se mezclan con la normal del elipsoide (0,2 en flores, 0,75
en los arbustos redondos): la mata se ilumina como un volumen y no como facetas
sueltas. Esa normal nunca apunta hacia abajo y se inclina hacia el cielo: las hojas
bajas y tumbadas quedaban de espaldas a la luz y salían negras. El material activa `volume_normal_both_faces`, para que el envés use la
misma normal; con el volteo normal de Godot, una hoja vista por detrás recibía una
normal hacia el interior y salía casi negra. El interior y la base de la copa se
oscurecen en el color de vértice, y cada rama o fronde tiene su propio tono. La luz
ambiental del material sube de 0,08 a 0,14; las zonas secas, las hojas muertas y el
brillo de ráfaga de la hierba no se aplican (o muy atenuados) al sotobosque.

La construcción es determinista y se cachea por especie. En la máquina de prueba
tarda aproximadamente 1–15 ms por especie, una vez por proceso.
`understory_mesh.gd` permite ver cada prefab en el editor y entrega los cuatro
LODs al cargador del planeta sin necesitar que el nodo entre en el árbol.

Se reutiliza `grass_wind.gdshader`, activando `use_vertex_color` para distinguir
hojas, ramas y pétalos dentro de una sola superficie/material. Esta opción queda
desactivada por defecto en la hierba existente. Los colores de vértice se
convierten a lineal al construir la malla; los uniforms siguen usando
`source_color`.

UV contiene la transversal y semilla por hoja; UV2 codifica altura normalizada
de la planta y la marca de geometría refinada. `CUSTOM0` lleva los datos del morph
de LOD, como en la hierba: desplazamiento respecto al eje de cada hoja o tallo y
`4 · LOD de la malla + último LOD de la pieza`. El viento mantiene la raíz fija
y aumenta la flexión hacia arriba. Los materiales reciben la dirección del sol,
posición del planeta y viento/clima por la misma ruta que la hierba.

## LODs

Cada hoja tiene un nivel: el último LOD en el que sigue. En los arbustos redondos,
las dos primeras hojas de cada grupo heredan el nivel del grupo y las exteriores
duran más, porque son las que dibujan la silueta. Las demás caen en los LODs
cercanos. Los tallos finos solo llegan a LOD1 y las ramillas de la copa, a LOD0.
Una hoja de un solo tramo es un triángulo con la base en su parte ancha.

Las supervivientes se ensanchan ×1,23 por nivel (`WIDTH_GROWTH`), el mismo factor
que usa el morph del shader: las hojas que desaparecen se estrechan hasta cero y el
resto se ensancha de forma continua con la distancia (ventanas de 14→20, 30→42 y
48→64 m). No se generan impostores de imagen.

## Distribución y distancia

Cada especie tiene un generador por superficie (`EMIT_FROM_FACES`), con ruido 3D,
semilla propia y variación de escala. Los helechos, arbustos verdes, hojas anchas
y flores usan la máscara verde; el arbusto florido y la esparraguera usan la
transición verde/arena. Es una distribución de bioma, no una detección de sombra
de árboles ni una simulación de humedad.

Los límites inferiores están entre -35 y -20 m respecto al radio del planeta,
por encima del mar actual (radio - 50 m). La pendiente máxima es de 32 grados.
Los límites superiores y densidades se ajustan en los generadores del JSON.

Cada especie se registra en las bandas de terreno 0, 1 y 2 mediante
`understory_lods`, con el mismo relevo encadenado que la hierba (ver
`grass_lods.md`): banda 0 hasta 40 m, banda 1 de 28 a 88 m y banda 2 de 64 a
176 m. Como el último morph termina a 64 m, la banda 2 solo registra LOD3 y
los bloques ocultos por su relevo usan una malla vacía.

## Comprobación

Con el ejecutable de Godot que contiene Voxel Tools:

```sh
godot --headless --path . --script res://tests/vegetation/test_understory.gd
godot --headless --path . --script res://tests/vegetation/test_grass_instancer.gd
godot --path . res://tests/vegetation/understory_preview.tscn -- --capture
godot --path . res://tests/vegetation/grass_lod_preview.tscn -- --capture --understory
```

Los tests verifican mallas y caché de las ocho especies, índices, normales,
triángulos no degenerados y orientados, UVs, colores, datos de morph,
presupuestos, prefabs, máscaras de bioma, registro de 24 bandas, materiales y
relevos encadenados. Terminan con cero fallos.

La galería guarda catálogo, los cuatro niveles de detalle, un primer plano de
helechos y una composición mixta de día y a contraluz en `build/understory/`.
La prueba nativa usa las densidades y escalas del JSON con un terreno plano:
desactiva las máscaras de bioma para hacer visibles todas las especies y
mantiene el ruido de grupos. Guarda vistas cercanas, elevadas y un recorrido.
El coste medido junto con la hierba está en `grass_lods.md`.

Para ver las incorporaciones en una partida abierta, recargar la escena del
planeta: los items y mallas se registran durante la carga.

## Estaciones

Cada pieza lleva su tipo en `COLOR.a` (hoja, tallo o flor) y cada especie su comportamiento en
`SEASONS` de `understory_geometry.gd`: las herbáceas se agostan, los arbustos caducos cambian de
color y pierden la hoja, y las flores se abren en su ventana. En primavera florecen el arbusto
redondo (amarillo), el florido (más racimos rosas), el sauce (amentos) y la hoja ancha (espigas);
las flores se generan al final de cada especie para no cambiar la forma de la mata. Ver
[seasons.md](seasons.md).

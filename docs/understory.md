# Sotobosque estilizado

Ocho prefabs nuevos en `scenes/planet/planet_items/vegetation/understory/`.
Se añaden al final de los items terrestres de `planet_earth.json`, conservando
los identificadores de registro de las rocas, árboles, hierba y plantas existentes.
Son decoración: no crean nodos, colisiones ni objetos recolectables por instancia.

| Especie | Prefab | Densidad nominal/m² | LOD0 | LOD1 | LOD2 | LOD3 |
|---|---|---:|---:|---:|---:|---:|
| Helecho de bosque | wood_fern | 0,035 | 2844 | 1101 | 584 | 166 |
| Helecho alto | royal_fern | 0,015 | 2042 | 853 | 454 | 137 |
| Arbusto redondo | round_shrub | 0,013 | 3146 | 1674 | 360 | 102 |
| Arbusto de hoja larga | willow_shrub | 0,008 | 2662 | 1422 | 315 | 88 |
| Arbusto florido | flowering_shrub | 0,010 | 3566 | 1956 | 501 | 147 |
| Esparraguera | wild_asparagus | 0,020 | 3198 | 1022 | 311 | 201 |
| Planta de hojas anchas | broadleaf | 0,023 | 234 | 132 | 96 | 32 |
| Flores silvestres | wildflowers | 0,030 | 792 | 486 | 270 | 90 |

Las columnas de LOD cuentan triángulos por planta. Las densidades son anteriores
a los filtros de ruido, bioma, altura y pendiente; no son una cuenta final de
plantas por metro cuadrado.

## Modelo y material

`scripts/planet/understory_geometry.gd` construye hojas curvas con pliegue,
tallos y pétalos opacos, sin texturas ni recortes alfa. Los helechos tienen
frondes con pares de hojuelas; las esparragueras tienen tallos, ramillos y hojas
finas. Los arbustos varían su altura, forma de hoja y floración. Las flores
mezclan crema y lavanda en una paleta suave.

La construcción es determinista y se cachea por especie. En la máquina de
prueba tarda aproximadamente 0,7–10 ms por especie, una vez por proceso.
`understory_mesh.gd` permite ver cada prefab en el editor y entrega los cuatro
LODs al cargador del planeta sin necesitar que el nodo entre en el árbol.

Se reutiliza `grass_wind.gdshader`, activando `use_vertex_color` para distinguir
hojas, ramas y pétalos dentro de una sola superficie/material. Esta opción queda
desactivada por defecto en la hierba existente. Los colores de vértice se
convierten a lineal al construir la malla; los uniforms siguen usando
`source_color`.

UV contiene la transversal y semilla por hoja; UV2 codifica altura normalizada
de la planta y la marca de geometría refinada. El viento mantiene la raíz fija
y aumenta la flexión hacia arriba. Los materiales reciben la dirección del sol,
posición del planeta y viento/clima por la misma ruta que la hierba.

## Distribución y distancia

Cada especie tiene un generador por superficie (`EMIT_FROM_FACES`), con ruido 3D,
semilla propia y variación de escala. Los helechos, arbustos verdes, hojas anchas
y flores usan la máscara verde; el arbusto florido y la esparraguera usan la
transición verde/arena. Es una distribución de bioma, no una detección de sombra
de árboles ni una simulación de humedad.

Los límites inferiores están entre -35 y -20 m respecto al radio del planeta,
por encima del mar actual (radio - 50 m). La pendiente máxima es de 32 grados.
Los límites superiores y densidades se ajustan en los generadores del JSON.

Cada especie se registra en bandas de terreno 0/1 y 2 mediante
`understory_lods`. Las bandas comparten el relevo de la hierba: 64–88 m con la
configuración actual; la última desaparece entre 152 y 176 m. Las mallas cambian
a 24/55/100 m, medidos por el centro de cada bloque del instancer.

Los LODs conservan hojas terminales y subconjuntos estables del resto, ensanchando
las hojas supervivientes. Reducen segmentos y eliminan ramitas finas; el último
representa los tallos mediante cintas. No se generan impostores de imagen.

## Comprobación

Con el ejecutable de Godot que contiene Voxel Tools:

```sh
godot --headless --path . --script res://tests/vegetation/test_understory.gd
godot --headless --path . --script res://tests/vegetation/test_grass_instancer.gd
godot --path . res://tests/vegetation/understory_preview.tscn -- --capture
godot --path . res://tests/vegetation/grass_lod_preview.tscn -- --capture --understory
```

Los tests verifican mallas y caché de las ocho especies, índices, normales,
triángulos no degenerados, UVs, colores, presupuestos, prefabs, máscaras de bioma,
registro de 24 bandas, materiales y coordinación de transiciones. Terminaron
con cero fallos; la integración de hierba también sigue pasando.

La galería guarda catálogo, los cuatro niveles de detalle, un primer plano de
helechos y una composición mixta de día y a contraluz en `build/understory/`.
La prueba nativa usa las densidades y escalas del JSON con un terreno plano:
desactiva las máscaras de bioma para hacer visibles todas las especies y
mantiene el ruido de grupos. Guarda vistas cercanas, elevadas y un recorrido.

Renderizado con Godot 4.6 Forward+ / RTX 4080 SUPER. No se detectaron errores
nuevos de shader ni scripts. El proyecto conserva los avisos previos del plugin
de Git ausente, dos audios no encontrados y recursos retenidos al salir.
La prueba plana no reproduce el relieve ni la atmósfera completa del planeta.

Para ver las incorporaciones en una partida abierta, recargar la escena del
planeta: los items y mallas se registran durante la carga.

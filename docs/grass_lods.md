# Hierba con LODs geométricos

La hierba terrestre del planeta usa hojas del modelo original a todas las distancias
en las que se dibuja. Las tres variantes (`low_poly_grass`, `green_yellow`, `yellow`)
ya no activan `grass_patch`: no se hornea una imagen de la mata para LOD2/LOD3.

`scripts/planet/grass_geometry_lods.gd` separa las 64 hojas del asset por conectividad
y construye una selección anidada de hojas, repartida por las puntas de la mata.
Conserva la hoja más alta y distribuye las demás por su silueta. Los niveles son:

| Mesh LOD | Hojas | Vértices | Triángulos | Forma |
|---|---:|---:|---:|---|
| 0 | 64 | 390 | 262 | Arrays originales, sin simplificación automática adicional |
| 1 | 32 | 202 | 138 | Hojas originales, anchura ×1,45 |
| 2 | 16 | 80 | 48 | Dos segmentos siguiendo la hoja, anchura ×2 |
| 3 | 8 | 24 | 8 | Un triángulo por hoja, anchura ×2,8 |

Las anchuras compensan parte de la pérdida de cobertura sin aumentar la altura de
la mata. Todos los niveles heredan el material de su variante y el mismo shader de
viento. Una mezcla moderada de las normales hacia la vertical planetaria suaviza
el contraste lejano entre hojas, desde 95 hasta 240 m; no afecta al modelo cercano.

## Distribución y transiciones

Los items se configuran en `data/planet/planet_earth.json` mediante `grass_lods`:

- `layer: "near"`: conserva los generadores cercanos y las bandas de terreno 0/1.
- `layer: "far"`: usa las bandas 2/3 y los generadores `grass_far_generator_*`.
- `fade_width_m: 24`: anchura de relevo entre capas de instancias.
- `max_distance_m: 320`: límite de la capa lejana, acotado también por el alcance
  de la banda del terreno. El último tramo se encoge progresivamente.
- `mesh_lod_distances_m: [40, 95, 180]`: distancias de selección de malla por bloque.

La distribución lejana es por superficie (`EMIT_FROM_FACES`) y no por vértice del
terreno. Así no pierde un factor de cuatro en densidad cuando se simplifica el
terreno. Las densidades lejanas iniciales son 0,6 / 0,006 / 0,003 matas por m² para
verde / verde-amarillo / amarillo, antes de aplicar las máscaras de bioma.
Las escalas coinciden con las variantes cercanas.

Cada banda tiene un material propio. La entrada de una banda coincide con la
salida de la anterior; el encogimiento usa raíz cuadrada para compensar que cambian
alto y ancho. Con `lod_distance=48`, los relevos son 64–88 y 152–176 m; el último
desvanecido es 296–320 m. El código deriva los alcances del terreno al cargar.

`VoxelInstancer` selecciona las mallas por distancia al **centro del bloque**, por
lo que los 40/95/180 m no son fronteras exactas por mata. Las capas lejanas también
dependen de la precisión del terreno de su banda; todavía hay que valorar en el
planeta real las pendientes y los cambios bruscos de relieve.

## Validación

Con el ejecutable personalizado de Godot que contiene Voxel Tools:

```sh
godot --headless --path . --script res://tests/vegetation/test_grass_geometry_lods.gd
godot --headless --path . --script res://tests/vegetation/test_grass_instancer.gd
godot --path . res://tests/vegetation/grass_lod_preview.tscn -- --capture
```

Las pruebas comprueban los tres assets, conservación de LOD0 y altura, normales e
índices válidos, presupuesto geométrico, registro de las 12 bandas en el instancer,
materiales, viento y coordinación de los rangos de relevo.

La escena gráfica usa el VoxelInstancer real sobre un terreno plano, con las
densidades, escalas y LODs del planeta para la variante verde. Desactiva las máscaras
de bioma para llenar el terreno de prueba. Guarda capturas a ras de suelo, elevadas
y durante un recorrido en `build/grass_lods/`. Sin `--capture`, permite recorrer la
pradera con WASD, subir/bajar con E/Q y acelerar con Shift.

Validado con Godot 4.6, Forward+, MSAA 2× y RTX 4080 SUPER a 1280×720. En la vista
elevada, el contador de primitivas de la escena pasó de 88.671.054 con todas las
mallas en LOD0 a 5.366.408 con los LODs activados (aproximadamente un 94 % menos).
Es una comparación de carga geométrica con idéntica distribución, no una medición
de FPS del juego completo ni una comparación con las tarjetas antiguas.

El arranque del proyecto presenta avisos previos del complemento de Git ausente,
dos audios no encontrados y recursos retenidos por autoloads al salir. La prueba
gráfica no produjo errores nuevos de compilación de los shaders de hierba.

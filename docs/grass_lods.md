# Hierba con LODs geométricos

La hierba terrestre del planeta usa hojas geométricas a todas las distancias
en las que se dibuja. Las tres variantes (`low_poly_grass`, `green_yellow`, `yellow`)
ya no activan `grass_patch`: no se hornea una imagen de la mata para LOD2/LOD3.

`scripts/planet/grass_geometry_lods.gd` separa las 64 hojas del asset por conectividad
y construye una selección anidada de hojas, repartida por las puntas de la mata.
Conserva las raíces y puntas de referencia, reconstruye cada hoja como una cinta
Bézier y distribuye los niveles por su silueta. La sección se ensancha tras el
arranque, se estrecha hacia la punta y tiene una torsión pequeña. Los niveles son:

| Mesh LOD | Hojas | Vértices | Triángulos | Forma |
|---|---:|---:|---:|---|
| 0 | 64 | 704 | 576 | Cinco segmentos curvos por hoja |
| 1 | 32 | 224 | 160 | Tres segmentos de la misma curva, anchura ×1,45 |
| 2 | 16 | 80 | 48 | Dos segmentos siguiendo la hoja, anchura ×2 |
| 3 | 8 | 24 | 8 | Un triángulo por hoja, anchura ×2,8 |

Las anchuras compensan parte de la pérdida de cobertura sin aumentar la altura de
la mata. Todos los niveles heredan el material de su variante y el mismo shader de
viento, y comparten el sombreado descrito más abajo.

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

## Modelo, paleta e iluminación

Las tres variantes usan verdes salvia, verde pajizo y paja dorada. Los colores
se ajustan en los materiales de `low_poly_grass*.tscn`, en espacio sRGB; no hay
texturas nuevas. Las mallas fuente permanecen intactas: el refinado se construye
en memoria al cargar la vegetación, antes de registrar los LODs.

Atributos generados en los cuatro niveles:

- **UV.x**: transversal de la hoja, de 0 a 1. El shader curva ligeramente la normal
  a lo ancho para dar un pliegue suave.
- **UV.y**: semilla por hoja, compartida entre LODs.
- **UV2.x**: recorrido raíz–punta, independiente de la altura y escala de la mata.
  Controla el gradiente, la oclusión, la transmisión y la flexión.
- **UV2.y = 1**: identifica la malla refinada. Los assets sueltos mantienen un
  fallback de altura para que el shader también pueda dibujarlos.

La variación por mata usa un hash entero de celdas de 25 cm relativas al centro
del planeta, en lugar del índice de instancia que se repite en cada MultiMesh.
Una variación espacial de baja frecuencia añade diferencias suaves entre zonas.
El viento también usa posición relativa al planeta, con dos ondas de ráfaga y
un aleteo pequeño por hoja. Las raíces son rígidas y la normal acompaña la flexión.
Se transforma solo el vector de desplazamiento para evitar pérdida de precisión
al reconstruir posiciones mundiales grandes.

El shader de hierba compone una sola luz difusa envolvente, transmisión cálida
hacia las puntas y un reflejo ancho tenue. No añade el SSS ni el rim genéricos del
include, que duplicarían la contribución. La transmisión y los reflejos reciben
las sombras; las luces locales funcionan también de noche.

El relleno hemisférico del cielo se aplica una vez en `fragment()`, mediante
`EMISSION` proporcional al albedo, oclusión y factor de día. Así conserva detalle
bajo una sombra y no se multiplica al añadir antorchas. De noche baja al 1,5 %;
la luz ambiental del entorno se sigue aplicando por separado. La oclusión de la
raíz atenúa cada contribución una vez. El albedo no se oscurece de nuevo con AO.

`planet_lighting.gdshaderinc` sigue proporcionando los uniforms y el terminador
planetario. La normal radial se inicializa antes de pasársela al helper. La
iluminación compartida de los árboles y otros materiales no se modifica.

### Entorno de la prueba

La pradera de prueba conserva el ACES, glow, niebla, luz ambiental y configuración
de sombras de `scenes/maps/sun.tscn`. Carga los seis items de hierba (tres variantes,
cada una con capa cercana y lejana). El cielo es un color plano; no reproduce el
compositor de atmósfera ni el terreno completo del planeta.

La galería `grass_quality_preview.tscn` añade primeros planos y vistas con luz
frontal, contraluz, sombra proyectada y antorcha nocturna. Usa distribución fija
y viento parado para comparar forma e iluminación. La sombra de la galería es
completa, más severa que la opacidad 0,7 configurada para la pradera.

## Validación

Con el ejecutable personalizado de Godot que contiene Voxel Tools:

```sh
godot --headless --path . --script res://tests/vegetation/test_grass_geometry_lods.gd
godot --headless --path . --script res://tests/vegetation/test_grass_instancer.gd
godot --path . res://tests/vegetation/grass_lod_preview.tscn -- --capture
godot --path . res://tests/vegetation/grass_quality_preview.tscn -- --capture
```

Las pruebas comprueban los tres assets, puntas y altura conservadas, normales,
triángulos no degenerados y orientación de caras, UVs, presupuesto geométrico,
registro de las 12 bandas en el instancer, materiales, viento y coordinación de
los rangos de relevo. Ambos scripts terminaron con cero fallos.

La escena gráfica usa el VoxelInstancer real sobre un terreno plano, con las
densidades, escalas y LODs del planeta para las tres variantes. Desactiva las máscaras
de bioma para llenar el terreno de prueba. Guarda capturas a ras de suelo, elevadas,
durante un recorrido y a contraluz en `build/grass_lods/`. La vista `native_backlit`
baja el sol al horizonte delante de la cámara para comprobar la transmisión.
Sin `--capture`, permite recorrer la pradera con WASD, subir/bajar con E/Q y
acelerar con Shift.

La galería guarda `after_day/detail/backlit/shadow/night_torch.png` en
`build/grass_quality/`. La opción `--baseline` requiere la copia local anterior
en `build/grass_quality/opus/`; esa carpeta está ignorada por Git y no es necesaria
para ejecutar la versión actual.

Validado con Godot 4.6, Forward+ y RTX 4080 SUPER. En la vista elevada se midieron
5.966.232 primitivas con LODs y 197.926.944 forzando todas las mallas a LOD0
(aproximadamente un 97 % menos). Es una comparación de carga geométrica con la
misma distribución, no una medición de FPS del juego completo.

LOD0 pasa de 262 a 576 triángulos para dibujar la curva; LOD1 pasa de 138 a 160.
LOD2 y LOD3 mantienen 48 y 8. La construcción tarda aproximadamente 3,1 ms por
variante en esta máquina y se hace al cargar, no cada frame. Queda por valorar
el resultado en las pendientes y condiciones atmosféricas del planeta real.

El arranque del proyecto presenta avisos previos del complemento de Git ausente,
dos audios no encontrados y recursos retenidos por autoloads al salir. La prueba
gráfica no produjo errores nuevos de compilación de los shaders de hierba.

# Revisión de rendimiento del bosque — 5 de octubre de 2026

La limitación de esta vista se reparte entre CPU y GPU. Las sombras tienen un coste
medible, pero optimizar solamente las sombras de los impostores deja otros costes
que limitan los FPS, también con la cámara quieta.

## Condiciones de la medición

- Godot 4.6 custom, Forward+, RX 9070 (RADV).
- Posición de la partida guardada, mirando al norte local, a 1,7 m sobre el terreno.
  Dos puntos del mismo recorrido: 37,5 m y 7,5 m desde la posición inicial.
- Cámara quieta, terreno ya cargado, sol fijo a 24° sobre el horizonte local;
  calendario inicial del arnés (día 8,5, verano del norte).
- Ventana efectiva de 2560×1440, escala 3D 0,5, FSR2, MSAA 2x. El servidor gráfico
  limita la ventana solicitada de 3840×2160 a 2560×1440: estas cifras corresponden
  a la resolución efectiva que imprime el arnés.
- Densidad y distancia de hierba en nivel 1, detalle de terreno en nivel 1, fauna
  en nivel 1; demás ajustes leídos de `settings.cfg`.
- Mediana de 180 fotogramas por variante, calentamiento entre variantes y vuelta
  al estado inicial. Copia temporal de los datos de usuario.

## GPU y fotograma completo

En el punto de 37,5 m:

| Cambio aislado | GPU | Fotograma completo |
|---|---:|---:|
| FSR2 + MSAA 2x | 7,26 ms | 9,51 ms |
| FSR2 sin MSAA | 7,10 ms | 9,15 ms |
| FSR1 + MSAA 2x | 5,73 ms | 8,93 ms |
| Vuelta a FSR2 + MSAA 2x | 7,25 ms | 9,45 ms |

Los timestamps nativos atribuyen ~1,06 ms a las sombras, ~1,13 ms al pre-pase de
profundidad y ~2,43 ms al pase de movimiento. Ocultar la hierba reduce ese último
pase a ~0,74 ms. El pase de movimiento **no equivale a 2,43 ms adicionales por
FSR2**: con FSR1 parte de ese dibujo se realiza en el pase opaco. La diferencia
total medida entre FSR2 y FSR1 es ~1,5 ms de GPU en este punto.

En una tanda separada, apagar las sombras reduce la GPU de 7,34 a 6,18 ms.
Ocultar los impostores reduce la GPU de 7,34 a 6,99 ms. Se mantiene el cambio
anterior del shader de impostor; quitar más trabajo de ese pase tiene un margen
limitado frente al resto del fotograma.

El tiempo real del fotograma baja menos que el tiempo de GPU. La fase de scripts
idle ronda 2,4 ms, además de la preparación de render (~0,9 ms) y el render de CPU
(~2,7 ms). Estas fases no deben sumarse sin considerar la partición del frame y
la sincronización con la GPU. Las lecturas de `Performance.TIME_PROCESS` y
`TIME_PHYSICS_PROCESS` no se han usado para sumar fases: se usan las sondas de
`DebugStats` y el intervalo real entre dibujos.

## Corrección de CPU

La sonda por scripts localizó ~0,63 ms por fotograma en `Underwater`, incluso en
tierra firme. `UnderwaterRenderPass.update_material()` empaquetaba los cuatro
arrays de 128 interiores aunque `interior_count` fuese cero: 512 vec4 que ningún
consumidor podía leer.

Ahora empaqueta únicamente los interiores activos. Se conserva el tamaño y la
disposición del buffer; las plazas sin usar permanecen a cero en cada snapshot
nuevo. El cambio no depende de estar fuera del agua: también funciona nadando
sin barcos y conserva los datos necesarios en barcos con compartimentos secos.

Comparación de 500 actualizaciones con el material real y cero interiores:
**0,582 → 0,090 ms por actualización**. En la sonda de juego, `Underwater` pasa
de ~0,63 a ~0,16 ms por fotograma.

En dos parejas alternas del punto más cargado, el fotograma completo pasa de
9,02/8,98 a 8,41/8,38 ms: aproximadamente **111 → 119 FPS**. El punto de 7,5 m
varía más por las frecuencias de GPU y la distribución de ticks de física;
no se toma una sola pareja allí como una mejora o regresión general. Los ciclos
aproximados de GPU permanecen prácticamente constantes con el cambio de CPU;
una bajada de milisegundos GPU por mayor frecuencia no es ahorro de shader.

Validación del snapshot: 0, 1, 2 y 128 interiores activos,
vuelta de 128 a 0, exclusión de interiores inactivos, conservación de los demás
arrays y desactivación con material nulo. Resultado: cero fallos en el proyecto
aislado sin GPU.

## Límites y registros

La mejora de CPU es moderada; no elimina el coste de render de vegetación ni el
de FSR2. El perfilado restante señala animaciones (~0,49 ms en 14 AnimationTree),
actualización de planetas (~0,33 ms) y VoxelInstancer (~0,25 ms), además del render.
Cambiar FSR2 por FSR1 es una opción de calidad, no la corrección aplicada.

El descarte temprano de hierba fuera de su banda se probó en memoria: ahorra algo
de GPU, pero no produjo una mejora consistente de FPS. No se incorporó al shader.
El culling en serie se conserva: el commit `9c322aa7` documenta picos de espera
con el culling paralelo en esta versión del motor.

Registros locales de la revisión (artefactos ignorados por Git):

- `build/ab/performance_review_native3.log`: aislamiento de grupos y timestamps.
- `build/ab/performance_variants.log`: FSR, MSAA, shader experimental y sondas.
- `build/ab/cpu_review3.log`: comparación alterna antes/después de la corrección.

Las mediciones corresponden a estos dos puntos en verano, con la cámara quieta;
no cuantifican otros biomas, el invierno ni el streaming durante el movimiento.

## Partida de otoño en la zona nevada

Commit de control solicitado antes de esta segunda revisión: `5c57596`.
Se mide una copia de `main_save`, con el día 19,203801 del año, clima despejado,
posición canónica (21585,6875; 15315,9971; 803,0516) y distancia de cámara 3,2 m.
La cámara conserva el encuadre guardado; el sol y el calendario siguen avanzando.

Ajustes actuales: ventana efectiva 2560×1440, bilineal, escala 0,75 (3D a
1920×1080), MSAA 2x, densidad/distancia de hierba, fauna y detalle de terreno en
nivel 1. Se conservan las sombras, incluido el alcance de 1500 m del sol.

### Cambios conservados

- `_update_planet()` envía el centro, viento y velocidad únicamente cuando cambian.
  Inicializa materiales nuevos o sustituidos y conserva las actualizaciones del
  sol para shaders antiguos que realmente declaran `light_direction`. El include
  moderno usa `LIGHT` y deja de declarar ese uniform sin uso; el registro del
  equipo reconoce `planet_position` y sigue admitiendo shaders antiguos.
  Se invalida la consulta de uniforms al cambiar el código de un shader.
- Celdas de árboles de 64/64/128 m en lugar de 32/32/64 m: mismas posiciones,
  mallas, densidad, distancias de LOD y sombras, agrupadas en menos MultiMeshes.
  En esta vista se reducen unas 650–700 llamadas de dibujo.
- Caché de defaults del shader en el snapshot del agua. Los overrides del
  material siguen leyéndose en cada actualización; cambiar el shader o su código
  invalida la caché. Evita consultas repetidas al servidor de render.

### Comparación final

El arnés mide FPS medios con el tiempo real de 400 fotogramas por variante,
alternando el estado anterior y el optimizado dentro de la misma partida, con
controles y física activos. El estado anterior restaura las celdas de 32 m y los
envíos de uniforms por frame; conserva las comprobaciones del código nuevo.

| Pareja | Estado anterior | Optimizado |
|---|---:|---:|
| 1 | 84,12 FPS / 11,888 ms | 106,99 FPS / 9,347 ms |
| 2 | 86,00 FPS / 11,628 ms | 109,38 FPS / 9,142 ms |
| 3 | 88,85 FPS / 11,255 ms | 111,90 FPS / 8,936 ms |
| 4 | 88,51 FPS / 11,298 ms | 110,12 FPS / 9,081 ms |

La preparación de render baja aproximadamente de 1,2–1,4 a 0,3–0,4 ms en las
muestras de control. La frecuencia de GPU también sube al aliviar la CPU.
Las mediciones del arnés quedan en 107–112 FPS; el usuario confirma **120 FPS y
algo más en el juego** tras los cambios. Son observaciones de ejecuciones
distintas: las comparaciones alternas cuantifican la mejora y la comprobación
del usuario valida el objetivo en su partida.

### Validación y limpieza

Validación: prueba de actualización de materiales (sol, rebase, viento, clima,
velocidad de especie, sustitución/recarga, equipo, shader moderno y cambio de
shader en vivo), cero fallos; prueba existente de árboles, cero fallos; snapshot
del agua con 0/1/2/128 interiores y transición a cero, cero fallos sin GPU; defaults,
overrides y sustitución de shader, cero fallos con OpenGL.
Se retiran las pruebas y los arneses temporales añadidos durante esta revisión
a petición del usuario; se conservan los tests existentes.

Registros locales ignorados por Git: `build/ab/save_paired.log` (comparación final),
`build/ab/planet_material_updates_final.log`, `build/ab/tree_tests_after.log` y
`build/ab/snapshot_final_{headless,gpu}2.log` (validación).

# Hierba con LODs geométricos

La hierba terrestre del planeta usa hojas geométricas a todas las distancias
en las que se dibuja. Las tres variantes (`low_poly_grass`, `green_yellow`, `yellow`)
ya no activan `grass_patch`: no se hornea una imagen de la mata para LOD2/LOD3.

`scripts/planet/grass_geometry_lods.gd` separa las 64 hojas del asset por conectividad
y construye una selección anidada de hojas, repartida por las puntas de la mata.
Reconstruye cada hoja como una cinta Bézier y añade 32 hojas más bajas (copias
giradas de las del asset, al 50–82 % de su altura) que rellenan la parte baja de
la mata de cerca y solo existen en LOD0. Los niveles son:

| Mesh LOD | Hojas | Vértices | Triángulos | Forma |
|---|---:|---:|---:|---|
| 0 | 96 | 864 | 672 | Cuatro segmentos curvos por hoja |
| 1 | 48 | 336 | 240 | Tres segmentos de la misma curva, anchura ×1,55 |
| 2 | 24 | 120 | 72 | Dos segmentos siguiendo la hoja, anchura ×2,4 |
| 3 | 12 | 36 | 12 | Un triángulo por hoja, anchura ×3,7 |

- **Forma de la hoja.** Las hojas miden el 62 % de la anchura del asset
  (`WIDTH_SCALE`): a ~1/9 de su largo se leían como palas. La sección se ensancha
  tras el arranque, se estrecha hacia la punta y tiene una torsión pequeña.
- **Arqueado.** Las 12 hojas de silueta (las que llegan a LOD3) conservan raíz y
  punta del asset, y con ellas la altura y el contorno de la mata. Las demás se
  abren hacia fuera y caen por la punta, hasta ~30° por debajo de la horizontal,
  según su semilla. Se doblan por la cara: su anchura queda perpendicular a la
  dirección en la que caen. La normal de la punta usa la tangente de su último
  tramo, para que no se invierta en los LODs de pocos tramos.
- **Anchura por nivel.** Crece ×1,55 por nivel (`GrassGeometryLods.WIDTH_GROWTH`) y
  compensa parte de la cobertura perdida sin aumentar la altura de la mata.

Todos los niveles heredan el material de su variante y el mismo shader de viento.

## Bandas del instancer

`VoxelInstancer` genera cada banda de terreno (0, 1, 2…) en una caja anidada de
bloques de 16 · 2^banda m, y **todas las cajas llegan hasta la cámara**: la banda 2
tiene matas a 5 m aunque solo se vean a partir de 64 m. Cada banda recibe su propio
material (`Planet._build_grass_band`) con un relevo que entra mientras sale el de la
anterior, y solo registra las mallas que una mata visible puede necesitar:

| Banda | Visible | Relevo de salida | Mallas |
|---|---|---|---|
| 0 | 0–40 m | 28–40 m (`split_m`, `split_fade_m`) | LOD0–LOD2 |
| 1 | 28–88 m | 64–88 m (alcance de la banda − 8 m) | LOD1–LOD3 |
| 2 | 64–130 m | 106–130 m (`max_distance_m`) | LOD3 |

- Los bloques cuyas matas quedan todas dentro del relevo de entrada usan una malla
  vacía, y los que quedan enteros más allá del relevo de salida no se dibujan
  (`hide_beyond_max_lod`).
- La caja de cada banda cubre en todas direcciones al menos su alcance: medido con la
  cámara en varios puntos de su bloque, banda 1 ≥ 132 m, 2 ≥ 196 m, 3 ≥ 388 m. Por eso
  las bandas terminan 8 m antes de `48 · 2^banda`.
- La banda 3 ya no se usa para la hierba: cubría el anillo de 152 a 320 m con bloques
  de 128 m y costaba más de la mitad del total. La hierba termina ahora en 130 m.
- Con los bosques de árboles Branching, la banda 2 hasta 184 m era la parte más cara de la
  vegetación en GPU (0,3-0,7 ms a 2560×1440, más que cualquier parte de los árboles): el
  follaje la tapaba y, con bosques menos densos, quedaba a la vista. Terminarla en 130 m dio
  +3 fps andando y +6 volando quieto; bajo los árboles y a ras de suelo no se distingue.

`Planet._set_mesh_lod_ratios` asigna los cuatro ratios en dos pasadas. El módulo
recorta cada ratio al intervalo [anterior, siguiente] con los valores que tiene en ese
momento, así que asignados en orden los primeros quedaban recortados al valor por
defecto del siguiente. Por ese motivo la hierba pedía LOD0 hasta 40 m y usaba 0,35 · 48 m.
Los árboles, que no configuran distancias, conservan las que venían usando de hecho
(270 / 460 / 768 m).

## Morph de LOD por mata

El instancer elige la malla por la distancia al **centro del bloque**, así que un
bloque de 16 m cambia de malla cuando algunas de sus matas están 14 m más cerca o más
lejos de ese límite. Para que el cambio no se vea, `grass_wind.gdshader` hace un
morph continuo por mata:

- La geometría hornea en `CUSTOM0` el desplazamiento de cada borde respecto al eje de
  su hoja (xyz) y `4 · LOD de la malla + último LOD en el que sigue la hoja` (w).
- El shader calcula un nivel continuo a partir de la distancia de la mata y las
  ventanas `lod_morph_start/end` (hierba: 10→16, 24→34 y 46→62 m). Las hojas que no
  existen en el siguiente nivel se estrechan hasta cero y las supervivientes se
  ensanchan ×1,55 por nivel. Una malla más detallada de lo necesario imita la
  siguiente; una más simple se deja como está.
- Cada bloque cambia de malla cuando la esquina más cercana del bloque ya ha
  terminado la transición: `fin del morph + 0,866 · lado del bloque + 2 m`. Las mallas
  más finas se usan algo más lejos de lo imprescindible, pero sus hojas sobrantes son
  triángulos degenerados que no se rasterizan.
- Una semianchura mínima de 0,6 px (tope ×2,5) evita que las hojas lejanas parpadeen
  y dejen de cubrir el suelo.

`test_grass_instancer.gd` comprueba en cada banda que ningún bloque cambia a una malla
más simple antes de que sus matas terminen el morph, y que la malla vacía solo cubre
bloques ocultos.

## Densidad y manchas

Los tres generadores cercanos pasan a `EMIT_FROM_FACES`: la densidad es por m² y no
depende de la resolución del terreno. La verde lleva además ruido 3D de manchas
(frecuencia 0,045, `threshold` 0,3, `falloff` 0,25, `on_scale` 0,3), que deja el
~70 % del suelo dentro de alguna mancha, con bordes suaves. La capa lejana usa la
misma semilla, así que las manchas continúan en todas las bandas. La escala mínima
de las matas verdes sube de 0,5 a 0,75: las más pequeñas apenas se veían y más
cobertura por mata cuesta menos que más matas.

| Generador | Dentro de las manchas | Media | Antes |
|---|---:|---:|---:|
| Verde, banda 0 | 1,2 /m² | ~0,84 /m² | ~1,25 /m² (bandas 0 y 1 superpuestas) |
| Verde, banda 1 | 0,84 /m² | ~0,59 /m² | ~0,25 /m² |
| Verde lejana, banda 2 | 0,75 /m² | ~0,52 /m² | 0,6 /m² |

El umbral del ruido de `VoxelInstanceGenerator` recorta más cuanto más negativo es:
con 0 sobrevive el 53 %, con −0,2 el 28 %, con 0,15 / `falloff` 0,2 el 55 % y con
0,3 / `falloff` 0,25 el 70 %. Con hojas finas, una cobertura menor se leía como una
pradera calva. Las variantes amarilla y verde-amarilla mantienen sus densidades: son
la hierba principal de sus biomas. En el planeta real las máscaras de bioma
(`noise_graph`) se aplican además del ruido.

## Modelo, paleta e iluminación

Las tres variantes usan verde de pradera, verde pajizo y paja dorada. Los colores
se ajustan en los materiales de `low_poly_grass*.tscn`, en espacio sRGB; no hay
texturas nuevas. La verde es más cálida que el antiguo salvia (base 0,2/0,33/0,14,
punta 0,6/0,72/0,36): sobre el suelo oliva del bioma, el salvia frío parecía pegado
encima. El arranque de cada hoja toma el color de ese suelo (`ground_tint`, 35 %). Las mallas fuente permanecen intactas: el refinado se construye
en memoria al cargar la vegetación, antes de registrar los LODs.

Atributos generados en los cuatro niveles:

- **UV.x**: transversal de la hoja, de 0 a 1. El shader curva ligeramente la normal
  a lo ancho para dar un pliegue suave.
- **UV.y**: semilla por hoja, compartida entre LODs.
- **UV2.x**: recorrido raíz–punta, independiente de la altura y escala de la mata.
  Controla el gradiente, la oclusión, la transmisión y la flexión.
- **UV2.y = 1**: identifica la malla refinada. Los assets sueltos mantienen un
  fallback de altura para que el shader también pueda dibujarlos.
- **CUSTOM0**: datos del morph (ver arriba). Sin ellos el morph no desplaza nada.

La variación por mata usa un hash entero de celdas de 25 cm relativas al centro
del planeta, en lugar del índice de instancia que se repite en cada MultiMesh.
Encima, dos ruidos de valor 3D (26 m y ~8 m, `meadow_scale`) forman manchas de
prado: deciden el tono de cada mata entre verde profundo y verde amarillento, su
luminosidad (±30 %) y, en su extremo cálido, zonas secas que tiran hacia paja. Un
8 % de las hojas de cada mata sale seca (`dead_blade_ratio`). Las hojas que dobla
una ráfaga se aclaran (`wind_sheen`), y una onda de brillo recorre el prado con el
viento. El ruido cuesta ~0,10 ms en la vista a ras de suelo; una tercera evaluación
para las zonas secas costaba otros ~0,04 ms y se sustituyó por el extremo cálido.
El viento también usa posición relativa al planeta, con dos ondas de ráfaga y
un aleteo pequeño por hoja. Las raíces son rígidas y la normal acompaña la flexión.
Se transforma solo el vector de desplazamiento para evitar pérdida de precisión
al reconstruir posiciones mundiales grandes. La base de la instancia es ortogonal
con escala, así que ese vector se pasa a espacio local con la traspuesta dividida
por la escala² de cada eje, en lugar de `inverse(MODEL_MATRIX)` por vértice.

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
de sombras de `scenes/maps/sun.tscn`. El suelo usa la textura del bioma verde con la
escala triplanar del terreno (`meadow_ground_material()`): con un color liso, los
claros entre matas parecían agujeros y no el césped corto que se ve en el juego. Carga los seis items de hierba (tres variantes,
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
godot --path . --script res://tests/vegetation/test_foliage_lighting.gd
godot --path . res://tests/vegetation/grass_lod_preview.tscn -- --capture
godot --path . res://tests/vegetation/grass_quality_preview.tscn -- --capture
```

Las pruebas comprueban los tres assets, puntas y altura conservadas, normales,
triángulos no degenerados y orientación de caras, UVs, datos de morph y anidamiento
de hojas por LOD, presupuesto geométrico, registro de las 9 bandas, asignación de
ratios, relevos encadenados, mallas por banda sin saltos, materiales y viento.
Todas terminan con cero fallos.

La escena gráfica usa el VoxelInstancer real sobre un terreno plano, con las
densidades, escalas y LODs del planeta para las tres variantes. Desactiva las máscaras
de bioma para llenar el terreno de prueba. Guarda capturas a ras de suelo, elevadas,
durante un recorrido y a contraluz en `build/grass_lods/`. La vista `native_backlit`
baja el sol al horizonte delante de la cámara para comprobar la transmisión.
Sin `--capture`, permite recorrer la pradera con WASD, subir/bajar con E/Q y
acelerar con Shift. Con `--understory` carga también el sotobosque.

### Coste medido

Tiempo de GPU de la vegetación (fotograma completo menos el mismo fotograma con el
instancer oculto), mediana de 200 fotogramas en la pradera de prueba con hierba,
sotobosque y el suelo con textura, 2560×1440, Godot 4.6 Forward+, RTX 4080 SUPER:

| Vista | Antes | Después | Primitivas antes → después |
|---|---:|---:|---:|
| A ras de suelo | 4,38 ms | 2,11 ms | 11,1 M → 5,3 M |
| A ras de suelo, lateral | 3,83 ms | 2,05 ms | 8,9 M → 4,9 M |
| Elevada (14 m) | 4,17 ms | 2,03 ms | 8,1 M → 4,5 M |
| Alta (45 m) | 4,20 ms | 1,60 ms | 7,3 M → 3,3 M |

El fotograma completo a ras de suelo pasa de 5,28 a 3,01 ms, y las instancias
cargadas de 860.937 a 213.430. Solo las mejoras de rendimiento dejaban la vegetación
en ~1,5 ms; las hojas finas y más numerosas, las matas más grandes y el color
cuestan el resto. Antes, las bandas lejanas 2 y 3 costaban 1,0 y 2,4 ms casi por
completo en matas ocultas cerca de la cámara con mallas LOD0. La prueba plana no
reproduce el relieve ni la atmósfera del planeta: es una comparación de carga con
la misma escena, no una medida de FPS del juego.

Un recorrido de 90 pasos de 25 cm con el viento parado no muestra picos de
diferencia entre fotogramas en las franjas donde cambian las mallas de los bloques.

El arranque del proyecto presenta avisos previos del complemento de Git ausente,
dos audios no encontrados y recursos retenidos por autoloads al salir.

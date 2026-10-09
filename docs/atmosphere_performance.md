# Resolución de la atmósfera

**Opciones → Gráficos → Calidad de la atmósfera** controla la resolución de la dispersión del aire
(Rayleigh/Mie y perspectiva aérea) y de los rayos de luz. **Las nubes, sus sombras, la niebla y la
aurora se calculan siempre a resolución completa**, con sus algoritmos y jitter originales. Las
nubes, además, se filtran y con la escala de render por debajo del 100 % van por encima de ella
(ver [Capa de nubes](#capa-de-nubes)). El ajuste de pasos de las nubes sigue siendo independiente:

| Calidad | Resolución del aire y rayos | Píxeles respecto a completa |
|---------|----------------------------|----------------------------|
| Alta | Completa | 100 % |
| Media | Mitad en cada eje | Aproximadamente 25 % |
| Baja | Un cuarto en cada eje | Aproximadamente 6,25 % |

Los presets Bajo/Medio/Alto/Ultra usan respectivamente Baja/Media/Media/Alta. El ajuste se aplica
en caliente. El valor predeterminado es Media; Alta usa el cálculo completo y permite comparar
nitidez y rendimiento. Estos porcentajes cuentan píxeles del aire/rayos, no equivalen a ganancias
de FPS: nubes, niebla, composición, bordes y el resto de la escena mantienen su coste.

## Aire reducido, nubes y escena completas

La dispersión del aire se expresa como `color_final = color_escena * transmisión + luz`.
El pase reducido guarda solo estos coeficientes suaves en dos imágenes RGBA16F por vista.
El pase completo aplica las sombras de nube al color de escena, reconstruye la luz y transmisión
del aire con cuatro muestras, y marcha las nubes, aurora y niebla por píxel. Después aplica Purkinje
y compone el agua. Se mantienen el color, las estrellas, el sol, las texturas y las siluetas
originales. Las imágenes admiten resoluciones impares y se recrean al cambiar tamaño, calidad
o número de vistas.

La profundidad lineal guía el filtrado: no se mezclan muestras de cielo, geometría y rayos que
no cruzan aire; tampoco profundidades que difieran más del 3 %. Si no hay una muestra compatible
(por ejemplo, una rama fina que el render reducido no captó), se calcula ese píxel completo.
Los píxeles bajo el agua mantienen el transporte refractado completo. Purkinje se aplica al color
compuesto, ya que depende de su luminancia y no es un coeficiente lineal del medio.

Los rayos de luz calculan su integral a la misma resolución reducida y reutilizan la imagen de
luz después de consumir el caché del aire. Su máscara de oclusión se calcula con las nubes a
resolución completa. La composición de los rayos conserva la atenuación por la
profundidad completa y la exclusión de los píxeles sumergidos. Sus modos de depuración usan el
pase original completo. Si el sol queda fuera del rango de visibilidad, se omiten los despachos
de rayos salvo en depuración. Cada pase usa una compute list separada para sincronizar escritura y
lectura de sus imágenes.

## Capa de nubes

Las nubes se marchan en un pase propio (`planet_atmosphere_clouds.glsl`) y la composición las
filtra. Con 10 pasos de vista y salto doble en aire limpio, un borde fino de nube caía o no dentro
de un paso según el jitter IGN de cada píxel, y sin filtro ni TAA se veía como un tramado de puntos
a cualquier resolución, más marcado aún con FSR 1.0. El filtro quitaba los puntos, pero dejaba un
rayado fino (IGN solo avanza 0,31 por fila, así que en vertical se promedia mal). Por eso los pasos
de vista de la Tierra (`cloud_quality.cloud_steps` en `planet_earth.json`) suben de 10 a 24; los
presets de calidad los escalan como antes.

La composición aplica un filtro de tienda que cubre la huella del píxel más 1,5 texels
(`cloud_filter_margin`), 1-2-1 a la misma resolución. Las muestras se ponderan por la guía de
profundidad de su píxel (la misma que usa el caché del aire): cielo, relieve y aire vacío no se
mezclan, ni profundidades que difieran más del 3 %, así que la nube no se cuela por las siluetas.
El filtro es exacto para la composición porque la luz de detrás es la misma en todas las muestras:
`media(luz*T + C) = luz*media(T) + media(C)`. Cada texel guarda el color de la nube con su
perspectiva aérea y la transmitancia (RGBA16F), y la transmitancia en crudo para la máscara de los
rayos más la guía (RG16F). Los píxeles bajo el agua siguen marchando sus nubes en el pase
completo, porque su rayo se refracta.

Con la escala de render por debajo del 100 %, la capa va además a una resolución intermedia:
`cloud_resolution_boost` es la fracción del camino entre la resolución interna y la de salida
(0 a 1; lo que pase de 1 cuenta como 1), con un tope del doble por eje. Con 0,5, al 75 % sobre
1920×1080, la escena va a 1440×810 y las nubes a 1680×945. Cada texel marcha su propio rayo, con su jitter y su huella para el LOD, pero
con la profundidad del píxel interno que lo contiene (`cloud_owner`).

Medido con `lighting_capture --perf` a la tarde, con `--weather=cloudy` y
`--atmo=cloud_group_strength:0`, al 75 % con FSR 1.0 en una RTX 4080 SUPER (media de dos tandas,
GPU por frame):

| Pasos de vista | `clouds_up` (nubes desde abajo) | `ridges_sun` (horizonte) |
|----------------|---------------------------------|--------------------------|
| 10 | 2,60 ms | 4,26 ms |
| 24 | 2,70 ms | 4,62 ms |
| 40 | 3,26 ms | 4,61 ms |

En `clouds_up`, la desviación del laplaciano de toda la imagen, que mide el grano, es 29,5 con 10
pasos sin filtro, 8,2 con filtro, 7,2 con 24 pasos y filtro, y 7,2 con 40. A simple vista, 24
pasos ya no muestran el rayado que quedaba con 10.

## Historia temporal

No se usa historia temporal: al mover la cámara no quedan muestras de frames anteriores.
Para valorar el cambio conviene comparar Media con Alta mirando cielo y horizonte, bosque,
tormenta/niebla, puesta de sol y agua. La ganancia será menor cuando dominen el coste de las nubes,
los bordes o los píxeles sumergidos.

## Código

- `scripts/atmosphere/planet_atmosphere.gd`: asignación de imágenes, resolución y despachos.
- `shaders/atmosphere/planet_atmosphere_pass.glslinc`: integral del aire compartida, reconstrucción
  bilateral, capa de nubes y volúmenes de nube/niebla/aurora del pase completo.
- `shaders/atmosphere/god_rays_pass.glslinc`: integral y composición de los rayos.
- Los seis `.glsl` de entrada seleccionan el pase mediante defines; declaran los includes de agua
  directamente para que el importador de Godot no tenga que resolver includes anidados.

El UBO tiene **43 vec4**. `P(42).x` es el divisor de resolución (1/2/4) y `P(42).y` vale 1 cuando
el pase completo lee la capa de nubes; los demás parámetros conservan sus índices. La compilación
desde texto del editor resuelve los includes recursivamente.
Al modificar un `.glslinc` también se deben reimportar las entradas `.glsl` antes de exportar:
el importador no sigue cambios de las dependencias. Si un pipeline reducido falla, se usa completo.
Si falla la asignación del caché del aire, se intenta el pase completo con imágenes auxiliares de 1×1;
si falla la capa de nubes, se deja con imágenes de 1×1 que no se leen y las nubes se marchan, sin
filtro, en el pase completo.

Las seis entradas se han compilado a SPIR-V con Godot 4.6. La comparación visual y las medidas
de FPS/GPU quedan para la comprobación en juego.

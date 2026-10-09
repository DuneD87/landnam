# Resolución de la atmósfera

**Opciones → Gráficos → Calidad de la atmósfera** controla la resolución de la dispersión del aire
(Rayleigh/Mie y perspectiva aérea) y de los rayos de luz. **Las nubes, sus sombras, la niebla y la
aurora se calculan siempre a resolución completa**, con sus algoritmos y jitter originales.
El ajuste de pasos de las nubes sigue siendo independiente:

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

No se usa historia temporal: al mover la cámara no quedan muestras de frames anteriores.
Para valorar el cambio conviene comparar Media con Alta mirando cielo y horizonte, bosque,
tormenta/niebla, puesta de sol y agua. La ganancia será menor cuando dominen el coste de las nubes,
los bordes o los píxeles sumergidos.

## Código

- `scripts/atmosphere/planet_atmosphere.gd`: asignación de imágenes, resolución y despachos.
- `shaders/atmosphere/planet_atmosphere_pass.glslinc`: integral del aire compartida, reconstrucción
  bilateral y volúmenes de nube/niebla/aurora exclusivos del pase completo.
- `shaders/atmosphere/god_rays_pass.glslinc`: integral y composición de los rayos.
- Los cinco `.glsl` de entrada seleccionan el pase mediante defines; declaran los includes de agua
  directamente para que el importador de Godot no tenga que resolver includes anidados.

El UBO tiene **43 vec4**. `P(42).x` es el divisor de resolución (1/2/4); los demás parámetros
conservan sus índices. La compilación desde texto del editor resuelve los includes recursivamente.
Al modificar un `.glslinc` también se deben reimportar las entradas `.glsl` antes de exportar:
el importador no sigue cambios de las dependencias. Si un pipeline reducido falla, se usa completo.
Si falla la asignación del caché del aire, se intenta el pase completo con imágenes auxiliares de 1×1.

Las cinco entradas se han compilado a SPIR-V con Godot 4.6. La comparación visual y las medidas
de FPS/GPU quedan para la comprobación en juego.

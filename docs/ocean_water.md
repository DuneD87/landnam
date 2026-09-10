# Agua: espectro, espuma y óptica

El núcleo de paquetes mezclados y el material anterior se han sustituido.
`water_shader.gdshader` orquesta tres módulos independientes:

- `ocean_spectrum.gdshaderinc`: doce modos coherentes de mar de fondo, mar cruzado
  y oleaje de viento, con longitudes inconmensurables y dispersión gravitatoria.
- `ocean_foam.gdshaderinc`: nacimiento en crestas comprimidas, espuma residual,
  contacto con obstáculos y estelas de barcos.
- `ocean_optics.gdshaderinc`: reconstrucción de profundidad, refracción y SSR.

`ocean_spectrum.gd` replica en CPU el desplazamiento, sus derivadas y la velocidad
orbital. `gerstner_waves.gdshaderinc` se conserva como adaptador de las interfaces
del planeta: exposición al temporal, campo costero, LOD y consultas inversas.
La flotación y el corte submarino utilizan este mismo espectro. Se mantienen las
conexiones del quadtree, los compartimentos secos, el clima y las estelas.

## Geometría

Las olas ya no se promedian entre ocho grupos vecinos. Los modos comparten una
fase continua en coordenadas del planeta. El arrastre horizontal estrecha la
cresta y su presupuesto de contracción está acotado para evitar pliegues. Un
perfil con segundo y tercer armónico produce crestas elevadas y senos anchos.
Las normales derivan de esa geometría, incluida la curvatura de la esfera.

Controles de forma: `wave_amplitude`, `wave_base_length`, `wave_steepness`,
`wave_speed`, `wave_direction`, `wave_pole` y `spectrum_spread`.
`wave_speed=1` usa `omega=sqrt(9.81*k)`; la familia costera mantiene su velocidad
independiente. La amplitud es una escala de los modos, no una altura máxima.
El radio actual es 29950 m; el material tiene amplitud base 2.5 m y longitud 60 m.
El clima produce A=1/L=30 en calma y A=11.5/L=132 en temporal. El temporal
usa pendiente 0.94, velocidad 1.5 y cantidad de espuma 8.4. Acortar la longitud
anterior de 300 m aumenta el relieve de las crestas sin depender de franjas
adicionales de espuma. La iluminación del evento baja a sol 0.35 y ambiente 0.65;
el controlador aplica estos factores según la cobertura local de nubes.

La familia costera usa amplitud 1.1 m, longitud 32 m y pendiente 0.3. En temporal
resultan 2.64 m, 38.4 m y 0.42, antes de la atenuación local y el límite de altura.
`shore_shoal_max=1.35` permite crecer al entrar en poca profundidad.
`shore_handover=0.45` entrega antes el control al campo costero y
`shore_chop=0.28` reduce las olas pequeñas cruzadas. Son ajustes de escala y
mezcla: la familia costera sigue sin simular una rompiente que vuelque sobre sí misma.

## Espuma

La señal de nacimiento procede de la contracción tangencial del espectro,
evaluada por píxel y normalizada por su energía local. Así el umbral no depende
del presupuesto absoluto de contracción ni de la orientación del viento sobre
la esfera. Una puerta de actividad basada en pendiente impide que esa
normalización genere espuma en ondas insignificantes o con amplitud cero.
El campo costero añade su señal geométrica sin alterar el desplazamiento.

Se consultan seis instantes del mismo punto material durante `foam_lifetime`
(5 segundos por defecto). La deposición reciente forma la cresta y la suma
ponderada del historial deja restos que se abren y disuelven. Es un historial
analítico finito, no una simulación de fluido ni una textura con memoria.

`foam_crest_threshold` mide compresión normalizada (por defecto 0.55 en el shader).
El material conserva el ajuste del usuario: umbral 0.1 y suavidad 0.1.
Los valores del antiguo cálculo de compresión absoluta no son equivalentes.
`foam_crest_softness` controla la transición. `foam_crest_amount` recibe
el multiplicador climático y aumenta la masa depositada mediante una curva
logarítmica: cambia cobertura y densidad, no solo la opacidad de una máscara
ya activada. `foam_trail_strength` regula los restos (0.38 en el material) y
`foam_scale` (1.2) el tamaño del patrón.

`foam_edge_breakup` (0.65 en el material) varía el umbral local a tres escalas
para romper el contorno de activación de la cresta. Esto permite entrantes y
prolongaciones sin recortar toda la textura contra la misma línea de compresión.
La densidad de la textura también erosiona ese contorno; el umbral queda siempre
por encima de cero. El valor 0 desactiva esta irregularidad adicional. El ruido
se filtra con la huella del píxel y evoluciona lentamente en coordenadas materiales.

La altura del mismo perfil de doce ondas que desplaza la superficie refuerza
la deposición en la zona superior. `foam_crest_width` (0.65) regula la amplitud
de esa zona. El refuerzo modifica únicamente la densidad de la textura existente:
no rellena sus huecos ni dibuja una segunda franja opaca. Se ha retirado la máscara
de pendiente cero, que convertía las ondulaciones pequeñas en cintas sinuosas.
El borde y los restos reciben menos deposición para dar contraste a la cresta.

El patrón usa `textures/planet/water/foam_density.png`, una máscara de espuma
generada con ImageGen; se ha retirado por completo la evaluación Voronoi.
Dos escalas de la textura aportan acumulaciones grandes, bordes deshilachados y
detalle interno. Los niveles de gris controlan la densidad sin convertirla en
contornos binarios. La espuma vieja pierde antes sus zonas menos densas.

La proyección triplanar mezcla parches interiores con giros y desplazamientos
distintos; no necesita que los bordes de la imagen coincidan. Las transiciones
entre parches tienen derivada continua. La textura se importa sin pérdida, como
datos lineales y con mipmaps. Se usan gradientes explícitos para que los giros
no creen saltos de filtrado ([textureGrad en Godot](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shader_functions.html)).
Costa y estelas comparten el patrón. La óptica del agua y la geometría no cambian.
El origen y el prompt completo figuran en `foam_density_asset.md`.

## Apariencia y diagnóstico

La refracción aplica Snell con IOR 1.333 y valida la profundidad y la altura de
la muestra seleccionada. El desplazamiento de pantalla se limita con
`refraction_max_offset`; la absorción usa la longitud del segmento dentro del
agua, no la diferencia de profundidad de cámara. El reflejo usa
Fresnel dieléctrico, cielo procedural y SSR cuando hay geometría visible válida.
La espuma recibe iluminación difusa; el brillo directo usa GGX. Las normales
finas tienen pendiente acotada para no ocultar el volumen de las olas.

El inspector de `OceanSystem` expone `water_debug_mode`: 0 aspecto final,
1 normales geométricas, 2 cobertura de espuma, 3 compresión, 4 altura y
5 peso del refuerzo de la cresta (antes de aplicar textura y cantidad).
La vista 2 permite distinguir espuma real de brillos blancos. Los controles
obsoletos del material se han retirado, incluidos `packet_size`, `packet_spread`,
`surface_alpha`, `refraction_alpha_floor` y el segundo brillo solar.

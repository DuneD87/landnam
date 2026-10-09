# Iluminación día/noche (SkyLighting)

Los planetas son esferas pequeñas (la Tierra mide 30 km de radio) y el sol gira a su
alrededor (`sun_controller.gd`), así que la hora no es global: depende de dónde esté
el observador. `scripts/planet/sky_lighting.gd` (nodo `SkyLighting` de `sun.tscn`)
resuelve cada frame, para la cámara activa, en qué cuerpo está y a qué altura tiene el
sol y la luna sobre **su** horizonte, y con eso gobierna todas las luces de la escena.

La resolución de la dispersión del aire y los rayos se controla con **Calidad de la atmósfera**;
ver [atmosphere_performance.md](atmosphere_performance.md). El modelo físico se mantiene en
`planet_atmosphere_pass.glslinc`, compartido por los pases completo y reducido.

| Pieza | Qué hace |
|---|---|
| Sol (`DirectionalLight3D`) | Color y energía con la transmitancia del modelo de cielo (abajo): blanco cálido alto, dorado a ~7°, naranja rojizo rasante. Se funde mientras el disco (2,9° de radio) cruza el horizonte y se apaga (`visible = false`) al hundirse. |
| Luna (`MoonLight`) | Dirección real desde el observador hasta el centro de la luna, fase por el ángulo sol‑luna‑observador (esfera lambertiana suavizada), luz fría y rojiza también ella cuando está baja. Entra cuando el disco del sol ya se ha hundido y toma entonces las sombras: nunca hay dos luces con sombras. En órbita queda encendida sin sombras para que la cara nocturna del planeta no sea negra. |
| Ambiente de cielo | El `Environment` usa `AMBIENT_SOURCE_SKY`. El pase de cubemap de `space_sky.gdshader` (que no se ve) reconstruye el cielo del observador a partir de seis muestras del **mismo** modelo que pinta el compute de atmósfera. El relleno de las sombras es el cielo que se ve. |
| Exposición | Adaptación del ojo parcial: sube hasta ×3 cuando la escena se oscurece, para que la noche se lea sin dejar de ser noche. Depende de la luz, no de lo que haya en pantalla (mirar al sol no bombea). |
| Uniforms globales | `sky_sun_radiance`, `sky_moon_radiance`, `sky_ambient_radiance`, direcciones y colores de cielo reflejado. Los leen los shaders que se iluminan a mano: agua, cristal, impostores de árboles, partículas de clima. |
| Compute de atmósfera | Cielo, nubes, niebla y god rays con el modelo de cielo; recibe la luna (`PlanetAtmosphere.set_moon_light`) y el tono del sol para los god rays (`set_sun_tint`). |

## Modelo de cielo (`planet_atmosphere.glsl`, sección MODELO DE CIELO)

Dispersión simple de Rayleigh (con su fase) y de Mie (aerosoles, fase de Cornette‑Shanks),
una capa de ozono elevada y un término de dispersión múltiple. La luz que llega a cada punto
del aire se calcula analíticamente (función de Chapman), sin marchar hacia el sol.

El problema de fondo es la escala: con 3 km de aire sobre 30 km de radio la luz rasante apenas
se filtra, el horizonte está a 13 km y a 10 km hacia el sol ya es media tarde. Antes se tapaba con
un "tinte de terminador" que teñía de naranja el cielo entero (cénit incluido) y dejaba la hora
dorada de color lavanda. Ahora:

- **Camino al sol a escala terrestre** (`sun_path_scale`) sobre la curvatura de un planeta
  `sky_curvature` veces mayor: el sol se enrojece solo, y el cénit sigue azul porque el aire alto
  recibe luz menos filtrada.
- **Ozono** (`ozone_strength`): absorbe el naranja de la luz rasante y mantiene azul el cénit al
  atardecer y en el crepúsculo.
- **Rayos de cielo en un planeta virtual**: los píxeles de cielo (sin geometría antes de salir del
  aire) se integran como en un planeta `sky_curvature` veces mayor y con el espesor óptico de vista
  a escala terrestre (`sky_view_scale`), que es lo que satura el horizonte (blanco a mediodía,
  naranja al ponerse). El terreno conserva el aire real, cuya bruma ya estaba afinada.
- **Ángulo del sol aplanado** alrededor del observador en el terreno, las nubes y la niebla: todas
  las nubes de alrededor se encienden a la vez al ponerse el sol.
- **Dispersión múltiple** (`multiple_scattering`): relleno azulado de la bóveda que se prolonga tras
  la puesta y se refuerza en la hora azul (el azul del crepúsculo civil y náutico).
- **Sin halo de aerosoles sobre el terreno** (`TERRAIN_MIE_G` 0,2): el cielo lleva el halo del sol
  (Mie con g 0,85), pero los rayos que acaban en el relieve usan un Mie casi isótropo. Con el lóbulo
  fuerte se pintaba un resplandor alrededor del sol encima de laderas que están a la sombra de la
  propia montaña (el aire no sabe qué lo tapa, y sombrearlo en pantalla dejaba franjas en las
  siluetas). La bruma se conserva; la silueta oscura contra el cielo encendido la da el cielo.
- **Luz de cielo en nubes y niebla** (`sky_ambient_level`): cae con el sol como el ambiente que
  integra SkyLighting (0,72 a 7°, 0,29 al ponerse, 0,06 en el civil). El realce de la hora azul
  es solo color del cielo: usado como luz de las nubes las dejaba en el crepúsculo con el doble de
  ambiente que a mediodía, blancas pasado el terminador vistas desde órbita.
- Todo se funde con la geometría real al salir de la atmósfera: desde órbita se ve el planeta que
  hay. Desde fuera el velo del aire se atenúa (`space_scatter_scale`) y la superficie recibe la luz
  filtrada de su propio punto, rojiza junto al terminador.

`SkyLighting` replica la misma transmitancia (color de la luz del sol y de la luna) y la misma
integral para las muestras de ambiente (con el halo de Mie ensanchado).

## Vegetación, terreno y agua

- `planet_lighting.gdshaderinc` calcula el horizonte del planeta **por luz** (el sol y la
  luna salen y se ponen cada uno por su lado).
- El ambiente de la vegetación lo pone el entorno, una vez por fragmento, con AO y sin pasar por
  la sombra de ninguna luz.
- El terreno aplica la AO de sus texturas al ambiente (`ambient_ao_strength`).
- Las luces usan `shadow_opacity = 0.85`; el terreno remapea `ATTENUATION` con la misma opacidad
  (`sun_shadow_opacity`, lo sincroniza SkyLighting) para que las cuevas sigan a oscuras.
- El agua refleja el sol y la luna con su GGX (`directional_specular_clamp` 24): estela dorada o
  roja al atardecer y plateada bajo la luna. El sol y la luna solo alumbran el agua que los tiene
  sobre su horizonte.
- `directional_roughness_floor` 0,18 es la pendiente de las ondas capilares que la malla y las
  normales no resuelven (unos 3° incluso con el mar en calma, Cox‑Munk). Con la rugosidad del
  material (0,12) el agua era un espejo para el sol: con el mar en calma la estela del ocaso se
  quedaba en un punto en el horizonte, a menudo tapado por las rocas. Solo afecta a las luces
  direccionales; el reflejo del cielo conserva la rugosidad del material.

## Cuevas: profundidad bajo tierra

El ambiente sale del cielo y el motor no sabe que una cueva tiene roca encima: sin más, su interior
recibe el mismo relleno que una sombra al aire libre. Lo resuelve la **profundidad bajo tierra**
(`scripts/planet/underground_depth.gd`): los metros de roca sobre un punto, medidos contra la
superficie del planeta antes de tallar las cuevas (con los ríos ya tallados). Un valle o una cumbre
son superficie y valen 0; solo lo que vació una cueva queda por debajo.

- **Generador**: `earth_terrain_terraces.tres` la saca de la salida de `river_carve` (nodos
  `underground_depth_*`) como el peso de la capa 15, que viaja con el vóxel hasta la malla (CUSTOM1,
  como las menas). Se guarda en 4 bits en raíz cuadrada sobre 64 m: el nivel n vale (n/15)²·64 m,
  fino cerca de la superficie y saturado en 64 m.
- **Terreno** (`planet_biomes.gdshader`): multiplica la `AO` por la visibilidad del cielo, que cae
  entre `underground_dark_start` (3 m) y `underground_dark_end` (16 m) hasta `underground_min_ambient`
  (0, negro). Con el ambiente caen los reflejos del cielo (la oclusión especular del motor sale de
  él); la luz directa no pasa por la `AO` y las antorchas alumbran igual. El mallador interpola el
  peso por la arista, así que una ladera lejana llevaría unos metros falsos: se descuenta un cuarto
  del vóxel que toca a esa distancia (`underground_lod_distance`, lo pone Planet).
  `debug_underground_view` = 1 la pinta (verde cielo abierto, rojo `underground_dark_end`).
- **Lo demás** (personajes, fauna, objetos, vegetación de cueva) no lleva la profundidad en su
  malla: SkyLighting lee la de la cámara (`Planet.get_underground_depth`) y entre
  `underground_dark_start` (6 m) y `underground_dark_end` (18 m) apaga el ambiente, el rebote del
  suelo y los reflejos del cielo, y sube la opacidad de sombra del sol y la luna a 1. La exposición
  no cambia. Mientras dura, las sombras de fuera que se vean por la boca pierden también su relleno.
- **Límites**: mide la roca en vertical, así que en una boca abierta en un acantilado vertical
  oscurece antes de lo que debería. Excavar no la cambia (solo toca el SDF): un pozo hondo
  oscurece como una cueva. Los bloques guardados en la partida antes de existir no la llevan. Los 4
  huecos de pesos del vóxel los comparten las menas (capas 1-3) y esta capa; una cuarta mena
  competiría por ellos.

## God rays

Los haces se concentran junto al sol (lóbulo de dispersión hacia delante): antes el pase sumaba un
velo uniforme sobre todo el cielo abierto al mirar hacia el sol. Toman el color del sol que ve el
observador, y lo que está fuera del aire (el impostor de la luna) no los ensombrece.

## Clima

El `WeatherController` ya no escribe la energía del sol ni del ambiente: llama a
`SkyLighting.set_weather_scales(sol, ambiente, encapotado)` y las escalas se componen con
la hora. `encapotado` desatura el ambiente hacia el gris de las nubes.

## Ajustes

- **PlanetAtmosphere › Sky Model**: `mie_strength` 0,04 · `mie_g` 0,85 · `mie_height_ratio` 3 ·
  `ozone_strength` 2,5 · `sun_path_scale` 4,5 (subir enrojece antes el atardecer) ·
  `sky_view_scale` 9 · `sky_curvature` 16 · `multiple_scattering` 0,06 · `space_scatter_scale` 0,35.
- **SkyLighting › Sun**: `sun_energy` 1,1.
- **SkyLighting › Moon**: `moon_energy` 0,17 (luna llena alta) · `moon_phase_contrast` 0,6 (1 = fase
  física) · `earthshine` 0,035 (luz cenicienta en la cara oscura; solo con el cielo oscuro).
- **SkyLighting › Sky Ambient**: `ambient_scale` 0,6 · `ambient_saturation` 0,3 ·
  `ambient_horizon_weight` 0,45 · `night_sky_radiance` (luz de estrellas sin luna).
- **SkyLighting › Exposure**: `exposure_key` 0,35 · `exposure_adaptation` 0,4 · `max_exposure` 3.

## Capturas de comparación

`tests/lighting/lighting_capture.tscn` carga `sun.tscn`, coloca una cámara en puntos fijos
del planeta (bosque, dunas, orilla, mar, órbita, luna) y fija el sol a una elevación local concreta:

```
godot --path . res://tests/lighting/lighting_capture.tscn -- --tag=after --perf
```

Guarda `build/lighting/<tag>_<vista>_<hora>.png` e imprime el estado resuelto de
SkyLighting y, con `--perf`, el tiempo medio de GPU. `--views=`, `--times=`, `--no-clouds` y
`--debug-draw=N` acotan o aíslan partes, y `--atmo=prop:valor,...` cambia propiedades del
PlanetAtmosphere para comparar (p. ej. `--atmo=mie_strength:0`). `dunes_sun_hidden` deja el sol bajo
escondido detrás de una colina y `ridges_sun` mira al sol desde alto sobre crestas escalonadas. `--weather=clear` fija el clima: sin él lo elige el azar, y con
él el oleaje, así que dos tandas de capturas del mar no son comparables.

## Hora del día en la partida

El sol (`sun_controller.gd`, raíz de `sun.tscn`) es una entidad guardable (`entity_id` "sun",
categoría `planet`): la partida guarda su azimut y elevación y al cargar vuelve a la misma hora.
`tests/lighting/test_time_of_day_save.tscn` lo comprueba (guarda en un slot de prueba y lo borra).

## Límites conocidos

- La luna está fija en el mundo y el sol gira: desde cada lugar la luna ocupa siempre el
  mismo punto del cielo y su fase se repite cada día; el hemisferio opuesto nunca la ve.
- Bajo el agua la luz nocturna sigue siendo la propia del compute submarino (no recibe la luna).

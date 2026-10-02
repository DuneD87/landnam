# Estaciones

El sol marca la fecha: cada vuelta del sol es un día y el año tiene 4 × 8 días. Con la fecha, el
sol sube y baja (los días se alargan y acortan, y hay día y noche polares), y los árboles brotan,
amarillean, enrojecen y pierden la hoja. Todos los árboles Branching cambian: pino y picea como un
alerce (dorados en otoño, sin acícula en invierno) y el olivo como un caducifolio más. Las palmeras
(otro generador y otro shader) no cambian. La hierba, el sotobosque y la pradera del terreno se
agostan en otoño y quedan pardos en invierno. En primavera florecen los arbustos (flores de
geometría, no hojas pintadas), las flores silvestres y los bosquetes de almendros y manzanos.

## Calendario y sol

`scripts/planet/sun_controller.gd` (raíz de `sun.tscn`) lleva `day_of_year`. Con la rotación
automática avanza con el azimut (360° = un día) y la elevación del sol pasa a ser la declinación del
día: `inclinación · sin(2π · fase)`. La fase 0 es el equinoccio de primavera del norte, la 0,25 el
solsticio de verano del norte.

| Export | Valor | |
|---|---|---|
| `days_per_season` | 8 | Un día dura 1 h real (`rotation_speed_deg` 0,1). |
| `axial_tilt_deg` | 23,44 | Declinación máxima. Más allá de 66,6° de latitud hay día y noche polares. |
| `start_day` | 8,5 | Partida nueva: principio del verano del norte, donde está el SpawnPoint (17° N). |

- La iluminación ya era por observador (`SkyLighting`): con la declinación la duración del día, la
  noche polar, la luna y la exposición salen solas. A 40° de latitud la luz va de ~9 h a ~15 h.
- Con la rotación automática apagada (`sun <azimut>`, capturas) la elevación es la que se fije a
  mano; la fecha sigue mandando sobre los árboles.
- El guardado añade `day_of_year`. Las partidas anteriores empiezan en `start_day`.
- `Seasons.push_globals()` escribe el uniform global `season_state` en cada `_update_sun()`:
  x = fase del año, y = declinación, z = inclinación, w = 1. Sin calendario (herramientas,
  horneado) w = 0 y todo se queda en verano.

`scripts/planet/seasons.gd` (`Seasons`) es la parte en CPU: declinación, fase local, latitud, horas
de luz. Cada shader saca su estación de `season_state` con `shaders/lib/season.gdshaderinc`:

- El sur va medio año por detrás (`season_local_phase`).
- Entre 3° y 12° de latitud entra el ciclo (`season_strength`); más cerca del ecuador los caducos
  no pierden la hoja. La franja es estrecha a propósito: los bosques caducos llegan casi al ecuador
  y el punto de partida está a 17° N.

## Hoja caduca

Todas las especies Branching (`"deciduous": true` en `tools/vegetation/tree_presets.gd`). Calendario
en fase local, con el frío de referencia (25°, como `climate_coldness`):

| Fase | Día (norte) | |
|---|---|---|
| 0,03 – 0,11 | 1 – 3,5 | Brotan las tarjetas; hoja tierna, más clara y amarilla. |
| 0,11 – 0,23 | 3,5 – 7,4 | La hoja tierna madura. |
| 0,47 – 0,74 | 15 – 23,7 | Otoño: amarillo → color de pleno otoño → hoja seca → cae. |
| 0,74 – 1,03 | 23,7 – 1 | Pelado. |

- Cada grado de frío por encima de 25 (latitud y altura) retrasa la primavera y adelanta el otoño
  0,003 de fase (hasta 0,06): la montaña y el norte amarillean antes. Cada árbol se adelanta o se
  retrasa además ±0,015 (`SEASON_TREE_JITTER`).
- **Por tarjeta**: el aleatorio de cada tarjeta de ramillete (`COLOR.a`) decide cuándo cambia y
  cuándo cae (`season_card`); la copa cambia a manchas y se aclara poco a poco. Las hojas más
  amarillas que la media de la textura van algo por delante dentro de la misma tarjeta.
- **Hoja o madera**: las texturas de ramita llevan dibujada la madera de la ramilla. La hoja se
  reconoce por el color (verde o verde amarillenta y saturada; la madera es gris, parda o violácea,
  con más rojo que verde), ensanchada con una muestra borrosa de la textura para llevarse el
  contorno de cada hoja y los peciolos (`season_leaf_mask_wide`). Sin hoja, la tarjeta deja la
  madera: el invierno es una masa de ramillas con sus yemas, no solo las ramas de la malla.
  Los umbrales son por especie (`leaf_mask_edges`: saturación y matiz). El pino y el olivo, de hoja
  poco saturada (acícula oscura, hoja plateada), bajan la saturación y se apoyan en el matiz.
- **Color de otoño** por especie (`autumn_early`, `autumn_late`, `autumn_withered`): son los de la
  hoja verde media de la textura (`leaf_luma_ref`, `leaf_chroma_ref`, medidas en lineal); cada
  texel conserva su luz relativa. Abedul dorado, manzano ocre y anaranjado, almendro rojo, pino y
  picea dorados y tostados, olivo amarillo y ocre.
- La hoja caída se descarta también en el pase de sombras: en invierno entra el sol en el bosque.
- Sin hoja, la oclusión horneada de la copa sobre ramas y ramillas se aclara un 60 %
  (`SEASON_BARE_AO_LIFT`); la de la base del tronco se queda.

La ramita del abedul estaba pintada en otoño. Ahora es verde (`tools/vegetation/paint_cold_twigs.gd`)
y el dorado lo pone el shader.

**Flor de los frutales** (`blossom_color`, el alfa la activa): almendro y manzano florecen al brotar.
Las tarjetas recién brotadas están en flor (rosa que va al blanco según la tarjeta, con la luz
relativa del texel de hoja) y la flor da paso a la hoja tierna (`season_blossom`). El almendro
adelanta su brotación (`spring_shift` −0,05): florece a finales del invierno, antes que el manzano.
Es la forma de la hoja pintada de flor: de cerca no son pétalos.

Almendros y manzanos crecen en **bosquetes** de una sola especie (`tree_generator_almond_grove` y
`tree_generator_apple_grove` en `planet_earth.json`): manchas de ruido de ~80 m
(frecuencia 0,012, umbral 0,42: pocas y pequeñas) con 0,009 árboles/m² por variante dentro de
ellas, cada especie con su semilla. En flor se ven como cúmulos rosas (almendro) y blancos (manzano) entre el bosque
de pinos y olivos. El almendro conserva además los sueltos de la arena.

### Impostores

Cada árbol lleva un segundo par de atlas horneado sin hoja (`<escena>_bare_albedo.png` /
`_normal.png`, `TreeOctaImpostor.bake(..., bare = true)`): las tarjetas solo dejan su madera, y la
corteza recibe más sol que en el atlas con hoja (`BARE_BARK_SHADE` 0,75 frente a 0,45).

El impostor lleva el estado de la hoja del árbol (`season_leaf_state`) en `v_snow_climate.zw` (el
shader está en el tope de varyings). Manchas de ruido en cada vista hacen de tarjetas: en las que ya
han perdido la hoja, los píxeles de hoja del atlas normal se sustituyen por los del atlas sin hoja;
en el resto, el color de otoño se aplica igual que en la geometría. En verano solo lee el atlas
normal y en invierno solo el sin hoja; entre medias, los dos.

`bake_tree_impostors.gd` hornea los dos pares de los caducos. Los `.import` de un atlas sin hoja
nuevo deben ser los del atlas con hoja (mipmaps y compresión VRAM): Godot los crea sin mipmaps.
`test_trees.gd` lo comprueba.

## Pradera: hierba y terreno

`season_meadow_state` da, por sitio: sequedad (0 verde .. 1 pardo del invierno) y verdor tierno de
primavera. Con el frío, como los árboles:

| Fase local | |
|---|---|
| 0 – 0,08 | Reverdece. |
| hasta ~0,3 | Tierna (verde más claro y amarillento). |
| 0,3 – 0,47 | Se seca un poco al final del verano (25 %). |
| 0,47 – 0,72 | Se agosta: paja. |
| invierno | Parda. |

- **Hierba** (`grass_wind.gdshader`): el color sigue a la pradera (`season_meadow_color`, conserva
  la luz relativa de cada hoja) y unas hojas se agostan antes que otras: en invierno queda alguna
  verde. Pierde un 20 % de altura en invierno (`winter_flatten`).
- **Terreno** (`planet_biomes.gdshader`): las texturas de `"meadow_textures"` (en
  `climate_settings.terrain` del JSON: la pradera entera y el barro con vegetación a medias)
  cambian igual, para que no haya salto donde termina la hierba (130 m).

## Sotobosque

`scripts/planet/understory_geometry.gd` marca cada pieza en `COLOR.a` (1 hoja, 0,75 tallo,
0,5 flor) y da a cada especie su comportamiento (`SEASONS`):

| Especie | Hojas | Flores |
|---|---|---|
| Helechos, hoja ancha, flores silvestres, algodoncillo, amapola ártica | Herbácea: se agostan con la pradera (helechos rojizos) | Silvestres en primavera; hoja ancha: dos espigas blancas y lila a finales de primavera; algodoncillo y amapola en verano |
| Arbusto redondo, florido, sauce, abedul enano | Caducas: color de otoño y caen por hojas | Redondo: racimos de flor amarilla de retama en la mitad de sus brotes exteriores; florido: el doble de racimos rosas, y el doble de matas (0,020/m²); sauce: amentos a principios de primavera |
| Enebro, esparraguera, brezo | Perennes | Brezo a finales del verano; las gálbulas del enebro siempre |
| Liquen | — | — |

- La hoja caída y la flor cerrada se quitan estrechando la pieza a su eje (`CUSTOM0`, el mismo
  desplazamiento del morph de LOD).
- Las flores se abren en su ventana (`bloom_center`, `bloom_width`, en fase local), cada mata a su
  ritmo. Sin estaciones (ecuador) están siempre abiertas.
- El abedul enano estaba en otoño todo el año; ahora es verde y el rojo lo pone el shader.
- Las flores de los arbustos son geometría (`_flower_cluster`, `_flower`; la espiga de la hoja
  ancha lleva su tallo como pieza de flor, que se cierra con ella). Se generan al final de cada
  especie, después de copa y hojas: el generador es un solo RNG y así la mata queda igual que
  antes. Coste en LOD0: redondo 2.748 → 4.473 triángulos, florido 3.423 → 4.323, sauce
  2.398 → 2.530, hoja ancha 286 → 554; los LOD lejanos conservan solo parte de las flores.

## Clima y tiempo

**Frío de la estación.** `season_chill` (en `shaders/lib/season_calendar.gdshaderinc`, que incluye
`climate.gdshaderinc`) vale 0 en lo más cálido del verano y 1 en lo más frío del invierno, con
retraso térmico (`SEASON_THERMAL_LAG` 0,05: la primavera sale más fría que el otoño). Las funciones
de frío del clima (`climate_coldness`, `climate_snow_coldness`) le suman `SEASON_WINTER_COLD` (14°)
por él: en invierno la cota de nieve baja en terreno, hierba, árboles y rocas a la vez. A 28° de
latitud el invierno nieva el suelo; a 17° (el inicio), solo las lomas. El verano es la calibración de
siempre. No lo llevan las zonas de vegetación (`ClimateGraph`, el bosque no se mueve), ni el hielo
marino (sus placas son física en CPU), ni los hábitats de la fauna.

En CPU, `ClimateField.snow_coldness()` es la réplica (`Seasons.chill`): la usan las pisadas en
nieve y el tiempo atmosférico. `coldness()` sigue sin estación.

**Tiempo atmosférico** (`WeatherController`):

- El frío de la estación decide la zona del jugador: en invierno la taiga (con su refuerzo de nieve
  y niebla) llega más cerca del ecuador, y la lluvia de los temporales cae como nieve allí donde el
  frío de la estación llega a la cota. Esa nevada baja aún más la cota (`climate_fresh_snow`).
- Pesos por estación (`"season_weights"` en `weather_settings` del JSON): multiplican los del perfil
  del sitio, repartidos entre las dos estaciones más cercanas (centros a 1/8, 3/8, 5/8 y 7/8 del año
  local). Verano despejado, otoño de temporales, viento y niebla, invierno de niebla y nieve. En el
  ecuador no cambian.
- Con el calendario acelerado (`estacion velocidad`) los eventos duran proporcionalmente menos y la
  transición se acorta hasta 2 s: el tiempo sigue a la estación. Al saltar de fecha (`estacion
  otoño`) el evento se sortea de nuevo en el acto (`WeatherController.reroll`), salvo uno forzado.

## Fauna

Cada especie tiene su actividad de día, crepúsculo y noche, y por estación: las aves no salen de
noche y migran en invierno, los osos hibernan, los zorros y los ciervos salen al anochecer. Ver
[ambient_fauna.md](ambient_fauna.md).

## Herramientas

- Consola: `estacion` informa de la fecha y de la estación, la latitud y las horas de luz donde
  estás; `estacion otoño` (o `primavera`, `verano`, `invierno`) salta a esa estación en tu
  hemisferio; `estacion 19.5` a un día; `estacion velocidad 50` acelera el calendario (no se guarda).
- `tests/vegetation/tree_designer.tscn -- --seasons=0.08,0.38,0.6,0.85 [--only=almond_01]`: una
  hoja por árbol con el LOD0 en cada fase. `--season=0.6` deja la hoja normal en esa fase.
- `tests/lighting/lighting_capture.tscn -- --day=19.2`: capturas del juego en esa fecha.

## Pendiente

- Hielo marino estacional (las placas son física en CPU).
- Hojas cayendo; textura de ramita con flor para los frutales.

# Creación de personaje

Al pulsar **Nueva partida** el menú principal abre `CharacterCreationScreen` en
lugar de lanzar la cinemática. El jugador elige nombre, sexo y apariencia sobre
una vista previa 3D (`CharacterPreview`): con el botón izquierdo gira alrededor
del personaje, con el derecho o el central sube y baja por el cuerpo, y la
rueda acerca hacia la altura del cursor. Cada categoría tiene su encuadre, y
los botones **Cuerpo** y **Rostro** devuelven la cámara al suyo. El idle del
juego es una postura de guardia encorvada; en la vista previa `PreviewPosture`
endereza columna, cuello y hombros (conserva un 30 % de su giro, así que se
sigue viendo la respiración) y `PreviewHeadAim` gira la cabeza hacia la cámara. A la derecha, **Vista**
cambia de encuadre y **Luz** cambia entre el estudio (la piel con su color) y dos
luces como las de la partida, de día y de hoguera, con la curva ACES del mundo.

El panel tiene arriba el nombre y el sexo, a la izquierda las categorías y a la
derecha sus opciones. Las elecciones (peinados, barbas, cejas, rostros y
pieles) son fichas con un retrato del propio personaje con cada una puesta:
`ChoiceThumbnails` las hace fuera de pantalla con un segundo modelo y las luces
del estudio, una por fotograma, y solo vuelve a retratar una opción si cambia
algo de lo que se ve en ella. Una elección nueva del catálogo sale retratada sola,
con el encuadre de la cara; si necesita otro, se le da en
`ChoiceThumbnails.FRAMING`.

Al pulsar **Comenzar partida**, el `CharacterData`
resultante pasa a `GameManager.character` y arranca la cinemática. **Volver al
menú** (o Escape) cancela y devuelve el menú. Para ello `GameManager` tiene el
estado `CHARACTER_CREATION`, añadido al final del enum para no alterar los
estados de las partidas ya guardadas.

La cinemática calcula un aterrizaje nuevo en cada partida, entre 35° y 45° norte,
fuera de la banda desértica del planeta. `NewGameLanding` usa el mapa para descartar
agua y consulta el SDF del terreno actual para comprobar la altura, la pendiente
y el suelo alrededor. Se exige el sol al menos 10° sobre el horizonte local.
El marcador precarga las colisiones del destino mientras la cámara baja desde
una altura proporcional al radio del planeta. Al terminar se activa la vista
inicial del jugador y se devuelven los controles cuando el suelo está listo.
El descenso avanza en física y mantiene visible la cámara, ocultando solo el
modelo del personaje, para que la interpolación no deje congelada la imagen.
**Continuar** conserva la posición guardada, incluso si está en otro planeta.

El jugador lleva siempre el cuerpo humano nuevo: el de su personaje si lo hay,
y si no uno por defecto. Lo guarda en la categoría `player` bajo la clave
`character`, y las partidas anteriores cargan con el aspecto por defecto.

## El modelo

El humano sale de [MakeHuman](http://www.makehumancommunity.org) a través de
MPFB, su extensión para Blender, con assets de sistema y de la comunidad
(CC0 y CC-BY; la atribución está en [character_credits.md](character_credits.md)).
Las texturas copiadas están en `textures/character/human/`. Sobre esa base:

- **Hombre y mujer comparten topología.** El cuerpo base es el masculino y el
  femenino es el morph `sex_female`. Los macros que dependen del cuerpo
  (músculo, peso, edad, altura, pecho) se hornean por sexo (`muscle@male`,
  `muscle-@female`) y, para que músculo y peso combinados no deformen, también
  sus cruces (`muscle&body_weight@male`...). La musculatura suma los targets
  locales de MakeHuman (hombros, brazos, espalda, pectorales).
- **Rasgos:** unos 70 *targets* de MakeHuman (forma de cabeza, frente, sienes,
  mandíbula, mentón, pómulos, ojos, cejas, nariz, boca, orejas, cuello...), cada
  uno con sus dos lados: `nose_width` para valores positivos y `nose_width-`
  para negativos. Los rasgos africanos y asiáticos solo mueven la cabeza.
- **Rostros:** `AppearanceCatalog.FACE_PRESETS` define siete puntos de partida
  por sexo. El primero de cada sexo es su cara por defecto: cambiar de sexo o
  pulsar **Restablecer** vuelve a él, y **Aleatorio** parte de uno al azar.
- **Pesos de piel:** los del modelo original del jugador, para el que se
  hicieron las animaciones. `dump_skeleton.gd` vuelca su malla y el exportador
  transfiere sus pesos al cuerpo de MakeHuman: el de cada vértice, desplazado
  por la diferencia entre sus articulaciones y las del jugador, sale de los
  vértices cercanos del escaneo que miran hacia el mismo lado. Manos, pies y
  cabeza conservan los de MakeHuman, más finos ahí. Los proxies los heredan del
  cuerpo por sus vértices de ajuste. El reposicionado sigue con los pesos de
  MakeHuman, así que cuerpo y proxies no se separan.
- **Articulaciones:** cada morph guarda cuánto mueve cada articulación, así que
  hombros, caderas o rodillas siguen al cuerpo. `HumanShape` calcula las
  posiciones en tiempo real y `BodyProportions` suma el desplazamiento de cada
  hueso a la pose animada. El esqueleto es el del jugador, con sus mismas
  animaciones: el exportador recoloca brazos, piernas, pies y dedos para que
  cada hueso apunte como en la pose de reposo del jugador. El tronco conserva
  la curva natural de MakeHuman (enderezarla plegaba la zona lumbar en un
  escalón) y solo reparte las articulaciones de la columna entre cadera y
  cuello como las del jugador (las de MakeHuman quedaban bajas y el idle
  doblaba la espalda como una joroba).
- **Proxies:** ojos, dientes, lengua, cejas, pestañas, pelos y barbas se
  reajustan al cuerpo con la fórmula de MakeHuman (tres vértices de referencia
  y un desplazamiento escalado), evaluada en tiempo real sobre los anclajes del
  cuerpo, así que siguen todos los morphs sin guardar un delta por proxy. Los
  ojos siguen el anillo de sus párpados.
- **Pieles:** ocho texturas por sexo (`AppearanceCatalog.SKINS`) con el tono
  como ajuste aparte. `human_skin.gdshader` tiñe respecto al tono medio de la
  textura, pinta labios, sombra de ojos, barba de tres días y rapado con
  máscaras (`make_skin_masks.py`) y usa un mapa de normales esculpido cuya
  profundidad sube con el músculo y baja con la grasa.
- **Desnudos:** los personajes no llevan ropa interior. MakeHuman modela la
  mujer en su malla base; los genitales del hombre son un *helper* de MakeHuman
  que MPFB oculta (`helper-genital`). El exportador lo convierte en una pieza
  más (`HELPERS`): sigue los morphs como un proxy cuyos vértices son sus
  propios anclajes, va rígido con la pelvis, lleva el material de la piel del
  cuerpo y toma sus UV de un parche del interior del muslo (en el atlas le
  toca una esquina lisa, sin poros ni relieve). Los targets de MakeHuman dan
  sus sliders: longitud, grosor y testículos.
- **Vello púbico:** lo pinta la piel, como la sombra de barba.
  `make_skin_masks.py` genera `body_masks.png` con un campo por sexo (R mujer,
  G hombre, que al máximo sube en línea hasta el ombligo) que vale 1 en el
  centro y baja hasta 0 en su alcance máximo; el slider **Vello púbico**
  (`pubic_hair`) es el umbral, así que va de un parche recortado a uno
  natural. Los rizos son el canal G de `stubble.png`, sobre una base oscura
  del color del pelo.
- **Parpadeo:** los targets de cierre de párpados de MakeHuman
  (`expression/units/caucasian/eye-*-closure`) se hornean por sexo como el
  morph `blink@<sexo>`, que no es un slider. `HumanBlink`, hijo de
  `CharacterAppearanceRig`, parpadea cada 2-6 s (a veces dos veces seguidas)
  moviendo blend shapes: en la vista previa las del propio cuerpo, en partida
  la única que conserva el cuerpo horneado (`blink`). Las pestañas llevan su
  propia blend shape `blink`, ajustada a los párpados cerrados; los globos
  oculares no se mueven. Al cerrar, el parpadeo relaja los morphs que dan
  forma a la abertura (`HumanShape.BLINK_RELAXES`: apertura y párpado): si no,
  un ojo muy abierto no llegaría a cerrar y un párpado caído se plegaría
  sobre sí mismo.
- **Pelo:** `human_hair.gdshader` dibuja el núcleo opaco de las tarjetas con
  alpha to coverage y su `next_pass`, `human_hair_fringe.gdshader`, mezcla el
  borde fino, así que el pelo largo no tiene franjas de ordenación. Al hornear,
  las texturas de pelo pierden la luz pintada (manchas) y se quedan con los
  mechones en gris; el color sale del ajuste y es el mismo en todos los
  peinados. Hay peinados propios de cada sexo; rapado y calvo, para ambos.
  Bajo cualquier peinado la piel pinta raíces en el cuero cabelludo
  (`scalp_hair`, `scalp_spread`), así que la línea del pelo no queda desnuda.

En la pantalla de creación el cuerpo lleva un blend shape por morph y los
proxies se reajustan en cada cambio. En partida `CharacterAppearanceRig`
hornea los pesos elegidos en mallas estáticas una sola vez. La vista previa usa
luces de estudio y tonemapping lineal para que la piel se vea con su color.

## Regenerar

Necesita Blender 4.5 con MPFB y los packs de MakeHuman instalados en MPFB: el
de sistema, `hair01`, `hair02`, `hair03`, `bodyparts05`, `bodyparts06`,
`skins01` y `skins02` (de files.makehumancommunity.org).

```sh
# 1. Esqueleto y malla (con sus pesos) del jugador -> JSON
godot --headless --path . --script res://tools/character/dump_skeleton.gd -- $PWD/build/character/mpfb/skeleton.json
# 2. Humano de MPFB -> build/character/mpfb/human.{json,bin} (~1 min)
blender -b --python tools/character/blender/export_mpfb_human.py -- \
    $PWD/build/character/mpfb/skeleton.json $PWD/build/character/mpfb
# 3. Máscaras de piel (cuero cabelludo, barba, vello púbico) y mapa de normales femenino
blender -b --python tools/character/blender/make_skin_masks.py -- $PWD/build/character/mpfb
# 4. Recursos de Godot (data/character/human/) y texturas
godot --headless --path . --script res://tools/character/bake_character_human.gd
godot --headless --editor --quit --path .    # importa las texturas nuevas
godot --headless --path . --script res://tools/character/fix_texture_imports.gd
godot --headless --editor --quit --path .    # las reimporta con VRAM y mipmaps
# Pruebas
godot --headless --path . --script res://tests/character/test_character_appearance.gd
```

El horneado no borra lo que sobra: si se quita un proxy del exportador hay que
borrar su `.res` en `data/character/human/proxies/` y sus texturas.

`tests/character/character_creation_preview.tscn` abre la pantalla sola. Con
`-- --capture` guarda capturas en `build/character/creation/` (necesita
ventana).

## Ampliar

- **Una opción nueva**: una línea en `AppearanceCatalog._build()` dentro de su
  categoría (`_morph`, `_shader_slider`, `_color` o `_choice`). La interfaz,
  el guardado y el aleatorio salen solos. `_for_sexes` la limita a un sexo.
- **Un rasgo de MakeHuman nuevo**: una entrada en `TARGET_MORPHS` (o
  `MACRO_MORPHS`) del exportador con los targets de cada lado, volver a
  ejecutar el proceso y añadir una opción `_morph` con ese id.
- **Un rostro**: una entrada en `FACE_PRESETS` con los sliders que cambia.
- **Un peinado, una barba o unas cejas**: el asset en `HAIRS`, `BEARDS` o
  `PROXIES` del exportador y una entrada en `HAIR_STYLES` (con sus `sexes`),
  `BEARDS` o `EYEBROW_STYLES` del catálogo. Si el asset es CC-BY, hay que
  añadirlo a los créditos.
- **Una categoría**: una llamada más a `_category()`, con su encuadre de cámara
  (`body`, `head` o `face`).
- **Una pantalla nueva** (habilidades, atributos...): una subclase de
  `CreationStep` añadida a `CharacterCreationScreen.STEPS`. La cabecera,
  Atrás / Siguiente y la validación (`can_continue`, `blocking_reason`) se
  adaptan solas. Los datos nuevos van en `CharacterData` y en su
  `to_dict`/`from_dict`.

## Armaduras

Las armaduras equipables se modelaron sobre el escaneo anterior del jugador,
un hombre de 1,90 m bastante más corpulento que el cuerpo de MakeHuman. Al
equiparlas, `CharacterAppearanceRig.dress()` las ajusta al cuerpo del
personaje en dos pasos (`ArmorFit`):

- **Medidas.** `BodyMeasurements` mide un cuerpo en la pose de reposo del
  esqueleto: para cada hueso, los vértices que más mueve, en el marco del
  hueso, cortados en seis rodajas a lo largo de él, con el ancho y el fondo
  de cada una. Las del escaneo están horneadas en
  `data/character/armor_fit/reference_body.tres`; las del personaje se toman
  al cambiar su cuerpo (`rig.measurements()`). Cada vértice de la armadura
  pasa, hueso a hueso según sus pesos, de las rodajas del escaneo a las del
  personaje: a lo largo del hueso, de una región a la otra, y a lo ancho y a
  lo hondo, escalado dentro del contorno del escaneo y a la misma distancia
  fuera de él, para que la armadura conserve su grosor y su holgura.
- **Holgura.** Lo que aún queda dentro del cuerpo (o a menos de 4 mm, y
  hasta 7 cm de hondo: un pecho mucho más ancho que el del escaneo se
  traga el cuello de una túnica) se empuja hacia fuera por la normal de la
  piel (cuerpo y genitales). El empuje
  es un campo suave en el espacio, no por la malla: las armaduras son piezas
  sueltas y capas que se tocan, y así se mueven juntas sin abrir rendijas.

- **Pelo bajo capuchas y cascos.** Una pieza que cubre la cabeza (el jugador
  lo indica al equipar las de la ranura `HEAD`: `dress(item, true)`) mete
  debajo el pelo y la barba (`HairTuck`). Desde el centro de la cabeza, la
  pieza es un mapa octaédrico de a qué distancia está su superficie interior
  en cada dirección. En las que cubre, el pelo se comprime hacia la cabeza
  hasta caber debajo, conservando sus capas (de su punto más interior al más
  exterior, todo se escala al hueco que deja la pieza). Donde no cubre, en la
  abertura de la cara o bajo el borde, el pelo no se toca, así que el
  flequillo, los mechones de la cara o el pelo largo que cae por debajo se
  siguen viendo. El mapa se difumina en los bordes para que el pelo salga de
  ellos sin escalón. Al quitar la pieza (`undress()`) el pelo vuelve a su
  forma.

Las medidas también dan un resumen con nombre en metros (`summary`: altura,
hombros, contorno de pecho, cintura, cadera, cabeza, brazo, antebrazo,
muslo, gemelo, largo de brazo, pierna y torso, y ancho y fondo de pecho,
cintura y cadera). Se parecen a las de un sastre sin ser las mismas: cada
región acaba donde su hueso deja de ser el que más mueve la piel. No se
guardan en la partida porque salen del aspecto.

El ajuste tarda unos 100 ms por pieza y corre en el `WorkerThreadPool`,
igual que el del pelo, que va después; mientras tanto la pieza está oculta
(`is_dressing()`), así que nunca se ve el pelo atravesándola. Cada malla ajustada
se guarda por pieza y cuerpo, y un cuerpo nuevo vuelve a ajustar lo que el
personaje lleva puesto. La malla nueva conserva materiales y LODs.

```sh
# Medidas de referencia (solo si cambian el escaneo, su piel o el esqueleto)
godot --headless --path . --script res://tools/character/bake_armor_reference.gd
# Pruebas
godot --headless --path . --script res://tests/character/test_armor_fit.gd
# Capturas de seis cuerpos y el escaneo con cada conjunto (necesita ventana);
# --unfitted deja las armaduras como se hicieron y --untucked el pelo suelto,
# para comparar
godot --path . res://tests/character/armor_fit_preview.tscn -- --out res://build/character/armor_fit/after
```

### Prendas de Meshy

Las prendas de pieles con pelo y de cuero (`scenes/items/armor/stone_age/`)
se generaron con [Meshy](https://www.meshy.ai) desde imágenes de referencia:
cada una es un modelo suelto, sin cuerpo ni esqueleto, con texturas PBR.
`tools/character/blender/fit_meshy_armor.py` las pone sobre el escaneo y las
pesa con su piel, así que quedan como las demás: hechas para el escaneo, y
`ArmorFit` las lleva a cada cuerpo.

- **Colocar**, según el hueco de cada una (`stone_age_armor.json`):
  - peto: escalado, con el cuello sobre el del escaneo y centrado en el torso.
    Si se hizo sobre un maniquí ancho (el manto es un poncho), `"ease"` lo
    recoge por debajo de las axilas: los costados quedan a 2 cm del torso,
    para que el brazo bajado caiga por fuera en vez de atravesarlo, y delante
    y detrás cuelga desde lo que más sobresale el pecho o la espalda. Lo que
    está sobre el torso (la bolsa del manto) no se deforma. Su tercer valor
    vale por encima de las axilas, después de la holgura: nada queda a más de
    4 cm de la piel (el manto llevaba en los hombros una piel de 10 cm que
    parecía una hombrera); desde 2 cm se acerca a la piel en línea recta, así
    que sus capas no se cruzan. Lo que quedaba dentro del cuello se quita
    (un modelo hecho sobre maniquí está cerrado por arriba y, empujado fuera
    del cuello, levantaba un embudo), así que queda un escote;
  - calzones: cintura y bajo a las alturas que se le dan, y cada pernera
    llevada rodaja a rodaja sobre la pierna del escaneo (salvo un faldellín);
  - `"turn"` gira antes un modelo hecho del revés (el faldellín, con la bolsa
    de conchas por detrás);
  - `"length"` alarga o acorta solo lo que queda por debajo de las axilas
    (peto) o de la cintura (calzones), sin ensancharlo: el manto llega a la
    cadera (0,67) y el faldellín, por delante, a la rodilla (1,6). `"floor"`
    es lo más bajo a lo que llega algo (sus tiras, a media espinilla): lo que
    pasaría se alarga menos, sin bajar del 70 % de su alto (aplastado del todo
    quedaba como una repisa entre las piernas);
  - manos y pies: un solo modelo, puesto en cada lado y reflejado para el
    otro. La manopla se centra en la carne de la mano (palma y cuatro dedos),
    se ensancha hasta su grueso y su pulgar gira hasta el del escaneo, que
    lo tiene abierto: así toma sus pesos y lo sigue al agarrar. La suela se
    aplana bajo el pie (una puntera que sube dejaría fuera los dedos) y la
    caña sigue la espinilla.
- **Holgura**: lo que queda dentro del cuerpo o a menos de 8 mm (más en el
  manto y las botas) sale empujado por la normal de la piel; también donde la
  piel asoma entre vértices de un triángulo grande y, en manos y pies, donde
  un punto de la mano o del pie no tiene prenda delante. En manos, pies y
  piernas solo se saca lo que está a menos de 3,5 cm de hondo (más hondo es
  que ha pasado al otro lado de un dedo); en el peto, hasta 10 cm, porque los
  hombros de un maniquí quedan muy dentro de los del escaneo (el manto no
  tiene escote: su parte de arriba quedaba enterrada en los trapecios y se
  veía la piel). El empuje se reparte como en `ArmorFit`.
- **Relajado**: cada vértice sale empujado lo suyo, y eso estira los
  triángulos de entre medias y la textura que llevan (en las mangas del
  manto, más del cuádruple). Después del empuje la prenda se relaja como una
  tela (`relax()`): cada arista vuelve hacia el largo que tenía al colocarla,
  sin acercarse a la piel más que su holgura, y se empuja otra vez. Lo
  estirado a más del doble pasa del 26 al 13 % del manto, del 21 al 12 % del
  faldellín, del 10 al 4 % de la túnica y del 8 al 4 % de las calzas.
- **Capas**: un peto va por encima de los calzones que lista en `"over"`
  (que se ajustan antes): lo que queda bajo ellos, o a menos de su holgura,
  sale hacia fuera, así que la bolsa del faldellín no asoma por el manto.
- **Pesos**: los de la piel del escaneo en su punto más cercano, solo de los
  huesos que puede seguir cada hueco (el peto no sigue el antebrazo ni la
  cabeza: lo de esos pasa al padre permitido). Lo que va pegado a la piel (a
  menos de 4 cm) los conserva casi sin suavizar, para moverse como la piel de
  debajo y que no asome el hombro o la cadera; lo suelto (desde 10 cm) los
  toma de la prenda que tiene alrededor. Por debajo de la entrepierna, el
  faldón de un peto o un faldellín sigue a los muslos (un 95 % por delante,
  para montar sobre el que avanza; un 65 % por detrás; el resto, la cadera),
  repartido entre los dos según lo ladeado que cuelga: el centro sigue a los
  dos a la vez, así que no se raja cuando se abren las piernas. Un faldellín
  que cuelga (`"hang"`, el de pieles) cuelga de los huesos de falda (ver
  *Faldas que se mueven*): desde 5 cm sobre su anillo hasta 5 cm por debajo
  pasa de los pesos de la piel a los de las dos cadenas que tiene a los lados,
  repartido entre ellas por el ángulo y, a lo largo, entre las dos
  articulaciones entre las que queda; por delante, la mitad va además a los
  muslos (`HANG_RIDE`, repartida como el faldón de un peto): solo con las
  cadenas, un muslo que avanza la atravesaba entre dos. Sin esos huesos en
  `body.json`, sigue a la cadera desde sus articulaciones y a los muslos solo
  un 15 % por delante y un 5 % por detrás (`HANG_THIGHS`). Su forro se queda
  en la cadera y las nalgas (en los muslos parecería unas mallas). Antes de
  apartarla de la piel, lo que tiene dentro de las piernas sale hacia fuera
  desde la cadera, como la tela que cae sobre las dos: empujado por la normal
  de la pierna la rodeaba, y como no la sigue, al moverla quedaba un anillo
  cruzándola. Una falda no sigue a las espinillas ni a los pies: lo que su
  bajo tomaría de ellos pasa al muslo y, de ahí, a la cadera. `"flare"` la
  abre hacia los lados hasta el bajo (el faldellín, un 35 % más ancho abajo
  que en la cintura); por delante se recoge con `"ease"` como un peto, para
  que cuelgue a plomo desde la tripa y no por delante de las rodillas, y
  `"forward"` adelanta el delantero desde la cintura hasta la entrepierna y lo
  deja colgar de ahí (el faldellín, 7 cm: si no, el muslo de la pierna que va
  adelantada al estar quieto quedaba por delante de él). Lo que cuelga del
  brazo (una manga) conserva los pesos de la piel aunque esté lejos:
  siguiéndolo a medias, al bajar el brazo quedaba fuera como una hombrera.
  Después se suaviza el campo de pesos por distancia en metros (8 cm en
  petos —12 en la túnica, mediante `"weight_radius"`—, 5 en calzones, 1,8 en
  manoplas y 2 en calzado), incluyendo las capas
  de pelo sueltas y unificando los vértices de las costuras UV: suavizar solo
  por aristas dejaba saltos entre triángulos diminutos o mechones separados.
  En una manopla (`"mitten": true`), los cuatro dedos de su bolsa siguen las
  falanges del dedo medio; el pulgar conserva sus propios huesos. El reparto
  entre el delantero del faldellín, que monta sobre los muslos, y la espalda
  que cuelga se hace a través de todo el costado (24 cm), para que no se
  estiren uno contra otro al correr. Se conservan ocho influencias por
  vértice, sin cortar los pesos pequeños al 1 %: cuatro descartaban de golpe
  una cadena de falda o un muslo al cambiar su puesto entre los pesos mayores.
- **Forro** (`"liner": true`, petos y calzones): la propia piel del
  escaneo donde la prenda la tapa, a hasta 1,2 cm de ella en el peto y
  0,9 cm en los calzones (que no se pisen en las caderas), y siempre menos
  que la holgura de la prenda; mate y del color medio de la prenda oscurecido. Sus
  pesos son los de la piel suavizados como se suavizaron al pasarlos al
  cuerpo de MakeHuman, así que se dobla como la piel del personaje: por los
  rotos de la prenda, o donde la piel la atraviesa en una postura, se ve
  cuero y no carne. Cuenta como tapado lo que tiene prenda delante en al
  menos 4 de 9 rayos; los huecos pequeños se cierran y el borde queda un
  anillo por dentro, así que el escote o las sisas siguen abiertos.
- **Juego**: `tools/character/bake_meshy_armor.gd` escribe las texturas
  (JPEG de 2048 px, la rugosidad de 1024), la malla con su material
  (`models/equipable/stone_age/<id>.res`, con la piel del escaneo) y la
  escena equipable, que lleva su `data/items/Armor/StoneAge/<id>.tres`. Una
  falda que cuelga de los huesos de falda lleva otra Skin,
  `firstage_human_male_player_skirt_skin.tres`: la del escaneo y la de esos
  huesos, sacada de su reposo en el esqueleto del personaje.

### Faldas que se mueven

`SkirtBones` son los huesos de una falda: 8 cadenas de 4 alrededor de la
cadera, colgando a plomo desde un anillo un poco por encima de las
articulaciones de las caderas hasta la rodilla. El anillo empieza medio paso
girado desde el frente, así que hay una cadena delante de cada muslo y otra
detrás de cada nalga, que son quienes la empujan. Su reposo sale del propio
esqueleto (la separación entre las caderas da el tamaño), así que el ajuste en
Blender (`dump_skeleton.gd` los escribe en `body.json`, en el espacio del
escaneo) y el juego los ponen en el mismo sitio. No están en el esqueleto
hasta que se viste una pieza cuya Skin los usa: `dress()` los añade (cuelgan
de la cadera) y rehace el contexto de `ArmorFit`, que lleva un hueso que la
referencia no tenía como su antepasado medido más cercano, la cadera.

Mientras alguna pieza puesta los use, `SkirtSwing` (un `SpringBoneSimulator3D`
hijo del esqueleto, detrás de `BodyProportions`) los mueve: cada cadena cae
por la gravedad, vuelve poco a poco a colgar como en reposo desde la cadera, y
la empujan unas cápsulas en muslos y espinillas, ajustadas a la carne de ese
cuerpo (`BodyMeasurements`, la mediana de las secciones de cada hueso) y no
centradas en el hueso: el muslo abulta mucho por delante del fémur, y una
cápsula centrada se quedaba unos 6 cm por detrás de la piel. Simula en el
espacio del propio esqueleto: con el `Armature` a escala 0,01, en el del mundo
las articulaciones y las formas de choque no coinciden (sus radios se quedan
en unidades del esqueleto). Por eso sus longitudes y velocidades van en
unidades del esqueleto, y el movimiento del cuerpo por el mundo, que ese
espacio no ve, entra como fuerza externa: la aceleración del cuerpo,
suavizada, la echa hacia el otro lado al arrancar, frenar o girar. Al quitarse
la pieza se apaga; los huesos se quedan, sin peso en nada.

Los modelos de Meshy no están en el repositorio: se buscan en la carpeta que
se le da (las descargas, `stone_age_armor/` y `stone_age_armor_2/`).

```sh
# 1. Escaneo, sus triángulos y sus pesos -> JSON
godot --headless --path . --script res://tools/character/dump_skeleton.gd -- $PWD/build/character/meshy/body.json
# 2. Ajustar (unos 15 s todas; deja vistas previas <id>_preview_*.png)
blender -b --factory-startup --python tools/character/blender/fit_meshy_armor.py -- \
    build/character/meshy/body.json tools/character/blender/stone_age_armor.json ~/Descargas build/character/meshy [id...]
# 3. Texturas; importarlas; mallas y escenas
godot --headless --path . --script res://tools/character/bake_meshy_armor.gd -- $PWD/build/character/meshy [id...]
godot --headless --path . --import
godot --headless --path . --script res://tools/character/bake_meshy_armor.gd -- $PWD/build/character/meshy [id...]
# 4. Iconos (necesita ventana)
godot --path . --script res://tools/ui/bake_item_icons.gd -- --background --only=fur_mantle,fur_loincloth,hide_tunic,hide_trousers
```

Una prenda nueva es una entrada más en el JSON (o uno nuevo para otra edad),
su `ItemData` y su receta, y una línea en `ARMOR` de `bake_item_icons.gd`.

Para regenerar solo los pesos de las ocho prendas ya horneadas, sin las
descargas de Meshy, se exporta su geometría y se aplica el nuevo reparto.
Se conservan posiciones, normales, UV, materiales, forros y escenas:

```sh
mkdir -p build/character/armor_weights/source build/character/armor_weights/fitted
godot --headless --path . --script res://tools/character/dump_skeleton.gd -- $PWD/build/character/armor_weights/body.json
godot --headless --path . --script res://tools/character/bake_meshy_armor.gd -- --export-weights $PWD/build/character/armor_weights/source
blender -b --factory-startup --python tools/character/blender/fit_meshy_armor.py -- \
    build/character/armor_weights/body.json tools/character/blender/stone_age_armor.json \
    build/character/armor_weights/source build/character/armor_weights/fitted --reweight
godot --headless --path . --script res://tools/character/bake_meshy_armor.gd -- --weights $PWD/build/character/armor_weights/fitted
godot --headless --path . --script res://tests/character/test_armor_deformation.gd
```

La prueba mide las aristas de las prendas ajustadas al cuerpo en quieto y
en dos momentos de carrera, con la física de la falda desactivada para aislar
el rigging: al menos el 99 % debe estirarse menos del doble y ninguna arista
de al menos 2 mm puede llegar a 4,5 veces su largo de reposo. Comprueba
también que el ajuste conserva las ocho influencias y sus pesos normalizados.

Para verla puesta sin abrir ventana: `dump_dressed.gd` viste el modelo como el
juego (con el aspecto de una partida si se le da), lo pone en un momento de
una animación y vuelca lo que se ve, deformado por el esqueleto;
`render_dressed.py` lo dibuja en Blender de frente, de lado, de espaldas y a
tres cuartos (y desde arriba, `above`; desde delante y abajo, `low_front`).
`--anim=none` lo deja en la pose de reposo, en la que se ajusta. Lo que se
mueve solo (una falda) necesita fotogramas: `--frames=N` vuelca tras N, con la
animación quieta en `--time` o, con `--play`, avanzando desde ahí; mejor con
`--fixed-fps 60` de Godot. `--still` la deja como se ajustó, sin física (para
saber si algo raro es del ajuste o de la simulación).

```sh
godot --headless --path . --script res://tools/character/dump_dressed.gd -- $PWD/build/character/dressed/a.json \
    --appearance=$HOME/.local/share/godot/app_userdata/VoxelTest/saves/main_save_player.json \
    --armor=res://scenes/items/armor/stone_age/fur_mantle_equipable.tscn,... [--anim=running --time=0.25] [--play --frames=40]
blender -b --factory-startup --python tools/character/blender/render_dressed.py -- \
    build/character/dressed/a.json build/character/dressed/a.png [b.json ...] [--views=front,three] [--zoom=1.7]
```

Con ventana, `tests/combat/anim_stage.gd` las ve en movimiento:
`--armor=stone_age:fur_` viste solo esas piezas, `--appearance=` usa el cuerpo
de una partida y las vistas `hips_side`, `hips_front`, `hips_back`,
`chest_front` y `chest_back` siguen de cerca caderas y pecho.

`CharacterAppearanceRig` sirve para cualquier modelo con la estructura
`Armature/Skeleton3D/Mesh_0` (el `PlayerModel` o
`scenes/character/character_model.tscn`), así que también puede vestir PNJ.

## Limitaciones

- Las armaduras tienen huecos de diseño (muslo del pantalón de cuero, rotos
  de la túnica de pieles) por los que en el escaneo se veían sus calzoncillos
  y ahora se ve la piel. Entre muslos que se tocan (cuerpos muy corpulentos)
  pueden quedar unos pocos vértices del pantalón dentro del cuerpo, donde no
  se ven. La capucha de pieles está abierta por detrás: por ahí se ve el pelo
  (o el cuero cabelludo pintado si va rapado).
- El pelo largo que cae por la espalda aún atraviesa el peto: solo las piezas
  de cabeza lo recogen.
- Las prendas de Meshy tienen rotos y tiras de diseño (el faldellín en las
  caderas); el forro tapa la piel bajo los del peto y los calzones. Solo los
  petos se separan de otras prendas (de los calzones de `"over"`): los bajos
  de unas calzas pueden asomar por la caña de las botas. Los bordes de las
  pieles del manto tienen alguna punta suelta que sobresale.
- El aspecto es el de MakeHuman: limpio y de juego, no fotográfico. Algunos
  peinados son mallas esculpidas más que mechones.
- El mundo usa ACES, que apaga algo la piel respecto a la vista previa.
- Algunos peinados (`classic`) acaban en un borde de malla duro, más bajo que
  la línea del pelo natural.
- Los recursos horneados ocupan unos 19 MB y las texturas unos 50 MB (PNG y
  JPEG; en VRAM van comprimidas). Guardar los deltas en 16 bits o las texturas
  en WebP lo reduciría.

# Creación de personaje

Al pulsar **Start Game** el menú principal abre `CharacterCreationScreen` en
lugar de lanzar la cinemática. El jugador elige nombre, sexo y apariencia sobre
una vista previa 3D (`CharacterPreview`): con el botón izquierdo gira alrededor
del personaje, con el derecho o el central sube y baja por el cuerpo, y la
rueda acerca hacia la altura del cursor. Cada categoría tiene su encuadre, y
los botones **Cuerpo** y **Rostro** devuelven la cámara al suyo. El idle del
juego es una postura de guardia encorvada; en la vista previa `PreviewPosture`
endereza columna, cuello y hombros (conserva un 30 % de su giro, así que se
sigue viendo la respiración) y `PreviewHeadAim` gira la cabeza hacia la cámara. Al pulsar **Comenzar partida**, el `CharacterData`
resultante pasa a `GameManager.character` y arranca la cinemática. **Volver al
menú** (o Escape) cancela y devuelve el menú. Para ello `GameManager` tiene el
estado `CHARACTER_CREATION`, añadido al final del enum para no alterar los
estados de las partidas ya guardadas.

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

`CharacterAppearanceRig` sirve para cualquier modelo con la estructura
`Armature/Skeleton3D/Mesh_0` (el `PlayerModel` o
`scenes/character/character_model.tscn`), así que también puede vestir PNJ.

## Limitaciones

- Las armaduras equipables se hicieron para el escaneo anterior y no se ajustan
  al cuerpo nuevo.
- El aspecto es el de MakeHuman: limpio y de juego, no fotográfico. Algunos
  peinados son mallas esculpidas más que mechones.
- El mundo usa ACES, que apaga algo la piel respecto a la vista previa.
- Algunos peinados (`classic`) acaban en un borde de malla duro, más bajo que
  la línea del pelo natural.
- Los recursos horneados ocupan unos 19 MB y las texturas unos 50 MB (PNG y
  JPEG; en VRAM van comprimidas). Guardar los deltas en 16 bits o las texturas
  en WebP lo reduciría.

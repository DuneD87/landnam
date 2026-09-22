# Creación de personaje

Al pulsar **Start Game** el menú principal abre `CharacterCreationScreen` en
lugar de lanzar la cinemática. El jugador elige nombre, sexo y apariencia sobre
una vista previa 3D. Al pulsar **Comenzar partida**, el `CharacterData`
resultante pasa a `GameManager.character` y arranca la cinemática. **Volver al
menú** (o Escape) cancela y devuelve el menú. Para ello `GameManager` tiene el
estado `CHARACTER_CREATION`, añadido al final del enum para no alterar los
estados de las partidas ya guardadas.

El jugador lleva siempre el cuerpo humano nuevo: el de su personaje si lo hay,
y si no uno por defecto. Lo guarda en la categoría `player` bajo la clave
`character`, y las partidas anteriores cargan con el aspecto por defecto.

## El modelo

El humano sale de [MakeHuman](http://www.makehumancommunity.org) a través de
MPFB, su extensión para Blender. La malla, las pieles, los ojos, las cejas,
las pestañas, los dientes y los pelos son CC0; las texturas copiadas están en
`textures/character/human/`. Sobre esa base:

- **Hombre y mujer comparten topología.** El cuerpo base es el masculino y el
  femenino es el morph `sex_female`. Los macros que dependen del cuerpo (peso,
  músculo, edad, pecho) se hornean por sexo (`body_weight@male`,
  `body_weight@female`) y el rig reparte el peso entre los dos.
- **Rasgos:** son los *targets* anatómicos de MakeHuman (nariz, ojos, boca,
  mentón, cejas, orejas, cintura...), cada uno con sus dos lados: `nose_width`
  para valores positivos y `nose_width-` para negativos.
- **Proxies:** los ojos (globos oculares con iris), las cejas, las pestañas,
  los dientes, la lengua y los pelos se reajustan al cuerpo en cada estado con
  la fórmula de MakeHuman, así que siguen todos los morphs. Los ojos van con el
  anillo de párpados porque los targets de ojos no mueven sus anclajes.
- **Esqueleto:** es el del jugador, con las mismas animaciones y sin
  retargeting. El exportador recoloca el humano para que cada hueso apunte como
  en la pose de reposo del jugador. Cada sexo tiene su `Skin` y unos
  desplazamientos de articulación (`HumanRigData`) que `BodyProportions` suma a
  la pose animada, de modo que las caderas, los hombros o las rodillas de cada
  cuerpo quedan donde toca. La altura escala el `Armature`; el tamaño de cabeza
  y el ancho de hombros son del mismo modificador.
- **Materiales:** `human_skin.gdshader` tiñe la piel respecto al tono medio de
  su textura, colorea labios y párpados con las máscaras UV de MPFB, añade SSS y
  pinta la ropa interior (solo la inferior; el top sigue disponible con
  `top_cover`) por bandas de altura de reposo (UV2). Los ojos usan
  `human_eyes.gdshader`, que recolorea el iris con una máscara radial. El pelo
  usa `human_hair.gdshader`, con tarjetas y alpha to coverage, y las cejas y
  pestañas `human_brows.gdshader`, con mezcla alfa. Todos tiñen respecto al tono
  medio de su textura, así que un mismo color de pelo se ve igual en todos los
  peinados.

En la pantalla de creación cada pieza lleva un blend shape por morph y los
sliders responden al instante. En partida `CharacterAppearanceRig` hornea los
pesos elegidos en mallas estáticas una sola vez, así que no hay mezcla de blend
shapes por frame.

## Regenerar

El proceso tiene dos pasos. Necesita Blender 4.5 con MPFB y el pack de assets
de sistema de MakeHuman (CC0) instalado en MPFB.

```sh
# 1. Esqueleto del jugador -> JSON
godot --headless --path . --script res://tools/character/dump_skeleton.gd -- $PWD/build/character/mpfb/skeleton.json
# 2. Humano de MPFB -> build/character/mpfb/human.{json,bin}
blender -b --python tools/character/blender/export_mpfb_human.py -- \
    $PWD/build/character/mpfb/skeleton.json $PWD/build/character/mpfb
# 3. Recursos de Godot (data/character/human/) y texturas
godot --headless --path . --script res://tools/character/bake_character_human.gd
godot --headless --editor --quit --path .    # importa las texturas nuevas
# Pruebas
godot --headless --path . --script res://tests/character/test_character_appearance.gd
```

Las texturas nuevas se importan con compresión VRAM y mipmaps: hay que
ajustarlo en su `.import` si se añaden más, porque el pelo sin mipmaps parpadea.

`tests/character/character_creation_preview.tscn` abre la pantalla sola. Con
`-- --capture` guarda capturas en `build/character/creation/` (necesita
ventana).

## Ampliar

- **Una opción nueva**: una línea en `AppearanceCatalog._build()` dentro de su
  categoría (`_morph`, `_proportion`, `_shader_slider`, `_color` o `_choice`).
  La interfaz, el guardado y el aleatorio salen solos. `_for_sexes` la limita a
  un sexo; los demás usan su valor por defecto.
- **Un rasgo de MakeHuman nuevo**: una entrada en `TARGET_MORPHS` (o
  `MACRO_MORPHS`) del exportador de Blender con los targets de cada lado,
  volver a ejecutar el proceso y añadir una opción `_morph` con ese id.
- **Un peinado o unas cejas**: el asset en `PROXIES` del exportador y una
  entrada en `AppearanceCatalog.HAIR_STYLES` o `EYEBROW_STYLES` con el nombre
  de la pieza. Sirve cualquier `.mhclo` (los packs de la comunidad de MakeHuman
  también son CC0).
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
- No hay barba: el pack de sistema de MakeHuman no incluye vello facial.
- El aspecto es el de MakeHuman: limpio y de juego, no fotográfico. Las pieles
  no traen mapa de normales.
- Los recursos horneados ocupan unos 17 MB y las texturas unos 39 MB. Guardar
  los deltas en 16 bits reduciría los primeros a la mitad.

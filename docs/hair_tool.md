# Peinados y barbas de Hair Tool

Los peinados y las barbas del creador de personajes salen de la biblioteca de
presets de Hair Tool (addon comercial de Blender). Cada preset se pasa a la
cabeza de MakeHuman, se convierte en tarjetas y se guarda como asset de
MakeHuman (`ht_<estilo>`). A partir de ahí es un proxy más: el exportador y el
horneado de `docs/character_creation.md` lo tratan como al resto, así que sigue
los morphs, el esqueleto y el ajuste bajo capuchas y cascos (`HairTuck`).

La lista está en `tools/character/hair_tool_styles.json`: por estilo, el preset
de la biblioteca, los subcomponentes que se le añaden (`extra`: coleta, trenza
o moño sobre una base recogida) y los sexos a los que se ofrece. El catálogo
(`AppearanceCatalog.HAIR_STYLES` y `BEARDS`) apunta a `hair_ht_<estilo>` y a
`beard_ht_<barba>`.

## En este equipo

- Blender 5.2 (presets): `/home/drive/tools/blender-5.2.3-linux-x64/blender`.
- Blender 4.5 con MPFB (assets): `/home/drive/tools/blender-4.5.14-linux-x64/blender`.
- Biblioteca: `/home/drive/tools/hair_tool_library/HairLibrary_52` (variables
  `BLENDER_52`, `BLENDER_45` y `HAIR_TOOL_LIBRARY` para cambiarlos).

Ningún paso abre ventanas ni necesita el addon: los presets llevan sus propios
nodos de geometría, que se evalúan en segundo plano. La biblioteca y los
archivos de trabajo (`build/character/hair_tool/lib/`) quedan fuera del
repositorio; los assets van a los datos de usuario de MPFB.

## Regenerar

```sh
python3 tools/character/blender/hair_tool_build.py            # todo (~35 min)
python3 tools/character/blender/hair_tool_build.py --only bob --render
python3 tools/character/blender/hair_tool_build.py --textures # solo texturas (~3 min)
```

Después, los pasos 1 a 4 de `docs/character_creation.md`. `--render` guarda
vistas de frente, tres cuartos y espalda en Cycles (CPU, sin ventana) en
`build/character/hair_tool/lib/<estilo>_<vista>.png`.

## Cómo funciona

1. **Cabeza base** (`hair_tool_base.py`, Blender 4.5): el humano neutro de
   MakeHuman (sexo 0,5, el cuerpo base del exportador), sin helpers.
2. **Preset a la cabeza** (`hair_tool_convert.py`, Blender 5.2). Todos los
   presets se peinaron sobre el mismo maniquí, que la biblioteca no incluye. El
   cuero cabelludo completo de `ShortHair` se ajusta una vez a la cabeza de
   MakeHuman (ICP con escala por eje y desplazamiento, sin giro: el cráneo de
   MakeHuman es un 15 % más estrecho) y esa transformación mueve cada preset.
   Luego el Shrinkwrap de su cuero cabelludo, que el addon apuntaría a la
   cabeza al añadirlo, se apunta a la de MakeHuman, y las guías lo siguen
   (`GN_MeshDeform`).
3. **Tarjetas**: la malla que generan los nodos, con sus UV. Se queda con las
   caras del atlas que más usan (el de pelo largo o el corto, `stubble`); si un
   preset trae color y opacidad aparte (Afro), se juntan en uno. Hair Tool
   dibuja mechones finos con huecos y cuenta con muchas capas mezcladas;
   nuestro shader solo tapa lo de detrás con lo que pasa de media opacidad,
   así que se veía el cuero cabelludo. Los mechones del atlas se ensanchan a
   lo ancho (`densify()`) y los sueltos y las puntas siguen finos, aunque eso
   ayuda poco: lo que tapa es no quitar tarjetas (punto 4).
4. **Presupuesto**: cada tarjeta se reduce a la mitad de filas (Decimate
   *un-subdivide*: no se nota y ahorra un 45-50 %; una segunda pasada no ahorra
   más). Si aún pasa del presupuesto (26 000 triángulos un peinado, 20 000 una
   barba: en la práctica, ninguno pierde tarjetas), se quitan tarjetas enteras
   al azar hasta entrar. Con 12 000, De punta perdía la mitad y enseñaba el 13-29 %
   del cuero cabelludo; con todas, el 3-4 %. `unsubdivide: 0` en el JSON evita
   el paso anterior para tarjetas demasiado cortas (Afro).
5. **Asset** (`hair_tool_mhclo.py`, Blender 4.5): MakeClothes de MPFB ancla
   cada vértice a tres del cuerpo neutro, con las escalas de la cabeza, y
   escribe `.mhclo`, `.obj`, `.mhmat` y la textura en `hair/ht_<estilo>` (las
   barbas, en `clothes/`). Los vértices que mueve el parpadeo quedan fuera de
   los anclajes (grupo `hair_anchor`), para que un mechón sobre la cara no
   siga los párpados; MakeClothes aún ancla alguno en ellos, así que además
   `HumanShape.proxy_blink` no da parpadeo al pelo ni a las barbas.

## Revisar la densidad

`hair_tool_coverage.py` mide qué parte del cuero cabelludo se ve a través de
cada estilo como lo dibuja el juego (solo tapa lo que pasa de media opacidad),
desde arriba y desde atrás, con renders en Cycles sin ventana (unos segundos
para todos):

```sh
blender -b --factory-startup --python tools/character/blender/hair_tool_coverage.py -- \
    build/character/hair_tool/lib/mh_base.blend build/character/hair_tool/lib \
    textures/character/human/proxies build/character/hair_tool/coverage <estilo>...
```

Con `--look` (antes de los nombres) pinta la piel como el juego bajo cada
estilo, con su máscara de raíces, y la renderiza de frente, de tres cuartos y
desde arriba (`<estilo>_look_<vista>.png`), para revisar la línea del pelo.

## Raíces bajo el pelo

Las tarjetas dejan huecos, así que la piel pinta debajo raíces del color del
pelo, con una máscara propia de cada estilo que sigue su línea del pelo:

1. El exportador suma, en cada vértice de la cabeza, el pelo que tiene a
   menos de 2 cm (`hair_cover`; del todo a menos de 4 mm).
2. `make_skin_masks.py` lo rasteriza en las UV de la piel, lo difumina
   (`COVER_BLUR`: lo que tarda en fundirse con la piel pasada la línea del
   pelo) y no lo deja salir del cuero cabelludo más un margen
   (`COVER_MARGIN`), para no manchar la frente:
   `build/character/mpfb/hair_cover/<proxy>.png`.
3. El horneado lo guarda como textura `cover` del peinado y
   `human_skin.gdshader` la pinta (`use_hair_cover`), gris si el pelo lo es.

Así la coronilla queda del color del pelo y el borde se difumina donde acaba
cada peinado: la frente despejada de una coleta, el lado rapado de De lado,
la coronilla de la tonsura. La máscara genérica del cuero cabelludo
(`scalp_hair`) queda para el rapado pintado y los peinados sin máscara.

## Añadir o cambiar un estilo

Una entrada en el JSON (los presets se ven en
`HairLibrary_52/*.png`), el paso anterior con `--only <estilo> --render` para
revisarlo, el proceso de `docs/character_creation.md` y su línea en el
catálogo con el nombre en `localization/translations.csv`. Lo que no sirve
de la biblioteca: `Dreadlocks`, `LongHairWithGuides` y `QuiffHair_Strands` no
generan tarjetas; `BraidFromScalp` es solo la trenza; `CurlsDense` y
`Gramma_Curls` son tan densos que con el presupuesto quedan calvas.

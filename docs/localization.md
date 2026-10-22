# Idiomas

Todos los textos que ve el jugador están en un solo fichero, `localization/translations.csv`: una fila
por texto y una columna por idioma. El código y los datos (`.tres`, `.tscn`) solo llevan la **clave**
del texto. De momento hay inglés (`en`) y castellano (`es`). Si a un idioma le falta una clave, sale
en inglés (el idioma de reserva del proyecto).

```
keys,en,es,_notes
,,,## Inventory
INV_TITLE,INVENTORY,INVENTARIO,
SURV_EAT,You eat %s,Comes %s,
```

- `keys`: la clave. Las filas sin clave no cuentan: separan las secciones (`## Inventory`).
- Una columna por idioma, con su código (`en`, `es`, `fr`, `pt_BR`...).
- `_notes`: notas para quien traduce (Godot ignora las columnas que empiezan por `_`).
- `\n` es un salto de línea. `%s`, `%d`, `%.1f`... son los valores que pone el código: cada traducción
  lleva los mismos y en el mismo orden. Si un idioma necesita otro orden, la clave usa nombres
  (`Cercenado: {part} {side}.`) y el código la rellena con `format()`.

Godot importa el CSV y deja una traducción por columna (`localization/translations.<idioma>.translation`,
fuera de git). Hay que abrir el editor, o ejecutar `godot --headless --import`, después de cambiar el
CSV.

## Cómo se lee un texto

1. **Texto fijo en un control**: la clave tal cual, `label.text = "INV_TITLE"`. Los `Label`, `Button`,
   las ayudas emergentes, los `placeholder_text` y las opciones de un `OptionButton` se traducen
   solos y cambian en cuanto se cambia el idioma. Igual en las escenas: el botón del menú principal
   lleva `text = "MENU_NEW_GAME"`.
2. **Texto con valores**: `tr("SURV_EAT") % nombre`. En una función `static` no hay `tr()`:
   `TranslationServer.translate(&"CLAVE")`.
3. **Datos**: el `.tres` guarda la clave (`display_name = "ITEM_COAL"`,
   `description = "ITEM_COAL_DESC"`) y el código la lee traducida con `ItemData.get_display_name()` y
   `get_description()`. Lo mismo los estados (`StatusEffectData.display_name`), los remedios
   (`RemedyTrait.use_text`), las opciones del aspecto (`AppearanceCatalog`), los materiales y bloques
   de construcción y los nombres de los huecos, categorías y grupos.

Lo que escribe el jugador (el nombre del personaje, el de un blueprint) no se traduce: esos controles
llevan `auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED`.

## Claves

| Prefijo | Qué |
|---|---|
| `UI_` | Comunes: aceptar, cancelar, sí, desmontar, la «y» de las listas |
| `MENU_`, `OPT_`, `ACTION_`, `KEY_` | Menú principal, opciones, acciones reasignables, botones del ratón |
| `CREATE_`, `APP_` | Creación de personaje y su catálogo de aspecto (`APP_<opción>`, `APP_CAT_<categoría>`, `APP_HAIR_<peinado>`...) |
| `INV_`, `CRAFT_`, `CARD_`, `SLOT_`, `CHAR_` | Inventario, fabricar, ficha del objeto, huecos de equipo, muñeco |
| `ITEM_<ID>`, `ITEM_<ID>_DESC` | Nombre y descripción de cada objeto, por su id (`ITEM_BLOCK_CUBE_STONE` para los bloques) |
| `CAT_`, `GROUP_`, `DMG_`, `REGION_`, `TRAIT_`, `CURE_`, `STAT_`, `NEED_`, `TEMP_` | Clasificación de objetos, tipos de golpe, partes que cubre la ropa, rasgos, vida y necesidades |
| `SURV_`, `SLEEP_`, `REMEDY_`, `STATUS_`, `HUD_` | Avisos de supervivencia, descanso, remedios, estados, HUD de combate |
| `MAP_`, `WATER_`, `COMPASS_` | Mapa del mundo |
| `BUILD_`, `BLOCK_`, `SHIP_`, `GRID_` | Construcción |
| `CON_`, `CON_HELP_<COMANDO>`, `SEASON_` | Consola: respuestas y ayuda de cada comando |
| `LANGUAGE_NAME`, `NUM_DECIMAL_SEPARATOR` | El nombre del idioma en sí mismo y su separador decimal |

## Añadir un texto

1. Una fila en su sección del CSV, con todas las columnas.
2. En el código, la clave como en [Cómo se lee un texto](#cómo-se-lee-un-texto).

## Añadir un idioma

1. Una columna más en el CSV con su código (`fr`) y todas las filas traducidas, empezando por
   `LANGUAGE_NAME` (`Français`): es lo que sale en Opciones > Juego > Idioma.
2. Reimportar (abrir el editor). `SettingsManager` carga al arrancar cualquier traducción de
   `localization/`, así que el idioma aparece solo en las opciones.

## El idioma del juego

`Opciones > Juego > Idioma` (`game/language` en `SettingsManager`): «El del sistema» (`""`) o uno de los
idiomas del CSV. Se aplica al momento con `TranslationServer.set_locale()`. Lo fijo se traduce de
nuevo solo; lo que lleva valores se rehace la próxima vez que se pinta (las páginas de opciones se
rehacen al cambiarlo).

## La consola

Los comandos y sus argumentos son en inglés en todos los idiomas (`season autumn`, `cut arm left`,
`needs hunger 0.5`, `spawn wolf 3 large`), igual que su sintaxis en la ayuda. Lo que se traduce es la
ayuda de cada comando (`CON_HELP_<COMANDO>`) y lo que contesta (`CON_*`).

`toon on threshold 0.12 softness 0.04 gradient 0.25` ajusta la luz por bandas. Su ayuda y su
respuesta se traducen; los nombres de los parámetros y el autocompletado se mantienen en inglés.

## Lo que no pasa por el CSV

- Los logs (`print`, `push_warning`, `push_error`) y la capa de perfilado (F3, `perf`), que son para
  quien desarrolla.
- Lo que solo se ve en el editor: `@export_group`, `@export_enum`, nombres de nodos.
- El nombre del juego (LANDNÁM) y las siglas técnicas de las opciones (FXAA, MSAA, AMD FSR).

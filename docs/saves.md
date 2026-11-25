# Partidas guardadas

`GameManager` (`scripts/autoload/game_manager.gd`) guarda y carga; `SaveSlots`
(`scripts/autoload/save_slots.gd`) lleva las carpetas, los metadatos y la migración.

## En disco

Una carpeta por partida en `user://saves/<nombre>/`:

- `meta.json`: formato, fecha, estado del juego, personaje, nota y `protected`.
- `player.json`, `grid.json`, `planet.json`, `npc.json`, `remains.json`, `world_items.json`:
  las entidades del grupo `saveable` por `save_category`, como siempre.
- `terrain/<planeta>.sqlite`: el terreno modificado de cada planeta al guardar.

`user://saves/last_slot.txt` guarda la última partida usada, que es la que carga
"Continuar".

## El terreno vivo

El módulo de vóxeles escribe en su SQLite cada vez que suelta bloques, no solo al
guardar. Por eso el terreno con el que se juega es una copia de trabajo en
`user://saves/live/<pid>/<planeta>_<n>.sqlite`, con una carpeta por proceso para
que un test headless no toque la de la partida abierta.

- **Al arrancar:** se borran las carpetas de procesos muertos y se copia el terreno de
  la partida de "Continuar". El planeta lo abre en su `_ready`, así que Continuar no
  recarga nada.
- **Al guardar:** después de `save_modified_blocks()`, `PlanetLoader.snapshot_voxel_data`
  hace `flush()` del stream y copia la base a la carpeta de la partida.
- **Al cargar o empezar una partida nueva:** `GameManager._swap_terrain` copia el
  terreno guardado a una base nueva (`<n>` + 1). Después `PlanetLoader.swap_voxel_stream`
  quita el stream y pone uno nuevo, y el terreno se vacía y se vuelve a streamear. El
  paso por `null` evita que la vegetación guarde en la base nueva lo que tenía a medias
  de la anterior. Lo cavado desde el último guardado se pierde, igual que el resto de
  la partida.

## Protegidas

Una partida protegida solo se carga: `save_game` y `delete_save` devuelven `false`.
Sirve para las partidas de prueba. En el menú, "Guardar" sobre una protegida abre la
pantalla de partidas para elegir otro nombre.

## Formas de usarlo

- **Menú**: "Continuar" carga la última partida. "Partidas" (`SavesScreen`) lista las
  partidas para cargar, sobrescribir, proteger y borrar; en partida permite además
  guardar con un nombre y una nota. En partida, "Guardar «nombre»" guarda encima de la
  partida en juego, y "Cargar partida" vuelve a su último guardado.
- **Consola**:
  - `save [nombre] [nota...]`: sin nombre, guarda en la partida en juego.
  - `load <nombre>`
  - `saves`: lista las partidas.
  - `delsave <nombre>`
  - `protect <nombre> [on|off]`
- **Arranque**: `godot --path . -- --load=<nombre>` entra directamente en esa partida.

## Migración

El formato 1 eran archivos `<slot>_<categoría>.json` sueltos en `saves/`, con un
`saves/*.sqlite` compartido. Al primer arranque se mueve a `saves/main_save/` con ese
terreno. Las copias a mano `user://saves_*/` se importan como partidas protegidas con
el nombre de la carpeta sin `saves_`, y las carpetas originales no se tocan.

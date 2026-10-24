# Almacenamientos

`Inventory` (`scripts/items/inventory.gd`) es el componente de contenido del jugador,
cadáveres, hogueras y contenedores. `Storage` añade interacción y persistencia en el
mundo; `InventoryPanel` muestra cualquier instancia sin decidir sus reglas.

## Capacidad y reglas

`Inventory.new(8)` crea ocho huecos. También se puede configurar `max_slots` en el
inspector o llamar a `resize_slots(8)`: devuelve `false` si la reducción recortaría
un hueco ocupado. `max_slots` e `items.size()` se mantienen sincronizados.

Sin reglas se aceptan todos los objetos, respetando su apilado. Un recurso
`InventoryRules` puede especializar `accepts(slot, data)` y `capacity(slot, data)`.
Se consulta al insertar, mover y transferir, también desde código. La hoguera usa
`CampfireInventoryRules`: combustible en el hueco 0 y una pieza de comida en cada
uno de los siguientes.

## Mochilas equipables

`InventoryExpansionTrait.extra_slots` amplía el inventario mientras el objeto está
equipado. `EquipmentCapacity` calcula base + bonificaciones del equipo completo;
`CharacterWindow` valida el cambio antes de modificar cualquier hueco o emitir señales.

Al reducir capacidad, `Inventory.can_repack` prepara la compactación sin modificar
cantidades ni identidades. Reserva además espacio para la mochila retirada. Una
operación viable se aplica con `repack_slots`; una rechazada deja intactos el
inventario y el equipo. Cambiar por otra mayor se valida contra la capacidad final.
Al sustituir por igual capacidad también se compacta para alojar la saliente.

La mochila de pieles ocupa `ArmorSlot.BACK` (añadido al final del enum), aporta ocho
huecos y se fabrica en el banco de trabajo. Su malla rígida se cuelga de Spine2 con
`BackEquipment`, que compensa los ejes y la escala del esqueleto importado y ajusta
la separación a la profundidad del torso, tanto en el jugador como en el muñeco.

La partida guarda `inventory_base_slots` junto con inventario y equipo. Al restaurar,
se deriva de nuevo la capacidad final; las partidas antiguas usan la base configurada
en la escena. Una mochila sin equipar es un objeto normal, sin contenido propio.

`tests/items/test_backpacks.tscn` comprueba compactación, equipar y quitar, cambios
de tamaño, cursor desde un cofre, ajuste visual, cargas repetidas y partidas antiguas.
Con render admite `-- --background --capture=/tmp/backpack.png`.

## Operaciones

- `add_item(data, cantidad)` devuelve cuántas unidades no caben.
- `transfer_to(destino, hueco_origen, cantidad = -1, hueco_destino = -1)` devuelve
  cuántas unidades se han movido. Sin hueco de destino apila y busca sitio libre;
  no intercambia objetos. Restaura el sobrante antes de notificar a ambos inventarios.
- `take_at`, `put_at` e `insert` trabajan con montones retirados del inventario:
  devuelven el objeto que se sostiene o el sobrante, sin emitir señales. Permiten
  completar una transacción de cursor y notificar después de colocar todos sus restos.
- `move_item` y `split_item` mueven dentro del mismo inventario.

La interfaz recuerda `(inventario, hueco)` para el cursor. Al cancelar intenta
devolver al hueco original, después busca sitio en ese inventario y en el jugador;
si no cabe, lo suelta al mundo. Si desaparece el contenedor, pasa directamente al
jugador y conserva el sobrante en el mundo.

## Añadir otro almacenamiento

1. Crear un `ItemData` en `data/items/` con nombre, descripción e icono.
2. Añadir `StorageTrait`: número de `slots` y `rules` opcionales. Solo guarda
   configuración compartida, nunca los objetos almacenados.
3. Crear una escena con `Storage` como script raíz e `item_id` del objeto, su visual
   y colisión. Cada instancia crea su propio `Inventory`.
4. Añadir `GroundPlaceableTrait` con la escena y su visual para la colocación.
5. Añadir receta y traducciones. No hace falta otra clase de lógica ni interfaz.

El ejemplo completo es `wooden_chest`: 24 huecos, 12 maderas y 2 pieles, a mano.
Su malla se comparte entre el mundo, la vista previa y el icono, que se regenera con:

```sh
godot --path . --audio-driver Dummy --script res://tools/ui/bake_item_icons.gd -- --background --only=wooden_chest
```

## Persistencia y comprobación

El formato común guarda `max_slots` y una lista de `item_id`, `quantity` y
`slot_index`. También se sigue leyendo la lista usada por partidas antiguas del
jugador. `Storage` añade su transformación y usa la identidad y escena del sistema
de guardado existente. Se retiran al cargar los contenedores posteriores al guardado.

`GameManager` llama a `prepare_save` y `prepare_restore` en todas las entidades antes
de capturar o restaurar ninguna. El jugador resuelve el cursor en esos pasos, para
que un montón no quede fuera de la partida ni se reinserte sobre contenido restaurado.

`tests/items/test_storage.tscn` cubre capacidad, restricciones, transferencias,
cursor, cierres y guardado/carga real; admite `-- --background --capture=/tmp/storage.png`
para una captura con render. Las pruebas de inventario, equipo y objetos soltados
se mantienen en sus escenas existentes.

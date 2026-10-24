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

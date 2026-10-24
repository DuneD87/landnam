# GodotVoxelTest

Prototipo en Godot 4.6: planetas voxel, construcción, fauna, combate y supervivencia.
Necesita una build del motor con las clases `Voxel*` y las extensiones del proyecto disponibles.
Abre `project.godot` y ejecuta la escena principal configurada en él.

## Mapa del código

| Sistema | Entrada y responsabilidades |
| --- | --- |
| Planetas | `PlanetLoader` monta terreno, agua, atmósfera, clima y fauna desde `data/planet/*.json`. |
| Configuración del terreno | `PlanetParser` carga una `PlanetDefinition`: biomas, materiales, vegetación, minerales, ríos y clima. El planeta y sus consumidores comparten este recurso; cada planeta tiene el suyo. |
| Vegetación | `Planet` registra los generadores, las bandas de LOD y las colisiones. `VegetationBaker` hornea las tarjetas de hierba y los impostores de árboles. |
| Jugador | `PlayerController` coordina movimiento, interacción, equipo y construcción; `scripts/player/` contiene sus componentes. |
| Combate | `PlayerCombat` lleva las acciones del jugador; `CombatTargeting` selecciona el blanco y actualiza el punto de la cámara. Las criaturas usan `scripts/npc/ai/`. |
| Inventario | `Inventory` (`scripts/items/`) lleva capacidad, reglas y transferencias. `Storage` incorpora ese componente en los contenedores del mundo, configurados con `StorageTrait`. `InventoryPanel` presenta cualquier inventario y `InventoryUI` coordina el cursor. Ver `docs/storage.md`. |
| Audio | `AudioManager` mantiene el catálogo y las voces. Agua y clima calculan ganancias; `AmbientBedMixer` crea sus pistas y las funde. |
| Objetos | `ItemData` y sus rasgos describen los objetos; `data/items/` y `data/recipes/` contienen sus recursos. `ItemCatalog.get_item(id)` los busca por id. |
| Guardado y ajustes | Los autoloads `GameManager` y `Settings` mantienen partidas y preferencias. |
| Tiempo y descanso | `WorldTime` comparte la aceleración del reloj; `RestController` permite dormir en un lecho y recuperar descanso durante la noche. |
| Utilidades | En `scripts/core/`: `PhysicsLayers` y `RenderLayers` (todas las capas del proyecto), `Raycast` (rayos y sondeo de suelo), `ProcMesh` (mallas por código) y `AnimGraph` (montaje del AnimationTree). `HumanRig` nombra los huesos del esqueleto humano y `BurstParticles` crea los emisores de una ráfaga. |

La configuración JSON conserva su formato. Los datos compartidos de terreno se consultan como
`planet.definition`; radio, nivel del agua, viento y referencias a nodos siguen en el planeta.
Los shaders están en `shaders/`, las herramientas de horneado en `tools/` y la documentación
por sistema en `docs/`.

## Comprobaciones

Sustituye `godot` por la ruta a tu build. Las escenas de prueba cargan los autoloads normales:

```sh
godot --headless --path . res://tests/audio/test_ambient_mixer.tscn
godot --headless --path . res://tests/items/test_inventory_transfers.tscn
godot --headless --path . res://tests/items/test_storage.tscn
godot --headless --path . res://tests/player/test_item_save_load.tscn
godot --headless --path . res://tests/planet/test_planet_definition.tscn
godot --headless --path . res://tests/ui/test_drop_items.tscn
godot --headless --path . res://tests/ui/test_build_hammer.tscn
godot --headless --path . res://tests/ui/test_blueprints.tscn
godot --headless --path . res://tests/combat/test_combat_core.tscn
godot --headless --path . res://tests/combat/test_targeting.tscn
godot --headless --path . res://tests/survival/test_cold_exposure.tscn
godot --headless --path . res://tests/survival/test_rest.tscn
godot --headless --path . res://tests/console/test_toon_command.tscn
```

El horneado necesita render real; la ventana puede abrirse fuera de pantalla:

```sh
godot --path . --audio-driver Dummy res://tests/vegetation/test_vegetation_baker.tscn -- --background
godot --path . --audio-driver Dummy res://tests/lighting/test_toon_shading.tscn -- --background
```

Las vistas previas de `tests/ui/`, `tests/vegetation/` y `tests/combat/` permiten revisar el
resultado visual sin recorrer una partida. Sus cabeceras describen los argumentos de captura.

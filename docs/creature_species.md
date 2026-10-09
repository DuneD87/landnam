# Criaturas del pack WildMesh

Los animales grandes del pack WildMesh (`~/Downloads/WildMesh3D`) son criaturas (`NPCController`),
como el oso, el lobo o el león: tienen IA, vida, percepción, cadáver y, los que pelean, un
`CreatureCombatProfile`. Cada especie es una escena heredada de
`scenes/animals/base/creature_base.tscn`, que trae todo lo común. La especie pone su modelo, sus
clips, sus materiales y sus números. Los tamaños (joven, adulto, grande) son las variantes
`mammal_*` de [ambient_fauna.md](ambient_fauna.md#tamaños).

## Especies

| Especie | `spawn` | Escena | Dónde sale (población) | Conducta | Vida |
| --- | --- | --- | --- | --- | ---: |
| Cierva | `cierva` | `Hind` | templado (6) | huye | 55 |
| Jabalí | `jabali` | `Boar` | templado (5) | huye; herido, carga | 80 |
| Alce | `alce` | `Moose` | templado frío y frío (2) | huye; herido, carga | 180 |
| Lince | `lince` | `Lynx` | templado y frío (1) | huye | 45 |
| Cabra montés | `cabra_montes` | `MountainGoat` | templado frío y frío (4) | huye | 60 |
| Mamut | `mamut` | `Mammoth` | frío (3) | carga si te acercas a menos de 15 m | 900 |
| Leona | `leona` | `Lioness` | sabana (3) | ataca al verte: zarpazos y salto | 120 |
| Ñu | `nu` | `Wildebeest` | sabana (8) | huye | 80 |
| Hiena | `hiena` | `Hyena` | sabana (4), en grupos de 2 a 4 | ataca al verte y avisa al grupo: mordisco | 70 |
| Caimán | `caiman` | `Alligator` | sabana, a menos de 25 m del agua (2) | ataca al verte: mordisco | 150 |
| Rinoceronte | `rinoceronte` | `Rhinoceros` | sabana (2) | carga a menos de 18 m | 400 |
| Elefante | `elefante` | `Elephant` | sabana (4) | carga a menos de 20 m | 800 |
| Puma | `puma` | `Puma` | solo consola | ataca al verte: zarpazos y salto | 90 |
| Muflón | `muflon` | `Bighorn` | solo consola | huye | 60 |
| Berrendo | `berrendo` | `Pronghorn` | solo consola | huye | 45 |
| Caballo | `caballo` | `Horse` | solo consola | huye | 120 |
| Burro | `burro` | `Donkey` | solo consola | huye | 90 |
| Vaca, ternero, cabra | `vaca`, `ternero`, `cabra` | `Cow`, `Calf`, `Goat` | solo consola | huyen | 120, 50, 40 |
| Labrador, sabueso | `labrador`, `sabueso` | `Labrador`, `Bloodhound` | solo consola | huyen | 50 |

El clima exacto de cada una está en su perfil (`climate_min`/`climate_max` de
`data/fauna/<especie>.tres`). Los de solo consola tienen perfil pero no están en
`planet_earth.json`. Los domésticos (caballo, burro, vaca, ternero, cabra, perros) están pensados
para los asentamientos. Puma, muflón y berrendo son americanos y repetían papel con el lince, la
cabra montés y el ñu.

Las voces se reutilizan: la leona, el puma y la hiena usan las del león y el lobo con otro tono
(`voice_pitch`). El jabalí, el alce, el rinoceronte, el elefante y el mamut van casi mudos hasta
que tengan grabaciones propias.

## Población

Cada perfil tiene su propia población, así que cada especie que se añade a una zona suma
criaturas. Con todas las especies nuevas, en la partida guardada había 50 en juego en vez de 28. Y
una criatura grande cuesta aunque esté lejos: su cuerpo físico, sus zonas de golpe pegadas a los
huesos y su esqueleto. Por eso las poblaciones de cada zona se bajaron a la mitad o menos:

| Zona | Especies (población) | Total |
| --- | --- | ---: |
| Templado (biomas 1 y 3) | ciervo 8, cierva 6, oso 4, lobos 5, jabalí 5, lince 1; en lo frío, alce 2 y cabra montés 4 | ~30–35 |
| Frío (por clima) | caribú 8, oso polar 2, mamut 3, y los lobos, alces, linces y cabras que comparte | ~25 |
| Sabana (bioma 2) | ñu 8, búfalo 5, elefante 4, hiena 4, leona 3, león 2, rinoceronte 2, caimán 2 | 30 |

Los animales pequeños también se bajaron a la mitad (ver
[small_ground_fauna.md](small_ground_fauna.md)). Al añadir una especie a una zona, la población
se quita a las otras de esa zona, no se suma.

## Coste de la animación

Lo que más cuesta de una criatura es su esqueleto, en CPU: mezclar los clips del `AnimationTree` y
posar los huesos. Los rigs del pack tienen de 90 a 547 huesos (el caballo), frente a los 38–60 de
los primeros animales. Animados en cada fotograma, cada uno costaba unos 87 µs frente a 27, y los
22 nuevos en juego sumaban 1,9 ms.

`AnimationController.throttled` (lo enciende `NPCController`) avanza el árbol a mano:

- en cámara, cada fotograma;
- fuera de cámara, uno de cada 8 (`AnimationLod.HIDDEN_STRIDE`), con el tiempo acumulado;
- oculto (en el pool), nada;
- mientras ataca o suena el canal de acciones (`full_rate`), cada fotograma, porque los golpes se
  miden con los huesos.

Si está en cámara se mira en cada fotograma, con el radio del cuerpo (`lod_radius`, de la
cápsula): al girar, el que entra en vista ya anima entero. Animar a saltos según la distancia,
como la fauna pequeña (`AnimationLod.stride_for`), se probó en las criaturas y se notaba. Su
coste sale como `npc:anim` en DebugStats.

Sin ventana no se ve: el coste del árbol se pierde en el ruido de un juego sin dibujo. Hay que
medirlo con el juego en ventana, apagando `AnimationTree.active` por especie y comparando el
tiempo de fotograma.

## De un FBX del pack a una especie

Los FBX del pack traen todas sus animaciones y pesan decenas o cientos de MB. No entran en el
repositorio: se copian a `models/_pack/<id>/<id>.fbx` (en `.gitignore`) para que Godot los
importe, y de ahí se saca solo lo que se usa.

1. **Medir.** `tools/fauna/measure_gait.gd` da la velocidad de suelo de cada clip de marcha,
   sobre los pies en apoyo (`--clips`, `--feet`). Sirve para `sprint_anim_speed` y para que las
   patas no patinen. `tools/fauna/measure_attack.gd` da cuánto adelanta cada hueso que golpea a lo
   largo de un clip: la ventana del golpe (`from`/`to`) y el alcance de cada `CreatureHit`.
2. **Clips de otro animal.** Si el modelo no trae muerte o ataque, `tools/fauna/retarget_clip.gd`
   lo pasa de otro. Con la misma familia de esqueleto basta con los nombres de hueso. Entre
   familias distintas, `--map` pasa el giro en el espacio del modelo: `names`, `root_from_rig` o
   `dst:src,...` a mano. `--track_root=<id>/<ruta del esqueleto>` cuelga las pistas del modelo bajo
   `NPCModel`. Así salieron la muerte del caballo (de la cierva), las del puma y la leona (del lince)
   y el mordisco de la hiena (del lobo).
3. **Modelo y clips.** `tools/fauna/import_pack_model.gd` guarda el modelo como `.scn` (mallas,
   esqueleto y piel, sin materiales ni dependencias del FBX) y los clips pedidos en una
   `AnimationLibrary`. `--clips` admite comodines, `--loop` marca los ciclos y `--alias` da los
   nombres comunes que usa el árbol de criatura (`Idle`, `Run`, `Sprint`, `Death`, `Attack`).
   `--root=<id>` cuelga las pistas del modelo y `--add=Death:res://...` añade los clips del paso 2.
4. **Materiales.** Las texturas van a `models/animals/<id>/`, a 2048 px como mucho, con un
   `StandardMaterial3D` por superficie. Las superficies que no deben verse (la silla del caballo,
   las tarjetas de pelo de la cierva, cuya textura no viene en el pack) llevan
   `data/fauna/hidden_surface.tres`. Se siguen enviando a la GPU, así que más adelante convendría
   quitarlas al importar.
5. **Escena.** Se hereda `creature_base.tscn` y se pone:
   - en la raíz, `npc_type`, `variants`, sonidos y `sprint_anim_speed`;
   - `Movement.speed`, `HealthComponent.max_health` y la percepción;
   - la cápsula y la escala de `NPCModel`;
   - el modelo instanciado bajo `NPCModel` (`[editable path=...]`), con
     `surface_material_override` en cada superficie;
   - la librería en el `AnimationPlayer` de `NPCModel`.

   El árbol (`data/fauna/creature_tree.tres`) es el mismo para todas.
6. **Combate.** Un nodo `CombatState` (`creature_combat_state.gd`) con su perfil
   `data/fauna/combat/<id>_combat.tres` y sus ataques en `data/fauna/combat/attacks/`. Cuándo
   pelea lo dicen los estados:
   - ataca al verte: `detect_state = CombatState`;
   - solo si le hieres: `provoked_state`;
   - defiende su sitio: `threat_state` y `flee_trigger_radius` en `IdleState` y `WanderState`.
7. **Aparición.** El perfil `data/fauna/<especie>.tres` (`GroundFaunaProfile`: biomas, clima,
   población, `group_size`, distancias de detalle y `near_water` para los que viven junto al agua)
   va en `biome_settings.ground_fauna` de `planet_earth.json`. El nombre de consola va en
   `ANIMAL_SCENES` de `scripts/console/console.gd`.

`near_water` (m) acepta un punto si hay un río a esa distancia (`RiverField.distance_at`, con la
red de ríos del planeta) o agua del mapa (lago, mar) en dos corros de 8 puntos, a esa distancia y
a la mitad. Se mira solo en las especies que lo piden, al buscar sitio.

### Familias de esqueleto del pack

Los modelos del pack miran a +Z. Por familia de esqueleto:

| Familia | Huesos | Modelos |
| --- | --- | --- |
| Root | `Root`, `Pelvis`, `Spine1`, `LegFL1`… | conejo, hiena; trae el derrumbe `WalkSlowWounded2Lying` y no trae ataques |
| Rig | `RigPelvis`, `RigLFLeg1`… | cierva; trae muertes (`Death_*`) y ataques |
| Reference / Hips | | lince, puma, caimán, visón |
| Reference con IK | 87 huesos en común con el lince | leona, león, labrador, sabueso |
| Bip001 | | rata, vaca, ternero, gallo, cuervo |
| RL | | cabra, burro |
| Al estilo Unreal | | caballo y el otro burro del pack |
| Propia | `c_*`, a escala ×10 | mamut |

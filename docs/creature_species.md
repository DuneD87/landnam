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
| Cierva | `cierva` | `Hind` | templado (8) | huye | 55 |
| Jabalí | `jabali` | `Boar` | templado (8) | huye; herido, carga | 80 |
| Alce | `alce` | `Moose` | templado frío y frío (4) | huye; herido, carga | 180 |
| Lince | `lince` | `Lynx` | templado y frío (2) | huye | 45 |
| Cabra montés | `cabra_montes` | `MountainGoat` | templado frío y frío (8) | huye | 60 |
| Mamut | `mamut` | `Mammoth` | frío (6) | carga si te acercas a menos de 15 m | 900 |
| Leona | `leona` | `Lioness` | sabana (6) | ataca al verte: zarpazos y salto | 120 |
| Ñu | `nu` | `Wildebeest` | sabana (12) | huye | 80 |
| Hiena | `hiena` | `Hyena` | sabana (8), en grupos de 2 a 4 | ataca al verte y avisa al grupo: mordisco | 70 |
| Caimán | `caiman` | `Alligator` | sabana, a menos de 25 m del agua (2) | ataca al verte: mordisco | 150 |
| Rinoceronte | `rinoceronte` | `Rhinoceros` | sabana (4) | carga a menos de 18 m | 400 |
| Elefante | `elefante` | `Elephant` | sabana (8) | carga a menos de 20 m | 800 |
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

Las que huyen dejan que el jugador se acerque (`lets_player_approach`, en `creature_base`):
percibirlo no las hace huir, solo lo tienen fichado. Huyen cuando entra en su `flee_trigger_radius`
(en `IdleState` y `WanderState`) y ya lo han percibido: lo oyen según el ruido que hace y lo ven
peor agachado (ver el sigilo en [combat.md](combat.md)). A un depredador que perciben
(`hostile_npc_types`: el oso para el ciervo y el caribú) y a quien les hiere reaccionan en el acto.

| Huyen a | Especies |
| --- | --- |
| 5 m | ciervo, caribú, cierva, berrendo, caballo, muflón, cabra montés, ñu, lince |
| 4 m | jabalí, alce, búfalo, burro |
| 3 m | vaca, ternero, cabra, labrador, sabueso |

Mamut, elefante y rinoceronte no huyen: cargan a la distancia de su tabla.

Cada especie suena con grabaciones de su animal o de uno muy parecido (ver
[audio_credits.md](audio_credits.md)): `hurt_sound` y `death_sound` en la escena y, las que pelean,
amenaza, ataque y tambaleo en su perfil de combate. Las voces se comparten por familias, cada especie
con su tono en su `SoundEvent` (`tools/audio/build_combat_events.gd`):

| Voz | Especies |
| --- | --- |
| ciervo (corzos y ciervos) | cierva, berrendo, ciervo, caribú |
| cabra / oveja | cabra y cabra montés / muflón |
| vaca, ternero, caballo, burro | la suya cada uno |
| bisonte | búfalo, alce (más agudo) y ñu (aún más): no hay alces ni ñus libres |
| cerdo | jabalí |
| elefante | elefante y mamut (más grave) |
| rinoceronte, caimán | la suya cada uno |
| felino (lince, serval, gatos) | lince y puma (más grave: sisea y gruñe, no ruge) |
| perro (las del lobo) | labrador, sabueso |
| león / lobo | leona / hiena, con otro tono (`voice_pitch`) |

## Población

Cada perfil mantiene su propio cupo alrededor del jugador. La suma de las especies de una zona
determina su densidad: los cupos terrestres se ajustan juntos, incluyendo los animales pequeños,
con menos depredadores solitarios y manadas pequeñas. Las optimizaciones de percepción y
esqueletos reducen su coste, pero los cupos responden también a la frecuencia de los encuentros.

| Zona | Criaturas grandes (cupo por especie) | Total grandes | Pequeños | Suma |
| --- | --- | ---: | ---: | ---: |
| Templado (biomas 1 y 3) | ciervo 6, cierva 4, oso 2, lobos 5, jabalí 4, lince 1; en lo frío, alce 2 y cabra montés 4 | 22–28 | conejo 5, zorro 1, ratón 6 | 34–40 |
| Frío (por clima) | caribú 6, oso polar 1, mamut 3, lobos 5, alce 2, lince 1, cabra montés 4 | 22 | liebre 4, zorro ártico 1, lémming 6 | 33 |
| Sabana (bioma 2) | ñu 6, búfalo 6, elefante 4, hiena 4, leona 3, león 1, rinoceronte 2, caimán 1 | 27 | — | 27 |

Las sumas son orientativas, con la opción de fauna al máximo y antes de aplicar actividad por
hora y estación. Cada especie tiene su propio radio; altura, clima y terreno pueden reducir su
presencia, y las bandas templada y fría se solapan en la transición. No son un límite global
compartido. El nivel bajo de las opciones aplica el 40 % y el medio el 70 % (`FAUNA_SCALE`), con
redondeo por especie y un mínimo de uno antes de la actividad. Los compañeros de una manada
cuentan dentro del cupo del perfil.

Fuera de cámara, una criatura grande a más de `dormant_distance` (100 m) deja de existir para el
motor: oculta y parada hasta que asoma o el jugador se acerca. Los pequeños se duermen a 30 m, los
pájaros a 20 m y los peces a 15 m (`AmbientAnimal.dormant`). Los cupos se partieron por la mitad el 28 de octubre
de 2026 por rendimiento: cada criatura cuesta CPU aunque no se vea.

Los pequeños se detallan en [small_ground_fauna.md](small_ground_fauna.md). Al añadir una especie
a una zona, hay que redistribuir los cupos de esa zona para mantener su densidad.

## Coste de la animación

Lo que más cuesta de una criatura es su esqueleto, en CPU: mezclar los clips del `AnimationTree` y
posar los huesos. Los rigs del pack traían de 90 a 547 huesos (el caballo), frente a los 38–60 de
los primeros animales. Animados en cada fotograma, cada uno costaba unos 87 µs frente a 27, y los
22 nuevos en juego sumaban 1,9 ms.

Muchos de esos huesos no deforman nada (IK, ayudantes, puntas) y aun así cuestan en cada fotograma:
sus pistas se mezclan, se posan y, con bind en la piel, se suben al servidor de render.
`tools/fauna/prune_skeleton.gd` los quita del modelo y de sus clips (ver el paso 8 más abajo). Ya
podados, los del pack tienen de 33 a 122 huesos y el caballo 238; por ejemplo, el ñu pasó de 119 a
59, la cabra montés de 119 a 57 y el elefante de 146 a 106. Los primeros animales (ciervo, oso,
búfalo, león) no tenían nada que quitar, y el lobo usa su FBX tal cual.

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
8. **Podar.** `tools/fauna/prune_skeleton.gd -- --creature=res://scenes/animals/<Escena>.tscn`
   (`--dry` solo informa) quita del `.scn` y de su librería los huesos sin peso en la malla que no
   son ancestros de uno con peso ni los nombra el juego: `head_bone`, `flinch_bones`, los huesos de
   los golpes (`CreatureHit.bones`), las tablas de `AnimalGore` y los `BoneAttachment3D`. Por eso va
   después de la escena y del combate. La malla no se vuelve a codificar (solo se renumeran los
   índices de hueso de la piel), así que se conservan compresión y LOD. Hay que volver a pasarla si
   se reimporta el modelo con `import_pack_model`.

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

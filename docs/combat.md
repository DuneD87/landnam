# Combate

Combate en tiempo real al estilo souls: los golpes se resuelven por colisión con la
hoja real del arma, se esquiva rodando con fotogramas de invulnerabilidad, se puede
fijar al objetivo y hay armas cuerpo a cuerpo y a distancia. Los osos son hostiles
y sirven de banco de pruebas.

## Controles

| Acción | Tecla |
| --- | --- |
| Golpe ligero (encadena combo) | Clic izquierdo |
| Golpe pesado (mantener = cargar) | Clic derecho |
| Apuntar (arco, tirachinas, lanza) | Clic derecho mantenido |
| Tensar y disparar / cargar y lanzar | Clic izquierdo mantenido, soltar |
| Picar con la lanza sin apuntar | Clic izquierdo |
| Esquivar rodando (quieto: paso atrás) | Alt o botón lateral del ratón |
| Fijar / soltar objetivo | Q o clic de rueda |
| Cambiar de objetivo fijado | Mover el ratón de lado |
| Recoger una lanza clavada | E |

Con un objetivo fijado, flechas, piedras y lanzas van a él con la caída compensada;
sin fijar, van a lo que hay bajo la mira.

Con una herramienta (hacha o pico de piedra) el clic sigue talando y picando; solo
pega como arma cuando hay una criatura delante o un objetivo fijado.

## Armas

Todas empiezan en el inventario. `give <id>` en la consola da más.

| Id | Arma | Daño | Ritmo | Notas |
| --- | --- | --- | --- | --- |
| `iron_sword` | Espada de hierro | 30 | 1,45 | Rápida, alcance 0,93 m |
| `battle_axe` | Hacha de guerra | 38 | 1,25 | Rompe más la guardia |
| `iron_mace` | Maza de hierro | 34 | 1,10 | Contundente, la que más tambalea |
| `spear` | Lanza | 26 (×1,5 lanzada) | 1,40 | Pica a 1,2 m o se arroja; hasta 5 |
| `hunting_bow` | Arco de caza | 36 a tensión completa | — | Gasta `arrow` |
| `slingshot` | Tirachinas | 14 | — | Gasta piedras (`stone_01`) |
| `stone_axe_01`, `stone_pickaxe_01` | Herramientas | 18 / 16 | — | Solo con enemigo delante |

Las estadísticas viven en el `.tres` de cada item (grupo *Combat* de `ItemData`):
`reach` y `blade_start` (qué tramo del arma hiere), `blade_radius`, `attack_speed`
(escala de la animación), `stamina_cost`, `poise_damage`, `heavy_multiplier`,
`ammo_id`, `projectile_speed`, `draw_time`, `throwable`.

Las mallas se generan en `scripts/combat/weapon_meshes.gd` y se hornean con sus
escenas e iconos:

```
godot --path . --script res://tools/combat/bake_weapons.gd
godot --headless --path . --import
```

Todas siguen la misma convención: metros, origen en el agarre, +Y hacia la punta y
+Z hacia el filo. `CombatPose.RIGHT_GRIP` / `LEFT_GRIP` las colocan en las manos.

## Cómo funciona

- **Hurtbox** (`scripts/combat/hurtbox.gd`): áreas en la capa de física 9, solo para
  recibir golpes. Todo `NPCController` crea el suyo a partir de su cápsula, más uno
  de cabeza (×1,5) si la escena define `head_bone`. El jugador lleva uno propio.
- **Golpes de hoja**: en la ventana activa de cada animación, `MeleeSweep` barre el
  segmento de la hoja desde la pose anterior a la actual con cápsulas intermedias,
  así un tajo rápido no atraviesa el cuerpo sin tocarlo. Cada criatura se golpea
  una vez por pasada. Los animales pequeños sin hurtbox se miden contra el segmento.
- **Ataques del jugador** (`PlayerCombat`): usan las animaciones `attack_horizontal`
  y `attack_vertical` con un `TimeScale` insertado en el árbol, de forma que cada arma
  golpea a su ritmo. El combo alterna los dos. El pesado se congela arriba mientras
  se mantiene el botón para cargar. Una pulsación temprana se guarda 0,45 s (buffer).
- **Esquiva**: 18 de aguante. La voltereta dura 0,68 s y recorre 4,4 m; su hurtbox
  se apaga entre 0,04 s y 0,46 s. Quieto hace un paso atrás más corto. Se puede
  cancelar la recuperación de un golpe rodando.
- **Animaciones de Mixamo**: la voltereta viene de Mixamo
  (`models/player/mixamo/combat/`, descargada con un personaje de Character Creator).
  `tools/combat/retarget_mixamo.gd` reorienta esas animaciones al esqueleto del
  jugador (otros nombres de hueso y reposo en A en vez de en T: se transfiere el giro de
  cada hueso respecto a su reposo, no la rotación local) y las guarda como la librería
  `combat` en `models/player/mixamo/combat_anims.tres`. La librería también trae paso
  atrás, reacción al golpe, muerte, arco y lanzamiento, pero esas acciones se ven mejor
  con las versiones procedurales. Qué acción usa cuál se elige en
  `PlayerCombat.USE_MIXAMO`. Para añadir o cambiar una animación: dejar el FBX en esa
  carpeta, añadirla a `CLIPS` (con el tramo a usar) y ejecutar
  `godot --headless --path . --script res://tools/combat/retarget_mixamo.gd`.
- **Canales de acción**: `PlayerCombat` pone dos one-shots encima del árbol de
  animación, uno de cuerpo entero (voltereta, paso atrás, tambaleo, muerte) y otro
  filtrado al tronco y los brazos (arco, lanza: las piernas siguen andando). Se pueden
  reproducir, acelerar o arrastrar: el tensado del arco y la carga de la lanza siguen
  exactamente a lo que se mantiene pulsado, y la lanza sale en el instante en que la
  mano la suelta en la animación. El tronco se inclina hacia el blanco sobre la pose.
- **Apoyo en el suelo**: durante esas animaciones el cuerpo sube lo justo si alguna
  parte quedara bajo el suelo real (laderas). Mientras rueda o muere se apagan el IK de
  pies y el de mirada.
- **Voltereta procedural** (`RollMotion`, con `USE_MIXAMO.roll = false`): ocho posturas clave asimétricas
  interpoladas con splines (preparación, impulso, apoyo de manos, de espaldas,
  incorporarse, aterrizaje en cuclillas, arranque y zancada), con las extremidades algo
  retrasadas respecto al tronco. Gira en diagonal sobre un hombro alrededor del centro
  del cuerpo y en cada paso se apoya sobre el suelo real: ni se hunde ni flota.
- **Poses sin animación**: `CombatPose` (modificador del esqueleto) monta por código lo que
  el rig no trae animado, sobre la animación que suene. Tiene utilidades para orientar
  manos (repartiendo la torsión con el antebrazo, como la pronación, para que no se
  retuerza la muñeca), cerrar dedos en poses absolutas y girar clavículas. `HitReact` da
  el respingo al encajar un golpe (jugador y osos).
- **Arco** (`ArcheryPose`): ciclo completo del arquero. De perfil al blanco (quieto, el
  cuerpo entero gira 50° y el tronco pone el resto; andando, solo el tronco; en cuestas
  gira menos para no dejar un pie en el aire), la T entera se inclina por la cintura para
  tiros altos o bajos. Puño cerrado en diagonal sobre la empuñadura, gancho de tres dedos
  en la cuerda, tensado por la línea de la flecha hasta el anclaje bajo el pómulo con el
  codo detrás y la escápula cerrada. Sostener a tope más de un segundo (o sin aguante)
  hace temblar el pulso. Al soltar se abren los dedos, la mano sigue hacia atrás, la cuerda
  vibra, las palas rebotan (la malla del arco tiene una forma de mezcla "drawn") y el arco
  cabecea. Después, si sigue apuntando, la mano va por encima del hombro a la aljaba de la
  espalda (`QuiverVisual`, muestra las flechas que quedan), saca una flecha, la trae por
  fuera de la cabeza y la encaja (0,72 s). La flecha encajada se conserva al bajar el arco.
- **Lanza** (`ThrowPose`): lista sobre el hombro con la palma arriba y el otro brazo
  señalando el blanco; al cargar, el tronco gira y el brazo va atrás con el peso en la
  pierna de atrás; al lanzar, cadena de látigo (cadera, tronco, hombro, codo, mano) con
  paso adelante, suelta a los 0,13 s y el brazo acaba cruzando el cuerpo.
- **Tambaleo y paso atrás** (`BodyMotion`): claves de tronco, cadera, cabeza y brazos
  sobre la animación de quieto, y pasos de verdad con IK de piernas. Cada pie apoyado se
  queda fijo en el suelo mientras el cuerpo retrocede (conoce el mismo perfil de
  desplazamiento con que `PlayerCombat` mueve el cuerpo) y en el aire hace un arco hasta
  donde aterriza. El primer paso lo da el pie del lado del empujón.
- **Muerte** (`Ragdoll`): muñeco de trapo con cuerpos rígidos sueltos (el esqueleto va en
  centímetros y las físicas no llevan bien los nodos escalados) unidos por articulaciones
  con límites del cuerpo: codos y rodillas en bisagra, cadera, columna y cuello doblan
  mucho más hacia delante que hacia atrás, hombros en cono. Arranca desde la pose del
  momento con el empujón del golpe que lo mata y la gravedad del planeta; al segundo se
  asienta y las partes quietas se congelan (en una ladera no resbala metros). El cuerpo
  del jugador, y con él la cámara, sigue al muñeco.
- **Armas en la mano**: el arma va respecto a la palma (no a un dedo) y los dedos cierran
  el puño sobre el mango.
- **Proyectiles** (`CombatProjectile`): avanzan a mano con la gravedad del planeta y
  un rayo por tick contra terreno y hurtboxes. Flechas y lanzas se clavan. Lo que se
  clava en una criatura va a su inventario; una lanza en el suelo se recoge con E.
- **Aguante**: golpes, esquivas, correr (11/s) y mantener la cuerda tensa. Si se
  agota, hay que recuperar un poco antes de volver a gastar.
- **Guardia (poise)**: un golpe con más desgaste que la guardia del jugador (24) le
  hace tambalearse. Los osos aguantan 85 de desgaste acumulado y, al romperla, se
  quedan 1,5 s vendidos.

## Osos

`CreatureMeleeState` sustituye al antiguo `CombatState` en `Bear.tscn`. El oso ve
al jugador a 32 m (cono de 140°) y lo oye a 14 m, ruge y persigue a 6,2 m/s. Tiene
tres ataques:

| Ataque | Animación | Distancia | Daño |
| --- | --- | --- | --- |
| Zarpazo | `atk stand2` | < 3,3 m | 32 |
| Doble zarpazo | `atk stand` | < 3,0 m | 20 + 28 |
| Embestida | `atk run` | 4,5–10 m | 26 |

Cada ataque avisa: la primera parte de la animación va más lenta y el oso se encara.
Cuando empieza el golpe se compromete y ya no gira, así que apartarse o rodar a
tiempo lo evita. Las zarpas y la cabeza hieren por colisión solo dentro de la ventana
activa. Después de cada ataque se queda un momento quieto (la ventana para castigar)
y a veces rodea al jugador gruñendo. Tiene 240 de vida. Deja de perseguir a 45 m.

## Muerte

Al llegar a cero, el personaje cae, aparece **HAS MUERTO** y, a los 5 s, funde a
negro y reaparece en la posición de la última partida guardada (el botón Guardar
del menú). Si no se ha guardado nunca, reaparece donde empezó a jugar. Vuelve con
la vida y el aguante llenos y conserva el inventario. Las criaturas que iban a por
él se calman y recuperan la vida.

## Consola

- `spawn oso [cantidad] [distancia]`: suelta osos delante (también `ciervo`, `leon`,
  `bufalo`). Sus cadáveres duran dos minutos.
- `morir`: mata al jugador para probar la muerte y la reaparición.
- `god`, `heal`, `give <id> [n]` siguen igual.

## Pruebas

```
godot --headless --path . res://tests/combat/test_combat_core.tscn
godot --path . res://tests/combat/combat_capture.tscn -- --tag=x [--runs=melee,bow,death]
godot --path . --script res://tests/combat/pose_preview.gd -- --tag=x
godot --path . --audio-driver Dummy --script res://tests/combat/anim_preview.gd -- --tag=x --background
godot --path . --audio-driver Dummy --script res://tests/combat/roll_preview.gd -- --tag=x --background
godot --path . --script res://tests/combat/weapon_preview.gd -- --tag=x
godot --path . --audio-driver Dummy --fixed-fps 30 --script res://tests/combat/anim_stage.gd -- --tag=x --scene=bow [--views=front,side,game] [--frames] --background
```

`anim_stage` es el escenario de animación: el cuerpo del jugador sobre suelo plano con
las poses conducidas por una línea de tiempo fija y varias cámaras a la vez (también
primeros planos que siguen a manos o cabeza). Escenas: `bow`, `bow_walk`, `throw`,
`stagger`, `backstep`, `death`, `melee_h`, `melee_v`, `grip`, `fingers`.
`combat_capture` acepta `--showcase` para sacar los fotogramas desde una cámara cercana.

`test_combat_core` comprueba el barrido, las esquivas, el daño, el aguante y los
proyectiles. `roll_preview` compara la voltereta anterior con la actual fotograma a fotograma
sobre suelo plano e imprime cuánto se hunde en cada fase. `combat_capture` juega contra un oso en el planeta real con entradas
simuladas y guarda fotogramas en `build/combat/`. Las otras dos renderizan las poses
y las armas.

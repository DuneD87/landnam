# Combate

Combate en tiempo real al estilo souls: los golpes se resuelven por colisión con la
hoja real del arma, se esquiva rodando con fotogramas de invulnerabilidad, se puede
fijar al objetivo y hay armas cuerpo a cuerpo y a distancia. Los osos son hostiles
y sirven de banco de pruebas.

## Controles

| Acción | Tecla |
| --- | --- |
| Golpe ligero (encadena combo) | Clic izquierdo (un toque) |
| Golpe pesado (sigue cargando mientras se mantiene) | Clic izquierdo mantenido |
| Guardia (escudo con arma de una mano, o arma a dos manos) | Clic derecho mantenido |
| Parada | Alzar la guardia justo antes del golpe |
| Apuntar (arco, tirachinas, lanza sin escudo) | Clic derecho mantenido |
| Tensar y disparar / cargar y lanzar | Clic izquierdo mantenido, soltar |
| Picar con la lanza sin apuntar | Clic izquierdo |
| Esquivar rodando (quieto: paso atrás) | Alt o botón lateral del ratón |
| Fijar / soltar objetivo | Q o clic de rueda |
| Cambiar de objetivo fijado | Mover el ratón de lado |
| Recoger una lanza clavada | E |

Con un objetivo fijado, flechas, piedras y lanzas van a él con la caída compensada;
sin fijar, van a lo que hay bajo la mira.

El clic izquierdo decide al soltar: soltado antes de 0,18 s (`HOLD_TO_HEAVY`) es el golpe
ligero; mantenido hasta ahí, sale el pesado, que se sigue cargando mientras no se suelte.

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
| `branch_01` | Rama | 9 | 1,15 | Garrote largo (1,1 m), contundente; se recoge del suelo |
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

### Ramas y piedras del suelo

Las ramas caídas (`scenes/planet/planet_items/litter/fallen_branch_0..2.tscn`) y las
piedras pequeñas (`small_rock_01`) son objetos del planeta como el resto: van en
`planet_earth.json` con `"pickup": true`, `"pickup_item"` (lo que dan; por defecto
`stone_01`) y `"collision_distance_m": 40` (el módulo lo mide hasta el bloque, no hasta cada objeto). Cerca llevan un cuerpo en la capa
física 13 (`Planet.PICKUP_LAYER`), con la que nadie choca, y `GroundPickup` coge lo más
cercano a 2,4 m con la tecla de acción y lo quita del instancer. Una piedra da munición
según su tamaño (1,5 por unidad de escala, hasta 5); las de escala > 3 no se levantan.
Las ramas salen con los generadores `fallen_branches_generator_*` (bosque verde, taiga
y abedules), que copian el ruido y el clima de los árboles de su bioma: caen en las
mismas manchas de bosque. `suelo` en la consola dice qué hay para recoger cerca.
Mallas y escenas: `bake_weapons.gd -- --only=branch,litter`.

## Guardia y parada

Se para con un escudo (ranura de mano secundaria de la ventana del personaje, con un arma de una
mano, una herramienta o nada en la derecha) o con un arma a dos manos. Con el arco o el tirachinas
el escudo no se lleva en la mano (no se ve) y el clic derecho apunta; con la lanza y escudo, el
clic derecho bloquea y la lanza solo pica.

- **`Guard`** (`scripts/combat/guard.gd`): cuelga del `HealthComponent` de quien se defiende y
  decide antes de descontar cada golpe. Sirve igual para un humano enemigo.
  - **Parada**: un golpe cuerpo a cuerpo que llega de frente en los primeros `parry_window`
    segundos de alzarla no hace nada; el atacante recibe `on_parried` (una criatura corta el
    ataque y se queda vendida `parried_time` de su perfil) y el siguiente golpe del jugador en
    1,2 s es un contraataque (×1,6 de daño, ×2 de desgaste de guardia). Alzarla y bajarla sin
    parar nada cierra las paradas 0,6 s: machacar el botón no sirve.
  - **Bloqueo**: de frente y dentro de `guard_arc`, pasa `1 - guard_reduction` del daño, no
    tambalea y empuja poco; cuesta aguante según la fuerza del golpe (su desgaste de guardia,
    menos lo que absorbe `guard_stability`). En guardia se anda a la mitad y el aguante recupera
    a un tercio.
  - **Rotura**: si no hay aguante (o está agotado), la guardia cede: pasa lo que no se ha podido
    pagar del golpe y tambalea.
  - Por la espalda o de lado no para nada. Las flechas solo las para un escudo
    (`guard_projectiles`) y rebotan en él. Una embestida o un salto de fiera
    (`CreatureHit.parryable = false`) se bloquea pero no se para.
  - Lo parado ni sangra ni corta miembros: suena la guardia (`guard_sound`: `block_wood` o
    `block_metal`), y con metal saltan chispas (`CombatFx.sparks`).
- **Datos** (`ItemData`, grupo *Guard*): `guard_reduction`, `guard_stability`, `guard_arc`,
  `parry_window`, `guard_projectiles`, `guard_sound`.

| Con qué | Para | Estabilidad | Arco | Parada | Flechas |
| --- | --- | --- | --- | --- | --- |
| Rodela de madera (`wooden_shield`) | 90 % | 45 | 65° | 0,20 s | sí |
| Escudo de roble (`heater_shield`) | 100 % | 68 | 60° | 0,15 s | sí |
| Espadón | 65 % | 35 | 50° | 0,13 s | no |
| Hacha grande | 55 % | 30 | 45° | 0,10 s | no |
| Martillo de guerra | 60 % | 35 | 45° | 0,10 s | no |

Las criaturas lo leen (`guarding` en `CombatRead`): el oso embiste más contra la guardia para
romperla. El escudo va en el antebrazo izquierdo (`CombatPose.shield_xform`, sus mallas en
`WeaponMeshes.round_shield`/`heater_shield`). La guardia es de Mixamo, en el canal de tronco y
brazos (`PlayerCombat.GUARD_ANIMS`): con escudo, alzarlo (`shield_block`, a ×1,4: arriba a los
~0,25 s, lo que dura la parada), sostenerlo (`shield_block_idle`, en bucle) y encajar
(`shield_block_hit`); con un arma a dos manos, sostenerla (`greatsword_block_idle`) y el golpe lo
encaja `HitReact`. Las grabaciones están de lado (la cadera girada 50-70°) y en el jugador la
cadera va con las piernas: `CombatPose._apply_guard` gira el tronco sobre ella hasta dejar el
escudo, o las manos en el arma, delante del cuerpo.

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
- **Animaciones de Mixamo**: la voltereta y el arco vienen de Mixamo
  (`models/player/mixamo/combat/`, descargadas con un personaje de Character Creator; las del
  arco, del Pro Longbow Pack en `Pro_Longbow_Pack/`).
  `tools/combat/retarget_mixamo.gd` reorienta esas animaciones al esqueleto del
  jugador (otros nombres de hueso y reposo en A en vez de en T: se transfiere el giro de
  cada hueso respecto a su reposo, no la rotación local) y las guarda como la librería
  `combat` en `models/player/mixamo/combat_anims.tres`. La librería también trae paso
  atrás, reacción al golpe, muerte y lanzamiento, pero esas acciones se ven mejor con las
  versiones procedurales, y del arquero andar apuntando, reposo, sacar y guardar el arco, que
  aún no se usan. Qué acción usa cuál se elige en
  `PlayerCombat.USE_MIXAMO`. Para añadir o cambiar una animación: dejar el FBX en esa
  carpeta, añadirla a `CLIPS` (con el tramo a usar) y ejecutar
  `godot --headless --path . --script res://tools/combat/retarget_mixamo.gd`.
- **Canales de acción**: `PlayerCombat` pone dos canales encima del árbol de
  animación, uno de cuerpo entero (voltereta, paso atrás, tambaleo, muerte; un OneShot) y otro
  filtrado al tronco y los brazos (arco, lanza: las piernas siguen andando). Este último es un
  Blend2 con el peso llevado a mano: un OneShot cuenta su propio tiempo desde que se dispara y
  se apaga al pasar la duración del clip aunque el clip vaya arrastrado (tensar y sostener).
  `_act_switch` cambia de clip dentro del canal sin fundido, para encadenar clips que empiezan
  donde acaba el anterior. Se pueden
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
  retuerza la muñeca, y con un límite de cuánto se dobla), cerrar dedos en poses absolutas y
  girar clavículas. `arm_ik` es el IK de brazo anatómico: el brazo gira sobre su eje hasta que la
  bisagra del codo (medida en las animaciones) queda perpendicular al plano del brazo y el codo
  solo dobla sobre ella. El rig no tiene huesos de torsión: si el codo doblara sobre cualquier
  eje, lo que sobra acabaría retorciendo el antebrazo y la piel (y la armadura) se estrujaría. `HitReact` da
  el respingo al encajar un golpe (jugador y osos).
- **Arco** (Pro Longbow Pack y `BowAnimRig`): el cuerpo lo ponen las animaciones en el canal de
  tronco y brazos, encadenadas sin saltos: `bow_draw` (la mano va por encima del hombro a la
  aljaba, saca la flecha, la encaja y tensa; el tensado arrastra el clip con la tensión real),
  `bow_overdraw` (sostener a tope, con el tiempo que lleva) y `bow_recoil` (soltar; acaba donde
  empieza `bow_draw`, así que si sigue apuntando va a por otra flecha sin cortes). El tronco se
  inclina hacia el blanco. `BowAnimRig` coloca el arco en el puño izquierdo (su orientación en
  el marco de la mano está medida a tope), la cuerda entre el índice y el corazón de la derecha,
  la flecha (en la mano desde que pasa por la aljaba, encajada desde `NOCK_T`) y la flexión de
  las palas por la distancia de tensado; al soltar, la cuerda vibra y las palas rebotan. Con
  `USE_MIXAMO.bow = false` vuelve el arco procedural.
- **Arco procedural** (`ArcheryPose`): ciclo completo del arquero. De perfil al blanco (quieto, el
  cuerpo entero gira 50° y el tronco pone el resto; andando, solo el tronco; en cuestas
  gira menos para no dejar un pie en el aire), la T entera se inclina por la cintura para
  tiros altos o bajos. Puño cerrado en diagonal sobre la empuñadura, gancho de tres dedos
  en la cuerda, tensado por la línea de la flecha hasta el anclaje bajo el pómulo con el
  codo detrás, en línea con la flecha, a la altura del hombro y lejos de la cabeza, y la escápula
  cerrada. La palma de la cuerda mira al cuello algo vuelta hacia abajo: de lado del todo el
  antebrazo tendría que girar más de lo que da de sí. Sostener a tope más de un segundo (o sin aguante)
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
- **Aguante**: golpes, esquivas, correr (2/s, y corriendo no se recupera), esprintar
  (11/s), mantener la cuerda tensa y trepar (ver [climbing.md](climbing.md)). Si se
  agota, hay que recuperar un poco antes de volver a gastar.
- **Guardia (poise)**: un golpe con más desgaste que la guardia del jugador (24) le
  hace tambalearse. Los osos aguantan 110 de desgaste acumulado (más la armadura de su
  ataque) y, al romperla, se quedan 1 s vendidos.

## Heridas y mutilaciones

Daño por partes al estilo Kenshi (`BodyDamage`, en el jugador): cabeza, pecho, vientre, brazos y
piernas llevan su propia vida aparte de la general, que sigue siendo la que mata. Un golpe cae en la
parte cuyo tramo del esqueleto queda más cerca de por donde entra. El HUD dibuja bajo las barras una
silueta de espaldas con cada parte del color de su estado (solo si hay algo herido); un miembro
perdido queda en contorno con el muñón rojo y una gota late mientras sangra.

- **Sangrado**: toda herida sangra un rato y resta vida general (más un tajo que un golpe
  contundente); un muñón sangra a borbotones, ~1 de vida/s al principio, y se va cortando.
- **Cercenar**: un tajo (`SLASH`, zarpas incluidas) de al menos `SEVER_MIN_DAMAGE` en un brazo o
  una pierna lo corta con probabilidad `BodyDamage.sever_chance` (0,5; negativa,
  la natural: solo si deja el miembro bajo cero). Cada miembro se corta una vez: por el brazo o el
  antebrazo, el muslo o la pierna, a la altura por donde entra el golpe e inclinado hacia donde iba.
  Sin la mano del arma, el arma vuelve al inventario.
- **El corte** (`Dismemberment`, `LimbCutter`): todas las mallas con piel del esqueleto (cuerpo y
  armadura) se parten por un plano en el marco del hueso; los triángulos que lo cruzan se parten,
  así que el borde es un anillo limpio. Lo que cuelga del hueso cortado se mide con el miembro
  estirado y las articulaciones donde las ponen las proporciones del cuerpo: la caña de una bota se
  corta a la altura de la pierna y una mano no se queda en el muñón por llevar el codo doblado. El
  muñón se tapa con carne, grasa y hueso (`shaders/combat/stump_flesh.gdshader`). Corta en un hilo
  y rehace el corte solo si la armadura o el cuerpo cambian de malla.
- **Lo que cae** (`SeveredLimb`): una copia del esqueleto en la pose del corte con las mallas
  cortadas, movida por un `Ragdoll` solo de sus segmentos (el codo y la rodilla doblan). Gotea por el
  corte unos segundos y, quieto, deja un charco que se extiende. Dura dos minutos.
- **Sangre de los golpes** (`CombatFx.blood`): gotas en forma de lágrima alineadas con su velocidad
  (`blood_droplet.gdshader`) y una neblina que se funde con lo que toca (`blood_mist.gdshader`).
  Cada tipo salpica a su manera: un tajo, muchas gotas rápidas en abanico; una estocada, un chorro
  estrecho; un golpe contundente, pocas gotas y más neblina. La cantidad sale del daño.
- **Sangre en el suelo** (`BloodPool`): decals bajo el punto, siguiendo la gravedad del planeta. Las
  gotas de cada golpe manchan el suelo por delante, un muñón al gotear (reguero si se anda), lo
  cortado deja su charco y los cadáveres (el jugador y las criaturas) uno a su medida. Brillan
  mojados, se oscurecen al secarse y se van a los tres minutos.
- **Sangre en el cuerpo** (`BloodStains`): cada golpe deja una mancha con regueros hacia abajo,
  pegada al hueso más cercano. Solo pinta las mallas del personaje (llevan la capa de render 20,
  la única del `cull_mask` de las manchas). Se limpian al reaparecer o al reciclar la criatura.
- **Sangre en la vegetación** (`BloodFoliage`): cada mancha o charco en el suelo, cada golpe (a su
  altura) y cada corte apuntan una salpicadura en una lista de 128 (las que caen casi encima se
  juntan) que el shader de la hierba y los arbustos (`shaders/lib/blood_splats.gdshaderinc`) lee
  como textura global, repartidas por cercanía en 16 grupos de 8 con su esfera: una hoja solo
  recorre los grupos en cuya esfera cae, así que el coste no crece con el total. Tiñe a gotas las
  hojas que caen dentro, sobre su posición en reposo: la sangre va pegada a la hoja con el viento.
  Se secan y se van con los charcos.
- **Desangrarse**: con mucha sangre perdida por segundo o poca vida, el mundo pierde color y los
  bordes se oscurecen a cada latido (`blood_loss.gdshader`), y se oye el corazón cada vez más
  deprisa.
- Las texturas de la sangre las hornea `tools/combat/bake_blood_decals.gd`.

*Opciones > Juego > Sangre y mutilaciones*: sin sangre, solo sangre (no se cercena) o completo.

Todo se cura al reaparecer, al cargar partida o con `heal` (los miembros aún no se guardan).

### Miembros perdidos en la partida guardada

La partida del jugador guarda los miembros perdidos (`"severed"`: zona, hueso y el plano
del corte en el marco del hueso, `BodyDamage.save_data`). Al cargar, después de
`on_restored` (que deja el cuerpo entero), `BodyDamage.load_data` los rehace con
`Dismemberment.add_saved`: corta las mallas y tapa el muñón otra vez, sin sangre ni
miembro que caiga. Reaparecer tras morir sigue devolviendo el cuerpo entero.

### Animales mutilados al morir

`AnimalGore` (`scripts/combat/animal_gore.gd`) se monta en cada `NPCController` cuyo
esqueleto tenga tabla (oso, ciervo y búfalo, león). El golpe que lo mata, si es un tajo
o un porrazo de 14 o más (un pinchazo necesita 45) y el gore está entero, corta con
probabilidad `AnimalGore.sever_chance` (0,5) el tramo más cercano al
golpe: dos tramos por pata, el cuello o la cola. Un cañonazo letal (`die(point)`) cuenta
como porrazo. Lo cortado cae de una pieza (`SeveredChunk`: la malla horneada en la pose
del corte, en el hilo del corte, dentro de un RigidBody con caja), gotea, deja charco y
se va a los 2 minutos (10 a la vez). Los cuernos se van con la cabeza. Al volver del
pool el animal está entero.

### Muerte de la fauna

Al morir, la fauna ambiental (`AmbientAnimal.die`) sangra con los efectos del combate
(`CombatFx.blood`: chorro, gotas, salpicaduras en el suelo y en la hierba) en vez de la
nube vieja, que se queda solo para peces y animales marinos (bajo el agua). Conejos,
zorros, ratones y aves dejan un cadáver (`FaunaCorpse`): copia quieta de las mallas del
modelo en la pose en que murió, en un RigidBody que cae y se vuelca; al pararse deja un
charco y se va a los 90 s (16 a la vez). Un pato o una gaviota posados en el agua no dejan
cadáver (se hundiría). Los animales grandes ya dejaban cuerpo; ahora también sangran así.

### Lisiado

`Cripple` (`scripts/combat/cripple.gd`) decide cómo anda el jugador según lo que le falta:
sin una pierna y con una rama (`branch_01`) empuñada, cojea con la rama de muleta en el
lado de esa pierna (hace falta la mano de ese lado); sin rama, sin esa mano o sin las dos
piernas, se arrastra. Lisiado no corre, no salta, no esquiva ni pega. Las animaciones
(`injury/` de Mixamo: Injured Idle/Walk/Walk Backwards y Zombie Crawl) van en un canal
encima de la locomoción; la cojera original es de la pierna izquierda y el retarget saca
su espejo (`*_mirror`). Velocidades medidas en los clips: cojear ~0,9 m/s, arrastrarse
~0,4 m/s. La muleta es un pie más: la punta se queda clavada y da un paso cuando se queda
atrás; el brazo la agarra por IK (`CombatPose._apply_crutch`).

## Criaturas

El combate de las criaturas es común a todas las especies; lo propio de cada una son datos. El
tono es realista y letal: avisan poco, castigan los errores y no se las deja atrás corriendo.

- **`CreatureCombatState`** (`scripts/npc/ai/states/`): el estado de combate. Amenaza al
  empezar contra el jugador; persigue hacia donde va a estar el objetivo (`chase_lead`), a fondo
  si está lejos y le queda fuelle (`sprint_*`); lanza un ataque en cuanto alguno llega; encadena
  otros (`follow_ups`) o se queda vendido después y a veces rodea al objetivo; y se tambalea si
  le rompen la guardia.
- **`CreatureCombatProfile`** (`data/fauna/combat/<especie>_combat.tres`): el temperamento de la
  especie (velocidades, fuelle, distancias, guardia, recuperación, combo máximo, penalización por
  repetir, sonidos, clip de tambaleo) y la lista de sus ataques.
- **`CreatureAttack`** (`data/fauna/combat/attacks/*.tres`): un ataque. Los tiempos están en
  segundos del clip a ritmo 1.
  - Clip, distancias y ángulo a los que se elige, peso, cooldown.
  - `situations`: multiplicadores del peso según lo que hace el objetivo (ver `CombatRead`).
  - Aviso: `tell` (plantado) y `windup_speed` (el clip lento hasta poco antes del primer golpe).
  - Seguimiento: gira hacia el objetivo a `track_windup` °/s hasta comprometerse (`commit`, por
    defecto justo antes del primer golpe) y a `track_active` °/s después, apuntando a donde
    estará (`lead`). Apartarse en el momento justo funciona; hacerlo pronto, no.
  - Avance (`lunge`), que se frena para quedarse a `lunge_min_distance` del objetivo.
  - Armadura (`armor`): guardia extra en un tramo, que los golpes gastan antes que la suya.
  - Combo: `follow_ups` (ids del mismo perfil), su probabilidad y desde cuándo pueden salir.
  - Ventanas de golpe (**`CreatureHit`**): tramo del clip, huesos que hieren, radio, daño,
    desgaste de guardia, empujón y tipo de daño.

  Las especies con el mismo esqueleto comparten ataques (el oso polar usa los del oso).
- **`CreatureAttackRunner`** (`scripts/npc/ai/combat/`): ejecuta un ataque, sea cual sea el estado
  que lo lanza: aviso, seguimiento, avance, barrido de los huesos contra los hurtboxes y armadura.
- **`CombatRead`**: lo que la criatura sabe de su objetivo. El objetivo cuenta lo suyo con
  `get_combat_situation()` (`windup`, `active`, `recovering`, `dodging`, `aiming`, `staggered`;
  el jugador lo saca de `PlayerCombat.get_situation()` y una criatura de su estado de combate) y
  desde fuera se ve `fleeing`, `back_turned` y `weak`. Un objetivo nuevo (un humano) entra con
  solo implementar `get_combat_situation()`.
- **`CreatureActionChannel`**: el canal de animación de acción de cada criatura, encima de la
  locomoción y sobre su propia copia del árbol. Son dos ranuras que se turnan, para que un golpe
  encadenado se funda sobre el anterior. Lo da `NPCController.get_action_channel()`.
- **`TerritorialState`**: defender un sitio sin ir a por nadie mientras no haga falta. Lo enciende
  `IdleState`/`WanderState` (su `threat_state`) cuando el objetivo entra en su radio. Lo vigila
  encarado; a menos de `warn_distance` le amenaza cada poco (clips y sonido) y se le gasta la
  paciencia, más deprisa cuanto más cerca; a menos de `attack_distance`, al acabarse la paciencia
  o si le hieren (`NPCController.provoked_state`), pasa al combate; más allá de `calm_distance`
  se calma. La paciencia gastada se recupera despacio. En combate, `leash_distance` del perfil
  hace que deje de perseguir al que se aleja de su sitio (`NPCController.get_home()`, guardado en
  el marco del planeta para que sobreviva a los rebases del origen flotante).
- **Cuerpo**: `AIController.desired_facing` y `turn_rate` separan hacia dónde mira de hacia dónde
  anda y limitan el giro; `AIController.target_velocity` mide cómo se mueve el objetivo.
  `NPCController.sprint_anim_speed` pasa al clip de esprintar por encima de esa velocidad, y
  `run_clip_speed`/`sprint_clip_speed` (la velocidad de suelo de cada clip, medida en él) aceleran
  o frenan esos clips a la velocidad del cuerpo para que las patas no patinen.
- **Percepción**: si el estado suelta al objetivo (se rinde, se calma) y lo sigue viendo, se lo
  vuelve a dar; los muertos no se perciben.

Una especie nueva necesita su perfil, sus ataques medidos sobre sus clips y un nodo
`CombatState` con `CreatureCombatState` y el perfil en su escena. `test_creature_combat` comprueba
que los ataques de cada escena casen con sus clips y su esqueleto, y que cada uno acierte a un
blanco quieto en los dos extremos de su distancia. `ia [radio]` en la consola dice qué piensa cada
criatura cercana.

Para medir los clips (ninguno de los animales trae movimiento de raíz: el avance lo pone el
`lunge`), lo que sirve es la posición y la velocidad de zarpas y cabeza respecto a la raíz a lo
largo del clip, y la velocidad de suelo de los pies en apoyo en los de correr.

### Osos

El oso ve al jugador a 32 m (cono de 140°) y lo oye a 14 m, ruge y persigue a 8 m/s, la velocidad
de suelo de su clip de correr; a más de 12 m esprinta a 11,5 m/s mientras le dura el fuelle (6 s).
El jugador esprintando va a 9 m/s: no se le deja atrás. Sus ataques (`bear_combat.tres`):

| Ataque | Animación | Distancia | Daño | Prefiere | Encadena |
| --- | --- | --- | --- | --- | --- |
| Zarpazo (`bear_swipe`) | `atk stand2` | < 3,3 m | 48 | al que se recupera, se tambalea o da la espalda | doble (35 %) |
| Doble zarpazo (`bear_double`) | `atk stand` | < 3 m | 28 + 42 | al que se tambalea o esquiva | zarpazo (25 %) |
| Embestida (`bear_charge`) | `atk run` | 4,5–7,5 m | 42 | al que huye o apunta | zarpazo (50 %) |

Avisa poco (0,12–0,15 s plantado y el clip algo lento) y, comprometido, aún sigue al objetivo a
25–60 °/s. Tiene 240 de vida (el polar, 320) y 110 de guardia, más la armadura de cada ataque; al
romperla se queda vendido 1 s. Deja de perseguir a 60 m.

### León

Defiende su territorio: no va a por el jugador por verlo. Lo ve a 60 m (cono de 220°) y lo oye a
20 m. Si se le acerca a menos de 28 m pasa a `TerritorialState`: lo vigila; a menos de 22 m ruge
(`lion_aggressive_roar_01`, `lion_alerted_roar`) cada 3–4,5 s y se impacienta (6 s al borde,
unos 2 s pegado a 10 m); a menos de 10 m, al acabarse la paciencia o si le hieren, ataca. Se calma
si el intruso se aleja a más de 34 m, y en combate deja de perseguir al que se va a más de 45 m
de su sitio. Carga a 12,5 m/s con el clip de esprintar. Sus ataques (`lion_combat.tres`):

| Ataque | Animación | Distancia | Daño | Prefiere | Encadena |
| --- | --- | --- | --- | --- | --- |
| Zarpazo izquierdo (`lion_swipe_l`) | `lion_attack_close_lft` | < 2,6 m | 38 | al que se recupera o se tambalea | el derecho (50 %) |
| Zarpazo derecho (`lion_swipe_r`) | `lion_attack_close_rgt` | < 2,6 m | 38 | ídem | el izquierdo (50 %) |
| Salto (`lion_pounce`) | `lion_attack_fwd_01` | 3–7 m | 52 | al que huye, da la espalda o apunta | un zarpazo (60 %) |

Apenas avisa (0,06–0,08 s) y es ágil (sigue al objetivo a 70 °/s comprometido en los zarpazos).
Tiene 170 de vida y 70 de guardia; al romperla se tambalea 0,8 s con `lion_hit_chest_lft/rgt_01`.

## Sonido

Cada sonido del combate es un `SoundEvent` del catálogo de `AudioManager`,
`data/audio/events/combat_<id>.tres`, con varias variantes que se turnan. `CombatFx.play(id)` lo
busca ahí y, si no existe, suena su versión sintetizada (la de antes; `SYNTH_STANDIN` dice cuál
hace las veces de los que solo existen grabados). `heartbeat`, `lock` y `dodge` siguen siendo
sintéticos.

| Ids | Qué |
| --- | --- |
| `swing_light`, `swing_heavy` | Silbido del arma (hachas, mazas y armas a dos manos: el pesado) |
| `hit_slash`, `hit_pierce`, `hit_blunt` | Golpe en carne según el tipo de daño |
| `hit_world`, `bow_release`, `throw` | Arma contra el suelo, suelta del arco, lanzamiento |
| `block_wood`, `block_metal`, `parry`, `guard_break` | Golpe parado con madera o metal, parada en seco, guardia que cede |
| `player_hurt`, `player_death` | Voz del jugador (un solo actor); con `_female`, la de la jugadora (una sola actriz), que se elige por el sexo del personaje |
| `claw_swipe` | Zarpazo de las fieras |
| `bear_growl`, `bear_roar`, `bear_huff`, `bear_hurt`, `bear_death` | Oso |
| `lion_roar`, `lion_growl`, `lion_hurt`, `lion_death` | León |

Las criaturas los nombran en sus datos: el perfil de combate (`threaten_sound`, `attack_sound`,
`swing_sound`, `stagger_sound`), cada ataque (`sound`, la embestida del oso resopla) y cada golpe,
`TerritorialState.warn_sound` y `NPCController.hurt_sound`/`death_sound`. `test_creature_combat`
comprueba que todos suenen.

Los clips son grabaciones CC0 de Freesound (créditos en [audio_credits.md](audio_credits.md)):

```
build/fauna_tools/bin/python tools/audio/build_combat_sounds.py [--only=bear_roar,...] [--sheets]
godot --headless --editor --quit --path .
godot --headless --path . --script res://tools/audio/build_combat_events.gd
```

El primero descarga las fuentes (en `build/audio/freesound/`), las recorta (entera, desde el
golpe o troceando una grabación larga en vocalizaciones), las pasa a mono, iguala el volumen de
las variantes y escribe `audio/combat/<evento>/`; `--sheets` deja un espectrograma por evento en
`build/audio/` para revisar los cortes. El último crea los `SoundEvent` con la mezcla de cada uno
(volumen, tono, alcance, voces, cooldown: la tabla `MIX`). En la consola, `audio combat_bear_roar`
suena un evento junto al jugador.

## Muerte

Al llegar a cero, el personaje cae, aparece **HAS MUERTO** y, a los 5 s, funde a
negro y reaparece en la posición de la última partida guardada (el botón Guardar
del menú). Si no se ha guardado nunca, reaparece donde empezó a jugar. Vuelve con
la vida y el aguante llenos y conserva el inventario. Las criaturas que iban a por
él se calman y recuperan la vida.

## Consola

- `spawn oso [cantidad] [distancia]`: suelta osos delante (también `ciervo`, `leon`,
  `bufalo`). Sus cadáveres duran dos minutos.
- `ia [radio]`: estado, fase, ataque, combo, guardia y fuelle de cada criatura cercana, y lo que
  lee de su objetivo.
- `morir`: mata al jugador para probar la muerte y la reaparición.
- `cortar [brazo|antebrazo|muslo|pierna] [izq|der]`: cercena un miembro del jugador al momento.
- `mutilar [0-1|auto]`: probabilidad de que un tajo en un brazo o una pierna lo cercene.
- `heal` sin argumento también cierra las heridas y devuelve los miembros.
- `sangre`: cuántos charcos y salpicaduras hay y a qué distancia está el más cercano.
- `god`, `heal`, `give <id> [n]` siguen igual.

## Pruebas

```
godot --headless --path . res://tests/combat/test_combat_core.tscn
godot --headless --path . res://tests/combat/test_creature_combat.tscn
godot --path . res://tests/combat/combat_capture.tscn -- --tag=x [--runs=melee,bow,death,bowterrain]
godot --path . --script res://tests/combat/pose_preview.gd -- --tag=x
godot --path . --audio-driver Dummy --script res://tests/combat/anim_preview.gd -- --tag=x --background
godot --path . --audio-driver Dummy --script res://tests/combat/roll_preview.gd -- --tag=x --background
godot --path . --script res://tests/combat/weapon_preview.gd -- --tag=x
godot --path . --audio-driver Dummy --fixed-fps 30 --script res://tests/combat/anim_stage.gd -- --tag=x --scene=bow [--views=front,side,game] [--frames] [--armor=leather_armor] [--twist] --background
```

`anim_stage` es el escenario de animación: el cuerpo del jugador sobre suelo plano con
las poses conducidas por una línea de tiempo fija y varias cámaras a la vez (también
primeros planos que siguen a manos o cabeza). Escenas: `bow`, `bow_walk`, `throw`,
`bow_anim`, `stagger`, `backstep`, `death`, `melee_h`, `melee_v`, `grip`, `fingers`. `--armor` viste un
conjunto (los fallos de deformación se ven mucho más con armadura) y `--twist` imprime cuánto se
retuerce cada hueso de los brazos en el arco.
`combat_capture` acepta `--showcase` para sacar los fotogramas desde una cámara cercana.

`combat_capture --runs=bowterrain` dispara un minuto andando por terreno irregular y cuenta los
fotogramas con el brazo dentro del tronco y los tirones de la mano. En `anim_stage`, la escena
`bow_anim` es el ciclo del arco con las animaciones.

`test_combat_core` comprueba el barrido, las esquivas, el daño, el aguante y los
proyectiles. `roll_preview` compara la voltereta anterior con la actual fotograma a fotograma
sobre suelo plano e imprime cuánto se hunde en cada fase. `combat_capture` juega contra un oso en el planeta real con entradas
simuladas y guarda fotogramas en `build/combat/`. Las otras dos renderizan las poses
y las armas.

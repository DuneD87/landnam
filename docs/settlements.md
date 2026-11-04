# Poblados

Al final de las sendas del mundo y a sus lados hay poblados: granjas, aldeas y poblados de
construcciones de bloques con su gente ([Aldeanos](villagers.md)). Se eligen y se trazan al crear el
planeta, después de las sendas y sobre el terreno definitivo. Las construcciones se levantan cuando
el jugador se acerca.

| Pieza | Qué hace |
|---|---|
| `SettlementSites` (`scripts/world/settlement_sites.gd`) | Los sitios (las puntas sueltas de las sendas y a sus lados) y el sorteo de cuáles llevan poblado |
| `SettlementLayout` (`scripts/world/settlement_layout.gd`) | El plano de un poblado: la plaza, y dónde va cada construcción, girada cómo, a qué altura, con su zócalo y su rampa |
| `SettlementField` (`scripts/world/settlement_field.gd`) | Lo junta todo en hilos, lo guarda en caché y abre el claro de los árboles |
| `SettlementPrefab`, `SettlementTemplate` | Los datos: cada construcción (un blueprint) y cada clase de poblado |
| `SettlementManager` (`scripts/world/settlement_manager.gd`) | En partida: levanta y quita las construcciones, y sabe cuáles ya son de la partida |
| `tools/build_settlement_prefabs.tscn` | Genera los prefabs provisionales y las plantillas |

`Planet._setup_settlements` lo traza (o lo lee de la caché) al final de `setup_voxel_generator` y lo deja
en `Planet.get_settlements()`. `PlanetLoader._setup_settlements` crea el gestor.

## Dónde

1. **Puntas sueltas** (`SettlementSites.dead_ends`): los extremos de trazo a más de 30 m de cualquier
   otro trazo. Son los finales de los ramales, que ya acaban en un llano, y los de la red que no siguen a
   ninguna parte. La punta de una senda que llega a un cruce queda encima de otra y no cuenta. La
   dirección de llegada sale de los últimos 40 m del trazo.
2. **Junto a la senda** (`SettlementSites.roadside`): uno cada `roadside_spacing` m de trazo,
   apartado `roadside_setback` m del eje, a un lado o al otro según toque. Ninguno a menos de 200 m de
   los extremos de su trazo (cruces y puntas) ni a menos de 60 m de otro trazo. Para el trazado es
   como una punta: la senda llega por detrás y el poblado se abre hacia fuera de ella.
3. **Sorteo** (`SettlementSites.roll`): cada punta lleva poblado con probabilidad `fraction` y cada
   sitio junto a la senda con `roadside_fraction`. La tirada va antes que todo lo demás, así que un
   sitio no cambia de suerte por los de antes, y solo se busca plaza a los que salen.
4. **Plaza** (`SettlementLayout.find_center`): nueve sitios de 6 a 30 m más allá del sitio y hasta
   12 m a los lados. Gana el más llano, con desnivel medido a 12 m en cruz. Se descarta si pasa de
   `max_slope` o si queda a menos de 1,5 m sobre el mar. Un sitio junto a la senda sin plaza lo
   intenta al otro lado.
5. **Separación** (`SettlementSites.space`): por orden, se salta el que cae a menos de `min_spacing`
   de otro ya elegido. Las puntas van primero y mandan.

En la Tierra (todas las puntas, y junto a la senda uno cada 1000 m con la mitad de suerte) hay 291
puntas sueltas y 889 sitios junto a la senda. Salen 725 en el sorteo, 530 tienen plaza y 297 quedan
separados. De ellos, 292 poblados (126 junto a la senda) con 1191 construcciones: 114 granjas, 95
aldeas y 83 poblados, cada uno con su iglesia. El vecino más cercano queda a unos 1,9 km (mediana;
2,7 km el p90). Tarda 4,3 s la primera vez, con la lectura del suelo repartida en hilos. Con solo una
de cada tres puntas eran 60 poblados, a 4,4 km.

## El plano

Cada sitio elige plantilla al azar por su `weight`, con una semilla que sale de `seed` y del número del
sitio. `SettlementLayout.plan` coloca primero la construcción principal de la plantilla, al fondo de la
plaza y frente a la llegada de la senda; si no cabe, prueba abriéndose a los lados y más lejos. Las
demás van en corona alrededor:

- la puerta hacia el centro, con ±12° de giro al azar;
- fuera del sector de ±35° por el que llega la senda;
- a 3 m como poco unas de otras;
- a 6 m como poco del eje de cualquier senda (`TrailField.distance_at`);
- entre `plaza_radius` y `plaza_radius + ring_depth` del centro.

La huella de cada construcción incluye sus sitios de trabajo de fuera (el huerto, la leñera:
[Aldeanos](villagers.md)), que se asientan en el terreno al trazarla.

Se dan 24 intentos por construcción. La principal es lo que hace a la plantilla (un poblado sin su
iglesia no es un poblado): si no cabe, o al final caben menos de dos, el sitio prueba las demás
plantillas por orden, y si no cabe ninguna no hay poblado.

**El apoyo.** El suelo se lee en una rejilla, a 4 m como mucho, sobre las celdas del suelo de la grid
principal. El desnivel puede llegar a `max_step` o a `max_grade` por el lado largo de la huella, lo que
sea más: una choza no pasa de 3 m de zócalo y la iglesia o la casa larga llegan a unos 4 (con 3 para
todas, en 4 de cada 17 poblados no cabía la iglesia). La cara de arriba del suelo queda 0,3 m sobre
el punto más alto, por debajo del escalón del jugador (0,55). El suelo es una capa de celdas y va casi
enterrado. Bajo cada columna se pone piedra hasta 0,5 m por debajo del terreno, interpolado en la
rejilla. Si delante de la puerta el terreno queda más de 0,4 m por debajo del suelo, sale una rampa
de bloques inclinados de piedra, una celda más abajo cada vez, con piedra debajo. Si hacen falta más
de 4 celdas, la construcción no cabe ahí.

Cada construcción lleva su propio arriba (la vertical en su centro). El plano guarda por construcción
el prefab, su tipo (`kind`), la pose de su grid principal en el marco del terreno, el umbral de la
puerta y los bloques de más (zócalo y rampa: celda, bloque y giro).

## Prefabs y plantillas

Un **prefab** (`SettlementPrefab`, `data/settlements/prefabs/<id>.tres`) es un blueprint en el formato
de `GridBlueprint.capture` y su ficha:

| Campo | |
|---|---|
| `id` | Nombre único; las grids lo llevan como `source_blueprint` |
| `kind` | Para qué sirve: `house`, `longhouse`, `storage`, `church` |
| `blueprint_path` | El JSON |
| `door`, `door_cell` | Lado de la puerta (±X o ±Z) y la celda (x, z) por la que se entra, en la grid principal |
| `foundation_material` | Material del zócalo y la rampa (piedra) |

La huella y el suelo salen del propio blueprint (`SettlementPrefab.measure`). La grid principal es la
primera, la de más bloques, y su capa más baja es el suelo.

Los provisionales los genera `tools/build_settlement_prefabs.tscn`. Son casas de celdas de 1 m como la
cabaña de `tests/building/thatch_roof_preview.gd`: suelo, paredes, tejado de paja a dos aguas con la
cumbrera a lo largo de X y frontones de madera por fuera de las paredes de los extremos. La herramienta
tiene piezas para montarlas: la casa con el material de cada celda de pared (zócalo y esquinas de
piedra), huecos de puerta, ventanas (un panel de cristal en la cara de fuera de la pared, o un cuadrado
de cristal en el frontón), la chimenea y la torre de la iglesia.

Cada entrada lleva su **puerta de madera** (`wooden_door`, ver [Puertas y
trampillas](building.md#puertas-y-trampillas)), puesta como con el martillo. La casa se levanta en una
grid de verdad y la hoja se encaja con `WoodenDoor.fit`, apuntando a la jamba desde fuera, así que queda
a ras de la cara de fuera del muro con las bisagras en esa jamba. El blueprint sale de
`GridBlueprint.capture`, como al guardar uno, sin la fecha para que no cambie si no cambia la casa. Por
eso la herramienta es una escena (hacen falta los autoloads) y no un script de `-s`.

Las paredes miden 3 m (5 la iglesia). Con 2, el alero del lado largo bajaba hasta el dintel y tapaba
la puerta.

| Prefab | Suelo | Cómo es | Bloques |
|---|---|---|---|
| `choza` | 6 × 5 | Madera con esquinas de piedra; puerta de 1 × 2 en el frontón, tres ventanas | 140 |
| `casa` | 9 × 7 | Zócalo y esquinas de piedra; puerta de 1 × 2 en el lado largo entre dos ventanas, tres detrás, una en el frontón y otra en el desván; chimenea de piedra | 263 |
| `casa_larga` | 17 × 7 | Piedra; puerta de 1 × 2 en el centro del lado largo con marco de madera, nueve ventanas pequeñas y una en cada frontón | 432 |
| `granero` | 7 × 5 | Suelo de piedra, zócalo y esquinas de piedra; portón de 3 × 2 en el frontón, dos ventanucos y uno en el desván | 154 |
| `iglesia` | 13 × 7 + torre de 3 × 3 | Nave de piedra con paredes de 5 m, ocho ventanales de dos celdas, el altar al fondo bajo una ventana y una vidriera en el frontón; delante, el campanario con la entrada (puerta de 1 × 3), los vanos de las campanas, un chapitel de piedra y la cruz | 516 |

Sin contar el zócalo, que de media son unos 95 bloques más por construcción.

**Uno hecho con el martillo** sustituye a cualquiera: se construye (con sus puertas), se guarda como
blueprint y se copia `user://blueprints/<nombre>.json` encima de `data/settlements/prefabs/<id>.json`.
Después se ajustan `door` y `door_cell` en la ficha. Los blueprints entran en la firma de la caché, así que en la siguiente
carga se vuelven a trazar los poblados. Las casas que el jugador no ha tocado salen ya con el prefab
nuevo.

Una **plantilla** (`SettlementTemplate`, `data/settlements/templates/<id>.tres`) es una clase de
poblado. Las lee todas `SettlementField.load_templates`. Una de otro bioma o de otra gente será una
plantilla nueva, no código nuevo.

| Plantilla | Peso | Principal | Las demás (al azar, con repetición) | Cuántas | Plaza, corona |
|---|---|---|---|---|---|
| `granja` | 0,4 | casa | granero, choza | 1-2 | 8, 10 m |
| `aldea` | 0,4 | casa larga | choza ×2, casa, granero | 3-5 | 10, 14 m |
| `poblado` | 0,2 | iglesia | choza, casa ×2, casa larga, granero | 6-9 | 14, 22 m |

La herramienta no pisa las plantillas que ya existen; con `-- --templates` las rehace.

```sh
godot --headless --path . res://tools/build_settlement_prefabs.tscn [-- --templates]
```

## El claro de los árboles

Los árboles no brotan dentro de los poblados. En su grafo de densidad (los generadores con
`"trail_clearance"`, junto al claro de las sendas) se multiplica la función de
`SettlementField.clearance_graph`. Esa función lee una imagen de 4096 × 2048 R8 con la distancia con
signo al borde del claro de cada poblado: el centro de la plaza y el radio de lo más lejano, más
`clear_margin`. Es la convención del nodo `SdfSphereHeightmap`, con el factor de las sendas.

Una distancia a un círculo se interpola bien salvo cerca del centro, donde no importa. Junto al borde,
con téxeles de 46 × 58 m, el error es de una docena de metros y el claro sale algo irregular;
`clear_margin` (14 m) lo cubre. Los árboles vuelven del todo a 6 m del borde. Cuesta unos 20 ms
compilarlo en cada generador. `"settlement_clearance": false` en un generador lo deja fuera.

La hierba, las matas y las piedras pequeñas siguen saliendo: entre las casas quedan bien y bajo el suelo
no se ven. En la esquina más alta de una huella el suelo queda solo 0,3 m sobre el terreno, y ahí
puede asomar alguna brizna por dentro.

## En partida

`SettlementManager` mira cada 0,5 s a qué distancia está el jugador del centro de cada poblado. A
menos de `load_distance` encola sus construcciones. A más de `unload_distance` quita las que nadie ha
tocado.

Cada construcción se levanta en varios fotogramas. En el primero se crean sus grids y se ponen los
bloques del prefab, el zócalo y la rampa. Después se malla, que es lo caro, un chunk de 16 celdas por
fotograma (`GridBase.end_bulk_edit(false)` y `rebuild_chunk`), y en el último se ponen los colocables
(la puerta). Las que miden más de 12 celdas a lo largo de X o de Z se centran en el origen de su grid
(`SettlementManager._centering`), sin moverse en el mundo: así caen en dos chunks parecidos y no casi
enteras en uno.

| Prefab | Fotogramas (ms, sin ventana) |
|---|---|
| `choza` | 3,2 + 4,7 + 2,2 (la primera puerta carga su escena) |
| `granero` | 2,9 + 4,4 + 1,2 |
| `casa` | 5,2 + 7,4 + 1,0 |
| `casa_larga` | 8,2 + 6,4 + 6,3 + 0,3 |
| `iglesia` | 8,1 + 1,1 + 5,1 + 6,0 + 0,3 |

Antes de repartir el mallado, la casa larga y la iglesia costaban unos 13 ms en un fotograma.

**El guardado.** Las grids de un poblado llevan `GridBase.settlement` ("<poblado>:<casa>") y
`GridManager.get_save_data` se las salta: salen siempre iguales del plano. Una casa pasa a ser de la
partida en cualquiera de estos casos:

- el jugador pone o quita un bloque o un colocable (abrir o cerrar la puerta no cuenta:
  `GridBase.set_prop_state` no avisa);
- un golpe rompe un bloque;
- desaparece alguna de sus grids sin que la quite el poblado (desmontarla, convertirla en dinámica).

Desde entonces la casa es una construcción normal: se guarda con la partida y no se quita al alejarse.
El gestor apunta su clave en `claimed` (`save_category` "planet", `entity_id` "<planeta>_settlements")
y ya no la levanta. Al cargar una partida, `prepare_restore` suelta antes las grids del poblado, para
que no cuenten como tocadas cuando `GridManager` las quita. El daño que no rompe ningún bloque no
cuenta y se pierde al alejarse.

## Consola

`village` dice qué poblado es el más cercano (su plantilla y cuántas construcciones tiene), a cuántos
metros y en qué rumbo, y cuántos hay en el planeta. `village tp` deja al jugador de pie en su plaza.

## Caché y costes

`user://maps/<planeta>_settlements.bin` (zstd). La clave lleva la de las sendas (y con ella la huella
del generador), `settlement_settings`, la firma de las plantillas y los prefabs (incluido el contenido
de sus blueprints) y `SettlementField.FILE_VERSION`, que hay que subir al cambiar cómo se traza.

| | |
|---|---|
| Primera carga | 4,3 s (la Tierra, 16 hilos): leer el suelo cuesta ~0,15 ms por punto |
| Cargas siguientes | La caché y la imagen del claro, poca cosa; ~20 ms por generador de árboles al compilar el claro |
| Memoria | 8 MB la imagen del claro |
| Levantar una construcción | De 2 a 4 fotogramas de 1-8 ms (ver «En partida») |

## Configuración

`settlement_settings` en `data/planet/planet_earth.json`. Sin esa clave el planeta no tiene poblados.

| Clave | Por defecto | |
|---|---|---|
| `enabled` | true | |
| `seed` | 1 | El sorteo y las plantillas |
| `fraction` | 0,33 | Probabilidad de que una punta suelta lleve poblado (la Tierra: 1) |
| `min_spacing` | 1500 | Distancia mínima entre poblados (m) |
| `roadside_spacing` | 0 | Un sitio junto a la senda cada tanto (m de trazo); 0 = ninguno (la Tierra: 1000) |
| `roadside_setback` | 14 | Lo que se aparta del eje de la senda (m) |
| `roadside_fraction` | 0,5 | Probabilidad de que un sitio junto a la senda lleve poblado |
| `max_slope` | 0,25 | Desnivel / distancia que se acepta en la plaza |
| `max_step`, `max_grade` | 3, 0,25 | Desnivel dentro de una huella: hasta `max_step` m o `max_grade` por su lado largo, lo que sea más |
| `clear_margin` | 14 | Claro de los árboles más allá de lo más lejano (m) |
| `load_distance`, `unload_distance` | 600, 800 | Cuándo se levantan y se quitan (m) |

## Comprobaciones

```sh
godot --headless --path . res://tests/world/test_settlements.tscn
```

La prueba cubre:

- los prefabs: el hueco de su puerta, que delante no haya tejado hasta los 2 m, que desde la puerta se
  entre andando, que tengan ventanas, que cada cristal dé a fuera y que una puerta cierre la entrada;
- las puntas sueltas de unas sendas inventadas y el sorteo;
- el plano de cada plantilla sobre un llano y sobre una ladera del 12 %: separadas, con la puerta a la
  plaza, la llegada libre, el suelo a menos de un escalón y el zócalo dentro del terreno;
- que no hay plaza en un risco ni bajo el mar;
- la imagen del claro y los árboles apartados, y la caché;
- el gestor con grids de verdad: levanta, no guarda, quita al alejarse, abrir una puerta no cuenta,
  pasa a la partida al poner un bloque o al desmontar, y una partida cargada no cuenta como tocada.

## Pendiente

- **El terreno.** Aplanar la plaza y las huellas en el grafo del terreno, como las sendas, con tierra
  pisada en la plaza y sin hierba bajo las casas.
- **De lejos.** Más allá de `load_distance` no se ve nada. Faltan un impostor o una marca en el mapa.
- **Mallar en un hilo.** El peor fotograma (poner los bloques de la iglesia, ~8 ms) bajaría con un
  mallador en un hilo o con los bloques del prefab ya leídos.
- **Reparar con el prefab.** `RepairSite` busca el blueprint en la biblioteca del jugador.

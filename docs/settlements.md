# Poblados

Al final de las sendas del mundo y a sus lados hay poblados: granjas, aldeas y poblados de
construcciones de bloques con su gente ([Aldeanos](villagers.md)): casas de troncos, de tablas, de tepe y
de entramado, graneros, la herrería, la tienda, los puestos del mercadillo y la iglesia, con su decorado y
una cerca alrededor. Se eligen y se trazan al crear el
planeta, después de las sendas y sobre el terreno definitivo. Las construcciones se levantan cuando
el jugador se acerca.

| Pieza | Qué hace |
|---|---|
| `SettlementSites` (`scripts/world/settlement_sites.gd`) | Los sitios (las puntas sueltas de las sendas y a sus lados) y el sorteo de cuáles llevan poblado |
| `SettlementLayout` (`scripts/world/settlement_layout.gd`) | El plano de un poblado: la plaza, y dónde va cada construcción, girada cómo, a qué altura, con su zócalo y su rampa |
| `SettlementField` (`scripts/world/settlement_field.gd`) | Lo junta todo en hilos, lo guarda en caché y abre el claro de los árboles |
| `SettlementFlatten` (`scripts/world/settlement_flatten.gd`) | El aplanado del terreno de cada poblado, en el grafo del terreno |
| `SettlementPrefab`, `SettlementTemplate` | Los datos: cada construcción (un blueprint) y cada clase de poblado |
| `SettlementProp` (`scripts/world/settlement_prop.gd`) | El decorado de una construcción: barriles, cajas, sacos, mercancía, letreros, el yunque, la cruz |
| `SettlementWall` (`scripts/world/settlement_wall.gd`) | La cerca: empalizada o cerca de varas, con sus puertas |
| `SettlementStreets` (`scripts/world/settlement_streets.gd`) | Las calles y la plaza de una villa, que pinta el terreno |
| `SettlementAnimal` (`scripts/world/settlement_animal.gd`) | El ganado de los cercados y los perros sueltos |
| `SettlementManager` (`scripts/world/settlement_manager.gd`) | En partida: levanta y quita las construcciones, y sabe cuáles ya son de la partida |
| `tools/build_settlement_prefabs.tscn` | Genera los prefabs provisionales y las plantillas |
| `tools/build_settlement_flatten.gd` | Genera `data/graph_functions/settlement_flatten.tres`, la función del aplanado |

`Planet` lo lee de la caché antes de compilar el grafo (`_load_settlements`, que mete el aplanado) o, sin
caché, lo traza después (`_trace_settlements`: trazar, aplanar, recompilar y volver a trazar), y lo deja
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
aldeas y 83 poblados, cada uno con su iglesia (medido con las plantillas de antes de las tiendas y la
cerca, que llevan más construcciones). El vecino más cercano queda a unos 1,9 km (mediana;
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
cabaña de `tests/building/thatch_roof_preview.gd`: suelo, paredes, tejado a dos aguas con la cumbrera a
lo largo de X (faldones y cumbrera de paja, de tejuelas o de tepe: ver [Materiales de las
casas](building.md#materiales-de-las-casas-y-carpintería)) y frontones por fuera de las paredes de los
extremos. La herramienta tiene piezas para montarlas: la casa con el material de cada celda de pared,
huecos de puerta, ventanas (un panel de cristal en la cara de fuera de la pared, o un cuadrado de cristal
en el frontón), la chimenea, la torre de la iglesia y el toldo de los puestos, y:

- **el entramado** (`_half_timber`, `_frame`): listones de fachada de tablas oscuras en las celdas de
  fuera del muro, pegados a él. Las líneas van por los cantos de las celdas, así que siguen de una a otra
  sin hueco: postes en las esquinas y cada dos o tres celdas, la solera, un travesaño, y en los frontones
  riostras bajo el de arriba. Donde se cruzan, la escuadra. No se pone nada delante de un hueco de puerta;
- **los marcos** (`_frame_openings`) de puertas y ventanas: las dos jambas (la de la derecha, el listón
  reflejado), el dintel y, en las ventanas, la peana;
- **el decorado** (`SettlementProp`, ver abajo).

Cada entrada lleva su **puerta de madera** (`wooden_door`, ver [Puertas y
trampillas](building.md#puertas-y-trampillas)), puesta como con el martillo. La casa se levanta en una
grid de verdad y la hoja se encaja con `WoodenDoor.fit`, apuntando a la jamba desde fuera, así que queda
a ras de la cara de fuera del muro con las bisagras en esa jamba. El blueprint sale de
`GridBlueprint.capture`, como al guardar uno, sin la fecha para que no cambie si no cambia la casa. Por
eso la herramienta es una escena (hacen falta los autoloads) y no un script de `-s`. `capture` guarda las
celdas con la caja desde 0: por eso todo empieza en x = 0 (los frontones) y en z = 0 (los aleros), y lo
que se mide en metros (lechos, puestos, decorado) cuenta desde ahí.

Las paredes miden 3 m (5 la iglesia, 6 la casa alta). Con 2, el alero del lado largo bajaba hasta el
dintel y tapaba la puerta.

| Prefab | Para qué | Suelo | Cómo es |
|---|---|---|---|
| `choza` | casa, 2 lechos | 6 × 5 | Troncos con esquinas de piedra, tejado de tepe, frontones de tablas; puerta enmarcada en el frontón y una ventana en cada pared; leñera detrás |
| `casa` | casa, 3 lechos | 9 × 7 | Entramado sobre enlucido, tejado de paja; puerta en el lado largo entre dos ventanas, chimenea, huerto detrás |
| `casa_tablas` | casa, 3 lechos | 8 × 7 | Tablas oscuras con esquinas de piedra, tejado de tejuelas; bastidor de pieles junto al frontón y leñera |
| `casa_turba` | casa, 3 lechos | 8 × 7 | A la islandesa: piedra abajo y tepe encima, tejado de tepe, el frontón de delante de tablas con la puerta; secadero de pescado y huerto |
| `casa_alta` | casa, 3 lechos | 7 × 7 | Dos plantas: piedra abajo, entramado arriba, tejado de tejuelas; escalera de rampas al piso de tablas |
| `casa_larga` | casa larga, 6 lechos | 17 × 7 | Zócalo de piedra y troncos, tejado de tejuelas, ventanas enmarcadas; banco dentro y leñera detrás |
| `granero` | almacén | 7 × 5 | Tablas con zócalo de piedra, tejado de paja, portón de 3 × 2 en el frontón; banco, sacos y cajas |
| `tienda` | tienda, 2 lechos | 9 × 7 | Entramado y tejuelas; en el lado largo, un mostrador de tres celdas abierto a la calle con la mercancía encima, la puerta al lado y el letrero en el frontón; el tendero detrás |
| `herreria` | herrería | 7 × 5 | Piedra, abierta por delante entre dos pilares, tejado de tejuelas y chimenea; dentro la fragua, el yunque, el barril de templar y el herrero |
| `puesto_comida`, `puesto_pieles`, `puesto_cacharros` | puesto | 3 × 3 | Suelo de tablas, dos losas de mostrador con el paso entre ellas, postes en las esquinas y toldo de lona a rayas; la mercancía de su género y quien la vende |
| `iglesia` | iglesia | 13 × 7 + torre de 3 × 3 | Nave de tablas oscuras sobre sillería, tejado de tejuelas, ocho ventanales de dos celdas, el altar al fondo y una vidriera en el frontón; delante, el campanario de tablas con la entrada (puerta de 1 × 3), los vanos de las campanas, un chapitel de tejuelas y la cruz |

Los puestos y la herrería no tienen hoja de puerta ni ventanas: son abiertos por delante, y su «puerta»
(`door_cell`) es por donde se entra.

**Uno hecho con el martillo** sustituye a cualquiera: se construye (con sus puertas), se guarda como
blueprint y se copia `user://blueprints/<nombre>.json` encima de `data/settlements/prefabs/<id>.json`.
Después se ajustan `door` y `door_cell` en la ficha. Los blueprints entran en la firma de la caché, así que en la siguiente
carga se vuelven a trazar los poblados. Las casas que el jugador no ha tocado salen ya con el prefab
nuevo.

Una **plantilla** (`SettlementTemplate`, `data/settlements/templates/<id>.tres`) es una clase de
poblado. Las lee todas `SettlementField.load_templates`. Una de otro bioma o de otra gente será una
plantilla nueva, no código nuevo.

| Plantilla | Peso | Principal | Las demás (al azar, con repetición) | Cuántas | Plaza, corona | Cerca |
|---|---|---|---|---|---|---|
| `granja` | 0,38 | casa | granero, choza, casa de tepe, casa de tablas | 1-3 | 8, 10 m | de varas |
| `aldea` | 0,36 | casa larga | choza, casa, casa de tablas, casa de tepe, granero, herrería, puesto de comida | 5-8 | 11, 20 m | empalizada |
| `poblado` | 0,18 | iglesia | casa, casa alta, casa de tablas, casa larga, granero, tienda, herrería, los tres puestos, casa de tepe, choza | 10-14 | 15, 28 m | empalizada |
| `villa` | 0,08 | iglesia | en las calles: casas (de todas), casa larga, granero, herrería; en la plaza: tienda, herrería y puestos (8-12) | 26-40 | 16 m; calles de 68 m | empalizada |

**El decorado** (`SettlementPrefab.props`, `SettlementProp`) es como los sitios de trabajo: el plano lo
asienta (`"props"` de cada construcción; los de fuera, `grounded`, en el terreno) y `SettlementManager` lo
pone con la casa (`SettlementDecor.prop`), sin guardarlo. Hay barriles, cajas, sacos y arcones, el yunque y
la fragua, la cruz, el letrero colgado de un brazo con la seña de lo que se vende, el bastidor con una
piel, el secadero con pescado colgado y la mercancía: cualquier objeto del juego, que se ve con su escena
(`SettlementDecor.goods`, solo sus mallas). Los grandes llevan colisión.

La herramienta no pisa las plantillas que ya existen; con `-- --templates` las rehace.

```sh
godot --headless --path . res://tools/build_settlement_prefabs.tscn [-- --templates]
```

## La villa

Una plantilla con `layout = &"streets"` (`SettlementLayout._plan_streets`) no reparte en corona:

- **La plaza** (`plaza_radius`) es el mercado. La principal va a su fondo, frente a la llegada, con la puerta
  en el borde. Lo de `plaza_buildings` va en corro: los puestos dentro de la plaza, entre la mitad y siete
  décimas de su radio, y lo demás (la tienda, la herrería) en su borde, todo con la puerta al centro.
- **Las calles** (`streets`, de `street_width` de ancho) salen de la plaza y llegan hasta pasar la cerca.
  Primero, una por cada senda que entra en la villa (`_trail_ways`): donde la senda cruza el círculo de
  fuera (`street_length` + 8 m; los mínimos de la distancia a su eje por la vuelta, en el campo fino del
  terreno, el que se pinta) y de ahí hacia dentro por la senda, en círculos cada 4 m mientras la haya;
  luego, derecha a la plaza. Así la calle va encima de la senda y sale por la puerta alineada con la de
  fuera. Después, hasta `streets`, las de siempre por los huecos (a más de 35° de otra): hacia la llegada,
  a los lados y en diagonal hacia el fondo. Los solares llegan hasta `street_length` del centro. Una
  **ronda** las cruza a seis décimas de su largo, en cuerdas de 20°. Si una senda entra por el fondo, la
  principal se aparta a un lado.
- **Las casas** (`buildings`) van a los dos lados de cada tramo de calle, una tras otra, con la cara de la
  puerta a `STREET_SETBACK` m del borde. Por delante la huella llega solo al borde de la calle (la rampa,
  si hace falta, baja a ella). Su cuerpo, sin el decorado ni los sitios de trabajo de fuera, no puede
  pisar ninguna calle. Las sendas solo se miran bajo el cuerpo: la de llegada es la calle de entrada.
- Si no caben `count_min`, no hay villa y el sitio prueba las demás plantillas: solo sale en sitios
  bastante llanos.
- La cerca lleva puerta al final de cada calle.

`SettlementStreets` hace que las calles y la plaza las pinte el propio terreno con el material de las
sendas: el mismo borde con ruido, la misma mezcla por altura con el suelo de al lado, mojadas con la lluvia
y bajo la nieve. No hay malla. Cuando una villa está cerca (con su cerca), sus calles van a los
sombreadores como tramos (`shaders/lib/settlement_streets.gdshaderinc`): el eje de cada calle leído en el
suelo, sin los puntos que no la apartan más de 0,25 m de la recta, con su medio ancho; la plaza, un tramo
de un punto con su radio. Van en una textura global (`settlement_streets`, 128 tramos entre todas las
villas cercanas, con `settlement_street_count` y una esfera que los abarca, `settlement_street_bounds`) en
coordenadas canónicas (mundo + desplazamiento del origen flotante), como la sangre de la vegetación, así
que no hay que moverlos al recentrar.
- `planet_biomes.gdshader` suma la calle al peso de la senda por píxel, a cualquier distancia, con el borde
  de la senda de lejos (`trail_edge_softness`, ensanchado con `trail_width_variation`), y solo en la
  superficie.
- `grass_wind.gdshader` encoge a su pie la hierba y el sotobosque cuya mata cae a más de 0,4 m dentro de una
  calle, como las sendas, que no tienen hierba; en el borde se deja algo.
Fuera de la esfera no se mira nada: sin una villa cerca no cuesta nada.

Con las calles de 68 m, la villa del banco de pruebas sale con 35 construcciones y unos 70 lechos.

## Los cercados y los perros

Un adorno `&"pen"` (`SettlementProp.size`, `.animals`) es un cercado de varas (`SettlementWall` con la cerca
de las granjas, por el contorno leído al trazar, un poste cada 2 m) con su ganado dentro: vacas y un ternero
detrás del granero, cabras junto a la casa de tepe, caballos y un burro detrás de la casa larga.

`SettlementAnimal` es el modelo de la escena de fauna con sus animaciones (su `NPCModel` sin el
`AnimationTree`, que mandaría en el esqueleto, y sin IA, física ni salud): está quieto, pasea a otro sitio de su zona y, el que puede, se tumba; se pega al suelo con un rayo
como los aldeanos (también parado, cada segundo, por si apareció antes que la colisión del terreno). No se caza ni se guarda. A más de 140 m del jugador se oculta y no se anima. Los perros
(labrador o sabueso, uno por cada tres casas con gente, hasta seis) los suelta `SettlementVillagers` cuando
el poblado cobra vida, y van de la plaza a las puertas de las casas.

## La cerca

La plantilla dice si lleva cerca (`SettlementTemplate.wall`). `SettlementLayout._wall` la traza con el
plano: la envolvente convexa de las huellas (con la rampa y los sitios de trabajo) y de la plaza,
apartada `WALL_GAP` (4 m), con un vértice cada 3,75° (`WALL_SEGMENTS`, 96) sobre el suelo y algo ondulada
para que no parezca trazada a compás. Cada tramo es cerca, puerta o hueco (sin suelo o bajo el mar). Lleva
puerta donde una senda pasa a menos de `WALL_GATE_TRAIL` (2,5 m) del centro de un tramo, siempre en la
llegada de la senda del poblado, y ninguna más estrecha que `WALL_GATE_MIN` (3,5 m).

`SettlementWall` la levanta cuando el poblado se levanta y la quita con él: decorado con colisión (una caja
por tramo), ni se guarda ni se toca con el martillo.

La empalizada tiene guardia (ver [Aldeanos](villagers.md)): dos puestos por puerta, por dentro a cada lado
y mirando fuera (`wall.posts`), y una ronda por dentro de la cerca (`wall.patrol`).

- **Empalizada** (aldeas, poblados y villas): troncos de 2,7 a 3,1 m con la punta afilada, uno cada 30 cm y
  enterrados medio metro, algo torcidos, con dos largueros por dentro. Cada puerta, entre dos postes de
  4 m con un dintel y las dos hojas de tablones abiertas hacia fuera.
- **Cerca de varas** (granjas): postes cada 2,2 m y tres varas; la puerta, dos postes.

Los troncos siguen el suelo entre vértices interpolado, no leído: van enterrados lo bastante para que no
floten en un suelo algo abombado. Todo va en `MultiMesh` (una malla por pieza).

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

## De lejos y en el mapa

**De lejos** (`SettlementFar`, `scripts/world/settlement_far.gd`). Entre `load_distance` y `far_distance`,
cada poblado es una sola malla sin texturas, con el color medio de cada material (`SettlementFar.COLORS`,
sacado de sus albedos). Sale del blueprint de cada casa, con su zócalo, su rampa y la empalizada:

- los cubos, con las caras de un mismo material en un mismo plano juntas en rectángulos;
- los faldones y las cumbreras de paja, tejuelas o tepe: cada hilera de piezas iguales, como una sola tira
  con el perfil sin las capas;
- las rampas, esquinas, paneles y losas, como en la grid;
- sin carpintería (postes, listones, riostras, escuadras), sin puertas ni decorado, y sin la cerca de
  varas;
- bajo el suelo de cada casa, un faldón de piedra de 2 m, por si el terreno de lejos queda más bajo que el
  de cerca.

Son de 130 a 680 triángulos por casa en vez de 2000-7000, y de 0,3 a 4 ms por casa. La malla de cada poblado
se hace en un hilo (`WorkerThreadPool`) y se suelta pasados `far_distance` + 300 m. Las caras van metidas
5 cm hacia dentro, así que mientras el poblado se levanta las casas de verdad tapan las de lejos sin
parpadear. Cuando ya están todas, la malla se esconde. Las casas que son de la partida no salen en ella:
al pasar una a la partida, la malla se rehace.

**En el mapa** (`SettlementMap`, `scripts/ui/settlement_map.gd`). El mapa grande (M) y el minimapa
dibujan todos los poblados (`SettlementManager.map_sites`) con un icono por plantilla
(`textures/icons/settlements`): la granja con su cerca, la aldea con dos casas, el poblado con la iglesia y
la villa tras la empalizada. En el mapa grande, de lejos, cada poblado es un
punto. Los que el jugador conoce van en hueso y los demás, apagados. Un poblado se conoce cuando se ha
visto de cerca (a menos de `load_distance`, y queda guardado en la partida) o cuando lo nombra un encargo
abierto. Con el zoom cerca, el mapa grande rotula los conocidos con su nombre
(`SettlementPopulation.village_name`).

## Consola

`village` dice qué poblado es el más cercano (su plantilla y cuántas construcciones tiene), a cuántos
metros y en qué rumbo, y cuántos hay en el planeta. `village tp` deja al jugador de pie en su plaza.

## El aplanado

El terreno de cada poblado se acerca a un plano con su pendiente media, hasta 40 m más allá de lo más
lejano y fundiéndose con el de alrededor en 75 m más. Va en el grafo del terreno, como las sendas, así
que el terreno nace aplanado, sin ediciones que guardar, y se ve igual de lejos.

- **No del todo.** El peso dentro es `STRENGTH` (0,75), no 1. Un plano perfecto en terreno ondulado se
  veía como una plataforma recortada en el paisaje; así los bultos se suavizan pero el relieve natural
  se nota. Se mezclan las SDF, no las alturas, y la del terreno crece menos de un metro por metro (bajo
  tierra, un tercio), así que el suelo se acerca al plano entre tres cuartos y nueve décimas de lo
  que le falta, según el sitio.

- **El plano.** Mínimos cuadrados sobre el suelo de lo ocupado: el origen y la puerta de cada
  construcción, la plaza y las calles de una villa. No sobre todo el círculo, porque en el borde de una
  meseta medio círculo es ladera abajo. La pendiente se queda en `MAX_TILT` (0,25, la de una plaza)
  como mucho; con menos, el plano sigue pasando por la media de lo ocupado. En la Tierra la pendiente
  mediana es 0,185.
- **Dónde no.** Bajo el mar, junto a un río (de 15 a 45 m del cauce, para no rellenarlo) y donde haría
  falta mover más de 12 m de tierra (se retira hasta los 21 m). Un risco o un barranco junto al poblado
  se quedan.
- **El grafo.** `settlement_flatten.tres` va entre las sendas y las cuevas. Lee dos imágenes de
  4096 × 2048 RF en la convención de `SdfSphereHeightmap`: la cota del plano (el nodo da directamente su
  SDF) y el peso. Mezcla el campo con la SDF del plano por el peso, solo a menos de 60-90 m de la
  superficie. Lo que cada poblado escribe en ellas (`SettlementFlatten.fit`) va en la caché (`"flats"`);
  al cargar solo se pintan los téxeles.
- **Las cuevas.** Su ruido no sabe del relieve, y donde un túnel pasa justo bajo la superficie abre una
  boca. Dentro de un poblado volvería a vaciar lo rellenado, así que la función saca también su peso y
  las cuevas tienen un techo (`cave_roof`, entrada nueva de `cave_field.tres`, 0 fuera): el peso por
  8 m. Ya no hay bocas de cueva en las plazas.
- **La vegetación de cuevas.** Sus setas brotan donde el punto queda de 3 a 12 m bajo la superficie
  sin tallar que reconstruye su grafo (`cave_vegetation_field.tres`, como con los ríos). Donde el
  aplanado rebaja el suelo, eso es la superficie, y salían setas fuera. Su grafo lleva también la
  función del aplanado, tras el tallado de los ríos, y `Planet._load_vegetation_graph` le mete las
  imágenes (`SettlementFlatten.present`). Medido: de 2418 puntos con setas en la superficie de los
  poblados a 6, de 32 260.
- **Las casas.** Con el aplanado en el grafo se vuelven a trazar todos los poblados en los mismos sitios
  y con la misma plantilla, sobre el suelo aplanado (`SettlementField.replan`): las casas se asientan en
  lo que haya de verdad. Si alguno ya no cabe, su llano se queda igual (los `"flats"` son aparte).

Trampas del nodo, medidas:

- **Las zonas constantes las lee como 0.** Fuera de los poblados es justo el neutro (peso 0), pero
  dentro el peso vale 1 en todo un trozo, y en un llano la cota también es igual. Los téxeles escritos
  llevan un temblor de 1 mm de cota y una millonésima de peso.
- **Solo lee la imagen cerca de su propia superficie.** Dos téxeles del polo llevan cotas de -1200 y
  2200 m para que lea todo el relieve.
- **La poda.** Un Select calcula siempre lo que prueba, aunque pode la rama que no elige, y el peso sale
  de restar dos valores que varían por el bloque, con lo que su rango nunca se cierra. El peso lleva un
  factor de 10⁶ y el Select prueba `max(peso - 0,002, 0)`. Lejos de los poblados ese rango es justo 0 y
  el runtime deja de leer la imagen. Sin esto, generar terreno costaba un 30 % más en todo el planeta.

Medido en la Tierra (`build/flatten_check/planet_flatten.tscn`):
- **Poblados.** Salen 287-288. Con el plano entero (`STRENGTH` 1), donde el peso
  era entero el suelo coincidía con el plano a 3-4 mm.
- **Coste de generar.** Un bloque de 32³ cuesta igual lejos de los poblados (5,2 frente a 5,1 ms) y un
  20 % más dentro de ellos.

## Caché y costes

`user://maps/<planeta>_settlements.bin` (zstd). La clave lleva la de las sendas (y con ella la huella
del generador), `settlement_settings`, la firma de las plantillas y los prefabs (incluido el contenido
de sus blueprints) y `SettlementField.FILE_VERSION`, que hay que subir al cambiar cómo se traza.

| | |
|---|---|
| Primera carga | 12 s (la Tierra, 16 hilos): trazar, aplanar, recompilar el grafo y volver a trazar; leer el suelo cuesta ~0,15 ms por punto |
| Cargas siguientes | La caché, las imágenes del claro y del aplanado, poca cosa; ~20 ms por generador de árboles al compilar el claro |
| Memoria | 8 MB la imagen del claro y 64 MB las dos del aplanado |
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
| `far_distance` | 4000 | Hasta dónde se ven de lejos (m) |

## Comprobaciones

```sh
godot --headless --path . res://tests/world/test_settlements.tscn [-- --only=prefabs,sites,layout,clearance,flatten,manager,villagers]
```

La prueba cubre:

- los prefabs: el hueco de su puerta, que delante no haya tejado hasta los 2 m, que desde la puerta se
  entre andando, que tengan ventanas, que cada cristal dé a fuera y que una puerta cierre la entrada
  (menos los puestos y la herrería, abiertos por delante);
- las puntas sueltas de unas sendas inventadas y el sorteo;
- el plano de cada plantilla sobre un llano y sobre una ladera del 12 %: separadas, con la puerta a la
  plaza, la llegada libre, el suelo a menos de un escalón y el zócalo dentro del terreno;
- que no hay plaza en un risco ni bajo el mar;
- que la cerca rodea todas las construcciones y tiene puerta donde llega la senda;
- la imagen del claro y los árboles apartados, y la caché;
- el aplanado sobre una ladera: el plano sigue la pendiente con tope, pesa entero dentro y nada lejos, y
  no rellena un barranco de 30 m junto al poblado;
- el gestor con grids de verdad: levanta, no guarda, quita al alejarse, abrir una puerta no cuenta,
  pasa a la partida al poner un bloque o al desmontar, y una partida cargada no cuenta como tocada;
- el mapa: el poblado sale sin nombre hasta verlo de cerca, y se sigue conociendo al cargar;
- de lejos: la malla barata del poblado sale sin las casas de la partida y se esconde con todas
  levantadas.

## Pendiente

- **El terreno.** Sin hierba bajo las casas (el aplanado y las calles ya están).
- **De lejos.** Sin los cercados, el ganado ni la cerca de varas. Sin nieve en los tejados. Más allá de
  `far_distance` no se ve nada.
- **Mallar en un hilo.** El peor fotograma (poner los bloques de la iglesia, ~8 ms) bajaría con un
  mallador en un hilo o con los bloques del prefab ya leídos.
- **Reparar con el prefab.** `RepairSite` busca el blueprint en la biblioteca del jugador.

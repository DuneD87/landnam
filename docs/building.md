# Construcción

Los bloques se ponen y se quitan con el **martillo de piedra** (`stone_hammer_01`) en la mano. Se
fabrica a mano con una rama, dos piedras y una fibra vegetal, y la partida de pruebas lo da al empezar.
Con él en la mano no se ataca, como pasaba antes con un bloque en la barra.

`PlayerController._sync_build_mode()` enciende el modo construir con el martillo en la mano derecha
(`ToolType.HAMMER`) o con un colocable elegido en la barra, y lo apaga con cualquier otra cosa. Mira
la mano al cambiar la barra, al cambiar el equipo (también desde el muñeco) y al cargar partida.

## Controles

| Entrada | Con el martillo |
|---|---|
| Clic izquierdo | La acción elegida: poner el bloque elegido o quitar el apuntado |
| Clic derecho | Abre la rueda (ver abajo) |
| H | Cambia entre poner y quitar sin abrir la rueda |
| B | Abre el menú de bloques. Sin martillo, avisa de que hace falta uno |
| G | Menú de blueprints, como «Blueprints» en la rueda |
| Mayús + rueda | Tamaño de celda: 0,25 · 0,5 · 1 · 2 m (también arriba del menú de bloques) |
| 4, 8 y 9 del teclado numérico | Giran el bloque en X, Y y Z (los que giran). Con una puerta o una trampilla, el 4 la tumba o la pone de pie y el 8 la pasa a la otra cara del hueco |
| V / N | Simetría sobre el bloque apuntado / cambia su plano (también desde la rueda) |
| J | Convierte en dinámica la grid apuntada |

## La rueda

`BuildRadialMenu` (`scripts/ui/menu/build_radial_menu.gd`) tiene seis huecos. En el sentido de las
agujas del reloj desde arriba: a la derecha lo de cada golpe, abajo reparar y a la izquierda los
menús.

1. **Añadir bloque**: el clic izquierdo pone.
2. **Quitar bloque**: el clic izquierdo quita bloques y colocables.
3. **Simetría**: sin ella, la pone en el bloque apuntado, en el eje X. Puesta, pasa al eje
   siguiente, y después del Z la quita. Su hueco dice el eje («Simetría Y») y, bajo el ratón, el
   centro dice qué hará. Si no se apunta a un bloque, avisa.
4. **Reparar**: deja una reparación en la construcción apuntada, con su blueprint (ver «Reparar»,
   abajo). Si no se sabe cuál es, abre la biblioteca para elegirlo.
5. **Blueprints**: abre el menú de blueprints (ver abajo).
6. **Elegir bloque**: abre el menú de bloques. Su hueco enseña el icono del bloque elegido.

Se usa así:

- **Elegir:** se mantiene el clic derecho, se lleva el ratón hacia un hueco y se suelta. El clic
  izquierdo también elige.
- **Toque corto:** pulsar y soltar en menos de 0,25 s sin apuntar a nada la deja abierta; elige el
  siguiente clic.
- **Cerrar sin elegir:** soltar en el centro después de mantener, o Esc.
- **El ratón:** sigue capturado. Su movimiento lleva un cursor virtual (el rombo de bronce) y la
  cámara no gira mientras la rueda está abierta, porque la rueda recibe la entrada antes que la
  cámara.
- **Lo activo:** el modo (poner o quitar) y la simetría puesta llevan un arco de bronce por fuera, y el
  centro dice el modo y el bloque. Poner, quitar y la simetría avisan sobre la barra al elegirlos.

Las medidas están en la escala base de 1440 px (`GameTheme.scale_for`). Si cuesta apuntar, se tocan
`OUTER_RADIUS`, `INNER_RADIUS`, `DEAD_ZONE` y `TAP_TIME`.

## Menú de bloques

`BuildMenu`, en Saga:

- **Izquierda:** los materiales, con lo que se lleva de cada uno, y los recientes. Los recientes son los
  últimos bloques elegidos de cualquier material (`BuildingSystem.recent_blocks`, 8 como mucho, solo en
  la sesión). Al final de los materiales, **Naval** (ver «Piezas navales») y **Puertas** (ver «Puertas
  y trampillas»), que enseñan su panel en lugar de los bloques y la ficha.
- **Centro:** los bloques del material. Los que no alcanza para poner ni uno salen apagados, pero se
  pueden elegir igual.
- **Derecha:** la ficha del bloque bajo el ratón, o del elegido: el tamaño de celda, el coste por
  bloque, lo que se lleva, para cuántos bloques alcanza y si se gira.
- **Arriba:** el tamaño de celda.

Al hacer clic en un bloque, o en «Construir con este bloque», queda en el martillo con su material
(`BuildingSystem.pick_block`), se vuelve a poner y el menú se cierra. Se cierra también con Esc, B, el
aspa o un clic fuera.

Los bloques ya no van en la barra rápida. Las partidas de antes que los tenían allí los descartan al
cargar (`Hotbar.restore_save_data`).

## Lo que cuesta

Un bloque gasta su material según el tamaño de celda: `BuildMaterial.get_cost_for_size`, como mínimo 1.
Un colocable gasta una unidad de su objeto; las velas navales y las puertas y trampillas consumen
materiales según sus medidas.
Quitar un bloque devuelve la parte de su coste que le queda
de vida, redondeando hacia arriba. Lo que no cabe en el inventario cae al suelo delante del jugador;
antes se perdía.

`BuildCost` (`scripts/building/build_cost.gd`) hace las cuentas para todo lo que no es un bloque suelto:

- **Un blueprint:** lo que pide su obra para construirse.
- **Una construcción en pie:** lo que vale y lo que devuelve al desmontarla.
- **Frente al inventario:** lo que falta, pagar y devolver.

El precio sale siempre de los costes de ahora. Una ficha de blueprint solo guarda el recuento de
bloques por material y tamaño de celda, de colocables por objeto y los diseños de las velas y de las
puertas (con la celda de su grid).

**Construir gratis** (consola: `freebuild [on|off]`, `BuildingSystem.free_build`): bloques, colocables
y blueprints no gastan nada. Quitar o desmontar tampoco devuelve nada, para que no sea una fuente de
material infinita. Un blueprint se construye entero al colocarlo, sin obra y sin límite de distancia, y
los martillazos en una obra que ya estaba puesta no piden material.

## Blueprints

### El menú

`GridManipulatorMenu`, en Saga, con dos pestañas.

**Construcción.** Es la que se apuntaba al abrir el menú, que se queda fijada. Tiene:

- la miniatura;
- los datos: medidas, bloques, colocables, volumen, celdas y, si es dinámica, masa y compartimentos;
- lo que vale en materiales, que es lo que devolvería al desmontarla;
- **Guardar como blueprint.** Si el nombre ya existe avisa, y hay que pulsar «Sustituir» otra vez.
  Desde entonces la construcción sabe que es ese blueprint (para repararla);
- **Convertir en dinámica**;
- **Desmontar.** Pide pulsar dos veces. Quita todo como el martillo bloque a bloque, devuelve los
  materiales (`BuildingSystem.dismantle_group`), cierra el menú y avisa de lo recuperado. Antes,
  «Eliminar» lo borraba sin devolver nada.

**Biblioteca.** Los blueprints guardados, en fichas con miniatura, medidas, bloques y si llevas los
materiales. Se pueden buscar por nombre y ordenar por nombre o por fecha. La ficha del elegido tiene:

- miniatura y datos;
- los bloques de un tipo que ya no existe, que no se pondrán;
- los materiales, cada uno con «lo que llevas / lo que pide» en verde o en rojo;
- **Colocar**, siempre: queda una obra (ver abajo). «Colocar como estática» en los dinámicos;
- **Reparar**, si el menú se abrió apuntando a una construcción: la repara con este blueprint. Si se
  abrió desde «Reparar» en la rueda para elegirlo, es el botón principal y «Colocar» no sale;
- **Renombrar**, que no pisa otro;
- **Borrar**, que pide pulsar dos veces.

Sin construcción apuntada, el menú abre en la biblioteca.

### Ficheros

En `user://blueprints/`:

| Fichero | Contenido |
|---|---|
| `<nombre>.json` | El blueprint (`GridBlueprint.capture`) |
| `<nombre>.info` | La ficha: datos, recuento de lo que cuesta y bloques desconocidos |
| `<nombre>.png` | La miniatura |

La biblioteca lee las fichas y no los blueprints, que en un barco son megas. Un blueprint sin ficha, de
antes o de otra versión (`INFO_VERSION`), la recupera la primera vez que se lista.

Renombrar y borrar se llevan los tres ficheros.

### Las miniaturas

`BlueprintThumbnail` las pinta con la luz de los iconos.

- **Construcción en pie:** copia las mallas de sus chunks, que ya existen, así que cuesta lo mismo una
  caseta que un barco. Se hace al guardar el blueprint.
- **Blueprint sin miniatura** (uno de antes): se malla de sus datos la primera vez que sale en la
  biblioteca, hasta `DATA_BLOCK_LIMIT` bloques. Pasado ese límite se queda sin miniatura.

### Colocar

`BlueprintPlacer`. El fantasma sigue al puntero. Un panel arriba enseña el nombre, cada material con lo
que llevas y lo que pedirá, si se puede y los controles. No hace falta llevar nada.

No se puede colocar, y el fantasma se pone rojo, si:

- **choca con otra construcción:** algún bloque cae en una celda ocupada. Se mira cada 0,15 s con 600
  bloques como mucho, y al confirmar con todos;
- **está demasiado lejos:** el centro a más de 24 m del jugador, más media diagonal del blueprint.

Al confirmar queda una **obra** sin pagar nada. Si no se puede, sigue colocando y la barra dice por qué.

Al reconstruir, los materiales de los bloques salen del `BuildMaterial` de ahora por su id
(`GridBlueprint._restore_materials`). Los de piedra y madera son subrecursos de su `.tres`, y su ruta
guardada no se podía cargar suelta.

### Obras

`BlueprintSite` (`scripts/building/blueprint_site.gd`): el blueprint colocado y por construir. Lo que
falta se ve como un fantasma azul translúcido, que se aviva al apuntarlo; lo construido ya son bloques
de verdad en las grids de la obra, que se crean vacías al colocarla. `SiteBuilder`
(`scripts/player/site_builder.gd`) la maneja desde el jugador. Se apunta con el rayo de construcción
(8 m), antes que lo que haya detrás, recorriendo sus celdas; no hace falta física para el fantasma.

| Apuntando a la obra | |
|---|---|
| E | Le aporta lo que le falta y se lleva encima, con cualquier cosa en la mano |
| Clic izquierdo con el martillo en modo poner | Un martillazo; mantenido, se sigue martilleando |
| Clic izquierdo con el martillo en modo quitar | Dos clics en 4 s la desmontan |

- **El martillazo** es el golpe vertical del pico, en el sitio (`PlayerCombat.work_strike`), y gasta
  aguante. En el impacto pone los siguientes bloques y suena como poner un bloque de su material.
  Sin material para nada de lo que queda no golpea y avisa.
- **El orden:** de abajo arriba por la base del bloque, y en cada altura por grid y por filas (x, z).
  Si al que toca le falta su material, sigue con los siguientes que lo tienen. Los colocables van al
  final, con todos los bloques puestos.
- **Cuánto pone cada golpe:** el trabajo de un bloque es lo que cuesta (como mínimo 1) y el de un
  colocable, 1. Un golpe hace unas 8 unidades, sin bajar de 3 golpes para acabarla ni pasar de 40
  (`WORK_PER_HIT`, `MIN_HITS`, `MAX_HITS`).
- **Lo que estorba:** no pone nada donde está de pie quien martillea (una caja de 0,8 × 1,8 m); si es
  lo único que queda, avisa de que se aparte. Una celda que al llegarle ya está ocupada (otra
  construcción, o un bloque puesto ahí a mano) se salta y no se cobra.
- **El panel** (`BlueprintSitePanel`), arriba mientras se apunta: el nombre, cuánto lleva hecho, cada
  material con «tiene / pide» y lo que se lleva de lo que falta, qué hacer ahora y los controles.
- **Acabada**, se quitan las grids que se quedaron vacías, se convierte en dinámica si el blueprint lo
  era (salvo «Colocar como estática») y devuelve lo que sobre de lo aportado.
- **Desmontarla** devuelve lo aportado entero y lo construido según la vida de cada bloque
  (`BuildingSystem.dismantle_group`).
- **Grandes:** pasados 4000 bloques el fantasma es la caja de lo que falta, que baja según sube la obra.
- **Guardado:** con las grids (`GridManager`, clave `sites`): el blueprint, la pose, sus grids, el
  estado de cada bloque y lo aportado.

Si se desmonta o se convierte desde el menú una grid de la obra a medio hacer, lo que queda se pone en
una grid nueva en el mismo sitio.

### Reparar

`RepairSite` (`scripts/building/repair_site.gd`): una obra sobre una construcción que ya está en pie,
con lo que le falta para volver a ser la de un blueprint. Pensada para un barco que ha perdido unos
bloques contra las rocas, pero vale para cualquier construcción.

Se empieza con **Reparar** en la rueda del martillo, apuntando a la construcción, o con **Reparar** en
la ficha de un blueprint de la biblioteca (el menú abierto apuntándola). Avisa de cuántas piezas hay
que reponer y cuántos bloques están dañados.

- **Qué blueprint:**
  1. el que apuntan sus grids (`GridBase.source_blueprint`, ver abajo). Casa por poco que quede de
     ella, siempre que algún bloque siga donde dice el blueprint;
  2. si no lo apuntan, o ya no está en la biblioteca, el de la biblioteca que más bloques de la
     construcción explica; a igualdad, el más pequeño. Tiene que salir de él al menos el 60 % de lo
     que hay en pie (lo demás son añadidos) y tiene que quedar al menos el 20 % del blueprint
     (`MIN_MATCH`, `MIN_KEPT`);
  3. si tampoco, la rueda abre la biblioteca para elegirlo a mano. Elegido a mano basta con que
     coincida un bloque: el fantasma enseña lo que haría, y si no es eso se cancela.

  Un blueprint girado respecto a la construcción no casa.
- **Cómo casa sin saberlo:** unos cuantos bloques suyos votan el desplazamiento entre sus celdas y las
  del blueprint, se prueban también los que juntan las esquinas de las dos cajas, y gana el que hace
  coincidir más bloques (`match_blueprint`).
- **De qué blueprint es cada grid** (`source_blueprint`: nombre, cuál de sus grids es y el
  desplazamiento de sus celdas): lo apuntan colocar un blueprint (obra o gratis), guardar la
  construcción como blueprint y acabar de repararla. Va en cada grid y no en el cuerpo del barco, así
  que vale también para las estáticas. Pasa a la grid dinámica al convertirla y a los trozos al
  partirse, se guarda con la partida (clave `blueprint` de la grid) y se renombra con el blueprint.
  Borrar el blueprint no lo quita: se busca otro como si no lo supiera.
- **Qué hace:**
  - pone los bloques que faltan si su celda está libre. Lo que el jugador haya puesto en su sitio, de
    otro material o de otro tamaño de celda, se respeta;
  - devuelve la vida a los bloques dañados que siguen siendo los del blueprint. Cuestan lo que les
    falta para valer lo que costaron: el coste menos lo que devolverían al desmontarlos. Un bloque
    que cuesta 1 se arregla sin material, solo con el martillo;
  - pone los colocables que faltan (la vela, la antorcha), al final, como en una obra.
- **Se ve:** lo que falta, en el fantasma azul de las obras, y lo dañado, en un velo ámbar sobre el
  propio bloque.
- **Con el martillo**, igual que una obra: E aporta, el clic izquierdo martillea y en modo quitar dos
  clics la **cancelan**. Cancelar devuelve lo aportado y deja la construcción como esté. Arreglar un
  bloque se puede estando encima de él; poner uno que falta, no.
- **Solo se apunta con el martillo en la mano.** Mientras tanto la construcción entera es la
  reparación (como una obra), así que con el martillo no se ponen ni se quitan bloques sueltos en
  ella hasta acabarla o cancelarla. Navegando sin martillo, el barco no enseña el panel.
- **Sigue al barco:** va colgada de su cuerpo, en el espacio de sus grids. Si la construcción estática
  se convierte en dinámica, se pasa al cuerpo nuevo.
- **Desmontar la construcción** desde el menú quita la reparación y devuelve lo aportado. Si la
  construcción desaparece de otra forma, lo aportado cae al suelo.
- **Construyendo gratis** se repara al momento.
- **Guardado:** con las obras, con `kind = "repair"`. Su blueprint es solo lo que hay que hacer, ya en
  las celdas de las grids de la construcción: por cada grid del blueprint, una con lo que falta y otra
  con lo dañado (`"repair"`, y `"repair_cost"` en cada bloque). Lleva también con qué casó
  (`"offset"`, `"owners"` y `"source"` en cada grid), para apuntarlo en las grids al acabar.

Lo dañado se mira al empezar: si el barco recibe más golpes mientras se repara, se cancela y se
vuelve a empezar para incluirlos.

## Tejados de paja

Con el martillo equipado, **B → Paja** ofrece **Faldón de paja** y **Cumbrera de paja**.
Se colocan, giran y desmontan como los demás bloques, en celdas de 0,25 · 0,5 · 1 · 2 m.
Cada módulo consume fibra vegetal: 1 · 1 · 2 · 4 unidades respectivamente. Desmontarlo devuelve
el coste según la vida que le quede; los blueprints cuentan y restauran el material de paja.

El faldón sube 45° de -Z a +Z. Para continuar hacia arriba, la siguiente pieza va una celda más
alta y una más hacia +Z. La cumbrera ocupa una fila central propia: su cara inferior está en la base
de la celda y el vértice medio metro más el grosor por encima. Encaja entre el extremo alto de
un faldón a cada lado; el del otro lado se gira 180° alrededor de Y. Las hiladas tienen relieve geométrico y el grosor
se prolonga hacia arriba de la pendiente: la cara inferior coincide con el remate de los muros
y triángulos de madera. Las piezas de tejado se ofrecen solo en paja.

**B → Madera → Panel triangular de madera** cierra los extremos bajo las pendientes. Es un
triángulo rectángulo de 45° con grosor, en la cara de la celda como los paneles cuadrados; gira
y admite simetría. Consume la misma madera que los otros bloques del tamaño elegido. Se combina
con paneles cuadrados para rellenar el centro del frontón hasta la cumbrera. Ambos se colocan
en las celdas de la cara exterior del tejado, junto a sus extremos.

La cara exterior de los triángulos y paneles de madera queda en el mismo plano que el muro,
con las UV proyectadas en metros de la grid. El grosor del triángulo entra hacia la casa;
el de la paja queda sobre su canto inclinado. Así la fachada continúa sin escalones ni
saltos de textura y la madera no atraviesa la cubierta. Los paneles de cristal conservan
su retranqueo de ventana. Contra un bloque macizo, los paneles de madera conservan también
la separación que evita caras coplanares. Se aplica a las construcciones guardadas sin cambiar sus ids.

`ThatchRoofMesh` comparte la geometría entre chunks, iconos y fantasma. Su perfil también define
la colisión convexa y el volumen para masa e impactos. Las fibras conservan la orientación de
la pendiente al girar las piezas. La simetría refleja también los puntos de colisión, incluida
la conversión de una construcción estática en dinámica.

Vista aislada de una cabaña, con órbita al arrastrar y zoom con la rueda:

```sh
godot --path . res://tests/building/thatch_roof_preview.tscn
# Capturas en build/building/thatch/:
godot --path . res://tests/building/thatch_roof_preview.tscn -- --capture --background
godot --headless --path . res://tests/building/test_thatch_roof.tscn
```

## Piezas navales

**B → Naval → Vela** ofrece un aparejo a medida: ancho y alto del paño y altura del
mástil, con vista 3D y coste según el tamaño. Se construye con pieles, tendones, fibra
y ramas directamente sobre cubierta. Los barcos dinámicos se propulsan con esas velas
y el viento ligado al clima. Las flechas gobiernan el rumbo y el despliegue;
R permite remar gastando aguante. Ver [Velas y navegación](sailing.md).

Con el martillo equipado, **B → Naval** abre el editor de **Proa**, **Tramo de casco** y
**Popa plana**, con vista 3D que se gira al arrastrar y zoom con la rueda. Se ajustan por separado
ancho (X), alto (Y) y largo (Z), en metros y en pasos del tamaño de celda elegido arriba.
La proa ofrece afinado recto o curvo. Las medidas son exteriores; fondo y costados tienen
**una capa de bloques de grosor**: 0,25 · 0,5 · 1 · 2 m según la celda.

Las piezas generan una cáscara de madera con proa elíptica y unión redondeada entre fondo y
costados. La superficie se recorta en celdas editables conservando sus caras curvas: la rejilla
no produce escalones en el contorno. Cada celda parcial guarda su geometría, volumen y colisión;
las celdas completamente llenas se fusionan como los cubos de la construcción habitual.
Los tramos abren ambos extremos, la proa cierra +Z y la popa cierra -Z. Todas dejan el techo
abierto. El tamaño inicial es 12 × 6 × 12 bloques; con celda de 0,25 m son 3 × 1,5 × 3 m.
Los límites por pieza son 3–64 bloques de ancho, 2–32 de alto y 3–64 de largo.

**Construir con esta pieza** la deja en el martillo y cierra el menú. El fantasma muestra la
geometría completa; B vuelve a las medidas. Los giros del teclado numérico funcionan en XYZ.
Al apuntar a la cara de un extremo abierto del mismo ancho, se alinean el suelo y los dos costados
(también al girar el casco alrededor de Y). Para probar: colocar un tramo, añadir una proa por
su extremo +Z y una popa por -Z, y convertir la construcción en dinámica con J.

El coste es la suma de los bloques de madera que se colocan, no el volumen de la caja exterior.
Se valida y paga el módulo entero al confirmar: sin material suficiente o con una celda ocupada,
no se coloca una parte. Se comprueban también las otras grids y los otros tamaños de celda.
La simetría refleja la pieza completa y cuenta solo una vez las celdas compartidas.
Las piezas ya colocadas admiten edición, daño, reparación, desmontaje y blueprints como cualquier
construcción de bloques. Un casco de proa + tramo + popa forma una bodega continua bajo la borda;
romper un costado abre una vía de agua para el análisis de inundación existente.
La máscara que oculta el mar dentro de la bodega usa la geometría de cada celda curva
(`ShipInteriorAnalyzer`, en sub-vóxeles de ¼ de celda): llega hasta la cara interior del casco aunque
el pantoque cruce varias celdas parciales, y no tapa las que tienen mar dentro.

**Completar el casco con cubos normales.** Los cubos del martillo pueden coincidir parcialmente
con el casco naval para rellenar un suelo o continuar una cubierta. Se apunta al hueco real junto
a la superficie curva: si aún queda volumen libre y alcanza el material, el fantasma es verde.
Funciona también entre tamaños de celda distintos, con simetría y con barcos dinámicos.
Se sigue rechazando una celda completamente maciza o el solapamiento con otro bloque normal.

La unión conserva el casco y recorta de la pieza añadida el sólido ya ocupado (`BlockBoolean`),
para contar una sola vez la masa y el empuje. `NavalCubeMerge` guarda el relleno en una grid alineada
del mismo grupo y, en un barco dinámico, del mismo cuerpo físico. El cubo gasta su material normal
y se desmonta por separado: devuelve ese material sin quitar la pieza curva original. El recorte,
su material y su volumen se conservan en partidas y blueprints. El fantasma muestra el cubo
completo, cuya unión con el casco es el volumen resultante de la construcción.
Los cubos macizos se dibujan dentro de su celda, independientemente del giro guardado: sus
caras coinciden con la colisión y con los vecinos que las ocultan. Esto evita agujeros entre
cubos normales y rellenos al construir un suelo con el bloque girado.

`NavalPiece` y `NavalHullMesh` generan el diccionario de bloques y las caras curvas que comparten
el editor, el fantasma y la colocación. `NavalBuildPanel` aporta la ficha del menú; `BuildingSystem`
coloca todo dentro de una edición masiva de la grid para reconstruir sus chunks una sola vez.

La madera naval es una tablazón (`naval_planks.gdshader`) sobre el escaneo *Wood Floor Deck* de
[Poly Haven](https://polyhaven.com) (CC0, en `textures/build_materials/ship_planks/`): color, normales,
rugosidad y altura. Cada tabla coge una fila de la foto al azar con su propio desplazamiento, y las
testas se escalonan entre tracas. Las juntas tienen hondura por parallax sobre el mapa de altura.
Las tracas van horizontales en los costados y a lo largo de la eslora en fondo y borda. Salen de la
posición en la grid, así que siguen de una faceta curva a otra y de una pieza a la siguiente, aunque
una esté girada 180°: el eje de eslora llega al shader por UV2 sin sentido.

Hay tres tonos de la misma madera: por fuera, curtida y mate; en la bodega, más clara y limpia; en la
barandilla, un solo madero untado y apenas satinado, con empalmes, que cubre la regala y una franja de
30 cm bajo ella por dentro y por fuera. `NavalHullMesh.surface_custom` lo decide por celda al
construir el chunk y lo pasa en CUSTOM0. Una cara da a la bodega si, bajando desde el aire de
delante, aparece el fondo del casco. La regala es la cima de una pared con el aire de fuera a un lado
y el de la bodega al otro.

Vista de prueba sin cargar el planeta (B edita las medidas y reconstruye la muestra):

```sh
godot --path . res://tests/building/naval_pieces_preview.tscn
# Capturas de casco, interior y menú en build/building/naval/:
godot --path . res://tests/building/naval_pieces_preview.tscn -- --capture --background
godot --headless --path . res://tests/building/test_naval_pieces.tscn
godot --headless --path . res://tests/building/test_naval_cube_merge.tscn
# Detalle del cubo verde solapando el suelo curvo (fusion.png y fusion_interior.png):
godot --path . res://tests/building/naval_pieces_preview.tscn -- --capture --background --merge-preview
# Suelo completo con cubos girados y rellenos curvos (suelo.png y suelo_interior.png):
godot --path . res://tests/building/naval_pieces_preview.tscn -- --capture --background --floor-preview
```

La prueba cubre dimensiones, grosor, giros, menú, coste completo, obstáculos de otros tamaños,
simetría, encaje, colisión del fondo, masa dinámica, apertura de la bodega y blueprints vía JSON.

## Colocables

Un colocable de la barra (la antorcha de pared) se sigue poniendo sin martillo. Con él elegido, el clic
izquierdo lo pone en la cara apuntada y el derecho apaga y enciende el modo construir. Con un colocable
siempre se pone (`BuildingSystem.set_action_mode`); para quitar uno puesto hace falta el martillo en
modo quitar.

La **escala de cuerda** (`rope_ladder_01`) solo va en las caras de los lados. No se inclina como la
antorcha: cuelga derecha del canto de arriba de la cara hasta lo primero que toca debajo, o hasta un
poco por debajo del mar (`BuildingSystem._measure_ladder`, `RopeLadder.measure_length`), y el fantasma
enseña ese largo. No choca con nada. Ver [Escalada](climbing.md#escalas-de-cuerda).

### Puertas y trampillas

La **puerta de madera** (`wooden_door`) cierra un hueco en un muro, de pie; la **trampilla de madera**
(`wooden_trapdoor`) cierra el hueco en su plano: en un techo o un suelo es una trampilla, y en un muro,
una contraventana. Se construyen a medida con el martillo, como la vela: no se fabrican ni van en la
barra.

**El menú** (**B → Puertas**, `DoorBuildPanel`): las pestañas Puerta de madera y Trampilla de madera,
el ancho y el alto (en la trampilla, el largo a lo largo de las bisagras) en bloques, de 1 a 4 de ancho
y de 1 a 6 de alto, una vista que se gira arrastrando y se acerca con la rueda, lo que mide en metros y
lo que cuesta al tamaño de celda elegido arriba, con lo que se lleva. Salen de 1 × 3 la puerta y de 1 ×
1 la trampilla (`DoorTrait.cells`), y cada pestaña recuerda sus medidas. **Construir esta puerta** la
deja en el martillo (`BuildingSystem.pick_door`) y cierra el menú; B vuelve a él.

**Las medidas** (`DoorDesign`) son en bloques de la construcción en la que se pone, así que encaja en
el hueco sea cual sea el tamaño de sus bloques: una de 1 × 3 mide 1 × 3 m en bloques de 1 m y 0,5 × 1,5
en bloques de 0,5 m. **Cuesta** según lo que mide en metros: 2 maderas por m² y una piel para las
bisagras por cada 3 m² (como poco, 1 y 1). Una de 1 × 3 en bloques de 1 m, 6 maderas y 1 piel. Se paga
al ponerla, con lo de la construcción apuntada, y quitarla con el martillo lo devuelve entero. Mientras
se apunta, debajo del fantasma salen sus medidas y lo que costará ahí. Con ella en el martillo, H pasa a
quitar como con la vela.

**Dónde va** (`WoodenDoor.fit`). Se apunta a un bloque del borde del hueco, y la hoja cierra el hueco de
delante de esa cara:

- **El plano:** de frente al eje por el que se atraviesa el hueco (libre a los dos lados). Si no está
  claro (un hueco en una esquina, una pieza suelta), el que más de cara se mira. La puerta va siempre
  de pie.
- **La cara:** la hoja queda a ras de la cara del hueco del lado desde el que se pone (por fuera del
  muro, si se pone desde fuera), con la cara de las tablas hacia ese lado y los travesaños dentro del
  hueco. **Girar en Y** (el 8 del teclado numérico) la pasa a la otra cara, como si se pusiera desde
  el otro lado, con las bisagras en el mismo sitio (`BuildingSystem.door_flipped`). Al elegir otra
  puerta en el menú se vuelve a la cara de quien la pone, y de pie.
- **Tumbada:** para el agujero de un techo o un suelo. Una trampilla apuntada por abajo al techo, o
  por arriba al suelo, junto al borde de un agujero se mete en él tumbada
  (`WoodenDoor._hole_beside`): el agujero es la celda vacía de al lado por el borde más cercano a lo
  apuntado, sin nada encima ni debajo y con forjado por otro lado más (así no cuenta el aire de fuera
  del borde de un tejado). Apuntando al alféizar o al dintel de una ventana sigue siendo una
  contraventana. Apuntando al canto del agujero, por dentro, también va tumbada. **El 4 del teclado
  numérico** la tumba a la fuerza, también a la puerta (`BuildingSystem.door_lying`); tumbada, lejos de
  un agujero no va. Tumbada queda a ras de arriba, con las tablas hacia arriba, para pisarla; el 8 la
  pasa a ras de abajo. Una trampilla alargada crece a lo largo de las bisagras hacia donde quepa.
- **Las bisagras:** en el bloque apuntado. Apuntando a una jamba van en ella. En una puerta apuntando al
  suelo del hueco o al dintel, en el lado de la celda que se apunta; si así no cabe (una puerta ancha
  apuntada por el lado de la celda que no es), en el otro. En una ventana, apuntando al dintel queda
  colgada de él, y al alféizar, abatible hacia abajo.
- **Girada:** una trampilla que no cabe con sus medidas se prueba con el ancho y el largo cambiados,
  para que una de 2 × 1 cierre también un hueco de 1 × 2.
- **La altura:** apuntando a una jamba, la puerta baja por el hueco mientras siga la jamba, hasta el
  suelo, o hasta el pie del muro si está sobre el terreno. Apuntando al dintel, cuelga de él.
- **Cuándo cabe:** sus celdas tienen que estar vacías y sin otra hoja. El fantasma la enseña a su
  medida, con las bisagras en su sitio, y en rojo si no cabe.

Es un colocable: va anclada al bloque apuntado, la quita el martillo en modo quitar (devolviendo sus
materiales) y conservan sus medidas el guardado, los blueprints y la conversión en dinámica.

**Abrir y cerrar.** E apuntándola a menos de 3 m del pecho (`PlayerController._toggle_aimed_door`) la
abre hacia el lado contrario de quien la empuja, así que no le da, y la vuelve a cerrar. Va antes que
agarrarse a una pared, para que E junto a una puerta cerrada no la trepe, y vale también trepando (una
trampilla del techo desde la escala de cuerda, una contraventana desde la pared). Gira 90° en 0,45 s por el
canto de las bisagras, por la cara de las tablas del lado al que se abre. Hacia la cara a ras de la
que está sale entera del muro; hacia el otro lado gira por dentro del hueco pegada a la jamba. De las
dos maneras deja libre 0,95 del ancho (el jugador mide 0,9). El collider gira con ella (`GridBase.pose_prop`, que
mueve el ancla del colocable sin cambiar dónde está puesto), así que abierta choca y se apunta donde se
ve. Una trampilla en un techo se abre hacia arriba desde abajo y hacia abajo desde arriba. Si está
abierta o cerrada va en el estado del colocable (`GridBase.set_prop_state`), que no cuenta como tocar la
construcción: una casa de un poblado no pasa por ello a ser de la partida. Suenan `door_open` y
`door_close` (`data/audio/events/`): las dos mitades de `audio/effects/door_open_close.mp3`, de
Pixabay, partidas por el silencio del medio en `door_open.wav` y `door_close.wav`, en mono para que
suenen en su sitio (`tools/audio/build_door_sound.py`, créditos en `docs/door_audio_credits.md`).

**La malla** (`DoorMesh`): tablas verticales con la foto del casco de los barcos, travesaños con
riostras en Z por detrás, tiras de cuero crudo de bisagra y un asidero en cada cara. Es la de una celda
de 1 m y se escala a la de la grid: lleva cinco tablas por bloque de ancho, un travesaño cada metro y
pico de alto y las tiras más largas cuanto más ancha es. La comparten la hoja puesta, el fantasma, la
vista del menú y los iconos:

```sh
godot --path . --script res://tools/items/bake_doors.gd -- --background
godot --headless --path . res://tests/building/test_doors.tscn
```

## Iconos de los bloques

`BlockIconGenerator` los renderiza en partida, uno por bloque y material, con la luz de estudio de
los iconos de los objetos (`IconStudio`):

- **Vista:** isométrica ortográfica con MSAA, menos exposición y menos relleno, para que la piedra no
  se queme y se distingan las tres caras.
- **Escala:** la de la celda entera, así que todos salen a la misma: una rampa ocupa media celda y un
  panel es una lámina. La malla va centrada.
- **Giro:** cada bloque sale girado por `BlockData.icon_yaw`, que pone de cara lo que lo distingue:
  la pendiente de la rampa (135°), las caras de la esquina (225°), el corte de la esquina invertida en
  la silueta (315°) y el panel casi de frente (160°).

## Martillo: malla e icono

La malla sale de `WeaponMeshes.stone_hammer()`. Lleva el mismo astil, ataduras y materiales que el
hacha y el pico, y la cabeza es un canto escuadrado con la cara de golpe hacia delante.
`tools/combat/bake_weapons.gd` hornea la malla, la escena y el icono:

```sh
# Malla y escena, sin ventana:
godot --headless --path . --script res://tools/combat/bake_weapons.gd -- --only=stone_hammer_01 --meshes-only
# Con el icono (abre una ventana; --background la deja fuera de la pantalla):
godot --path . --script res://tools/combat/bake_weapons.gd -- --only=stone_hammer_01 --background
godot --headless --path . --import
```

## Comprobaciones

```sh
godot --headless --path . res://tests/ui/test_build_hammer.tscn
godot --headless --path . res://tests/ui/test_blueprints.tscn
godot --headless --path . --script res://tests/combat/test_stone_tool_meshes.gd
# Capturas sin partida (abre una ventana): iconos, menús, rueda y panel de colocar
godot --path . res://tests/ui/build_ui_preview.tscn -- --capture --background
```

**`test_build_hammer`** prueba:

- el objeto y su receta;
- los seis huecos de la rueda y cómo se elige;
- que con un colocable no se puede pasar a quitar;
- el menú de bloques: elegir, recientes y tamaño de celda.

**`test_blueprints`** prueba:

- lo que cuesta un blueprint;
- pagar, y devolver con el inventario lleno;
- la ficha y los ficheros: guardar, recuperar la ficha, renombrar y borrar;
- desmontar y construir gratis;
- el choque con otra construcción;
- el menú de blueprints: búsqueda, coste, colocar (también sin materiales), sustituir y desmontar.

La vista previa deja sus capturas en `build/building/preview/`.

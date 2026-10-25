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
| 4, 8 y 9 del teclado numérico | Giran el bloque en X, Y y Z (los que giran) |
| V / N | Simetría sobre el bloque apuntado / cambia su plano (también desde la rueda) |
| J | Convierte en dinámica la grid apuntada |

## La rueda

`BuildRadialMenu` (`scripts/ui/menu/build_radial_menu.gd`) tiene cinco huecos. En el sentido de las
agujas del reloj desde arriba: a la derecha lo de cada golpe y a la izquierda los menús.

1. **Añadir bloque**: el clic izquierdo pone.
2. **Quitar bloque**: el clic izquierdo quita bloques y colocables.
3. **Simetría**: sin ella, la pone en el bloque apuntado, en el eje X. Puesta, pasa al eje
   siguiente, y después del Z la quita. Su hueco dice el eje («Simetría Y») y, bajo el ratón, el
   centro dice qué hará. Si no se apunta a un bloque, avisa.
4. **Blueprints**: abre el menú de blueprints (ver abajo).
5. **Elegir bloque**: abre el menú de bloques. Su hueco enseña el icono del bloque elegido.

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
  la sesión).
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
Un colocable gasta una unidad de su objeto. Quitar un bloque devuelve la parte de su coste que le queda
de vida, redondeando hacia arriba. Lo que no cabe en el inventario cae al suelo delante del jugador;
antes se perdía.

`BuildCost` (`scripts/building/build_cost.gd`) hace las cuentas para todo lo que no es un bloque suelto:

- **Un blueprint:** lo que gasta al colocarlo.
- **Una construcción en pie:** lo que vale y lo que devuelve al desmontarla.
- **Frente al inventario:** lo que falta, pagar y devolver.

El precio sale siempre de los costes de ahora. Una ficha de blueprint solo guarda el recuento de
bloques por material y tamaño de celda, y de colocables por objeto.

**Construir gratis** (consola: `freebuild [on|off]`, `BuildingSystem.free_build`): bloques, colocables
y blueprints no gastan nada. Quitar o desmontar tampoco devuelve nada, para que no sea una fuente de
material infinita. Colocar un blueprint deja de tener límite de distancia.

## Blueprints

### El menú

`GridManipulatorMenu`, en Saga, con dos pestañas.

**Construcción.** Es la que se apuntaba al abrir el menú, que se queda fijada. Tiene:

- la miniatura;
- los datos: medidas, bloques, colocables, volumen, celdas y, si es dinámica, masa y compartimentos;
- lo que vale en materiales, que es lo que devolvería al desmontarla;
- **Guardar como blueprint.** Si el nombre ya existe avisa, y hay que pulsar «Sustituir» otra vez;
- **Convertir en dinámica**;
- **Desmontar.** Pide pulsar dos veces. Quita todo como el martillo bloque a bloque, devuelve los
  materiales (`BuildingSystem.dismantle_group`), cierra el menú y avisa de lo recuperado. Antes,
  «Eliminar» lo borraba sin devolver nada.

**Biblioteca.** Los blueprints guardados, en fichas con miniatura, medidas, bloques y si llevas los
materiales. Se pueden buscar por nombre y ordenar por nombre o por fecha. La ficha del elegido tiene:

- miniatura y datos;
- los bloques de un tipo que ya no existe, que no se pondrán;
- los materiales, cada uno con «lo que llevas / lo que pide» en verde o en rojo;
- **Colocar**, solo si alcanza (salvo construyendo gratis), y «Colocar como estática» en los
  dinámicos;
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
que llevas y lo que pide, si se puede y los controles.

No se puede colocar, y el fantasma se pone rojo, si:

- **faltan materiales;**
- **choca con otra construcción:** algún bloque cae en una celda ocupada. Se mira cada 0,15 s con 600
  bloques como mucho, y al confirmar con todos;
- **está demasiado lejos:** el centro a más de 24 m del jugador, más media diagonal del blueprint.

Al confirmar se paga y se construye. Si no se puede, sigue colocando y la barra dice por qué.

Al reconstruir, los materiales de los bloques salen del `BuildMaterial` de ahora por su id
(`GridBlueprint._restore_materials`). Los de piedra y madera son subrecursos de su `.tres`, y su ruta
guardada no se podía cargar suelta.

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
el editor, el fantasma y la colocación. La madera naval utiliza su propio acabado de madera lisa.
`NavalBuildPanel` aporta la ficha del menú; `BuildingSystem` coloca todo dentro de una edición masiva
de la grid para reconstruir sus chunks una sola vez.

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
- los cinco huecos de la rueda y cómo se elige;
- que con un colocable no se puede pasar a quitar;
- el menú de bloques: elegir, recientes y tamaño de celda.

**`test_blueprints`** prueba:

- lo que cuesta un blueprint;
- pagar, y devolver con el inventario lleno;
- la ficha y los ficheros: guardar, recuperar la ficha, renombrar y borrar;
- desmontar y construir gratis;
- el choque con otra construcción;
- el menú de blueprints: búsqueda, coste, colocar, sustituir y desmontar.

La vista previa deja sus capturas en `build/building/preview/`.

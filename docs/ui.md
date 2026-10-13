# Interfaz: Saga

Toda la interfaz comparte un estilo, **Saga**: placas de hierro oscuro
translúcido, superficies de cuero, filetes y remaches de bronce y texto color
hueso. Las esquinas van biseladas, no redondeadas. Los títulos usan Cinzel y el
texto Alegreya Sans, las dos en `fonts/` con su licencia OFL
(`OFL-Cinzel.txt`, `OFL-AlegreyaSans.txt`).

## El tema

`GameTheme.build(ui_scale)` (`scripts/ui/theme/game_theme.gd`) devuelve el
`Theme` de una pantalla: se asigna a su `Control` raíz y lo heredan todos los
hijos, también las ayudas emergentes. Las medidas están pensadas para 1440 px
de alto y se multiplican por `GameTheme.scale_for(viewport)`, porque el
proyecto no estira la UI. Las pantallas que viven toda la partida (barra
rápida, equipo) rehacen el tema cuando cambia el tamaño de la ventana.

- **Paleta:** `IRON` (paneles), `IRON_DEEP` (campos y huecos vacíos), `LEATHER`
  (botones y huecos con objeto), `BRONZE` (acento), `BONE` (texto), `MUTED`, y
  los de significado: `BLOOD` (vida, peor), `MOSS` (aguante, mejor) y `FROST`
  (lo que lleva la otra mano).
- **Formas:** `GameTheme.box()` es un `StyleBoxFlat` con `corner_detail = 1`,
  que corta las esquinas en bisel. Las ventanas usan `SagaFrame`, un `StyleBox`
  propio con filete interior y un rombo en cada bisel, y los separadores
  `SagaRule`, un filete que se desvanece con un rombo en el centro.
- **Variaciones:** `TitleLabel`, `HeaderLabel` (cabecera de ventana),
  `SectionLabel`, `HintLabel`, `ValueLabel`, `StatLabel`/`StatValue`,
  `BetterLabel`/`WorseLabel`; `AccentButton` (el botón principal), `TabButton`
  (pestañas subrayadas), `RailButton` (lista de categorías), `Tile` (ficha con
  miniatura), `CloseButton`; `WindowPanel`, `Card`, `Inset` y `HotbarPanel`;
  `HealthBar` y `StaminaBar`. Ninguna puede llamarse como una clase de Godot
  («Window» no vale).
- **Campos de cantidad:** el `SpinBox` usa la placa de `LineEdit` y lleva dos
  flechas de bronce a la derecha, una encima de otra (`GameTheme.chevron_icon`).
- **Huecos de objeto:** `ItemSlotView` es el hueco común de inventario, equipo,
  barra rápida y botín (`InventorySlot`, `EquipmentSlot` y `HotbarSlot` lo
  extienden). Cada estado es una variación (`SlotEmpty`, `Slot`, `SlotHover`,
  `SlotSelected`, `SlotEquipped`, `SlotHeld`) y el lado sale de las constantes
  del tipo `ItemSlot` (`GameTheme.SLOT_SIDES`; la ventana de fabricar tiene los
  suyos: `recipe`, `ingredient` y `preview`). Vacío enseña en bronce tenue la
  silueta de lo que va en él (`shaders/ui/tint_alpha.gdshader`).

## Inventario y pantalla de personaje

`InventoryUI` tiene tres vistas. Con la **I** sale el inventario solo, a la
izquierda, sin fondo, para ver el mundo donde cae lo que se tira (con el botín
al lado mientras se saquea). Con la **C** sale la pantalla de personaje entera.
Con el **Tab** (o «Fabricar», en la cabecera del inventario) sale la de fabricar
(ver abajo). La tecla de la vista abierta la cierra, y las otras cambian a la
suya. El
inventario tiene filtros por categoría que dejan en segundo plano lo que no es
del filtro, sin moverlo de su hueco.

En la pantalla de personaje, en el centro, está el muñeco de `CharacterWindow`: el propio personaje en 3D
(`CharacterPreview` horneado y con fondo transparente), con la ropa de sus
huecos ajustada a su cuerpo como en el jugador y los huecos a los lados. A la
derecha van los atributos (vida, aguante, armadura y las dos manos) o, mientras
se saquea, el botín, con **Cogerlo todo**. Detrás queda el mundo desenfocado y
oscurecido (`shaders/ui/backdrop.gdshader`), y la barra rápida sube por encima
del fondo mientras la pantalla está abierta, para asignarle cosas.

Al pasar el ratón por un hueco sale la ficha del objeto (`ItemCard`): su tipo,
sus cifras comparadas con lo que se lleva puesto en el mismo sitio (▲ mejor,
▼ peor) y qué hacen ahí los clics. Sale fuera de la columna del hueco, para no
tapar a sus vecinos. Los objetos se siguen moviendo a clics, como antes.

`CharacterWindow` conserva su API (`equipment_slots`, `equip_item()`,
`unequip_item()`, `equipment_changed`), así que el jugador y las partidas
guardadas no cambian. El muñeco no es una ventana: `InventoryUI` lo coloca al
montarse (`take_doll()`) y llama a `refresh()` al abrir la vista de personaje
(el inventario solo no lo prepara). `refresh()` le pone el aspecto del personaje
(solo si ha cambiado) y le viste la ropa de los huecos.

`tests/ui/equipment_screen_preview.tscn` abre la pantalla sola, con el
inventario lleno, ropa puesta y un banco de trabajo al lado, para probarla sin
arrancar la partida (I, C y Tab cambian de vista).

## Fabricar

La vista de fabricar (`CraftingPanel`) va a la derecha del inventario, en el
sitio del muñeco y la columna de atributos, con el mundo oscurecido detrás.
Tiene tres partes:

- **Pestañas**, a la izquierda: «Todo» y las categorías de `ItemTaxonomy` que
  tienen alguna receta.
- **Recetas**, en medio:
  - Van agrupadas por era (de momento, la Edad de piedra) y, dentro, por dónde se
    hacen: «A mano» y cada estación de trabajo.
  - Junto a cada estación pone si hay una **Cerca** o **No está cerca** y, si no
    lo está, dónde se fabrica la estación misma.
  - Con una cerca, sale el botón **Desmontar**, que la devuelve al inventario.
  - Lo que ahora no se puede hacer (falta material o la estación) sale apagado.
  - **Solo lo que puedo hacer**, en la cabecera, esconde el resto. La cabecera
    también dice qué estaciones hay cerca.
- **La receta elegida**, a la derecha:
  - La ficha: el objeto en grande, su tipo y sus cifras.
  - **Dónde** se hace.
  - **Materiales:** lo que pide para las veces elegidas, con lo que tienes de
    cada cosa, en verde si alcanza y en rojo si no.
  - **Cantidad:** un campo con flechas arriba y abajo (también vale la rueda o
    escribir, de 1 a 99) y **Máx**, que pone todas las que alcanzan.
  - **Fabricar ×N**, y debajo por qué no se puede, si no se puede.

Las estaciones cercanas se vuelven a mirar cada 0,4 s, así que al acercarse o
alejarse la ventana cambia sola. E junto a una estación abre esta vista en sus
recetas (`InventoryUI.open_station`). Al abrir el botín o una hoguera, se vuelve
al inventario solo.

## Inventario: ordenar y hoguera

- **Filtros:** «Todo» y las categorías de `ItemTaxonomy` (Armas, Herramientas,
  Ropa, Comida, Materiales y Construcción). Si no caben en una línea, saltan a
  la siguiente.
- **Ordenar:** junta lo que se apila y lo ordena por categoría, grupo y nombre
  (`ItemTaxonomy.sort_inventory`).
- **Hoguera:** E junto a una hoguera la abre en esa misma columna
  (`open_campfire`).
  - **Combustible:** un hueco, con una barra de lo que dura la pieza que quema y
    el tiempo que queda con todo.
  - **Asador:** ocho huecos con una barrita de lo que llevan asado.
  - **Botones:** encender o apagar, recoger lo asado y desmontar.
  - **Clics:** con algo en el cursor, el clic lo deja en el hueco (el derecho,
    de uno en uno); sin nada, el clic pasa lo del hueco al inventario.
- **Prioridad de la columna derecha:** el botín, luego la hoguera y, si no hay
  nada de eso, los atributos (`_update_side`).
- **La ficha** enseña también lo que dan los rasgos del objeto (hambre, arde,
  abrigo...).
- **Avisos:** los cortos («Bebes agua dulce», «Necesitas un cuchillo en la
  mano...») salen sobre la consola de la barra y se van solos (`Hotbar.notify`).

## Barra rápida, vida, aguante y necesidades

La barra rápida va encajada en una consola a lo Diablo (`VitalsPlate`): la misma
placa de hierro de las ventanas, con su filete de bronce por fuera y otro más
tenue por dentro. La sostiene desde el borde de abajo y se levanta a cada lado
en el engaste de una orbe. Cada engaste lleva una banda de runas del fuþark
joven, como las de las piedras rúnicas: «líf auk blóð» (vida y sangre) en la
vida y «þrek auk andi» (aguante y aliento) en el aguante. De cada engaste salen
las raíces del fresno, que se atan en un nudo de tres lóbulos (el trébol de las
piedras rúnicas) y se agarran al borde de la pantalla, y encima lleva una copa
de hojas de bronce. Una sierpe a lo Urnes, con las fauces abiertas, muerde cada
engaste donde se junta con la barra y recorre el borde de arriba de esta a
jorobas, hundiéndose en la placa entre una y otra: su cuerpo es parte de la
placa, con el mismo hierro y el mismo filete. La cola sale hecha zarcillo con
hojas y acaba en voluta. En el centro se levanta el engaste de la media orbe
de la cordura, con media banda de runas («hugr auk minni», pensamiento y
memoria), asentado en una voluta doble y coronado por un remache y tres hojas.
En cada voluta está posado un cuervo pequeño, Huginn y Muninn, con el ala
alzada y una espiral en su arranque, mirando a la cordura. Por debajo de la
barra corre una trenza de hilo de bronce.

Alrededor de cada engaste, por fuera, van tallados dos medidores: un medallón
con su icono del que sale un canal en el sentido de las agujas del reloj, que se
llena desde el icono: hambre (espiga) y sed (gota) en el de la vida, temperatura
(termómetro) y descanso (luna) en el del aguante. Los llena `NeedGauge` en
tiempo de juego. El oxígeno no tiene canal: bajo el agua, `BreathRing` enciende
las runas del aguante con una máscara horneada aparte,
`textures/ui/hotbar_breath_runes.png`. Qué mide cada uno y cómo se mueve está en
[survival.md](survival.md).

Se dibuja como el resto de Saga: rellenos lisos y filetes finos, sin luces ni
relieve, con la paleta de `GameTheme`. Es una imagen horneada,
`textures/ui/hotbar_console.png`, a dos píxeles por cada uno de la UI a 1440 px
para que a 4K siga nítida (con mipmaps para reducirla). La pinta
`tools/ui/bake_hotbar_console.py` con campos de distancia, así que los bordes
salen suavizados.

```sh
build/fauna_tools/bin/python -I tools/ui/bake_hotbar_console.py
godot --headless --editor --quit --path .   # importa la textura
```

Está pintada para las medidas de la barra (diez huecos de 92 px, orbes de radio
75 a 38 px del panel, media orbe de radio 48, canales de radio 106,5): si
cambian, hay que cambiarlas en el script y en `Hotbar` (`PANEL_SIZE`, `ORB_*`,
`SANITY_RADIUS`, `GAUGE_*`, `MEDALLION_*` y `GAUGES`) y volver a hornear. El script imprime dónde empieza el panel en
la imagen, que tiene que coincidir con `VitalsPlate.BAR_ORIGIN`.

Las orbes (`VitalOrb`) son esferas de cristal con un aro de bronce y un líquido
(`shaders/ui/vital_orb.gdshader`) que llega hasta lo que queda: la vida a la
izquierda y el aguante a la derecha. La barra las coloca a partir de su panel
(`Hotbar._layout_vitals()`), y `CombatHUD` las llena cada fotograma:

- **Vida:** al recibir un golpe, el tramo perdido queda encima en ámbar y se
  vacía con retraso. Con poca vida o desangrándose, el líquido late con el
  corazón.
- **Aguante:** agotado, el líquido se apaga; si falta para un golpe, el aro
  destella.
- Cuando el valor cambia, la cifra se destaca en el centro de la orbe. Si la
  reserva está incompleta permanece visible, con fuente seminegrita y un
  mínimo de 14 px; a tope se desvanece.
- La silueta del cuerpo herido va a la izquierda de la consola y los estados en
  curso (pierna rota...) a la izquierda de la silueta.
- **Cordura:** la media orbe violeta; con poca, el aro destella.
- En vuelo libre o sin cuerpo no salen ni las orbes ni la consola
  (`Hotbar.set_vitals_shown()`).

**Tamaño:** la barra entera (consola, orbes, medidores, huecos, nombre y avisos)
va a la escala de la ventana por un factor que el jugador elige en Opciones >
Juego, de 50 a 140 %, con un 75 % por defecto (`game/hotbar_scale`,
`SettingsManager.hotbar_scale()`). `Hotbar.get_ui_scale()` lo aplica y la
recoloca al cambiarlo; en ventanas estrechas no pasa de lo que cabe a lo ancho.
En partida la barra se oculta con el menú de pausa, así que el tamaño nuevo se
ve al volver al juego.

Como son parte de la barra, suben con ella por encima del fondo de la pantalla
de personaje. El efecto de desangrado va en una capa por debajo de la barra
(9), para que la vida no pierda el color justo cuando más importa. Clicar en la
consola con algo en el cursor no lo tira.

## Menú principal

`scenes/menu/main_menu.tscn`, que en partida hace de menú de pausa: el nombre
del juego en Cinzel (`MenuTitle`) y una columna de botones de solo texto
(`SagaMenuButton`, para no colisionar con la clase `MenuButton` de Godot) a la
izquierda, sobre una sombra que deja ver el mundo a la
derecha. Los botones conservan sus nombres (`btnStartGame`, `btnSaveGame`...),
que el jugador busca con `find_child`. Cargar dice «Continuar partida» en el
menú y «Cargar partida» en la pausa.

## Pantallas nuevas

1. Un `CanvasLayer` con un `Control` raíz a pantalla completa y
   `root.theme = GameTheme.build(GameTheme.scale_for(get_viewport()))`.
2. Ventanas como `PanelContainer` con `theme_type_variation = "WindowPanel"`:
   cabecera con `HeaderLabel`, `HSeparator` debajo y el contenido.
3. Las medidas fijas, multiplicadas por la escala. Las etiquetas que parten
   líneas piden mucho alto mientras no tienen ancho: hay que colocarlas con
   anclas y márgenes, no con un `size` puesto a mano, que ya no volvería a
   encoger.

## Pendiente

- **Iconos:** mezclan tres estilos (vectores planos, renders sobre fondo negro y
  siluetas, con un yelmo de caballero entre ellas). Habría que renderizarlos
  desde los modelos con la misma luz, como ya se hace con los bloques
  (`BlockDatabase`).
- **Nombres y descripciones:** varios objetos siguen en inglés en sus `.tres`.
- **Menús de construcción y el resto del HUD** (barras de las criaturas, mira):
  aún no usan Saga.
- La armadura que muestran los atributos es la suma de la de las piezas puestas,
  pero el combate todavía no la usa (`HealthComponent.defense` no se rellena).

## Validar la barra rápida

La consola conserva la talla anterior a la consola compacta (commit
`0878e3e`). Los huecos usan `HotbarSlotFrame`: cuero con filetes de bronce,
un pie propio para las teclas y acento dorado para el arma activa, azul para
el escudo. Los iconos conservan sus dibujos y se encuadran por su zona visible
con `AtlasTexture`, compartida por textura. La antorcha usa el render con
transparencia; los iconos se reducen con mipmaps.

El nombre del objeto aparece sobre la cresta durante dos segundos al
seleccionar y luego se desvanece. Los avisos tienen prioridad. Sin orbes,
el nombre queda junto a la barra. En ventanas pequeñas, `Hotbar.get_ui_scale()`
parte de una escala mínima de 0,625 (antes del tamaño elegido en Opciones y
limitada por la anchura disponible), para que a 720p los objetos sigan siendo
reconocibles. Las teclas tienen un mínimo de 12 px y un pie con altura
suficiente para alojarlas.

El panel reajusta su tamaño y sus anclajes después de los cambios de tema y
toma la medida de la consola horneada (`Hotbar.PANEL_SIZE` por la escala): los
huecos se redondean uno a uno y a según qué escalas su mínimo se quedaría unos
píxeles corto, así que van centrados dentro y las orbes casan con sus engastes
a cualquier tamaño.

`tests/ui/hotbar_preview.tscn` abre la barra real sin cargar el planeta. Con
`-- --capture` pone la ventana en modo ventana, comprueba el tamaño real de
cada PNG y guarda exploración, selección, hover, necesidades críticas,
oxígeno y barra sola en `build/ui/hotbar/`, a 720p, 1080p y 1440p, con vuelta
a 1080p. También comprueba teclas, clics, escudo independiente, deselección
y que el panel siga centrado y coincida con las medidas de la consola.
También verifica el nombre seleccionado y que las teclas no pisen los
iconos ni salgan de sus huecos.
Los ajustes de pantalla del usuario no se guardan.

```sh
godot --path . res://tests/ui/hotbar_preview.tscn -- --capture
```

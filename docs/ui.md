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
- **Huecos de objeto:** `ItemSlotView` es el hueco común de inventario, equipo,
  barra rápida y botín (`InventorySlot`, `EquipmentSlot` y `HotbarSlot` lo
  extienden). Cada estado es una variación (`SlotEmpty`, `Slot`, `SlotHover`,
  `SlotSelected`, `SlotEquipped`, `SlotHeld`) y el lado sale de las constantes
  del tipo `ItemSlot` (`GameTheme.SLOT_SIDES`). Vacío enseña en bronce tenue la
  silueta de lo que va en él (`shaders/ui/tint_alpha.gdshader`).

## Inventario y pantalla de personaje

`InventoryUI` tiene dos vistas. Con la **I** sale el inventario solo, a la
izquierda, sin fondo, para ver el mundo donde cae lo que se tira (con el botín
al lado mientras se saquea). Con la **C** sale la pantalla de personaje entera.
La tecla de la vista abierta la cierra, y la otra cambia a la suya. El
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
inventario lleno y ropa puesta, para probarla sin arrancar la partida (I y C
cambian de vista).

## Inventario: ordenar, fabricar y hoguera

- **Filtros:** «Todo» y las categorías de `ItemTaxonomy` (Armas, Herramientas,
  Ropa, Comida, Materiales y Construcción). Si no caben en una línea, saltan a
  la siguiente.
- **Ordenar:** junta lo que se apila y lo ordena por categoría, grupo y nombre
  (`ItemTaxonomy.sort_inventory`).
- **Fabricar:** enseña las recetas en la columna de la derecha. Al lado de cada
  ingrediente va lo que tienes de él, en verde si alcanza y en rojo si no.
- **Hoguera:** E junto a una hoguera la abre en esa misma columna
  (`open_campfire`).
  - **Combustible:** un hueco, con una barra de lo que dura la pieza que quema y
    el tiempo que queda con todo.
  - **Asador:** ocho huecos con una barrita de lo que llevan asado.
  - **Botones:** encender o apagar, recoger lo asado y desmontar.
  - **Clics:** con algo en el cursor, el clic lo deja en el hueco (el derecho,
    de uno en uno); sin nada, el clic pasa lo del hueco al inventario.
- **Prioridad de la columna derecha:** el botín, luego la hoguera, luego
  fabricar y, si no hay nada de eso, los atributos (`_update_side`).
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
raíces que se agarran al borde de la pantalla, una copa de hojas de bronce
encima y una rama con hojas que se tiende sobre la barra hasta acabar en
voluta. En el centro se levanta el engaste de la media orbe de la cordura, con
media banda de runas («hugr auk minni», pensamiento y memoria, como Huginn y
Muninn), asentado en una voluta doble y coronado por un remache y tres hojas.
Por debajo de la barra corre una trenza de hilo de bronce.

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
cambian, hay que cambiarlas en el script y en `Hotbar` (`ORB_*`,
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
- Cuando el valor cambia, la cifra sale un momento en el centro de la orbe.
- La silueta del cuerpo herido va a la izquierda de la consola y los estados en
  curso (pierna rota...) a la izquierda de la silueta.
- **Cordura:** la media orbe violeta; con poca, el aro destella.
- En vuelo libre o sin cuerpo no salen ni las orbes ni la consola
  (`Hotbar.set_vitals_shown()`).

Como son parte de la barra, suben con ella por encima del fondo de la pantalla
de personaje. El efecto de desangrado va en una capa por debajo de la barra
(9), para que la vida no pierda el color justo cuando más importa. Clicar en la
consola con algo en el cursor no lo tira.

## Menú principal

`scenes/menu/main_menu.tscn`, que en partida hace de menú de pausa: el nombre
del juego en Cinzel (`MenuTitle`) y una columna de botones de solo texto
(`MenuButton`) a la izquierda, sobre una sombra que deja ver el mundo a la
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

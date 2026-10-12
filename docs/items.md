# Objetos

Cada objeto es un `ItemData` (`data/items/`, uno por `.tres`). Lo que **es** se
clasifica con una categoría y un grupo (`ItemTaxonomy`). Lo que **se puede
hacer con él** va aparte, en sus rasgos (`ItemTrait`).

## Clasificación

| Categoría | Grupos |
|---|---|
| Armas | Cuerpo a cuerpo · A distancia · Munición · Escudos |
| Herramientas | Hachas y picos · Luz · Recipientes |
| Ropa | Cabeza · Torso · Manos · Piernas · Pies |
| Comida | Cocinada · Cruda · Bebida |
| Materiales | De caza · Madera · Piedra y mineral · Otros |
| Construcción | Estaciones de trabajo · Colocables · Bloques |

- Las categorías son los filtros del inventario.
- El grupo (`ItemData.group`) da el orden al pulsar «Ordenar» y la línea de tipo
  de la ficha («Armas · Cuerpo a cuerpo · Tajo»).
- Sin grupo, `ItemTaxonomy.group_of()` le da el que le toca por cómo es (un
  arma a distancia, la ropa por su ranura...).

La categoría que se enseña sale del grupo, no de `ItemData.category`, que sigue
mandando para equipar:

- Un escudo es `ARMOR` (va en la mano secundaria) y se enseña con las armas.
- La flecha es `MATERIAL` (no se empuña) y sale como munición.
- El odre es `CONSUMABLE` (no se empuña: se usa desde la barra) y sale con las
  herramientas.
- La hoguera y el banco de trabajo son `MATERIAL` (no entran en el modo de
  construir) y salen en Construcción.

## Rasgos

Van en `ItemData.traits` y se buscan por su tipo con
`data.get_trait(EdibleTrait)`. La ficha del objeto enseña lo que dan.

| Rasgo | Qué hace | Lo llevan |
|---|---|---|
| `EdibleTrait` | Lo que da a cada necesidad, la vida que cura y la probabilidad de intoxicar | carne cruda y asada |
| `FuelTrait` | Segundos de fuego por unidad en una hoguera | rama (60 s), madera (150 s) |
| `CookableTrait` | En qué se convierte asado y en cuánto | carne cruda → asada (40 s) |
| `WaterContainerTrait` | Tragos que caben | odre (5) |
| `InsulationTrait` | Grados que abriga puesto | ropa de pieles (9 °C el juego entero), de cuero (6 °C) |
| `SkinningTrait` | En la mano, deja despellejar | seax |
| `GroundPlaceableTrait` | Se planta en el suelo: escena, vista previa, pendiente, separación y cuánto se inclina y se hunde | hoguera, banco de trabajo |
| `CraftingStationTrait` | Es una estación de trabajo: su era y desde qué distancia se usan sus recetas | banco de trabajo |

Un rasgo nuevo es una clase que hereda de `ItemTrait` en
`scripts/items/traits/`, con su `describe()` para la ficha.

## Lo de supervivencia

| Objeto | Id | Qué es |
|---|---|---|
| Seax | `seax` | Cuchillo de un filo: arma ligera (14 de daño) y despelleja |
| Carne cruda | `raw_meat` | Hambre +12 %, cordura −6 %; intoxica el 35 % de las veces; se asa |
| Carne asada | `cooked_meat` | Hambre +35 %, sed −3 %, cordura +3 %, vida +8 |
| Piel | `raw_hide` | Material de caza |
| Odre | `waterskin` | 5 tragos de agua |
| Hoguera | `campfire` | Se planta en el suelo |
| Banco de trabajo | `stone_workbench` | Estación de trabajo de la Edad de piedra: se planta en el suelo |

El jugador empieza con un seax. El resto sale con `give <id> [cantidad]`.

### Caza

Un animal muerto se despelleja con E llevando el seax (o lo que tenga
`SkinningTrait`) en la mano. Sin él, el juego avisa de que hace falta un
cuchillo.

Lo que da lo dice cada animal en su escena: `NPCController.butcher_loot` (grupo
*Caza* del inspector), un `LootTable` con líneas `LootEntry` (objeto, cantidad
para un adulto de tamaño 1 y probabilidad). Los de las especies están en
`data/fauna/loot/<especie>.tres`. `HuntingLoot` solo lo escala por el tamaño del
animal y por el cuchillo, con un ±20 %. Una especie nueva trae el suyo, y sin él
da carne y piel según el grosor de su cuerpo. Algunos ejemplos:

| Especie | Carne | Pieles |
|---|---|---|
| Ciervo | 3 | 2 |
| Jabalí | 2 | 1 |
| Oso | 5 | 3 |
| Alce | 5 | 3 |
| Mamut | 12 | 5 |

Después se saquea como cualquier botín. Los animales ya no traen madera y
piedra de relleno.

### Comer y beber

- **Comer y beber del odre:** con el objeto seleccionado en la barra, clic; en
  el inventario, doble clic sobre él. La hoguera solo se planta desde la barra,
  porque hay que ver dónde.
  - La carne cruda puede dejar el estado «Intoxicación»: anda un 10 % más
    despacio, el aguante se recupera a la mitad y quita 0,1 de vida por segundo,
    durante 1-3 minutos (`data/status/intoxication.tres`).
- **Junto al agua dulce, E:**
  - **Dónde vale:** a menos de 6 m de un río, o a pie de un lago o una charca
    (a menos de 2,5 m y no más de 2,5 m por encima del agua).
    El terreno cargado comprueba que hay agua real; el mapa aporta su tipo
    también cuando la orilla cae en una celda de tierra. Los ríos se miden
    contra sus segmentos, para que la imagen de distancias no pierda riberas.
  - **Con sed:** bebes un trago, que quita un 20 % de sed.
  - **Con la sed saciada:** llenas todos los odres.
  - **El mar:** no quita la sed, y el juego lo avisa.
- **Los odres:** el agua es del jugador (`SurvivalNeeds.water`), repartida entre
  todos los que lleva. Si tiras un odre, cabe menos.

### Fabricar

Se fabrica en la ventana de fabricar: **Tab**, o «Fabricar» en la cabecera del
inventario. Cómo es la ventana está en [ui.md](ui.md#fabricar). Lo fabricado va
al inventario y lo que no cabe, al suelo.

- **Recetas:** cada una es un `RecipeData` en `data/recipes/<era>/<dónde>/`. Dice
  qué sale (`result`), cuántos cada vez (`amount`), lo que gasta (`inputs`: id →
  cantidad), dónde se hace (`station`: vacío, a mano; o el id de una estación) y
  su era. `Recipes` las carga todas y hace las cuentas para N veces
  (`missing`, `max_times`, `craft`).
- **Eras:** `Eras.Era` (de momento solo `STONE`, la Edad de piedra). Cada era trae
  sus estaciones de trabajo y sus recetas, y la ventana las agrupa por era. Una
  era nueva es un valor más en `Eras`, con su nombre.
- **Estaciones de trabajo:** objetos con `CraftingStationTrait` que se plantan en
  el suelo como la hoguera (`Workstation`). Sus recetas solo se pueden hacer a
  menos de su alcance (3,5 m desde los pies). E junto a una abre la ventana en
  sus recetas. Se desmontan desde la ventana, con ella cerca, y se guardan con la
  partida.

| Sale | Con | Dónde |
|---|---|---|
| Hoguera | 6 piedras y 4 ramas | A mano |
| Odre | 2 pieles | A mano |
| Banco de trabajo | 6 maderas, 4 piedras y 4 ramas | A mano |
| Antorcha | 2 ramas | A mano |
| Hacha de piedra | 3 piedras, 2 ramas y 1 piel | Banco de trabajo |
| Pico de piedra | 4 piedras, 2 ramas y 1 piel | Banco de trabajo |
| Arco de caza | 3 ramas y 1 piel | Banco de trabajo |
| 4 flechas | 1 rama y 1 piedra | Banco de trabajo |
| Tirachinas | 1 rama y 1 piel | Banco de trabajo |
| Espada de sílex | 4 maderas, 4 piedras y 1 piel | Banco de trabajo |
| Lanza de sílex | 3 ramas y 2 piedras | Banco de trabajo |
| Escudo de madera | 3 maderas y 1 rama | Banco de trabajo |
| Ropa de pieles | capucha 2, jubón 4, manoplas 1, calzas 3 y botas 2 pieles | Banco de trabajo |

Una receta nueva es un `.tres` más en su carpeta, con el script
`scripts/items/recipe_data.gd`. Una estación nueva necesita:

- su objeto, con `GroundPlaceableTrait` y `CraftingStationTrait`;
- su escena, con `Workstation` en la raíz (`item_id`, `visual` y
  `collision_size`);
- recetas que la pidan en `station`.

### Banco de trabajo

- **Cómo se ve** (`StoneWorkbenchVisual`):
  - un banco de madera tosca de 1,22 m de largo y 0,76 de alto, que es el modelo
    *Wooden Stool 02* agrandado;
  - encima, lo de tallar: una piedra de yunque con una lasca, un percutor, más
    lascas, un cuenco tallado y un palo para un mango;
  - al pie, unas piedras.

  Las piezas son de [Poly Haven](https://polyhaven.com), CC0: *Wooden Stool 02*
  y *Wooden Bowl 02* (Kuutti Siitonen), *Stone 01* (Dario Barresi y Rico
  Cilliers) y *Namaqualand Stones 01* (Greg Zaal y Jenelle van Heerden), en
  `models/props/workbench/`, y una rama de *Dry Branches Medium 01*, la de la
  hoguera.
- **Plantarlo:** como la hoguera, con la vista previa, aunque va casi derecho:
  - se inclina hasta 10° con la pendiente;
  - se apoya en lo más bajo del suelo (hasta 25 cm), y las patas del lado alto
    se clavan;
  - sale rojo con más de 24° de pendiente o más de 0,3 m de desnivel debajo;
  - pide 2 m hasta lo plantado más cerca.
- El icono sale de una malla sencilla, `SurvivalMeshes.workbench()`.

### Hoguera

- **Cómo se ve** (`CampfireVisual`):
  - un corro de piedras, el modelo *Stone Fire Pit* de Sebastian Platen, a 1,1 m;
  - cuatro palos en tienda y un tronco atravesado, de *Dry Branches Medium 01*
    de Rico Cilliers;
  - una calcomanía de ceniza que tizna el suelo, por irregular que sea, y que
    encendida enseña las brasas.

  Los dos modelos son de [Poly Haven](https://polyhaven.com), CC0, y están en
  `models/props/campfire/`. La ceniza la hornea `tools/items/bake_campfire_ash.py`.
- **Plantarla:** con la hoguera seleccionada en la barra se ve, translúcida,
  dónde iría. Lo mismo vale para todo lo que se planta (`GroundPlaceableTrait`).
  - **Cómo se asienta** (`GroundFit`): sondea el suelo en el centro y en un corro
    de 0,55 m, ajusta un plano y la inclina con la pendiente, hasta 20°. El
    fuego sigue recto.
  - **Verde o roja:** sale verde si hay menos de 28° de pendiente y menos de
    0,3 m de desnivel debajo, está a menos de 4,5 m, no hay nada plantado a
    menos de 1,5 m y no estás en el agua; si no, sale roja.
  - El clic la planta.
- **Abrirla:** E junto a ella la abre en la columna de la derecha. Se cierra
  sola al alejarse.
  - **Combustible:** el hueco de combustible acepta lo que arde. Hay una barra
    con lo que dura la pieza que quema y el tiempo que queda con todo.
  - **Asador:** ocho huecos de una pieza cada uno, con lo que lleva asado.
  - **Encender / Apagar:** enciende si hay combustible y se apaga sola al
    acabarse. Con temporal y al raso, gasta un 60 % más deprisa.
  - **Recoger lo asado:** pasa al inventario lo que ya no se asa más.
  - **Desmontar:** apagada y vacía, vuelve al inventario.
- **Encendida:**
  - **Asa:** lo que hay en el asador se va asando.
  - **Calor:** a pie de fuego da hasta 18 °C de más, que se apagan del todo a
    6 m (`SurvivalNeeds`).
  - **Secado:** lo mojado se seca antes.
  - **Luz:** a menos de 9 m alumbra, y la oscuridad no quita cordura.
- **Partida:** se guarda con la partida, con lo que tiene dentro y el fuego.

## Herramientas

```sh
# Mallas, escenas e iconos (renderiza: sin --headless)
godot --path . --script res://tools/combat/bake_weapons.gd -- --only=seax,survival --background
# Solo el icono del banco de trabajo
godot --path . --script res://tools/combat/bake_weapons.gd -- --only=stone_workbench --background
# Nombres, grupos, rasgos y objetos nuevos del catálogo
godot --headless --path . --script res://tools/items/update_item_catalog.gd
godot --headless --editor --quit --path .   # importa
```

Las mallas están en `SurvivalMeshes`, la hoguera en `scenes/world/campfire.tscn`
(`Campfire`) y el banco en `scenes/world/stone_workbench.tscn` (`Workstation`). Los
iconos de la hoguera y del banco salen de las mallas sencillas de `SurvivalMeshes`.
`tests/world/placeables_review.tscn` planta tres hogueras encendidas y tres bancos
en un suelo de prueba (llano, una ladera de 15° y baches), para ver cómo asientan.
`tests/items/test_recipes.tscn` prueba el recetario y la ventana de fabricar:

```sh
godot --path . res://tests/world/placeables_review.tscn [-- --capture=<carpeta>]
godot --headless --path . res://tests/items/test_recipes.tscn
```

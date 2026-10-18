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
| Consumibles | Cocinada · Cruda · Bebida · Remedios |
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
| `SkinningTrait` | En la mano, deja despellejar | seax, cuchillo de sílex |
| `GroundPlaceableTrait` | Se planta en el suelo: escena, vista previa, pendiente, separación y cuánto se inclina y se hunde | hoguera, banco de trabajo |
| `CraftingStationTrait` | Es una estación de trabajo: su era y desde qué distancia se usan sus recetas | banco de trabajo |
| `RemedyTrait` | Cura: vida al momento, «Recuperándose» unos segundos, corta el sangrado, cierra las partes heridas y quita estados | milenrama, emplasto, bebedizo, tablilla |

Un rasgo nuevo es una clase que hereda de `ItemTrait` en
`scripts/items/traits/`, con su `describe()` para la ficha.

## Lo de supervivencia

| Objeto | Id | Qué es |
|---|---|---|
| Seax | `seax` | Cuchillo de un filo: arma ligera (14 de daño) y despelleja |
| Carne cruda | `raw_meat` | Hambre +12 %, cordura −6 %; intoxica el 35 % de las veces; se asa |
| Carne asada | `cooked_meat` | Hambre +35 %, sed −3 %, cordura +3 %, vida +8 |
| Piel | `raw_hide` | Material de caza |
| Hueso, tendón | `bone`, `sinew` | Materiales de caza: casi todos los animales |
| Asta, colmillo de jabalí, marfil, cuerno | `antler`, `boar_tusk`, `ivory`, `horn` | Materiales de caza: los ciervos, el jabalí, el mamut y el elefante, los de cuernos |
| Pluma | `feather` | Material de caza: las aves. Empluma las flechas |
| Fibra vegetal | `plant_fiber` | Se arranca de los arbustos |
| Odre | `waterskin` | 5 tragos de agua |
| Milenrama | `yarrow` | Hierba que se arranca en los prados. Masticada: vida +3 y corta el 30 % del sangrado |
| Emplasto de milenrama | `yarrow_poultice` | Corta todo el sangrado (un muñón, a medias), cierra el 35 % de cada parte herida, vida +5 y 12 s de recuperación |
| Bebedizo de milenrama | `yarrow_draught` | 40 s de recuperación (+60), cierra el 15 % de las partes, quita la intoxicación y la sed (+15 %) |
| Tablilla | `splint` | Cura la pierna rota |
| Menas | `flint`, `obsidian`, `copper_ore`, `tin_ore`, `bog_iron`, `iron_01`, `coal`, `silver_ore`, `gold_01`, `sulfur` | Los diez materiales del mundo: ver [terrain_materials.md](terrain_materials.md#menas). El carbón arde 300 s |
| Hoguera | `campfire` | Se planta en el suelo |
| Banco de trabajo | `stone_workbench` | Estación de trabajo de la Edad de piedra: se planta en el suelo |

El jugador empieza con un seax. El resto sale con `give <id> [cantidad]`.

### Caza

Un animal muerto se despelleja con E llevando el seax (o lo que tenga
`SkinningTrait`) en la mano. Sin él, el juego avisa de que hace falta un
cuchillo.

Despellejar lleva un rato (`Butchering`): 20 s por metro de radio del cuerpo,
entre 6 y 22 (un lobo, unos 7 s; un ciervo, 11; un mamut, 22; los pequeños, desde 3: ver
[Animales pequeños](#animales-pequeños)). El jugador se agacha de cara
al cadáver y corta por el lado que le da. Trabaja con el clip `butcher` en bucle
en el canal de tronco y brazos (`PlayerCombat.play_task`), sobre las piernas
agachadas. De momento es provisional: un tajo de espada en guardia baja
(Mixamo, *Sword And Shield Slash*, en `models/player/mixamo/tools/`), a ×0,9.

Va por fases (de toda la tarea), y al final del animal queda la canal:

- **Desmembrar** (hasta el 35 %): a cada tajo se le corta un miembro de los que
  le queden, del más cercano al jugador al más lejano: cada pata por arriba, el
  cuello y la cola (`AnimalGore.butcher_cuts`, las mismas mutilaciones del
  combate). Lo cortado sale con un empujón suave y cae junto al cuerpo de una
  pieza, gotea y deja charco; el muñón queda tapado, echa un chorro y deja su
  charco; cruje el hueso (`bone_snap`). Lo que no haya cortado ningún tajo a
  tiempo se corta al acabar la fase.
- **Despellejar** (hasta el 55 %): cada tajo, sincronizado con el clip (`CUT`, a
  0,60 s de cada vuelta, donde la mano va más deprisa), suena a cuchillo en carne
  (`skin_cut`) y salpica unas gotas. Uno de cada dos salpica de verdad
  (`CombatFx.blood`) y mancha la mano del cuchillo. El revés de vuelta
  (`BACKCUT`, 1,07 s) corta más flojo. Tres veces se arranca un buen trozo de
  piel (`skin_tear`).
- **Quitar la piel** (al 55 %): con un desgarro, huesos que se parten y sangre,
  el cuerpo del animal se esconde y en su sitio queda la canal (`Carcass`).
- **Destripar** (hasta el 72 %): al 62 % las vísceras salen al suelo
  (`GutPile`) con un chapoteo y su charco, y cada tajo chapotea
  (`skin_squelch`).
- **Descarnar** (desde el 72 %): se saca la carne y crujen huesos
  (`bone_snap`).
- **Acabar**: el cadáver se llena con lo que da y se abre como un botín.
- **A medias**: moverse, saltar, atacar, rodar, alzar la guardia, trepar, nadar o
  alejarse lo deja; E otra vez lo retoma donde se quedó
  (`NPCController.butcher_progress`).
- **Gore** (Opciones): sin gore, solo el cuchillo y la piel; con sangre, la
  sangre y todos los sonidos; con todo, también los miembros cortados, la canal
  y las vísceras.

#### La canal

Es la misma para todas las especies (`Carcass`): un caballo panza arriba,
abierto por el vientre y destripado, sin cabeza, sin cola y sin las patas de
abajo. La pared de carne entre las costillas forma una artesa, con las
costillas por dentro y sus puntas asomando por el borde; el lomo va a lo largo
de la columna y hay cuartos, paletillas con el hueso asomando y el muñón del
cuello. Se lleva a la medida de cada especie por su cápsula de colisión,
comparada con la del caballo: a lo largo, por el alto de la cápsula; de través,
por su radio, sin apartarse más de un 25-35 % de escalarla igual en todo
(`Carcass.CROSS_LIMITS`). Se pone sobre el suelo bajo el centro del cuerpo, con
su normal y el cuello hacia donde el animal tenía la cabeza. Al volver la
criatura del pool, se quita y el cuerpo vuelve.

`tools/combat/build_carcass.py` (Blender, `--preview DIR` deja renders) la hace
y la exporta a `models/animals/carcass/carcass.glb`:

- **Los huesos**: [*Lowpoly Horse Skeleton (Rigged)*](https://sketchfab.com/3d-models/lowpoly-horse-skeleton-rigged-0a35814ed7e34c05875081ed12266d35),
  de [Azazel750](https://sketchfab.com/BihexmorForgotHisPassword), CC-BY 4.0.
  Se descarga de Sketchfab (glTF) y se le pasa su `scene.gltf`. Se quitan la
  cabeza, el cuello (menos una vértebra), la cola y las patas por debajo del codo
  y del corvejón, se abren las patas y se tumba.
- **La carne**: un campo de distancias a los huesos (OpenVDB, el de Blender),
  cada hueso con su grosor (`MEAT`), unidos con un mínimo suave, con bultos de
  músculo y convertidos en malla. La pared de las costillas se aparta hacia fuera
  (`RIB_SHIFT`) para que asomen por dentro y llega al 72 % de su alto (`RIM`).
- **Las texturas**, horneadas con Cycles: músculo granate a manchas, con zonas
  secas, estrías, fascia, vetas de grasa, hueso donde roza las costillas y
  coágulos en las hondonadas; los huesos, con su textura y sangre.
- **Las vísceras** (`GutPile`): tripas enredadas, la panza, el hígado, los
  pulmones y el corazón, en el suelo junto a la canal.

`build/carcass_probe/preview.tscn` (fuera del repositorio, con ventana) mata
animales (`-- --animal=Deer,Wolf`), los cambia por la canal y la captura.

Para cambiar el clip por el definitivo: añadirlo a `CLIPS` de
`tools/combat/retarget_mixamo.gd` como `butcher` y medir en él los instantes del
corte (`CUT`, `BACKCUT` en `Butchering`). Los sonidos son grabaciones CC0 de
Freesound (`tools/audio/build_combat_sounds.py`, ver
[audio_credits.md](audio_credits.md)).

Lo que da lo dice cada animal en su escena: `NPCController.butcher_loot` (grupo
*Caza* del inspector), un `LootTable` con líneas `LootEntry` (objeto, cantidad
para un adulto de tamaño 1 y probabilidad). Los de las especies están en
`data/fauna/loot/<especie>.tres`. `HuntingLoot` lo escala por el tamaño del
animal y por el cuchillo, con un ±20 %. Lo que va por piezas no se escala
(`LootEntry.scales` apagado): un par de astas es un par en un ciervo pequeño y en
uno grande. Una especie nueva trae el suyo, y sin él da carne y piel según el
grosor de su cuerpo. Algunos ejemplos:

| Especie | Carne | Pieles | Huesos | Tendones | Piezas (fijas) |
|---|---|---|---|---|---|
| Ciervo, caribú | 3 | 2 | 2 | 1 | 2 astas |
| Cierva | 2 | 1 | 1 | 1 | — |
| Alce | 5 | 3 | 3 | 2 | 2 astas |
| Jabalí | 2 | 1 | 1 | 1 | 2 colmillos |
| Búfalo | 5 | 3 | 3 | 2 | 2 cuernos |
| Cabra, cabra montés, muflón, vaca, ñu, berrendo | 2-4 | 1-2 | 1-2 | 0-1 | 2 cuernos |
| Rinoceronte | 8 | 3 | 4 | 2 | 2 cuernos |
| Oso | 5 | 3 | 2 | 1 | — |
| Lobo | 2 | 1 | 1 | — | — |
| Mamut | 12 | 5 | 6 | 3 | 2 marfiles |
| Elefante | 10 | 4 | 5 | 3 | 2 marfiles |

Las mallas de los materiales de caza (hueso, tendón, asta, colmillo, marfil,
cuerno y pluma) salen de `SurvivalMeshes`, como la carne y la piel.

Después se saquea como cualquier botín. Los animales ya no traen madera y
piedra de relleno. Lo que se le quedó clavado (la lanza siempre, seis de cada
diez flechas) sale con lo demás: `HuntingLoot.fill` lo suma a lo que ya llevaba.

#### Animales pequeños

Conejos, liebres árticas, zorros, zorros árticos y aves (los de bosque, las
gaviotas y los patos) se despiezan igual: E sobre su cadáver (`FaunaCorpse`, a
menos de 2,5 m: `PlayerController.SMALL_CORPSE_REACH`) con el cuchillo en la mano.
El cadáver lleva para esto lo mismo que un `NPCController` muerto (`is_dead`,
`butchered`, `butcher_progress`, `inventory`, `butcher_loot`, `body_size`,
`get_skeleton`, `get_lock_point`, `butcher_shape`, `butcher_model`), que es lo que
usan `Butchering`, `Carcass` y `HuntingLoot`. Cambia que:

- Lo que da va en el perfil de la especie (`AmbientFaunaProfile.butcher_loot`,
  grupo *Caza*), que `AmbientAnimal.die` pasa al cadáver con su tamaño, el grueso
  de su cuerpo (el radio de su cápsula, o media esfera en las aves) y el color de
  sus plumas (`FaunaCorpse.set_hunt`). Sin él (ratones, lémmings) no se despieza y
  E sigue a lo demás.
- No se desmiembra. Lleva desde 3 s (`Butchering.SMALL_MIN_TIME`: un conejo o un
  pájaro, 3; un zorro, 3,4) y sangra a su medida (`FX_RADIUS`). La canal y las
  vísceras salen a su tamaño.
- A las aves se las despluma: cada tajo, cada tirón y el final sueltan plumas
  (`FaunaCorpse.pluck`, `FeatherPuff`) que bajan despacio meciéndose, del color de
  la especie (`AmbientBird.PLUMES`).
- Mientras se trabaja en él se queda quieto y no se va; despiezado, dura otros
  90 s, y vacío ya no lo coge la E. Si se va con el botín abierto, se cierra.
- Su cadáver sale con cualquier nivel de gore (antes, sin gore, desaparecía).

| Especie | Da (un adulto de tamaño 1) |
|---|---|
| Conejo | 1 carne y, la mitad de las veces, 1 piel |
| Liebre ártica | 1 carne y, seis de cada diez, 1 piel |
| Zorro, zorro ártico | 1 carne, 1 piel y, la mitad de las veces, 1 hueso |
| Gorrión, petirrojo, herrerillo | 3 plumas y, tres de cada diez, 1 carne |
| Gaviota, pato | 5 plumas y 1 carne |

`tests/items/test_hunting_loot.tscn` comprueba que los perfiles que se despiezan
traen lo suyo, que ratones y lémmings no, y que un cadáver se llena, guarda lo que
se le clavó y deja de cogerse vacío.

### Fibra vegetal

Los arbustos leñosos (redondo, florido, sauce, abedul enano, enebro enano y
brezo) se arrancan con E **mirándolos**, y dan de 1 a 4 de fibra según el
tamaño de la mata. Usan la misma vía que las ramas y las piedras del suelo
(`GroundPickup`): en `planet_earth.json` sus entradas cercanas (bandas 0 y 1)
llevan `"pickup": true`, `"pickup_item": "plant_fiber"` y
`"collision_distance_m": 40`, y cerca del jugador cada mata tiene un cilindro de
su tamaño en la capa de recogida (`Planet._pickup_shape`). Hay que mirarlos
porque abundan, sobre todo en las orillas, y si no se llevarían la E de beber o
de recoger lo soltado. Al arrancarla suena a hojas (`land_leaves`).

### Curarse

Los remedios (`RemedyTrait`) se usan como la comida: clic con ellos en la barra o doble clic en el
inventario (`SurvivalActions._consume`). Uno que no es comida no se gasta si no hay nada que curar
(«Ahora no te hace falta»).

- **Vida** (`health`): al momento.
- **Recuperación** (`recovery_time`): el estado «Recuperándose» (`data/status/recovering.tres`,
  1,5 de vida por segundo) durante esos segundos; dos seguidos suman su tiempo.
- **Sangrado** (`stanch`): la parte del sangrado de cada herida que corta (`BodyDamage.treat`). Un
  muñón se frena algo más de la mitad de eso: sigue sangrando, menos.
- **Heridas** (`mend`): la parte de la vida de cada parte del cuerpo herida que le devuelve. Lo
  perdido no vuelve.
- **Estados** (`cures`): los que respondan a esas etiquetas (`StatusEffects.cure`): `poison`, la
  intoxicación; `fracture`, la pierna rota.

#### Milenrama

Matas de 40-60 cm con hojas finas como plumas y umbelas planas de florecillas blancas (alguna
rosada), que florecen en verano (`UnderstoryGeometry._yarrow`, especie `yarrow`). Salen sueltas en
los prados templados (`yarrow_generator_green`, como las flores silvestres pero cinco veces menos) y
en la taiga y la tundra baja (`yarrow_generator_cold`). Se arrancan con E **mirándolas**, como los
arbustos (`GroundPickup.PLANTS`), y dan 1 o 2 según la mata. Un neandertal de El Sidrón tenía
compuestos de milenrama y manzanilla en el sarro de los dientes: hierbas amargas que no alimentan
y que seguramente tomaba para curarse.

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
- **Agua:** una receta puede gastar tragos de los odres (`RecipeData.water`); la ventana lo enseña
  como un ingrediente más («Agua de los odres»).
- **La hoguera** encendida también es una estación (`Workstation.CAMPFIRE`): sus recetas llevan
  `station = &"campfire"` y se hacen a su alcance (2,6 m). Apagada no vale.
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
| Cuchillo de sílex | 1 sílex, 1 rama y 1 tendón | A mano |
| Puñal de hueso | 2 huesos y 1 tendón | A mano |
| Hacha de piedra | 3 piedras, 2 ramas y 1 piel | Banco de trabajo |
| Pico de piedra | 4 piedras, 2 ramas y 1 piel | Banco de trabajo |
| Arco de caza | 3 ramas y 1 piel | Banco de trabajo |
| 4 flechas | 1 rama, 1 piedra y 2 plumas | Banco de trabajo |
| Tirachinas | 1 rama y 1 piel | Banco de trabajo |
| Espada de sílex | 4 maderas, 4 sílex y 1 piel | Banco de trabajo |
| Espada de obsidiana | 4 maderas, 4 obsidianas y 1 piel | Banco de trabajo |
| Maza de piedra | 2 maderas, 3 piedras y 1 tendón | Banco de trabajo |
| Mazo de piedra | 4 maderas, 6 piedras, 2 tendones y 1 piel | Banco de trabajo |
| Lanza de sílex | 3 ramas, 1 sílex y 1 tendón | Banco de trabajo |
| Escudo de madera | 3 maderas y 1 rama | Banco de trabajo |
| Escudo de piel | 4 ramas, 2 pieles y 1 tendón | Banco de trabajo |
| Escudo de placas de hueso | 3 maderas, 6 huesos, 2 tendones y 1 piel | Banco de trabajo |
| Ropa de pieles | capucha 2, jubón 4, manoplas 1, calzas 3 y botas 2 pieles | Banco de trabajo |
| Emplasto de milenrama | 3 milenramas y 1 fibra vegetal | A mano |
| Tablilla | 2 ramas y 2 fibras vegetales | A mano |
| Bebedizo de milenrama | 4 milenramas y 2 tragos de agua de los odres | Hoguera encendida |

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
# Solo los materiales de caza y la fibra
godot --path . --script res://tools/combat/bake_weapons.gd -- --only=bone,sinew,antler,boar_tusk,ivory,horn,plant_fiber --background
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

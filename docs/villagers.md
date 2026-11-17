# Aldeanos

Los [poblados](settlements.md) tienen gente cuando el jugador se acerca: aldeanos nórdicos vestidos de
pieles que duermen en sus casas, trabajan en la leñera, el huerto o el banco con las herramientas del
jugador y pasan el resto del día en la plaza, con su hoguera al atardecer. Te miran, te saludan, se
apartan, huyen a casa si ataca una fiera y se meten en ella cuando llueve. Se puede hablar con ellos,
hacerles regalos, comerciar y hacerles encargos, y cada poblado recuerda la confianza que le tiene al
jugador. Con bastante, alguno se va con el jugador: lo sigue, le lleva cosas y pelea a su lado, y se
puede quedar a vivir en su base como colono. Salen siempre iguales del plano del poblado y no se
guardan; la confianza, los encargos, el compañero y los colonos sí.

| Pieza | Qué hace |
|---|---|
| `SettlementPopulation` (`scripts/world/settlement_population.gd`) | Quién vive en cada poblado: nombre, aspecto, ropa, casa y lecho |
| `SettlementVillage` (`scripts/world/settlement_village.gd`) | Los sitios del poblado en el marco del terreno (plaza, puertas, lechos) y sus puertas |
| `SettlementVillagers` (`scripts/world/settlement_villagers.gd`) | Cuándo un poblado tiene gente; los viste en un hilo y los saca |
| `Villager` (`scripts/world/villager.gd`) | El aldeano: su rutina, cómo anda y sus animaciones |
| `SettlementPrefab.beds` | Los lechos de cada casa, que pone `SettlementManager` como decorado |
| `SettlementWorkplace`, `SettlementDecor` | Los sitios de trabajo de cada casa (leñera, huerto, banco) y lo que se ve de ellos |
| `SettlementFire` (`scripts/world/settlement_fire.gd`) | La hoguera de la plaza, encendida al atardecer y cuando nieva |
| `SettlementRelations` (`scripts/world/settlement_relations.gd`) | La confianza de cada poblado en el jugador, a quién conoce y lo regalado hace poco |
| `VillagerTalk` (`scripts/world/villager_talk.gd`) | Qué dice un aldeano y cuánto le gusta un regalo |
| `VillagerChat` (`scripts/player/villager_chat.gd`) | El panel de hablar con un aldeano |
| `ItemValue` (`scripts/items/item_value.gd`) | Lo que vale un objeto para ellos |
| `SettlementCompanions` (`scripts/world/settlement_companions.gd`) | Quién se ha ido con el jugador: reclutar y guardar |
| `Companion` (`scripts/world/companion.gd`) | El compañero: sigue o espera al jugador, con física; lleva cosas y pelea |
| `SettlementTrade` (`scripts/world/settlement_trade.gd`) | El trueque: lo que tiene cada vecino y a cuánto |
| `SettlementQuests` (`scripts/world/settlement_quests.gd`) | Los encargos: lo que pide cada vecino, cómo va y lo que da |

## Quién vive

Un vecino por lecho de las casas (`SettlementPrefab.beds`: la choza tiene 2, la casa 3 y la casa
larga 6), con un 80 % de lechos ocupados. Cada uno tiene:

- nombre nórdico según su sexo;
- semilla de aspecto (`CharacterAppearance.randomize_values`, siempre de linaje nórdico: ver
  [Creación de personaje](character_creation.md));
- una de dieciséis mudas de pieles de las que se fabrican (`SettlementPopulation.OUTFITS`): las
  ligeras de manto, taparrabos y mocasines (lobo, ciervo, jabalí, zorro) y las de abrigo de casaca,
  calzas y botas (lobo, bisonte, cornamenta, ártico), algunas con manoplas o guanteletes. Nunca la
  vieja de `hide_*`, que ya no se fabrica. Uno de cada ocho lleva algo en la cabeza: la del animal
  de su ropa (lobo, ciervo, jabalí) o la capucha de oso;
- un oficio, si le toca un puesto de trabajo.

La semilla sale de la del poblado y de su número. Los puestos (`SettlementWorkplace.stands`) se reparten
al azar entre los vecinos, uno por puesto, y los que quedan sin puesto no tienen oficio.

| Sitio | Dónde | Oficio | Herramienta | Animación |
|---|---|---|---|---|
| Leñera: pila de troncos y tajo | detrás de la choza y de la casa larga | leñador | hacha de piedra o de bronce | el golpe de arriba abajo del jugador, con respiros |
| Huerto: surcos de matas sobre montones de tierra | detrás de la casa (2 puestos) | granjero | azada de piedra o de bronce | cavar (Mixamo) |
| Banco de trabajo | dentro de la casa larga y del granero | artesano | martillo de piedra | el mismo golpe, más rápido |

Talar y picar son solo gesto: no producen nada. La herramienta cuelga del hueso del dedo corazón con
el marco de agarre del jugador (`CombatPose.RIGHT_GRIP`). La mano no se cierra sobre el mango, así que
solo la saca mientras trabaja, con animaciones en las que ya agarra.

Los sitios de fuera se asientan en el terreno al trazar el poblado (`SettlementLayout._workplace`):

- **Leñera y pie de cada puesto:** se lee el suelo en su punto.
- **Huerto:** el suelo se lee en 3 × 3 puntos y cada mata va a su altura entre ellos.

Cuentan en la huella de su casa, así que ninguna construcción los pisa. `SettlementManager` los pone
como decorado con su casa (`SettlementDecor`) y los quita con ella.

Los lechos son la malla del `Bedroll` con su colisión, sin lo que lo hace un objeto de la partida: ni
se guardan ni se recogen. `SettlementManager` los pone con la casa (`_place_beds`) y los quita con
ella. La herramienta de prefabs los coloca contra la pared del fondo, con la cabecera (−Z del lecho)
hacia ella.

## Cuándo aparecen

A menos de `villager_distance` (200 m) del centro, con todas las casas levantadas, el poblado se llena
y se vacía a 60 m más. La casa que el jugador ya ha tocado es suya, y en ella no vive nadie.

Crear un humano cuesta ~100 ms (aplicar el aspecto y vestirlo) más el ajuste de la ropa en hilos. En
el hilo principal cada aldeano sería un tirón, así que `SettlementVillagers` los viste en un hilo de
fondo, de uno en uno y fuera del árbol (`Villager.build_model`), y mete uno por fotograma.

- **Antes de lanzarlo**, el hilo principal carga `AppearanceCatalog`: se rellena la primera vez y dos
  hilos a la vez se pisaban.
- **Las cachés de LODs** de `HumanShape` van con un mutex.
- **El rig sigue en marcha** al entrar en el árbol si le quedan ajustes por recoger
  (`CharacterAppearanceRig._ready`).

Nueve aldeanos tardan unos 10 s en estar todos. Cada uno cuesta en el hilo principal ~1 ms al entrar
y, al acabar el ajuste, montar su ropa (el peor fotograma medido con 20 a la vez, 9 ms).

## La rutina

Por la hora solar del poblado (`Seasons.solar_hour`; sin sol, mediodía):

| Hora | Qué hace |
|---|---|
| 21:30–6:30 | Va a su casa, entra por la puerta, se sienta en su lecho y se acuesta |
| Al levantarse | Sale por la puerta y se queda delante un rato |
| 8–12 y 13–18 | Con oficio, trabaja en su puesto entre 1 y 2,5 minutos seguidos, con algún descanso |
| 12–13 | Se sienta delante de su casa |
| De día, sin oficio | Pasea a un sitio de la plaza y se queda de pie, se sienta en el suelo o busca a alguien libre cerca para charlar: van los dos a encontrarse a medio camino |
| Desde las 18:30 | Lo mismo, pero sobre todo se sienta en corro alrededor de la hoguera |

Cada cosa dura entre unos segundos y un minuto. Al aparecer, de noche ya está dormido en su lecho, con
lluvia a los pies de su lecho y si no en un sitio de la plaza. La hoguera (`SettlementFire`: la del
jugador sin combustible, inventario ni guardado) se enciende de 18:00 a 23:00 y mientras nieva, y
con lluvia se apaga. El tiempo cambia la rutina de día (ver Reacciones).

## Reacciones

- **Al jugador.** De pie lo mira si está a menos de 4 m. A menos de 6 m, de pie o trabajando, a veces
  lo saluda con la mano y sigue con lo suyo; cada uno, una vez cada minuto y medio como mucho.
- **Al andar.** Fuera de las casas se aparta de quien tenga delante a menos de 1,3 m (otros aldeanos,
  el jugador, la hoguera) torciendo hacia su lado.
- **A las fieras.** Cada segundo el poblado mira si hay un lobo, oso, jabalí, felino, hiena o caimán
  vivo y despierto **atacando** (en pelea, `CreatureCombatState`, contra el jugador, el compañero u
  otro animal) a menos de 25 m de lo más lejano del poblado. Si lo hay, todos corren a su casa,
  entran, cierran y se quedan dentro, de pie a los pies de su lecho, y no aceptan regalos. Salen 15 s
  después de que ninguna ataque. Una fiera que solo ronda, come o avisa no asusta: si asustara, con
  tanta fauna el poblado se pasaría el día escondido de algo que ni se ve. Tampoco cuenta una dormida
  por la fauna (lejos del jugador y fuera de cámara se queda parada y oculta). La consola `village`
  dice de qué se esconden y a cuánto de la plaza.
- **Al tiempo.** Cada 2 s el poblado mira lo que cae donde está el jugador
  (`WeatherController.get_local_precipitation`, la misma lluvia y nieve que ve él). Con lluvia desde
  0,3 dejan lo que hagan fuera y corren a casa: se quedan a los pies de su lecho, de pie o sentados
  en el suelo mirando a la puerta, y solo trabaja el del banco, que está bajo techo; cualquiera que
  tenga que cruzar por fuera va corriendo. Con nieve desde 0,4 (si no llueve) se trabaja igual, pero
  nadie se sienta fuera: el rato libre lo pasan en casa, de pie alrededor de la hoguera o charlando
  en la plaza. Se acaba cuando baja de la mitad, y entonces cada uno sale de casa entre 2 y 12 s
  después.

## Cómo se mueve

En línea recta por los sitios del poblado (`SettlementVillage`): de la plaza a su puerta por fuera
(1,6 m), a la puerta por dentro (1 m) y a los pies de su lecho. Las casas miran a la plaza, así que
el camino queda libre.

- **Sin física.** Su sitio va en el marco del terreno, así que el origen flotante no lo mueve. Un
  rayo a la capa del mundo lo pega al suelo y a los suelos de las casas. Sin nada debajo (la colisión
  del terreno aún no ha llegado) sigue a la misma altura y, quieto fuera, la vuelve a buscar cada
  segundo.
- **Puertas.** Al cruzar una (la de su casa o la del banco donde trabaja) la abre
  (`WoodenDoor.toggle`, con su sonido) y la cierra cuando la ha pasado y nadie más la está cruzando.
  No cuenta como tocar la casa.
- **Colisión.** Una cápsula (`AnimatableBody3D`) en la capa 3 lo hace sólido para el jugador sin que
  la vea su propio rayo. Tumbado no la tiene.

## Animaciones

`models/player/village_anims.tres`, de Mixamo, reorientadas con
`tools/combat/retarget_mixamo.gd -- --set=village`:

- **Dormir:** cuatro clips que encadena `SleepRoutine` (`scripts/world/sleep_routine.gd`): sentado en
  el lecho (`wake`), boca arriba alzando la cabeza (`lie_back`), de lado (`sleep_side`, en bucle) y
  dándose la vuelta (`sleep_toss`). Al acostarse se sienta, se echa hacia atrás y se gira de lado con el
  final de `sleep_toss`; dormido, cada 45-150 s da una vuelta; al levantarse se gira boca arriba (otro
  tramo de `sleep_toss`), alza la cabeza, se sienta y aparece de pie a los pies del lecho. Los giros
  salen de la captura: mezclar sin más boca arriba con de lado lo incorporaba a medias. `sleep_side` y
  `sleep_toss` vienen a lo largo de X y se giran 90° (opción `yaw`); `sleep_toss` no es bucle, porque al
  volver a empezar en mitad de una mezcla promediaba boca arriba con de lado y salía la pose de reposo.
- **Apoyo en el lecho:** `Villager.bed_fit` sube o baja el cuerpo hasta que lo más bajo descansa en la
  colisión del lecho (o en el suelo): un rayo por cada punto de `BED_CONTACTS`, con lo que baja el cuerpo
  por debajo de cada hueso (medido en los vértices de varios cuerpos). Hace falta porque
  `BodyProportions` sube o baja la cadera según las piernas de cada uno, también tumbado. Cambiando de
  pose se apoya a cada una; dormido y quieto, cada 0,5 s.
- **Sentado:** en el suelo.
- **Hablar:** se sube 6 cm porque, con las piernas más rectas que el idle, hundía los pies.
- **Andar:** «Walking» de Mixamo (paso normal; avanza 1,7 m/s a ritmo 1), a 1,3 m/s; corre con el del
  jugador, a 3,5 m/s. El compañero también trota («Jogging», 1,6 m/s a ritmo 1). Antes usaban el paseo
  relajado del jugador, que avanza 0,5 m/s: a su paso iba a 2–3 veces su ritmo y se veía raro. Lo que
  avanza cada clip se mide con `build/settlers/clip_speed.tscn` (el pie apoyado respecto al cuerpo).
- **Cavar y saludar:** también se suben 6 y 8 cm. El saludo es un vaivén de medio segundo que se
  repite.
- **De pie y a golpes:** el idle y el golpe de arriba abajo del jugador.

El `AnimationPlayer` va a mano, más espaciado lejos o fuera de cámara (`AnimationLod`, como las
criaturas).

## Hablar con ellos

**E** delante de un aldeano, a menos de 2,6 m y por delante de la cámara (`Villager.find`), abre abajo
su ficha (`VillagerChat`). Él deja lo que hace (también la charla con otro o el trabajo), se para y
mira al jugador (`Villager.Act.CHAT`), y gesticula cada vez que dice algo. El jugador no se mueve
mientras tanto, porque el ratón va suelto. La ficha se cierra con E, Escape o «Adiós», al alejarse a
más de 4 m o si el aldeano se va (una fiera). Dormido no se le puede hablar.

La ficha enseña su nombre, su oficio («Leñadora», «Vecino»...), el nombre del poblado y la confianza
del poblado con su nivel, lo que dice y los botones:

- **Hablar:** otra frase.
- **Regalar:** los montones del inventario, uno por objeto. Un clic le da uno, que se pierde del
  inventario. Dice qué le parece y se ve lo que sube la confianza.
- **Adiós.**

**El nombre del poblado** sale de su número y de la semilla, con dos partes nórdicas (lo que hay allí y
qué clase de sitio es: «Hrafnsstaðir», «Vatnsgarður»; `SettlementPopulation.village_name`).

**Lo que dicen** (`VillagerTalk.line`). La primera vez que hablas con alguien se presenta con su nombre
y el del poblado. Con una fiera cerca, solo habla de eso. Si no, elige al azar, con más peso para lo
primero, entre:

- lo de su nivel de confianza, de «¿Qué quieres?» a «Mi casa es tu casa»;
- lo de su oficio (más si está trabajando);
- lo de la hora: la mañana, la comida, la tarde;
- lo del tiempo: nieve, tormenta, niebla, viento;
- dónde está el poblado más cercano, con el rumbo y lo lejos que queda andando («Hacia el norte, a
  una hora de camino, está Hrafnsstaðir»), si ya no son recelosos;
- la cabeza de animal que lleva el jugador;
- el bronce que lleva en la mano.

Las frases van en `localization/translations.csv` por montones (`VTALK_<MONTÓN>_<n>`, nota
«aldeanos»), y `VillagerTalk.POOLS` dice cuántas tiene cada uno. No repite la última.

**La confianza** (`SettlementRelations`) va de 0 a 100 por poblado. Tiene cinco niveles: recelosos
(desde 0), cautos (20), amables (40), amigos (60) y como de la familia (80).

- **Hablar** con alguien sube 1 la primera vez cada 12 horas de juego, y solo hasta 30: de palabras
  solo no se hacen amigos.
- **Un regalo** sube su valor (`ItemValue`) por el gusto de quien lo recibe por 0,35, hasta 8. Lo
  regalado hace poco cansa: con 40 de valor encima, lo siguiente cuenta la mitad, y eso se enfría a
  la mitad cada 12 horas. Lo que vale menos de 2 con su gusto no cuenta («¿Y qué hago yo con esto?»).
- **El gusto** (`VillagerTalk.taste`): la comida asada 1,5 y las medicinas 1,3; la herramienta de su
  oficio 1,8 (el hacha al leñador, la azada a la hortelana, el martillo al artesano); la ropa 1,2; las
  pieles, huesos y cuernos 1,2; el metal 2 al artesano; la madera 0,5 al leñador y 0,8 a los demás;
  los bloques 0,3; lo demás, 1.

`SettlementManager` guarda la confianza con la partida (`relations` en su `get_save_data`) y hace
avanzar el reloj de horas de juego de `SettlementRelations`, que no avanza con el sol parado.

**Lo que vale un objeto** (`ItemValue.of`), en piezas de leña: lo que no se fabrica tiene su valor en
`ItemValue.BASE` (la carne asada 5, una piel 4, un hueso 1, el oro 25) o el de su categoría, y lo
fabricado vale lo que sus ingredientes por 1,25, repartido entre lo que sale (el lingote de bronce, 8).

## Comerciar

**Comerciar** en la charla con un aldeano abre el trueque: a la izquierda lo suyo, a la derecha lo del
jugador, y debajo la cuenta. Clic en un hueco suma uno a lo que se elige (arriba, «×2»), clic derecho
lo quita. La ficha de cada hueco dice su precio. **Cerrar trato** sale si lo que da el jugador llega a
lo que se lleva; si no, se lo dice. Lo que se lleva va al inventario, y lo que no cabe, al suelo. Con
una fiera cerca no se comercia, y con un compañero tampoco: ya no tiene género.

**Lo que tiene** (`SettlementTrade.STOCK`) depende de su oficio y se sortea cada día de juego (el reloj
de `SettlementRelations`), siempre igual el mismo día. Lo que se lleva el jugador falta hasta el día
siguiente.

| Oficio | Qué tiene |
|---|---|
| Leñera | Madera y ramas siempre; a veces fibra, antorchas o un hacha de piedra |
| Huerto | Fibra y milenrama siempre; a veces emplastos y bebedizos, o una azada |
| Banco | Herramientas y armas de piedra y sílex, arco, flechas, escudo, odre, escala; muy rara vez algo de bronce |
| Sin oficio | La despensa: carne asada y cruda, pescado, pieles, huesos, tendones, plumas; a veces una cuerna o unas manoplas o mocasines |

**Los precios** salen de lo que vale cada cosa (`ItemValue`, en leños) según la confianza del poblado:

| Confianza | Cobran por lo suyo | Dan por lo tuyo |
|---|---|---|
| Recelosos | ×1,6 | ×0,55 |
| Cautos | ×1,35 | ×0,65 |
| Amables | ×1,15 | ×0,75 |
| Amigos | ×1 | ×0,85 |
| Como de la familia | ×0,95 | ×0,95 |

Nunca dan más de lo que cobran, así que comprar y revender no deja nada. Lo que el jugador da de más
es un regalo (`SettlementRelations.gift`, con gusto 1). Un trato de al menos 4 leños sube además la
confianza 2, una vez al día por vecino y hasta 60: comerciando se llega a amigos, no a familia.

`SettlementManager` guarda lo que se ha llevado el jugador hoy de cada vecino (`trade` en su
`get_save_data`).

## Encargos

Algunos vecinos tienen algo que pedir. Entonces su charla tiene **¿Te echo una mano?**, que dice lo que
pide y lo que hay a cambio; **Cuenta conmigo** lo acepta. Con uno abierto, el botón pasa a **El
encargo**: cómo va, **Entregar** (o **Ya está**, si es de caza), que solo se puede pulsar cuando está
cumplido, y **Dejarlo**, que lo cierra sin más. Debajo salen todos los encargos que tiene el jugador
(quién, de qué poblado y cómo van). Al aceptarlo, al avanzar y al cobrarlo se avisa en la barra.

**Quién pide qué** (`SettlementQuests.offer`): cada vecino puede pedir algo una vez cada 2 días de juego
(`PERIOD`, con el reloj de `SettlementRelations`), con un 45 % de probabilidad, sorteado y siempre igual
en ese tiempo. Hay como mucho un encargo abierto por poblado y 3 en total (`MAX_OPEN`); mientras su
poblado tiene uno, los demás vecinos no piden. Quien cumple uno no pide otro hasta el periodo siguiente.

- **Traer cosas** (`FETCH`), según su oficio: el leñero, sílex, carne asada, pieles o tendones; la
  hortelana, huesos, pescado, sílex o plumas; el artesano, sílex, mineral de cobre o de estaño, cuernas,
  tendones o huesos; sin oficio, comida, pieles o milenrama. De 2 a 6 de algo. Al entregar sale del
  inventario.
- **Cazar** (`PREY`): si rondan fieras a menos de 400 m de la plaza (`SettlementVillage.prey_near`,
  despiertas o dormidas), la mitad de las veces pide acabar con una o unas cuantas de una de esas
  especies (2-3 lobos o hienas, 1-2 jabalíes o linces, 1 oso, puma, caimán, león...). Cuentan las que
  caen a menos de 600 m de la plaza (`HUNT_REACH`) por mano del jugador o de su compañero: al morir, una
  criatura avisa al grupo `NPCController.KILLS_GROUP` con quien la hirió por última vez, y
  `SettlementManager.creature_killed` lo cuenta.

**Lo que da** (`SettlementQuests.complete`): lo que vale el encargo (lo traído por 1,5, o cada fiera lo
suyo: un lobo 12, un oso 40) por 0,3 de confianza, entre 4 y 15, **sin tope**: es lo que hace a alguien
de la familia. Y cosas de las que tiene para cambiar según su oficio (`SettlementTrade.STOCK`), una o
dos, por hasta 0,8 de ese valor. Las frases (`VTALK_QUEST_*`) y los nombres de las fieras (`VPREY_*`, con
`_ONE` y `_MANY`) van en `translations.csv`.

`SettlementManager` guarda los encargos abiertos, lo que pide cada vecino en este periodo y quién ha
cumplido (`quests` en su `get_save_data`).

## Compañeros

Con la confianza de su poblado en `SettlementRelations.RECRUIT_TRUST` (60, amigos), la charla tiene
**Ven conmigo**. Por debajo sale desactivado y dice cuánta hace falta. Van hasta seis a la vez (`SettlementCompanions.MAX`), en grupo (ver **El grupo**). Al aceptar, el aldeano deja su poblado
(`Villager.leave_with_player`) y su humano pasa a un `Companion`, sin volver a vestirlo, y la charla
sigue con él. Su poblado ya no lo saca mientras vaya con el jugador.

**El compañero** es un `CharacterBody3D` con la gravedad del planeta, en la capa de los aldeanos
(sólido para el jugador) y chocando con el mundo, colgado del padre de las grids, así que el origen
flotante lo mueve con ellas.

- **Sígueme**: echa a andar a más de 3,5 m del jugador y se para a 2,2. La velocidad va por pasos con la
  distancia: anda (1,4 m/s), a más de 7 m trota (2,4 m/s) y a más de 10 m corre, de 4 m/s a la carrera
  (8 m/s a 15 m). La animación (andar, trotar, correr) sale de la velocidad real, con margen para no
  cambiar a cada paso.
  Si avanza mucho menos de lo que quiere, salta (5 m/s: un bloque), pero solo si lo que tiene delante
  es bajo: con algo a 1,3 m del suelo (una pared) no salta y, en la base, busca camino al momento.
  Apoyado, empuja hacia el suelo a 0,5 m/s: sin eso, contra una pared de una construcción dejaba el
  suelo un tick sí y otro no. Si sigue atascado 4 s a más de
  8 m, o se queda a más de 50 m, aparece a 2,5 m del jugador, por detrás de hacia donde va, en un
  sitio a su vista y con suelo.
- **Espera aquí**: se queda quieto, mirando al jugador si está cerca, y a los 25 s se sienta.
- **Vuelve a casa**: se despide en el aviso de la barra y echa a andar hacia su poblado. Se va del
  todo a 35 m del jugador o a los 45 s, y su poblado lo vuelve a sacar la próxima vez que se llene.
- Con más de uno, cada uno va a su **hueco de la formación** (ver **El grupo**); sueltos, cada uno se
  para 0,6 m más lejos que el anterior y se apartan entre ellos.
- A más de 120 m del jugador no se mueve ni cae, y sin suelo a menos de 60 m por debajo (la colisión
  del terreno aún no ha llegado) tampoco cae: espera.

Se le habla con E como a un aldeano: hablar (frases del camino, `VTALK_ROAD`, y las del tiempo y de lo
que lleva el jugador), regalar (sube la confianza de su poblado), su morral, seguir o esperar, volver a
casa y adiós; y su encargo, si tenía uno abierto con el jugador. Peleando o malherido no se le puede
hablar, y si le atacan en mitad de la charla, se acaba.

**Su morral** (`Companion.pack`, 12 huecos): a la izquierda lo que lleva y a la derecha lo del jugador;
clic pasa uno al otro lado, Mayús+clic diez, Ctrl+clic la mitad (redondeando hacia arriba) y clic
derecho, todos los de ese montón. Al volver a casa devuelve lo que
lleva (lo que no cabe, al suelo).

**Pelea** (`Companion._scan`, cada 0,3 s). Va a por la criatura más cercana a menos de 20 m del jugador
(esperando, de sí mismo) que le ataca a él, que pelea con el jugador (`CreatureCombatState`: la presa
que huye del jugador también lo tiene de objetivo, y esa no) o, siguiéndolo, que el jugador ha herido.
La deja si muere, se duerme o se aleja más de 30 m, o si el jugador se aleja eso. Corre hasta tenerla a
tiro (los dos cuerpos, el brazo y lo que mide el arma), la encara y golpea con los golpes del jugador
(`MeleeMoveset`: de arriba abajo con lo contundente y las hachas, de lado con lo demás) a 1,3 veces su
ritmo y con un respiro entre golpe y golpe. El golpe le da en el cuerpo si sigue a tiro y delante, con
el 0,8 del daño del arma (los puños, 6; nunca menos) y su tipo. El arma (`refresh_weapon`) es la mejor
que lleve en el morral para golpear con la derecha (ni arcos ni hondas) o, si no, la herramienta de su
oficio; se ve mientras pelea y un rato después.

**Le pegan**: tiene 100 de vida (`HealthComponent`, con la protección de su ropa sumada por 0,4) y un
`Hurtbox`, así que las zarpas y los dientes le dan. La criatura a la que golpea se le revuelve
(`NPCController._on_damaged`), y `Perception` lo sigue viendo aunque el jugador ande cerca. Al encajar
un golpe da un respingo (si no está a mitad de golpe) y se revuelve contra quien ha sido. El jugador no
le hace daño: ni su hoja ni sus flechas. **Sin vida cae malherido**: queda en el suelo 25 s (las fieras
lo dejan, porque su vida está a cero), se avisa en la barra y se levanta con el 40 % de la vida. Fuera
de pelea, a los 8 s del último golpe recupera 0,5 por segundo, y por debajo de la mitad come cada 6 s
algo del morral: lo asado cura 25 y un remedio 40.

**Se guarda** en la categoría `"npc"` (`SettlementCompanions`, `entity_id` "<planeta>_settlements_companions"):
su poblado, su vecino (que al cargar se saca otra vez del plano y se viste en el momento), si sigue,
espera o vive en la base (y dónde la tiene), dónde está y hacia dónde mira, en el marco del terreno, lo que lleva y su vida (si estaba en
el suelo, se levanta). El que vuelve a casa no se guarda.

### En el barco

La orden **A los bancos** de la rueda del grupo los sienta en bancadas (`RowingBench`, ver
[Remo y bancadas](sailing.md#remo-y-bancadas)): las del barco en el que va el jugador o, en tierra,
las de a menos de 30 m (`SettlementCompanions.order_board`). Van primero a las de remo y, de cada
clase, a las más cercanas; los que ya van sentados en ese barco se quedan en la suya, y los que no
caben lo dice la barra («3 se sientan en las bancadas; 1 no tiene sitio»).

- **Ir y sentarse** (`Companion.board`): anda hasta la bancada y, a menos de 1,2 m, se sienta con
  `village/throne_sit` y se queda con `village/throne_idle`, con las caderas en el asiento
  (`RowingBench.SEAT`, medidas con la pose sentada, como el jugador en el trono). Si en 12 s no llega
  (un barco en el agua no tiene camino: no nadan), aparece sentado.
- **Sentado** queda en espera (`Mode.WAIT`) y va pegado a la bancada en cada fotograma, con la pose
  interpolada del barco (en el paso de física iría un paso detrás y resbalaría por el asiento al
  navegar); sin cápsula ni física. No pelea ni se revuelve si le pegan, pero se recupera; malherido
  se levanta y cae. Se le puede hablar sin que se levante.
  Mira hacia el -Z local de la bancada y se levanta por ese mismo lado; la orientación sigue la
  rotación con la que se plantó, también al cargar la partida.
- **Junto a la borda lleva remo** y rema con la marcha de remo. Si existe la animación `village/row`,
  rema con ella, a la par de su remo (`BoatOars.phase` y `Companion.ROW_PHASE`); si no, sigue
  sentado con la del trono como base. `RowingPose` ajusta ambos brazos por IK para sujetar el
  mango real durante toda la palada y cierra los dedos. La pelvis y la espalda acompañan el
  recorrido del mango: hacia delante al extender los brazos y hacia atrás al tirar, con los codos
  abiertos por delante del torso. Las caderas siguen apoyadas en el asiento con las proporciones
  de cada cuerpo y las piernas mantienen la postura sentada. Parado conserva el agarre en reposo;
  al levantarse se desactiva la pose.
- **Se levanta** con **Seguidme**, **Retirada**, **A la base**, **Atacad**, Sígueme o Vuelve a casa en
  la charla, al caer malherido o si su bancada desaparece (el barco se parte o se hunde); aparece de
  pie delante de ella. **Esperad aquí** no lo levanta.
- En la lista de la rueda sale «al remo» o «sentado».
- **Se guarda** la bancada (su `entity_id`) con el compañero; al cargar se vuelve a sentar en ella en
  cuanto aparece (hasta 5 s, porque los barcos se recrean al cargar) y, si no, se queda esperando.

### El grupo

Los que acompañan forman un grupo (`SettlementCompanions.party`): los que siguen y los que esperan.
`SettlementCompanions` guarda el rastro del jugador (un punto cada 0,5 m, hasta 48; un salto de más de
20 m lo empieza de cero) y hacia dónde va, y de ahí saca el hueco de cada uno (`slot_of`):

- **Cuña** (la de partida): uno solo va 2,2 m detrás; con más, en filas de dos, cada fila 1,7 m más
  atrás y 1,3 m más abierta a cada lado.
- **Fila**: cada uno 1,7 m detrás del anterior, por donde ha pasado el jugador (rodea lo que él rodea).
- **Sueltos**: como un compañero solo, hacia el jugador.

En formación echa a andar a más de 1,2 m de su hueco y se para a menos de 0,5 con el jugador quieto. Va
al paso del jugador y, si se queda atrás, trota (a más de 3 m), corre (a más de 6) y va a la carrera (a
12). Va por `Companion.steer`, así que si la recta no avanza busca camino. Si su hueco cae dentro de una
pared y en 1,5 s no se acerca, con el jugador quieto y cerca, se queda donde está hasta que el hueco se
mueva. Al aparecer detrás del jugador cada uno prueba primero un ángulo distinto.

**Las órdenes al grupo** (`GroupCommand`, la rueda `GroupOrderWheel`): la tecla **X** (`group_orders`,
reasignable en Combate) abre una rueda como la del martillo; se apunta con el ratón y se da al soltar
(o con clic; un toque la deja abierta; clic derecho, esquivar o Escape la cierran). Sin nadie en el
grupo solo avisa. Lo hecho sale en el aviso de la barra.

- **Seguidme**: los que esperan echan a andar.
- **Esperad aquí**: los que siguen se quedan y defienden el sitio.
- **Id allí**: van al suelo (o lo construido) al que mira el jugador, a menos de 80 m de la vista, y
  esperan allí como con Esperad aquí (`Companion.go_to`, `SettlementCompanions.order_goto`). Uno va al
  sitio y los demás, en corro a 1,6 m; el más cercano a cada hueco va a él. Van por `steer`, andando o
  al trote (desde 7 m); por el camino pelean como esperando. Si no llegan en lo que tardarían al trote
  más 15 s, se quedan donde estén; lejos del jugador (120 m) aparecen allí. En la lista salen «de
  camino» y el destino se guarda con la partida. Sin suelo a la vista, avisa.
- **Atacad**: todos a por la fiera fijada (`lock_on`) o, sin fijar, la criatura viva más centrada en la
  vista a menos de 60 m (12°). Sin ninguna sale apagada. La persiguen hasta 60 m del jugador.
- **Retirada**: dejan la pelea y vuelven corriendo con el jugador (los que esperaban también); durante
  12 s no pelean ni se revuelven.
- **Trabajad**: al apuntarla se despliega por fuera un arco con los oficios (talad, picad, limpiad,
  cazad, pescad, cocinad, construid); el elegido va a los elegidos, alrededor de lo que mira el jugador
  (como en Id allí; un árbol o una roca también valen). Se ponen con él **en campo**
  (`Companion.field_work`, `SettlerWork.field`): esperan allí trabajando, sin horario, hasta que se les
  mande otra cosa (cualquier otra orden los saca). Es el mismo trabajo que el de los colonos, con estas
  diferencias:
  - la zona es la de lo que se mira (25 m; limpiar, 12 m) y talan o pican primero lo más cercano a ese
    punto, así que mirando un árbol empiezan por él;
  - lo sacado va a un cofre de a menos de 30 m de la zona si lo hay y, si no, se queda en su morral (se
    les quita en la charla); con el morral lleno lo dicen y lo dejan (`SettlerWork.pack_full`);
  - construir usa primero el material de su morral y luego los cofres de cerca; lo que sobra, al morral;
  - cocinar usa la hoguera más cercana a la zona (40 m), lo crudo y la leña de su morral, y se queda lo
    asado si ningún cofre de cerca lo admite;
  - lejos del jugador (120 m) no avanza;
  - lo que sacan lo llevan antes a quien lo necesite (`SettlerWork.plan_delivery`): al acabar cada
    árbol, roca, presa o tanda de 5 peces miran si un constructor o un cocinero en campo a menos de 60 m
    necesita algo de lo que llevan y le llevan **solo eso**. Al constructor, directo a su obra
    (`BlueprintSite.deposit`): falta lo que pide la obra menos lo que él lleva y lo que traen otros
    (`SettlerBuild.demand`; el que va se apunta en `_hauls`, así que ni otro recolector ni el
    constructor van a por lo mismo). Al cocinero, en mano: lo crudo hasta 8 y leña hasta 12 cuando le
    quedan menos de 6 (`SettlerCook.demand`). Si nadie necesita nada, vuelven a mirar a los 3 s; lo que
    nadie necesita sigue al cofre o al morral. Entre los colonos de la base no hace falta: se pasan las
    cosas por los cofres.
  En la lista del grupo sale cómo va («Leñador · lleva 14», «Parado: necesita un hacha...»). Se guarda
  con la partida. Si se le dice que se quede a vivir, deja el trabajo en campo.
- **A los bancos**: se sientan en las bancadas del barco (ver **En el barco**).
- **A la base**: cada colono que dejó su base para irse con el jugador vuelve a ella con el trabajo que
  tenía (`Companion.return_to_base`; los que no tenían base, no). Va derecho y trotando hasta quedar a
  12 m; lejos del jugador aparece allí cuando habría llegado andando.
- **Formación**: al apuntarla se despliega por fuera un arco con cuña, fila y sueltos (la de ahora,
  marcada); se elige llevando el cursor allí. Soltar o hacer clic sobre Formación deja la rueda abierta.
  Es de todo el grupo y se guarda con la partida.

**A quién van** (como las teclas de Mount & Blade y el mirar de Ghost Recon): abajo, tapando los huecos
de la hotbar (en su sitio y subiendo por encima), sale el grupo en tarjetas: el retrato con su número, el
nombre, qué hace (sigue, espera, de camino, sentado, al remo, malherido) y las barras de vida y de comida
(`meals.fed` sobre 36 h), que se refrescan cada 0,25 s. Los retratos (`CompanionPortraits`) se hacen fuera
de pantalla, con el humano vestido de nuevo (`Villager.build_model`) y las luces del estudio de la
creación, uno por vez y una sola vez por partida; con la rueda cerrada se piden cada 2 s los que falten,
así que al abrirla suelen estar ya. Mientras se hacen sale una silueta. Al abrir están elegidos todos los que
no están ocupados (trabajando en campo o de camino a un sitio: si lo están todos, ninguno) o, si el
jugador mira a uno del grupo (40 m, 6°), solo ese, aunque esté ocupado. Con la rueda abierta, **1-9** elige o quita a
cada uno y **0** (o º) a todos o a ninguno; mientras tanto cada uno lleva su número encima, encendido
si está elegido. Las órdenes (no la formación) van solo a los elegidos; sin nadie, salen apagadas.

## Colonos

Al compañero se le puede decir **Quédate a vivir aquí**: pasa a `Companion.Mode.SETTLE`, con su base
donde está (`Companion.base`, en el marco del terreno), y deja libre el sitio de quien acompaña, así
que se puede reclutar a otro. Caben `SettlementCompanions.MAX_SETTLERS` (20); con la base llena el
botón sale desactivado. Al colono se le habla igual (frases de la base, `VTALK_BASE`), con su morral;
**Sígueme** lo vuelve a llevar contigo si cabe en el grupo, y **Vuelve a casa** lo devuelve a su poblado.
Al irse con el jugador se acuerda de su base y de su trabajo (`Companion.return_base`, `return_work`,
que se guardan con él) para volver con **A la base**.

**Su día** (`Companion._decide`, a la hora solar de la base, con las horas de los aldeanos):

- de día pasea a algún sitio a menos de 10 m de la base, se queda de pie o se sienta en el suelo;
- desde las 18:30, si hay una hoguera (`Campfire`) encendida a menos de 40 m de la base, se sienta a
  su alrededor (a 1,6-2,4 m) mirándola;
- de noche duerme en el petate (`Bedroll`) más cercano a la base, a menos de 40 m, que no use otro
  compañero: llega a sus pies y se acuesta encima, como los aldeanos (`SleepRoutine`). Sin petate,
  duerme en el suelo junto a la hoguera o en la base. Tumbado no choca ni se le puede hablar; al
  amanecer se levanta y aparece de pie a los pies del petate.
- Si un sitio no se alcanza en 4 s de atasco, hace allí lo que iba a hacer (el petate, encima).

**Come y bebe** (`SettlerMeals`), del **comedero** y del **bebedero** de la base (a menos de 60 m de ella):

- **Comer**: le dura saciado 36 h de juego (la mitad que al jugador) y, por debajo de 6 h, come hasta
  tener 14: primero de su morral y, si ahí no hay nada o solo algo crudo, del comedero. Lo asado antes
  que lo crudo, y de ello lo que más llena; cada pieza da lo que da al jugador (lo asado, ~12 h). Los
  cofres normales ya no le dan de comer.
- **Beber**: le dura bebido 24 h y, por debajo de 8 h, bebe del bebedero hasta tener 20; cada trago da
  16 h, así que gasta un trago y medio al día (60 tragos, unos dos días para 20 colonos).
- **Cerca del jugador va andando** (`SettlerMeals.trip`, `Companion._go_eat`): deja lo que hace (no
  dormido), va al comedero o al bebedero más cercano que tenga algo (con hambre y sed, primero a comer),
  come o bebe al llegar y se queda 6 s de pie junto a él; luego sigue con su trabajo. Si en 60 s no
  llega, come o bebe donde esté. **Lejos**, sin moverse.
- Sin comida o sin agua llega a cero y **pasa hambre** o **sed**: trabaja a la mitad de ritmo (con
  las dos, a un cuarto), no recupera vida y se avisa en la barra (y en su estado sale «· con hambre» o
  «· con sed»). No muere. El reloj es el del mundo (`WorldTime`): durmiendo el jugador, también. Lo que
  se le queda en el morral y las horas de hambre y de sed se guardan.

El **comedero** (`feeding_trough`, banco de piedra: 10 de madera) es un `Storage` con
`StorageTrait.feeder` y 12 huecos que solo admiten comida (`FeederInventoryRules`): nadie deja en él lo
que saca, salvo el cocinero lo asado; al abrirlo no salen los oficios. El **bebedero** (`water_trough`,
banco de piedra: 8 de madera y 2 pieles; `WaterTrough`) guarda hasta 60 tragos, como los odres, y se ve
el agua subir. Con E el jugador vierte en él lo que llevan sus odres; si no lleva agua y tiene sed, bebe
de él; si no, dice cuánto tiene. También lo llena la lluvia (hasta 4 tragos por hora de juego; la
nieve, la mitad), pero solo a menos de 200 m del jugador, porque el tiempo es el del sitio del jugador.
Lo que tiene se guarda con él.

**Defiende la base**: pelea como el compañero, con lo que ataca a menos de 25 m de la base a él, a
otro compañero o al jugador; lo deja a más de 30 m de ella. Si duerme, se despierta. Lo que pasa a
más de 120 m del jugador no lo mueve: allí se queda quieto.

### Trabajo

Los oficios (`SettlerWork`) se mandan **solo desde el trono** (ver *El trono*); el catálogo de todos
está en `SettlerOrders` (texto, dibujo, color, categoría y si pide zona), y uno nuevo es una entrada
más allí. **Tala árboles** y **Pica piedra** buscan alrededor de la base (60 m) o en la zona marcada, y
**Limpia una zona** tala y pica todo lo que haya en ella; **Deja eso** lo para. En la charla del colono
sale debajo cómo va («Leñador · lleva 14», o por qué está parado) o, sin trabajo, que se manda desde el
trono, y se le puede preguntar (`VillagerTalk.settler_doing`, `settler_needs`, en primera persona):
**¿Qué haces?** (su oficio y dónde, y si descansa, no le queda nada, lo que lleva sacado o qué le para)
y **¿Qué te falta?** (lo que le para el trabajo, el oficio si no tiene, la comida y el agua suyas y las
de los comederos y bebederos de la base, si duerme en el suelo y si está malherido; o que nada). Si está
parado por algo, lo dice nada más hablarle. Además avisa en la barra (`SettlerWork.watch`) cuando lleva
6 s parado por lo mismo («Thorgerd: «Necesito un hacha en el morral.»»), sin repetir el mismo aviso
antes de 10 min. Lo que le para va con su clave (`SettlerWork.block(clave, args)`, `reason_key`): la
misma clave con `_ME` es cómo lo dice él (`SettlerWork.stuck`). Trabaja en el horario de los
aldeanos (8-12 y 13-18); fuera de él hace su vida,
de noche duerme y, si atacan la base, deja lo que hace y pelea.

- **Con qué**: con lo que lleva en el morral, el mejor hacha para talar o el mejor pico para picar.
  Sin ella no hace nada (*Parado: necesita un hacha*). No se gasta.
- **Dónde lo deja**: en el cofre (`Storage`) de la base, a menos de 60 m de ella, que acepte su oficio y
  tenga sitio. En la pantalla del cofre, **Para colonos** marca los oficios (Leñador, Cantero,
  Desbroce, `Storage.jobs`); sin ninguno marcado lo aceptan todos. Van antes a los marcados con su
  oficio y de ellos al más cercano. Sin cofre, o con todos llenos, tampoco trabaja.
- **Cómo**: como el jugador, con sus golpes (`MeleeMoveset`) y la misma tala y picada. Va en línea
  recta hasta el árbol y, si así no se acerca en 1,5 s, por un camino (`Companion.steer`, `GroundPath`:
  A* en una rejilla de medio metro alrededor, escalones de hasta 0,55 m hacia arriba y 4 m hacia abajo,
  abriendo y cerrando las puertas; sale de una casa o baja de un tejado; tres intentos por destino y,
  si sigue sin acercarse, otros tres a los 8 s). No espera a atascarse si ve algo delante: cada 0,25 s
  mira 1,5 m al frente a la altura de las rodillas y de la cabeza (una ventana deja libre una de las
  dos) y, si hay una pared, una ventana o una puerta cerrada, busca camino ya. Tampoco se tira de un
  risco ni a una cueva (`Companion._ledge_ahead`, para todo lo que no sea seguir al jugador): antes de
  cada paso mira el suelo hasta donde le da para frenar y, si queda a más de 1,6 m por debajo (4 m
  yendo por un camino de `GroundPath`, que ya lo ha mirado), se para y busca camino; el camino
  prefiere una rampa a un salto (cada metro de caída de más cuenta como 6 casillas). Lo que queda a más de
  35 m de la búsqueda no tiene camino entero: va por el parcial hasta la casilla explorada más cercana
  (si acerca 1,5 m o más), que de dentro de una casa sale por la puerta y no por la ventana que da a ello. Lo que no alcanza ni así en
  12 s lo deja 2 minutos. Lo tala, al caer
  se aparta 4 m del tocón, lo parte y parte cada trozo en leña. La roca suelta sus trozos y los pica
  hasta que dan piedras. Lo que saca entra en su morral (`Companion.inventory`, sin sonido ni aviso) y,
  al acabar cada árbol o roca, lo lleva al cofre. Las ramas de la copa quedan en el suelo.
- **Nunca comparten** árbol ni roca (`SettlerWork._claims`): el siguiente va al siguiente. Los troncos
  caídos y los trozos que haya en la zona también se recogen.
- **Accidentes**: un árbol que cae encima de otro colono lo mata (`Companion.crush`; al que lo tala, no).
  Pero casi siempre se da cuenta: mientras cae, el árbol está en `FallingTree.HAZARD` con por dónde va a
  caer (`hazard_a`, `hazard_b`, `hazard_half`), y cada compañero lo mira en cada paso
  (`Companion._watch_falls`). De cada árbol decide una vez si se da cuenta: un 95 % a menos de 20 m del
  tocón, cada vez menos hasta 50 m (dormido, la mitad; malherido no se puede mover; al que lo tala no le
  hace falta). Si se ha dado cuenta:
  - si está en su camino (a menos de la anchura del tronco o la copa más 0,6 m, y no detrás del tocón),
    tras 0,15-0,45 s lo deja todo (se levanta de la bancada o del petate, corta el golpe de trabajo a
    medias y la pelea) y sale ya a la carrera, sin ir acelerando, por lo más corto: de lado o, cerca de
    la base, detrás del tocón, hasta quedar 0,8 m fuera (`dodge_fall`, `_start_flee`);
  - si no está pero va a meterse (donde estará en 0,8 s andando como anda: el que va a por otro árbol),
    se para fuera hasta que caiga (`_hold_for`).
  Luego sigue con lo suyo. Un árbol tarda de 2,3 s (6 m) a 3,4 s (15 m) en caer, así que solo muere el
  que no se da cuenta o se atasca. Vale también para los árboles que tala el jugador.
  Suelta lo que llevaba, se queda en el suelo un minuto y no vuelve a salir en su poblado
  (`SettlementCompanions`, "dead").
- La zona se da por vacía (o limpia) tras tres búsquedas seguidas sin nada con ella entera cerca de la
  cámara: lejos (o recién cargada) sus árboles y rocas aún no tienen cuerpo.
- **Lejos** (a más de 120 m del jugador): lo que tenía a medias se da por hecho (se quita del mundo y
  lo que daba va al cofre) y desde ahí produce sin moverse, en su horario, con su herramienta y
  mientras quepa en el cofre: leña o piedra al ritmo de `SettlerWork.rate`, precalculado con su
  herramienta (un árbol de 12 de leña o una roca de 45 piedras, el trabajo que piden y 30 s de ir y
  venir) y corregido con lo que tarda de verdad cerca. Limpiar una zona solo avanza cerca.
- Se guarda con él: el trabajo, la zona, lo que lleva sacado y su ritmo medido.

### Los demás oficios

Cada uno lo lleva su `SettlerTask` (`SettlerWork.task`), que `SettlerWork` crea al mandarlo; aquí va lo
común (andar a un sitio, los cofres de la base). Parados, dicen por qué (*Parado: necesita un martillo
en el morral*). Lejos del jugador cada uno sigue a su manera, sin moverse.

- **Constructor** (`SettlerBuild`, **Construye las obras**): levanta las obras (`BlueprintSite`: los
  blueprints colocados sin pagar, y las reparaciones) de su zona (60 m de la base o la marcada). Necesita
  un **martillo**. Coge de los cofres que aceptan su oficio (Constructor) lo que le falta a la obra (hasta
  60 unidades por viaje), lo aporta como el jugador con la E y la martillea desde fuera de su caja con el
  golpe vertical, que pone lo mismo que un martillazo del jugador. Si en los cofres no hay nada de lo que
  falta, se queda parado diciendo qué (*faltan 12 de Madera en los cofres*). Varios comparten obra: cada
  uno descuenta lo que ya traen los demás. Acabada, avisa y lo sobrante vuelve al cofre. Lleva la cuenta
  de los bloques puestos. Lejos: un viaje cada 30 s y un martillazo cada 2,5 s.
- **Guardia** (`SettlerGuard`, **Guardia de día / de noche**): vigila la zona marcada. Hasta 5 m es un **puesto** (se queda en el centro mirando alrededor);
  más grande, una **ronda** por 8 puntos de su borde, parándose a mirar hacia fuera. El de día vigila
  desde que se levanta hasta que se acuesta; el de noche, de 21:30 a 6:30, y duerme de 9 a 17. De turno
  va a por las fieras que atacan a la vista (lobos, osos, leones...) en cuanto entran en su zona o a
  menos de 12 m de ella, da la alarma en la barra (como mucho cada 45 s) y los otros guardias a menos de
  80 m acuden. No usa cofre.
- **Cazador** (`SettlerHunt`, **Sal a cazar**): caza las presas de su zona (las que huyen al herirlas;
  a las fieras no va) como en una pelea, persiguiéndolas hasta 25 m fuera de ella; la que se le escapa la
  deja 2 minutos. Muerta, la despieza (6 s; lo que da es lo del jugador, `HuntingLoot`, con el cuchillo
  que lleve) y lo lleva al cofre. También despieza lo muerto sin despellejar de su zona. Necesita un arma
  (o la herramienta de su oficio). Lejos: 4 de carne y 1 de piel cada 8 minutos.
- **Pescador** (`SettlerFish`, **Ponte a pescar**): necesita una **caña** (sin gastar anzuelos ni cebo).
  Busca la orilla más cercana de su zona (tantea el agua en anillos cada 3 m y vuelve hacia tierra hasta
  pisar seco), va y, de cara al agua con la caña en la mano, saca un pescado crudo cada 1-2 minutos; con 5
  los lleva al cofre. Sin agua en su zona se queda parado. Lejos, si ya había encontrado su orilla
  (se guarda), uno cada 90 s.
- **Cocinero** (`SettlerCook`, **Cocina**): asa en la hoguera de la base lo crudo que haya en los cofres
  (y en los comederos) y guarda lo asado en el comedero o, si no hay o está lleno, en el cofre que acepte
  su oficio. Coge lo crudo que quepa en los huecos libres y, si al
  fuego le quedan menos de 90 s, 6 de leña (madera antes que otra cosa); recoge lo asado, pone lo crudo,
  echa la leña y enciende. Trabaja hasta la hora de acostarse: al atardecer mantiene la hoguera encendida
  para los que se sientan alrededor. Sin hoguera a menos de 40 m de la base, parado. No tiene zona.
- **Aguador** (`SettlerWater`, **Trae agua**): necesita **odres** en el morral y lleva los tragos que
  quepan en todos (20 por odre). Busca la orilla de agua dulce más cercana de su zona (como el pescador,
  `SettlerTask.find_shore`, pero solo ríos, lagos y charcas: `WaterAccess.kind_at`), llena los odres en
  6 s y los vacía en el bebedero de la base con más sitio. Con todos llenos espera (vuelve a mirar cada
  20 s). Sin bebedero o sin agua dulce en su zona, parado. Lejos, si ya había encontrado su orilla, echa
  sus odres una vez cada 2 minutos. Lo que lleva y su orilla se guardan.

Con hambre o con sed todos van a la mitad de ritmo (con las dos, a un cuarto).

La carga pendiente del cocinero y del cazador se guarda con su oficio: al cargar la partida o volver
a la base después de acompañar al jugador, siguen entregando lo que llevaban en el morral.

### El trono

El **Trono de troncos** (`throne`, se hace en el banco de piedra: 20 de madera, 3 pieles, 2 astas y 2
tendones) se planta como el lecho (`Throne`, malla de `throne_visual.gd`). Con E junto a él el jugador
se sienta (`ThroneView`: `village/throne_sit` y luego `village/throne_idle`, en su AnimationPlayer con el
árbol de animación parado; las caderas se ponen en `Throne.SEAT`) y se abre la vista de la base:

- una cámara de teleobjetivo (35°, casi como una isométrica; la ortográfica dejaba el cielo en negro)
  desde delante del trono y por encima (55°), que WASD mueve (hasta 90 m), R y F inclinan (o arrastrar
  con el botón central, que además la gira) y la rueda acerca o aleja; nunca baja de 12 m sobre el
  suelo. Alejada del todo (a más de ~180 m) los árboles pierden su cuerpo y el trabajo espera;
- el nombre y el oficio de cada colono sobre su cabeza (en amarillo, los elegidos) y sus zonas en el
  suelo: verde talar, azul picar, naranja limpiar, amarillo construir, rojo la guardia, marrón cazar y
  turquesa pescar; tenue, la de alrededor de su base;
- arriba a la izquierda, lo que tiene la base (`BaseSupplies`), cada cosa con su barra en verde,
  naranja o rojo: **camas** (los petates a menos de 40 m de la base de alguno, contra cuántos son: una
  por colono va bien; si faltan, el resto duerme en el suelo), **comida** (para cuántos días da lo de
  los comederos y los morrales, a 24 horas de saciado por colono y día; bien desde 3 días, mal por
  debajo de 1; aparte, lo que hay en los cofres, que no comen hasta que pasa al comedero, y cuántos
  tienen hambre) y **agua** (los tragos de los bebederos, para cuántos días y cuántos tienen sed);
- a la derecha, arriba, cuántos hay de cada oficio (su icono y el número; pinchando uno se eligen
  todos los que lo tienen, también los que no tienen ninguno);
- abajo, en el sitio de la hotbar (que se quita con sus orbes mientras tanto), los colonos con su base
  a menos de 90 m del trono (`Throne.MANAGE_RADIUS`) en tarjetas, las mismas que la barra de la rueda del grupo (`CompanionCards`): su retrato
  (`CompanionPortraits`), el dibujo de su oficio, su nombre, cómo va (en naranja, si está parado por algo
  o le falta comida o agua; con el ratón encima sale entero si no cabe) y sus barras de vida, comida y
  agua. Van ordenados por oficio y nombre; si no caben, se pasan con las flechas o la rueda sobre ellas.
  Clic elige o deja a uno (también pinchando su nombre en el mapa; **Todos** y **Ninguno**, en el panel)
  y doble clic lleva la vista hasta él; con el ratón sobre una tarjeta, su aro en el mapa se agranda;
- a la derecha, debajo de los números de cada oficio, los oficios por categoría, cada uno con su
  dibujo (`OrderGlyphs`, el mismo trazo que la rueda del grupo) en el color de su zona: **Recursos** (Tala árboles, Pica piedra, Limpia una zona), **Comida**
  (Sal a cazar, Ponte a pescar, Cocina, Trae agua), **Obras** (Construye las obras) y **Defensa** (Guardia de día,
  Guardia de noche); aparte, **Deja eso** y **Seguidme**. Salvo cocinar, sale un círculo bajo el ratón: clic lo pone (la rueda cambia el radio, de
  4 a 60 m); con clic derecho van alrededor de su base, y limpiar y la guardia se cancelan.
  **Seguidme** se lleva a los elegidos que quepan en el grupo: dejan la base (acordándose de ella y de
  su trabajo) y siguen al jugador en cuanto se levanta.

E o Escape lo levantan (sentarse al revés) y aparece de pie delante del trono; un golpe también.

**A distancia**: con U (`throne_view`, se cambia en las opciones) a menos de 90 m de un trono
(`Throne.MANAGE_RADIUS`, el mismo radio que sus colonos) se abre la misma vista sin sentarse
(`ThroneView.try_remote`, fase `REMOTE`), empezando sobre el jugador; el cuerpo sigue como con
cualquier menú abierto. Se cierra con E, Escape o U; un golpe también. Sin trono cerca, lo dice.

Para probar, la consola: `settler [n] [kit]` saca `n` vecinos de los poblados más cercanos (que no
vayan ya con el jugador; el que anda por su poblado se va de allí) y los deja viviendo donde está el
jugador, con su base allí; con `kit` llevan en el morral hacha, pico, martillo, lanza, cuchillo y caña.
No pasa de `MAX_SETTLERS`. Se guardan como cualquier colono.

## Configuración

`villager_distance` (200 m) en `settlement_settings`.

## Comprobaciones

`tests/world/test_settlers.tscn` (sin ventana, acelerada ×8, sobre un suelo llano de física y un jugador
de pega): la cuña y la fila mientras el jugador anda (detrás, en su hueco, sin pisarse, parados con él
quieto), el grupo lleno a 6, esperad / seguidme / retirada, que el colono que se va con el jugador se
acuerda de su base y su trabajo (y se guarda) y vuelve con **A la base** (también lejos), el
constructor (parado sin martillo o sin material, levanta la obra desde el cofre, lo sobrante al cofre,
lejos sin moverse), el guardia (ronda por el borde, turnos, puesto de noche), el cocinero (del cofre a
la hoguera y lo asado al cofre o al comedero; lejos), las comidas (del comedero y no de los cofres,
lo asado antes que lo crudo, medio ritmo con hambre), la sed (el bebedero y su guardado, beber lejos
sin moverse, cerca ir andando primero al comedero y luego al bebedero, un cuarto de ritmo con hambre y
sed, el aguador sin odre, lejos y su guardado), el cazador y el pescador lejos, y el guardado de cada trabajo. El cazador y el pescador de
cerca necesitan criaturas y agua reales: solo se prueban con ventana.

`tests/world/test_settlements.tscn` (`_check_villagers`). Sobre un poblado de prueba, con los pasos de
física dados a mano, comprueba que:

- aparecen todos, con sus lechos y sus sitios de trabajo;
- de día están en la plaza;
- de noche entran abriendo y cerrando la puerta y se tumban en su lecho;
- de día vuelven a salir y los de oficio trabajan en su puesto con la herramienta en la mano;
- a mediodía se sientan delante de su casa;
- la hoguera se enciende al atardecer;
- saludan al jugador;
- dos que se cruzan se esquivan;
- si una fiera ataca cerca se encierran en casa, y salen cuando acaba;
- dos se juntan a charlar;
- lejos se van.

La consola `village` dice cuántos hay cerca y cuántos quedan por vestir, de qué fiera se esconden (si se
esconden) y los encargos abiertos con cómo van. `village trust <0-100>` pone la confianza del poblado
más cercano (para probar el compañero sin ganársela), y `spawn <animal>` saca fieras para pelear o cazar.

## Limitaciones

- Los colonos no se intoxican con lo crudo, y sin cocinero lo que cazan y pescan se queda en los cofres:
  hay que pasarlo al comedero a mano. Comen y beben de pie, sin animación. El bebedero lejos del jugador
  no recoge lluvia. El pescador no lanza de verdad (saca a su ritmo,
  haya peces o no) y el cazador despieza con la animación de cavar. El constructor no sube a andamios:
  una obra alta se martillea desde el suelo. El trono aún usa el icono del cofre. Sin ventana no se puede probar el
  trabajo de cerca: los cuerpos de los árboles no se regeneran alrededor del jugador. Cargar una partida
  con muchos colonos los viste todos en ese momento (~0,1 s cada uno).
- Esquivar es solo torcer el paso: dos que se encuentran en una puerta o contra una pared se rozan, y
  al jugador lo empuja su cápsula si se le pone delante.
- Sentarse y tumbarse son fundidos desde estar de pie, sin animación de transición.
- En la bancada, sin la animación de remar, las piernas usan la pose del trono; los brazos y el
  tronco acompañan el remo por código. Sentado no se defiende. Para subir a un barco en el agua no
  buscan camino: si en 12 s no llegan, aparecen en su sitio. El jugador no se sienta en las bancadas
  ni rema solo: sin remeros, el barco solo va a vela.
- La mano no agarra la herramienta fuera de los golpes y de cavar; por eso solo la sacan al trabajar.
- Ante una fiera los aldeanos solo huyen; no se puede pelear con ellos. El compañero sí pelea, pero no
  se protege (ni guardia ni escudo), no usa arcos y no se pone la ropa ni las armaduras que lleva.
- El tiempo es el del sitio del jugador, no el del poblado: valen porque solo hay gente en los
  poblados cercanos. No cambian de ropa con el frío.
- Lo regalado y lo que se les da en un trato se pierde: aún no va a ninguna parte del poblado ni lo
  revenden.
- Suelto o peleando, el compañero va en línea recta (los caminos, `Companion.steer`, los usan el colono
  en la base y en su trabajo y el grupo en formación): no rodea paredes ni busca puertas
  (salta o, si no sale, aparece detrás del jugador). No nada: en el agua anda por el fondo. Las fieras
  solo van a por él si les pega; las que no, siguen con el jugador.
- Los encargos no tienen plazo ni salen en ningún diario: solo en la charla y en los avisos de la barra.
  Las fieras de un encargo de caza no se marcan: valen cualesquiera de esa especie cerca del poblado.
- La confianza solo sube (hablando, regalando, comerciando y con los encargos); aún no baja por nada.
- Una casa que ha pasado a la partida pierde sus lechos al cargarla, porque son decorado.

# Aldeanos

Los [poblados](settlements.md) tienen gente cuando el jugador se acerca: aldeanos nórdicos vestidos de
pieles que duermen en sus casas, trabajan en la leñera, el huerto o el banco con las herramientas del
jugador y pasan el resto del día en la plaza, con su hoguera al atardecer. Te miran, te saludan, se
apartan, huyen a casa de las fieras y se meten en ella cuando llueve. Se puede hablar con ellos y hacerles regalos, y cada poblado
recuerda la confianza que le tiene al jugador. Salen siempre iguales del plano del poblado y no se
guardan; la confianza sí.

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
| 21:30–6:30 | Va a su casa, entra por la puerta y se tumba en su lecho |
| Al levantarse | Sale por la puerta y se queda delante un rato |
| 8–12 y 13–18 | Con oficio, trabaja en su puesto entre 1 y 2,5 minutos seguidos, con algún descanso |
| 12–13 | Se sienta delante de su casa |
| De día, sin oficio | Pasea a un sitio de la plaza y se queda de pie, se sienta en el suelo o busca a alguien libre cerca para charlar: van los dos a encontrarse a medio camino |
| Desde las 18:30 | Lo mismo, pero sobre todo se sienta en corro alrededor de la hoguera |

Cada cosa dura entre unos segundos y un minuto. Al aparecer, de noche ya está en su lecho, con
lluvia a los pies de su lecho y si no en un sitio de la plaza. La hoguera (`SettlementFire`: la del
jugador sin combustible, inventario ni guardado) se enciende de 18:00 a 23:00 y mientras nieva, y
con lluvia se apaga. El tiempo cambia la rutina de día (ver Reacciones).

## Reacciones

- **Al jugador.** De pie lo mira si está a menos de 4 m. A menos de 6 m, de pie o trabajando, a veces
  lo saluda con la mano y sigue con lo suyo; cada uno, una vez cada minuto y medio como mucho.
- **Al andar.** Fuera de las casas se aparta de quien tenga delante a menos de 1,3 m (otros aldeanos,
  el jugador, la hoguera) torciendo hacia su lado.
- **A las fieras.** Cada segundo el poblado mira si hay un lobo, oso, jabalí, felino, hiena o caimán
  vivo a menos de 25 m de lo más lejano del poblado. Si lo hay, todos corren a su casa, entran,
  cierran y se quedan dentro. Salen 15 s después de dejar de verlo.
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

- **Dormir:** el original viene tumbado en una cama de 1 m y se baja al suelo.
- **Sentado:** en el suelo.
- **Hablar:** se sube 6 cm porque, con las piernas más rectas que el idle, hundía los pies.
- **Pasear:** el paseo relajado de ActorCore, a 1,1 m/s; corre con el del jugador, a 3,5 m/s.
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

## Configuración

`villager_distance` (200 m) en `settlement_settings`.

## Comprobaciones

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
- con una fiera cerca se encierran en casa, y salen cuando se va;
- dos se juntan a charlar;
- lejos se van.

La consola `village` dice cuántos hay cerca y cuántos quedan por vestir.

## Limitaciones

- Esquivar es solo torcer el paso: dos que se encuentran en una puerta o contra una pared se rozan, y
  al jugador lo empuja su cápsula si se le pone delante.
- Sentarse y tumbarse son fundidos desde estar de pie, sin animación de transición.
- La mano no agarra la herramienta fuera de los golpes y de cavar; por eso solo la sacan al trabajar.
- Ante una fiera solo huyen; no se puede pelear con ellos.
- El tiempo es el del sitio del jugador, no el del poblado: valen porque solo hay gente en los
  poblados cercanos. No cambian de ropa con el frío.
- Lo regalado se pierde: aún no va a ninguna parte del poblado.
- La confianza solo sube hablando y regalando; aún no baja por nada.
- Una casa que ha pasado a la partida pierde sus lechos al cargarla, porque son decorado.

# Escalada y velocidades del jugador

El jugador trepa por cualquier pared que no se pueda andar (montaña, roca, árbol o construcción de
bloques) y la corona si arriba hay sitio para ponerse de pie. Una pared más baja que la cabeza se sube
sin colgarse. Trepar gasta aguante; si se acaba, se suelta y cae. Lo lleva
`scripts/player/climb_controller.gd` (`ClimbController`, hijo del jugador como `PlayerCombat`).

## Controles

| Acción | Tecla |
| --- | --- |
| Agarrarse o subirse encima | Empujar contra la pared y E (USAR), también en el aire |
| Subirse a una pared baja del terreno | Empujar contra ella (sin E) |
| Subir / bajar | W / S |
| De lado | A / D (según la cámara) |
| Soltarse | Espacio |

- Empujando contra una pared a la que se puede agarrar, la E agarra antes que recoger o usar lo que
  haya cerca (`ClimbController.request_grab`). Quieto, o sin pared delante, es USAR de siempre.
- Se agarra a lo que sea más empinado que `floor_max_angle` (50°) y menos que un techo (110°): terreno,
  rocas, árboles, construcciones fijas y barcos (lo que se trepa va con el casco mientras se mueve).
  No a criaturas ni a otros cuerpos sueltos.
- Si la pared sigue a la altura de la cabeza, se agarra. Si es más baja pero más alta que un escalón
  (`StepUpSystem.max_step_height`, 0,55 m), se sube encima con `climb_top` empezado a esa altura, sin
  colgarse; también saltando contra ella. Si es del terreno no hace falta la E: basta con empujar de
  frente contra ella `GRAB_DELAY` (0,2 s) andando, o saltar contra ella (cayendo no, para no
  agarrarse a cada cornisa al pasar). Las construcciones (cuerpos con `grid_id`) y los barcos piden
  siempre la E, para no subirse a una borda o un muro al andar pegado a ellos. Más baja que un
  escalón, la sube el cuerpo solo.
- Cuando la pared se acaba por encima de la cabeza, corona con `climb_top`. Acaba de pie donde lleva
  el clip (1,1 m por dentro del borde) o, si el suelo de arriba se acaba antes (un muro fino), en
  medio de lo que hay. Si arriba no hay suelo que se pueda andar con sitio para ponerse de pie, no
  sube más (sigue colgado).
- De lado solo se mueve si la pared sigue por ese lado: en una esquina se para con el costado en
  ella. En diagonal se mezclan las animaciones.
- Al llegar abajo bajando, se pone de pie. Si la pared se tumba hasta poder andarla, también.
- Se suelta si se queda sin pared, sin aguante, cae al agua o recibe un golpe que le hace tambalearse.
  Tras soltarse puede volver a agarrarse (E otra vez) pasado `REGRAB_COOLDOWN` (0,5 s).
- En la pared no se golpea, ni se apunta, ni se recoge nada, y el arma va escondida.

## Velocidades

| Paso | Velocidad | Animación | Ritmo |
| --- | --- | --- | --- |
| Andar | 0,6 m/s | `walk_relaxed` (0,50 m/s a ritmo 1) | 1,2 |
| Correr | 4,0 m/s | `running`, `running-torch` (4,3 m/s) | 0,93 |
| Esprintar | 6,0 m/s | `sprinting` (4,4 m/s) | 1,36 |
| Trepar | 0,6 m/s (la de andar) | `climb_up`, `climb_down` (0,76 m/s) | 0,8 |
| Trepar de lado | 0,6 m/s | `climb_left`, `climb_right` (0,46 m/s) | 1,3 |

Cada animación se reproduce al ritmo que hace coincidir sus pies con la velocidad (la velocidad del
clip a ritmo 1 es lo que retrocede el pie apoyado, o lo que avanza la mano que agarra al trepar,
medido sobre el esqueleto del jugador). Lo fija `PlayerController._setup_gaits` con los TimeScale
`walk_scale`, `run_scale`, `run_torch_scale` y `sprint_scale` del árbol. Los NPCs no cambian: usan
`Movement.speed` y no esprintan.

`floor_max_angle` del jugador pasa de 60° a 50°: más empinado ya no es suelo (se resbala) y se trepa.

## Aguante

Correr gasta 2/s y esprintar 11/s (`RUN_DRAIN`, `SPRINT_DRAIN` de `PlayerCombat`); mientras se
corre no se recupera, ni siquiera agotado: para descansar hay que andar o pararse.
Trepar gasta 5/s, colgado quieto 2,5/s (`CLIMB_DRAIN`, `HANG_DRAIN`). Con los 100 de aguante da para
unos 20 s trepando (12 m). Coronar no gasta. Sin aguante no se puede agarrar hasta recuperar un poco
(como el resto del combate).

## Caídas

Agarrarse cayendo para la caída, y su golpe (daño y pierna rota, como al aterrizar:
`PlayerController.take_fall_hit`) llega al agarrarse. Los primeros `GRAB_MARGIN` (3,5 m) se perdonan:
soltarse y volver a agarrarse un poco más abajo sale gratis. Pasado el margen, el golpe es el de un
aterrizaje que llega al umbral de daño (`fall_damage_min_speed`, unos 6 m) y sigue cayendo lo que
pase del margen: agarrarse a los 7 m duele como aterrizar desde casi 10. Con la pierna rota sigue
agarrado y puede acabar de subir, pero ya no vuelve a agarrarse. Lo que se cae después de agarrarse
cuenta desde ahí (`Movement.end_fall`).

El agua también para la caída: lo que se traía cayendo al zambullirse no se cobra al salir.

## Animaciones

`tools/combat/retarget_mixamo.gd` reorienta las tres de `models/player/mixamo/climbing/` (mismo
personaje de Character Creator que las de combate) a la librería `combat`:

- `climb_up` y `climb_down`: ciclos en el sitio que conservan el vaivén de la cadera. La de bajar
  venía 1,36 m más alta y 0,10 m más lejos de la pared: se lleva al marco de subir (opción `offset`)
  para mezclarlas sin saltos. Quieto, el ciclo se para donde iba.
- `climb_left` y `climb_right`: Braced Hang Shimmy, que va hacia la izquierda; la derecha es su
  espejo (opción `mirror`). Venía 0,58 m más alta y 0,19 m más lejos de la pared que subir: también
  se lleva a su marco.
- `climb_top`: acaba de pie en el origen (opción `end_at_origin`). El recorrido lo hace el cuerpo
  siguiendo la cadera, así que la cámara sube con el personaje.

Van en un canal encima de todo el árbol (`ClimbController.build`, llamado desde
`PlayerCombat._setup_action_channels`).

Trepando, la física es la normal: sin gravedad y en modo flotante, `move_and_slide` sube o baja la
cápsula por la pared mientras la aprieta contra ella, y lo que toca dice dónde está la pared (y si
se ha llegado al suelo). Como al correr, la animación se casa con el cuerpo con dos medidas suyas: la
velocidad de los apoyos (`UP_CLIP_SPEED`, `DOWN_CLIP_SPEED`, `SIDE_CLIP_SPEED`) y a qué distancia
por delante de los pies toca la pared (`CLIMB_WALL`, 0,36 m). `PlayerModel` se pone a esa distancia
de la pared e inclinado con ella; la cápsula se queda a su radio.

Al coronar, el clip empieza con su cadera donde está la del personaje y acaba de pie arriba
(`_find_stand`). Colgado, empieza por el principio; desde el suelo o en el aire, por el instante en
que su cadera está tan por debajo del borde como la del personaje (`_ledge_start`): a una cornisa de
1,3 m entra a los 0,8 s, ya tirando de los brazos.

Dónde ponerse de pie se busca con rayos hacia abajo cada `TOP_STEP` (0,1 m), del borde hacia dentro
hasta donde lleva el clip. Vale el primer tramo seguido de suelo que se pueda andar, con sitio para
ponerse de pie y sin saltos de más de un escalón entre rayo y rayo. Si llega hasta el final del clip
(una cima ancha), ahí; si se acaba antes (un muro fino), en su mitad. No cuenta:

- el suelo del otro lado de un muro (está por debajo de un escalón sobre los pies, o lejos del borde);
- lo que queda encima de un techo bajo o del muro sobre una ventana: bajo cada rayo vale el suelo más
  bajo (`_ground_under`), que es al que se llega desde el borde, y ahí no hay sitio para ponerse de
  pie.

Lo que el borde no casa con el clip (más cerca en un muro fino, más alto o más bajo) lo corre el marco
de PlayerModel a la par que avanza la cadera (`_frame_at`): lo de frente mientras pasa por encima del
borde (colgada no avanza, así que las manos no resbalan) y lo de alto mientras sube. El cuerpo, y
con él la cámara, sigue a esa cadera y no choca mientras corona. Acaba cuando la cadera del clip se
queda de pie (`TOP_SETTLE`, a los 3,2 s de los 4 que dura) y lo que queda se funde a la locomoción.

Al agarrarse o pasar a coronar, lo que se ve se funde desde la pose anterior en 0,25 s; al soltarse,
vuelve a la locomoción en 0,3 s.

## Ajustes

De la animación: `UP_CLIP_SPEED`, `DOWN_CLIP_SPEED`, `SIDE_CLIP_SPEED`, `CLIMB_WALL`, `TOP_SETTLE`.
De juego: `CLIMB_DRAIN`, `HANG_DRAIN`, `GRAB_MARGIN`, `MAX_WALL_ANGLE`, `STICK_SPEED`,
`REGRAB_COOLDOWN`. De coronar: `TOP_EDGE`, `TOP_STEP`. La altura de la cabeza y el alcance de lado
salen de la cápsula; el escalón, de `StepUpSystem`.

## Límites

- De lado se usa un desplazamiento colgado de un borde (shimmy): en pared lisa las manos van a la
  misma altura, algo despegadas de presas que no existen.
- No se trepa desde el agua (para subir a un barco nadando está salir del agua con Espacio).
- De lado no se doblan esquinas: se para en ellas y hay que soltarse.
- Coronar no busca el borde con las manos: en un muro fino o en una cornisa baja las manos se apoyan
  donde dice el clip, algo más allá o más acá del borde.

## Comprobaciones

```sh
godot --headless --path . res://tests/player/test_climb.tscn
```

Contra cajas estáticas como las de una construcción: corona un muro fino y acaba encima; en una cima
ancha, donde lleva el clip; se sube a una cornisa de 1,3 m con el clip empezado a su altura y a un
muro bajo y fino sin pasar al otro lado; no trepa un escalón ni una cornisa con un techo encima; y el
marco del clip sale de la cadera del personaje y acaba donde se pone de pie.

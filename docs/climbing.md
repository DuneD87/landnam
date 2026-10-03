# Escalada y velocidades del jugador

El jugador trepa por cualquier pared que no se pueda andar y la corona si arriba hay sitio para
ponerse de pie. Trepar gasta aguante; si se acaba, se suelta y cae. Lo lleva
`scripts/player/climb_controller.gd` (`ClimbController`, hijo del jugador como `PlayerCombat`).

## Controles

| Acción | Tecla |
| --- | --- |
| Agarrarse | Empujar contra la pared (andando, 0,2 s; en el aire, al momento) |
| Subir / bajar | W / S |
| De lado | A / D (según la cámara) |
| Soltarse | Espacio |

- Se agarra a lo que sea más empinado que `floor_max_angle` (50°) y menos que un techo (110°): terreno,
  rocas, árboles, construcciones fijas. No a criaturas ni a barcos (cuerpos que se mueven).
- Solo se agarra si la pared sigue a la altura de la cabeza; una más baja se salta.
- Cuando la pared se acaba por encima de la cabeza, corona con `climb_top` si donde acaba el clip hay
  suelo que se pueda andar y sitio para ponerse de pie; si no, no sube más.
- De lado solo se mueve si la pared sigue por ese lado. En diagonal se mezclan las animaciones.
- Al llegar abajo bajando, se pone de pie. Si la pared se tumba hasta poder andarla, también.
- Se suelta si se queda sin pared, sin aguante, cae al agua o recibe un golpe que le hace tambalearse.
  Tras soltarse no se vuelve a agarrar hasta dejar de empujar o tocar suelo.
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

Coronar no se casa con el borde: el clip empieza con su cadera donde está la del personaje y acaba de
pie en el suelo que haya donde termina (un rayo). La diferencia se funde en el primer cuarto de
segundo, así que las manos no siempre dan en el borde. El cuerpo no choca mientras corona.

Al agarrarse o pasar a coronar, lo que se ve se funde desde la pose anterior en 0,25 s; al soltarse,
vuelve a la locomoción en 0,3 s.

## Ajustes

De la animación: `UP_CLIP_SPEED`, `DOWN_CLIP_SPEED`, `SIDE_CLIP_SPEED`, `CLIMB_WALL`. De juego:
`CLIMB_DRAIN`, `HANG_DRAIN`, `GRAB_DELAY`, `MAX_WALL_ANGLE`, `STICK_SPEED`, `REGRAB_COOLDOWN`. La
altura de la cabeza y el alcance de lado salen de la cápsula.

## Límites

- De lado se usa un desplazamiento colgado de un borde (shimmy): en pared lisa las manos van a la
  misma altura, algo despegadas de presas que no existen.
- No se trepa desde el agua ni por barcos en movimiento.
- Coronar no se casa con el borde (manos que no dan en él, o un pequeño salto al empezar).

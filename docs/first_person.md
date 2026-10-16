# Primera persona

Acercando la cámara con la rueda hasta `fp_threshold` (0,5 m) se pasa a primera persona; alejándola
más de 1 m se vuelve a tercera. En primera persona se ve el mismo cuerpo que en tercera, sin la
cabeza: brazos, piernas, el arma, la antorcha, la armadura, las heridas y la sombra entera. Las
animaciones son las de tercera persona; lo que sigue las adapta a la cámara en la cabeza.

## La cabeza

`CharacterAppearanceRig.set_first_person` deja la cabeza solo en la sombra:

- La cámara ve `FirstPersonBody`, otro `MeshInstance3D` con la malla de `Mesh_0` y una piel cuyas
  uniones de la cabeza (y lo que cuelga de ella) se encogen a una milésima sobre la articulación
  del cuello. Toma la malla de `Mesh_0` en cada fotograma (otro cuerpo, un miembro cortado) y lleva
  `no_dismember`: `Dismemberment` corta `Mesh_0`, no la copia. No da sombra.
- `Mesh_0`, ojos, dientes, lengua, cejas, pestañas, pelo, barba y lo que cubre el pelo (capuchas,
  cascos) pasan a `SHADOWS_ONLY`: la sombra conserva la cabeza.

## La cámara

`CameraController` pega la cámara a la cabeza en cada fotograma, en `skeleton_updated`: es la pose
final, con las IK y las proporciones del cuerpo (fuera de esa señal el esqueleto ya ha vuelto a la
pose de la animación). Va con lo que se dibuja: el jugador interpolado entre ticks de física
(`get_global_transform_interpolated`) y la pose de este fotograma. En primera persona la cámara va
`top_level` y sin interpolación de física; al volver a tercera la recupera.

El punto es `first_person_eye(fp_eye_forward)`: entre los ojos (el centro de la malla de los ojos,
en el espacio del hueso de la cabeza) y movido `fp_eye_forward` metros a lo largo de la cara. A
-0,1 queda hacia el centro del cráneo, donde girar la cabeza apenas mueve la cámara. Sin
suavizado: en los golpes la cabeza va a 1,8 m/s (combo de espada) y hasta 6 m/s (pesado), y
cualquier retraso la saca de la cabeza.

El giro es siempre el del ratón. Agachado no se resta `crouch_drop`: la cabeza ya la baja la
animación.

## El cuerpo y la mirada

- **LookAtIK** usa `first_person_weights` (tronco 0,3 + 0,3, cuello 0,15, cabeza 0,25 en vez de
  0,15 + 0,15, 0,25, 0,45): el tronco se lleva más giro y brazos y arma suben y bajen con la mirada.
- **Giro en el sitio**: quieto (también nadando), el cuerpo no se mueve hasta que la mirada se
  aparta 50° (`FP_TURN_START`) de su frente, y entonces se gira hasta ponerse de cara. Andando se
  orienta a la cámara a ritmo 8 (3 en tercera persona).
- **La vista nunca pasa de 90° del frente del cuerpo** (`FP_VIEW_GAP`); más allá, la cámara en la
  cabeza vería la espalda. Si el cuerpo puede girar (quieto, andando, nadando, en guardia,
  apuntando), se arrastra con la vista cuando un giro brusco del ratón le saca ventaja. Si no
  (en pleno golpe, tambaleándose, muerto, trepando), se para el ratón
  (`CameraController.fp_yaw_limit`): no deja apartar más la vista, pero tampoco la mueve sola si
  ya estaba más lejos. Rodando no se toca: la voltereta gira el cuerpo de golpe hacia donde rueda.
- **FirstPersonSquare** (`scripts/player/first_person_square.gd`), un `SkeletonModifier3D` antes de
  `FootIK` y `LookAtIK`, gira el cuerpo entero sobre la cadera para que el pecho (la línea de los
  hombros) mire al frente del modelo. Los golpes de espada tuercen el pecho hasta 70° a cada lado
  y el pesado da la vuelta entera: sin él, la cámara en la cabeza mira por encima del hombro. Brazo
  y arma conservan su recorrido respecto al pecho, y la hoja que hiere es la que se ve. Solo gira en
  el plano del suelo del modelo. Está puesto quieto, andando, golpeando y en guardia, y se funde
  fuera (0,15 s) rodando, apuntando, tambaleándose o muerto, donde manda la animación, `CombatPose`,
  `HitReact` o el ragdoll.
- **Dirección del golpe**: en primera persona sale hacia donde se mira, no hacia donde se mueve (salvo
  con objetivo fijado), para que el cuerpo no se ponga de lado. Con objetivo fijado el cuerpo mira
  siempre al fijado, también moviéndose (en tercera, se encara a donde va).

## Rodar

La voltereta da una vuelta entera y, rodando hacia atrás o de lado, el cuerpo se gira de golpe hacia
donde rueda: con la cámara en la cabeza se vería la espalda y el cuerpo dando vueltas alrededor.
Mientras rueda (`PlayerCombat.roll_progress`, interpolado entre ticks como el cuerpo que se dibuja),
`CameraController._follow_roll`:

- Separa la cámara de la cabeza: va por el eje del cuerpo, baja hasta `fp_roll_dip` (0,6 m del suelo) a
  mitad de la voltereta y vuelve a subir. Al empezar sale de donde estaba (también si encadena otra
  voltereta) y, al acabar, vuelve a la cabeza en `FP_ROLL_RETURN` (0,18 s).
- Deja la vista en el ratón, algo inclinada hacia donde rueda: hacia delante baja hasta 10°, hacia
  atrás sube (a 0,6) y de lado se ladea hasta 9° hacia ese lado, más a mitad de la voltereta.
- Quita de la vista el cuerpo, la ropa y lo que lleva en las manos (`PlayerController.hide_body_in_first_person`):
  lo que da sombra pasa a solo sombra y lo que no, se esconde. La sombra sigue entera.

Acabada la voltereta, el cuerpo se pone de cara a la vista (`PlayerCombat._set_state`) antes de volver
a enseñarse. El paso atrás (quieto) sigue con la cámara en la cabeza: no gira el cuerpo.

## Golpes

Los golpes son animaciones de tercera persona: los tajos pasan a la altura de la cintura y el pecho,
por debajo de lo que ve la cámara en la cabeza o pegados al borde, y en algunos el tronco se echa hacia
delante con la cabeza atrás, de modo que la cámara queda detrás del cuello y el pecho llena media
pantalla. Dos correcciones, solo en primera persona:

- **La hoja en la vista** (`CombatPose._apply_fp_reach`, mientras golpea a una criatura; talando o
  picando no): si la mitad de la hoja (`fp_blade_mid`, entre `blade_start` y `reach` del arma) se
  aparta más de `FP_REACH_VIEW` del centro de la vista (30° a los lados, 20° hacia abajo), el brazo
  entero gira sobre el hombro lo justo para meterla, sin doblar el codo, y la mano gira al revés: la
  hoja conserva su giro y su recorrido. Con un arma a dos manos la izquierda la sigue. Entra y sale en
  `PlayerCombat.FP_REACH_BLEND` (0,12 s). La hoja que hiere es la que se ve, así que los golpes van
  hacia donde se mira: mirando abajo, a un lobo, también bajan (con `LookAtIK`).
- **La cámara por delante de los hombros** (`CombatPose.shoulder_clearance`, en `CameraController`):
  se adelanta en horizontal lo justo para quedar `FP_SHOULDER_CLEAR` (5 cm) por delante del cuello y
  las clavículas. De pie no se mueve; en el golpe horizontal llega a unos 20 cm. Trepando no se aplica:
  mirando arriba la cabeza también va atrás y la cámara se metería en la pared.

## Apuntar

- **Tirachinas** (`CombatPose`, `aim_style` `sling`): se apunta por la horquilla. `PlayerCombat` le pasa
  a la pose el ojo de la cámara (`fp_eye`) y apunta desde él (`_aim_dir`), no desde el pecho. El puño
  izquierdo va en la línea de mira, por debajo `SLING_SIGHT_DROP` (0,16 m: la mira cae entre las puntas
  de la horquilla), tan lejos como llega el brazo casi recto; los nudillos de la derecha tensan hasta
  la mejilla (`SLING_FP_ANCHOR`), así que la goma va del borde de abajo a la horquilla. En tercera
  persona el puño también cierra el mango (`ArcheryPose.GRIP`) y la derecha pinza la badana.
- **Arco y lanza**: la pose es la de tercera persona. Con la lanza, el asta entra por la derecha con la
  punta junto al blanco y el brazo izquierdo lo señala; al cargar baja a la esquina de abajo.

## Ajustes

| Ajuste | Dónde | Valor |
| --- | --- | --- |
| `fp_threshold` | `CameraController` | 0,5 m |
| `fp_eye_forward` | `CameraController` | -0,1 m |
| `fp_roll_dip` | `CameraController` | 0,6 m |
| `FP_ROLL_RETURN` | `CameraController` | 0,18 s |
| `FP_ROLL_PITCH`, `FP_ROLL_BANK` | `CameraController` | 10°, 9° |
| `SLING_SIGHT_DROP` | `CombatPose` | 0,16 m |
| `SLING_FP_ANCHOR` | `CombatPose` | 0,03, -0,08, 0,11 m |
| `FP_REACH_VIEW` | `CombatPose` | 30°, 20° |
| `FP_SHOULDER_CLEAR` | `CombatPose` | 0,05 m |
| `FP_REACH_BLEND` | `PlayerCombat` | 0,12 s |
| `first_person_weights` | `LookAtIK` | 0,3, 0,3, 0,15, 0,25 |
| `FP_TURN_START` | `PlayerController` | 50° |
| `FP_SQUARE_BLEND` | `PlayerController` | 0,15 s |
| `FP_VIEW_GAP` | `PlayerController` | 90° |

## Pruebas

```
godot --headless --path . --script res://tests/character/test_character_appearance.gd
godot --headless --path . --script res://tests/character/test_first_person.gd
godot --path . --script res://tests/character/first_person_preview.gd -- --tag=x
```

`test_character_appearance` comprueba el cuerpo de primera persona, la piel plegada, las sombras y el
punto del ojo. `test_first_person`, que `FirstPersonSquare` mantiene el pecho al frente en el combo y
el pesado de la espada. `first_person_preview` guarda en `build/character/first_person_<tag>.png` la
vista desde la cabeza con varias animaciones y golpes, y una desde fuera; `--loose` quita
`FirstPersonSquare`. Para las poses de combate desde el ojo, `anim_stage` con la vista `eye`
(`--scene=sling --views=eye,front`, `--scene=combo --views=eye --pitch=-10`; ver
[combat.md](combat.md#pruebas)).

## Pendiente

- La preparación de algunos golpes (alzar la espada sobre la cabeza) queda fuera de la vista.
- Tambalearse, morir y escalar: la cámara sigue a la cabeza tal cual.
- El arma atraviesa las paredes al pegarse a ellas.

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

## Ajustes

| Ajuste | Dónde | Valor |
| --- | --- | --- |
| `fp_threshold` | `CameraController` | 0,5 m |
| `fp_eye_forward` | `CameraController` | -0,1 m |
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
`FirstPersonSquare`.

## Pendiente

- Golpes que apenas se ven desde la cabeza (el segundo del combo de espada, el horizontal).
- Rodar, tambalearse, morir y escalar: la cámara sigue a la cabeza tal cual. Rodando hacia atrás o
  de lado se ve la espalda.
- Apuntar con arco, tirachinas y lanza: la pose de apuntar es la de tercera persona.
- El arma atraviesa las paredes al pegarse a ellas.

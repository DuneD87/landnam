# Pesca

Fabrica la caña en el banco de trabajo de piedra (3 ramas y 6 fibras vegetales),
los anzuelos a mano (1 hueso y 1 sílex producen 4) y el cebo a mano (1 carne cruda
produce 6 porciones). Equipa la caña en la mano derecha y lleva anzuelos y cebo
en el inventario.

- Mantén el clic izquierdo: aparece un marcador delante de la vista que avanza
  desde 3 hasta 22 metros en 1,5 segundos. Al llegar al máximo se queda ahí.
- Suelta para lanzar. El marcador verde indica agua válida; el rojo indica
  terreno seco, agua poco profunda o una zona del terreno que aún no está cargada.
  El anzuelo queda a 1,2 m: unos 1,6 m de agua libre bastan para lanzar.
- La caña hace el gesto de lanzamiento y la boya sigue una trayectoria en arco.
  El sedal va desde la punta de la caña hasta la boya.
- Un pez del hábitat a menos de 18 metros del cebo se acerca nadando, respetando
  sus colisiones. La boya tiembla mientras pica; al cabo de 1,2 segundos tiene
  un 65 % de probabilidad de engancharse. Sin peces cercanos no hay picadas.
- Cuando se engancha aparecen una alerta y ondas naranjas en el agua; la caña
  se dobla y su punta se ilumina. Mantén el clic izquierdo para recoger a
  3 m/s. Si dejas el sedal sin recoger durante 5 segundos, el pez escapa.
- Al acercarlo al jugador o a la orilla próxima recibes un pescado crudo.
  Se puede asar durante 30 segundos en una hoguera y comerlo.
- Clic derecho retira el aparejo. También se puede retirar con clic izquierdo
  antes de que el pez se enganche.

Apuntar o cancelar la carga no gasta materiales. Cada lanzamiento válido gasta
un cebo y reserva un anzuelo; el anzuelo vuelve al inventario al terminar,
incluidos fallos y escapes. Lo que no cabe queda en el mundo para recuperarlo.
Cambiar de herramienta, nadar, trepar, recibir un golpe, abrir menús, alejarse o
cambiar de planeta cancela la pesca. Guardar resuelve primero el aparejo; al
morir se incluye en el botín. La pesca en curso no se guarda y no deja boyas al
cargar. Tiburones, ballenas y otros animales marinos grandes no son capturas.

Los peces pescables aparecen a 6–32 m del jugador, normalmente a 1–2,6 m bajo
la superficie. Hay población en costa, lagos, charcas y cauces de río. Se
incorporan con un fundido aunque se esté mirando el agua, y respetan el fondo
al nadar. Ver [ambient_fauna.md](ambient_fauna.md).

`PlayerFishing` coordina entrada, estados, consumo y captura. `FishingRodTrait`
configura alcance, probabilidad y tiempos en el recurso de la caña. `AmbientFish`
reserva y sigue un anzuelo sin abandonar su movimiento normal; `FishingPose`
posa los brazos sobre la locomoción con el modificador `CombatPose`.
`FishingRodVisual` y `FishingFloat` presentan la caña y el aparejo. La boya se
mantiene bajo el terreno y sus destinos se guardan en coordenadas locales para
seguir el origen flotante; su altura sigue el muestreo del oleaje.

Verificación con la build Godot 4.6 con el módulo voxel:

```sh
godot --headless --path . res://tests/player/test_fishing.tscn
godot --headless --path . res://tests/fauna/test_shore_fish.tscn
godot --path . res://tests/player/test_fishing.tscn -- --capture
```

La ejecución con `--capture` guarda una captura en `build/fishing/hooked.png` y también
termina las comprobaciones. Las pruebas cubren recetas, materiales, carga y
lanzamiento, nado del pez, probabilidades extremas, recogida, conservación,
interrupciones, origen flotante y consultas sobre terreno voxel real.

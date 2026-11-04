# Mando

Los mandos reconocidos por Godot usan la distribución estándar del motor. Se pueden conectar
durante la partida y alternar con teclado y ratón. No hace falta activar un modo de mando.
Los nombres siguientes son los de Xbox; en PlayStation A/B/X/Y corresponden a cruz/círculo/
cuadrado/triángulo.

| Control | Acción |
| --- | --- |
| Stick izquierdo | Movimiento analógico; inclinándolo menos se avanza más despacio. |
| Stick derecho | Mirar; con un objetivo fijado, cambiar de blanco. |
| A | Saltar; subir del agua. |
| B | Esquivar. |
| X | Usar, recoger, abrir puertas, agarrarse para trepar. |
| Y | Inventario. |
| LT / RT | Defensa o apuntar / ataque, carga y disparo; también pesca y martillo. |
| Pulsar stick izquierdo | Esprintar mientras se mantiene pulsado. |
| Pulsar stick derecho | Fijar o soltar objetivo. |
| LB | Alternar agachado. |
| RB | Pantalla del personaje y equipo. |
| Cruceta izquierda / derecha | Objeto anterior / siguiente de la barra rápida. |
| Cruceta arriba | Menú de construcción, con el martillo equipado. |
| Cruceta abajo | Fabricación. |
| View / Select | Mapa. |
| Menu / Start | Pausa o cerrar la ventana actual. |

En las ventanas, el stick izquierdo mueve el cursor, A hace clic izquierdo y X clic derecho
(separar montones o depositar unidades). Mantener A permite arrastrar. LB+A equivale a
Mayús+clic para transferir objetos o tomar la mitad según el contenedor. El stick derecho
desplaza las listas; arriba/abajo en la cruceta también desplazan. B vuelve o cierra la ventana;
Y alterna el inventario. El ratón físico sigue disponible.

Con el martillo, LT abre la rueda. Se apunta con el stick derecho y se elige al soltar LT o
pulsar RT. Un toque corto sin apuntar deja la rueda abierta. Start la cierra sin elegir.

En **Opciones → Controles → Mando** se guardan sensibilidad de cámara, inversión vertical y
zona muerta. Los controles del teclado se reasignan por separado y conservan las asignaciones
del mando. La distribución del mando es fija en esta versión. El zoom, el vuelo libre y los
controles específicos de navegación y rotación de bloques conservan sus teclas de teclado.

Prueba automática (eventos simulados, sin necesitar mando conectado):

```sh
godot --headless --path . res://tests/player/test_gamepad.tscn
```

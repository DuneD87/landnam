# Referencias visuales de fauna marina

Revisión de proporciones de septiembre de 2026. Las fotografías se consultan
como referencia anatómica; los modelos siguen siendo geometría procedural
original, con volúmenes suaves, colores simplificados y expresión cartoon.
No se incorporan las fotografías como texturas ni como recursos del juego.

| Modelo | Referencia visual | Aplicación al modelo |
| --- | --- | --- |
| Tiburón blanco | [Monterey Bay Aquarium: 10 cool things about sharks](https://www.montereybayaquarium.org/about-us/stories/10-cool-things-about-sharks) | Hocico ancho que sobresale de la mandíbula; boca corta situada debajo; ojos pequeños integrados en la piel y narinas discretas. |
| Ballena azul | [Scholastic: Biggest Animals Ever!](https://sciencespin36.scholastic.com/issues/2017-18/010118/biggest-animals-ever.html) | Rostro ancho y aplanado, mandíbula larga, ojo pequeño junto al extremo posterior de la boca y cresta central integrada en la cabeza. |
| Orca | [Orca Norway: Our Story](https://www.orcanorway.info/our-story) | Frente redondeada, boca contenida, ojo pequeño por delante y debajo de la mancha blanca alargada. |
| Tortuga verde | [Monterey Bay Aquarium: Green turtle](https://www.montereybayaquarium.org/animals-the-ocean/animals-a-to-z/green-turtle) | Pico corto y romo, mejillas llenas, cuello diferenciado y ojos con párpado superior, colocados más atrás. |

Los ojos se construyen como córneas poco abultadas que siguen la superficie de
la cabeza, con un iris discreto, transición a la piel y reflejo pequeño. Cada
especie tiene posición y proporciones propias. Las bocas tienen recorridos
independientes y una costura fina, evitando aplicar la misma sonrisa a todas.
La mancha de la orca tiene un contorno ovalado de geometría ajustada a la piel,
para evitar el borde escalonado de un patrón pintado solo sobre la rejilla del
cuerpo. El color y el moteado son más suaves para mantener la lectura cartoon.

Las aletas se generan a partir de su planta: bordes de ataque y de salida
curvados en el plano de la propia aleta (convexos o falcados), punta afilada o
redondeada en remo, y sección más gruesa cerca del borde de ataque. Así cada
especie tiene su forma: aleta caudal en media luna en el tiburón, pectorales
anchas y redondeadas (negras por ambas caras) en la orca, pectorales finas de
un séptimo del cuerpo y aleta dorsal diminuta muy atrasada en la ballena azul, y
aletas delanteras largas en forma de ala en la tortuga. El caparazón de la
tortuga es una concha cerrada (espaldar abombado y peto plano) que se estrecha
hacia la cola y se abre solo alrededor del cuello; su reborde no sigue las
ranuras de las placas. Los tubos finos (reborde, costuras de boca y párpados)
comparten un marco por punto para curvarse sin aristas.

Los colores de vértice se eligen como muestras sRGB y el shader los decodifica
a lineal; sin esa conversión la orca se veía gris pizarra y la tortuga pálida.

Cada vértice lleva dos muestras de color (`COLOR` y `CUSTOM0`) y una distancia
con signo en `UV2.x`; el shader muestra la segunda donde la distancia es
positiva, con un borde antialiasado de un píxel. La distancia se interpola
linealmente, así que los contornos se mantienen nítidos a cualquier distancia en
lugar de difuminarse sobre la rejilla del cuerpo:

- **Tiburón blanco**: línea de contrasombreado nítida e irregular, justo sobre la
  boca en la cabeza, baja en branquias y pectorales, alta en el flanco y
  descendiendo hacia el pedúnculo. La boca se define por altura absoluta: vista
  de frente es un arco y de perfil desciende sin sonrisa. Ojo negro mayor,
  hocico cónico sobre la mandíbula, lomo recto, pectorales largas inclinadas
  hacia abajo con punta negra por debajo y cinco ranuras branquiales como
  tubos finos en su pliegue. Piel más mate que la de los cetáceos.
- **Orca**: vientre blanco que se estrecha entre las aletas, lóbulo del flanco
  que sube hacia atrás tras la dorsal (unión suave, sin esquinas) y silla gris
  clara tras la dorsal.

El moteado de la **ballena azul** no tiene bordes definidos y sigue horneado en
el color: manchas amplias y motas finas de bajo contraste. Su cuerpo es más
esbelto (longitud ≈ 6 veces el grosor), con cabeza ancha y plana y pliegues
ventrales hasta el ombligo.

El caparazón de la **tortuga verde** sigue la disposición real de escudos: cinco
vertebrales, cuatro costales por lado y un anillo de marginales. Cada escudo es
la celda de Voronoi de su semilla, teselada desde su centro de crecimiento hasta
sus costuras, que ambos vecinos comparten exactamente; así las costuras son
nítidas, cada placa se abomba ligeramente y las vetas ámbar irradian desde su
centro. Cabeza y aletas llevan escamas oscuras con borde amarillo pálido, y el
borde de salida de las aletas es claro. Las aletas traseras baten con el 40 %
de la amplitud de las delanteras.

El horneado concentra más secciones en las cabezas y conserva una sola
superficie por animal y cinco o seis LOD automáticos. No añade nodos ni colisiones.
Los tamaños del juego se siguen controlando en `SimpleMarineMesh`.

Para revisar las proporciones, ejecutar `tests/fauna/marine_preview.tscn`:
**1–4** seleccionan especie, **H** alterna cabeza/cuerpo, **P** coloca la cámara
de perfil, arrastrar gira y la rueda ajusta el zoom. **0** muestra los cuatro
animales a su escala relativa en el juego. Con `-- --capture` guarda vistas fijas
de cada especie en `build/fauna/marine/`.

Para regenerar:

```sh
godot --headless --path . --script res://tools/fauna/bake_marine_meshes.gd
```

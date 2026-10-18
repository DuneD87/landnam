# Necesidades

Además de la vida y el aguante, el jugador tiene hambre, sed, descanso, cordura,
oxígeno y temperatura del cuerpo (`SurvivalNeeds`, un nodo hijo del jugador).
Todas van de 0 a 1, con 1 = bien (saciado, bebido, descansado, cuerdo, con
aire). La temperatura va de -1 (helado) a 1 (abrasado), con 0 = a gusto.

Se guardan con la partida y se llenan al reaparecer tras morir. En vuelo libre
no corren.

Las compensan comer y beber, la ropa, que abriga, y las hogueras, que calientan,
secan y alumbran. Cómo se consigue cada cosa está en [items.md](items.md).

## Dónde se ven

En la consola de la barra rápida (ver [ui.md](ui.md)):

- **Cordura**: la media orbe violeta del centro, sobre la barra.
- **Hambre y sed**: las dos barras alrededor de la orbe de vida, que arrancan de
  la espiga y la gota.
- **Temperatura y descanso**: las dos barras alrededor de la orbe de aguante,
  que arrancan del termómetro y la luna. La temperatura no se llena: un rombo
  marca dónde estás entre el frío (junto al termómetro, azul) y el calor (al
  otro extremo, rojo).
- **Oxígeno**: solo bajo el agua. Las runas del engaste del aguante («þrek auk
  andi», aguante y aliento) se encienden en azul y se van apagando en el
  sentido de las agujas del reloj. Con poco aire laten en rojo.

Cada barra sale del medallón de su icono y se llena desde él en el sentido de
las agujas del reloj.

Cuando una necesidad está baja, su medallón late en rojo. En la ficha de
atributos (C) salen los valores exactos y los grados que se sienten.

## Reglas

| Necesidad | Baja | Sube | Vacía |
|---|---|---|---|
| Hambre | de lleno a vacío en 45 min; más deprisa con esfuerzo (lo que gasta aguante, nadar) y con frío | — | 0,25 de vida por segundo |
| Sed | en 30 min; más deprisa con esfuerzo y con calor | — | 0,4 de vida por segundo |
| Descanso | en 60 min despierto; algo más con esfuerzo | — | el aguante se recupera al 40 % |
| Cordura | a oscuras (en 40 min de noche cerrada; a la luz de una hoguera, no), muy cansado y con hambre o sed; la carne cruda, un 6 % | de día, si se ha descansado; la carne asada, un 3 % | (sin efectos todavía) |
| Oxígeno | 40 s con la cabeza bajo el agua | en 4 s al sacarla | 8 de vida por segundo |

La vida se quita a golpes de 2 puntos, no a pellizcos. El modo dios (`god`) no
para las necesidades, pero sí el daño.

El aguante también se recupera más despacio con mucho frío (hasta un 40 %
menos) y con hambre o sed (un 30 % menos).

### Temperatura

El cuerpo va hacia la temperatura que siente: tarda un minuto y medio en el
aire y unos 20 s en el agua. Lo que se siente sale de:

- **El sitio**: el frío del clima del planeta, el mismo que pone la nieve
  (latitud, altura y estación). La cota de nieve cae en torno a 0 °C y el
  ecuador, a nivel del mar, a 30 °C.
- **La hora**: 6 °C menos de noche y 3 más a pleno día.
- **El tiempo**, al aire libre: temporal −3, nieve −5, viento −3, niebla −1; a
  cubierto pesa un 30 %. Con el cielo despejado, el sol da 2 °C más.
- **Mojado**: hasta 8 °C menos. Nadar empapa, la lluvia también (en un minuto
  al raso), y se seca en unos 4 minutos, antes de día, con calor y junto al fuego.
- **La ropa puesta**: lo que abriga cada prenda (`InsulationTrait`): el juego de
  pieles entero, 9 °C, y el de cuero, 6 °C. Mojada, abriga un 60 % menos.
- **Una hoguera encendida**: hasta 18 °C a pie de fuego, que se apagan del todo a
  6 m.
- **En el agua**: la del agua, que no pasa mucho de cero en los mares fríos.

Entre 10 y 24 °C se está a gusto (0). Se llega al extremo a −12 °C (−1) y a
40 °C (1). Pasado ±0,85, el frío o el calor quitan vida (de 0,17 a 0,35 por
segundo).

## Comandos de consola

| Comando | Qué hace |
|---|---|
| `needs` | Lista los valores, lo que se siente en °C, si la cabeza está bajo el agua, el agua de los odres y qué agua hay al alcance |
| `needs <nombre> <valor>` | Fija una: `hunger`, `thirst`, `rest`, `sanity`, `oxygen`, `warmth` (de −1 a 1), `wetness` |
| `needs fill` | Todas llenas y a gusto |
| `needs empty` | Hambre, sed, descanso, cordura y oxígeno a cero |
| `needs pause [on\|off]` | Las congela para mirarlas |
| `needs rate <x>` | Las acelera (1 = normal) |

## Pendiente

- Dormir: el descanso solo baja.
- Los efectos de la cordura baja.

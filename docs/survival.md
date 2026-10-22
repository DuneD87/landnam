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

Cuando una necesidad está baja, su medallón late en rojo. El de temperatura
avisa desde **Frío**, cuando empieza a quitar vida. En la ficha de atributos
(C) salen los valores exactos y los grados que se sienten.

## Reglas

| Necesidad | Baja | Sube | Vacía |
|---|---|---|---|
| Hambre | de lleno a vacío en 45 min; más deprisa con esfuerzo (lo que gasta aguante, nadar) y con frío | — | 0,25 de vida por segundo |
| Sed | en 30 min; más deprisa con esfuerzo y con calor | — | 0,4 de vida por segundo |
| Descanso | en una jornada de 16 h del mundo despierto; algo más con esfuerzo | una noche de 8 h durmiendo en un lecho | el aguante se recupera al 40 % |
| Cordura | a oscuras (en 40 min de noche cerrada; a la luz de una hoguera, no), muy cansado y con hambre o sed; la carne cruda, un 6 % | de día, si se ha descansado; la carne asada, un 3 % | (sin efectos todavía) |
| Oxígeno | 40 s con la cabeza bajo el agua | en 4 s al sacarla | 8 de vida por segundo |

La vida se quita a golpes de 2 puntos, no a pellizcos. El modo dios (`god`) no
para las necesidades, pero sí el daño.

El aguante también se recupera más despacio con mucho frío (hasta un 40 %
menos) y con hambre o sed (un 30 % menos).

### Descansar y pasar el tiempo

El descanso alcanza para una jornada: **16 horas despierto y 8 horas de sueño**
forman un día completo. Las horas salen de la duración real de una vuelta del
sol, no de un temporizador independiente; si se cambia la velocidad de
rotación del sol, el cansancio sigue el nuevo día. Con el reloj solar detenido
para depurar, el descanso no baja y no se puede empezar a dormir.

Se fabrica un **lecho de pieles** a mano con 4 ramas, 8 fibras vegetales y
2 pieles. Se planta desde la barra rápida en suelo llano, como una hoguera.
**E** junto a él abre el panel: **Dormir 8 horas** o **Recoger lecho**.

Durmiendo, el cuerpo recupera descanso y hasta un 35 % de cordura en una
noche completa. El consumo de comida y agua baja al 60 % del reposo despierto.
El mundo corre a **×60**: con el día actual de una hora real, ocho horas de
juego pasan en unos **20 segundos**. Se puede pulsar **Despertarse**, **E** o
**Escape** para terminar antes. El tiempo vuelve al ritmo anterior al terminar.

La temperatura y las demás necesidades siguen corriendo. Recibir daño
(incluido el frío), morir, entrar en agua, perder el lecho o salir de la
partida interrumpe el sueño. La reserva de descanso y el lecho se guardan;
al cargar se está despierto y el reloj vuelve a ×1.

`WorldTime` comparte el ritmo del mundo entre el sol y el calendario, las
necesidades, la sucesión del clima, las hogueras (combustible y cocina) y los
estados duraderos. La física, el movimiento, las animaciones y la interfaz
mantienen su ritmo normal. La consola permite reutilizarlo con
`time speed <1-120>`; `time speed 1` vuelve al ritmo normal. La aceleración
de estaciones de `season speed` sigue siendo una herramienta aparte.

`tests/survival/test_rest.tscn` comprueba la jornada, el sueño completo,
interrupciones, vuelta al ritmo anterior, cocina, estados y guardado del lecho.

### Temperatura

El cuerpo va hacia la temperatura que siente: tarda un minuto y medio en el
aire y unos 20 s en el agua. Lo que se siente sale de:

- **El sitio**: el frío del clima del planeta, el mismo que pone la nieve
  (latitud, altura y estación). La cota de nieve cae en torno a 0 °C y el
  ecuador, a nivel del mar, a 30 °C.
- **La hora**: 6 °C menos de noche y 3 más a pleno día.
- **El tiempo que está haciendo**, con la transición entre eventos ya resuelta:
  lluvia hasta −3 °C, nieve hasta −5, viento hasta −3 y niebla hasta −1. Se
  suman según su intensidad. A cubierto no llega precipitación y el viento y
  la niebla pesan un 30 %. El sol aporta hasta 2 °C más, según la luz del
  evento y lo que esté precipitando.
- **Mojado**: hasta 8 °C menos. Nadar empapa, la lluvia también (en un minuto
  al raso a plena intensidad), y la nieve moja cuatro veces más despacio.
  Cuenta lo que cae sobre el jugador: en un claro entre nubes, por encima de
  ellas o bajo techo no se sigue mojando. En zonas frías, la lluvia que cae
  como nieve moja al ritmo de la nieve. Se seca en unos 4 minutos, antes de
  día, con calor y junto al fuego; ponerse a cubierto no seca de golpe.
- **La ropa puesta**: lo que abriga cada prenda (`InsulationTrait`): el juego de
  pieles entero, 9 °C, y el de cuero, 6 °C. Mojada, abriga un 60 % menos.
- **Una hoguera encendida**: hasta 18 °C a pie de fuego, que se apagan del todo a
  6 m.
- **En el agua**: la del agua, que no pasa mucho de cero en los mares fríos.

Entre 10 y 24 °C se está a gusto (0). Se llega al extremo a −12 °C (−1) y a
40 °C (1). Desde **Frío** (temperatura corporal ≤ −0,45) se pierde vida, cada
vez más al enfriarse: de 0,175 a 0,35 por segundo. **Fresco** todavía no
daña. El calor empieza a dañar a partir de +0,85, al mismo ritmo.

La alta montaña y las zonas con nieve o hielo enfrían por el clima del sitio,
aunque no esté lloviendo ni nevando. La ropa y las hogueras elevan la
temperatura sentida y permiten recuperar calor; al salir del estado de frío,
deja de bajar la vida por exposición.

La escena `tests/survival/test_cold_exposure.tscn` comprueba lluvia, nieve,
transiciones meteorológicas, refugio, montaña, hielo, abrigo, fuego, guardado
y daño usando el clima de la Tierra, sin cargar una partida completa.

## Comandos de consola

| Comando | Qué hace |
|---|---|
| `needs` | Lista los valores, lo que se siente en °C, si la cabeza está bajo el agua, el agua de los odres y qué agua hay al alcance |
| `needs <nombre> <valor>` | Fija una: `hunger`, `thirst`, `rest`, `sanity`, `oxygen`, `warmth` (de −1 a 1), `wetness` |
| `needs fill` | Todas llenas y a gusto |
| `needs empty` | Hambre, sed, descanso, cordura y oxígeno a cero |
| `needs pause [on\|off]` | Las congela para mirarlas |
| `needs rate <x>` | Las acelera (1 = normal) |
| `time [speed <1-120>]` | Consulta o cambia la velocidad compartida del mundo |

## Pendiente

- Los efectos de la cordura baja.

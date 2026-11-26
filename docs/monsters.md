# Monstruos

Además de las fieras, el mundo tiene monstruos. Algunos no se pueden matar hasta llegar a eras
futuras: el peligro es topárselos. El primero es Cthulhu.

## Cthulhu

Un gigante de unos 117 m (122 m con las alas) que cruza el mar a pie. No ataca. Lo que hace es
**mirar**: si ve al jugador, este se queda paralizado y pierde la cordura, toda si le sostiene la
mirada. La única forma de morir por él es un accidente: que pase por encima de tu barco.

Cómo se juega: los **presagios** avisan un minuto antes y dan tiempo a esconderse (bajo cubierta,
buceando, lejos de la costa). Si aun así te ve, **no le mires**: aparta la vista o tápate los ojos.

### Cuándo aparece

`CthulhuDirector` (lo crea `PlanetLoader` en planetas con mar, mapa del mundo y clima):

- El jugador tiene que estar **cerca del mar**: agua de mar o de océano de al menos 30 m de fondo
  bajo él o a menos de 700 m (en la costa vale, navegando también).
- Con esa condición sale de media una vez cada **10 h de juego** (`MEAN_INTERVAL`, 36 000 s).
- Después de un encuentro pasan al menos **5 días de calendario** sin otro (`COOLDOWN_DAYS`). Esa espera
  es lo único que se guarda en la partida (`abyss` en los datos del planeta).
- Primero llegan **su tormenta y los presagios** (ver abajo). **60 s después** sale de lo hondo a
  1,3–1,7 km, por donde se le oyó llamar, andando hacia un punto de mar a 200–420 m del jugador, para
  que pase cerca.
- Se hunde andando y se va (y con él la tormenta) cuando está a más de 2,6 km, cuando han pasado
  9 min o 75 s después de mirar al jugador. Un encuentro a medias no se guarda: al cargar no está.

### Presagios

Durante el minuto antes de salir (`CthulhuDirector._omens`):

- **Su tormenta** (el evento de clima `abyss`, forzado): cielo casi negro, lluvia, rayos, algo de
  niebla y la **mitad del oleaje** de `storm`. Entra en los 30 s de transición del clima.
- **El silencio**: las aves posadas cerca echan a volar al empezar. En 15 s se va toda la fauna
  (`AmbientFaunaSpawner.hush`): las aves se pierden de vista y los peces se alejan, como al anochecer.
  A los 10 s sale el aviso «El mar se ha quedado en silencio.». Al irse él, la fauna vuelve en 90 s.
- **El retumbar**: un zumbido grave que late y sube durante todo el aviso.
- **El mar hierve**: desde el 30 % del aviso brotan manchas de borbotones a 25–200 m del jugador, casi
  todas delante de la cámara y nunca bajo un casco. Cada una dura unos segundos y tiene sus burbujas,
  su vaho y un anillo de olas. Son cada vez más seguidas y más grandes.
- **La llamada**: 14 s antes de salir se le oye rugir, apagado, desde el punto por donde va a salir.
  Sale por ahí salvo que el jugador se haya alejado mucho.

### Cómo anda

- Cerca de la costa **pisa el fondo**. En lo hondo **vadea con el agua por la cintura** (52 m bajo
  el agua); el fondo no se ve.
- No se acerca a menos de 14 m de fondo. Si tiene la costa delante (260 m), frena y gira más deprisa.
- Anda a unos 10 m/s, con la animación de andar a 0,6× para que pese.
- Cada 70–140 s se para: a veces en reposo y a veces **despliega la amenaza** (alas y tentáculos),
  rugiendo.

### Agua y sonido

- **Al salir le chorrea el agua**: gotas que caen hasta el mar desde los hombros, los brazos, las garras,
  los bordes de las alas, la barba y la cola, con su sonido de cortina de agua. Se escurre en 45 s
  (`DRAIN_TIME`).
- **Espuma** donde las piernas y la cintura cortan el agua al andar, y un **reventón** en cada pisada y
  al asomar la cabeza.
- Es `AbyssSpray`: los shaders de los rociones (`OceanSpray`), con nubes de metros y gotas de un palmo.
  Más allá de 2,5 km de la cámara no se emite.
- **Sonido propio** (`tools/audio/build_cthulhu_sounds.py`): el rugido (león, oso, caimán y algo de
  elefante, bajados de tono, con un sub grave y la reverberación del mar abierto), la pisada (un golpe
  sub, el agua que revienta y la ola), la cortina de agua y el retumbar (bucles 3D suyos, fuertes al
  salir y al hundirse). Los clips son CC0 (ver [créditos](monster_audio_credits.md)).

### Olas

- **Al andar**: la cintura corta el agua como una proa ancha (estela de casco en `HullWaves`, que se
  dibuja hasta 2,5 km).
- **En cada pisada**: un anillo donde la espinilla corta el agua, de 1,3 m, que corre a 7,5 m/s
  durante 14 s.
- **Al asomar la cabeza** al salir: un anillo grande.
- Los anillos levantan y apartan de verdad los barcos al llegarles, por el lado que reciben primero
  (`Cthulhu._update_rings`). La flotación no ve las olas de `HullWaves`; esto lo suple.

### La mirada

Ve al jugador si se cumple todo esto, durante 0,8 s seguidos:

- Está a menos de 750 m y dentro de 110° de su frente.
- Hay **línea de visión** entre sus ojos y la cabeza o el pecho del jugador: nada en medio, ni una
  cubierta, ni una pared, ni el terreno. **Bajo cubierta no te ve**.
- El jugador no está con la cabeza más de 1,2 m bajo el agua (**buceando no te ve**).

Esconderse sirve sobre todo **antes** de que te vea. Una vez te ha visto:

1. Ruge, se para, se gira hacia el jugador y lo mira (animaciones Alerta y La mirada del abismo).
   El lomo, el pecho, el cuello y la cabeza giran por código (`CthulhuLookAt`) para clavar la cara
   en el jugador.
2. El jugador queda **paralizado** (`AbyssStare`, `PlayerController.is_transfixed`): sin moverse,
   sin acciones y sin timón. El cuerpo sigue con la gravedad, el agua y el barco. La vista **tira** sola
   hacia sus ojos, se cierra el encuadre, el mundo se retuerce y late el corazón. Sale el aviso «No le
   mires a los ojos. Aparta la vista o tápatelos (clic derecho).».
3. **No le mires.** En los ~7 s que dura, la cordura cae según lo que se le mire:
   - Con sus ojos a menos de 9° del centro de la vista, un 24 % por segundo: sostenerle la mirada la
     vacía entera.
   - Desde 38°, un 1,5 % por segundo: apartando la vista se pierde poco más de un 10 %.
   - El ratón gira la cámara al 60 % contra el tirón, que es proporcional al ángulo y tiene un tope de
     70°/s: se le puede ganar.
   - **Taparse los ojos** (clic derecho, el botón de la guardia): todo se queda casi negro, con algo de
     luz rojiza entre los dedos. Pasa un 10 % y el tirón baja al 35 %.
   - Si algo se pone en medio (una cubierta, la cabeza bajo el agua), no cuenta: él sigue comprobando
     la línea de visión mientras mira (`Cthulhu.target_visible`).
   - Con la vista apartada el efecto de pantalla y el latido bajan: así se nota que funciona.
4. Al acabar quedan **secuelas** (distorsión suave y latido): 3 min si se perdió un 60 % o más de
   cordura, menos si se perdió menos. Mira una sola vez por encuentro; después sigue andando y se va.

Lo que hace la cordura baja después está en [survival.md](survival.md#cordura-baja).

`notarget` hace que no vea al jugador.

### Accidentes

Las piernas, el cuerpo, la cola y los antebrazos son cápsulas (`Cthulhu.LIMBS`). Si una toca un barco:

- Le arranca el casco: `apply_damage_at` con 600 000 J en 5 m, cada 0,25 s mientras toca.
- Lo empuja hacia un lado y hacia delante.

Si el pecho del jugador queda dentro de una cápsula, muere aplastado (respeta `god`).

### Consola

| Comando | Qué hace |
|---|---|
| `cthulhu` | Dónde está, en qué estado, o cuánto falta para que pueda volver |
| `cthulhu spawn` | Trae la tormenta y lo saca en 6 s, a la distancia normal (los presagios, apretados) |
| `cthulhu omen` | Igual, con el minuto entero de presagios |
| `cthulhu gaze [distancia]` | Lo planta fuera del agua delante del jugador (420 m por defecto), mirándolo |
| `cthulhu leave` | Lo hunde |
| `cthulhu reset` | Lo quita y borra la espera entre encuentros |
| `weather abyss` | Solo la tormenta |

### Modelo

- La fuente es `~/Descargas/Cthulhu_Abyssal_Dreadwing_v6.blend` (Meshy, riggeado a mano).
- Se exporta con `tools/monsters/blender/export_cthulhu.py` a `models/monsters/cthulhu/cthulhu.glb`:
  solo el rig y la malla, con las acciones renombradas (`idle`, `walk`, `alert`, `threat`, `gaze`,
  `sweep`, `turn_l`, `turn_r`).
- Los bucles cierran con una copia de la primera pose, así que en Godot duran exactamente el ciclo.
- Mira a +Z. Escala ×72 en el juego.

```
blender -b ~/Descargas/Cthulhu_Abyssal_Dreadwing_v6.blend \
    -P tools/monsters/blender/export_cthulhu.py -- models/monsters/cthulhu/cthulhu.glb
```

`sweep` y los giros están exportados pero no se usan todavía.

### Pendiente

- Que compañeros y aldeanos reaccionen (huir, esconderse, perder cordura).

## Esbirros (Abyssal Maw)

Criaturas de 1,58 m que viven en comuna sobre Cthulhu. Cuando él anda cerca del jugador saltan al mar,
nadan deprisa dejando estela y van a por el jugador y sus compañeros para comérselos.

### La comuna

`CthulhuBrood` (la crea Cthulhu) lleva **8** posados en su piel: en los hombros, los brazos, la base de
las alas y el lomo, cada uno pegado a su hueso. Los sitios salen de `data/monsters/cthulhu_perches.json`,
que calcula `tools/monsters/build_cthulhu_perches.gd`: puntos de la malla que miran hacia arriba (o
hacia atrás en el lomo), por encima del agua. Hay que rehacerlo si cambia el modelo de Cthulhu. Los
posados son modelos ligeros que solo respiran, y no se animan a más de 450 m de la cámara.

- **Cuándo saltan**: con el jugador a menos de **700 m** de Cthulhu (`LAUNCH_RANGE`, en horizontal desde
  donde corta el agua), o en cuanto él lo ve, esté a la distancia que esté. Solo mientras anda, se para
  o mira; no mientras sale o se hunde. Una sola oleada por encuentro.
- **El salto**: uno tras otro, cada 0,15–0,6 s. Cada uno se agacha (el principio del clip `leap`) y en
  el impulso deja su sitio a un esbirro de verdad que sale disparado hacia su presa: a 16–24 m/s, 5–9 m/s
  hacia arriba, más lo que avance Cthulhu. Cae al mar con salpicadura, anillo de olas y sonido.
- **La presa**: el jugador o uno de sus compañeros vivos cerca, al azar; el jugador cuenta doble.

### El esbirro

`Minion` (`scenes/monsters/Minion.tscn`) es una fiera más, sobre `NPCController`: persigue con
`CombatState` (perfil `data/fauna/combat/minion_combat.tres`), ve a 500 m y, si mata a alguien, se lo
come como las fieras (`Devouring`, clip `devour`). Lo que tiene de suyo:

- **No suelta a su presa**: la huele a 1,5 km (`PREY_SENSE`) aunque no la vea, y si se queda parado
  vuelve a por ella. Solo la suelta cuando muere.

- **Nada**: en agua honda flota con la espalda a flor de agua (en el sitio, de pie, con la cabeza
  fuera) y va a **9 m/s**. Al tocar fondo en la orilla se pone a correr y, al meterse en agua honda, nada.
  El agua no la esquiva (`AIController.amphibious`).
- **Estela**: es un vadeador de `HullWaves` (se dibuja hasta 450 m) y suelta rocío nadando deprisa. Los
  vadeadores tienen ahora un tope (`MAX_WADERS`, 5, los más cercanos): el resto de huecos queda para
  los barcos.
- **Zarpazos** (`claws`): dos golpes, izquierda en F17 y derecha en F33, de 16 cada uno.
- **Vida** 55; corre a 5,2 m/s en tierra.
- **Sonido**: el del caimán (gruñido, siseo, herida y muerte), de momento.
- Muere cayéndose de lado (una muerte de reserva hecha por código: no hay clip). En el agua se hunde.
- Sus cadáveres duran 90 s. Ido Cthulhu, los que no cazan a nadie se quitan cuando no se ven y están a
  más de 60 m; cualquiera a más de 1,5 km, también.

`spawn minion [n] [distancia]` los pone sueltos delante (en el mar caen al fondo y suben a nado).
`cthulhu minions` hace saltar ya a los que lleva encima.

### Modelo

- La fuente es `~/Documents/Codex/2026-11-26/bue/outputs/Abyssal_Maw_v2_1_Clips.blend` (Blender 5.2).
- Se exporta con `tools/monsters/blender/export_minion.py` a `models/monsters/minion/minion.glb`, con
  los clips renombrados: `idle`, `idle_water`, `swim`, `run`, `climb`, `board`, `leap`, `claws`, `grab`,
  `devour`. A 30 fps. Mira a +Z.
- Los ciclos se ponen en bucle en el juego (`Minion.prepare_clips`).

```
~/tools/blender-5.2.3-linux-x64/blender -b ~/Documents/Codex/2026-11-26/bue/outputs/Abyssal_Maw_v2_1_Clips.blend \
    -P tools/monsters/blender/export_minion.py -- models/monsters/minion/minion.glb
```

### Pendiente de los esbirros

- **Subir a los barcos**: trepar por el casco (`climb`) y remontar la borda (`board`). Ahora, si el
  jugador está en un barco, llegan al casco y se quedan en el agua.
- **El agarre** (`grab`): sujetar a la víctima en `Anclaje.Agarre` entre F25 y F86.
- **Clips que faltan**: la muerte (en tierra y en el agua) y la carrera con una zancada más larga (el
  clip avanza ~1,1 m/s a ritmo 1; para correr a 5 m/s patina aunque se acelere al doble).
- **Voz propia**.

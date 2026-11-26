# Monstruos

Además de las fieras, el mundo tiene monstruos. Algunos no se pueden matar hasta llegar a eras
futuras: el peligro es topárselos. El primero es Cthulhu.

## Cthulhu

Un gigante de unos 117 m (122 m con las alas) que cruza el mar a pie. No ataca. Lo que hace es
**mirar**: si ve al jugador, este se queda paralizado y pierde toda la cordura. La única forma de
morir por él es un accidente: que pase por encima de tu barco.

### Cuándo aparece

`CthulhuDirector` (lo crea `PlanetLoader` en planetas con mar, mapa del mundo y clima):

- El jugador tiene que estar **cerca del mar**: agua de mar o de océano de al menos 30 m de fondo
  bajo él o a menos de 700 m (en la costa vale, navegando también).
- Con esa condición sale de media una vez cada **10 h de juego** (`MEAN_INTERVAL`, 36 000 s).
- Después de un encuentro pasan al menos **5 días de calendario** sin otro (`COOLDOWN_DAYS`). Esa espera
  es lo único que se guarda en la partida (`abyss` en los datos del planeta).
- Primero llega **su tormenta** (el evento de clima `abyss`, forzado): cielo casi negro, lluvia, rayos,
  algo de niebla y la **mitad del oleaje** de `storm`. **45 s después** sale de lo hondo a 1,3–1,7 km,
  andando hacia un punto de mar a 200–420 m del jugador, para que pase cerca.
- Se hunde andando y se va (y con él la tormenta) cuando está a más de 2,6 km, cuando han pasado
  9 min o 75 s después de mirar al jugador. Un encuentro a medias no se guarda: al cargar no está.

### Cómo anda

- Cerca de la costa **pisa el fondo**. En lo hondo **vadea con el agua por la cintura** (52 m bajo
  el agua); el fondo no se ve.
- No se acerca a menos de 14 m de fondo. Si tiene la costa delante (260 m), frena y gira más deprisa.
- Anda a unos 10 m/s, con la animación de andar a 0,6× para que pese.
- Cada 70–140 s se para: a veces en reposo y a veces **despliega la amenaza** (alas y tentáculos).

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

Esconderse solo sirve **antes** de que te vea. Una vez te ha visto:

1. Ruge, se para, se gira hacia el jugador y lo mira (animaciones Alerta y La mirada del abismo).
   El lomo, el pecho, el cuello y la cabeza giran por código (`CthulhuLookAt`) para clavar la cara
   en el jugador.
2. El jugador queda **paralizado** (`AbyssStare`, `PlayerController.is_transfixed`): sin moverse,
   sin acciones y sin timón. El cuerpo sigue con la gravedad, el agua y el barco. La cámara se va sola
   a sus ojos, se cierra el encuadre, el mundo se retuerce y late el corazón.
3. En los ~7 s que dura, la **cordura cae a cero**.
4. Al acabar quedan **3 min de secuelas** que se van pasando (distorsión suave y latido). Mira una sola
   vez por encuentro; después sigue andando y se va.

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
| `cthulhu spawn` | Trae la tormenta y lo saca en 6 s, a la distancia normal |
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

- Sonido propio. Ahora ruge con el león muy grave y late el corazón del desangrado.
- Espuma y salpicaduras alrededor de las piernas.
- Los efectos de la cordura baja más allá de las secuelas de la mirada.

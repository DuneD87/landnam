# Gaviotas y patos

`PlanetLoader` crea dos poblaciones independientes cerca del jugador cuando el
planeta tiene océano. Comparten el pool de fauna y el comportamiento de vuelo de
las aves del bosque mediante `AmbientBirdHabitat`; `WaterBirdHabitat` sustituye
las ramas por puntos sobre el agua. Los modelos horneados tienen siluetas,
colores, envergaduras y aleteos distintos; reutilizan mallas y LOD por especie.
La gaviota tiene pico con volumen y marca rojiza, y plumas oscuras con puntas
claras; el pato tiene pico aplanado, collar, franjas azules en las alas y cola
curvada. Ambos conservan patas palmeadas. La galería y el proceso de construcción
se describen en [bird_models.md](bird_models.md).

## Configuración

Editar los recursos `.tres`, también desde el inspector de Godot:

| Ajuste | `data/fauna/coastal_gulls.tres` | `data/fauna/river_ducks.tres` |
| --- | --- | --- |
| `population` | 6 | 4 |
| `spawn_min_distance` / `spawn_radius` | 25–100 m | 20–80 m |
| `min_spacing` | 22 m | 18 m |
| `recycle_distance` | 150 m | 120 m |
| `max_offshore_distance` | 250 m desde tierra | 80 m desde tierra |
| `coast_inland_distance` | 50 m hacia tierra | 30 m hacia tierra |
| `river_bank_distance` | 40 m desde el borde del cauce | 30 m desde el borde del cauce |
| `flight_height_min` / `flight_height_max` | 3–12 m sobre el agua | 1–5 m sobre el agua |
| `flight_speed_min` / `flight_speed_max` | 12–18 m/s | 10–15 m/s |
| `flight_time_min` / `flight_time_max` | 12–25 s de vuelo continuo | 8–16 s de vuelo continuo |
| `flight_distance_min` | 60 m recorridos antes de buscar agua | 35 m recorridos antes de buscar agua |
| `perch_time_min` / `perch_time_max` | 4–9 s sobre el agua | 10–20 s sobre el agua |
| `swim_speed` | 0,7 m/s | 1,4 m/s |

La altura se usa al aparecer y al preparar el aterrizaje; durante el descenso el
ave llega hasta la superficie. La distancia de aparición al jugador se comprueba
en 3D. `max_offshore_distance` mide proximidad a tierra, independientemente de esa
distancia al jugador. Los tiempos `perch_time_*` incluyen el desplazamiento a nado;
acercarse a menos de 4 m provoca el despegue, igual que en las aves del bosque.

El grupo **Sustained Flight** separa el vuelo del descanso: tanto al aparecer
como después de despegar, el ave encadena destinos en el aire sin detenerse en
cada uno. Solo busca agua para aterrizar cuando cumple el tiempo elegido entre
`flight_time_min/max` **y** la distancia horizontal acumulada `flight_distance_min`.
Esta distancia mide recorrido, no separación del punto de partida: puede incluir
giros amplios alrededor del jugador. El recorrido permanece dentro del área de
población y respeta el hábitat y los obstáculos. El tiempo de aproximación y
aterrizaje se añade al vuelo continuo; un espacio bloqueado puede alargarlo.

Cada perfil hereda **Ambient Audio**: se puede asignar un `SoundEvent` a
`ambient_sound`, añadir varias grabaciones a **Streams** y configurar volumen,
alcance, intervalos y límite de voces. Las grabaciones son independientes por
especie; las gaviotas usan el `seagull_audio.tres` asignado en su perfil.

`PlanetLoader.gull_profile = null` o `duck_profile = null` desactiva la especie.
`ambient_fauna_enabled` sigue controlando toda la fauna ambiental.

## Hábitat y comportamiento

- La costa se lee del campo de orilla de `PlanetWorldMap`. Cuando su distancia
  se satura (300 m en el bake actual), no se interpreta como costa confirmada:
  para límites mayores se busca tierra dentro del radio configurado con ocho
  anillos y 32 direcciones. La precisión depende del mapa horneado; la búsqueda
  conservadora puede omitir islas pequeñas entre muestras.
- Los ríos se consultan en el campo `RiverField`, usando su latitud polinómica,
  distinta de las coordenadas del mapa. Se exige agua real bajo el punto o en un
  cauce próximo a la ribera. En este proyecto los ríos inundados comparten la
  superficie del océano: los canales altos y secos no son hábitat acuático.
- El spawn comprueba terreno cargado, espacio libre y el volumen completo de
  los barcos, incluidas cubiertas abiertas. No necesita árboles ni ramas.
- Las aves mantienen vuelos continuos antes de buscar agua, posarse y nadar. El anclaje sigue la altura
  real de las olas y se guarda relativo al terreno para soportar FloatingOrigin.
  Las reservas evitan elegir el mismo punto de aterrizaje. El nado se detiene
  ante tierra u obstáculos; si un barco invade el anclaje, el ave despega.
- Las comprobaciones del recorrido también respetan el límite de hábitat. El
  vuelo sigue usando evitación local y colisión física, sin navegación global.
- Los límites de población, presupuesto por actualización, reciclaje y aparición
  fuera de cámara son los del spawner común. No se guardan en las partidas.

## Verificación

Ejecutar `tests/fauna/test_water_birds.tscn` con el Godot 4.6 del proyecto y
`--max-fps 60`. Comprueba terreno voxel real, mar abierto, límites de costa y
ribera, cauces secos, spawn sin árboles, vuelo, aterrizaje, nado, oleaje,
FloatingOrigin, reciclaje, población y exclusión de cubiertas de barcos.
También verifica tiempo y distancia mínimos antes de aterrizar, movimiento
continuo entre destinos y un nuevo vuelo completo al terminar el descanso.

`tests/fauna/water_birds_preview.tscn` muestra ambos modelos; `-- --capture`
guarda `build/fauna/water_birds_resting.png` y `water_birds_flying.png`.

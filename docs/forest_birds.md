# Aves de bosque

`ForestBirds` reutiliza el pool y las reglas de aparición de la fauna ambiental.
Hay tres modelos estilizados: gorrión, petirrojo y herrerillo, con cuerpo continuo,
plumaje propio, ojos pequeños con párpados, picos con volumen y plumas solapadas
en alas y cola. Las alas baten en vuelo y se recogen sobre los flancos al posarse.
Las mallas se hornean fuera del juego y comparten recursos y LOD entre instancias.
El ave mide unos
40 cm de alto; su tamaño no aumenta con el árbol.

La construcción, referencias, presupuestos y galería interactiva de las cinco
aves se describen en [bird_models.md](bird_models.md).

## Ramas e instancing

`Planet._build_tree_packed_scene()` llama a `TreePerchBaker` una vez al preparar
cada modelo Tree3D. Analiza la superficie de madera del LOD0 que se renderiza,
busca caras superiores y separa hasta 20 candidatos. No interpreta las tarjetas
de hojas como ramas. Guarda puntos, normales y tangentes en coordenadas del
modelo, junto con estructuras TriangleMesh para consultas geométricas.

El catálogo se comparte entre las entradas de la biblioteca que usan ese modelo.
Se pueden añadir Marker3D con nombres `BirdPerch*` a la escena original para dar
prioridad a puntos concretos sobre la madera; siguen sujetos a validación.

Una consulta física por segundo descubre hasta 48 árboles dentro de 65 m. Usa
los VoxelInstancerRigidBody que ya crea el instancer cerca de la cámara, sin
añadir colliders a las ramas ni nodos a cada árbol del planeta. El ID de biblioteca
identifica el catálogo. La transformación completa del cuerpo coloca cada punto
en el mundo, incluyendo la escala aleatoria, rotación y orientación planetaria.
La base del pájaro se normaliza para conservar su tamaño.

Antes de reservar se comprueban el espacio sobre la rama, el apoyo de ambas
patas y un punto de aproximación despejado. Cada punto admite una reserva.
Las referencias débiles y la transformación local detectan árboles eliminados,
descargados o cuerpos reasignados. Un cambio del origen flotante conserva los
anclajes porque tanto los destinos como los árboles dependen del terreno.

## Comportamiento y ajustes

- El perfil `data/fauna/forest_birds.tres` configura población, intervalo de
  aparición y distancia de reciclaje. `population` es el máximo de aves activas;
  `attempts_per_update` controla los intentos de aparición.
  Las 64 plazas se distribuyen entre 18 y 60 m del jugador, con al menos 7 m
  entre nuevas apariciones y reciclaje desde 100 m. El muestreo reparte por
  superficie para evitar concentrarlas en el borde interior del anillo.
- En el mismo recurso, el grupo **Flight** permite ajustar `flight_speed_min`
  y `flight_speed_max` en metros por segundo. Los valores iniciales son **8–12 m/s**.
  Cada ave elige una velocidad del intervalo al aparecer o reciclarse; para una
  velocidad fija, usar el mismo valor en ambos campos. Frenan al acercarse a
  puntos de paso y al aterrizar, y anticipan obstáculos según su velocidad.
- Si hay árboles cercanos, aparecen en aire libre alrededor del jugador, entre
  `spawn_min_distance` y `spawn_radius`, fuera de cámara y con comprobación de
  terreno cargado y colisiones. La posición queda entre 0,8 y 2,5 m por encima
  del origen del jugador (se reduce proporcionalmente para radios menores de 3 m).
  El radio es la distancia 3D completa, incluida esa altura.
- El spawn no consulta la altura, distancia ni ocupación de las ramas. Un bosque
  con ramas a 24 m permite aparecer a 8–10 m del jugador. Después de aparecer
  buscan una rama por separado; si no hay ninguna libre, siguen volando y reintentan.
  El radio de spawn limita dónde nacen, no sus vuelos posteriores.
- Vuelan al punto de aproximación, frenan y aterrizan. El grupo **Perching** del
  mismo `.tres` configura `perch_time_min` y `perch_time_max` en segundos (por
  defecto **5–12 s**). Cada aterrizaje elige una duración dentro del intervalo;
  usar ambos valores iguales para un tiempo fijo. A menos de 4 m del jugador
  levantan el vuelo antes de que termine el descanso.
  Si la subida directa está bloqueada, buscan una ruta por el exterior del árbol,
  ascienden y se aproximan desde arriba. El tiempo de vuelo admite la longitud
  de esa ruta. Si tampoco está despejada, vuelven a intentarlo.
- Prefieren ramas bajas al elegir dónde posarse. El catálogo
  conserva preferentemente las ramas inferiores y la elección pondera la altura real
  sobre la base del árbol, incluyendo su escala. Un metro extra de altura penaliza
  tanto como cuatro metros de distancia. Si las primeras opciones están obstruidas,
  amplían la búsqueda a otras ramas.
- Una esfera física evita troncos y otros cuerpos; rayos contra la madera horneada
  permiten anticipar ramas aunque el árbol solo tenga un collider de tronco.
- Si desaparece el árbol, liberan la reserva y despegan. Reciclar un ave también
  libera su punto. No se guardan en las partidas.
- `AmbientBird.bird_type` fija una especie o usa la selección aleatoria.
- `PlanetLoader.bird_perches_debug` dibuja esferas verdes en candidatos libres;
  algunos pueden descartarse al comprobar patas o espacio. `bird_profile = null`
  desactiva solo las aves; `ambient_fauna_enabled` desactiva toda la fauna.
- `DebugStats` registra el coste en `fauna:birds` y `fauna:spawner`.

## Audio ambiental

En `data/fauna/forest_birds.tres`, el grupo **Ambient Audio** configura:

- `ambient_audio_enabled`: activa o silencia los cantos.
- `ambient_sound`: recurso SoundEvent; expandirlo para editar su lista **Streams**.
  Ahora contiene `audio/effects/birds_01.wav`. Añadir más clips a esa lista permite
  alternarlos al azar, evitando repetir el anterior cuando hay varias variantes.
- `ambient_interval_min` / `ambient_interval_max`: pausa aleatoria entre cantos,
  en segundos (1–4 s inicialmente). Los temporizadores de cada ave son independientes.
- `ambient_only_perched`: por defecto `false`, para cantar también en vuelo sin
  depender de la frecuencia de aterrizaje ni del tiempo de descanso. Con `true`,
  solo inicia nuevos cantos estando posado. Si despega a
  mitad de un clip, este termina naturalmente y sigue la posición del pájaro.

El recurso de sonido está en `data/audio/events/forest_birds.tres`. También permite
ajustar **volume_db**, **max_distance**, **unit_size**, variación de volumen/tono,
**max_voices** y **cooldown**. Por defecto usa el bus **Ambient**, alcance de 60 m,
volumen de −6 dB, `unit_size = 12` y un máximo compartido de tres voces, incluso
con muchos pájaros. `high_frequency_attenuation_db = 0` conserva los agudos de los
trinos; la atenuación normal por distancia y el filtro submarino siguen activos.
`bird_02.wav` usa normalización al importar para compensar su menor nivel de
grabación, sin modificar el WAV original.
Usar grabaciones sin bucle para estos cantos ocasionales.

Las voces se toman del pool de AudioManager, siguen al ave y al origen flotante,
y se detienen al desactivar el audio o reciclar el animal. El bus Ambient conserva
los controles de volumen y el filtro submarino existentes.

El vuelo usa evitación local sencilla, sin navegación global. Las tarjetas de
follaje se tratan de forma conservadora al comprobar espacio para posarse; en
vuelo no son paredes sólidas, porque sus texturas contienen zonas transparentes.
Los anclajes siguen la geometría horneada, no la deformación del shader de viento.
Este recorrido cubre los árboles Tree3D registrados como MultiMesh del planeta;
otros formatos de vegetación necesitarían un adaptador.

## Verificación

Abrir `tests/fauna/test_forest_birds.tscn` con el Godot 4.6 del proyecto y su módulo
voxel. En consola, usar `--max-fps 60`; termina con código 0 si pasa. Incluye:

- Extracción de ramas de pino y olivo reales, escala y rotación distintas.
- Reserva exclusiva, apoyo de patas, espacio libre y aterrizaje autónomo.
- Aparición en un intervalo de 8–10 m sin candidatos fuera de sus límites.
- Spawn cerca del jugador con todas las ramas altas y reservadas; vuelo y
  aterrizaje posterior en una rama a 24 m, fuera del radio de aparición.
- Huida del jugador, eliminación/reasignación del árbol y origen flotante.
- Registro en Planet, árboles generados por VoxelInstancer y población real.
- Grabación configurada, intervalos, bus Ambient, límite de voces, seguimiento,
  silenciado, reciclaje y devolución de voces al terminar el clip.
- Inicio automático de cantos en vuelo y medición de señal en el bus Ambient
  con una cámara/oyente junto al jugador, antes de alcanzar las ramas.

`tests/fauna/birds_preview.tscn` muestra las tres especies. Con `-- --capture`
guarda `bird_species.png`, `bird_wings.png` y `bird_branch.png` en `build/fauna/`.
La última captura coloca un petirrojo en una rama extraída de un olivo a escala 2.

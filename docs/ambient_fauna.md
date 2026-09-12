# Fauna ambiental

Los planetas crean `ForestBirds` y, si tienen agua, `CoastalFish`, `CoastalGulls`
y `RiverDucks` bajo su `VoxelLodTerrain`. La opción
`Ambient Fauna / ambient_fauna_enabled` del cargador permite desactivarlo y
`fish_profile`, `bird_profile`, `gull_profile` y `duck_profile` permiten cambiar las
poblaciones sin tocar el controlador.
Las aves del bosque aparecen en aire libre cerca del jugador si hay árboles próximos;
buscan ramas para posarse después de aparecer.
Su funcionamiento y ajustes se describen en [forest_birds.md](forest_birds.md).

## Ajustes iniciales

`data/fauna/coastal_fish.tres` configura 28 peces, búsqueda entre 12 y 40 metros
del jugador, reciclaje a partir de 60 metros y un máximo de dos activaciones
cada 0,25 segundos. Las apariciones se buscan fuera de cámara. Los peces muy
lejanos se retiran incluso si siguen dentro del encuadre para acotar el coste.

El hábitat acuático busca entre 4 y 16 metros bajo la superficie; al bucear,
acompaña la profundidad del jugador. Consulta las olas y el SDF del terreno,
rechaza zonas sin datos cargados, sólidos y colisiones de construcciones. Si
el mapa de cuerpos de agua está disponible, limita esta población a océanos y
mares. Sin mapa, usa las comprobaciones locales de agua y terreno.

Hay seis tipos estilizados: sardina, dorada, pez payaso, pez mariposa, cirujano
azul y lábrido. Cada uno tiene una malla propia compartida entre sus instancias:
cuerpo perfilado, ojos con iris y pupila, boca, branquias, aletas laterales y una
silueta diferente de cola y dorsal. Los patrones incluyen bandas blancas,
franjas, manchas y una línea lateral; el lomo es más oscuro que el vientre.

Cada malla tiene una sola superficie y menos de 2.500 triángulos. Comparten un
shader que anima la cola y las aletas. Al activarse se elige un tipo y una
escala entre 0,75 y 1,1, con pequeñas variaciones de tono y velocidad. El export
`AmbientFish.fish_type` permite fijar una especie en una escena o mezclar las
seis usando `Aleatorio` (por defecto). El catálogo de formas y paletas está en
`SimpleFishMesh.TYPES`.

La caja de colisión se calcula a partir de la malla elegida, incluyendo margen
para el movimiento de las aletas. Las pruebas comprueban que cada modelo a su
máxima escala cabe en el radio de seguridad de spawn. Los peces son opacos y
participan en el efecto submarino existente.

## Barcos e impactos

- Al aparecer se excluye toda la caja orientada del barco, con margen, incluso
  las cubiertas abiertas y los compartimentos inundados.
- Durante el nado se utiliza la colisión de `CharacterBody3D`. Se comprueba
  además el movimiento relativo frente a cascos próximos: un barco puede
  alcanzar a un pez casi quieto sin que el movimiento propio del pez detecte
  el contacto. Esta comprobación usa los colliders reales, no la caja de spawn.
- Un impacto **superior a 5 m/s de cierre en la normal del contacto** elimina
  el pez y emite una pequeña nube roja. Se incluye la velocidad angular del
  barco alrededor de su centro de masa. Un roce tangencial rápido o dos cuerpos
  moviéndose juntos no cuentan como un golpe violento. El umbral se configura
  en `AmbientFish.lethal_ship_impact_speed`.
- Si el pez acaba dentro del volumen del casco por una edición o un movimiento
  que la física no resuelva, se retira sin efecto. No se simula daño al barco.
- La nube se expande sin gravedad, se desvanece en unos tres segundos y se
  recorta por la superficie del agua. Hay como máximo ocho emisores por
  hábitat, reutilizables. Su atenuación de color bajo el agua es aproximada.

Peces, destinos y nubes siguen el origen flotante mediante su padre terreno.
La fauna es ambiental y se regenera al cargar; no añade datos a las partidas.

## Reutilizar para ratones, lagartos o insectos

1. Crear una escena que herede de `AmbientAnimal`, con su movimiento y sus
   implementaciones de `activate()` y `deactivate()`. Reiniciar siempre el
   estado al reactivarla y desactivar las colisiones al retirarla.
2. Crear un hábitat que herede de `AmbientFaunaHabitat` e implemente
   `sample_spawn(anchor, profile, rng)` y `is_spawn_valid(point, clearance)`.
   Aquí se comprueban suelo, bioma, bosque o espacio aéreo. Devolver `null`
   si no se puede obtener una posición válida.
3. Crear un `AmbientFaunaProfile` con la escena, población, distancias y radio
   que envuelve al animal más grande.
4. Crear un `AmbientFaunaSpawner`, llamar a `setup(profile, habitat, player)`
   y añadirlo bajo el terreno/planeta correspondiente. El generador gestiona
   límites, cámara, reintentos y reutilización sin conocer el tipo de animal.

Las nuevas familias necesitan su hábitat y movimiento. Peces, aves y animales
terrestres usan esta infraestructura compartida. Los conejos, zorros y ratones
se describen en [small_ground_fauna.md](small_ground_fauna.md).

## Verificación

Ejecutar `tests/fauna/test_ambient_fauna.tscn` con Godot 4.6 y el módulo voxel.
Comprueba el pool genérico, cámara, terreno real y descargado, casco rotado,
colisión fina, barco a 20 m/s, umbral estricto de 5 m/s, nube y origen flotante.
Para ejecución automática, añadir `--max-fps 60`; la escena termina con código
0 si las comprobaciones pasan. La variante headless de este build puede emitir
errores del renderer dummy al generar mallas voxel; se valida también con Vulkan.

`tests/fauna/fauna_preview.tscn` muestra los seis tipos con sus nombres y la nube. Con
`-- --capture` guarda capturas de las fases en `build/fauna/` y termina.

Las categorías `fauna:spawner` y `fauna:fish` aparecen en `DebugStats`.

## Aves acuáticas

Gaviotas y patos comparten el sistema de población y disponen de perfiles propios
en `data/fauna/coastal_gulls.tres` y `data/fauna/river_ducks.tres`. Sus límites de
costa/río, vuelo y descanso sobre el agua se describen en [water_birds.md](water_birds.md).

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

`data/fauna/coastal_fish.tres` configura 28 peces, búsqueda entre 18 y 65 metros
del jugador, reciclaje a partir de 100 metros y un máximo de dos activaciones
cada 0,25 segundos. Las apariciones se buscan fuera de cámara. Los peces muy
lejanos se retiran incluso si siguen dentro del encuadre para acotar el coste.

### Distribución de las apariciones

Todos los hábitats muestrean el radio con probabilidad uniforme por superficie
del anillo, mediante `AmbientFaunaProfile.sample_spawn_distance()`. Así las
bandas exteriores, que tienen más superficie, reciben más ejemplares. El spawner
comprueba ambas distancias sobre la posición final, después de la proyección del
hábitat, y rechaza posiciones demasiado próximas a un ejemplar de esa población
antes de consultar colisiones. Los máximos de población se mantienen.

| Población | Aparición desde el jugador | Separación al aparecer | Reciclaje desde |
| --- | --- | --- | --- |
| Aves del bosque | 18–60 m | 7 m | 100 m |
| Gaviotas | 25–100 m | 22 m | 150 m |
| Patos | 20–80 m | 18 m | 120 m |
| Peces | 18–65 m | 3 m | 100 m |
| Conejos | 20–70 m | 10 m | 110 m |
| Ratones | 18–60 m | 7 m | 95 m |
| Zorros | 30–100 m | 25 m | 150 m |
| Ciervos | 30–120 m | 22 m | 180 m |
| Osos | 50–180 m | 55 m | 270 m |
| Leones | 50–240 m | 65 m | 360 m |
| Búfalos | 50–300 m | 30 m | 450 m |

La fauna marina grande conserva sus radios amplios y separaciones descritos
más abajo. `min_spacing` limita nuevas apariciones de la misma población; los
animales pueden acercarse después durante su movimiento normal. La distancia
de reciclaje mayor evita reemplazos constantes cuando el jugador se mueve.
Se conservan los filtros de terreno cargado y hábitat, el límite de intentos y
el presupuesto compartido de 2 ms: un área sin espacio puede quedar por debajo
del máximo de población.

`tests/fauna/test_fauna_distribution.tscn` comprueba el reparto por superficie,
la separación y cobertura con tres semillas, el origen flotante y el rechazo
de posiciones proyectadas fuera del intervalo permitido.

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

Las seis mallas están horneadas en `data/fauna/meshes/fish/` y se precargan: el
alta de un pez nunca ejecuta el `SurfaceTool` (costaba 10-15 ms por especie la
primera vez). Tras cambiar `TYPES`, regenerarlas con:

```
godot --headless --path . --script res://tools/fauna/bake_fish_meshes.gd
```

La caja de colisión se calcula a partir de la malla elegida, incluyendo margen
para el movimiento de las aletas. Las pruebas comprueban que cada modelo a su
máxima escala cabe en el radio de seguridad de spawn. Los peces son opacos y
participan en el efecto submarino existente.

## Tiburones, ballenas, orcas y tortugas

Los planetas con agua añaden cuatro poblaciones independientes. Sus perfiles
están en `data/fauna/` y se exponen en `PlanetLoader / Ambient Fauna`:

| Perfil | Población máxima cercana | Hábitat | Profundidad inicial |
| --- | --- | --- | --- |
| `shark.tres` | 4 | Alta mar | 10–15 m |
| `whale.tres` | 2 | Alta mar | 12–18 m |
| `orca.tres` | 3 | Costa y alta mar | 11–20 m |
| `turtle.tres` | 6 | Costa y alta mar | 4–12 m |

Alta mar empieza a **150 metros del litoral**, más el radio de seguridad del
animal completo. Se ajusta con `min_offshore_distance`; cero permite también
la costa. La distancia procede del campo de orilla del mapa planetario, tanto
en océanos como en mares. No aparecen en lagos, charcas ni tierra. Si falta el
mapa se espera a que esté listo; tiburones y ballenas necesitan además el campo
de orilla. Un campo cuyo alcance sea menor que el límite configurado no sirve
para confirmar alta mar y rechaza esas apariciones.

Las distancias de búsqueda/reciclaje se adaptan a cada tamaño: tiburones
50–240/330 m, ballenas 70–320/450 m, orcas 40–200/280 m y tortugas 25–110/160 m.
Cada perfil fija además una separación mínima (`min_spacing`) respecto a los
individuos activos de su especie: 60 m tiburones, 110 m ballenas, 50 m orcas y
20 m tortugas, para que no aparezcan amontonados.

El giro depende del tamaño: el rumbo cambia como mucho a velocidad / (radio de
giro), con un radio de un largo de cuerpo (`TURN_RADIUS_LENGTHS` en
`AmbientMarineAnimal`). Un giro de 90° lleva unos 41 s a la ballena, 15 s al
tiburón, 12 s a la orca y 5 s a la tortuga. Los rumbos nuevos se eligen dentro
de ±72° del actual y no se cambian hasta haber tenido tiempo de alcanzarlos; la
profundidad se sigue corrigiendo al mismo ritmo para esquivar la superficie.

### Ataques de tiburón a barcos

Un tiburón ataca a cualquier barco (`DynamicGridBody` de tipo `BOAT`) cuyo casco
se le acerque a menos de `attack_radius` (45 m; con 0 no ataca nunca). Como
aparecen a 50 m o más, el ataque solo empieza si es el barco quien se acerca.

1. **Carga:** acelera a `charge_speed_factor` (×1.8) y sube hasta la mitad del
   calado del casco. Si el barco queda de costado dentro de su círculo de giro,
   sigue recto para ganar distancia y vira después, en vez de orbitarlo.
2. **Mordisco:** cuando el hocico toca la caja del casco, o su cuerpo choca con
   él, aplica `apply_damage_at` con `bite_energy` (15 000 J) en un radio de
   `bite_radius` (1.2 m). Con celdas de 1 m arranca unos 2–3 bloques bajo la
   línea de flotación y la inundación hace el resto. El casco recibe además un
   empujón de 0.8 m/s (hasta 20 t de masa).
3. **Retirada:** se aleja `retreat_distance` (45 m) y vuelve a aguas profundas.
   Si el barco sigue cerca, repite; si escapa a más de 2.5 × `attack_radius`, se
   hunde o desaparece, lo deja y descansa 8 s antes de elegir otro.

Mientras ataca, solo se exigen mar y fondo suficiente: puede asomar el lomo y la
aleta. Su propia embestida no lo mata; solo lo hace un barco que lo embista a
más de 5 m/s o un cañonazo, igual que antes. Con los valores actuales, el primer
mordisco llega en unos 30 s y los siguientes cada ~40 s.

Al bucear acompañan la profundidad del jugador. Las reglas de hábitat
se comprueban también durante el nado y los destinos de tiburones y ballenas
se mantienen mar adentro. Las comprobaciones de terreno cargado, superficie,
barcos y colisiones son las mismas que para los peces, con márgenes adecuados
al tamaño de cada especie. Poner un perfil a `null` desactiva solo esa población.

Cada especie tiene una malla horneada y compartida, con cuerpo continuo de
secciones interpoladas, normales suaves y aletas curvas con grosor. El tiburón
tiene cinco branquias por lado, boca y aletas pélvicas; la ballena, pliegues
ventrales y espiráculo; la orca, manchas integradas en la piel y silla gris; la
tortuga, caparazón abovedado con placas delimitadas y borde. Los ojos siguen la
curvatura de la cabeza, con córnea poco abultada, iris discreto y párpado superior.
Las proporciones y posiciones se ajustan por especie a partir de
[referencias fotográficas](marine_model_references.md): mandíbula bajo el hocico
del tiburón, rostro ancho y ojo retrasado en la ballena, frente redondeada y ojo
separado de la mancha blanca en la orca, y pico romo en la tortuga.
Las bocas tienen recorridos propios y costuras finas. La mancha blanca de la
orca tiene un contorno curvo ajustado a la piel. El caparazón tiene pigmentación
radial en sus placas y las aletas de las tortugas muestran un patrón de escamas.
El moteado y la rugosidad se hornean en los colores de vértice: el shader no
calcula ruido por píxel. Las bocas, branquias, cresta del rostro y pliegues se esculpen en la piel;
las placas del caparazón tienen surcos hundidos. La interpolación de las
secciones respeta su separación real para suavizar mandíbula, hombros y cola.
Cada modelo conserva una sola superficie. Los tres animales grandes usan
39–43 mil triángulos de cerca; la tortuga, unos 24 mil. El horneado genera
seis niveles de detalle automáticos, hasta unos cientos de triángulos a gran
distancia. No se genera geometría ni se calcula la simplificación al jugar.

**Tiburones y ballenas tienen escala lineal ×6 y las orcas ×4**, respecto a la
malla original (unos 30 m el tiburón y 58 m la ballena). Las tortugas mantienen ×1. `SimpleMarineMesh.MODEL_SCALES` controla el tamaño
y se aplica tanto a la malla como a la caja de colisión y al margen de animación.
Los perfiles aumentan también profundidad y radio de seguridad; los destinos de
nado se separan según el tamaño del animal. Un shader anima
la cola lateralmente en tiburones, verticalmente en cetáceos y las aletas en
tortugas. La cadencia disminuye con el tamaño, las normales acompañan la
flexión y los pesos de las aletas mantienen rígido el caparazón. Ballenas,
orcas y tortugas son fauna ambiental: solo el tiburón tiene `attack_radius`.

`tests/fauna/marine_preview.tscn` permite revisar cada especie con las teclas
1–4 y comparar las cuatro a escala relativa con 0. Arrastrar el ratón gira la
vista y la rueda ajusta el zoom. H alterna entre cabeza y cuerpo; P muestra el
perfil. La etiqueta muestra la escala de cada especie
y la cámara encuadra automáticamente sus dimensiones.
Para regenerar las mallas:

```sh
godot --headless --path . --script res://tools/fauna/bake_marine_meshes.gd
```

### Aparición de los ejemplares grandes

Tiburones, ballenas y orcas (`use_bathymetry`) son más grandes que la zona que el
terreno mantiene cargada a detalle completo. Donde los vóxeles bajo el cuerpo no
están cargados, el fondo se comprueba con el mapa de alturas del planeta: el
centro y dos anillos de 6 y 12 muestras sobre la huella, con `bathymetry_margin`
de agua libre bajo el cuerpo. Al aparecer, si los vóxeles están cargados, se
comprueba además el cilindro exacto, pero solo tras pasar el filtro del mapa: con
el fondo cerca, ese recorrido cuesta de 2 a 14 ms por ballena. Mientras nadan
solo se comprueba el mapa (sin margen) y las rocas que no recoge las resuelve su
caja de colisión. Los destinos de nado se eligen donde el mapa garantiza el
margen, así que evitan los bajíos. Las muestras más hondas de lo que permite el fondo se elevan en vez de
descartarse. Tiburones y ballenas dirigen el 75 % de las muestras mar adentro
según el campo de orilla.

Aparecen con un fundido por tramado de 2,5 s, así que el margen fuera de cámara
(`view_margin`) puede ser menor que su longitud. Al salir del hábitat se desvanecen
en 1,5 s en lugar de desaparecer de golpe.

### Coste de las comprobaciones de terreno

Los animales con un radio de seguridad mayor de 2 m leen el SDF del volumen
completo en bloque. La comprobación usa memoria contigua y resuelve los volúmenes
uniformes en código nativo, evitando una consulta al terreno por cada vóxel.
Los volúmenes no uniformes se subdividen por su eje mayor; solo los fragmentos
de hasta 4.096 vóxeles pasan al recorrido de valores. Así los ejemplares gigantes
no recorren millones de muestras en GDScript por un pequeño cambio local.
Se conserva la comprobación previa de que todo el volumen está cargado y se
examinan todos los valores si el SDF no es uniforme, incluidos obstáculos de
un solo vóxel. El buffer se reutiliza, pero los datos se leen de nuevo en cada
consulta para respetar las ediciones del terreno. Las cajas de colisión y los
barridos contra cascos siguen activos.

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

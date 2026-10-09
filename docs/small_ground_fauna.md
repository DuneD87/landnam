# Pequeños animales terrestres

La Tierra incluye conejos, zorros y ratones en `biome_settings.ground_fauna`.
Usan `AmbientFaunaSpawner`, el pool de `AmbientAnimal` y el cargador de perfiles
terrestres, como las poblaciones existentes. `ambient_fauna_enabled` también los
desactiva. No requieren modelos externos ni añaden datos a las partidas.

| Perfil en `data/fauna/` | Población máxima | Paseo / huida | Distancia de alarma |
| --- | ---: | ---: | ---: |
| `rabbits.tres` | 6 | 0,55 / 5 m/s | 6 m |
| `foxes.tres` | 2 | 1,4 / 5 m/s | 8 m |
| `mice.tres` | 7 | 0,65 / 2,4 m/s | 3,5 m |

En el frío, `arctic_hares.tres` (5), `arctic_foxes.tres` (2) y `lemmings.tres` (7, 0,6 / 2,4 m/s).
Las poblaciones se bajaron a la mitad cuando llegaron las criaturas grandes del pack (ver
[creature_species.md](creature_species.md#población)).

Los perfiles heredan de `GroundFaunaProfile`: se pueden ajustar población,
biomas, alturas, distancias y frecuencia de aparición. `SmallGroundFaunaProfile`
añade especie, velocidades, distancia de paseo y pendiente máxima. Los tres
perfiles iniciales habitan las bandas templadas 1 y 3, entre -49,5 y 240 m sobre
el radio nominal del planeta. Aparecen fuera de cámara, con hasta dos
activaciones cada 0,35 s. Los conejos se reparten entre 20–70 m del jugador,
los ratones entre 18–60 m y los zorros entre 30–100 m, con separaciones mínimas
al aparecer de 10, 7 y 25 m respectivamente. El reciclaje empieza a 110, 95 y
150 m según visibilidad. Se conservan las poblaciones máximas.

## Modelos del pack

Las especies que tienen modelo en el pack de animales (WildMesh) lo usan en vez del procedural:
el perfil lleva `model`, un `FaunaModelData` (`data/fauna/models/`) con la escena importada, sus
clips (sacados con `tools/fauna/extract_animations.gd`, en bucle los ciclos), el material, la
escala, la cápsula y qué clip va quieto y a cada velocidad. Sin `model`, sigue el procedural. El
tamaño de cada individuo, con modelo o sin él, es el de su variante (`variants` del perfil, las de
`small_mammal_*`: joven, adulto y grande; ver [ambient_fauna.md](ambient_fauna.md#tamaños)), y los
jóvenes andan y huyen algo más despacio.

| Especie | Modelo | Escala | Al paso / huyendo |
| --- | --- | ---: | --- |
| Conejo | `Rabbit` | 0,7 | `HoppingSlow_F` a 0,55 m/s / `RunFast_F` a 5 m/s |
| Liebre ártica | `Rabbit`, pelaje blanco | 1,0 | ídem a 0,7 / 6,5 m/s |
| Zorro | `Fox` | 0,95 | `WalkSlow`, `Walk`, `Trot`, `Run`, `Sprint` (0,37 / 0,65 / 2,01 / 4,72 / 8,86 m/s) |
| Zorro ártico | `Fox`, pelaje blanco | 0,8 | ídem |
| Ratón | `Rat` | 0,36 | los mismos clips (0,11 / 0,2 / 0,48 / 1,34 / 1,82 m/s), hasta ×4 |
| Lémming | `Rat`, más dorado | 0,45 | ídem |

Los modelos de zorro y rata salen de sus FBX con `tools/fauna/import_pack_model.gd` (ver
[creature_species.md](creature_species.md#de-un-fbx-del-pack-a-una-especie)): solo la malla y los
clips que se usan, no el FBX entero. Las velocidades de suelo de cada clip las mide
`tools/fauna/measure_gait.gd` sobre los pies en apoyo. Un ratón con el clip de una rata mueve las
patas mucho más deprisa que ella, así que su `max_rate` (el ritmo máximo del clip, ×2 por defecto)
es 4. Las dos muertes vienen en el propio modelo.

`SkinnedFaunaModel` monta el modelo y elige el clip: quieto, `Idle`, y a veces (`rest_chance`)
se agacha a pastar (`rest_clips`: entrada y bucle) mientras siga quieto; en marcha, el ciclo cuya
velocidad de suelo (`gait_speeds`, medida sobre los pies en apoyo) menos tenga que cambiar, al
ritmo del cuerpo (×0,5–×2) para que las patas no patinen. El conejo ya salta en su clip: el cuerpo
no da saltos físicos. Los clips se avanzan a mano (`AnimationLod`): cerca de la cámara cada
fotograma, a más de 12, 30 y 60 m uno de cada 2, 3 y 4, y fuera de cámara uno de cada 8
(`fauna:small_ground/anim` en DebugStats).

Al morir, `FaunaCorpse` copia el esqueleto con la pose del momento. Si el modelo trae `death`, la
copia hace esa animación fundiéndose desde esa pose (0,2 s), y el cuerpo rígido ya no rueda: lo
tumba el clip. El conejo del pack no trae muerte, ni ningún animal de su familia de esqueleto
(`Root`, `Pelvis`, `Spine1`…); la suya es el derrumbe de la hiena herida
(`WalkSlowWounded2Lying`, desde 0,5 s: se tambalea, se derrumba y queda de lado), pasado con
`tools/fauna/retarget_clip.gd`, que copia el giro de cada hueso respecto a su reposo y escala lo
que baja la pelvis. `--lift` sube el cuerpo a medida que cae (el conejo es más grueso que la hiena
para su altura). Para regenerarlo, con el FBX de la hiena copiado un momento al proyecto:

```text
godot --headless --path . --script res://tools/fauna/retarget_clip.gd -- \
    --source=res://models/animals/_retarget/hyena.fbx --clip=WalkSlowWounded2Lying \
    --target=res://models/animals/rabbit/rabbit.fbx --out=res://models/animals/rabbit/rabbit_death.res \
    --from=0.5 --lift=0.065
```

La liebre ártica usa la textura del conejo pasada a blanco con `tools/fauna/winter_coat.gd`, que
aclara el pelo y conserva los ojos, la nariz y lo rosado de orejas y boca:

```text
godot --headless --path . --script res://tools/fauna/winter_coat.gd -- \
    --source=res://models/animals/rabbit/rabbit_body.png \
    --out=res://models/animals/rabbit/arctic_hare_body.png --keep_dark=0.04
```

Al huir, el animal corre hacia un punto a lo que recorre en todo el susto (`FLEE_TIME`, 1,8 s):
antes llegaba a los 5 m de su paseo y se paraba en seco.

## Modelos procedurales

`SimpleSmallAnimalModel` carga una malla horneada por especie desde
`data/fauna/meshes/`. El cuerpo, cuello, cabeza, orejas, patas y cola forman una
superficie continua, esculpida mediante un campo de distancias y simplificada
fuera del juego. Los ojos, nariz y bigotes se incorporan a la misma superficie
de dibujo. Cada animal usa una sola instancia de malla y comparte recursos.

El shader `small_animal.gdshader` añade variación fina de pelaje que se atenúa
con la distancia, brillo diferente en los ojos y movimiento de patas, cola y
orejas con pesos suaves. El coste de esculpido no se paga al aparecer animales.
Los modelos tienen aproximadamente 25.000 triángulos cada uno; el radio de
spawn y el margen de culling contemplan también la deformación animada.
Cada activación varía la escala entre 0,85 y 1,1 y reinicia el estado del modelo.
Los conejos dan saltos físicos cortos; los zorros trotan y los ratones mueven las
patas con mayor frecuencia. Entre paseos descansan y, al acercarse el observador,
huyen buscando una dirección transitable. Son fauna ambiental; el zorro no caza.

`SmallGroundFaunaHabitat` amplía el hábitat terrestre para limitar la pendiente
a 40°, rechazar suelo sumergido antes de que exista el mapa horneado y comprobar
el camino con rayos cortos. Los animales frenan ante paredes, agua y desniveles
sin apoyo próximo. Si se descarga el suelo, se retiran del pool activo; una cuesta fuerte o el
agua bajo los pies no los retiran (antes, pisar un triángulo empinado del terreno los hacía
desaparecer a la vista). Si la cápsula se cuela bajo la malla del terreno, que no tiene dentro y no
la empuja fuera, vuelve encima (`terrain_under` desde 0,6 m por encima). El modelo se inclina con
la normal del suelo que pisa, suavizada, para que en cuesta no se le metan la cabeza o la grupa en
la ladera; el cuerpo sigue andando con la vertical del planeta. Esta IA
es local: no utiliza navegación global ni intenta resolver laberintos.

El cuerpo usa colisión física y gravedad radial; los destinos se guardan en
coordenadas del terreno para seguir el origen flotante. Las criaturas reciben
daño e impactos mediante `AmbientAnimal`, sin cadáver persistente. La categoría
`fauna:small_ground` registra su coste en `DebugStats`.

## Verificación y vista previa

Con Godot 4.6 y el módulo voxel:

```text
godot --headless --path . --max-fps 60 --scene res://tests/fauna/test_small_ground_fauna.tscn
godot --path . --scene res://tests/fauna/small_ground_preview.tscn
```

La prueba comprueba las tres especies, suelo, huida, despeje del modelo animado,
origen flotante, reinicio y reutilización del pool, paredes, pendientes, agua y
descarga de terreno. Termina con código 0 si pasa. La vista previa muestra las
tres especies a escala real; añadir `-- --capture` guarda una imagen en
`build/fauna/small_ground_species.png`, primeros planos de cada especie en
`build/fauna/small_ground_detail_0.png` a `small_ground_detail_2.png` y termina.
También captura tres fases de movimiento por especie (`small_ground_motion_*`).
`small_ground_rebuilt.png` reúne tres vistas ampliadas, encuadradas por separado.

## Editar y regenerar las mallas

La anatomía, las zonas de color y los pesos se editan en
`tools/fauna/sculpt_small_animals.py`. Instalar sus dependencias en un entorno
Python separado con `tools/fauna/requirements.txt` y ejecutar:

```text
python tools/fauna/sculpt_small_animals.py
godot --headless --path . --script res://tools/fauna/bake_small_animal_meshes.gd
```

El primer paso genera datos intermedios en `build/fauna/sculpted/`. El segundo
guarda recursos nativos comprimidos `.res`; estos sí forman parte del proyecto.
No se necesita Python ni estas herramientas para ejecutar el juego.

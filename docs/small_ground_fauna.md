# Pequeños animales terrestres

La Tierra incluye conejos, zorros y ratones en `biome_settings.ground_fauna`.
Usan `AmbientFaunaSpawner`, el pool de `AmbientAnimal` y el cargador de perfiles
terrestres, como las poblaciones existentes. `ambient_fauna_enabled` también los
desactiva. No requieren modelos externos ni añaden datos a las partidas.

| Perfil en `data/fauna/` | Población máxima | Paseo / huida | Distancia de alarma |
| --- | ---: | ---: | ---: |
| `rabbits.tres` | 12 | 1,1 / 4,2 m/s | 6 m |
| `foxes.tres` | 4 | 1,4 / 5 m/s | 8 m |
| `mice.tres` | 14 | 0,65 / 2,4 m/s | 3,5 m |

Los perfiles heredan de `GroundFaunaProfile`: se pueden ajustar población,
biomas, alturas, distancias y frecuencia de aparición. `SmallGroundFaunaProfile`
añade especie, velocidades, distancia de paseo y pendiente máxima. Los tres
perfiles iniciales habitan las bandas templadas 1 y 3, entre -49,5 y 240 m sobre
el radio nominal del planeta. Aparecen fuera de cámara entre 8 y 35 m, con hasta
dos activaciones cada 0,35 s, y se reciclan a partir de 55 m según visibilidad.

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
sin apoyo próximo. Si se descarga el suelo, se retiran del pool activo. Esta IA
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

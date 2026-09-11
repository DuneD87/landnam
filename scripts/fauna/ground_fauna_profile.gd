class_name GroundFaunaProfile extends AmbientFaunaProfile

## Población de superficie: dónde vive la especie y qué deja al morir. Lo que decide el terreno
## (pendiente, despeje) vive en GroundFaunaHabitat, que es común a todas las especies.

## Escena del animal, por ruta y no por referencia: así el planeta la carga en hilo y la deja
## en animal_scene, en vez de arrastrarla al abrir este perfil.
@export_file("*.tscn") var scene_path: String = ""

## Índices de banda de biome_latitude_ranges del planeta donde aparece la especie.
@export var biomes: Array[int] = []
## Altura admitida sobre el radio NOMINAL del planeta, en metros. El mar está en -water_level,
## así que 0 no es la orilla: en el planeta Tierra la orilla es -50.
@export var min_height: float = -50.0
@export var max_height: float = 200.0
## Segundos que el cadáver se queda antes de volver al pool. 0 = desaparece al morir.
@export_range(0.0, 600.0, 1.0, "or_greater", "suffix:s") var corpse_duration: float = 0.0
## Distancia hasta la que la criatura corre con todo el detalle. Más allá el spawner la adormece
## sin reciclarla.
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:m") var full_detail_distance: float = 60.0
## Distancia a la que la IA pasa a actualizarse una vez de cada cuatro.
@export_range(0.0, 200.0, 1.0, "or_greater", "suffix:m") var near_detail_distance: float = 20.0

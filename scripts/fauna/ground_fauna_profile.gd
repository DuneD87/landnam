class_name GroundFaunaProfile extends AmbientFaunaProfile

## Población de superficie: dónde vive la especie y qué deja al morir. Lo que decide el terreno
## (pendiente, despeje) vive en GroundFaunaHabitat, que es común a todas las especies.

## Escena del animal, por ruta y no por referencia: así el planeta la carga en hilo y la deja
## en animal_scene, en vez de arrastrarla al abrir este perfil.
@export_file("*.tscn") var scene_path: String = ""

## Índices de banda de biome_latitude_ranges del planeta donde aparece la especie.
@export var biomes: Array[int] = []
## Frío admitido (grados del campo de frío del planeta, ver ClimateField): la fauna templada no
## sube a la tundra y la polar no baja del hielo. Sin clima en el planeta no filtra.
@export var climate_min: float = -1000.0
@export var climate_max: float = 1000.0
## 0 = los dos hemisferios, 1 = solo el norte, -1 = solo el sur (los pingüinos).
@export_range(-1, 1, 1) var hemisphere: int = 0
## Altura admitida sobre el radio NOMINAL del planeta, en metros. El mar está en -water_level,
## así que 0 no es la orilla: en el planeta Tierra la orilla es -50.
@export var min_height: float = -50.0
@export var max_height: float = 200.0
## Vive a menos de esto (m) de un río, un lago o la costa (los caimanes). 0 = donde sea.
@export var near_water: float = 0.0
## Segundos que el cadáver se queda antes de volver al pool. 0 = desaparece al morir.
@export_range(0.0, 600.0, 1.0, "or_greater", "suffix:s") var corpse_duration: float = 0.0
## Distancia hasta la que la criatura corre con todo el detalle. Más allá el spawner la adormece
## sin reciclarla.
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:m") var full_detail_distance: float = 60.0
## Distancia a la que la IA pasa a actualizarse una vez de cada cuatro.
@export_range(0.0, 200.0, 1.0, "or_greater", "suffix:m") var near_detail_distance: float = 20.0

class_name GroundPlaceableTrait
extends ItemTrait

## Se planta en el suelo (no en un bloque): la escena que deja y cuánta pendiente aguanta.
## Seleccionado en la barra, SurvivalActions enseña dónde iría y lo planta con el clic.

@export_file("*.tscn") var scene_path := ""
## Lo que se enseña, translúcido, donde iría (solo lo que se ve, sin la lógica).
@export var preview_scene: PackedScene
## Radio con el que se asienta en el suelo (GroundFit), pendiente máxima en grados (más allá no
## se planta) y desnivel máximo que puede quedar bajo él (m).
@export var radius := 0.55
@export var max_slope := 28.0
@export var max_rough := 0.3
## Distancia mínima a otro igual (m).
@export var spacing := 1.5


func describe() -> Array:
	return [["Se planta", "En el suelo"]]

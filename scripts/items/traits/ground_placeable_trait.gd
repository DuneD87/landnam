class_name GroundPlaceableTrait
extends ItemTrait

## Se planta en el suelo (no en un bloque): la escena que deja y cuánta pendiente aguanta.
## Seleccionado en la barra, SurvivalActions enseña dónde iría y lo planta con el clic.

## Grupo de lo que ya está plantado (hogueras, estaciones de trabajo), para no plantar una cosa
## encima de otra.
const PLACED_GROUP := &"ground_placed"

@export_file("*.tscn") var scene_path := ""
## Lo que se enseña, translúcido, donde iría (solo lo que se ve, sin la lógica).
@export var preview_scene: PackedScene
## Radio con el que se asienta en el suelo (GroundFit), pendiente máxima en grados (más allá no
## se planta) y desnivel máximo que puede quedar bajo él (m).
@export var radius := 0.55
@export var max_slope := 28.0
@export var max_rough := 0.3
## Distancia mínima a otra cosa plantada (m).
@export var spacing := 1.5
## Cuánto se inclina con la pendiente (grados): lo bajo, como una hoguera, sigue al suelo; lo que va
## sobre patas va casi derecho.
@export var max_tilt := 20.0
## Cuánto se hunde para que el lado más bajo no flote: la parte del desnivel (0-1) y el tope (m).
## Sobre patas se apoya en lo más bajo y las del lado alto se clavan en el suelo.
@export var settle := 0.6
@export var max_settle := 0.1


func describe() -> Array:
	return [["TRAIT_PLACED", tr("TRAIT_ON_GROUND")]]

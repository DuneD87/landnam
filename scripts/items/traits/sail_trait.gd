class_name SailTrait
extends ItemTrait

## El diseño de cada aparejo define la superficie; el material define la eficiencia.
@export_range(0.1, 3.0, 0.05) var efficiency := 1.2


func describe() -> Array:
	return [["TRAIT_SAIL_AREA", tr("SAIL_CUSTOM_AREA")]]

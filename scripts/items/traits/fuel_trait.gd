class_name FuelTrait
extends ItemTrait

## Arde en una hoguera (Campfire) o en el horno (Furnace): segundos de fuego que da cada unidad y lo
## que calienta para fundir.

@export var burn_time := 60.0
## Lo que funde en el horno cada segundo que arde, de 0 a 1 (RecipeData.time va a pleno calor: 1).
## 0 = no llega a fundir y el horno no lo acepta (las ramas). La madera, poco; el carbón, del todo.
@export_range(0.0, 1.0) var smelt_heat := 0.0


func describe() -> Array:
	var rows := [["TRAIT_BURNS", number(burn_time) + " s"]]
	if smelt_heat > 0.0:
		rows.append(["TRAIT_SMELT_HEAT", "%d %%" % roundi(smelt_heat * 100.0)])
	return rows

class_name SkinningTrait
extends ItemTrait

## Despelleja: en la mano, deja sacar la carne y la piel de un animal muerto (HuntingLoot).
## [yield_mult] multiplica lo que se saca.

@export var yield_mult := 1.0


func describe() -> Array:
	return [["Despelleja", "Sí" if is_equal_approx(yield_mult, 1.0) else "×" + number(yield_mult)]]

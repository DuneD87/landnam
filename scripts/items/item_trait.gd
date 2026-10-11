class_name ItemTrait
extends Resource

## Algo que se puede hacer con un objeto además de lo que dice su categoría: comerlo, quemarlo,
## asarlo, llevar agua, abrigar, despellejar, plantarlo en el suelo... Un objeto lleva los suyos en
## ItemData.traits, y quien los usa los busca por su tipo (ItemData.get_trait). Ver docs/items.md.


## Filas para la ficha del objeto (ItemCard): [nombre, valor].
func describe() -> Array:
	return []


## Con coma decimal y sin ceros de más.
static func number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return ("%.2f" % value).rstrip("0").rstrip(".").replace(".", ",")


static func percent(value: float) -> String:
	return "%+d %%" % roundi(value * 100.0)

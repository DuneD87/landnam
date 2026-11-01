class_name Eras
extends RefCounted

## Las eras del juego, de la más antigua a la más moderna. Cada una trae sus estaciones de trabajo
## (CraftingStationTrait) y sus recetas (RecipeData.era), y la ventana de fabricar las agrupa por
## era. Una era nueva es un valor más aquí, al final (los .tres guardan el número), con la clave de
## su nombre.
## Ver docs/items.md.

enum Era {STONE, BRONZE}

const NAMES := {
	Era.STONE: "ERA_STONE",
	Era.BRONZE: "ERA_BRONZE",
}


## El nombre de la era, ya traducido.
static func name_of(era: Era) -> String:
	return TranslationServer.translate(NAMES.get(era, "ERA_UNKNOWN"))

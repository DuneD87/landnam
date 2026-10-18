class_name Eras
extends RefCounted

## Las eras del juego, de la más antigua a la más moderna. Cada una trae sus estaciones de trabajo
## (CraftingStationTrait) y sus recetas (RecipeData.era), y la ventana de fabricar las agrupa por
## era. De momento solo hay la Edad de piedra; una era nueva es un valor más aquí, con la clave de su
## nombre.
## Ver docs/items.md.

enum Era {STONE}

const NAMES := {
	Era.STONE: "ERA_STONE",
}


## El nombre de la era, ya traducido.
static func name_of(era: Era) -> String:
	return TranslationServer.translate(NAMES.get(era, "ERA_UNKNOWN"))

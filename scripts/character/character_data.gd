class_name CharacterData
extends Resource

## Everything the new-game flow decides about the player character. Each
## creation step fills its part; new parts (skills, attributes, origin...)
## go here with their own entry in to_dict/from_dict.

@export var display_name := ""
@export var appearance := CharacterAppearance.new()


func to_dict() -> Dictionary:
	return {
		"name": display_name,
		"appearance": appearance.to_dict(),
	}


static func from_dict(data: Dictionary) -> CharacterData:
	var character := CharacterData.new()
	character.display_name = str(data.get("name", ""))
	var appearance_data: Variant = data.get("appearance")
	if appearance_data is Dictionary:
		character.appearance = CharacterAppearance.from_dict(appearance_data)
	return character

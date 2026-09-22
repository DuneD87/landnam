class_name AppearanceOption
extends RefCounted

## One editable trait of a character (a slider, a colour or a choice) and how
## it reaches the model. AppearanceCatalog declares them; the creation UI and
## CharacterAppearanceRig only read these fields, so a new trait needs no code
## beyond its declaration (and, for a new morph, a bake).

enum Kind { SLIDER, COLOR, CHOICE }

var id: StringName
var label: String
var kind: Kind
var default_value: Variant
## Slider range as shown to the player.
var min_value := -1.0
var max_value := 1.0
## Where the value goes. A slider maps its range linearly onto
## `target_range` for the target (morph weight, shader value or proportion).
var morph: StringName
var shader_param: StringName
var proportion: StringName
var target_range := Vector2(-1.0, 1.0)
## Colour swatches, for COLOR.
var palette: PackedColorArray
## [{id, label}], for CHOICE.
var choices: Array[Dictionary] = []
## Sexes the option is offered to; empty means all. Hidden options keep
## their default for that sex (see default_for).
var sexes: Array[StringName] = []
## Per-sex defaults overriding default_value.
var sex_defaults := {}


func is_available(sex: StringName) -> bool:
	return sexes.is_empty() or sex in sexes


func default_for(sex: StringName) -> Variant:
	return sex_defaults.get(sex, default_value)


## The slider value mapped onto the target's range.
func target_value(value: float) -> float:
	return lerpf(target_range.x, target_range.y, inverse_lerp(min_value, max_value, value))


func choice_index(choice: StringName) -> int:
	for i in choices.size():
		if choices[i].id == choice:
			return i
	return -1


## Converts a stored value to JSON-friendly form and back.
func serialize(value: Variant) -> Variant:
	match kind:
		Kind.COLOR:
			return (value as Color).to_html(false)
		Kind.CHOICE:
			return String(value)
	return value


func deserialize(value: Variant) -> Variant:
	match kind:
		Kind.COLOR:
			return Color.from_string(str(value), default_value)
		Kind.CHOICE:
			var choice := StringName(str(value))
			return choice if choice_index(choice) >= 0 else default_value
	return clampf(float(value), min_value, max_value)

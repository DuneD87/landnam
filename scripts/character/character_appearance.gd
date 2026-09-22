class_name CharacterAppearance
extends Resource

## A character's looks: values of AppearanceCatalog options, by option id.
## Options never touched are not stored; reads fall back to the option's
## default for the character's sex, so appearances saved before an option
## existed load with its default.

@export var values := {}


func get_sex() -> StringName:
	return get_value(AppearanceCatalog.SEX)


## The value the model shows: an option hidden for this sex uses that sex's
## default instead of whatever was stored (e.g. no beard on a female body).
func get_value(id: StringName) -> Variant:
	var option := AppearanceCatalog.find(id)
	if option == null:
		return values.get(id)
	var sex: StringName = values.get(AppearanceCatalog.SEX, AppearanceCatalog.find(AppearanceCatalog.SEX).default_value)
	if id != AppearanceCatalog.SEX and not option.is_available(sex):
		return option.default_for(sex)
	return values.get(id, option.default_for(sex))


func set_value(id: StringName, value: Variant) -> void:
	values[id] = value
	emit_changed()


## Changing sex resets the options whose default depends on it (hair style,
## beard...), so the new body starts from sensible values.
func set_sex(sex: StringName) -> void:
	values[AppearanceCatalog.SEX] = sex
	for option in AppearanceCatalog.all_options():
		if option.sex_defaults.has(sex):
			values.erase(option.id)
	emit_changed()


func reset() -> void:
	var sex := get_sex()
	values.clear()
	values[AppearanceCatalog.SEX] = sex
	emit_changed()


## Random values for every option offered to the current sex. Sliders stay
## near the middle, so the result is varied but rarely extreme.
func randomize_values(rng: RandomNumberGenerator) -> void:
	var sex := get_sex()
	for option in AppearanceCatalog.all_options():
		if option.id == AppearanceCatalog.SEX or not option.is_available(sex):
			continue
		match option.kind:
			AppearanceOption.Kind.SLIDER:
				var mid := (option.min_value + option.max_value) * 0.5
				var half := (option.max_value - option.min_value) * 0.5
				values[option.id] = clampf(mid + rng.randfn(0.0, 0.35) * half, option.min_value, option.max_value)
			AppearanceOption.Kind.COLOR:
				values[option.id] = option.palette[rng.randi() % option.palette.size()]
			AppearanceOption.Kind.CHOICE:
				values[option.id] = option.choices[rng.randi() % option.choices.size()].id
	emit_changed()


func to_dict() -> Dictionary:
	var result := {}
	for id in values:
		var option := AppearanceCatalog.find(id)
		result[String(id)] = option.serialize(values[id]) if option else values[id]
	return result


static func from_dict(data: Dictionary) -> CharacterAppearance:
	var appearance := CharacterAppearance.new()
	for key in data:
		var option := AppearanceCatalog.find(StringName(key))
		if option == null:
			push_warning("CharacterAppearance: unknown option '%s' ignored" % key)
			continue
		appearance.values[option.id] = option.deserialize(data[key])
	return appearance

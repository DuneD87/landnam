class_name CharacterAppearance
extends Resource

## A character's looks: values of AppearanceCatalog options, by option id.
## Options never touched are not stored; reads fall back to the option's
## default for the character's sex, so appearances saved before an option
## existed load with its default.

@export var values := {}


func get_sex() -> StringName:
	return get_value(AppearanceCatalog.SEX)


## The value the model shows: an option hidden for this sex, or a choice it
## does not offer, uses that sex's default instead of what was stored.
func get_value(id: StringName) -> Variant:
	var option := AppearanceCatalog.find(id)
	if option == null:
		return values.get(id)
	var sex: StringName = values.get(AppearanceCatalog.SEX, AppearanceCatalog.find(AppearanceCatalog.SEX).default_value)
	if id != AppearanceCatalog.SEX and not option.is_available(sex):
		return option.default_for(sex)
	var value: Variant = values.get(id, option.default_for(sex))
	if option.kind == AppearanceOption.Kind.CHOICE and id != AppearanceCatalog.SEX and not option.offers(value, sex):
		return option.default_for(sex)
	return value


func set_value(id: StringName, value: Variant) -> void:
	values[id] = value
	emit_changed()


## Changing sex resets the options whose default depends on it (hair style,
## eyebrows, skin...), so the new body starts from sensible values.
func set_sex(sex: StringName) -> void:
	values[AppearanceCatalog.SEX] = sex
	for option in AppearanceCatalog.all_options():
		if option.sex_defaults.has(sex) and option.id != AppearanceCatalog.SEX:
			values.erase(option.id)
	emit_changed()


## Sets every value a preset lists; the other options of the preset's
## categories go back to their defaults.
func apply_preset(option: AppearanceOption, preset_id: StringName) -> void:
	var i := option.choice_index(preset_id)
	if i < 0:
		return
	for id in AppearanceCatalog.preset_scope(option.id):
		values.erase(id)
	var preset: Dictionary = option.choices[i]
	for id in preset.get("values", {}):
		values[id] = preset.values[id]
	values[option.id] = preset_id
	emit_changed()


func reset() -> void:
	var sex := get_sex()
	values.clear()
	values[AppearanceCatalog.SEX] = sex
	emit_changed()


## A random character of the current sex: a random face preset nudged a
## little, a moderate body, and random colours and styles. Sliders stay near
## the middle, so the result is varied but rarely extreme.
func randomize_values(rng: RandomNumberGenerator, only: Array[AppearanceOption] = []) -> void:
	var sex := get_sex()
	var options := only if not only.is_empty() else AppearanceCatalog.all_options()
	for option in options:
		if option.kind == AppearanceOption.Kind.PRESET and option.is_available(sex):
			var presets := option.choices_for(sex)
			if not presets.is_empty():
				var preset: Dictionary = presets[rng.randi() % presets.size()]
				for id in AppearanceCatalog.preset_scope(option.id):
					values.erase(id)
				for id in preset.get("values", {}):
					values[id] = preset.values[id]
				values[option.id] = preset.id
	for option in options:
		if option.id == AppearanceCatalog.SEX or not option.is_available(sex):
			continue
		match option.kind:
			AppearanceOption.Kind.SLIDER:
				var mid := (option.min_value + option.max_value) * 0.5
				var half := (option.max_value - option.min_value) * 0.5
				var spread := AppearanceCatalog.random_spread(option.id)
				var current: float = values.get(option.id, option.default_for(sex))
				var centre := current if values.has(option.id) else mid
				values[option.id] = clampf(centre + rng.randfn(0.0, spread) * half, option.min_value, option.max_value)
			AppearanceOption.Kind.COLOR:
				values[option.id] = option.palette[rng.randi() % option.palette.size()]
			AppearanceOption.Kind.CHOICE:
				var offered := option.choices_for(sex)
				values[option.id] = offered[rng.randi() % offered.size()].id
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

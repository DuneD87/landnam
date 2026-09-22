class_name AppearanceCatalog
extends RefCounted

## Everything the player can edit about a character's looks, grouped into the
## categories the creation screen shows. To add a trait, add a line to a
## category (see AppearanceOption for the fields); a new category is a new
## entry in _build(). `focus` tells the preview camera where to look.
##
## Morph sliders name a morph baked by tools/character/bake_character_human.gd.
## CharacterAppearanceRig resolves the name: "<id>" for positive values,
## "<id>-" for negative ones, each possibly split per sex ("<id>@female").
##
## Sexes, hair styles and eyebrows are data tables too: a sex adds morphs and
## shader values and picks its eyelashes (and how thick they look); hair
## styles and eyebrows name the
## baked part to show (data/character/human/<part>.res).

const SEX := &"sex"
const HAIR_STYLE := &"hair_style"
const EYEBROWS := &"eyebrows"

const SEXES := {
	&"male": {label = "Masculino", eyelashes = &"eyelashes_01", eyelash_density = 0.7},
	&"female": {
		label = "Femenino",
		morphs = {&"sex_female": 1.0},
		eyelashes = &"eyelashes_02",
		eyelash_density = 1.4,
	},
}

## `part` is the baked hair mesh; empty is bald.
const HAIR_STYLES := {
	&"short02": {label = "Corto", part = &"hair_short02"},
	&"short04": {label = "Engominado", part = &"hair_short04"},
	&"short01": {label = "Rizado", part = &"hair_short01"},
	&"short03": {label = "Flequillo", part = &"hair_short03"},
	&"bob02": {label = "Melena asimétrica", part = &"hair_bob02"},
	&"bob01": {label = "Melena", part = &"hair_bob01"},
	&"ponytail01": {label = "Coleta", part = &"hair_ponytail01"},
	&"long01": {label = "Largo", part = &"hair_long01"},
	&"braid01": {label = "Trenza", part = &"hair_braid01"},
	&"bald": {label = "Calvo", part = &""},
}

const EYEBROW_STYLES := {
	&"eyebrow001": {label = "1", part = &"eyebrows_001"},
	&"eyebrow002": {label = "2", part = &"eyebrows_002"},
	&"eyebrow003": {label = "3", part = &"eyebrows_003"},
	&"eyebrow004": {label = "4", part = &"eyebrows_004"},
	&"eyebrow005": {label = "5", part = &"eyebrows_005"},
	&"eyebrow006": {label = "6", part = &"eyebrows_006"},
	&"eyebrow007": {label = "7", part = &"eyebrows_007"},
	&"eyebrow008": {label = "8", part = &"eyebrows_008"},
	&"eyebrow009": {label = "9", part = &"eyebrows_009"},
	&"eyebrow010": {label = "10", part = &"eyebrows_010"},
	&"eyebrow011": {label = "11", part = &"eyebrows_011"},
	&"eyebrow012": {label = "12", part = &"eyebrows_012"},
}

const SKIN_TONES := ["f2d3c0", "e0a98a", "d49a76", "b97d5a", "9a6242", "7a4a31", "5a3423", "3e2418"]
const HAIR_COLORS := ["120e0b", "2e1f15", "4a3222", "6e4b30", "9c7449", "cfae74", "8a3d1e", "b5b0a8", "e6e1d8"]
const EYE_COLORS := ["5b3d25", "7a5a34", "5f7a3e", "3f6f9a", "7593ab", "7b7c74", "2a1c14"]
const LIP_COLORS := ["b8625c", "c98079", "a04848", "8a3a3a", "6a2a30", "d69a94"]
const EYESHADOW_COLORS := ["3a2c2a", "5a4636", "6a4a5e", "3e4a5e", "7a6a52", "8a5a4a"]

static var _categories: Array[Dictionary] = []
static var _by_id := {}


## [{id, label, focus, options: Array[AppearanceOption]}]
static func categories() -> Array[Dictionary]:
	if _categories.is_empty():
		_build()
	return _categories


static func find(id: StringName) -> AppearanceOption:
	if _categories.is_empty():
		_build()
	return _by_id.get(id)


## Every option, including the sex selector that lives outside the categories.
static func all_options() -> Array[AppearanceOption]:
	if _categories.is_empty():
		_build()
	var result: Array[AppearanceOption] = []
	for option in _by_id.values():
		result.append(option)
	return result


static func _build() -> void:
	_register(_choice(SEX, "Sexo", &"male", SEXES))
	_category(&"body", "Cuerpo", &"body", [
		_proportion(&"height", "Altura", Vector2(-0.08, 0.08)),
		_morph(&"body_weight", "Peso"),
		_morph(&"muscle", "Musculatura"),
		_morph(&"age", "Edad"),
		_proportion(&"shoulder_width", "Hombros", Vector2(-0.2, 0.25)),
		_morph(&"torso_vshape", "Espalda en V"),
		_morph(&"pectorals", "Pectorales"),
		_for_sexes(_morph(&"breast_size", "Pecho"), [&"female"]),
		_for_sexes(_morph(&"breast_firmness", "Firmeza del pecho"), [&"female"]),
		_morph(&"abdomen", "Abdomen"),
		_morph(&"waist", "Cintura"),
		_morph(&"hips", "Caderas"),
		_morph(&"glutes", "Glúteos"),
	])
	_category(&"head", "Cabeza", &"face", [
		_proportion(&"head_size", "Tamaño", Vector2(-0.07, 0.07)),
		_morph(&"head_width", "Anchura"),
		_morph(&"forehead", "Frente"),
		_morph(&"neck_thickness", "Cuello"),
		_morph(&"jaw_width", "Mandíbula"),
		_morph(&"chin_width", "Anchura del mentón"),
		_morph(&"chin_length", "Largo del mentón"),
		_morph(&"chin_projection", "Mentón saliente"),
		_morph(&"cheekbones", "Pómulos"),
		_morph(&"cheeks", "Mejillas"),
		_morph(&"ear_size", "Orejas"),
		_morph(&"ear_angle", "Orejas separadas"),
	])
	_category(&"eyes", "Ojos", &"face", [
		_color(&"eye_color", "Color", EYE_COLORS, "5b3d25"),
		_morph(&"eye_size", "Tamaño"),
		_morph(&"eye_spacing", "Separación"),
		_morph(&"eye_height", "Altura"),
		_morph(&"eye_tilt", "Inclinación"),
		_choice(EYEBROWS, "Cejas", &"eyebrow001", EYEBROW_STYLES, {&"female": &"eyebrow010"}),
		_morph(&"brow_height", "Altura de las cejas"),
		_morph(&"brow_angle", "Ángulo de las cejas"),
		_morph(&"brow_depth", "Arco superciliar"),
		_color(&"eyeshadow_color", "Sombra de ojos", EYESHADOW_COLORS, "3a2c2a"),
		_shader_slider(&"eyeshadow", "Intensidad de la sombra", Vector2(0.0, 1.0), 0.0, 1.0, 0.0),
	])
	_category(&"nose", "Nariz", &"face", [
		_morph(&"nose_size", "Tamaño"),
		_morph(&"nose_width", "Anchura"),
		_morph(&"nose_length", "Longitud"),
		_morph(&"nose_projection", "Proyección"),
		_morph(&"nose_bridge", "Puente"),
		_morph(&"nose_tip", "Punta"),
		_morph(&"nostrils", "Aletas"),
	])
	_category(&"mouth", "Boca", &"face", [
		_morph(&"mouth_width", "Anchura"),
		_morph(&"mouth_height", "Altura"),
		_morph(&"mouth_projection", "Proyección"),
		_morph(&"upper_lip", "Labio superior"),
		_morph(&"lower_lip", "Labio inferior"),
		_morph(&"mouth_corners", "Comisuras"),
		_color(&"lip_color", "Color de labios", LIP_COLORS, "b8625c"),
		_shader_slider(&"lip_tint", "Intensidad del color", Vector2(0.0, 1.0), 0.0, 1.0, 0.0),
	])
	_category(&"hair", "Cabello", &"head", [
		_choice(HAIR_STYLE, "Peinado", &"short02", HAIR_STYLES, {&"female": &"long01"}),
		_color(&"hair_color", "Color", HAIR_COLORS, "3b2a1e"),
	])
	_category(&"skin", "Piel", &"body", [
		_color(&"skin_color", "Tono de piel", SKIN_TONES, "e0a98a"),
	])


static func _category(id: StringName, label: String, focus: StringName, options: Array) -> void:
	var typed: Array[AppearanceOption] = []
	for option in options:
		typed.append(_register(option))
	_categories.append({id = id, label = label, focus = focus, options = typed})


static func _register(option: AppearanceOption) -> AppearanceOption:
	assert(not _by_id.has(option.id), "Duplicate appearance option %s" % option.id)
	_by_id[option.id] = option
	return option


static func _slider(id: StringName, label: String, min_value: float, max_value: float, default_value: float) -> AppearanceOption:
	var option := AppearanceOption.new()
	option.id = id
	option.label = label
	option.kind = AppearanceOption.Kind.SLIDER
	option.min_value = min_value
	option.max_value = max_value
	option.default_value = default_value
	option.target_range = Vector2(min_value, max_value)
	return option


## Slider driving the blend shape of the same name, weight = slider value.
static func _morph(id: StringName, label: String, min_value := -1.0, max_value := 1.0) -> AppearanceOption:
	var option := _slider(id, label, min_value, max_value, 0.0)
	option.morph = id
	return option


## Slider driving BodyProportions; `target_range` is the proportion at the ends.
static func _proportion(id: StringName, label: String, target_range: Vector2) -> AppearanceOption:
	var option := _slider(id, label, -1.0, 1.0, 0.0)
	option.proportion = id
	option.target_range = target_range
	return option


## Slider driving the skin shader uniform of the same name.
static func _shader_slider(id: StringName, label: String, target_range: Vector2, min_value := -1.0,
		max_value := 1.0, default_value := 0.0) -> AppearanceOption:
	var option := _slider(id, label, min_value, max_value, default_value)
	option.shader_param = id
	option.target_range = target_range
	return option


static func _color(id: StringName, label: String, palette: Array, default_hex: String) -> AppearanceOption:
	var option := AppearanceOption.new()
	option.id = id
	option.label = label
	option.kind = AppearanceOption.Kind.COLOR
	option.shader_param = id
	option.default_value = Color(default_hex)
	for hex in palette:
		option.palette.append(Color(hex))
	return option


static func _choice(id: StringName, label: String, default_value: StringName, table: Dictionary,
		sex_defaults := {}) -> AppearanceOption:
	var option := AppearanceOption.new()
	option.id = id
	option.label = label
	option.kind = AppearanceOption.Kind.CHOICE
	option.default_value = default_value
	option.sex_defaults = sex_defaults
	for key in table:
		option.choices.append({id = key, label = table[key].label})
	return option


static func _for_sexes(option: AppearanceOption, sexes: Array, sex_defaults := {}) -> AppearanceOption:
	option.sexes.assign(sexes)
	option.sex_defaults = sex_defaults
	return option

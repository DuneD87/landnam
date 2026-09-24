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
## Sexes, hair styles, beards, eyebrows and skins are data tables too: a sex
## adds morphs and picks its eyelashes (and genitals); the others name the baked proxy
## (data/character/human/proxies/<part>.res) or skin to show, and the sexes
## that are offered them.

const SEX := &"sex"
const HAIR_STYLE := &"hair_style"
const BEARD := &"beard"
const EYEBROWS := &"eyebrows"
const SKIN := &"skin"
const FACE_PRESET := &"face_preset"

const SEXES := {
	&"male": {label = "Masculino", eyelashes = &"eyelashes_01", eyelash_density = 0.7, genitals = &"genitals"},
	&"female": {label = "Femenino", morphs = {&"sex_female": 1.0}, eyelashes = &"eyelashes_02", eyelash_density = 1.4},
}

const _MALE: Array[StringName] = [&"male"]
const _FEMALE: Array[StringName] = [&"female"]

## `part` is the baked hair; empty is none. `scalp` paints a buzz cut on the
## scalp (0 none, 1 full).
const HAIR_STYLES := {
	&"textured": {label = "Corto", part = &"hair_short01", sexes = _MALE},
	&"fringe": {label = "Flequillo", part = &"hair_short03", sexes = _MALE},
	&"classic": {label = "Clásico", part = &"hair_culturalibre_hair_02", sexes = _MALE},
	&"pompadour": {label = "Tupé", part = &"hair_elvs_maxwell_hair", sexes = _MALE},
	&"slicked": {label = "Peinado atrás", part = &"hair_culturalibre_hair_14", sexes = _MALE},
	&"side_part": {label = "Raya al lado", part = &"hair_elvs_short_side_do", sexes = _MALE},
	&"wavy_m": {label = "Ondulado", part = &"hair_elvs_grump_hair", sexes = _MALE},
	&"half_up": {label = "Semirrecogido", part = &"hair_faydaen_hair_1", sexes = _MALE},
	&"topknot": {label = "Moño", part = &"hair_rehmanpolanski_hair_bun_brown", sexes = _MALE},
	&"long_m": {label = "Largo", part = &"hair_punkduck_alpha7_long", sexes = _MALE},
	&"long_straight": {label = "Largo liso", part = &"hair_long01", sexes = _FEMALE},
	&"side_swept": {label = "De lado", part = &"hair_elvs_adrienne_hair", sexes = _FEMALE},
	&"wavy_f": {label = "Ondulado", part = &"hair_elvs_that_80s_babe_hair", sexes = _FEMALE},
	&"layered": {label = "Flequillo", part = &"hair_elvs_katherine_hair", sexes = _FEMALE},
	&"curly": {label = "Rizado", part = &"hair_punkduck_alpha7_curly", sexes = _FEMALE},
	&"braid": {label = "Trenza", part = &"hair_braid01", sexes = _FEMALE},
	&"french_braid": {label = "Trenza francesa", part = &"hair_elvs_unkempt_french_braid", sexes = _FEMALE},
	&"two_braids": {label = "Dos trenzas", part = &"hair_elvs_double_mh_braid", sexes = _FEMALE},
	&"ponytail": {label = "Coleta", part = &"hair_elvs_keylth_hair", sexes = _FEMALE},
	&"updo": {label = "Recogido", part = &"hair_elvs_50s_updo", sexes = _FEMALE},
	&"bob": {label = "Media melena", part = &"hair_toigo_blunt_bob_with_bangs", sexes = _FEMALE},
	&"wavy_bob": {label = "Bob ondulado", part = &"hair_elvs_wavy_bob", sexes = _FEMALE},
	&"cornrows": {label = "Trenzas pegadas", part = &"hair_elvs_braided_rows", sexes = _FEMALE},
	&"afro_puffs": {label = "Afro", part = &"hair_elvs_micky_afro", sexes = _FEMALE},
	&"braided_bun": {label = "Moño trenzado", part = &"hair_grinsegold_wig_bun_blonde_braids", sexes = _FEMALE},
	&"buzz": {label = "Rapado", part = &"", scalp = 1.0},
	&"bald": {label = "Calvo", part = &""},
}

const BEARDS := {
	&"none": {label = "Sin barba", part = &""},
	&"full": {label = "Completa", part = &"beard_grinsegold_full_beard"},
	&"long": {label = "Larga", part = &"beard_elvs_scruffy_beard1"},
	&"viking": {label = "Vikinga", part = &"beard_rehmanpolanski_beard_viking"},
	&"goatee": {label = "Perilla", part = &"beard_culturalibre_faun_beard"},
	&"moustache": {label = "Bigote", part = &"beard_grinsegold_moustache"},
	&"long_moustache": {label = "Bigote largo", part = &"beard_rehmanpolanski_moustache_viking"},
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

## Skin textures (HumanBodyData.skins), per sex.
const SKINS := {
	&"light_m": {label = "Clara", sexes = _MALE},
	&"freckles_m": {label = "Pecas", sexes = _MALE},
	&"bronze_m": {label = "Bronceada", sexes = _MALE},
	&"rugged_m": {label = "Curtida", sexes = _MALE},
	&"mature_m": {label = "Madura", sexes = _MALE},
	&"tattoo_m": {label = "Tatuada", sexes = _MALE},
	&"dark_m": {label = "Oscura", sexes = _MALE},
	&"asian_m": {label = "Asiática", sexes = _MALE},
	&"light_f": {label = "Clara", sexes = _FEMALE},
	&"freckles_f": {label = "Pecas", sexes = _FEMALE},
	&"bronze_f": {label = "Bronceada", sexes = _FEMALE},
	&"ginger_f": {label = "Pelirroja", sexes = _FEMALE},
	&"midtone_f": {label = "Tono medio", sexes = _FEMALE},
	&"zoey_f": {label = "Lunares", sexes = _FEMALE},
	&"dark_f": {label = "Oscura", sexes = _FEMALE},
	&"asian_f": {label = "Asiática", sexes = _FEMALE},
}

const SKIN_TONES := ["f0cdb8", "e0a98a", "d49a78", "bf865f", "a06a47", "7f4f34", "5c3826", "3d2519"]
const HAIR_COLORS := ["0f0c0a", "2a1c13", "46301f", "6b4a2f", "93704a", "c9a877", "e2cfa3", "8c3b1c", "b35a2c",
		"9a948c", "d8d4cc"]
const EYE_COLORS := ["4a2e1b", "6e4a2a", "8a6a3a", "5f7a3e", "3f6f9a", "7593ab", "7b7c74", "2a1c14"]
const LIP_COLORS := ["b8625c", "c98079", "a04848", "8a3a3a", "6a2a30", "d69a94"]
const EYESHADOW_COLORS := ["3a2c2a", "5a4636", "6a4a5e", "3e4a5e", "7a6a52", "8a5a4a"]

## Face presets per sex: starting points the sliders refine. Each sex's
## default preset is where its face sliders start (so "Restablecer" returns
## to it); every face option another preset does not list goes back there.
const FACE_PRESETS := [
	{id = &"m_default", label = "1", sexes = _MALE, values = {
		&"head_square": 0.3, &"jaw_width": 0.3, &"chin_projection": 0.25, &"chin_width": 0.15,
		&"cheekbones": 0.3, &"cheeks": -0.15, &"brow_depth": 0.25, &"eye_depth": 0.15, &"nose_bridge": 0.15,
		&"upper_lip": -0.1, &"head_size": 0.4, &"neck_thickness": 0.2, &"neck_length": 0.3, &"nape": 0.1,
	}},
	{id = &"m_rugged", label = "2", sexes = _MALE, values = {
		&"head_square": 0.6, &"jaw_width": 0.55, &"jaw_angle": 0.3, &"chin_width": 0.4, &"chin_cleft": 0.5,
		&"brow_depth": 0.5, &"brow_height": -0.25, &"eye_depth": 0.35, &"eye_opening": -0.2, &"nose_size": 0.25,
		&"nose_bridge": 0.4, &"nose_curve": 0.3, &"cheekbones": 0.35, &"cheeks": -0.3, &"upper_lip": -0.3,
		&"lower_lip": -0.2, &"neck_thickness": 0.6,
	}},
	{id = &"m_young", label = "3", sexes = _MALE, values = {
		&"head_oval": 0.6, &"jaw_width": -0.2, &"chin_length": 0.2, &"cheeks": -0.2, &"cheekbones": 0.4,
		&"eye_size": 0.2, &"eye_opening": 0.15, &"nose_width": -0.2, &"nose_size": -0.15, &"upper_lip": 0.1,
		&"lower_lip": 0.2, &"neck_length": 0.2,
	}},
	{id = &"m_gaunt", label = "4", sexes = _MALE, values = {
		&"head_diamond": 0.6, &"cheeks": -0.6, &"cheeks_inner": -0.4, &"cheekbones": 0.6, &"temples": -0.3,
		&"eye_depth": 0.5, &"nose_bridge": 0.6, &"nose_length": 0.3, &"chin_length": 0.35,
		&"chin_projection": 0.3, &"mouth_width": -0.1, &"upper_lip": -0.35, &"lower_lip": -0.25,
	}},
	{id = &"m_heavy", label = "5", sexes = _MALE, values = {
		&"head_fat": 0.6, &"head_round": 0.5, &"cheeks": 0.5, &"neck_thickness": 0.7, &"nose_size": 0.3,
		&"nose_tip": 0.3, &"nose_width": 0.25, &"eye_size": -0.15, &"chin_length": -0.2, &"jaw_width": 0.3,
		&"lower_lip": 0.15,
	}},
	{id = &"m_african", label = "6", sexes = _MALE, values = {
		&"race_african": 0.8, &"head_round": 0.3, &"jaw_width": 0.3, &"cheekbones": 0.3, &"brow_depth": 0.2,
		&"chin_projection": 0.2, &"neck_thickness": 0.3,
	}},
	{id = &"m_asian", label = "7", sexes = _MALE, values = {
		&"race_asian": 0.8, &"head_round": 0.2, &"cheekbones": 0.4, &"jaw_angle": 0.2, &"chin_projection": 0.15,
		&"neck_thickness": 0.3,
	}},
	{id = &"f_default", label = "1", sexes = _FEMALE, values = {
		&"head_oval": 0.5, &"jaw_width": -0.3, &"jaw_angle": -0.2, &"chin_width": -0.3, &"chin_length": -0.1,
		&"chin_projection": 0.1, &"cheekbones": 0.45, &"cheekbone_height": 0.2, &"cheeks": -0.1,
		&"eye_size": 0.3, &"eye_opening": 0.2, &"eye_tilt": 0.15, &"brow_height": 0.15, &"brow_depth": -0.4,
		&"nose_size": -0.25, &"nose_width": -0.25, &"nose_tip_width": -0.2, &"nose_bridge": -0.15,
		&"upper_lip": 0.35, &"lower_lip": 0.4, &"cupids_bow": 0.3, &"forehead": -0.1, &"neck_thickness": -0.3,
		&"head_size": 0.3, &"neck_length": 0.4, &"ear_size": -0.2,
	}},
	{id = &"f_strong", label = "2", sexes = _FEMALE, values = {
		&"head_square": 0.35, &"jaw_width": 0.1, &"cheekbones": 0.55, &"eye_depth": 0.2, &"eye_tilt": 0.2,
		&"brow_depth": -0.1, &"nose_bridge": 0.25, &"nose_length": 0.15, &"upper_lip": 0.2, &"lower_lip": 0.2,
		&"chin_projection": 0.25, &"neck_thickness": -0.1,
	}},
	{id = &"f_soft", label = "3", sexes = _FEMALE, values = {
		&"head_round": 0.5, &"cheeks": 0.35, &"eye_size": 0.4, &"eye_opening": 0.3, &"nose_size": -0.35,
		&"nose_tip": 0.2, &"upper_lip": 0.3, &"lower_lip": 0.45, &"chin_length": -0.25, &"jaw_width": -0.2,
		&"brow_depth": -0.4, &"neck_thickness": -0.3, &"ear_size": -0.2,
	}},
	{id = &"f_heart", label = "4", sexes = _FEMALE, values = {
		&"head_triangular": 0.5, &"forehead": 0.2, &"eye_size": 0.35, &"eye_tilt": 0.25, &"cheekbones": 0.5,
		&"chin_width": -0.4, &"chin_length": 0.15, &"jaw_width": -0.4, &"nose_size": -0.2, &"upper_lip": 0.3,
		&"lower_lip": 0.35, &"cupids_bow": 0.4, &"brow_depth": -0.35, &"neck_thickness": -0.3,
	}},
	{id = &"f_angular", label = "5", sexes = _FEMALE, values = {
		&"head_diamond": 0.4, &"cheekbones": 0.6, &"cheeks": -0.4, &"temples": -0.2, &"eye_depth": 0.3,
		&"eye_tilt": 0.3, &"nose_bridge": 0.3, &"nose_length": 0.2, &"upper_lip": -0.1, &"lower_lip": 0.1,
		&"chin_length": 0.2, &"jaw_angle": 0.2, &"brow_depth": -0.2, &"neck_thickness": -0.2,
	}},
	{id = &"f_african", label = "6", sexes = _FEMALE, values = {
		&"race_african": 0.8, &"jaw_width": -0.2, &"eye_size": 0.2, &"cheekbones": 0.4, &"brow_depth": -0.3,
		&"nose_size": -0.1, &"upper_lip": 0.2, &"lower_lip": 0.2, &"neck_thickness": -0.3,
	}},
	{id = &"f_asian", label = "7", sexes = _FEMALE, values = {
		&"race_asian": 0.8, &"head_oval": 0.3, &"eye_size": 0.15, &"jaw_width": -0.3, &"chin_length": 0.1,
		&"nose_size": -0.2, &"cheekbones": 0.3, &"upper_lip": 0.2, &"lower_lip": 0.25, &"brow_depth": -0.3,
		&"neck_thickness": -0.3,
	}},
]

## How far "Aleatorio" moves a slider from its centre, as a fraction of its
## half range: faces stay near their preset, bodies roam a little more.
const FACE_SPREAD := 0.12
const BODY_SPREAD := 0.3

static var _categories: Array[Dictionary] = []
static var _by_id := {}
static var _category_of := {}


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


## Options a face preset resets: every slider of the face categories.
static func preset_scope(_preset_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for category in categories():
		if category.focus != &"face":
			continue
		for option in category.options:
			if option.kind == AppearanceOption.Kind.SLIDER and option.morph:
				result.append(option.id)
	return result


static func random_spread(id: StringName) -> float:
	if _categories.is_empty():
		_build()
	var category: Dictionary = _category_of.get(id, {})
	return FACE_SPREAD if category.get("focus", &"") == &"face" else BODY_SPREAD


static func _build() -> void:
	_register(_choice(SEX, "Sexo", &"male", SEXES))
	_category(&"body", "Cuerpo", &"body", [
		_morph(&"height", "Altura", -1.0, 1.0, Vector2(-0.6, 0.35)),
		_for_sexes(_morph(&"body_weight", "Peso"), [], {&"male": 0.1}),
		_for_sexes(_morph(&"muscle", "Musculatura"), [], {&"male": 0.3}),
		_for_sexes(_shader_slider(&"definition", "Definición muscular", Vector2(0.15, 1.45), -1.0, 1.0, 0.0), [],
				{&"male": -0.5, &"female": -0.5}),
		_morph(&"age", "Edad"),
		# The middle is MakeHuman's narrowest; wider read as bulky on these bodies.
		_morph(&"shoulder_width", "Hombros", -1.0, 1.0, Vector2(-2.0, 0.0)),
		_for_sexes(_morph(&"chest_depth", "Tórax"), [], {&"male": 0.6, &"female": 0.15}),
		_for_sexes(_morph(&"torso_width", "Anchura del torso"), [], {&"male": 0.15}),
		_morph(&"torso_vshape", "Espalda en V"),
		_for_sexes(_morph(&"lats", "Dorsales"), [], {&"male": 0.3}),
		_for_sexes(_morph(&"pectorals", "Pectorales"), _MALE),
		_for_sexes(_morph(&"breast_size", "Pecho"), _FEMALE, {&"female": 0.3}),
		_for_sexes(_morph(&"breast_firmness", "Firmeza del pecho"), _FEMALE),
		_for_sexes(_morph(&"breast_position", "Altura del pecho"), _FEMALE),
		_for_sexes(_morph(&"breast_spacing", "Separación del pecho"), _FEMALE),
		_for_sexes(_morph(&"penis_length", "Longitud del pene", -1.0, 1.0, Vector2(-1.0, 0.5)), _MALE),
		_for_sexes(_morph(&"penis_girth", "Grosor del pene"), _MALE),
		_for_sexes(_morph(&"testicles", "Testículos"), _MALE),
		_shader_slider(&"pubic_hair", "Vello púbico", Vector2(0.0, 1.0), 0.0, 1.0, 0.5),
		_morph(&"abdomen", "Abdomen"),
		_morph(&"waist", "Cintura"),
		_morph(&"hips", "Caderas"),
		_morph(&"glutes", "Glúteos"),
		_morph(&"arms", "Brazos"),
		_morph(&"legs", "Piernas"),
	])
	_category(&"head", "Cabeza", &"face", [
		_choice(FACE_PRESET, "Rostros", &"m_default", {}, {&"female": &"f_default"}, AppearanceOption.Kind.PRESET),
		_morph(&"race_african", "Rasgos africanos", 0.0, 1.0),
		_morph(&"race_asian", "Rasgos asiáticos", 0.0, 1.0),
		_morph(&"head_size", "Tamaño"),
		_morph(&"head_width", "Anchura"),
		_morph(&"head_round", "Redondeada", 0.0, 1.0),
		_morph(&"head_square", "Cuadrada", 0.0, 1.0),
		_morph(&"head_oval", "Ovalada", 0.0, 1.0),
		_morph(&"head_diamond", "Angulosa", 0.0, 1.0),
		_morph(&"head_triangular", "Triangular"),
		_morph(&"head_fat", "Carnosidad"),
		_morph(&"forehead", "Frente alta"),
		_morph(&"forehead_slope", "Frente inclinada"),
		_morph(&"temples", "Sienes"),
		_morph(&"neck_thickness", "Cuello grueso"),
		_morph(&"neck_length", "Cuello largo"),
		_morph(&"nape", "Nuca"),
		_morph(&"ear_size", "Orejas"),
		_morph(&"ear_angle", "Orejas separadas"),
		_morph(&"ear_lobe", "Lóbulos"),
		_morph(&"ear_pointed", "Orejas puntiagudas", 0.0, 1.0),
	])
	_category(&"jaw", "Mandíbula", &"face", [
		_morph(&"jaw_width", "Mandíbula ancha"),
		_morph(&"jaw_angle", "Ángulo de la mandíbula"),
		_morph(&"chin_width", "Mentón ancho"),
		_morph(&"chin_length", "Mentón largo"),
		_morph(&"chin_projection", "Mentón saliente"),
		_morph(&"chin_cleft", "Hoyuelo en el mentón", 0.0, 1.0),
		_morph(&"cheekbones", "Pómulos"),
		_morph(&"cheekbone_height", "Altura de los pómulos"),
		_morph(&"cheeks", "Mejillas"),
		_morph(&"cheeks_inner", "Mejilla interior"),
	])
	_category(&"eyes", "Ojos", &"face", [
		_color(&"eye_color", "Color", EYE_COLORS, "4a2e1b", &"eyes"),
		_morph(&"eye_size", "Tamaño"),
		_morph(&"eye_spacing", "Separación"),
		_morph(&"eye_height", "Altura"),
		_morph(&"eye_tilt", "Inclinación"),
		_morph(&"eye_depth", "Hundidos"),
		_morph(&"eye_opening", "Apertura"),
		_morph(&"eyelid", "Párpado"),
		_morph(&"epicanthus", "Pliegue del párpado"),
		_morph(&"eye_bags", "Ojeras"),
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
		_morph(&"nose_bridge", "Caballete"),
		_morph(&"nose_bridge_width", "Anchura del puente"),
		_morph(&"nose_curve", "Curva"),
		_morph(&"nose_tip", "Punta"),
		_morph(&"nose_tip_width", "Anchura de la punta"),
		_morph(&"nostrils", "Aletas"),
		_morph(&"nose_flaring", "Orificios"),
	])
	_category(&"mouth", "Boca", &"face", [
		_morph(&"mouth_width", "Anchura"),
		_morph(&"mouth_height", "Altura"),
		_morph(&"mouth_projection", "Proyección"),
		_morph(&"upper_lip", "Labio superior"),
		_morph(&"lower_lip", "Labio inferior"),
		_morph(&"mouth_corners", "Comisuras"),
		_morph(&"cupids_bow", "Arco de Cupido"),
		_morph(&"philtrum", "Surco del labio"),
		_color(&"lip_color", "Color de labios", LIP_COLORS, "b8625c"),
		_shader_slider(&"lip_tint", "Intensidad del color", Vector2(0.0, 1.0), 0.0, 1.0, 0.0),
	])
	_category(&"hair", "Cabello", &"head", [
		_choice(HAIR_STYLE, "Peinado", &"textured", HAIR_STYLES, {&"female": &"long_straight"}),
		_color(&"hair_color", "Color", HAIR_COLORS, "2a1c13", &"hair"),
		_shader_slider(&"gray", "Canas", Vector2(0.0, 1.0), 0.0, 1.0, 0.0, &"hair"),
		_for_sexes(_choice(BEARD, "Barba", &"none", BEARDS), _MALE),
		_for_sexes(_shader_slider(&"stubble", "Sombra de barba", Vector2(0.0, 1.0), 0.0, 1.0, 0.35), _MALE,
				{&"female": 0.0}),
	])
	_category(&"skin", "Piel", &"body", [
		_choice(SKIN, "Textura", &"light_m", SKINS, {&"female": &"light_f"}),
		_color(&"skin_color", "Tono", SKIN_TONES, "e0a98a"),
	])
	var presets := find(FACE_PRESET)
	presets.choices.clear()
	for preset in FACE_PRESETS:
		presets.choices.append(preset)
	# Every face slider gets a default per sex, so changing sex resets the face.
	for sex in SEXES:
		var start: Dictionary = {}
		for preset in FACE_PRESETS:
			if preset.id == presets.default_for(sex):
				start = preset.values
		for id in preset_scope(FACE_PRESET):
			var option := find(id)
			option.sex_defaults[sex] = start.get(id, option.default_value)


static func _category(id: StringName, label: String, focus: StringName, options: Array) -> void:
	var typed: Array[AppearanceOption] = []
	var category := {id = id, label = label, focus = focus, options = typed}
	for option in options:
		typed.append(_register(option))
		_category_of[option.id] = category
	_categories.append(category)


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


## Slider driving the morph of the same name.
static func _morph(id: StringName, label: String, min_value := -1.0, max_value := 1.0,
		target_range := Vector2.ZERO) -> AppearanceOption:
	var option := _slider(id, label, min_value, max_value, 0.0)
	option.morph = id
	if target_range != Vector2.ZERO:
		option.target_range = target_range
	return option


## Slider driving the shader uniform of the same name on `material`.
static func _shader_slider(id: StringName, label: String, target_range: Vector2, min_value := -1.0,
		max_value := 1.0, default_value := 0.0, material := &"skin") -> AppearanceOption:
	var option := _slider(id, label, min_value, max_value, default_value)
	option.shader_param = id
	option.material = material
	option.target_range = target_range
	return option


static func _color(id: StringName, label: String, palette: Array, default_hex: String, material := &"skin") -> AppearanceOption:
	var option := AppearanceOption.new()
	option.id = id
	option.label = label
	option.kind = AppearanceOption.Kind.COLOR
	option.shader_param = id
	option.material = material
	option.default_value = Color(default_hex)
	for hex in palette:
		option.palette.append(Color(hex))
	return option


static func _choice(id: StringName, label: String, default_value: StringName, table: Dictionary,
		sex_defaults := {}, kind := AppearanceOption.Kind.CHOICE) -> AppearanceOption:
	var option := AppearanceOption.new()
	option.id = id
	option.label = label
	option.kind = kind
	option.default_value = default_value
	option.sex_defaults = sex_defaults
	for key in table:
		var choice := {id = key, label = table[key].label}
		if table[key].has("sexes"):
			choice.sexes = table[key].sexes
		option.choices.append(choice)
	return option


static func _for_sexes(option: AppearanceOption, sexes: Array, sex_defaults := {}) -> AppearanceOption:
	option.sexes.assign(sexes)
	option.sex_defaults = sex_defaults
	return option

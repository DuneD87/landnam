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
## Every label is a key of localization/translations.csv (APP_<option>, APP_CAT_<category>,
## APP_HAIR_<style>...); the creation screen puts it in its controls, which translate it.
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
	&"male": {label = "APP_SEX_MALE", eyelashes = &"eyelashes_01", eyelash_density = 0.7, genitals = &"genitals"},
	&"female": {label = "APP_SEX_FEMALE", morphs = {&"sex_female": 1.0}, eyelashes = &"eyelashes_02", eyelash_density = 1.4},
}

const _MALE: Array[StringName] = [&"male"]
const _FEMALE: Array[StringName] = [&"female"]
const _BOTH: Array[StringName] = [&"male", &"female"]

## `part` is the baked hair; empty is none. Under it the skin paints the roots
## of the scalp it covers (its "cover" texture). `scalp` paints a buzz cut on
## the scalp (0 none, 1 full). The parts are the Hair Tool styles of
## tools/character/hair_tool_styles.json (hair_ht_<style>).
const HAIR_STYLES := {
	&"crew_cut": {label = "APP_HAIR_CREW_CUT", part = &"hair_ht_crew_cut", sexes = _MALE},
	&"very_short": {label = "APP_HAIR_VERY_SHORT", part = &"hair_ht_very_short", sexes = _MALE},
	&"regular": {label = "APP_HAIR_REGULAR", part = &"hair_ht_regular", sexes = _MALE},
	&"side_part": {label = "APP_HAIR_SIDE_PART", part = &"hair_ht_parting", sexes = _MALE},
	&"quiff": {label = "APP_HAIR_QUIFF", part = &"hair_ht_quiff", sexes = _MALE},
	&"spiky": {label = "APP_HAIR_SPIKY", part = &"hair_ht_spiky", sexes = _MALE},
	&"bowl": {label = "APP_HAIR_BOWL", part = &"hair_ht_bowl", sexes = _MALE},
	&"tonsure": {label = "APP_HAIR_TONSURE", part = &"hair_ht_monk", sexes = _MALE},
	&"balding": {label = "APP_HAIR_BALDING", part = &"hair_ht_balding", sexes = _MALE},
	&"tousled": {label = "APP_HAIR_TOUSLED", part = &"hair_ht_split_center", sexes = _MALE},
	&"side_swept": {label = "APP_HAIR_SIDE_SWEPT", part = &"hair_ht_side_flat", sexes = _BOTH},
	&"curtains": {label = "APP_HAIR_CURTAINS", part = &"hair_ht_curtained", sexes = _BOTH},
	&"afro": {label = "APP_HAIR_AFRO", part = &"hair_ht_afro", sexes = _BOTH},
	&"cornrows": {label = "APP_HAIR_CORNROWS", part = &"hair_ht_cornrows", sexes = _BOTH},
	&"topknot": {label = "APP_HAIR_TOPKNOT", part = &"hair_ht_top_knot", sexes = _BOTH},
	&"long_parted": {label = "APP_HAIR_LONG_PARTED", part = &"hair_ht_long_slick", sexes = _BOTH},
	&"long_straight": {label = "APP_HAIR_LONG_STRAIGHT", part = &"hair_ht_long_straight", sexes = _BOTH},
	&"curly": {label = "APP_HAIR_CURLY", part = &"hair_ht_curly", sexes = _BOTH},
	&"ponytail": {label = "APP_HAIR_PONYTAIL", part = &"hair_ht_ponytail", sexes = _BOTH},
	&"braid": {label = "APP_HAIR_BRAID", part = &"hair_ht_braid_back", sexes = _BOTH},
	&"bob": {label = "APP_HAIR_BOB", part = &"hair_ht_bob", sexes = _FEMALE},
	&"braided_bun": {label = "APP_HAIR_BRAIDED_BUN", part = &"hair_ht_braided_bun", sexes = _FEMALE},
	&"two_braids": {label = "APP_HAIR_TWO_BRAIDS", part = &"hair_ht_double_braids", sexes = _FEMALE},
	&"long_layered": {label = "APP_HAIR_LONG_LAYERED", part = &"hair_ht_long_back", sexes = _FEMALE},
	&"french_twist": {label = "APP_HAIR_FRENCH_TWIST", part = &"hair_ht_french_twist", sexes = _FEMALE},
	&"side_ponytail": {label = "APP_HAIR_SIDE_PONYTAIL", part = &"hair_ht_ponytail_side", sexes = _FEMALE},
	&"pigtails": {label = "APP_HAIR_PIGTAILS", part = &"hair_ht_pigtails_back", sexes = _FEMALE},
	&"bun_fringe": {label = "APP_HAIR_BUN_FRINGE", part = &"hair_ht_simple_bun", sexes = _FEMALE},
	&"wavy": {label = "APP_HAIR_WAVY", part = &"hair_ht_wavy", sexes = _FEMALE},
	&"round_bun": {label = "APP_HAIR_ROUND_BUN", part = &"hair_ht_donut_bun", sexes = _FEMALE},
	&"buzz": {label = "APP_HAIR_BUZZ", part = &"", scalp = 1.0},
	&"bald": {label = "APP_HAIR_BALD", part = &""},
}

const BEARDS := {
	&"none": {label = "APP_BEARD_NONE", part = &""},
	&"short": {label = "APP_BEARD_SHORT", part = &"beard_ht_short"},
	&"goatee": {label = "APP_BEARD_GOATEE", part = &"beard_ht_goatee"},
	&"long": {label = "APP_BEARD_LONG", part = &"beard_ht_long_thin"},
	&"viking": {label = "APP_BEARD_VIKING", part = &"beard_ht_long_soft"},
	&"sideburns": {label = "APP_BEARD_SIDEBURNS", part = &"beard_ht_side_whiskers"},
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
	&"light_m": {label = "APP_SKIN_LIGHT_M", sexes = _MALE},
	&"freckles_m": {label = "APP_SKIN_FRECKLES_M", sexes = _MALE},
	&"bronze_m": {label = "APP_SKIN_BRONZE_M", sexes = _MALE},
	&"rugged_m": {label = "APP_SKIN_RUGGED_M", sexes = _MALE},
	&"mature_m": {label = "APP_SKIN_MATURE_M", sexes = _MALE},
	&"tattoo_m": {label = "APP_SKIN_TATTOO_M", sexes = _MALE},
	&"dark_m": {label = "APP_SKIN_DARK_M", sexes = _MALE},
	&"asian_m": {label = "APP_SKIN_ASIAN_M", sexes = _MALE},
	&"light_f": {label = "APP_SKIN_LIGHT_F", sexes = _FEMALE},
	&"freckles_f": {label = "APP_SKIN_FRECKLES_F", sexes = _FEMALE},
	&"bronze_f": {label = "APP_SKIN_BRONZE_F", sexes = _FEMALE},
	&"ginger_f": {label = "APP_SKIN_GINGER_F", sexes = _FEMALE},
	&"midtone_f": {label = "APP_SKIN_MIDTONE_F", sexes = _FEMALE},
	&"zoey_f": {label = "APP_SKIN_ZOEY_F", sexes = _FEMALE},
	&"dark_f": {label = "APP_SKIN_DARK_F", sexes = _FEMALE},
	&"asian_f": {label = "APP_SKIN_ASIAN_F", sexes = _FEMALE},
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

## How far "Randomize" moves a slider from its centre, as a fraction of its
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
	_register(_choice(SEX, "APP_SEX", &"male", SEXES))
	_category(&"body", "APP_CAT_BODY", &"body", [
		_morph(&"height", "APP_HEIGHT", -1.0, 1.0, Vector2(-0.6, 0.35)),
		_for_sexes(_morph(&"body_weight", "APP_BODY_WEIGHT"), [], {&"male": 0.1}),
		_for_sexes(_morph(&"muscle", "APP_MUSCLE"), [], {&"male": 0.3}),
		_for_sexes(_shader_slider(&"definition", "APP_DEFINITION", Vector2(0.15, 1.45), -1.0, 1.0, 0.0), [],
				{&"male": -0.5, &"female": -0.5}),
		_morph(&"age", "APP_AGE"),
		# The middle is MakeHuman's narrowest; wider read as bulky on these bodies.
		_morph(&"shoulder_width", "APP_SHOULDER_WIDTH", -1.0, 1.0, Vector2(-2.0, 0.0)),
		_for_sexes(_morph(&"chest_depth", "APP_CHEST_DEPTH"), [], {&"male": 0.6, &"female": 0.15}),
		_for_sexes(_morph(&"torso_width", "APP_TORSO_WIDTH"), [], {&"male": 0.15}),
		_morph(&"torso_vshape", "APP_TORSO_VSHAPE"),
		_for_sexes(_morph(&"lats", "APP_LATS"), [], {&"male": 0.3}),
		_for_sexes(_morph(&"pectorals", "APP_PECTORALS"), _MALE),
		_for_sexes(_morph(&"breast_size", "APP_BREAST_SIZE"), _FEMALE, {&"female": 0.3}),
		_for_sexes(_morph(&"breast_firmness", "APP_BREAST_FIRMNESS"), _FEMALE),
		_for_sexes(_morph(&"breast_position", "APP_BREAST_POSITION"), _FEMALE),
		_for_sexes(_morph(&"breast_spacing", "APP_BREAST_SPACING"), _FEMALE),
		_for_sexes(_morph(&"penis_length", "APP_PENIS_LENGTH", -1.0, 1.0, Vector2(-1.0, 0.5)), _MALE),
		_for_sexes(_morph(&"penis_girth", "APP_PENIS_GIRTH"), _MALE),
		_for_sexes(_morph(&"testicles", "APP_TESTICLES"), _MALE),
		_shader_slider(&"pubic_hair", "APP_PUBIC_HAIR", Vector2(0.0, 1.0), 0.0, 1.0, 0.5),
		_morph(&"abdomen", "APP_ABDOMEN"),
		_morph(&"waist", "APP_WAIST"),
		_morph(&"hips", "APP_HIPS"),
		_morph(&"glutes", "APP_GLUTES"),
		_morph(&"arms", "APP_ARMS"),
		_morph(&"legs", "APP_LEGS"),
	])
	_category(&"head", "APP_CAT_HEAD", &"face", [
		_choice(FACE_PRESET, "APP_FACE_PRESET", &"m_default", {}, {&"female": &"f_default"}, AppearanceOption.Kind.PRESET),
		_morph(&"race_african", "APP_RACE_AFRICAN", 0.0, 1.0),
		_morph(&"race_asian", "APP_RACE_ASIAN", 0.0, 1.0),
		_morph(&"head_size", "APP_HEAD_SIZE"),
		_morph(&"head_width", "APP_HEAD_WIDTH"),
		_morph(&"head_round", "APP_HEAD_ROUND", 0.0, 1.0),
		_morph(&"head_square", "APP_HEAD_SQUARE", 0.0, 1.0),
		_morph(&"head_oval", "APP_HEAD_OVAL", 0.0, 1.0),
		_morph(&"head_diamond", "APP_HEAD_DIAMOND", 0.0, 1.0),
		_morph(&"head_triangular", "APP_HEAD_TRIANGULAR"),
		_morph(&"head_fat", "APP_HEAD_FAT"),
		_morph(&"forehead", "APP_FOREHEAD"),
		_morph(&"forehead_slope", "APP_FOREHEAD_SLOPE"),
		_morph(&"temples", "APP_TEMPLES"),
		_morph(&"neck_thickness", "APP_NECK_THICKNESS"),
		_morph(&"neck_length", "APP_NECK_LENGTH"),
		_morph(&"nape", "APP_NAPE"),
		_morph(&"ear_size", "APP_EAR_SIZE"),
		_morph(&"ear_angle", "APP_EAR_ANGLE"),
		_morph(&"ear_lobe", "APP_EAR_LOBE"),
		_morph(&"ear_pointed", "APP_EAR_POINTED", 0.0, 1.0),
	])
	_category(&"jaw", "APP_CAT_JAW", &"face", [
		_morph(&"jaw_width", "APP_JAW_WIDTH"),
		_morph(&"jaw_angle", "APP_JAW_ANGLE"),
		_morph(&"chin_width", "APP_CHIN_WIDTH"),
		_morph(&"chin_length", "APP_CHIN_LENGTH"),
		_morph(&"chin_projection", "APP_CHIN_PROJECTION"),
		_morph(&"chin_cleft", "APP_CHIN_CLEFT", 0.0, 1.0),
		_morph(&"cheekbones", "APP_CHEEKBONES"),
		_morph(&"cheekbone_height", "APP_CHEEKBONE_HEIGHT"),
		_morph(&"cheeks", "APP_CHEEKS"),
		_morph(&"cheeks_inner", "APP_CHEEKS_INNER"),
	])
	_category(&"eyes", "APP_CAT_EYES", &"face", [
		_color(&"eye_color", "APP_EYE_COLOR", EYE_COLORS, "4a2e1b", &"eyes"),
		_morph(&"eye_size", "APP_EYE_SIZE"),
		_morph(&"eye_spacing", "APP_EYE_SPACING"),
		_morph(&"eye_height", "APP_EYE_HEIGHT"),
		_morph(&"eye_tilt", "APP_EYE_TILT"),
		_morph(&"eye_depth", "APP_EYE_DEPTH"),
		_morph(&"eye_opening", "APP_EYE_OPENING"),
		_morph(&"eyelid", "APP_EYELID"),
		_morph(&"epicanthus", "APP_EPICANTHUS"),
		_morph(&"eye_bags", "APP_EYE_BAGS"),
		_choice(EYEBROWS, "APP_EYEBROWS", &"eyebrow001", EYEBROW_STYLES, {&"female": &"eyebrow010"}),
		_morph(&"brow_height", "APP_BROW_HEIGHT"),
		_morph(&"brow_angle", "APP_BROW_ANGLE"),
		_morph(&"brow_depth", "APP_BROW_DEPTH"),
		_color(&"eyeshadow_color", "APP_EYESHADOW_COLOR", EYESHADOW_COLORS, "3a2c2a"),
		_shader_slider(&"eyeshadow", "APP_EYESHADOW", Vector2(0.0, 1.0), 0.0, 1.0, 0.0),
	])
	_category(&"nose", "APP_CAT_NOSE", &"face", [
		_morph(&"nose_size", "APP_NOSE_SIZE"),
		_morph(&"nose_width", "APP_NOSE_WIDTH"),
		_morph(&"nose_length", "APP_NOSE_LENGTH"),
		_morph(&"nose_projection", "APP_NOSE_PROJECTION"),
		_morph(&"nose_bridge", "APP_NOSE_BRIDGE"),
		_morph(&"nose_bridge_width", "APP_NOSE_BRIDGE_WIDTH"),
		_morph(&"nose_curve", "APP_NOSE_CURVE"),
		_morph(&"nose_tip", "APP_NOSE_TIP"),
		_morph(&"nose_tip_width", "APP_NOSE_TIP_WIDTH"),
		_morph(&"nostrils", "APP_NOSTRILS"),
		_morph(&"nose_flaring", "APP_NOSE_FLARING"),
	])
	_category(&"mouth", "APP_CAT_MOUTH", &"face", [
		_morph(&"mouth_width", "APP_MOUTH_WIDTH"),
		_morph(&"mouth_height", "APP_MOUTH_HEIGHT"),
		_morph(&"mouth_projection", "APP_MOUTH_PROJECTION"),
		_morph(&"upper_lip", "APP_UPPER_LIP"),
		_morph(&"lower_lip", "APP_LOWER_LIP"),
		_morph(&"mouth_corners", "APP_MOUTH_CORNERS"),
		_morph(&"cupids_bow", "APP_CUPIDS_BOW"),
		_morph(&"philtrum", "APP_PHILTRUM"),
		_color(&"lip_color", "APP_LIP_COLOR", LIP_COLORS, "b8625c"),
		_shader_slider(&"lip_tint", "APP_LIP_TINT", Vector2(0.0, 1.0), 0.0, 1.0, 0.0),
	])
	_category(&"hair", "APP_CAT_HAIR", &"head", [
		_choice(HAIR_STYLE, "APP_HAIR_STYLE", &"regular", HAIR_STYLES, {&"female": &"long_straight"}),
		_color(&"hair_color", "APP_HAIR_COLOR", HAIR_COLORS, "2a1c13", &"hair"),
		_shader_slider(&"gray", "APP_GRAY", Vector2(0.0, 1.0), 0.0, 1.0, 0.0, &"hair"),
		_for_sexes(_choice(BEARD, "APP_BEARD", &"none", BEARDS), _MALE),
		_for_sexes(_shader_slider(&"stubble", "APP_STUBBLE", Vector2(0.0, 1.0), 0.0, 1.0, 0.35), _MALE,
				{&"female": 0.0}),
	])
	_category(&"skin", "APP_CAT_SKIN", &"body", [
		_choice(SKIN, "APP_SKIN", &"light_m", SKINS, {&"female": &"light_f"}),
		_color(&"skin_color", "APP_SKIN_COLOR", SKIN_TONES, "e0a98a"),
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

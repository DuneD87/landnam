class_name AppearanceRoll
extends RefCounted

## Random looks that hang together (CharacterAppearance.randomize_values). A fresh roll starts from
## nothing: a lineage first (LINEAGES: its face presets, skins, skin tones, hair and eye colours), then an
## age in years (grey hair, eye bags, balding and the older skins follow it), then every slider around its
## default for the sex, at most two spreads away. Pointed ears, the other lineages' features, the head
## shape blends and make-up are left to the player. Varying moves only the given options a little from
## where they are, never far from their default. See docs/character_creation.md.

## Per lineage: its weight in a roll for any lineage, its face presets, and weights for its skins, skin
## tones, hair and eye colours (hex, from AppearanceCatalog's palettes).
const LINEAGES := {
	&"north": {weight = 4.0,
		presets = [&"m_default", &"m_rugged", &"m_young", &"m_gaunt", &"m_heavy",
			&"f_default", &"f_strong", &"f_soft", &"f_heart", &"f_angular"],
		skins = {&"light_m": 3.0, &"freckles_m": 2.0, &"rugged_m": 2.0, &"mature_m": 1.0, &"tattoo_m": 0.5,
			&"light_f": 3.0, &"freckles_f": 2.0, &"ginger_f": 1.5, &"zoey_f": 1.0},
		tones = {"f0cdb8": 2.0, "e0a98a": 3.0, "d49a78": 1.0},
		hair = {"2a1c13": 1.0, "46301f": 2.0, "6b4a2f": 3.0, "93704a": 3.0, "c9a877": 3.0, "e2cfa3": 2.0,
			"8c3b1c": 1.5, "b35a2c": 1.5, "0f0c0a": 0.5},
		eyes = {"3f6f9a": 3.0, "7593ab": 3.0, "7b7c74": 2.0, "5f7a3e": 2.0, "8a6a3a": 1.0, "6e4a2a": 1.0}},
	&"south": {weight = 2.5,
		presets = [&"m_default", &"m_rugged", &"m_young", &"m_gaunt", &"m_heavy",
			&"f_default", &"f_strong", &"f_soft", &"f_heart", &"f_angular"],
		skins = {&"bronze_m": 3.0, &"light_m": 1.0, &"mature_m": 1.0, &"bronze_f": 3.0, &"midtone_f": 3.0},
		tones = {"d49a78": 2.0, "bf865f": 3.0, "a06a47": 2.0},
		hair = {"0f0c0a": 3.0, "2a1c13": 3.0, "46301f": 2.0, "6b4a2f": 1.0},
		eyes = {"4a2e1b": 3.0, "6e4a2a": 3.0, "8a6a3a": 1.0, "5f7a3e": 1.0}},
	&"africa": {weight = 1.5,
		presets = [&"m_african", &"f_african"],
		skins = {&"dark_m": 1.0, &"dark_f": 1.0},
		tones = {"7f4f34": 2.0, "5c3826": 3.0, "3d2519": 2.0},
		hair = {"0f0c0a": 3.0, "2a1c13": 2.0},
		eyes = {"4a2e1b": 3.0, "2a1c14": 3.0}},
	&"asia": {weight = 2.0,
		presets = [&"m_asian", &"f_asian"],
		skins = {&"asian_m": 1.0, &"asian_f": 1.0},
		tones = {"e0a98a": 2.0, "d49a78": 3.0, "bf865f": 1.0},
		hair = {"0f0c0a": 3.0, "2a1c13": 2.0},
		eyes = {"2a1c14": 3.0, "4a2e1b": 2.0, "6e4a2a": 1.0}},
}
## Hair styles a roll picks, with their weight (the rest only by hand); a lineage adds its own.
const HAIR := {
	&"regular": 2.0, &"side_part": 1.0, &"tousled": 2.0, &"side_swept": 1.0, &"curtains": 1.0,
	&"crew_cut": 1.0, &"very_short": 1.0, &"buzz": 0.5, &"long_parted": 1.0, &"long_straight": 2.0,
	&"curly": 1.0, &"ponytail": 2.0, &"braid": 2.0, &"wild_mane": 1.0, &"shoulder_length": 2.0,
	&"long_side": 1.0, &"long_flowing": 1.0, &"long_loose": 2.0, &"long_unkempt": 2.0, &"long_tangled": 1.0,
	&"long_wild": 2.0, &"topknot": 0.5, &"braided_bun": 2.0, &"two_braids": 2.0, &"long_layered": 2.0,
	&"low_pigtails": 1.0, &"bun_fringe": 1.0, &"wavy": 1.0, &"round_bun": 1.0, &"french_twist": 0.5,
}
const LINEAGE_HAIR := {
	&"africa": {&"afro": 4.0, &"cornrows": 3.0, &"dreadlocks": 3.0},
	&"asia": {&"topknot": 3.0, &"spiky_topknot": 1.0},
}
## Beards a roll picks, by lineage (the rest only by hand).
const BEARDS := {
	&"north": {&"viking": 3.0, &"long": 2.0, &"short": 3.0, &"none": 1.5, &"circle": 1.0, &"walrus": 1.0,
		&"no_moustache": 1.0, &"horseshoe": 0.5, &"mutton_chops": 0.5, &"goatee": 0.5, &"moustache": 0.5},
	&"other": {&"none": 3.0, &"short": 2.0, &"circle": 1.0, &"goatee": 1.0, &"moustache": 1.0,
		&"long": 0.5, &"viking": 0.5, &"van_dyke": 0.5, &"chin_strap": 0.5},
}
## Sliders a roll leaves at their default (or the face preset's): features of other lineages, shapes
## only presets blend, make-up, and what the age sets.
const KEEP := [&"race_african", &"race_asian", &"head_round", &"head_square", &"head_oval", &"head_diamond",
	&"ear_pointed", &"chin_cleft", &"eyeshadow", &"lip_tint", &"age", &"gray", &"eye_bags", &"stubble"]
## How far varying goes from a slider's default, as a fraction of its half range, and how far each press
## moves it compared with a roll.
const VARY_LIMIT := 0.6
const VARY_STEP := 0.6
## Ages a roll picks (years), skewed towards the young.
const AGE_YEARS := Vector2(17.0, 68.0)
const AGE_SKEW := 1.6
## The most grey hair a roll gives.
const GREY_MAX := 0.6


## A fresh look for the sex [appearance] has, from [lineage] (LINEAGES) or any.
static func roll(appearance: CharacterAppearance, rng: RandomNumberGenerator, lineage := &"") -> void:
	var sex := appearance.get_sex()
	appearance.values.clear()
	appearance.values[AppearanceCatalog.SEX] = sex
	if not LINEAGES.has(lineage):
		var weights := {}
		for id in LINEAGES:
			weights[id] = LINEAGES[id].weight
		lineage = _weighted(weights, rng)
	var data: Dictionary = LINEAGES[lineage]
	var preset_option := AppearanceCatalog.find(AppearanceCatalog.FACE_PRESET)
	var presets: Array[Dictionary] = []
	for preset in preset_option.choices_for(sex):
		if (data.presets as Array).has(preset.id):
			presets.append(preset)
	if not presets.is_empty():
		var preset: Dictionary = presets[rng.randi() % presets.size()]
		for id in preset.get("values", {}):
			appearance.values[id] = preset.values[id]
		appearance.values[preset_option.id] = preset.id
	for option in AppearanceCatalog.all_options():
		if option.kind != AppearanceOption.Kind.SLIDER or not option.is_available(sex) or KEEP.has(option.id):
			continue
		var centre: float = appearance.values.get(option.id, option.default_for(sex))
		appearance.values[option.id] = _near(option, centre, AppearanceCatalog.random_spread(option.id), rng)

	var years := lerpf(AGE_YEARS.x, AGE_YEARS.y, pow(rng.randf(), AGE_SKEW))
	appearance.values[&"age"] = age_value(years)
	# Past about 0.6 the grey reads as white noise on curly and long styles: salt and pepper at most.
	var greying := smoothstep(42.0, 70.0, years)
	appearance.values[&"gray"] = clampf(greying * rng.randf_range(0.4, 0.75) + rng.randfn(0.0, 0.03), 0.0, GREY_MAX)
	appearance.values[&"eye_bags"] = clampf(smoothstep(28.0, 66.0, years) * 0.6 + rng.randfn(0.0, 0.1), -1.0, 1.0)

	_set_colour(appearance, &"skin_color", data.tones, rng)
	_set_colour(appearance, &"hair_color", data.hair, rng)
	_set_colour(appearance, &"eye_color", data.eyes, rng)
	appearance.values[AppearanceCatalog.SKIN] = _skin(data, sex, years, rng)
	appearance.values[AppearanceCatalog.HAIR_STYLE] = _hair_style(lineage, sex, years, rng)
	var eyebrows := AppearanceCatalog.find(AppearanceCatalog.EYEBROWS).choices_for(sex)
	appearance.values[AppearanceCatalog.EYEBROWS] = eyebrows[rng.randi() % eyebrows.size()].id
	if sex == &"male":
		var beards: Dictionary = (BEARDS.north as Dictionary).duplicate() if lineage == &"north" else (BEARDS.other as Dictionary).duplicate()
		# The young go clean-shaven more often.
		beards[&"none"] = float(beards.get(&"none", 0.0)) * (1.0 + 2.0 * (1.0 - smoothstep(18.0, 26.0, years)))
		appearance.values[AppearanceCatalog.BEARD] = _weighted(beards, rng)
		appearance.values[&"stubble"] = rng.randf_range(0.2, 0.8)


## Moves [options] of [appearance] a little from where they are: sliders a step (never far from their
## default), colours to a neighbour in their palette, styles to another the roll would pick.
static func vary(appearance: CharacterAppearance, rng: RandomNumberGenerator, options: Array[AppearanceOption]) -> void:
	var sex := appearance.get_sex()
	var lineage := lineage_of(appearance)
	for option in options:
		if option.id == AppearanceCatalog.SEX or not option.is_available(sex):
			continue
		match option.kind:
			AppearanceOption.Kind.SLIDER:
				if KEEP.has(option.id) and not [&"age", &"gray", &"eye_bags", &"stubble"].has(option.id):
					continue
				var half := (option.max_value - option.min_value) * 0.5
				var default_value: float = option.default_for(sex)
				var current: float = appearance.get_value(option.id)
				var moved := current + clampf(rng.randfn(0.0, 1.0), -2.0, 2.0) \
					* AppearanceCatalog.random_spread(option.id) * VARY_STEP * half
				moved = clampf(moved, default_value - VARY_LIMIT * half, default_value + VARY_LIMIT * half)
				appearance.values[option.id] = clampf(moved, option.min_value, option.max_value)
			AppearanceOption.Kind.COLOR:
				var palette := option.palette
				var at := 0
				for i in palette.size():
					if palette[i].is_equal_approx(appearance.get_value(option.id)):
						at = i
				appearance.values[option.id] = palette[clampi(at + (1 if rng.randf() < 0.5 else -1), 0, palette.size() - 1)]
			AppearanceOption.Kind.CHOICE:
				var years := age_years(float(appearance.get_value(&"age")))
				match option.id:
					AppearanceCatalog.HAIR_STYLE:
						appearance.values[option.id] = _hair_style(lineage, sex, years, rng)
					AppearanceCatalog.SKIN:
						appearance.values[option.id] = _skin(LINEAGES[lineage], sex, years, rng)
					_:
						var offered := option.choices_for(sex)
						appearance.values[option.id] = offered[rng.randi() % offered.size()].id


## The age slider for [years] (the macro export: -1 is about 21, 0 is 25 and +1 about 67).
static func age_value(years: float) -> float:
	return clampf((years - 25.0) / (41.6 if years >= 25.0 else 3.6), -1.0, 1.0)


static func age_years(value: float) -> float:
	return 25.0 + value * (41.6 if value >= 0.0 else 3.6)


## The lineage [appearance] looks like, by its skin.
static func lineage_of(appearance: CharacterAppearance) -> StringName:
	var skin: StringName = appearance.get_value(AppearanceCatalog.SKIN)
	for id in LINEAGES:
		if (LINEAGES[id].skins as Dictionary).has(skin):
			return id
	return &"north"


static func _near(option: AppearanceOption, centre: float, spread: float, rng: RandomNumberGenerator) -> float:
	var half := (option.max_value - option.min_value) * 0.5
	return clampf(centre + clampf(rng.randfn(0.0, 1.0), -2.0, 2.0) * spread * half, option.min_value, option.max_value)


static func _set_colour(appearance: CharacterAppearance, id: StringName, weights: Dictionary,
		rng: RandomNumberGenerator) -> void:
	appearance.values[id] = Color(String(_weighted(weights, rng)))


## A skin of [data] for [sex]: the older ones for the old.
static func _skin(data: Dictionary, sex: StringName, years: float, rng: RandomNumberGenerator) -> StringName:
	var offered := {}
	for choice in AppearanceCatalog.find(AppearanceCatalog.SKIN).choices_for(sex):
		if (data.skins as Dictionary).has(choice.id):
			offered[choice.id] = float(data.skins[choice.id])
	if offered.has(&"mature_m"):
		offered[&"mature_m"] *= 0.2 + 4.0 * smoothstep(35.0, 55.0, years)
	if offered.has(&"rugged_m"):
		offered[&"rugged_m"] *= 0.5 + 1.5 * smoothstep(28.0, 45.0, years)
	if offered.is_empty():
		return AppearanceCatalog.find(AppearanceCatalog.SKIN).default_for(sex)
	return _weighted(offered, rng)


## A hair style for [sex]: the roll's (HAIR and the lineage's own); men lose it with the years.
static func _hair_style(lineage: StringName, sex: StringName, years: float, rng: RandomNumberGenerator) -> StringName:
	var weights: Dictionary = HAIR.duplicate()
	weights.merge(LINEAGE_HAIR.get(lineage, {}), true)
	if sex == &"male":
		var thinning := smoothstep(32.0, 60.0, years)
		weights[&"balding"] = 6.0 * thinning
		weights[&"bald"] = 3.0 * thinning
	var offered := {}
	for choice in AppearanceCatalog.find(AppearanceCatalog.HAIR_STYLE).choices_for(sex):
		if float(weights.get(choice.id, 0.0)) > 0.0:
			offered[choice.id] = weights[choice.id]
	return _weighted(offered, rng)


static func _weighted(weights: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var total := 0.0
	for key in weights:
		total += float(weights[key])
	var roll := rng.randf() * total
	var last: Variant = null
	for key in weights:
		last = key
		roll -= float(weights[key])
		if roll <= 0.0:
			return key
	return last

extends RefCounted

## Parámetros del generador Branching (Tree3D, shape = 3) por especie y materiales.
## Los usan tests/vegetation/tree_designer.tscn para iterar y
## tools/vegetation/apply_tree_presets.gd para escribirlos en las escenas de árbol.
## Alturas en metros: la escala final la fija "height_m" en planet_earth.json.

const BARK_DIR := "res://textures/planet/vegetation/tree/trunk/"
const TWIG_DIR := "res://textures/planet/vegetation/tree/twigs/"

## Por escena: preset base, semilla y retoques de esa variante.
const SCENES := {
	"pine_01": {"species": "pine", "seed": 11, "overrides": {}},
	"pine_02": {"species": "pine", "seed": 27, "overrides": {"branch_height": 15.0, "branch_split_count": 5, "branch_lean": 0.14}},
	"pine_03": {"species": "pine", "seed": 43, "overrides": {"branch_height": 12.0, "branch_split_height": 0.55, "branch_crown_base": 0.5}},
	"olive_01": {"species": "olive", "seed": 5, "overrides": {}},
	"olive_02": {"species": "olive", "seed": 19, "overrides": {"branch_split_count": 2, "branch_lean": 0.2, "branch_height": 5.0}},
	"apple_01": {"species": "apple", "seed": 8, "overrides": {}},
	"apple_02": {"species": "apple", "seed": 31, "overrides": {"branch_height": 6.2, "branch_split_count": 3}},
	"almond_01": {"species": "almond", "seed": 3, "overrides": {}},
	"almond_02": {"species": "almond", "seed": 37, "overrides": {"branch_height": 5.6, "branch_split_angle": 34.0}},
}

const SPECIES := {
	"pine": {
		"bark": "pine", "twig": "twig_pine.png",
		"params": {
			"branch_height": 14.0, "branch_trunk_radius": 0.3, "branch_trunk_taper": 0.3,
			"branch_root_flare": 1.5, "branch_flare_height": 0.5, "branch_root_lobes": 4,
			"branch_lobe_depth": 0.15, "branch_gnarl": 0.05, "branch_lean": 0.08, "branch_wobble": 0.08,
			"branch_split_height": 0.6, "branch_split_count": 4, "branch_split_angle": 42.0,
			"branch_crown_base": 0.62, "branch_crown_shape": 2,
			"branch_l1_count": 18, "branch_l1_length": 0.34, "branch_l1_angle": 82.0, "branch_l1_angle_top": 65.0,
			"branch_l1_gravity": 0.55, "branch_l1_radius": 0.55,
			"branch_l2_count": 6, "branch_l2_length": 0.5, "branch_l2_angle": 50.0, "branch_l2_gravity": 0.2,
			"branch_l2_radius": 0.6,
			"branch_twig_count": 7, "branch_twig_angle": 35.0, "branch_leaf_size": 1.45, "branch_leaf_width": 1.0,
			"branch_leaf_jitter": 0.25, "branch_leaf_up": 0.8, "branch_leaf_droop": 0.1, "branch_leaf_cross": 0.15,
			"branch_leaf_start": 0.3, "branch_leaf_outward": 0.3,
			"branch_crown_normal": 0.7, "branch_crown_ao": 0.4, "branch_bark_tile": 1.2, "branch_lod_card_boost": 1.0,
		},
		"foliage": {"albedo_tint": Color(0.92, 1.0, 0.95), "transmission_color": Color(0.9, 1.0, 0.55)},
		"bark_material": {"moss_amount": 0.15},
	},
	"olive": {
		"bark": "olive", "twig": "twig_olive.png",
		"params": {
			"branch_height": 5.5, "branch_trunk_radius": 0.2, "branch_trunk_taper": 0.5,
			"branch_root_flare": 1.7, "branch_flare_height": 0.6, "branch_root_lobes": 5,
			"branch_lobe_depth": 0.25, "branch_gnarl": 0.35, "branch_lean": 0.12, "branch_wobble": 0.25,
			"branch_split_height": 0.3, "branch_split_count": 3, "branch_split_angle": 35.0,
			"branch_crown_base": 0.3, "branch_crown_shape": 1,
			"branch_l1_count": 16, "branch_l1_length": 0.4, "branch_l1_angle": 60.0, "branch_l1_angle_top": 40.0,
			"branch_l1_gravity": 0.05, "branch_l1_radius": 0.6,
			"branch_l2_count": 7, "branch_l2_length": 0.5, "branch_l2_angle": 50.0, "branch_l2_gravity": -0.2,
			"branch_l2_radius": 0.6,
			"branch_twig_count": 7, "branch_twig_angle": 45.0, "branch_leaf_size": 0.8, "branch_leaf_width": 1.0,
			"branch_leaf_jitter": 0.25, "branch_leaf_up": 0.4, "branch_leaf_droop": 0.3, "branch_leaf_cross": 0.15,
			"branch_leaf_start": 0.25, "branch_leaf_outward": 0.35,
			"branch_crown_normal": 0.7, "branch_crown_ao": 0.4, "branch_bark_tile": 1.0, "branch_lod_card_boost": 1.0,
		},
		"foliage": {"albedo_tint": Color(0.95, 1.0, 0.97), "transmission_color": Color(0.95, 1.0, 0.7)},
		"bark_material": {"moss_amount": 0.3},
	},
	"apple": {
		"bark": "apple", "twig": "twig_apple.png",
		"params": {
			"branch_height": 5.5, "branch_trunk_radius": 0.15, "branch_trunk_taper": 0.45,
			"branch_root_flare": 1.5, "branch_flare_height": 0.5, "branch_root_lobes": 5,
			"branch_lobe_depth": 0.18, "branch_gnarl": 0.1, "branch_lean": 0.06, "branch_wobble": 0.15,
			"branch_split_height": 0.32, "branch_split_count": 4, "branch_split_angle": 40.0,
			"branch_crown_base": 0.3, "branch_crown_shape": 1,
			"branch_l1_count": 16, "branch_l1_length": 0.45, "branch_l1_angle": 65.0, "branch_l1_angle_top": 40.0,
			"branch_l1_gravity": -0.05, "branch_l1_radius": 0.6,
			"branch_l2_count": 7, "branch_l2_length": 0.5, "branch_l2_angle": 45.0, "branch_l2_gravity": -0.25,
			"branch_l2_radius": 0.6,
			"branch_twig_count": 7, "branch_twig_angle": 40.0, "branch_leaf_size": 0.9, "branch_leaf_width": 1.0,
			"branch_leaf_jitter": 0.25, "branch_leaf_up": 0.35, "branch_leaf_droop": 0.25, "branch_leaf_cross": 0.15,
			"branch_leaf_start": 0.25, "branch_leaf_outward": 0.35,
			"branch_crown_normal": 0.7, "branch_crown_ao": 0.4, "branch_bark_tile": 1.0, "branch_lod_card_boost": 1.0,
		},
		"foliage": {},
		"bark_material": {"moss_amount": 0.35},
	},
	"almond": {
		"bark": "almond", "twig": "twig_almond.png",
		"params": {
			"branch_height": 6.5, "branch_trunk_radius": 0.15, "branch_trunk_taper": 0.4,
			"branch_root_flare": 1.5, "branch_flare_height": 0.5, "branch_root_lobes": 4,
			"branch_lobe_depth": 0.15, "branch_gnarl": 0.12, "branch_lean": 0.05, "branch_wobble": 0.15,
			"branch_split_height": 0.28, "branch_split_count": 4, "branch_split_angle": 30.0,
			"branch_crown_base": 0.3, "branch_crown_shape": 7,
			"branch_l1_count": 14, "branch_l1_length": 0.42, "branch_l1_angle": 45.0, "branch_l1_angle_top": 30.0,
			"branch_l1_gravity": 0.25, "branch_l1_radius": 0.6,
			"branch_l2_count": 6, "branch_l2_length": 0.5, "branch_l2_angle": 45.0, "branch_l2_gravity": 0.0,
			"branch_l2_radius": 0.6,
			"branch_twig_count": 6, "branch_twig_angle": 40.0, "branch_leaf_size": 0.85, "branch_leaf_width": 1.0,
			"branch_leaf_jitter": 0.25, "branch_leaf_up": 0.3, "branch_leaf_droop": 0.2, "branch_leaf_cross": 0.15,
			"branch_leaf_start": 0.25, "branch_leaf_outward": 0.35,
			"branch_crown_normal": 0.7, "branch_crown_ao": 0.4, "branch_bark_tile": 1.1, "branch_lod_card_boost": 1.0,
		},
		"foliage": {},
		"bark_material": {"moss_amount": 0.25},
	},
}


static func params_for(scene_name: String) -> Dictionary:
	var entry: Dictionary = SCENES[scene_name]
	var params: Dictionary = SPECIES[entry.species].params.duplicate()
	params.merge(entry.overrides, true)
	return params


static func bark_material(species: String) -> ShaderMaterial:
	var data: Dictionary = SPECIES[species]
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/vegetation/tree_bark.gdshader")
	material.set_shader_parameter("texture_albedo", load(BARK_DIR + "bark_%s_albedo.jpg" % data.bark))
	material.set_shader_parameter("texture_normal", load(BARK_DIR + "bark_%s_normal.jpg" % data.bark))
	material.set_shader_parameter("texture_roughness", load(BARK_DIR + "bark_%s_roughness.jpg" % data.bark))
	for key in data.bark_material:
		material.set_shader_parameter(key, data.bark_material[key])
	return material


static func foliage_material(species: String) -> ShaderMaterial:
	var data: Dictionary = SPECIES[species]
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/vegetation/tree_foliage.gdshader")
	material.set_shader_parameter("texture_albedo", load(TWIG_DIR + data.twig))
	for key in data.foliage:
		material.set_shader_parameter(key, data.foliage[key])
	return material


## Configura un Tree3D con la forma Branching, la semilla, los parámetros y los materiales.
static func configure(tree: Tree3D, scene_name: String) -> void:
	var entry: Dictionary = SCENES[scene_name]
	tree.shape = 3
	tree.seed = entry.seed
	var params := params_for(scene_name)
	for key in params:
		tree.set(key, params[key])
	tree.material_trunk = bark_material(entry.species)
	tree.twig_materials = [foliage_material(entry.species)]

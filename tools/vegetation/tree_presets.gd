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
	# Bioma nevado: picea de la taiga (también la enana de la línea de árboles, escalada con
	# height_m) y abedul de su borde templado.
	"spruce_01": {"species": "spruce", "seed": 13, "overrides": {}},
	"spruce_02": {"species": "spruce", "seed": 29, "overrides": {"branch_height": 16.0, "branch_l1_count": 24, "branch_lean": 0.06}},
	"spruce_03": {"species": "spruce", "seed": 47, "overrides": {"branch_height": 20.0, "branch_l1_gravity": 0.7, "branch_crown_base": 0.14}},
	"birch_01": {"species": "birch", "seed": 7, "overrides": {}},
	"birch_02": {"species": "birch", "seed": 23, "overrides": {"branch_crown_shape": 1, "branch_l1_length": 0.45, "branch_crown_base": 0.3, "branch_lean": 0.12, "branch_l1_count": 18, "branch_l2_count": 7}},
}

const SPECIES := {
	# Picea: un solo guía hasta la punta, verticilos de ramas casi horizontales desde el suelo que
	# se levantan arriba, y ramillas colgantes (la "peineta" de la picea de Noruega).
	"spruce": {
		"bark": "spruce", "twig": "twig_spruce.png",
		"params": {
			"branch_height": 18.0, "branch_trunk_radius": 0.27, "branch_trunk_taper": 0.75,
			"branch_root_flare": 1.45, "branch_flare_height": 0.45, "branch_root_lobes": 5,
			"branch_lobe_depth": 0.12, "branch_gnarl": 0.02, "branch_lean": 0.03, "branch_wobble": 0.04,
			"branch_split_height": 1.0, "branch_split_count": 1, "branch_split_angle": 5.0,
			"branch_crown_base": 0.08, "branch_crown_shape": 0,
			"branch_l1_count": 26, "branch_l1_length": 0.26, "branch_l1_angle": 96.0, "branch_l1_angle_top": 30.0,
			"branch_l1_gravity": 0.6, "branch_l1_radius": 0.34,
			"branch_l2_count": 5, "branch_l2_length": 0.46, "branch_l2_angle": 58.0, "branch_l2_gravity": 0.55,
			"branch_l2_radius": 0.5,
			"branch_twig_count": 6, "branch_twig_angle": 38.0, "branch_leaf_size": 0.9, "branch_leaf_width": 1.0,
			"branch_leaf_jitter": 0.2, "branch_leaf_up": 0.55, "branch_leaf_droop": 0.35, "branch_leaf_cross": 0.2,
			"branch_leaf_start": 0.12, "branch_leaf_outward": 0.3,
			"branch_crown_normal": 0.75, "branch_crown_ao": 0.5, "branch_bark_tile": 1.0, "branch_lod_card_boost": 1.15,
		},
		"foliage": {"albedo_tint": Color(0.92, 1.0, 1.0), "transmission_color": Color(0.7, 0.9, 0.5),
			"transmission_strength": 0.55, "deciduous": true,
			"autumn_early": Color(0.62, 0.55, 0.2), "autumn_late": Color(0.66, 0.45, 0.17),
			"autumn_withered": Color(0.48, 0.34, 0.2), "leaf_luma_ref": 0.061, "leaf_chroma_ref": 0.54},
		"bark_material": {"moss_amount": 0.12, "deciduous": true},
	},
	# Abedul: tronco blanco esbelto y algo ondulado, copa oval y ramillas péndulas. Caduco: en
	# otoño se pone dorado (el color lo pone el shader de follaje sobre la ramita verde).
	"birch": {
		"bark": "birch", "twig": "twig_birch.png",
		"params": {
			"branch_height": 14.0, "branch_trunk_radius": 0.14, "branch_trunk_taper": 0.55,
			"branch_root_flare": 1.3, "branch_flare_height": 0.35, "branch_root_lobes": 3,
			"branch_lobe_depth": 0.08, "branch_gnarl": 0.04, "branch_lean": 0.08, "branch_wobble": 0.2,
			"branch_split_height": 0.62, "branch_split_count": 3, "branch_split_angle": 24.0,
			"branch_crown_base": 0.28, "branch_crown_shape": 5,
			"branch_l1_count": 24, "branch_l1_length": 0.42, "branch_l1_angle": 46.0, "branch_l1_angle_top": 28.0,
			"branch_l1_gravity": 0.3, "branch_l1_radius": 0.45,
			"branch_l2_count": 8, "branch_l2_length": 0.55, "branch_l2_angle": 42.0, "branch_l2_gravity": 0.85,
			"branch_l2_radius": 0.5,
			"branch_twig_count": 7, "branch_twig_angle": 35.0, "branch_leaf_size": 1.1, "branch_leaf_width": 1.0,
			"branch_leaf_jitter": 0.3, "branch_leaf_up": 0.3, "branch_leaf_droop": 0.6, "branch_leaf_cross": 0.2,
			"branch_leaf_start": 0.15, "branch_leaf_outward": 0.35,
			"branch_crown_normal": 0.7, "branch_crown_ao": 0.4, "branch_bark_tile": 1.1, "branch_lod_card_boost": 1.0,
		},
		"foliage": {"transmission_color": Color(0.9, 1.0, 0.55), "deciduous": true,
			"autumn_early": Color(0.75, 0.65, 0.22), "autumn_late": Color(0.77, 0.54, 0.19),
			"autumn_withered": Color(0.66, 0.5, 0.27), "leaf_luma_ref": 0.27, "leaf_chroma_ref": 0.6},
		"bark_material": {"moss_amount": 0.05, "deciduous": true},
	},
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
			"branch_crown_normal": 0.7, "branch_crown_ao": 0.4, "branch_bark_tile": 1.2, "branch_lod_card_boost": 1.12,
		},
		"foliage": {"albedo_tint": Color(0.92, 1.0, 0.95), "transmission_color": Color(0.9, 1.0, 0.55),
			"deciduous": true, "leaf_mask_edges": Vector4(0.1, 0.2, -0.2, -0.05),
			"autumn_early": Color(0.62, 0.55, 0.2), "autumn_late": Color(0.66, 0.45, 0.17),
			"autumn_withered": Color(0.48, 0.34, 0.2), "leaf_luma_ref": 0.107, "leaf_chroma_ref": 0.44},
		"bark_material": {"moss_amount": 0.15, "deciduous": true},
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
		"foliage": {"albedo_tint": Color(0.95, 1.0, 0.97), "transmission_color": Color(0.95, 1.0, 0.7),
			"deciduous": true, "leaf_mask_edges": Vector4(0.1, 0.2, -0.3, -0.15),
			"autumn_early": Color(0.7, 0.64, 0.28), "autumn_late": Color(0.66, 0.48, 0.22),
			"autumn_withered": Color(0.55, 0.42, 0.26), "leaf_luma_ref": 0.23, "leaf_chroma_ref": 0.46},
		"bark_material": {"moss_amount": 0.3, "deciduous": true},
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
		"foliage": {"deciduous": true,
			"autumn_early": Color(0.68, 0.63, 0.25), "autumn_late": Color(0.7, 0.49, 0.22),
			"autumn_withered": Color(0.6, 0.45, 0.26), "leaf_luma_ref": 0.21, "leaf_chroma_ref": 0.5,
			"blossom_color": Color(0.98, 0.86, 0.9, 1.0)},
		"bark_material": {"moss_amount": 0.35, "deciduous": true},
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
		# Florece al brotar (blossom_color: rosa que va al blanco por tarjeta), a finales del
		# invierno (spring_shift): antes que el manzano.
		"foliage": {"deciduous": true,
			"autumn_early": Color(0.73, 0.61, 0.22), "autumn_late": Color(0.68, 0.33, 0.19),
			"autumn_withered": Color(0.6, 0.37, 0.23), "leaf_luma_ref": 0.24, "leaf_chroma_ref": 0.49,
			"blossom_color": Color(0.97, 0.76, 0.84, 1.0), "spring_shift": -0.05},
		"bark_material": {"moss_amount": 0.25, "deciduous": true},
	},
}


## Hoja caduca: todos los árboles Branching. Pino y picea como un alerce (dorados en otoño, sin
## acícula en invierno). El follaje cambia con las estaciones (shaders/lib/season.gdshaderinc) y
## el impostor lleva además el atlas sin hoja.
static func is_deciduous(scene_name: String) -> bool:
	return bool(SPECIES[SCENES[scene_name].species].foliage.get("deciduous", false))


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

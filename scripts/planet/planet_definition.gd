@tool
class_name PlanetDefinition
extends Resource

## Datos de biomas, materiales y generación compartidos por el lector JSON y el planeta.
## Cada carga crea su propia definición; los consumidores leen la misma instancia tipada.

## Uniforms que se copian sin transformación al preparar el material del terreno.
const MATERIAL_PARAMETERS: Array[StringName] = [
	&"transition_smoothness", &"height_transition_noise_scale", &"height_transition_noise_strength",
	&"biome_transition_smoothness", &"max_heights", &"biome_count", &"textures_per_biome",
	&"biome_latitude_ranges", &"textures", &"normal_textures", &"roughness_textures", &"ao_textures",
	&"height_textures", &"packed_materials", &"biome_texture_indices", &"biome_noise_enabled",
	&"biome_noise_source_texture_indices", &"biome_noise_target_texture_indices",
	&"biome_noise_scales", &"biome_noise_thresholds", &"biome_noise_smoothness", &"biome_noise_seeds",
	&"biome_noise_invert", &"biome_noise_abs_latitude_mins", &"biome_noise_abs_latitude_maxs",
	&"biome_noise_latitude_smoothness", &"slope_texture", &"slope_normal_texture",
	&"slope_roughness_texture", &"slope_ao_texture", &"slope_height_texture", &"slope_threshold",
	&"slope_smoothness", &"slope_height_blend_strength", &"slope_height_blend_sharpness",
	&"slope_breakup_scale", &"slope_breakup_strength", &"slope_breakup_anisotropy",
	&"slope_strata_thickness", &"slope_strata_strength", &"slope_strata_warp", &"parallax_enabled",
	&"parallax_strength", &"macro_variation_scale", &"macro_variation_strength",
	&"slope_albedo_adjust",
]

@export_group("Generación")
@export var vegetation: Dictionary
@export var terrain_generator_path: String
@export var ore_settings: Array[Dictionary] = []

@export_group("Biomas")
@export var biome_count: int
@export var textures_per_biome: int
@export var biome_latitude_ranges: Array[float] = []
@export var biome_transition_smoothness: float
@export var max_heights: Array[float] = []
@export var biome_texture_indices: Array[int] = []
@export var biome_noise_enabled: Array[int] = []
@export var biome_noise_source_texture_indices: Array[int] = []
@export var biome_noise_target_texture_indices: Array[int] = []
@export var biome_noise_scales: Array[float] = []
@export var biome_noise_thresholds: Array[float] = []
@export var biome_noise_smoothness: Array[float] = []
@export var biome_noise_seeds: Array[float] = []
@export var biome_noise_invert: Array[int] = []
@export var biome_noise_abs_latitude_mins: Array[float] = []
@export var biome_noise_abs_latitude_maxs: Array[float] = []
@export var biome_noise_latitude_smoothness: Array[float] = []

@export_group("Texturas")
@export var textures: Array[Texture2D] = []
@export var normal_textures: Array[Texture2D] = []
@export var roughness_textures: Array[Texture2D] = []
@export var ao_textures: Array[Texture2D] = []
@export var height_textures: Array[Texture2D] = []
## height_textures contiene R=roughness/G=AO/B=height cuando se usan mapas empaquetados.
@export var packed_materials: bool = false
## Familias de pisadas en el mismo orden que textures.
@export var sound_materials: Array[StringName] = []
@export var slope_sound_material: StringName = &"rock"

@export_group("Pendiente")
@export var slope_texture: Texture2D
@export var slope_normal_texture: Texture2D
@export var slope_roughness_texture: Texture2D
@export var slope_ao_texture: Texture2D
@export var slope_height_texture: Texture2D
@export var slope_threshold: float = 0.35
@export var slope_smoothness: float = 0.18
@export var slope_height_blend_strength: float = 0.0
@export var slope_height_blend_sharpness: float = 0.2
@export var slope_breakup_scale: float = 0.025
@export var slope_breakup_strength: float = 0.0
@export var slope_breakup_anisotropy: float = 2.5
@export var slope_strata_thickness: float = 18.0
@export var slope_strata_strength: float = 0.0
@export var slope_strata_warp: float = 0.35

@export_group("Mezcla de materiales")
@export var parallax_enabled: bool = false
@export var parallax_strength: float = 0.09
@export var transition_smoothness: float = 10.0
@export var height_transition_noise_scale: float = 0.015
@export var height_transition_noise_strength: float = 12.0
@export var macro_variation_scale: float = 0.006
@export var macro_variation_strength: float = 0.18
## xyz = multiplicador lineal de albedo, w = saturación. Las entradas ausentes usan Vector4.ONE.
@export var texture_albedo_adjust: PackedVector4Array = PackedVector4Array()
@export var slope_albedo_adjust: Vector4 = Vector4.ONE

@export_group("Ríos, arrecifes y clima")
@export var river_settings: Dictionary = {}
@export var reef_settings: Dictionary = {}
@export var climate_settings: Dictionary = {}


func apply_shader_parameters(material: ShaderMaterial) -> void:
	for key in MATERIAL_PARAMETERS:
		material.set_shader_parameter(key, get(key))

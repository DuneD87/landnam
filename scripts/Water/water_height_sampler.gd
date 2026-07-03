class_name WaterHeightSampler extends Node

## Réplica en CPU de las olas Gerstner de water_shader.gdshader para física/flotabilidad.
## Devuelve el radio de superficie (desplazamiento radial) en una posición, invirtiendo el
## arrastre horizontal de Gerstner para coincidir con la superficie visual del shader. Debe
## mantenerse en sincronía con gerstner_surface().

var wave_speed: float
var wave_amplitude: float
var wave_steepness: float
var wave_base_length: float
var wave_octaves: int
var wave_direction: Vector2
var wave_pole: Vector3

var _material: ShaderMaterial

const _GOLDEN_ANGLE := 2.399963
const _TAU := 6.28318530718
const _INVERT_ITERATIONS := 3

## Lee del material los parámetros que intervienen en la altura de ola.
func setup(water_material: ShaderMaterial) -> void:
	_material = water_material
	wave_base_length = water_material.get_shader_parameter("wave_base_length")
	wave_octaves = int(water_material.get_shader_parameter("wave_octaves"))
	wave_direction = water_material.get_shader_parameter("wave_direction")
	var pole: Variant = water_material.get_shader_parameter("wave_pole")
	wave_pole = pole if pole != null else Vector3(0, 1, 0)
	_refresh_dynamic_params()

## Relee los parámetros que el weather muta en caliente sobre el material.
func _refresh_dynamic_params() -> void:
	wave_speed = _material.get_shader_parameter("wave_speed")
	wave_amplitude = _material.get_shader_parameter("wave_amplitude")
	wave_steepness = _material.get_shader_parameter("wave_steepness")

## Altura de ola (desplazamiento radial) en world_pos. Invierte por punto-fijo el arrastre
## horizontal de Gerstner: sin esto, con oleaje marcado la física y el visual se separan varios metros.
func get_height_at(world_pos: Vector3, time: float, planet_center: Vector3) -> float:
	if _material == null:
		return 0.0
	_refresh_dynamic_params()

	var local_q := world_pos - planet_center
	# Busca la posición "en reposo" cuya ola desplazada horizontalmente cae bajo world_pos.
	var guess := local_q
	for _i in _INVERT_ITERATIONS:
		var radial := guess.normalized()
		var disp := _gerstner_disp(guess, radial, time)
		var horiz := disp - radial * disp.dot(radial)
		guess = local_q - horiz

	var final_radial := guess.normalized()
	return _gerstner_disp(guess, final_radial, time).dot(final_radial)

## Desplazamiento world-space (tangencial + radial) de la suma de olas Gerstner en 'local'.
## Réplica de gerstner_surface() del shader (posición; la normal no hace falta en CPU).
func _gerstner_disp(local: Vector3, radial: Vector3, time: float) -> Vector3:
	var pole := wave_pole.normalized()
	var gx := pole.cross(Vector3(1, 0, 0) if absf(pole.x) < 0.9 else Vector3(0, 0, 1)).normalized()
	var gy := pole.cross(gx)

	var base_dir := wave_direction
	if absf(base_dir.x) + absf(base_dir.y) < 1e-4:
		base_dir = Vector2(1.0, 0.0)
	else:
		base_dir = base_dir.normalized()

	var octaves := clampi(wave_octaves, 1, 6)
	var amp := wave_amplitude
	var length := wave_base_length
	var ang := 0.0
	var horiz := Vector3.ZERO
	var vert := 0.0

	for i in octaves:
		var k := _TAU / maxf(length, 0.1)
		var ca := cos(ang)
		var sa := sin(ang)
		var dir_fixed := (gx * (base_dir.x * ca - base_dir.y * sa) + gy * (base_dir.x * sa + base_dir.y * ca)).normalized()
		var dir_tan := dir_fixed - radial * dir_fixed.dot(radial)
		var tan_len := dir_tan.length()
		var dir_unit := (dir_tan / tan_len) if tan_len > 1e-4 else Vector3.ZERO
		var q := wave_steepness / maxf(k * amp * float(octaves), 1e-4)
		var phase := k * dir_fixed.dot(local) + time * wave_speed * sqrt(k)
		horiz += dir_unit * (q * amp * cos(phase))
		vert += amp * sin(phase)
		amp *= 0.5
		length *= 0.5
		ang += _GOLDEN_ANGLE

	return horiz + radial * vert

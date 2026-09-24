class_name HumanBlink
extends Node

## Blinks a human every few seconds, now and then twice in a row, through the
## blink blend shapes of its body and of the proxies that shut with the
## eyelids (the eyelashes). CharacterAppearanceRig hands it the meshes.

## Seconds between blinks.
const INTERVAL := Vector2(2.0, 6.0)
## Chance that a blink comes twice, and the pause between the two.
const DOUBLE_CHANCE := 0.15
const DOUBLE_GAP := 0.1
## The lids shut fast, stay shut an instant and open more slowly.
const CLOSE_TIME := 0.07
const HOLD_TIME := 0.03
const OPEN_TIME := 0.14

## [MeshInstance3D, blend shape index, open value, change when shut].
var _targets: Array[Array] = []
var _rng := RandomNumberGenerator.new()
var _wait := 0.0
## Seconds into the current blink; negative between blinks.
var _time := -1.0
var _repeat := false
var _value := 0.0


func _ready() -> void:
	_rng.randomize()
	_wait = _rng.randf_range(0.5, INTERVAL.y)


## Blend shapes to drive, as [MeshInstance3D, blend shape name, value with
## the eyes open, change with them shut].
func set_targets(targets: Array[Array]) -> void:
	_targets.clear()
	for target in targets:
		var instance: MeshInstance3D = target[0]
		var index := instance.find_blend_shape_by_name(target[1])
		if index >= 0:
			_targets.append([instance, index, target[2], target[3]])
	_write(_value)


func _process(delta: float) -> void:
	if _time < 0.0:
		_wait -= delta
		if _wait > 0.0:
			return
		_time = 0.0
	_time += delta
	var opening := _time - CLOSE_TIME - HOLD_TIME
	if opening >= OPEN_TIME:
		_time = -1.0
		_repeat = not _repeat and _rng.randf() < DOUBLE_CHANCE
		_wait = DOUBLE_GAP if _repeat else _rng.randf_range(INTERVAL.x, INTERVAL.y)
		_write(0.0)
	elif opening >= 0.0:
		_write(1.0 - smoothstep(0.0, OPEN_TIME, opening))
	else:
		_write(smoothstep(0.0, CLOSE_TIME, _time))


func _write(value: float) -> void:
	_value = value
	for target in _targets:
		var instance: MeshInstance3D = target[0]
		if is_instance_valid(instance):
			instance.set_blend_shape_value(target[1], target[2] + target[3] * value)

class_name MuzzleBlood
extends Node

## El hocico de una fiera que come carne (Devouring) gotea sangre: mientras come y un buen rato
## después, cada vez menos, con alguna gota que queda en el suelo. Lo ensangrentado del morro y del
## pecho son manchas (BloodStains) que se quedan secándose hasta que la criatura vuelve al pool; esto
## es solo el goteo. Va colgado de la criatura y se va solo; clear() lo quita antes (al reciclarla).

const NODE_NAME := &"MuzzleBlood"
## Cuánto gotea tras el último bocado (s), cada cuánto al principio (s) y cuánto más espaciado al final.
const DRIP_TIME := 45.0
const DRIP_EVERY := Vector2(0.35, 1.1)
const SLOW_DOWN := 4.0
## Las gotas que dejan mancha en el suelo, y su tamaño (m).
const SPLAT_CHANCE := 0.3
const SPLAT_SIZE := Vector2(0.07, 0.14)
## Más lejos de la cámara no gotea (m): no se vería.
const NEAR := 40.0

var _creature: Node3D
var _mouth: Callable
var _left := 0.0
var _next := 0.0


## Un bocado de [creature]: gotea de nuevo DRIP_TIME s desde la boca que da [mouth] (un Callable que
## da un punto del mundo, o INF).
static func soak(creature: Node3D, mouth: Callable) -> void:
	if creature == null or SettingsManager.gore_level() == SettingsManager.GORE_OFF:
		return
	var drip := creature.get_node_or_null(NodePath(NODE_NAME)) as MuzzleBlood
	if drip == null:
		drip = MuzzleBlood.new()
		drip.name = NODE_NAME
		drip._creature = creature
		creature.add_child(drip)
	drip._mouth = mouth
	drip._left = DRIP_TIME


## Deja de gotear (la criatura vuelve al pool).
static func clear(creature: Node) -> void:
	var drip := creature.get_node_or_null(NodePath(NODE_NAME)) if creature != null else null
	if drip != null:
		creature.remove_child(drip)
		drip.queue_free()


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0 or not is_instance_valid(_creature):
		queue_free()
		return
	_next -= delta
	if _next > 0.0:
		return
	var fading := 1.0 - _left / DRIP_TIME
	_next = randf_range(DRIP_EVERY.x, DRIP_EVERY.y) * lerpf(1.0, SLOW_DOWN, fading)
	var point: Variant = _mouth.call() if _mouth.is_valid() else null
	if not (point is Vector3) or point == Vector3.INF:
		return
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null or camera.global_position.distance_to(point) > NEAR:
		return
	CombatFx.drip(_creature, point, randi_range(1, 3) if fading < 0.5 else 1)
	if randf() < SPLAT_CHANCE * (1.0 - fading * 0.5):
		var gravity: Variant = _creature.get(&"gravity_direction")
		var down := CombatFx._down()
		if gravity is Vector3 and (gravity as Vector3).length_squared() > 1e-6:
			down = (gravity as Vector3).normalized()
		BloodPool.spawn(_creature, point, down * 9.8, randf_range(SPLAT_SIZE.x, SPLAT_SIZE.y), 0.5,
			PhysicsLayers.WORLD, true)

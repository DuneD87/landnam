class_name Hurtbox
extends Area3D

## Zona que recibe golpes. Vive en su propia capa de física (LAYER) para que las hojas, zarpas y
## flechas la busquen sin tropezar con el terreno ni con los cuerpos, y para que esquivar sea
## simplemente apagarla durante los fotogramas de invulnerabilidad.
##
## No detecta nada por sí misma (monitoring apagado): son los golpes los que la consultan.

## Capa 9 de física: solo hurtboxes. Nada colisiona con ella; solo se consulta.
const LAYER := 1 << 8

## A quién pertenece: el cuerpo que se lleva el golpe (jugador o criatura).
var owner_body: Node3D
## Salud que descuenta. Si es null se busca en owner_body.
var health: HealthComponent
## Multiplicador de esta parte: la cabeza duele más.
var damage_multiplier: float = 1.0
## Nombre de la parte (body, head…), para depurar y para decidir reacciones.
var part: StringName = &"body"

var _enabled: bool = true


func _init() -> void:
	monitoring = false
	monitorable = true
	collision_layer = LAYER
	collision_mask = 0


## Crea un hurtbox con una forma y lo cuelga de [parent] en [local_xform].
static func attach(parent: Node3D, owner: Node3D, shape: Shape3D, local_xform: Transform3D,
		part_name: StringName = &"body", multiplier: float = 1.0) -> Hurtbox:
	var box := Hurtbox.new()
	box.name = "Hurtbox_%s" % part_name
	box.owner_body = owner
	box.part = part_name
	box.damage_multiplier = multiplier
	var col := CollisionShape3D.new()
	col.shape = shape
	col.transform = local_xform
	box.add_child(col)
	parent.add_child(box)
	return box


## Encendido/apagado (esquivas, muerte, criaturas dormidas del pool). Cambia la capa en vez de
## monitorable: una consulta de forma ve áreas no monitorizables igual.
func set_enabled(value: bool) -> void:
	if value == _enabled:
		return
	_enabled = value
	collision_layer = LAYER if value else 0


func is_enabled() -> bool:
	return _enabled


func get_health() -> HealthComponent:
	if health != null:
		return health
	if owner_body != null:
		health = owner_body.get_node_or_null("HealthComponent") as HealthComponent
	return health


## Aplica el golpe. Devuelve el daño que ha llegado a descontarse (0 si no había a quién).
func receive(info: DamageInfo) -> float:
	if not _enabled:
		return 0.0
	var target_health := get_health()
	if target_health == null:
		return 0.0
	info.part_multiplier = damage_multiplier
	return target_health.receive_hit(info)

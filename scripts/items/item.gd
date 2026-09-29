extends StaticBody3D
class_name Item

const config = preload("res://scripts/config.gd")

signal destroyed(position: Vector3, amount: int, item_data: ItemData)

@export var health: int = 300
@export var drop_amount_min: int = 1
@export var drop_amount_max: int = 3
@export var item_data: ItemData

## Dureza frente al embiste de un barco (J por m³ de roca). Los bloques de un casco cuestan 6000
## (GridBase.DEFAULT_IMPACT_TOUGHNESS): una roca aguanta varias veces más que la madera, así que
## solo un barco pesado y rápido la parte, y a costa de su proa.
const RAM_TOUGHNESS := 30000.0
## Mínimo de volumen que cuenta, para que un guijarro no se deshaga con un roce.
const RAM_MIN_VOLUME := 0.5

var _ram_damage := 0.0
var _ram_volume := -1.0


## Golpe de un barco (DynamicGridBody._apply_impact), en julios. Se acumula: embestidas que no
## la parten la van astillando hasta que cede.
func ram_damage(energy: float, world_pos: Vector3, rammer: Node) -> void:
	_ram_damage += energy
	var up :Vector3 = (world_pos - rammer.planet_node.global_pos).normalized() \
		if rammer != null and rammer.get("planet_node") != null else Vector3.UP
	var broken := _ram_damage >= RAM_TOUGHNESS * _volume()
	BlockDebris.burst(self, world_pos, up, 8 if broken else 2, 0.6 if broken else 0.35)
	AudioManager.play_material(&"block_impact", &"rock", world_pos,
		{"volume_offset_db": 0.0 if broken else -8.0})
	if broken:
		_on_destroyed()


## Volumen aproximado de la roca: la caja de sus formas de colisión, con la escala de la instancia.
func _volume() -> float:
	if _ram_volume >= 0.0:
		return _ram_volume
	var box := AABB()
	var first := true
	for child in get_children():
		var shape := child as CollisionShape3D
		if shape == null or shape.shape == null:
			continue
		var mesh := shape.shape.get_debug_mesh()
		var local := shape.transform * mesh.get_aabb() if mesh != null else AABB()
		box = local if first else box.merge(local)
		first = false
	var scale3 := global_transform.basis.get_scale()
	_ram_volume = maxf(box.size.x * scale3.x * box.size.y * scale3.y * box.size.z * scale3.z * 0.5,
		RAM_MIN_VOLUME)
	return _ram_volume


func take_damage(damage: int) -> void:
	health -= damage
	if health <= 0:
		_on_destroyed()

func _on_destroyed() -> void:
	destroyed.emit(global_position, get_drop_amount(), item_data)
	queue_free()

func get_drop_amount() -> int:
	return randi_range(drop_amount_min, drop_amount_max)

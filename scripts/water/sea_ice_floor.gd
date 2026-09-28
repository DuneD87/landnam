class_name SeaIceFloor extends StaticBody3D

## Suelo de la banquisa bajo el jugador. El agua es una esfera sin colisión; donde el mar está
## helado (WaterHeightSampler.last_ice, la réplica en CPU del hielo del shader) este bloque plano
## se coloca bajo sus pies, tangente al nivel del mar, y el jugador camina por encima.
##
## Va en su propia capa de colisión y solo el jugador la añade a su máscara: un barco que entra en
## el hielo no choca con él (su casco va por debajo del nivel del mar y saltaría por los aires), y
## los rayos de la fauna y del mapa (capa 1) no lo ven.

## Capa 17. Nada más en el proyecto la usa.
const LAYER := 1 << 16
## Hielo a partir del cual hay suelo. Por debajo el oleaje (que el hielo apaga en proporción) ya
## movería el agua visible por encima de un suelo quieto.
const MIN_ICE := 0.75
## Con témpanos 3D (SeaIceFloes) el suelo plano solo hace falta en la banquisa cerrada, para las
## grietas y los huecos entre esquinas; en la abierta se camina sobre los témpanos o se cae al agua.
const PACK_ICE := 0.97
## Altura de la cara de arriba sobre el nivel del mar en calma, en metros.
const TOP := 0.05
## Lado del bloque: el jugador no se sale de él entre dos fotogramas de física.
const SIZE := 60.0
const THICKNESS := 2.0

var _shape: CollisionShape3D


func _init() -> void:
	name = "SeaIceFloor"
	collision_layer = LAYER
	collision_mask = 0
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE, THICKNESS, SIZE)
	_shape.shape = box
	_shape.disabled = true
	add_child(_shape)


## Coloca el suelo bajo `feet` (posición del jugador) o lo apaga. `center` es el centro del
## planeta y `sea_radius` el radio del mar en calma. Devuelve true si el jugador está sobre hielo.
## `min_ice`: hielo a partir del cual hay suelo (MIN_ICE, o PACK_ICE si hay témpanos 3D).
func follow(feet: Vector3, center: Vector3, sea_radius: float, ice: float,
		min_ice: float = MIN_ICE) -> bool:
	var to_feet := feet - center
	var height := to_feet.length() - sea_radius
	var active := ice >= min_ice and height > -1.5 and height < 30.0
	_shape.disabled = not active
	if not active:
		return false
	var up := to_feet.normalized()
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var basis := Basis(side, up, side.cross(up))
	global_transform = Transform3D(basis, center + up * (sea_radius + TOP - THICKNESS * 0.5))
	return true

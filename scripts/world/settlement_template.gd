class_name SettlementTemplate extends Resource

## Una clase de poblado (granja, aldea, poblado): qué construcciones lleva y cuánto sitio ocupa. Cada
## sitio elige una al azar por su peso (SettlementField) y SettlementLayout la reparte alrededor de la
## plaza. Los poblados de otro bioma o de otra gente serán plantillas nuevas, no código nuevo.

@export var id: StringName
## Clave de traducción del nombre.
@export var display_name: String
## Lo a menudo que sale frente a las demás.
@export var weight: float = 1.0
## La construcción principal: al fondo de la plaza, frente a la llegada de la senda. Puede faltar.
@export var center: SettlementPrefab
## Las demás se sacan de aquí al azar, con repetición.
@export var buildings: Array[SettlementPrefab] = []
@export var count_min: int = 2
@export var count_max: int = 4
## Radio de la plaza libre del centro (m).
@export var plaza_radius: float = 9.0
## Hasta cuánto más allá de la plaza se reparten las construcciones (m).
@export var ring_depth: float = 16.0
## La cerca alrededor (SettlementWall): &"" ninguna, &"fence" cerca de varas, &"palisade" empalizada.
@export var wall: StringName = &""
## Cómo se reparten: &"ring" en corona alrededor de la plaza, o &"streets" (la villa): la principal al
## fondo de la plaza, [plaza_buildings] en corona a su alrededor y [buildings] a los dos lados de [streets]
## calles que salen de la plaza, con la puerta a la calle. En una villa caben count_min como poco, o no hay.
@export var layout: StringName = &"ring"
## La villa: lo que va alrededor de la plaza (la tienda, los puestos...) y cuántos.
@export var plaza_buildings: Array[SettlementPrefab] = []
@export var plaza_count_min: int = 0
@export var plaza_count_max: int = 0
## La villa: cuántas calles (la primera va hacia la llegada de la senda), lo que miden desde el centro y
## su ancho (m).
@export var streets: int = 4
@export var street_length: float = 50.0
@export var street_width: float = 5.0


## Todas las construcciones que puede llevar: la principal, las de la plaza y las demás, sin repetir.
func all_prefabs() -> Array[SettlementPrefab]:
	var out: Array[SettlementPrefab] = []
	for p: SettlementPrefab in [center] + buildings + plaza_buildings:
		if p != null and not out.has(p):
			out.append(p)
	return out

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

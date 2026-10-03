class_name StatusEffectData
extends Resource

## Definición de un estado duradero (pierna rota, intoxicación, enfermedad…): qué es, cuánto dura y
## qué limita. Es un dato (data/status/*.tres) sin estado propio: lo que le queda a cada caso lo
## lleva su StatusEffect, y lo cuenta StatusEffects.
##
## Los estados no tocan otros sistemas: el movimiento, el combate (Cripple), la escalada y el HUD
## preguntan cada tick a StatusEffects (blocks, speed_mult, is_zone_impaired…), así que cuando uno
## acaba, se carga la partida o se reaparece no hay nada que deshacer. Un estado con lógica propia
## (una fiebre que empeora y remite, un contagio) hereda de aquí y sobrescribe on_apply, on_tick y
## on_end.

enum Stacking {
	## Volver a cogerlo deja la duración más larga de las dos (y la gravedad mayor).
	REFRESH,
	## Volver a cogerlo suma la duración nueva a lo que quedaba.
	EXTEND,
	## Mientras dure, volver a cogerlo no hace nada.
	IGNORE,
}

const DATA_DIR := "res://data/status/"

@export var id: StringName
## Nombre para el HUD; con zona se le añade el lado ("Pierna rota (izq.)").
@export var display_name: String
## Va por parte del cuerpo (BodyDamage.ZONES): uno por pierna o brazo, cada uno con su tiempo.
@export var per_zone: bool = false
## Segundos de juego que dura, de la gravedad 0 (x) a la 1 (y).
@export var duration := Vector2(60.0, 60.0)
@export var stacking: Stacking = Stacking.REFRESH
## Lo que lo cura antes de tiempo (una tablilla, un antídoto): StatusEffects.cure(tag).
@export var cure_tags: Array[StringName] = []

@export_group("Efectos")
## La parte no sirve: una pierna no carga peso (cojea, o se arrastra si son las dos).
@export var impairs_zone: bool = false
## Acciones que impide: sprint, jump, dodge, attack, climb.
@export var blocks: Array[StringName] = []
## Multiplica la velocidad de andar y correr.
@export var speed_mult: float = 1.0
## Multiplica lo que recupera el aguante.
@export var stamina_regen_mult: float = 1.0
## Vida por segundo (negativa: la quita).
@export var health_per_second: float = 0.0

static var _catalog: Dictionary = {}


## La definición de [effect_id], de data/status/ (null si no existe).
static func find(effect_id: StringName) -> StatusEffectData:
	if _catalog.is_empty():
		_load_catalog()
	return _catalog.get(effect_id)


static func ids() -> PackedStringArray:
	if _catalog.is_empty():
		_load_catalog()
	var out := PackedStringArray()
	for k: StringName in _catalog:
		out.append(String(k))
	return out


static func _load_catalog() -> void:
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		push_error("StatusEffectData: no se pudo abrir " + DATA_DIR)
		return
	for file_name in dir.get_files():
		# Exportado, los .tres pasan a .tres.remap.
		file_name = file_name.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var data := load(DATA_DIR.path_join(file_name)) as StatusEffectData
		if data == null or data.id == &"":
			push_warning("StatusEffectData: no es un estado válido: " + file_name)
			continue
		_catalog[data.id] = data


func duration_for(severity: float) -> float:
	return lerpf(duration.x, duration.y, clampf(severity, 0.0, 1.0))


## Al empezar (no al cargar la partida: el estado ya venía de antes).
func on_apply(_effects: StatusEffects, _effect: StatusEffect) -> void:
	pass


## Cada tick de juego, antes de descontarle el tiempo.
func on_tick(_effects: StatusEffects, _effect: StatusEffect, _delta: float) -> void:
	pass


## Al acabar: [cured] si lo quitó una cura o reaparecer, false si se le acabó el tiempo.
func on_end(_effects: StatusEffects, _effect: StatusEffect, _cured: bool) -> void:
	pass

class_name SoundEvent
extends Resource

## Un evento de audio del juego: sus variantes de clip y cómo suena (bus, volumen, pitch,
## atenuación), más sus topes de gasto (voces simultáneas y cooldown). Todo play() del
## AudioManager se resuelve contra uno de estos, así que afinar el audio es editar .tres, no código.

## Identificador con el que se pide el sonido. Vacío = se usa el nombre del archivo.
@export var event_id: StringName = &""
## Variantes del sonido; se elige una al azar evitando repetir la última. Vacío = evento mudo,
## que se descarta sin ruido: sirve para declarar el catálogo antes de tener los clips.
## El loop se declara abajo, NO en el .import del clip: un one-shot que se repita en bucle
## nunca devolvería su voz al pool.
@export var streams: Array[AudioStream] = []
@export_enum("SFX", "Ambient", "UI", "Music", "Voice") var bus: String = "SFX"

@export_group("Mezcla")
@export_range(-40.0, 12.0) var volume_db: float = 0.0
## Variación aleatoria de volumen en dB (±). Rompe la repetición mecánica de un clip único.
@export_range(0.0, 12.0) var volume_jitter_db: float = 0.0
@export_range(0.1, 4.0) var pitch: float = 1.0
@export_range(0.0, 0.5) var pitch_jitter: float = 0.0

@export_group("Espacialización")
## Alcance en metros. Más allá ni se coge voz del pool.
@export var max_distance: float = 60.0
## Radio (m) dentro del cual suena a volume_db sin atenuar.
@export var unit_size: float = 4.0
@export var attenuation: AudioStreamPlayer3D.AttenuationModel = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE

@export_group("Presupuesto")
## Voces simultáneas de ESTE evento. Un impacto que rompe 40 bloques no son 40 sonidos.
@export_range(1, 16) var max_voices: int = 4
## Segundos que el evento queda mudo tras dispararse. 0 = sin cooldown.
@export_range(0.0, 2.0) var cooldown: float = 0.05

@export_group("Continuo")
## Marca el evento como loop. El AudioManager no lo dispara; lo usa EntityAudio.
@export var looping: bool = false
## Fundido de entrada y salida del loop, en segundos.
@export_range(0.0, 5.0) var fade_time: float = 0.4

var _last_index: int = -1


## Un .tres puede referenciar un clip que todavía no está en disco; ese hueco llega como null.
func is_valid() -> bool:
	for stream in streams:
		if stream != null:
			return true
	return false


## Elige una variante al azar, evitando repetir la anterior cuando hay más de una.
func pick_stream() -> AudioStream:
	var usable: Array[AudioStream] = []
	for stream in streams:
		if stream != null:
			usable.append(stream)
	if usable.is_empty():
		return null
	if usable.size() == 1:
		return usable[0]
	var index := randi() % usable.size()
	if index == _last_index:
		index = (index + 1) % usable.size()
	_last_index = index
	return usable[index]


func roll_volume_db() -> float:
	return volume_db + randf_range(-volume_jitter_db, volume_jitter_db)


func roll_pitch() -> float:
	return maxf(0.01, pitch + randf_range(-pitch_jitter, pitch_jitter))

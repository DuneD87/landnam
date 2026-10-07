class_name CreatureCombatProfile
extends Resource

## Cómo pelea una especie: sus ataques y su temperamento (velocidades, guardia, recuperación y
## sonidos). Lo lee CreatureCombatState; una especie nueva es un .tres nuevo, sin código.

@export var attacks: Array[CreatureAttack] = []

@export_group("Engage")
## Más allá de esta distancia deja de perseguir.
@export var disengage_distance: float = 45.0
## Correa: si el objetivo se aleja más que esto de donde vive (NPCController.get_home()), lo deja
## estar y vuelve a lo suyo. 0 = lo sigue a donde vaya.
@export var leash_distance: float = 0.0
## Segundos que se planta amenazando al empezar contra el jugador, y el clip y el sonido de la
## amenaza. 0 = va directo.
@export var threaten_time: float = 1.1
@export var threaten_anim: StringName = &""
@export var threaten_sound: StringName = &""

@export_group("Movement")
## Velocidad de persecución y al rodear al objetivo (m/s).
@export var chase_speed: float = 6.2
@export var circle_speed: float = 2.4
## Carrera a fondo para cerrar distancia: más lejos que sprint_distance corre a sprint_speed,
## mientras le aguante el fuelle (sprint_stamina segundos, que recupera a la mitad de ritmo).
## 0 = no esprinta.
@export var sprint_speed: float = 0.0
@export var sprint_distance: float = 10.0
@export var sprint_stamina: float = 8.0
## Anticipación (s, como mucho) al perseguir: corre hacia donde va a estar el objetivo.
@export var chase_lead: float = 0.0

@export_group("Recovery")
## Segundos que se queda quieto tras un ataque: la ventana para castigarle. Mientras, se vuelve
## hacia el objetivo a recover_turn_rate grados/s.
@export var recover_time := Vector2(0.55, 1.0)
@export var recover_turn_rate: float = 180.0
## Tras recuperarse, probabilidad de rodear al objetivo en vez de volver a entrar, si lo tiene
## más cerca que circle_max_distance.
@export_range(0.0, 1.0) var circle_chance: float = 0.35
@export var circle_max_distance: float = 6.0
## Distancia a la que lo rodea y cuánto rato.
@export var circle_distance: float = 4.5
@export var circle_time: float = 1.6

@export_group("Choice")
## Peso del ataque que acaba de usar, para que no repita siempre el mismo.
@export_range(0.0, 1.0) var repeat_penalty: float = 1.0
## Ataques seguidos como mucho, encadenando follow_ups.
@export var max_combo: int = 1

@export_group("Poise")
## Guardia: el desgaste acumulado que aguanta antes de tambalearse.
@export var max_poise: float = 85.0
## Lo que recupera por segundo, tras poise_regen_delay segundos sin encajar golpes.
@export var poise_regen: float = 18.0
@export var poise_regen_delay: float = 2.0
## Segundos que se queda vendido al romperle la guardia, y las animaciones que pone entonces,
## una al azar (ninguna = se queda quieto).
@export var stagger_time: float = 1.5
@export var stagger_anims: Array[StringName] = []
## Segundos que se queda vendido cuando le paran un golpe en seco (la ventana del contraataque).
@export var parried_time: float = 1.2

@export_group("Animation")
## Fundidos de entrada y salida de las animaciones de ataque.
@export var action_fade_in: float = 0.3
@export var action_fade_out: float = 0.4

@export_group("Sound")
## Al empezar el aviso de un ataque (si el ataque no trae el suyo), al abrirse cada ventana de
## golpe (ídem) y al romperle la guardia.
@export var attack_sound: StringName = &""
@export var swing_sound: StringName = &""
@export var stagger_sound: StringName = &""
## Tono de su voz (amenaza, gruñidos): otra especie puede usar los mismos sonidos más graves o
## más agudos.
@export var voice_pitch: float = 1.0

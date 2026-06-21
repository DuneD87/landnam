class_name WeatherParticlePreset
extends Resource

## Datos de un efecto de precipitación. El mismo WeatherParticles construye cualquiera desde un
## preset, así que lluvia/nieve/etc. son solo datos. rain()/snow() traen los valores por defecto.

@export_group("Emisión")
## Nº máximo de partículas; la intensidad del clima lo escala en caliente (amount_ratio).
@export var amount: int = 2000
@export var lifetime: float = 2.0
## Mitad-extensión de la caja de emisión (m), centrada en el jugador y orientada en radial.
@export var box_extents: Vector3 = Vector3(35.0, 18.0, 35.0)
## Desplazamiento de la caja hacia arriba (m): deja la mayor parte sobre la cabeza.
@export var volume_offset: float = 6.0

@export_group("Movimiento")
## Aceleración de caída hacia el centro del planeta (m/s²).
@export var gravity_strength: float = 20.0
@export var initial_velocity_min: float = 8.0
@export var initial_velocity_max: float = 12.0
## Apertura del chorro inicial (grados). 0 = vertical.
@export_range(0.0, 180.0) var spread: float = 4.0
## Frenado por aire. Alto en nieve (flota); ~0 en lluvia.
@export var damping_min: float = 0.0
@export var damping_max: float = 0.0
## Deriva por turbulencia. 0 = recta; >0 = vaivén de copo.
@export var turbulence_strength: float = 0.0
@export var turbulence_scale: float = 9.0

@export_group("Aspecto")
@export var mesh_size: Vector2 = Vector2(0.5, 0.5)
@export var scale_min: float = 0.8
@export var scale_max: float = 1.2
@export var color: Color = Color(1.0, 1.0, 1.0, 0.85)
## Si es null, se genera un punto suave radial por código.
@export var texture: Texture2D


static func rain() -> WeatherParticlePreset:
	var p := WeatherParticlePreset.new()
	p.amount = 18000
	p.lifetime = 1.3
	p.box_extents = Vector3(20.0, 10.0, 20.0)
	p.volume_offset = 10.0
	p.gravity_strength = 22.0
	p.initial_velocity_min = 13.0
	p.initial_velocity_max = 17.0
	p.spread = 4.0
	p.mesh_size = Vector2(0.06, 0.45)
	p.color = Color(0.78, 0.85, 1.0, 0.7)
	return p


static func snow() -> WeatherParticlePreset:
	var p := WeatherParticlePreset.new()
	p.amount = 15000
	p.lifetime = 6.0
	p.box_extents = Vector3(20.0, 20.0, 20.0)
	p.volume_offset = 10.0
	p.gravity_strength = 1.5
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.spread = 25.0
	p.damping_min = 0.4
	p.damping_max = 1.0
	p.turbulence_strength = 6.0
	p.turbulence_scale = 9.0
	p.mesh_size = Vector2(0.16, 0.16)
	p.scale_min = 1.5
	p.scale_max = 2.4
	p.color = Color(1.0, 1.0, 1.0, 0.9)
	return p

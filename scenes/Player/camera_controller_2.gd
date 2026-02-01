extends Camera3D

@export var mouse_sensitivity := 0.002  # Sensibilidad del ratón
@export var camera_distance := 5.0      # Distancia de la cámara al jugador
@export var camera_height := 2.0        # Altura de la cámara sobre el jugador

var yaw := 0.0
var pitch := 0.0

func _ready():
	# Capturar el ratón para que no sea visible
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Posicionar la cámara inicialmente
	position = Vector3(0, camera_height, camera_distance)

func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Actualizar yaw (rotación horizontal) y pitch (rotación vertical)
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		# Limitar el pitch para que no gire demasiado hacia arriba o abajo
		pitch = clamp(pitch, -1.5, 1.5)

func _process(delta):
	# Rotar la cámara alrededor del origen (el jugador) usando yaw y pitch
	rotation.y = yaw  # Rotación horizontal
	rotation.x = pitch  # Rotación vertical
	# Mantener la cámara a la distancia y altura correctas
	position = Vector3(0, camera_height, camera_distance).rotated(Vector3.UP, yaw)

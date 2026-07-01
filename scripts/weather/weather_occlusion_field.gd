class_name WeatherOcclusionField
extends Node3D

## Rejilla de oclusión radial: por cada celda alrededor del jugador lanza un rayo hacia arriba
## buscando un techo y guarda su altura en una textura; el shader oculta las gotas que quedan por
## debajo (no llueve dentro de cuevas, pero sí al aire libre). La textura es RG: R = altura del
## techo (oclusión de lluvia), G = altura del suelo (para posar los splashes sobre el terreno).

@export var grid_resolution: int = 100
@export var grid_size: float = 100.0
## Distancia (m) que se busca un techo hacia arriba.
@export var probe_above: float = 800.0
## Offset de codificación (m): "sin dato" decodifica a -este valor (nunca oculta / nunca posa).
@export var probe_below: float = 60.0
## Distancia (m) que se busca el suelo hacia abajo (para los splashes).
@export var probe_ground: float = 80.0
@export_flags_3d_physics var terrain_mask: int = 3
@export var update_interval: float = 0.15
## Filas de la rejilla reconstruidas por frame (time-slicing); acota el coste por frame.
@export var rows_per_update: int = 8
## Depura los rayos (VERDE = techo, ROJO = cielo abierto, AZUL = suelo, x-ray). Apágalo para jugar.
@export var debug_draw: bool = false

# Offset (m) sobre el jugador donde arranca el rayo de techo, para no chocar con el suelo de los pies.
const CEILING_START := 1.0
# Offset (m) sobre el jugador donde arranca el rayo de suelo.
const GROUND_START := 3.0

var center: Vector3
var x_axis: Vector3 = Vector3.RIGHT
var z_axis: Vector3 = Vector3.BACK
var up: Vector3 = Vector3.UP

## Lo enciende WeatherFX solo con lluvia activa: añade el rayo de suelo (canal G).
var ground_enabled: bool = false

## True si hay techo justo sobre el jugador (cueva/voladizo). Se recalcula al inicio de cada barrido.
var player_occluded: bool = false

var _player: Node3D
var _planet_center: Vector3
var _img: Image
var _tex: ImageTexture
var _accum: float = 999.0
var _debug_im: ImmediateMesh
var _debug_mi: MeshInstance3D

var _row: int = -1
var _w_center: Vector3
var _w_x: Vector3 = Vector3.RIGHT
var _w_z: Vector3 = Vector3.BACK
var _w_up: Vector3 = Vector3.UP
var _w_exclude: Array = []
var _w_inv_span: float = 0.0
var _w_ground: bool = false
var _drawing: bool = false


func setup(player: Node3D, planet_center: Vector3) -> void:
	_player = player
	_planet_center = planet_center
	var n := maxi(grid_resolution, 2)
	_img = Image.create_empty(n, n, false, Image.FORMAT_RGBAF)
	_img.fill(Color(0, 0, 0.5, 0.5))
	_tex = ImageTexture.create_from_image(_img)
	_create_debug()


func _create_debug() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	_debug_im = ImmediateMesh.new()
	_debug_mi = MeshInstance3D.new()
	_debug_mi.name = "OcclusionDebug"
	_debug_mi.mesh = _debug_im
	_debug_mi.material_override = mat
	_debug_mi.top_level = true
	add_child(_debug_mi)
	_debug_mi.global_transform = Transform3D.IDENTITY
	_debug_mi.visible = false


## Actualiza el centro del planeta tras un rebase de origen flotante; sin esto la radial (up) se
## desalinea porque pos se desplaza con el rebase pero _planet_center se quedaría con el valor viejo.
func set_planet_center(c: Vector3) -> void:
	_planet_center = c
	_row = -1


func get_height_texture() -> Texture2D:
	return _tex


func half_size() -> float:
	return grid_size * 0.5


func span() -> float:
	return probe_above + probe_below


## Reconstruye la rejilla y devuelve true solo el frame en que queda completa (centro/ejes/textura nuevos).
func update(delta: float) -> bool:
	if debug_draw:
		_accum += delta
		if _accum < update_interval:
			return false
		_accum = 0.0
		return _rebuild_full()

	if _row < 0:
		_accum += delta
		if _accum < update_interval:
			return false
		if not _begin_sweep():
			return false
	return _advance_sweep()


## Congela el marco de referencia del barrido (centro/ejes/up + exclusión + inv_span + ground).
func _compute_frame() -> bool:
	if _player == null or not is_instance_valid(_player) or _img == null:
		return false
	var pos := _player.global_position
	var u := pos - _planet_center
	u = u.normalized() if u.length_squared() > 0.0001 else Vector3.UP
	var ref := Vector3.FORWARD
	if absf(u.dot(ref)) > 0.99:
		ref = Vector3.RIGHT
	_w_up = u
	_w_x = ref.cross(u).normalized()
	_w_z = _w_x.cross(u).normalized()
	_w_center = pos
	_w_inv_span = 1.0 / maxf(span(), 0.001)
	_w_ground = ground_enabled
	_w_exclude = []
	if _player is CollisionObject3D:
		_w_exclude = [(_player as CollisionObject3D).get_rid()]
	player_occluded = _center_has_ceiling(pos, u)
	return true


## Un único rayo central hacia arriba: ¿hay techo justo sobre el jugador? Da el estado de cueva de
## inmediato (al inicio del barrido), sin esperar a que el time-slicing llegue a la celda central.
func _center_has_ceiling(pos: Vector3, u: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		pos + u * CEILING_START, pos + u * probe_above, terrain_mask)
	query.exclude = _w_exclude
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _begin_sweep() -> bool:
	if not _compute_frame():
		return false
	if _debug_mi != null:
		_debug_mi.visible = false
	_row = 0
	return true


## Procesa hasta rows_per_update filas; al completar el barrido publica el marco y la textura.
func _advance_sweep() -> bool:
	var space := get_world_3d().direct_space_state
	var n := _img.get_width()
	var end_row := mini(_row + maxi(rows_per_update, 1), n)
	for j in range(_row, end_row):
		for i in n:
			_img.set_pixel(i, j, _probe_cell(i, j, n, space))
	_row = end_row
	if _row < n:
		return false
	_commit_sweep()
	_row = -1
	_accum = 0.0
	return true


## Reconstrucción completa en un frame (ruta de depuración): dibuja los rayos y publica de golpe.
func _rebuild_full() -> bool:
	if not _compute_frame():
		return false
	var space := get_world_3d().direct_space_state
	var n := _img.get_width()
	_drawing = _debug_im != null
	if _drawing:
		_debug_im.clear_surfaces()
		_debug_im.surface_begin(Mesh.PRIMITIVE_LINES)
	for j in n:
		for i in n:
			_img.set_pixel(i, j, _probe_cell(i, j, n, space))
	if _drawing:
		_debug_im.surface_end()
		_drawing = false
	if _debug_mi != null:
		_debug_mi.visible = true
	_commit_sweep()
	return true


## Publica el marco congelado (lo que lee WeatherFX) y sube la imagen a la GPU.
func _commit_sweep() -> void:
	center = _w_center
	x_axis = _w_x
	z_axis = _w_z
	up = _w_up
	_tex.update(_img)


## Lanza los rayos de la celda (i, j) y devuelve su color RGBA: R=techo, G=suelo, B,A=normal del suelo.
func _probe_cell(i: int, j: int, n: int, space: PhysicsDirectSpaceState3D) -> Color:
	var fw := (float(j) / float(n - 1) - 0.5) * grid_size
	var fu := (float(i) / float(n - 1) - 0.5) * grid_size
	var cell := _w_center + _w_x * fu + _w_z * fw

	var from := cell + _w_up * CEILING_START
	var to := cell + _w_up * probe_above
	var query := PhysicsRayQueryParameters3D.create(from, to, terrain_mask)
	query.exclude = _w_exclude
	var hit := space.intersect_ray(query)
	var ceil_norm := 0.0
	if not hit.is_empty():
		var hp: Vector3 = hit["position"]
		ceil_norm = clampf(((hp - _w_center).dot(_w_up) + probe_below) * _w_inv_span, 0.0, 1.0)
		if _drawing:
			_debug_im.surface_set_color(Color.GREEN)
			_debug_im.surface_add_vertex(from)
			_debug_im.surface_add_vertex(hp)
	elif _drawing:
		_debug_im.surface_set_color(Color.RED)
		_debug_im.surface_add_vertex(from)
		_debug_im.surface_add_vertex(to)

	var ground_norm := 0.0
	var gn_x := 0.5
	var gn_z := 0.5
	if _w_ground:
		var gfrom := cell + _w_up * GROUND_START
		var gto := cell - _w_up * probe_ground
		var gquery := PhysicsRayQueryParameters3D.create(gfrom, gto, terrain_mask)
		gquery.exclude = _w_exclude
		var ghit := space.intersect_ray(gquery)
		if not ghit.is_empty():
			var ghp: Vector3 = ghit["position"]
			ground_norm = clampf(((ghp - _w_center).dot(_w_up) + probe_below) * _w_inv_span, 0.0, 1.0)
			var gn: Vector3 = (ghit["normal"] as Vector3).normalized()
			gn_x = clampf(gn.dot(_w_x) * 0.5 + 0.5, 0.0, 1.0)
			gn_z = clampf(gn.dot(_w_z) * 0.5 + 0.5, 0.0, 1.0)
			if _drawing:
				_debug_im.surface_set_color(Color.BLUE)
				_debug_im.surface_add_vertex(gfrom)
				_debug_im.surface_add_vertex(ghp)

	return Color(ceil_norm, ground_norm, gn_x, gn_z)

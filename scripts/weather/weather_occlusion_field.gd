class_name WeatherOcclusionField
extends Node3D

## Rejilla de oclusión radial: por cada celda alrededor del jugador lanza un rayo HACIA ARRIBA
## buscando un techo (roca de cueva, tejado...) y guarda su altura en una textura; el shader oculta
## las gotas que quedan por debajo → no llueve dentro de cuevas, pero sí en el aire libre.
##
## Hacia ARRIBA a propósito: golpea el techo por su cara frontal a cualquier profundidad (hacia
## abajo fallaba: cruzaba el techo por la cara trasera y captaba el suelo). Altura normalizada a
## [0,1] en la textura.
##
## La textura es RG: R = altura del TECHO (oclusión de lluvia), G = altura del SUELO (para posar los
## splashes de la lluvia sobre el terreno). Ambas con la misma codificación (span/probe_below).

@export var grid_resolution: int = 40
@export var grid_size: float = 100.0
## Distancia (m) que se busca un techo hacia arriba.
@export var probe_above: float = 800.0
## Offset de codificación (m): "sin dato" decodifica a -este valor (nunca oculta / nunca posa).
@export var probe_below: float = 60.0
## Distancia (m) que se busca el suelo hacia abajo (para los splashes).
@export var probe_ground: float = 80.0
@export_flags_3d_physics var terrain_mask: int = 3
@export var update_interval: float = 0.15
## Depura los rayos (VERDE = techo, ROJO = cielo abierto, AZUL = suelo, x-ray). Apágalo para jugar.
@export var debug_draw: bool = false

# Offset (m) sobre el jugador donde arranca el rayo de techo, para no chocar con el suelo de los pies.
const CEILING_START := 1.0
# Offset (m) sobre el jugador donde arranca el rayo de suelo (capta terreno algo por encima de los pies).
const GROUND_START := 3.0

# Colocación actual de la rejilla (la lee WeatherFX).
var center: Vector3
var x_axis: Vector3 = Vector3.RIGHT
var z_axis: Vector3 = Vector3.BACK
var up: Vector3 = Vector3.UP

## Lo enciende WeatherFX solo cuando hay splashes (lluvia activa): añade el rayo de suelo (canal G).
## Apagado (p. ej. solo nieve) NO se lanza ese rayo → no se duplica el coste de raycasts.
var ground_enabled: bool = false

var _player: Node3D
var _planet_center: Vector3
var _img: Image
var _tex: ImageTexture
var _accum: float = 999.0   # fuerza una reconstrucción en el primer frame
var _debug_im: ImmediateMesh
var _debug_mi: MeshInstance3D


func setup(player: Node3D, planet_center: Vector3) -> void:
	_player = player
	_planet_center = planet_center
	var n := maxi(grid_resolution, 2)
	_img = Image.create_empty(n, n, false, Image.FORMAT_RGF)
	_img.fill(Color(0, 0, 0, 0))   # R=techo, G=suelo; 0 = sin dato (decodifica a -probe_below)
	_tex = ImageTexture.create_from_image(_img)
	_create_debug()


func _create_debug() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true   # x-ray
	_debug_im = ImmediateMesh.new()
	_debug_mi = MeshInstance3D.new()
	_debug_mi.name = "OcclusionDebug"
	_debug_mi.mesh = _debug_im
	_debug_mi.material_override = mat
	_debug_mi.top_level = true   # vértices en mundo
	add_child(_debug_mi)
	_debug_mi.global_transform = Transform3D.IDENTITY
	_debug_mi.visible = false


func get_height_texture() -> Texture2D:
	return _tex


func half_size() -> float:
	return grid_size * 0.5


func span() -> float:
	return probe_above + probe_below


## La conduce WeatherFX para reconstruir antes de empujar la textura al shader (mismo frame).
## Devuelve true SOLO el frame en que se reconstruyó la rejilla (centro/ejes/textura nuevos), para
## que WeatherFX empuje los uniforms únicamente entonces y no en cada frame.
func update(delta: float) -> bool:
	_accum += delta
	if _accum >= update_interval:
		_accum = 0.0
		_rebuild()
		return true
	return false


func _rebuild() -> void:
	if _player == null or not is_instance_valid(_player) or _img == null:
		return
	var pos := _player.global_position
	up = pos - _planet_center
	up = up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
	var ref := Vector3.FORWARD
	if absf(up.dot(ref)) > 0.99:
		ref = Vector3.RIGHT
	x_axis = ref.cross(up).normalized()
	z_axis = x_axis.cross(up).normalized()
	center = pos

	var space := get_world_3d().direct_space_state
	var n := _img.get_width()
	var inv_span := 1.0 / maxf(span(), 0.001)
	var exclude: Array = []
	if _player is CollisionObject3D:
		exclude = [(_player as CollisionObject3D).get_rid()]

	var draw := debug_draw and _debug_im != null
	if draw:
		_debug_im.clear_surfaces()
		_debug_im.surface_begin(Mesh.PRIMITIVE_LINES)

	for j in n:
		var fw := (float(j) / float(n - 1) - 0.5) * grid_size
		for i in n:
			var fu := (float(i) / float(n - 1) - 0.5) * grid_size
			var cell := pos + x_axis * fu + z_axis * fw

			# Techo (hacia arriba) → canal R.
			var from := cell + up * CEILING_START
			var to := cell + up * probe_above
			var query := PhysicsRayQueryParameters3D.create(from, to, terrain_mask)
			query.exclude = exclude
			var hit := space.intersect_ray(query)
			var ceil_norm := 0.0
			if not hit.is_empty():
				var hp: Vector3 = hit["position"]
				ceil_norm = clampf(((hp - pos).dot(up) + probe_below) * inv_span, 0.0, 1.0)
				if draw:
					_debug_im.surface_set_color(Color.GREEN)
					_debug_im.surface_add_vertex(from)
					_debug_im.surface_add_vertex(hp)
			elif draw:
				_debug_im.surface_set_color(Color.RED)
				_debug_im.surface_add_vertex(from)
				_debug_im.surface_add_vertex(to)

			# Suelo (hacia abajo) → canal G, para posar los splashes. Solo si hay lluvia (ground_enabled):
			# sin splashes este rayo no aporta nada, así que evitamos duplicar el coste de raycasts.
			var ground_norm := 0.0
			if ground_enabled:
				var gfrom := cell + up * GROUND_START
				var gto := cell - up * probe_ground
				var gquery := PhysicsRayQueryParameters3D.create(gfrom, gto, terrain_mask)
				gquery.exclude = exclude
				var ghit := space.intersect_ray(gquery)
				if not ghit.is_empty():
					var ghp: Vector3 = ghit["position"]
					ground_norm = clampf(((ghp - pos).dot(up) + probe_below) * inv_span, 0.0, 1.0)
					if draw:
						_debug_im.surface_set_color(Color.BLUE)
						_debug_im.surface_add_vertex(gfrom)
						_debug_im.surface_add_vertex(ghp)

			_img.set_pixel(i, j, Color(ceil_norm, ground_norm, 0.0, 1.0))

	if draw:
		_debug_im.surface_end()
	_debug_mi.visible = debug_draw
	_tex.update(_img)

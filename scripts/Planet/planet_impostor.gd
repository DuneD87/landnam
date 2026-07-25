class_name PlanetImpostor extends MeshInstance3D

## Impostor analítico de un cuerpo planetario visto de lejos: un quad orientado a la cámara
## donde planet_impostor.gdshader traza la esfera. Sustituye al VoxelLodTerrain cuando el
## planeta está tan lejos que su LOD tope degenera en un octaedro, y se funde con dither al
## acercarse. Reproyecta la esfera dentro del far plane conservando su tamaño angular.

const SHADER_PATH := "res://shaders/planet_impostor.gdshader"

## Uniforms de aspecto que el loader empuja cada frame (mismo nombre aquí y en el shader).
const APPEARANCE_PARAMS: Array[StringName] = [
	&"fallback_color", &"relief_strength", &"terminator_softness", &"night_light",
	&"rim_strength", &"rim_color", &"debug_mode",
]

@export var planet_radius: float = 1000.0
## Distancia (en radios, desde el centro) a partir de la cual solo se ve el impostor.
@export var show_factor: float = 3.0
## Distancia (en radios) por debajo de la cual solo se ve el terreno real. La banda entre
## ambas es el crossfade, y hace de histéresis: no hay parpadeo en el umbral.
@export var hide_factor: float = 2.0
## Fracción del far plane de la cámara donde se ancla el proxy cuando el planeta cae fuera.
@export var proxy_far_ratio: float = 0.85
## Resolución del equirect horneado. A 1024x512 un téxel son ~37 u en una luna de radio 6000,
## que es del orden del píxel de pantalla a la distancia de transición.
@export var map_size: Vector2i = Vector2i(1024, 512)
## Semirrango de búsqueda del SDF alrededor del radio nominal: la superficie del planeta debe
## caer dentro de +/- este valor. Para la luna el ruido del grafo vale 400.
@export var height_range: float = 600.0

## Color plano mientras el bake (en hilo) no ha llegado.
@export var fallback_color: Color = Color(0.55, 0.53, 0.5)
## Ganancia del relieve sobre la pendiente real del mapa de alturas. 1 = tal cual.
@export var relief_strength: float = 1.0
@export var terminator_softness: float = 0.03
@export var night_light: float = 0.03
@export var rim_strength: float = 0.0
@export var rim_color: Color = Color(0.35, 0.55, 1.0)
## Diagnóstico: 0 normal, 1 albedo crudo, 2 altura, 3 normal, 4 verde=hay mapa / magenta=no.
@export var debug_mode: int = 0

var _center_node: Node3D
var _body_nodes: Array[Node3D] = []
var _sun_source: Node
var _mat: ShaderMaterial
var _body_visible: bool = true

## Prepara el impostor y lanza el bake del mapa de superficie. 'body_nodes' son los nodos a
## ocultar mientras el impostor está a pleno, y 'sun_source' expone 'sun_dir' (el planet_loader).
## El centro se lee vivo de planet.voxel_terrain, así el origen flotante lo arrastra solo.
func setup(planet: Planet, body_nodes: Array[Node3D], sun_source: Node) -> void:
	_center_node = planet.voxel_terrain
	_body_nodes = body_nodes
	_sun_source = sun_source
	planet_radius = planet.radius

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mesh = quad

	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	_mat.set_shader_parameter("body_radius", planet_radius)
	material_override = _mat

	# El quad se coloca en world-space a mano: el transform del planeta no debe arrastrarlo.
	top_level = true
	# El proyecto tiene physics_interpolation activado, y este nodo se recoloca en _process (no en
	# _physics_process). Interpolado, se renderizaría con el transform de hace un tick mientras
	# sphere_center/radius van sin interpolar, y al volver de invisible partiría del transform
	# obsoleto de cuando se ocultó: en ambos casos el borde del lienzo recorta la silueta trazada.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	visible = false
	_push_appearance()

	_install_surface(planet)


## Hornea el mapa de alturas y empuja al shader los mismos arrays de bioma que usa el terreno.
## Si el bake falla, el impostor se queda con 'fallback_color' plano (y el aviso en consola).
func _install_surface(planet: Planet) -> void:
	var data := PlanetImpostorBaker.bake(planet, map_size, height_range)
	if data.is_empty():
		return

	_mat.set_shader_parameter("height_map", data.texture)
	_mat.set_shader_parameter("height_min", data.height_min)
	_mat.set_shader_parameter("height_range", data.height_range)
	_mat.set_shader_parameter("biome_colors", data.biome_colors)

	_mat.set_shader_parameter("biome_count", planet.biome_count)
	_mat.set_shader_parameter("textures_per_biome", planet.textures_per_biome)
	_mat.set_shader_parameter("biome_latitude_ranges", planet.biome_latitude_ranges)
	_mat.set_shader_parameter("max_heights", planet.max_heights)
	_mat.set_shader_parameter("biome_texture_indices", planet.biome_texture_indices)
	_mat.set_shader_parameter("biome_transition_smoothness", planet.biome_transition_smoothness)

	# transition_smoothness se lee del material del terreno para que el corte por altura caiga
	# exactamente donde cae allí.
	var vt_mat := planet.voxel_terrain.material as ShaderMaterial
	if vt_mat != null:
		var v = vt_mat.get_shader_parameter("transition_smoothness")
		if v != null:
			_mat.set_shader_parameter("transition_smoothness", float(v))

	_mat.set_shader_parameter("has_surface_map", true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _center_node == null or _mat == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	# Transform INTERPOLADO de la cámara: es el que se usará al renderizar (y el que verá el shader
	# en INV_VIEW_MATRIX), no el de física que devuelve global_position. Con physics_interpolation
	# activado difieren en un tick de movimiento, que a velocidad alta descuadra lienzo y esfera.
	var cam_xform := cam.get_global_transform_interpolated()
	var cam_pos := cam_xform.origin
	var to_planet := _center_node.global_position - cam_pos
	var dist := to_planet.length()
	# Dentro del planeta (o encima): solo terreno real.
	if dist <= planet_radius * 1.001:
		_set_visible_state(0.0)
		return

	var band_near := planet_radius * hide_factor
	var band_far := maxf(planet_radius * show_factor, band_near + 0.001)
	var fade := clampf(inverse_lerp(band_near, band_far, dist), 0.0, 1.0)
	_set_visible_state(fade)
	if fade <= 0.0:
		return

	# Proxy: si el planeta cabe dentro del far plane se usa su posición real (profundidad
	# exacta); si no, se ancla más cerca. clamp es monótono, así que el orden relativo entre
	# cuerpos se conserva y siguen tapándose bien entre ellos.
	var proxy_dist := minf(dist, maxf(cam.far * proxy_far_ratio, cam.near * 10.0))
	var k := proxy_dist / dist
	var dir := to_planet / dist
	var virtual_center := cam_pos + dir * proxy_dist
	var virtual_radius := planet_radius * k

	# El quad se ancla al polo cercano de la esfera, no a su centro: la profundidad que escribe
	# es entonces la del punto más cercano de la superficie, que es lo que espera el compute de
	# la atmósfera para cortar su march. Anclado al centro, el march empezaba DENTRO del planeta
	# (densidad máxima) y quemaba el disco a blanco.
	var plane_dist := maxf(proxy_dist - virtual_radius, cam.near * 2.0)

	# La silueta subtiende asin(R/d) desde la cámara: en un plano perpendicular a 'dir' a
	# distancia L, el cono de silueta mide L*tan(theta) (+6% de margen).
	var half_size := plane_dist * tan(asin(clampf(planet_radius / dist, 0.0, 0.999))) * 1.06

	global_transform = Transform3D(
		_billboard_basis(dir, cam_xform, half_size * 2.0), cam_pos + dir * plane_dist)

	_mat.set_shader_parameter("sphere_center", virtual_center)
	_mat.set_shader_parameter("sphere_radius", virtual_radius)
	_mat.set_shader_parameter("light_direction", _sun_direction())
	_mat.set_shader_parameter("fade", fade)
	_push_appearance()


## Base ortonormal del quad: su +Z mira a la cámara y el roll sigue al de la cámara.
func _billboard_basis(dir: Vector3, cam_xform: Transform3D, size: float) -> Basis:
	var z_axis := -dir
	var up_ref := cam_xform.basis.y
	var x_axis := up_ref.cross(z_axis)
	if x_axis.length_squared() < 0.0001:
		x_axis = cam_xform.basis.z.cross(z_axis)
	x_axis = x_axis.normalized()
	var y_axis := z_axis.cross(x_axis)
	return Basis(x_axis * size, y_axis * size, z_axis)


## Dirección HACIA el sol. El sun_controller actualiza 'sun_dir' del loader cada frame.
func _sun_direction() -> Vector3:
	if _sun_source != null:
		var d = _sun_source.get("sun_dir")
		if d is Vector3 and d.length_squared() > 0.0:
			return d.normalized()
	return Vector3.UP


## Aplica el estado: el impostor aparece con fade > 0 y el cuerpo real se apaga a fade pleno.
func _set_visible_state(fade: float) -> void:
	visible = fade > 0.0
	var body_on := fade < 1.0
	if body_on == _body_visible:
		return
	_body_visible = body_on
	for node in _body_nodes:
		if is_instance_valid(node):
			node.visible = body_on


func _push_appearance() -> void:
	if _mat == null:
		return
	for param in APPEARANCE_PARAMS:
		_mat.set_shader_parameter(param, get(param))

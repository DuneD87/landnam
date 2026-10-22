class_name IconStudio
extends RefCounted

## Luz de estudio común de los iconos de Saga: cielo y ambiente fríos, una luz principal cálida
## arriba a la izquierda, un relleno frío a la derecha y un contraluz, con tonemap fílmico y fondo
## transparente. La usan los iconos horneados de los objetos (tools/ui/item_icon_renderer.gd), los
## de los bloques (BlockIconGenerator, en partida) y las miniaturas de los blueprints, para que todo
## lo que sale en la interfaz se vea con la misma luz.

## Luces: posición (miran al origen), color y energía. La segunda es el relleno.
const LIGHTS := [
	[Vector3(-3, 4, 5), Color("ffebce"), 1.8],
	[Vector3(4, 1, 3), Color("b8d3f3"), 0.9],
	[Vector3(1, 3, -4), Color("eed9b7"), 1.2],
]

## Exposición y relleno de los bloques y las construcciones: superficies grandes y claras (la piedra)
## se queman con la luz de los objetos, y con menos relleno las tres caras de un bloque se distinguen.
const BLOCK_EXPOSURE := 0.7
const BLOCK_FILL := 0.45


## Viewport de render de iconos: cuadrado, fondo transparente, mundo propio y MSAA.
static func make_viewport(side: int) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(side, side)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	return viewport


## Monta en [stage] el entorno y las luces. No hace falta que [stage] esté ya en el árbol.
## [exposure] escala todas las luces y el ambiente; [fill], además, la de relleno. Apaga la
## interpolación de física en el escenario: el proyecto la tiene puesta, y un modelo que se gira de
## golpe entre dos iconos saldría capturado a medio girar.
static func light(stage: Node3D, exposure: float = 1.0, fill: float = 1.0) -> void:
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c5cfda")
	env.ambient_light_energy = 0.5 * exposure
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.sky = Sky.new()
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color("667c95")
	sky.sky_horizon_color = Color("d6d0c0")
	sky.ground_bottom_color = Color("272c35")
	sky.ground_horizon_color = Color("a7a095")
	env.sky.sky_material = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	stage.add_child(environment)
	for i in LIGHTS.size():
		var entry: Array = LIGHTS[i]
		var light := DirectionalLight3D.new()
		var at: Vector3 = entry[0]
		light.transform = Transform3D(Basis.looking_at(-at), at)
		light.light_color = entry[1]
		light.light_energy = entry[2] * exposure * (fill if i == 1 else 1.0)
		stage.add_child(light)


## Cámara ortográfica en +Z mirando al origen, que abarca [extent] metros de lado.
static func make_camera(extent: float) -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = extent
	camera.position = Vector3(0, 0, maxf(4.0, extent * 4.0))
	camera.far = maxf(100.0, extent * 10.0)
	return camera


## Giro de vista de los iconos de bloques y blueprints: [yaw] grados alrededor de Y y la cara de
## arriba inclinada [pitch] grados hacia la cámara.
static func view_basis(yaw: float, pitch: float = 30.0) -> Basis:
	return Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Basis(Vector3.UP, deg_to_rad(yaw))


## Caja (en el espacio de la cámara) que ocupa [box] visto con [view].
static func projected_bounds(box: AABB, view: Basis) -> AABB:
	var out := AABB(view * box.position, Vector3.ZERO)
	for i in 8:
		out = out.expand(view * box.get_endpoint(i))
	return out

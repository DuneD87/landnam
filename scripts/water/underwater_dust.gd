class_name UnderwaterDust extends MultiMeshInstance3D

## Polvo en suspensión alrededor de la cámara sumergida. No es un sistema de partículas:
## las motas están clavadas a una retícula del mundo y no se mueven ni nacen ni mueren.
## Al desplazarte cambian las celdas visibles, y el paralaje resultante es lo que da
## profundidad al agua abierta. Todo el trabajo lo hace el shader; aquí solo se decide
## si hay agua delante de la cámara y con cuánta densidad.

## Lado de la celda, en metros.
@export var cell_size: float = 0.5
## Celdas por eje. El alcance del polvo es la mitad de este número por celda.
@export var grid_side: int = 20
## Fracción de celdas con mota a plena densidad.
@export_range(0.0, 1.0, 0.05) var occupancy: float = 0.65
## Densidad relativa justo bajo la superficie, donde el agua está más limpia.
@export_range(0.0, 1.0, 0.05) var surface_occupancy: float = 0.25
## Profundidad a la que el agua alcanza su carga máxima de materia.
@export var full_density_depth: float = 25.0

## Margen de claridad de las motas respecto al agua que las rodea.
@export var shade_range := Vector2(0.55, 2.2)

var camera: Camera3D
var water_material: ShaderMaterial
## Ajustes de niebla, para teñir el polvo con el color del agua a esa profundidad.
var optics: Underwater
var _material: ShaderMaterial


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/liquid/underwater_dust.gdshader")
	_material.set_shader_parameter(&"cell_size", cell_size)
	_material.set_shader_parameter(&"grid_side", grid_side)
	_material.set_shader_parameter(&"shade_range", shade_range)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = grid_side * grid_side * grid_side
	# El shader coloca cada mota por su índice; las transformadas de instancia no se usan.
	for index in multimesh.instance_count:
		multimesh.set_instance_transform(index, Transform3D.IDENTITY)
	var reach := grid_side * cell_size
	custom_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * reach * 2.0)
	visible = false


func _process(_delta: float) -> void:
	var start := Time.get_ticks_usec()
	_process_step()
	DebugStats.report_cost(&"agua:polvo", Time.get_ticks_usec() - start)


func _process_step() -> void:
	var view := camera if camera != null else get_viewport().get_camera_3d()
	if view == null or water_material == null:
		visible = false
		return
	var point: Variant = water_material.get_shader_parameter(&"waterline_point")
	var normal: Variant = water_material.get_shader_parameter(&"waterline_normal")
	if not (point is Vector3) or not (normal is Vector3) or (normal as Vector3).is_zero_approx():
		visible = false
		return
	var up: Vector3 = (normal as Vector3).normalized()
	var depth: float = (point as Vector3 - view.global_position).dot(up)
	if depth <= 0.0 or _in_dry_interior(view.global_position):
		visible = false
		return
	# La retícula es absoluta, pero el nodo tiene que seguir a la cámara o el culling
	# descartaría el dibujado en cuanto el jugador se alejara del origen.
	global_position = view.global_position
	_material.set_shader_parameter(&"waterline_point", point)
	_material.set_shader_parameter(&"waterline_normal", up)
	_material.set_shader_parameter(&"water_color", _water_color(depth))
	# Cerca de la superficie el agua está más limpia; en el fondo carga más materia.
	_material.set_shader_parameter(&"occupancy", lerpf(surface_occupancy, occupancy,
			clampf(depth / maxf(full_density_depth, 0.01), 0.0, 1.0)))
	visible = true


## Color del agua a esta profundidad, con la misma mezcla que la niebla (uw_depth_color).
## Así el polvo acompaña al agua al oscurecerse en profundidad en vez de quedarse blanco.
func _water_color(depth: float) -> Color:
	if optics == null:
		return Color(0.14, 0.34, 0.38)
	var deep := maxf(optics.deep_transition_depth, 0.01)
	var abyss := maxf(optics.abyss_transition_depth, deep + 0.01)
	if depth < deep:
		return optics.fog_color.lerp(optics.deep_fog_color, clampf(depth / deep, 0.0, 1.0))
	return optics.deep_fog_color.lerp(optics.abyss_fog_color, clampf((depth - deep) / (abyss - deep), 0.0, 1.0))


## Un compartimento seco de un barco no tiene agua, y el compositor ya lo excluye.
func _in_dry_interior(world_point: Vector3) -> bool:
	for node in DynamicGridBody.bodies_in_play(get_tree()):
		var body := node as DynamicGridBody
		if body != null and is_instance_valid(body) and body.is_point_in_dry_interior(world_point):
			return true
	return false

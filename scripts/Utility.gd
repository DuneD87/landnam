class_name DebugUtils
extends RefCounted


static func draw_debug_line(start_pos: Vector3, end_pos: Vector3, color: Color, duration: float = 1.0):
	var scene_tree = Engine.get_main_loop() as SceneTree
	if not scene_tree or scene_tree.current_scene:
		return

	var debug_line = MeshInstance3D.new()

	scene_tree.current_scene.add_child(debug_line)
	
	var immediate_mesh = ImmediateMesh.new()
	debug_line.mesh = immediate_mesh
	
	var material = ORMMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	debug_line.material_override = material
	
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(start_pos)
	immediate_mesh.surface_add_vertex(end_pos)
	immediate_mesh.surface_end()
	
	var timer = Timer.new()
	timer.wait_time = duration
	timer.one_shot = true
	timer.timeout.connect(func(): debug_line.queue_free(); timer.queue_free())
	scene_tree.current_scene.add_child(timer)
	timer.start()

static func draw_debug_point(position: Vector3, color: Color, size: float = 0.1, duration: float = 1.0):
	var scene_tree = Engine.get_main_loop() as SceneTree
	if not scene_tree:
		return
	
	var debug_point = MeshInstance3D.new()
	scene_tree.current_scene.add_child(debug_point)
	
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = size
	sphere_mesh.height = size * 2
	debug_point.mesh = sphere_mesh
	debug_point.global_position = position
	
	var material = ORMMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	debug_point.material_override = material
	
	var timer = Timer.new()
	timer.wait_time = duration
	timer.one_shot = true
	timer.timeout.connect(func(): debug_point.queue_free(); timer.queue_free())
	scene_tree.current_scene.add_child(timer)
	timer.start()

static func draw_debug_cross(position: Vector3, color: Color, size: float = 0.5, duration: float = 1.0):
	var half_size = size * 0.5
	draw_debug_line(position + Vector3(-half_size, 0, 0), position + Vector3(half_size, 0, 0), color, duration)
	draw_debug_line(position + Vector3(0, -half_size, 0), position + Vector3(0, half_size, 0), color, duration)
	draw_debug_line(position + Vector3(0, 0, -half_size), position + Vector3(0, 0, half_size), color, duration)

static func draw_debug_cube(center: Vector3, size: Vector3, color: Color, duration: float = 1.0):
	var half_size = size * 0.5
	var corners = [
		center + Vector3(-half_size.x, -half_size.y, -half_size.z),
		center + Vector3( half_size.x, -half_size.y, -half_size.z),
		center + Vector3( half_size.x,  half_size.y, -half_size.z),
		center + Vector3(-half_size.x,  half_size.y, -half_size.z),
		center + Vector3(-half_size.x, -half_size.y,  half_size.z),
		center + Vector3( half_size.x, -half_size.y,  half_size.z),
		center + Vector3( half_size.x,  half_size.y,  half_size.z),
		center + Vector3(-half_size.x,  half_size.y,  half_size.z)
	]
	
	var edges = [
		[0,1], [1,2], [2,3], [3,0],
		[4,5], [5,6], [6,7], [7,4],
		[0,4], [1,5], [2,6], [3,7]
	]
	
	for edge in edges:
		draw_debug_line(corners[edge[0]], corners[edge[1]], color, duration)

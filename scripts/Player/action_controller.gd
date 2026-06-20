extends Node
class_name ActionController
const Config = preload("res://scripts/config.gd")

signal voxel_mined(item_id: StringName, amount: int)

@export var timer : Timer
@export var show_raycast_debug: bool = false

var rand_num_gen: RandomNumberGenerator = RandomNumberGenerator.new()
var attacking_nodes: Dictionary
var is_attacking = false
var attack_raycast: RayCast3D
var is_voxel: bool
var current_voxel: VoxelLodTerrain
var current_origin: Vector3
var current_direction: Vector3
var current_target_id: int
var current_target_node: VoxelInstancerRigidBody

func _ready() -> void:
	timer = Timer.new()
	timer.connect("timeout", on_timeout)
	add_child(timer)
	attack_raycast = RayCast3D.new()
	add_child(attack_raycast)
	attack_raycast.enabled = false  # Solo se habilita durante el ataque

func dig_hole(radius: float, distance: float):
	var voxel_tool: VoxelTool = current_voxel.get_voxel_tool()
	var result = voxel_tool.raycast(current_origin, current_direction, distance)

	if result:
		var hit_position = result.previous_position
		var center = Vector3(hit_position.x, hit_position.y, hit_position.z)
		voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
		voxel_tool.mode = VoxelTool.MODE_REMOVE
		voxel_tool.value = 0
		voxel_tool.do_sphere(center, radius)

		# Leemos el ore DESPUÉS de excavar. Un bloque generado-no-editado no expone los canales
		# INDICES/WEIGHTS a get_voxel (devuelve los defaults -> el 1er golpe siempre saldría
		# stone). El do_sphere edita el bloque (solo el canal SDF) y lo hace residente con todos
		# los canales, así que INDICES/WEIGHTS ya devuelven el ore generado de verdad. El SDF
		# editado no afecta a esos canales, así que seguimos leyendo el ore que había.
		var type_id := _read_best_ore_along_ray(voxel_tool, result.position, current_direction, 2)
		var drop := _get_ore_drop(type_id)

		var amount := rand_num_gen.randi_range(drop.min_count, drop.max_count)
		voxel_mined.emit(drop.item_id, amount)

# Recorre desde 'start' hacia dentro del rayo (dir) 'steps' voxels y devuelve el type_id del
# ore dominante (mayor peso) encontrado. Cubre la piel de terreno base sobre el depósito.
func _read_best_ore_along_ray(voxel_tool: VoxelTool, start: Vector3i, dir: Vector3, steps: int) -> int:
	var best_id := 0
	var best_w := 0.15  # mínimo para contar como ore; el slot base (índice 0) nunca cuenta
	for i in range(steps + 1):
		var p := start + Vector3i((dir * float(i)).round())
		voxel_tool.channel = VoxelBuffer.CHANNEL_INDICES
		var indices := VoxelTool.u16_indices_to_vec4i(voxel_tool.get_voxel(p))
		voxel_tool.channel = VoxelBuffer.CHANNEL_WEIGHTS
		var weights := VoxelTool.u16_weights_to_color(voxel_tool.get_voxel(p))
		# Un voxel normal trae INDICES=(0,1,2,3) con peso solo en el slot 0 (índice 0 = base).
		# Es ore solo si un slot con índice>0 tiene peso suficiente.
		var idx := [indices.x, indices.y, indices.z, indices.w]
		var w := [weights.r, weights.g, weights.b, weights.a]
		for s in 4:
			if idx[s] > 0 and w[s] > best_w:
				best_w = w[s]
				best_id = idx[s]
	return best_id

func _get_ore_drop(type_id: int) -> Dictionary:
	var fallback := {"item_id": &"stone_01", "min_count": 1, "max_count": 2}
	if type_id == 0:
		return fallback
	# La tabla de drops la publica Planet.setup_voxel_generator() como meta del terreno
	# (antes vivía en OreVoxelGenerator, ahora la generación está en el VoxelGraph).
	var drops: Dictionary = current_voxel.get_meta("ore_drops", {})
	return drops.get(type_id, fallback)
		
func on_timeout():
	if is_attacking:
		if is_voxel:
			dig_hole(1.0, 5.0)
		if !Input.is_action_pressed("attack_1"):
			is_attacking = false
			timer.stop()
		else:
			if !attacking_nodes.has(current_target_id):
				is_attacking = false
				timer.stop()
				return
				
			attacking_nodes[current_target_id].take_damage(rand_num_gen.randf_range(50, 100))
			print(attacking_nodes[current_target_id].health)
			if attacking_nodes[current_target_id].health <= 0:
				current_target_node.queue_free_and_notify_instancer()
				attacking_nodes.erase(current_target_node)
				current_target_id = -1
				timer.stop()
				is_attacking = false
			else:
				timer.start(1.7)
func perform_raycast(origin: Vector3, rotation: Vector3, show_debug: bool) -> Dictionary:
	var ray_origin = origin
	
	attack_raycast.global_position = ray_origin
	attack_raycast.target_position = Vector3(0, 0, -1000)
	attack_raycast.global_rotation = rotation
	attack_raycast.enabled = true
	attack_raycast.force_raycast_update()
	
	var out_dictionary = {
		"has_hit": false,
		"target_node": null,
		"hit_pos": Vector3.ZERO,
		"hit_distance": 0.0
	}
	
	if attack_raycast.is_colliding():
		var hit_point = attack_raycast.get_collision_point()
		var target_node = attack_raycast.get_collider() as Node3D
		var hit_distance = hit_point.distance_to(origin)
		out_dictionary["has_hit"] = true
		out_dictionary["target_node"] = target_node
		out_dictionary["hit_pos"] = hit_point
		out_dictionary["hit_distance"] = hit_distance
		if show_raycast_debug:
			DebugUtils.draw_debug_line(ray_origin, hit_point, Color.GREEN, 2.0)
			DebugUtils.draw_debug_point(hit_point, Color.YELLOW, 0.2, 2.0)
		
	return out_dictionary
	

func handle_pickup(camera: Camera3D, origin: Vector3) -> ItemData:
	var forward = -camera.global_transform.basis.z
	var up = camera.global_transform.basis.y
	var right = camera.global_transform.basis.x
	
	# Primero intentamos el raycast central (prioridad)
	var raycast_result = perform_raycast(origin, camera.global_rotation, true)
	var target_node = raycast_result["target_node"]
	var hit_distance = raycast_result["hit_distance"]
	
	# Si no hay hit central, probamos el cono
	if target_node == null:
		target_node = cone_raycast(origin, forward, up, right, camera)
		if target_node:
			hit_distance = origin.distance_to(target_node.global_position)
	
	if target_node == null:
		return null
	
	var data: ItemData = null
	if target_node is ItemPhysics:
		data = target_node.item_data
		target_node.queue_free()
	return data


func cone_raycast(origin: Vector3, forward: Vector3, up: Vector3, right: Vector3, camera: Camera3D) -> Node:
	var cone_angle := deg_to_rad(40)
	var ray_length := 10.0
	var rings := 5
	var rays_per_ring := 20
	
	var space_state = camera.get_world_3d().direct_space_state
	var closest_node: Node = null
	var closest_dist := INF
	
	for ring in range(1, rings + 1):
		var ring_angle = cone_angle * (float(ring) / rings)
		
		for i in range(rays_per_ring):
			var rotation_angle = TAU * i / rays_per_ring
			
			var offset = (right * cos(rotation_angle) + up * sin(rotation_angle)) * sin(ring_angle)
			var direction = (forward * cos(ring_angle) + offset).normalized()
			
			var query = PhysicsRayQueryParameters3D.create(origin, origin + direction * ray_length)
			var result = space_state.intersect_ray(query)
			
			if result and result.collider is ItemPhysics:
				var dist = origin.distance_to(result.position)
				if dist < closest_dist:
					closest_dist = dist
					closest_node = result.collider
	
	return closest_node
	
func handle_attack(camera: Camera3D, origin: Vector3, planet: Planet, destroyed_callback: Callable) -> Node3D:
	if is_attacking:
		return
	var raycast_result = perform_raycast(origin, camera.global_rotation, true)
	var target_node = raycast_result["target_node"]
	if target_node == null:
		return
	var hit_distance = raycast_result["hit_distance"]
	if target_node is VoxelInstancerRigidBody && hit_distance < 3.0:
		var instance_id = target_node.get_instance_id()
		current_target_id = instance_id
		current_target_node = target_node
		if !attacking_nodes.has(instance_id):
			var item_id = target_node.get_library_item_id()
			var scene = planet.voxel_instancer.library.get_item(item_id).scene.instantiate()
			var registered = planet.planet_item_scenes.get(item_id)
			if registered != null:
				scene.health = registered.health
			if not scene.destroyed.is_connected(destroyed_callback):
				scene.destroyed.connect(destroyed_callback)
			attacking_nodes[instance_id] = scene
			
	is_voxel = target_node && target_node is VoxelLodTerrain
	if is_voxel:
		current_voxel = target_node as VoxelLodTerrain
		current_origin = origin
		current_direction = -camera.global_transform.basis.z
		
	is_attacking = true
	timer.start(1.7)

	return target_node

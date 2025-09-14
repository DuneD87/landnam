extends Node
class_name ActionController
const Config = preload("res://scripts/config.gd")

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
		voxel_tool.mode = VoxelTool.MODE_REMOVE 
		voxel_tool.value = 0
		voxel_tool.do_sphere(center, radius)
		
func on_timeout():
	if is_attacking:
		if is_voxel:
			dig_hole(2.0, 100.0)
		if !Input.is_action_pressed("attack_1"):
			is_attacking = false
			timer.stop()
		else:
			attacking_nodes[current_target_id].health -= rand_num_gen.randf_range(10, 50)
			if attacking_nodes[current_target_id].health <= 0:
				current_target_node.queue_free_and_notify_instancer()
				attacking_nodes.erase(current_target_node)
				current_target_id = -1
				timer.stop()
				is_attacking = false
			else:
				timer.start(1.7)
	
	
func handle_attack(camera: Camera3D, origin: Vector3, planet: Planet) -> Node3D:
	if is_attacking:
		return
		
	var ray_origin = origin
	
	attack_raycast.global_position = ray_origin
	attack_raycast.target_position = Vector3(0, 0, -1000)
	var camera_forward = -camera.global_transform.basis.z
	attack_raycast.global_rotation = camera.global_rotation
	attack_raycast.enabled = true
	attack_raycast.force_raycast_update()
	
	var target_node: Node3D = null
	
	if attack_raycast.is_colliding():
		var hit_point = attack_raycast.get_collision_point()
		target_node = attack_raycast.get_collider() as Node3D
		
		if show_raycast_debug:
			DebugUtils.draw_debug_line(ray_origin, hit_point, Color.GREEN, 2.0)
			DebugUtils.draw_debug_point(hit_point, Color.YELLOW, 0.2, 2.0)
		
		var hit_distance = hit_point.distance_to(origin)
	
		if target_node is VoxelInstancerRigidBody && hit_distance < 3.0:
			var instance_id = target_node.get_instance_id()
			current_target_id = instance_id
			current_target_node = target_node
			if !attacking_nodes.has(instance_id):
				var item_id = target_node.get_library_item_id()
				var scene = planet.voxel_instancer.library.get_item(item_id).scene.instantiate()
				scene.health = planet.planet_item_scenes[item_id].health
				attacking_nodes[instance_id] = scene
			
	is_voxel = target_node && target_node is VoxelLodTerrain
	if is_voxel:
		current_voxel = target_node as VoxelLodTerrain
		current_origin = origin
		current_direction = camera_forward
		
	is_attacking = true
	timer.start(1.7)

	return target_node

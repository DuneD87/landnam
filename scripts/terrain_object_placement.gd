@tool
extends VoxelInstancer
var planet : Node3D
var item_transparent_materials : Array[Dictionary]

@export var wind_direction : Vector3

func _set_mesh_items(data: Array[Dictionary]) -> void:
	library.clear()
	var i = 0
	for item in data:
		var scene = load(item.scene_path)
		item.mesh_item.scene = scene
		if library.get_item(i) == null:
			library.add_item(i, item.mesh_item)
		i+=1

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	planet = get_parent().get_parent()
	print(planet.wind_direction)

	for veg in planet.vegetation:
		var item : VoxelInstanceLibraryMultiMeshItem = veg.mesh_item
		var scene_mesh : MeshInstance3D = item.scene.instantiate().get_child(0)
		var surface_count = scene_mesh.mesh.get_surface_count()
		for surface_idx in surface_count:
			var shader_material = scene_mesh.mesh.surface_get_material(surface_idx)
			if shader_material is ShaderMaterial:
				item_transparent_materials.append(
					{
						"shader": shader_material as ShaderMaterial,
						"wind_speed": veg.wind_speed
					}
				)
	

func _process(delta: float) -> void:
	for mat_struct in item_transparent_materials:
		var mat = mat_struct.shader as ShaderMaterial
		mat.set_shader_parameter("light_direction", planet.sun_dir)
		mat.set_shader_parameter("planet_position", planet.position)
		mat.set_shader_parameter("wind_direction", planet.wind_direction)
		mat.set_shader_parameter("wind_speed", mat_struct.wind_speed)

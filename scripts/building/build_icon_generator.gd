class_name BlockIconGenerator
extends Node

## Genera iconos de bloques renderizando su mesh en un SubViewport con cámara isométrica.

const ICON_SIZE := 256
const CAMERA_FOV := 35.0
const CAMERA_DISTANCE := 2.8
## Alpha mínimo con el que se pinta un material traslúcido en su icono.
const MIN_ICON_ALPHA := 0.7

# Ángulos de la cámara isométrica (grados).
const PITCH := -30.0
const YAW := 45.0

var _viewport: SubViewport
var _camera: Camera3D
var _light: DirectionalLight3D
var _mesh_instance: MeshInstance3D
var _is_ready := false


func _ready() -> void:
	_setup_viewport()
	_is_ready = true


func _setup_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(ICON_SIZE, ICON_SIZE)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.own_world_3d = true
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.fov = CAMERA_FOV
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_viewport.add_child(_camera)
	_position_camera()

	_light = DirectionalLight3D.new()
	_light.rotation_degrees = Vector3(-45, 30, 0)
	_light.light_energy = 1.2
	_light.shadow_enabled = false
	_viewport.add_child(_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20, -150, 0)
	fill_light.light_energy = 0.4
	fill_light.shadow_enabled = false
	_viewport.add_child(fill_light)

	_mesh_instance = MeshInstance3D.new()
	_viewport.add_child(_mesh_instance)


func _position_camera() -> void:
	_camera.position = Vector3.ZERO
	_camera.rotation_degrees = Vector3(PITCH, YAW, 0.0)
	var direction := -_camera.global_transform.basis.z
	_camera.position = -direction * CAMERA_DISTANCE


## Copia del material apta para el icono. Un material muy traslúcido sobre el fondo transparente del
## viewport sale casi invisible, así que para el icono se le sube el alpha mínimo.
static func _icon_material(material: Material) -> Material:
	var base := material as BaseMaterial3D
	if not base or base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		return material
	if base.albedo_color.a >= MIN_ICON_ALPHA:
		return material
	var copy := base.duplicate() as BaseMaterial3D
	copy.albedo_color.a = MIN_ICON_ALPHA
	return copy


## Genera una icona (ImageTexture ICON_SIZE×ICON_SIZE RGBA) para un mesh con material opcional.
func generate_icon(mesh: Mesh, material: Material = null) -> ImageTexture:
	if not _is_ready:
		push_warning("[BlockIconGenerator] Not ready yet.")
		return null

	var aabb := mesh.get_aabb()
	var center := aabb.get_center()
	_mesh_instance.mesh = mesh
	_mesh_instance.position = -center

	_mesh_instance.material_override = _icon_material(material)

	var size := aabb.size.length()
	var dist := size / (2.0 * tan(deg_to_rad(CAMERA_FOV * 0.5)))
	_position_camera()
	var direction := -_camera.global_transform.basis.z
	_camera.position = -center - direction * (dist * 1.3)

	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var image := _viewport.get_texture().get_image()
	var texture := ImageTexture.create_from_image(image)

	_mesh_instance.mesh = null
	_mesh_instance.material_override = null
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	return texture

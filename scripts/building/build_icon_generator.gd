class_name BlockIconGenerator
extends Node

## Genera iconos de bloques en partida: renderiza su mesh en un SubViewport con la luz de estudio de
## Saga (IconStudio), la misma de los iconos horneados de los objetos, en isométrica ortográfica y
## con MSAA. La escala es la de la celda entera y no la de la malla, así que todos los bloques salen
## a la misma: una rampa ocupa media celda y un panel es una lámina, como en el mundo.

const ICON_SIZE := 256
## Margen alrededor de la celda en el encuadre (fracción del lado).
const MARGIN := 0.06
## Inclinación de la cara de arriba hacia la cámara (grados).
const PITCH := 30.0
## Alpha mínimo con el que se pinta un material traslúcido en su icono.
const MIN_ICON_ALPHA := 0.7
## La celda de un bloque base (BlockMeshGenerator): origen en el centro de la base.
const CELL := AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)

var _viewport: SubViewport
var _camera: Camera3D
var _holder: Node3D
var _mesh_instance: MeshInstance3D
var _is_ready := false
var _busy := false


func _ready() -> void:
	_setup_viewport()
	_is_ready = true


func _setup_viewport() -> void:
	_viewport = IconStudio.make_viewport(ICON_SIZE)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	var stage := Node3D.new()
	_viewport.add_child(stage)
	IconStudio.light(stage, IconStudio.BLOCK_EXPOSURE, IconStudio.BLOCK_FILL)
	_holder = Node3D.new()
	stage.add_child(_holder)
	_mesh_instance = MeshInstance3D.new()
	_holder.add_child(_mesh_instance)
	_camera = IconStudio.make_camera(1.0)
	stage.add_child(_camera)
	_camera.current = true


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


## Genera un icono (ImageTexture ICON_SIZE×ICON_SIZE RGBA) para un mesh con material opcional,
## girado [yaw] grados (BlockData.icon_yaw). Las mallas de bloque base se encuadran por su celda;
## cualquier otra, por su propia caja.
func generate_icon(mesh: Mesh, material: Material = null, yaw: float = 45.0) -> ImageTexture:
	if not _is_ready:
		push_warning("[BlockIconGenerator] Not ready yet.")
		return null
	# Antes de tomar el turno: un mesh nulo aborta la función a medias y deja _busy puesto, con lo
	# que todos los iconos que vengan detrás se quedan esperando un turno que no llega nunca.
	if not mesh:
		push_warning("[BlockIconGenerator] Mesh nulo, no hay icono que generar.")
		return null

	# El viewport y el MeshInstance son únicos, y entre await y await no hay nada que los proteja:
	# dos generaciones simultáneas se pisan el mesh y cada una captura el render de la otra.
	while _busy:
		await get_tree().process_frame
	_busy = true

	# La escala sale de la celda (todos los bloques a la misma), pero la malla va centrada: un panel
	# pegado al fondo de su celda saldría arrinconado.
	var box := mesh.get_aabb()
	var frame := CELL if CELL.grow(0.001).encloses(box) else box
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _icon_material(material)
	_mesh_instance.position = -box.get_center()
	_holder.basis = IconStudio.view_basis(yaw, PITCH)
	var view := IconStudio.projected_bounds(AABB(-frame.size * 0.5, frame.size), _holder.basis)
	_camera.size = maxf(view.size.x, view.size.y) * (1.0 + 2.0 * MARGIN)
	_camera.position = Vector3(view.get_center().x, view.get_center().y, 4.0)

	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var image := _viewport.get_texture().get_image()
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)

	_mesh_instance.mesh = null
	_mesh_instance.material_override = null
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_busy = false

	return texture

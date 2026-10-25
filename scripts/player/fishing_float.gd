class_name FishingFloat
extends Node3D

## Vive bajo el terreno: marcador, boya, anzuelo sumergido y sedal siguen el origen flotante.
const HOOK_DEPTH := 1.2
var hook: Node3D
var _ring: MeshInstance3D
var _bobber: MeshInstance3D
var _line: MeshInstance3D
var _mesh := ImmediateMesh.new()
var _material: StandardMaterial3D
var _alert: Label3D
var _time := 0.0


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(0.3, 0.95, 0.8)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.40
	torus.outer_radius = 0.46
	_ring.mesh = torus
	_ring.material_override = _material
	add_child(_ring)
	_bobber = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.085
	sphere.height = 0.23
	_bobber.mesh = sphere
	_bobber.material_override = _material
	add_child(_bobber)
	hook = Node3D.new()
	hook.position.y = -HOOK_DEPTH
	add_child(hook)
	_line = MeshInstance3D.new()
	_line.mesh = _mesh
	var cord := StandardMaterial3D.new()
	cord.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cord.albedo_color = Color(0.85, 0.88, 0.75)
	_line.material_override = cord
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)
	_alert = Label3D.new()
	_alert.text = "!"
	_alert.font_size = 96
	_alert.pixel_size = 0.01
	_alert.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert.modulate = Color(1.0, 0.6, 0.12)
	_alert.position.y = 0.7
	add_child(_alert)


func present(delta: float, aiming: bool, valid: bool, nibbling: bool, hooked: bool, flying := false) -> void:
	_time += delta
	_material.albedo_color = Color(1, 0.55, 0.1) if hooked else (
		Color(0.3, 0.95, 0.8) if valid else Color(1.0, 0.25, 0.2))
	_ring.scale = Vector3.ONE * (1.0 + sin(_time * (12.0 if hooked else 4.0)) * 0.12)
	_ring.position.y = 0.06
	_ring.visible = not flying
	_bobber.visible = not aiming
	_bobber.position.y = sin(_time * 17.0) * 0.12 - 0.08 if nibbling or hooked else 0.05
	_alert.visible = hooked
	_line.visible = not aiming


func draw_line(tip: Vector3, flying: bool) -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var start := to_local(tip)
	for i in 17:
		var t := float(i) / 16.0
		var point := start.lerp(_bobber.position, t)
		point.y -= sin(t * PI) * (0.15 if flying else 0.5)
		_mesh.surface_add_vertex(point)
	_mesh.surface_end()

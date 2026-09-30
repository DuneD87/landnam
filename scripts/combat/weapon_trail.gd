class_name WeaponTrail
extends MeshInstance3D

## Estela de la hoja mientras hiere: una cinta entre la base y la punta de las últimas poses que
## se desvanece en [lifetime] segundos. Solo se ve durante la ventana activa del golpe, así
## que además de lucir dice cuándo y por dónde corta.

## Segundos que dura cada tramo.
@export var lifetime: float = 0.16
@export var color: Color = Color(1.0, 0.97, 0.9, 0.34)

var _samples: Array = []
var _mesh := ImmediateMesh.new()
var _clock: float = 0.0


func _ready() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	material_override = mat
	global_transform = Transform3D.IDENTITY


## Añade la pose actual de la hoja (mundo). Con [emit] a false no se añade nada y solo se apaga
## lo que queda.
func push(base: Vector3, tip: Vector3, emit: bool, delta: float) -> void:
	_clock += delta
	if emit:
		_samples.append([base, tip, _clock])
	while not _samples.is_empty() and _clock - float(_samples[0][2]) > lifetime:
		_samples.pop_front()
	_rebuild()


func clear() -> void:
	_samples.clear()
	_mesh.clear_surfaces()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _samples.size() < 2:
		return
	# La malla va en mundo: el nodo se queda en el origen.
	global_transform = Transform3D.IDENTITY
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for s in _samples:
		var age := clampf((_clock - float(s[2])) / lifetime, 0.0, 1.0)
		var fade := (1.0 - age) * (1.0 - age)
		# Más intensa hacia la punta, donde la hoja corre más.
		_mesh.surface_set_color(Color(color.r, color.g, color.b, color.a * fade * 0.25))
		_mesh.surface_add_vertex(s[0])
		_mesh.surface_set_color(Color(color.r, color.g, color.b, color.a * fade))
		_mesh.surface_add_vertex(s[1])
	_mesh.surface_end()

class_name RangedWeaponVisual
extends Node3D

## Cuerda del arco o goma del tirachinas. Va de las puntas del arma al punto de tensado: en
## reposo, recta entre las puntas (arco) o colgando un poco por detrás (tirachinas); tensando, a
## la mano derecha del arquero, que la fija quien lo lleva con set_draw_point().

## Extremos de la cuerda en el espacio del arma. Vacío = se deducen del tipo (por el nombre).
@export var anchors: PackedVector3Array = PackedVector3Array()
@export var cord_radius: float = 0.0
## Tirachinas: lleva badana en el punto de tensado.
@export var has_pouch: bool = false

## 0..1 cuánto se doblan las palas del arco (forma de mezcla "drawn" de la malla).
var flex: float = 0.0:
	set(value):
		if is_equal_approx(value, flex):
			return
		flex = value
		_apply_flex()

var _segments: Array[MeshInstance3D] = []
var _is_bow := false
var _mesh: MeshInstance3D
var _pouch: MeshInstance3D
var _draw_global: Variant = null


func _ready() -> void:
	var is_sling := name.to_lower().contains("sling")
	_mesh = get_node_or_null("Mesh") as MeshInstance3D
	_is_bow = not is_sling and anchors.is_empty()
	if anchors.is_empty():
		if is_sling:
			anchors = PackedVector3Array(WeaponMeshes.SLING_PRONG_TIPS)
		else:
			anchors = PackedVector3Array([WeaponMeshes.bow_tip(true), WeaponMeshes.bow_tip(false)])
	if cord_radius <= 0.0:
		cord_radius = 0.0055 if is_sling else 0.0022
	has_pouch = has_pouch or is_sling
	var cord := CylinderMesh.new()
	cord.top_radius = cord_radius
	cord.bottom_radius = cord_radius
	cord.height = 1.0
	cord.radial_segments = 5
	cord.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.12, 0.08) if is_sling else Color(0.80, 0.74, 0.60)
	mat.roughness = 0.9
	cord.material = mat
	for i in anchors.size():
		var seg := MeshInstance3D.new()
		seg.mesh = cord
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(seg)
		_segments.append(seg)
	if has_pouch:
		var pouch_mesh := SphereMesh.new()
		pouch_mesh.radius = 0.02
		pouch_mesh.height = 0.022
		pouch_mesh.radial_segments = 8
		pouch_mesh.rings = 4
		pouch_mesh.material = mat
		_pouch = MeshInstance3D.new()
		_pouch.mesh = pouch_mesh
		add_child(_pouch)
	_update()


func _apply_flex() -> void:
	if _mesh != null and _mesh.mesh != null and _mesh.mesh.get_blend_shape_count() > 0:
		_mesh.set_blend_shape_value(0, flex)
	if _is_bow:
		anchors = PackedVector3Array([WeaponMeshes.bow_tip(true, flex), WeaponMeshes.bow_tip(false, flex)])
	_update()


## Punto de tensado en mundo, o null para dejar la cuerda en reposo.
func set_draw_point(point: Variant) -> void:
	_draw_global = point
	_update()


func _process(_delta: float) -> void:
	# La cuerda sigue al arma aunque nadie la mueva (el padre se anima).
	if _draw_global != null:
		_update()


func _rest_point() -> Vector3:
	var mid := Vector3.ZERO
	for a in anchors:
		mid += a
	mid /= maxf(anchors.size(), 1)
	if has_pouch:
		return mid + Vector3(0, -0.03, -0.05)
	return mid


func _update() -> void:
	if _segments.is_empty():
		return
	var target: Vector3 = _rest_point() if _draw_global == null else to_local(_draw_global)
	for i in _segments.size():
		_place(_segments[i], anchors[i], target)
	if _pouch:
		_pouch.position = target


func _place(seg: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var axis := b - a
	var length := axis.length()
	if length < 1e-4:
		seg.visible = false
		return
	seg.visible = true
	var y := axis / length
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	seg.transform = Transform3D(Basis(x, y * length, z), (a + b) * 0.5)

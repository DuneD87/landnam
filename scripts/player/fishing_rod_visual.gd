@tool
class_name FishingRodVisual
extends Node3D

## Caña en metros, +Y hacia la punta. La punta se dobla al picar y recoger.
const LENGTH := 2.3
var tension := 0.0
var _shaft: MeshInstance3D
var _tip: MeshInstance3D
var _wood: StandardMaterial3D
var _signal: StandardMaterial3D


func _ready() -> void:
	set_meta(&"grip_aligned", true)
	_wood = StandardMaterial3D.new()
	_wood.albedo_color = Color(0.43, 0.26, 0.10)
	_signal = StandardMaterial3D.new()
	_signal.albedo_color = Color(0.85, 0.71, 0.40)
	_signal.emission_enabled = true
	_shaft = MeshInstance3D.new()
	_shaft.mesh = ImmediateMesh.new()
	_shaft.material_override = _wood
	add_child(_shaft)
	var handle := MeshInstance3D.new()
	var grip := CylinderMesh.new()
	grip.top_radius = 0.029
	grip.bottom_radius = 0.032
	grip.height = 0.32
	handle.mesh = grip
	handle.material_override = _wood
	add_child(handle)
	_tip = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.07
	_tip.mesh = sphere
	_tip.material_override = _signal
	add_child(_tip)
	update_tension(0.0)


func tip_local() -> Vector3:
	return Vector3(0.0, LENGTH - tension * 0.18, tension * 0.6)


func tip_world() -> Vector3:
	return to_global(tip_local())


func update_tension(value: float) -> void:
	if _shaft != null and absf(tension - value) < 0.015 and _shaft.mesh is ArrayMesh:
		return
	tension = clampf(value, 0.0, 1.0)
	if _shaft == null:
		return
	var points := PackedVector3Array()
	var radii := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		points.append(Vector3(0, t * LENGTH - tension * 0.18 * t * t, tension * 0.6 * t * t))
		var radius := lerpf(0.021, 0.005, t)
		radii.append(Vector2.ONE * radius)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	ProcMesh.tube(st, points, radii, 6)
	st.generate_normals()
	_shaft.mesh = st.commit()
	_tip.position = tip_local()
	_signal.emission = Color(1.0, 0.37, 0.04) * tension * 2.0

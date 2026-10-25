@tool
extends Node3D

enum Kind { HOOK, BAIT, RAW_FISH, COOKED_FISH }
@export var kind: Kind = Kind.HOOK


func _ready() -> void:
	var visual := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	if kind in [Kind.RAW_FISH, Kind.COOKED_FISH]:
		visual.mesh = SimpleFishMesh.mesh(SimpleFishMesh.Kind.SARDINE)
		visual.scale = Vector3.ONE * 0.8
		material.albedo_color = Color(0.45, 0.66, 0.72) if kind == Kind.RAW_FISH else Color(0.55, 0.29, 0.11)
	else:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var points := PackedVector3Array()
		var radii := PackedVector2Array()
		if kind == Kind.HOOK:
			points.append(Vector3(0.04, 0.12, 0))
			radii.append(Vector2.ONE * 0.007)
			for i in 17:
				var angle := -PI * float(i) / 16.0
				points.append(Vector3(cos(angle) * 0.04, sin(angle) * 0.04, 0))
				radii.append(Vector2.ONE * lerpf(0.007, 0.002, float(i) / 16.0))
			material.albedo_color = Color(0.81, 0.76, 0.58)
		else:
			for i in 17:
				var t := float(i) / 16.0
				points.append(Vector3((t - 0.5) * 0.20, sin(t * TAU) * 0.025, 0))
				radii.append(Vector2.ONE * (0.006 + sin(t * PI) * 0.007))
			material.albedo_color = Color(0.65, 0.28, 0.25)
		ProcMesh.tube(st, points, radii, 6, Vector3.FORWARD)
		st.generate_normals()
		visual.mesh = st.commit()
	visual.material_override = material
	add_child(visual)

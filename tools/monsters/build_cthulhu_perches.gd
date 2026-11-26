extends SceneTree

## Asientos de los esbirros sobre la piel de Cthulhu (CthulhuBrood): puntos de la malla que miran hacia
## arriba (o hacia atrás, en el lomo) y que mueve casi solo un hueso, en el espacio de ese hueso, para que
## sigan al cuerpo al andar. Escribe data/monsters/cthulhu_perches.json.
##   godot --headless --path . -s res://tools/monsters/build_cthulhu_perches.gd
## Se rehace al cambiar el modelo de Cthulhu.

const OUT := "res://data/monsters/cthulhu_perches.json"
## Huesos donde se sientan, lo que tiene que mirar la piel (eje en el modelo, +Y arriba, +Z delante) y
## cuántos como mucho.
const BONES := {
	"Clavícula.L": [Vector3.UP, 2], "Clavícula.R": [Vector3.UP, 2],
	"Brazo.L": [Vector3.UP, 1], "Brazo.R": [Vector3.UP, 1],
	"Ala.Base.L": [Vector3(0, 1, -0.6), 2], "Ala.Base.R": [Vector3(0, 1, -0.6), 2],
	"Lomo": [Vector3(0, 0.6, -1), 3], "Pecho": [Vector3(0, 0.7, -1), 2],
}
## Altura mínima (m del modelo; el agua le llega por 0,72 vadeando en lo hondo).
const MIN_HEIGHT := 0.85
## Peso mínimo del hueso en el vértice, lo que tiene que mirar (coseno) y separación (m del modelo).
const MIN_WEIGHT := 0.3
const MIN_FACING := 0.45
const SPACING := 0.07


func _initialize() -> void:
	var root := (load("res://models/monsters/cthulhu/cthulhu.glb") as PackedScene).instantiate()
	var mesh_instance := root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var skel := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var skin := mesh_instance.skin
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / vertices.size()
	# Del índice de bind al hueso del esqueleto.
	var bind_bone := {}
	for b in skin.get_bind_count():
		var bone_name := skin.get_bind_name(b)
		bind_bone[b] = skel.find_bone(bone_name) if bone_name != &"" else skin.get_bind_bone(b)
	var mesh_to_model := mesh_instance.transform
	var candidates := {}
	for bone_name: String in BONES:
		candidates[bone_name] = []
	for v in vertices.size():
		var best := -1
		var best_w := 0.0
		for k in per:
			if weights[v * per + k] > best_w:
				best_w = weights[v * per + k]
				best = bones[v * per + k]
		if best_w < MIN_WEIGHT:
			continue
		var bone_index: int = bind_bone.get(best, -1)
		if bone_index < 0:
			continue
		var bone_name := String(skel.get_bone_name(bone_index))
		if not candidates.has(bone_name):
			continue
		var want: Vector3 = (BONES[bone_name][0] as Vector3).normalized()
		var normal := (mesh_to_model.basis * normals[v]).normalized()
		var facing := normal.dot(want)
		var point := mesh_to_model * vertices[v]
		if facing < MIN_FACING or point.y < MIN_HEIGHT:
			continue
		# Los que miran atrás (lomo, alas), detrás del cuerpo: no la cara interior de la barba.
		if want.z < 0.0 and point.z > 0.0:
			continue
		candidates[bone_name].append([facing, point, normal, best])
	var perches := []
	for bone_name: String in candidates:
		var list: Array = candidates[bone_name]
		list.sort_custom(func(a, b): return a[0] > b[0])
		var chosen := []
		for item in list:
			if chosen.size() >= int(BONES[bone_name][1]):
				break
			var ok := true
			for other in chosen:
				if (other[1] as Vector3).distance_to(item[1]) < SPACING:
					ok = false
					break
			if ok:
				chosen.append(item)
		for item in chosen:
			var bind: Transform3D = skin.get_bind_pose(item[3])
			var local: Vector3 = bind * (mesh_to_model.affine_inverse() * (item[1] as Vector3))
			var local_normal: Vector3 = (bind.basis * (mesh_to_model.basis.inverse() * (item[2] as Vector3))).normalized()
			perches.append({"bone": bone_name, "offset": [local.x, local.y, local.z],
				"normal": [local_normal.x, local_normal.y, local_normal.z], "model": [item[1].x, item[1].y, item[1].z],
				"model_normal": [item[2].x, item[2].y, item[2].z]})
		print("PERCH ", bone_name, " candidates=", list.size(), " chosen=", chosen.size())
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({"perches": perches}, "\t"))
	file.close()
	print("WROTE ", perches.size(), " perches")
	root.free()
	quit()

extends Node

## Las rocas del planeta (ProceduralRock): cada escena da su malla, plantada por su base, estrellada
## desde su centro (RockFracture lo supone) y con el COLOR que lee planet_rock.gdshader. Al partirla,
## los trozos conservan ese COLOR, las caras del corte salen limpias (CUT_COLOR) y cada trozo sabe
## dónde estaba dentro de la roca (meta rock_offset).
##   godot --headless --path . res://tests/world/test_procedural_rocks.tscn

const ROCKS := "res://scenes/planet/planet_items/rocks/"

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	for file in DirAccess.get_files_at(ROCKS):
		if not file.ends_with(".tscn") or file == "rock_template.tscn":
			continue
		var root: Node = (load(ROCKS + file) as PackedScene).instantiate()
		var rock := root.get_child(0) as ProceduralRock
		check(rock != null, "%s: la roca es un ProceduralRock" % file)
		if rock != null:
			_check_rock(file, rock)
		root.free()
	_check_fracture()
	print("PROCEDURAL ROCKS: %d failures" % failures)
	get_tree().quit(1 if failures else 0)


func _check_rock(file: String, rock: ProceduralRock) -> void:
	var mesh := rock.get_rock_instance().mesh
	check(mesh != null and rock.material_rock != null, "%s: malla y material" % file)
	if mesh == null:
		return
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	check(colors.size() == verts.size(), "%s: COLOR en todos los vértices" % file)
	var box := mesh.get_aabb()
	var below := -box.position.y / box.size.y
	check(absf(below - rock.sink) < 0.02, "%s: %.2f de la altura bajo el suelo (sink %.2f)" % [file, below, rock.sink])
	# Estrellada desde el centroide (de donde RockFracture saca las semillas): la normal de cada
	# vértice mira hacia fuera de él.
	var center := Vector3.ZERO
	for v in verts:
		center += v
	center /= float(verts.size())
	var inward := 0
	for i in verts.size():
		if normals[i].dot(verts[i] - center) < 0.0:
			inward += 1
	check(inward * 50 < verts.size(), "%s: %d de %d vértices miran hacia dentro" % [file, inward, verts.size()])
	var dark := 0
	for c in colors:
		if c.r < 0.3 - 1e-4 or c.r > 1.0 or not is_equal_approx(c.g, 1.0):
			dark += 1
	check(dark == 0, "%s: %d colores fuera de rango (r en [0,3, 1], g = 1)" % [file, dark])


func _check_fracture() -> void:
	var rock := ProceduralRock.new()
	rock.subdivisions = 3
	var mesh := rock.build_mesh()
	rock.free()
	var pieces := RockFracture.pieces_of(mesh, 6)
	check(pieces.size() >= 4, "La roca se parte en trozos (%d)" % pieces.size())
	var cut := 0
	var outer := 0
	for piece in pieces:
		var piece_mesh: Mesh = piece.mesh
		var offset: Vector3 = piece_mesh.get_meta(&"rock_offset", Vector3.INF)
		check(offset.is_equal_approx(piece.offset), "El trozo guarda su sitio en la roca")
		var arrays := piece_mesh.surface_get_arrays(0)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		check(colors.size() == (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "El trozo lleva COLOR")
		for c in colors:
			if c == RockFracture.CUT_COLOR:
				cut += 1
			elif c.g > 0.99:
				outer += 1
		# Un trozo de un trozo suma los dos desplazamientos.
		var sub := RockFracture.pieces_of(piece_mesh, 2)
		if not sub.is_empty():
			var sub_offset: Vector3 = (sub[0].mesh as Mesh).get_meta(&"rock_offset", Vector3.INF)
			check(sub_offset.is_equal_approx(offset + (sub[0].offset as Vector3)),
				"El trozo de un trozo sigue sabiendo dónde estaba en la roca entera")
	check(cut > 0 and outer > 0, "Hay caras de corte (%d vértices) y de fuera (%d)" % [cut, outer])
	var visual := RockFracture.mesh_instance(pieces[0].mesh)
	check((visual.get_instance_shader_parameter(&"rock_offset") as Vector3).is_equal_approx(pieces[0].offset),
		"mesh_instance pasa el sitio del trozo al shader")
	visual.free()

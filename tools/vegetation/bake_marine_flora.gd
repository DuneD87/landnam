extends SceneTree

## Horneado de la flora sumergida: praderas, laminarias, gorgonias y coral ramificado.
## Geometría procedural con color por vértice, sin texturas, como la fauna marina.
## Y local = arriba (el instanciador la alinea con la normal del terreno), planta centrada en 0.

const IDS := ["seagrass", "kelp", "sea_fan", "coral"]
## Altura nominal de cada especie, que el shader usa para pesar el vaivén.
const HEIGHTS := {"seagrass": 0.85, "kelp": 4.2, "sea_fan": 1.15, "coral": 0.95}

var surface: SurfaceTool
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/vegetation/marine")
	for id in IDS:
		rng.seed = hash(id)
		surface = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		match id:
			"seagrass": _seagrass()
			"kelp": _kelp()
			"sea_fan": _sea_fan()
			_: _coral()
		surface.generate_normals()
		surface.index()
		var mesh := surface.commit()
		# El material viaja dentro de la malla: el planeta recoge los materiales de item
		# por surface_get_material, y así la escena del item es solo un MeshInstance3D.
		mesh.surface_set_material(0, _material(id))
		var path := "res://data/vegetation/marine/%s.res" % id
		if ResourceSaver.save(mesh, path) != OK:
			quit(1)
			return
		print("Baked ", path, " triangles=", mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3,
				" bounds=", mesh.get_aabb())
	quit()


## Material compartido por todas las instancias de la especie.
func _material(id: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/vegetation/marine_flora.gdshader")
	material.set_shader_parameter(&"plant_height", HEIGHTS[id])
	# Extremos del tinte por instancia. El shader coloca cada planta entre los dos,
	# así que un fondo entero no comparte el mismo verde ni el mismo rosa.
	var palette: Dictionary = {
		"seagrass": [Color(0.72, 1.05, 0.78), Color(1.12, 1.0, 0.6)],
		"kelp": [Color(0.78, 0.95, 0.85), Color(1.2, 0.92, 0.55)],
		"sea_fan": [Color(0.72, 0.8, 1.25), Color(1.25, 0.82, 0.68)],
		"coral": [Color(0.84, 0.92, 1.08), Color(1.22, 0.9, 0.86)],
	}
	material.set_shader_parameter(&"tint_cool", palette[id][0])
	material.set_shader_parameter(&"tint_warm", palette[id][1])
	material.set_shader_parameter(&"value_jitter", 0.16 if id == "coral" else 0.2)
	match id:
		"coral":
			# El coral es calcáreo: solo las puntas acusan la corriente.
			material.set_shader_parameter(&"sway_amount", 0.02)
			material.set_shader_parameter(&"sway_stiffness", 3.0)
			material.set_shader_parameter(&"translucency", 0.12)
			material.set_shader_parameter(&"roughness_value", 0.62)
		"sea_fan":
			material.set_shader_parameter(&"sway_amount", 0.05)
			material.set_shader_parameter(&"sway_stiffness", 2.2)
		"kelp":
			material.set_shader_parameter(&"sway_speed", 0.4)
			material.set_shader_parameter(&"sway_amount", 0.1)
	return material


## Desvía un color en tono y claridad, para que dos hojas de la misma mata no sean
## el mismo verde. La saturación se mueve poco: es lo que delata un tinte falso.
func _vary(color: Color, hue: float, value: float, saturation: float = 0.07) -> Color:
	var varied := Color.from_hsv(
			fposmod(color.h + rng.randf_range(-hue, hue), 1.0),
			clampf(color.s + rng.randf_range(-saturation, saturation), 0.0, 1.0),
			clampf(color.v * (1.0 + rng.randf_range(-value, value)), 0.0, 1.0))
	return varied


func _vertex(point: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(point)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color) -> void:
	if (b - a).cross(c - a).length_squared() < 0.0000000001:
		return
	_vertex(a, ca)
	_vertex(b, cb)
	_vertex(c, cb)
	_vertex(a, ca)
	_vertex(c, cb)
	_vertex(d, ca)


## Cinta curvada de `segments` tramos: la base es ancha y la punta se afila.
## `bend` desplaza la punta y `twist` gira la cinta para que no sea plana.
func _blade(base: Vector3, heading: Vector3, height: float, width: float,
		bend: Vector3, twist: float, root_color: Color, tip_color: Color, segments: int = 6,
		ripple: float = 0.0) -> void:
	var previous_left := Vector3.ZERO
	var previous_right := Vector3.ZERO
	for step in segments + 1:
		var t := float(step) / segments
		# Arco cuadrático: vertical en la base, tumbado en la punta.
		# El rizo recorre la cinta a lo largo, que es lo que la separa de una cuchilla recta.
		var point := base + Vector3.UP * (height * t) + bend * (t * t) \
				+ heading * sin(t * PI * 2.2) * ripple
		var side := heading.rotated(Vector3.UP, twist * t)
		var half := width * (1.0 - t * 0.85) * 0.5
		var left := point - side * half
		var right := point + side * half
		if step > 0:
			var color := root_color.lerp(tip_color, t)
			_quad(previous_left, previous_right, right, left, root_color.lerp(tip_color, (t - 1.0 / segments)), color)
		previous_left = left
		previous_right = right


## Tallo de sección triangular: barato y suficiente para ramas y estipes.
func _stem(points: Array[Vector3], radius: float, taper: float, root_color: Color, tip_color: Color) -> void:
	for i in range(points.size() - 1):
		var t := float(i) / maxf(points.size() - 1, 1)
		var next_t := float(i + 1) / maxf(points.size() - 1, 1)
		var along := (points[i + 1] - points[i]).normalized()
		var side := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
		var other := along.cross(side)
		for face in 3:
			var a0 := TAU * face / 3.0
			var a1 := TAU * (face + 1) / 3.0
			var r0 := radius * lerpf(1.0, taper, t)
			var r1 := radius * lerpf(1.0, taper, next_t)
			var color0 := root_color.lerp(tip_color, t)
			var color1 := root_color.lerp(tip_color, next_t)
			_quad(points[i] + (side * cos(a0) + other * sin(a0)) * r0,
					points[i + 1] + (side * cos(a0) + other * sin(a0)) * r1,
					points[i + 1] + (side * cos(a1) + other * sin(a1)) * r1,
					points[i] + (side * cos(a1) + other * sin(a1)) * r0,
					color0, color1)


func _seagrass() -> void:
	# Mata de cintas cortas, más claras en la punta por el desgaste.
	var root := Color("2f5233")
	var tip := Color("8fae54")
	for blade in 16:
		var blade_root := _vary(root, 0.035, 0.22)
		var blade_tip := _vary(tip, 0.045, 0.2)
		var angle := TAU * blade / 16.0 + rng.randf_range(-0.2, 0.2)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.0, 0.09)
		var height := rng.randf_range(0.45, 0.85)
		var lean := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.12, 0.4)
		_blade(offset, Vector3(-sin(angle), 0.0, cos(angle)), height, rng.randf_range(0.03, 0.05),
				lean, rng.randf_range(-0.6, 0.6), blade_root, blade_tip)


func _kelp() -> void:
	# Estipes largos con frondas alternas y flotadores en su arranque.
	var stipe_root := Color("4a3a1f")
	var stipe_tip := Color("6b5a24")
	var frond_root := Color("53421b")
	var frond_tip := Color("9c7c2e")
	for stipe in 3:
		var angle := TAU * stipe / 3.0 + rng.randf_range(-0.3, 0.3)
		var base := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.05, 0.18)
		var height := rng.randf_range(2.8, 4.2)
		var drift := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.3, 0.7)
		var spine: Array[Vector3] = []
		for step in 9:
			var t := float(step) / 8.0
			spine.append(base + Vector3.UP * (height * t) + drift * (t * t))
		_stem(spine, 0.035, 0.45, _vary(stipe_root, 0.02, 0.18), _vary(stipe_tip, 0.025, 0.18))
		for leaf in 11:
			var t := 0.12 + 0.85 * leaf / 11.0
			var index := int(t * 8.0)
			var attach: Vector3 = spine[mini(index, spine.size() - 1)]
			var leaf_angle := angle + PI * leaf * 0.72
			var heading := Vector3(-sin(leaf_angle), 0.0, cos(leaf_angle))
			var out := Vector3(cos(leaf_angle), 0.0, sin(leaf_angle))
			# La fronda nace hacia arriba y cae hacia fuera con su propio peso.
			# Cintas largas que caen hacia fuera: la silueta del kelp es la fronda, no el tallo.
			_blade(attach, heading, rng.randf_range(0.9, 1.5), rng.randf_range(0.15, 0.23),
					out * rng.randf_range(0.3, 0.6) - Vector3.UP * rng.randf_range(0.1, 0.35),
					rng.randf_range(-0.6, 0.6), _vary(frond_root, 0.03, 0.25),
					_vary(frond_tip, 0.04, 0.22), 7, rng.randf_range(0.04, 0.09))
	# Vejigas de flotación en la base de las frondas bajas.
	for float_index in 5:
		var angle := TAU * float_index / 5.0
		var centre := Vector3(cos(angle), 0.0, sin(angle)) * 0.12 + Vector3.UP * rng.randf_range(0.6, 2.4)
		_blob(centre, Vector3(0.05, 0.075, 0.05), Color("7d6526"))


func _sea_fan() -> void:
	# Gorgonia: retícula contenida en un plano, con ramas que se bifurcan y afinan.
	var root := Color("6b2436")
	var tip := Color("c8566b")
	_branch(Vector3.ZERO, Vector3.UP, 0.34, 0.022, 6, root, tip, 0.0)


func _branch(base: Vector3, direction: Vector3, length: float, radius: float,
		depth: int, root: Color, tip: Color, spread: float) -> void:
	if depth <= 0 or length < 0.025:
		return
	var points: Array[Vector3] = []
	for step in 4:
		var t := float(step) / 3.0
		# Cada tramo se arquea un poco, para que la rama no sea un palo recto.
		points.append(base + direction * (length * t) + Vector3(spread, 0.0, 0.0) * (t * t * length * 0.3))
	_stem(points, radius, 0.7, _vary(root, 0.02, 0.16), _vary(tip, 0.03, 0.16))
	var end: Vector3 = points[-1]
	for side in [-1.0, 1.0]:
		var angle: float = rng.randf_range(0.28, 0.5) * side
		# El abanico crece en el plano XY: la rotación es siempre sobre Z.
		_branch(end, direction.rotated(Vector3.BACK, angle).normalized(), length * rng.randf_range(0.78, 0.9),
				radius * 0.78, depth - 1, root, tip, spread + side * 0.06)
	# Rama intermedia ocasional: es lo que llena la retícula y la separa de un árbol pelado.
	if depth > 2 and rng.randf() < 0.55:
		_branch(end, direction.rotated(Vector3.BACK, rng.randf_range(-0.12, 0.12)).normalized(),
				length * 0.7, radius * 0.7, depth - 2, root, tip, spread)


func _coral() -> void:
	# Coral cuerno de alce: base calcárea apagada y puntas claras, no rosa de juguete.
	var root := Color("6d5b41")
	var tip := Color("c3b083")
	for trunk in 4:
		var angle := TAU * trunk / 4.0 + rng.randf_range(-0.3, 0.3)
		var lean := Vector3(cos(angle), 0.0, sin(angle))
		var base := lean * rng.randf_range(0.02, 0.12)
		_antler(base, (Vector3.UP * 5.0 + lean).normalized(), rng.randf_range(0.26, 0.36), 0.05, 4, root, tip)


func _antler(base: Vector3, direction: Vector3, length: float, radius: float,
		depth: int, root: Color, tip: Color) -> void:
	if depth <= 0:
		return
	var points: Array[Vector3] = []
	for step in 4:
		points.append(base + direction * (length * float(step) / 3.0))
	_stem(points, radius, 0.72, _vary(root, 0.025, 0.14), _vary(tip, 0.03, 0.16))
	var end: Vector3 = points[-1]
	if depth == 1:
		_blob(end, Vector3.ONE * radius * 0.85, tip)
		return
	for fork in 2:
		var axis := Vector3(cos(TAU * fork / 2.0 + rng.randf()), 0.0, sin(TAU * fork / 2.0 + rng.randf())).normalized()
		var next := (direction.rotated(axis, rng.randf_range(0.35, 0.6)) + Vector3.UP * 0.25).normalized()
		_antler(end, next, length * rng.randf_range(0.7, 0.85), radius * 0.68, depth - 1, root, tip)


func _blob(centre: Vector3, size: Vector3, color: Color) -> void:
	for ring in 6:
		for segment in 8:
			var points: Array[Vector3] = []
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				var latitude: float = PI * (ring + corner.x) / 6.0
				var longitude: float = TAU * (segment + corner.y) / 8.0
				points.append(centre + Vector3(sin(latitude) * cos(longitude), cos(latitude),
						sin(latitude) * sin(longitude)) * size)
			_quad(points[0], points[1], points[2], points[3], color, color)

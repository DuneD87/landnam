@tool
extends MeshInstance3D

## Saco de cuero con una piel de pelo sobre la boca y los costados, retales superpuestos y
## amarres de tendón. Usa los atlas PBR del manto de pelo y la túnica de pieles, con las UV
## limitadas a sus zonas de pelo/cuero. Metros; Y arriba, +Z hacia la espalda del portador.
const HIDE := &"pack_hide"
const FLAP := &"pack_flap"
const PATCH := &"pack_patch"
const STRAP := &"pack_strap"
const CORD := &"pack_cord"
const WOOD := &"pack_wood"
const SEGMENTS := 32
const ARMOR_MAPS := "res://models/equipable/stone_age/%s_%s.jpg"
## Rectángulos interiores de islas del atlas, en píxeles del albedo de 2048 × 2048.
## Albedo, normales y rugosidad comparten UV; se evitan los huecos y bordes de las islas.
const FUR_REGION := Rect2(1645, 625, 100, 95)
const HIDE_REGION := Rect2(1180, 1130, 150, 150)
const PATCH_REGION := Rect2(1140, 1430, 110, 110)
const FLAP_PROFILE := [Vector2(0.211, 0.035), Vector2(0.224, -0.050),
	Vector2(0.184, -0.110), Vector2(0.118, -0.142),
	Vector2(0.052, -0.153), Vector2(-0.015, -0.146)]
static var _mesh: ArrayMesh


func _ready() -> void:
	mesh = make_mesh()


static func make_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var builder := ProcMesh.Builder.new()
	_body(builder.st(HIDE))
	_flap(builder.st(FLAP))
	_fur(builder.st(FLAP))
	_patch(builder.st(PATCH))
	var cord := builder.st(CORD)
	# Bordes del remiendo inferior y costuras en los costados, con lazadas cortas e irregulares.
	for side: float in [-1.0, 1.0]:
		for i in 8:
			var at := _patch_point(0.04 if side < 0 else 0.96, 0.08 + i * 0.12)
			_rope(cord, PackedVector3Array([at + Vector3(-0.008, 0.005, -0.002),
				at + Vector3(0, 0, -0.005), at + Vector3(0.008, -0.005, -0.002)]), 0.0018)
		# Las correas rodean el hombro con una curva continua, de ancho variable.
		var curve := _curve(PackedVector3Array([Vector3(side * 0.105, -0.175, 0.074),
			Vector3(side * 0.155, -0.095, 0.22), Vector3(side * 0.18, 0.065, 0.285),
			Vector3(side * 0.17, 0.205, 0.25), Vector3(side * 0.135, 0.245, 0.155),
			Vector3(side * 0.095, 0.18, 0.058)]))
		var radii := PackedVector2Array()
		for i in curve.size():
			var t := i / float(curve.size() - 1)
			radii.append(Vector2(0.016 + 0.003 * sin(PI * t), 0.004))
		ProcMesh.tube(builder.st(STRAP), curve, radii, 8)
		for end: Vector3 in [curve[0], curve[-1]]:
			var tie := PackedVector3Array()
			for i in 17:
				var a := TAU * i / 16.0
				tie.append(end + Vector3(cos(a) * 0.022, sin(a) * 0.010, -0.006))
			_rope(cord, tie, 0.0022)
	# Boca fruncida y una lazada central para cerrar la solapa.
	var mouth := PackedVector3Array()
	for i in 49:
		var a := TAU * i / 48.0
		mouth.append(Vector3(cos(a) * 0.117, 0.166 + 0.004 * sin(a * 6.0), sin(a) * 0.077))
	_rope(cord, mouth, 0.003)
	_rope(cord, _curve(PackedVector3Array([Vector3(-0.105, 0.125, -0.158),
		Vector3(-0.068, 0.055, -0.183), Vector3(0, -0.036, -0.185),
		Vector3(0.067, 0.049, -0.181), Vector3(0.102, 0.13, -0.156)])), 0.0034, true)
	var knot := PackedVector3Array()
	for i in 25:
		var a := TAU * i / 24.0
		knot.append(Vector3(cos(a) * 0.013, -0.036 + sin(a) * 0.010, -0.190))
	_rope(cord, knot, 0.0035)
	for side: float in [-1.0, 1.0]:
		var end := Vector3(side * 0.034, -0.15 - 0.012 * side, -0.153)
		_rope(cord, _curve(PackedVector3Array([Vector3(side * 0.004, -0.040, -0.190),
			Vector3(side * 0.018, -0.096, -0.179), end])), 0.0026, true)
		_bead(builder.st(WOOD), end + Vector3(0, 0.009, 0))
		for i in 4:
			_rope(cord, PackedVector3Array([end, end + Vector3((i - 1.5) * 0.003,
				-0.017 - i * 0.002, -0.002)]), 0.0009)
	# Pasador de madera, corto y gastado, en vez de una hebilla.
	ProcMesh.tube(builder.st(WOOD), PackedVector3Array([Vector3(-0.026, -0.032, -0.194),
		Vector3(0, -0.029, -0.200), Vector3(0.026, -0.026, -0.193)]),
		PackedVector2Array([Vector2(0.003, 0.003), Vector2(0.005, 0.005), Vector2(0.002, 0.002)]), 8)
	_mesh = builder.commit(_material)
	return _mesh


static func _body(st: SurfaceTool) -> void:
	var profile := [Vector3(-0.235, 0.105, 0.048), Vector3(-0.216, 0.143, 0.078),
		Vector3(-0.17, 0.168, 0.103), Vector3(-0.09, 0.18, 0.113),
		Vector3(0.015, 0.177, 0.111), Vector3(0.105, 0.16, 0.103),
		Vector3(0.155, 0.13, 0.084), Vector3(0.19, 0.107, 0.065)]
	var rings: Array = []
	for shape: Vector3 in profile:
		var ring := PackedVector3Array()
		for i in SEGMENTS:
			var a := TAU * i / SEGMENTS
			var folds := 0.018 * sin(a * 9.0 + 0.3) * smoothstep(0.025, 0.20, shape.x)
			var swell := 1.0 + 0.035 * sin(a * 3.0 + shape.x * 7.0) + folds
			ring.append(Vector3(cos(a) * shape.y * swell + 0.004 * sin(shape.x * 14.0),
				shape.x + 0.003 * sin(a * 5.0 + shape.x * 19.0), sin(a) * shape.z * swell))
		rings.append(ring)
	for j in rings.size() - 1:
		var low: PackedVector3Array = rings[j]
		var high: PackedVector3Array = rings[j + 1]
		for i in SEGMENTS:
			var k := (i + 1) % SEGMENTS
			# Cada cuarto del saco es una pieza de cuero: mantiene el tamaño del grano en los costados.
			var u := (i % 8) / 8.0
			var v := j / float(rings.size() - 1)
			var next_u := (i % 8 + 1) / 8.0
			var next_v := (j + 1) / float(rings.size() - 1)
			_quad(st, [low[i], low[k], high[k], high[i]],
				[Vector2(u, v), Vector2(next_u, v), Vector2(next_u, next_v), Vector2(u, next_v)])
	for end in [0, rings.size() - 1]:
		var ring: PackedVector3Array = rings[end]
		var center := Vector3.ZERO
		for point in ring:
			center += point / ring.size()
		for i in SEGMENTS:
			var k := (i + 1) % SEGMENTS
			var uv_a := Vector2(cos(TAU * i / SEGMENTS), sin(TAU * i / SEGMENTS)) * 0.5 + Vector2.ONE * 0.5
			var uv_b := Vector2(cos(TAU * k / SEGMENTS), sin(TAU * k / SEGMENTS)) * 0.5 + Vector2.ONE * 0.5
			if end == 0:
				_tri(st, [center, ring[k], ring[i]], [Vector2.ONE * 0.5, uv_b, uv_a])
			else:
				_tri(st, [center, ring[i], ring[k]], [Vector2.ONE * 0.5, uv_a, uv_b])


static func _flap(st: SurfaceTool) -> void:
	st.set_color(Color.WHITE)
	var rows: Array = []
	for row in 11:
		var points := PackedVector3Array()
		for i in 25:
			points.append(_flap_point(i / 24.0, row / 10.0))
		rows.append(points)
	_sheet(st, rows)


static func _flap_point(u: float, t: float) -> Vector3:
	var r := t * (FLAP_PROFILE.size() - 1)
	var index := mini(int(r), FLAP_PROFILE.size() - 2)
	var shape: Vector2 = FLAP_PROFILE[index].lerp(FLAP_PROFILE[index + 1], r - index)
	var across := u * 2.0 - 1.0
	# La piel abraza también los laterales; los extremos vuelven hacia la espalda del portador.
	var angle := across * PI * 0.67
	var x := sin(angle) * lerpf(0.135, 0.195, sin(t * PI * 0.75))
	var hem := 0.014 * sin(u * 13.0 + 0.6) + 0.010 * sin(u * 29.0)
	var y := shape.x - t * t * (0.035 * (1.0 - across * across) + hem)
	var z := shape.y * cos(angle)
	z += -0.009 * sin(u * PI) + 0.003 * sin(u * 23.0 + t * 8.0)
	return Vector3(x, y, z)


## Mechones en el contorno, siguiendo la caída del pelo; el interior conserva el relieve del atlas.
static func _fur(st: SurfaceTool) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 854
	for row in 19:
		for column in 53:
			if row > 0 and row < 16 and column > 3 and column < 49:
				continue
			var u := clampf((column + random.randf_range(-0.3, 0.3)) / 52.0, 0.0, 1.0)
			var t := clampf((row + random.randf_range(-0.3, 0.3)) / 18.0, 0.0, 0.98)
			var at := _flap_point(u, t)
			var across := (_flap_point(minf(1.0, u + 0.01), t)
				- _flap_point(maxf(0.0, u - 0.01), t)).normalized()
			var down := (_flap_point(u, minf(1.0, t + 0.01)) - at).normalized()
			var normal := across.cross(down).normalized()
			at += normal * random.randf_range(0.002, 0.005)
			var width := random.randf_range(0.0014, 0.003)
			var length := random.randf_range(0.014, 0.028)
			var bend := at + down * length * 0.55 + normal * 0.005
			var tip := at + down * length + across * random.randf_range(-0.005, 0.005)
			var shade := random.randf_range(0.72, 1.08)
			st.set_color(Color(shade, shade, shade))
			_quad(st, [at - across * width, at + across * width,
				bend + across * width * 0.5, bend - across * width * 0.5],
				[Vector2(u, t), Vector2(minf(u + 0.03, 1), t),
				Vector2(minf(u + 0.03, 1), minf(t + 0.05, 1)), Vector2(u, minf(t + 0.05, 1))])
			_tri(st, [bend - across * width * 0.5, bend + across * width * 0.5, tip],
				[Vector2(u, minf(t + 0.05, 1)), Vector2(minf(u + 0.03, 1), minf(t + 0.05, 1)),
				Vector2(u, minf(t + 0.1, 1))])
	st.set_color(Color.WHITE)


static func _patch(st: SurfaceTool) -> void:
	for panel in 3:
		var rows: Array = []
		var shade := 0.85 + panel * 0.12
		st.set_color(Color(shade, shade, shade))
		for j in 6:
			var row := PackedVector3Array()
			for i in 7:
				var u := clampf((panel + i / 6.0) / 3.0 + 0.025 * sin(i * 2.7 + j), 0.0, 1.0)
				var at := _patch_point(u, j / 5.0)
				at.y -= (1.0 - j / 5.0) * (0.008 + 0.012 * sin(i * 1.7 + panel))
				at.z -= panel * 0.002
				row.append(at)
			rows.append(row)
		_sheet(st, rows)
	st.set_color(Color.WHITE)


static func _patch_point(u: float, t: float) -> Vector3:
	var x := lerpf(-0.139, 0.133, u) + 0.003 * sin(t * 12.0 + u * 12.0)
	var y := lerpf(-0.192, -0.027, t) + 0.006 * sin(u * 17.0 + t * 5.2)
	var z := -0.118 + 0.042 * pow(absf(x) / 0.14, 2.0)
	return Vector3(x, y, z)


static func _sheet(st: SurfaceTool, rows: Array) -> void:
	for j in rows.size() - 1:
		var low: PackedVector3Array = rows[j]
		var high: PackedVector3Array = rows[j + 1]
		for i in low.size() - 1:
			var u := i / float(low.size() - 1)
			var v := j / float(rows.size() - 1)
			var next_u := (i + 1) / float(low.size() - 1)
			var next_v := (j + 1) / float(rows.size() - 1)
			_quad(st, [low[i], low[i + 1], high[i + 1], high[i]],
				[Vector2(u, v), Vector2(next_u, v), Vector2(next_u, next_v), Vector2(u, next_v)])


static func _quad(st: SurfaceTool, points: Array, uv: Array) -> void:
	_tri(st, [points[0], points[1], points[2]], [uv[0], uv[1], uv[2]])
	_tri(st, [points[0], points[2], points[3]], [uv[0], uv[2], uv[3]])


static func _tri(st: SurfaceTool, points: Array, uv: Array) -> void:
	var base := ProcMesh.vertex_count(st)
	for i in 3:
		ProcMesh.emit(st, uv[i], points[i])
		st.add_index(base + i)


static func _curve(points: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for i in points.size() - 1:
		var a := points[maxi(0, i - 1)]
		var b := points[i]
		var c := points[i + 1]
		var d := points[mini(points.size() - 1, i + 2)]
		for j in 6:
			result.append(b.cubic_interpolate(c, a, d, j / 6.0))
	result.append(points[-1])
	return result


static func _rope(st: SurfaceTool, points: PackedVector3Array, radius: float, braided := false) -> void:
	var radii := PackedVector2Array()
	radii.resize(points.size())
	radii.fill(Vector2.ONE * radius)
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	var side := Vector3.RIGHT
	if bounds.size.y < bounds.size.x and bounds.size.y < bounds.size.z:
		side = Vector3.UP
	elif bounds.size.z < bounds.size.x:
		side = Vector3.BACK
	ProcMesh.tube(st, points, radii, 6, side)
	if not braided:
		return
	# Dos cabos discretos que se cruzan sobre el cordón, legibles también al reducir el icono.
	for phase: float in [0.0, PI]:
		var strand := PackedVector3Array()
		for i in points.size():
			var a := i * 1.8 + phase
			strand.append(points[i] + Vector3(cos(a) * radius * 0.65, 0, sin(a) * radius * 0.65))
		var thin := PackedVector2Array()
		thin.resize(strand.size())
		thin.fill(Vector2.ONE * radius * 0.42)
		ProcMesh.tube(st, strand, thin, 5, side)


static func _bead(st: SurfaceTool, at: Vector3) -> void:
	ProcMesh.lathe(st, [Vector2(0.003, -0.008), Vector2(0.006, -0.004),
		Vector2(0.0065, 0.002), Vector2(0.004, 0.007), Vector2(0.002, 0.009)], 10, at)


static func _material(kind: StringName) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = kind
	material.roughness = 1.0
	material.metallic_specular = 0.18
	match kind:
		HIDE:
			_armor_material(material, "hide_tunic", HIDE_REGION)
		FLAP:
			_armor_material(material, "fur_mantle", FUR_REGION)
		PATCH:
			_armor_material(material, "hide_tunic", PATCH_REGION)
		STRAP:
			_armor_material(material, "hide_tunic", HIDE_REGION)
			material.uv1_scale.y *= 0.3
			material.albedo_color = Color("b6a795")
		CORD:
			material.albedo_color = Color("8d8069")
		WOOD:
			material.albedo_texture = ProcMesh.noise_texture(Color("423023"), Color("7c6040"), 1.8, 849)
	return material


static func _armor_material(material: StandardMaterial3D, garment: String, region: Rect2) -> void:
	material.albedo_texture = load(ARMOR_MAPS % [garment, "albedo"])
	material.normal_enabled = true
	material.normal_texture = load(ARMOR_MAPS % [garment, "normal"])
	material.normal_scale = 0.7
	material.roughness_texture = load(ARMOR_MAPS % [garment, "roughness"])
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.metallic_specular = 0.25
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.uv1_scale = Vector3(region.size.x / 2048.0, region.size.y / 2048.0, 1)
	material.uv1_offset = Vector3(region.position.x / 2048.0, region.position.y / 2048.0, 0)

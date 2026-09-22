extends SceneTree

## Offline sculpting: continuous body lofts, swept foil fins and surface details.
## All coordinates are unscaled; gameplay applies SimpleMarineMesh.MODEL_SCALES.
##
## Every vertex carries two sRGB swatches (COLOR and CUSTOM0) and a signed
## distance in UV2.x. The shader shows the second swatch where that distance is
## positive. A distance interpolates linearly across each triangle, so the
## shark's countershading line, the orca patches and the whale mottling keep a
## sharp edge at any range instead of blurring over the body grid.
const IDS := ["shark", "whale", "orca", "turtle"]
## Distance for surfaces that only ever show their first swatch.
const NO_PATTERN := -1.0
const ROUGHNESS := [0.62, 0.5, 0.34, 0.6]
var surface: SurfaceTool
var kind: int
var profile: Array[Vector4]
var dark: Color
var pale: Color
var skin_noise := FastNoiseLite.new()
var pattern_noise := FastNoiseLite.new()
var flipper_origin := Vector3.ZERO
var flipper_vector := Vector3.ZERO
## Flap amplitude of the flipper being built, relative to the front flippers.
var flipper_amplitude := 1.0
## Roughness forced on the part being built; negative uses the species skin.
var roughness_override := -1.0


func _initialize() -> void:
	skin_noise.seed = 71821
	skin_noise.frequency = 5.0
	pattern_noise.seed = 4127
	pattern_noise.frequency = 1.0
	pattern_noise.fractal_octaves = 2
	DirAccess.make_dir_recursive_absolute("res://data/fauna/meshes/marine")
	for species in 4:
		kind = species
		surface = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_custom_format(0, SurfaceTool.CUSTOM_RGBA8_UNORM)
		dark = [Color("5c7280"), Color("4a6679"), Color("14212b"), Color("6a6c3c")][kind]
		pale = [Color("e6e7e1"), Color("a9bcc2"), Color("f4f1e5"), Color("d9c690")][kind]
		_build()
		surface.generate_normals()
		surface.index()
		var sculpt := surface.commit()
		var importer := ImporterMesh.new()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, sculpt.surface_get_arrays(0), [], {}, null, "",
				Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		importer.generate_lods(60.0, 25.0, [])
		var result := importer.get_mesh()
		print("Automatic LODs: ", importer.get_surface_lod_count(0))
		var lod_counts: Array[int] = []
		for lod in importer.get_surface_lod_count(0):
			lod_counts.append(importer.get_surface_lod_indices(0, lod).size() / 3)
		result.set_meta("lod_triangles", lod_counts)
		var path := "res://data/fauna/meshes/marine/%s.res" % IDS[kind]
		if ResourceSaver.save(result, path, ResourceSaver.FLAG_COMPRESS) != OK:
			quit(1)
			return
		print("Baked ", path, " bounds=", result.get_aabb(), " triangles=", result.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3)
		# Optional raw geometry for a renderer-independent silhouette review.
		if "--review" in OS.get_cmdline_user_args():
			var arrays := result.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var rows: Array = []
			for i in vertices.size():
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				rows.append([vertices[i].x, vertices[i].y, vertices[i].z, colors[i].r, colors[i].g, colors[i].b, normals[i].x, normals[i].y, normals[i].z])
			var file := FileAccess.open("/tmp/marine_%s.json" % IDS[kind], FileAccess.WRITE)
			file.store_string(JSON.stringify({"vertices": rows, "indices": Array(arrays[Mesh.ARRAY_INDEX])}))
	quit()


func _vertex(point: Vector3, color: Color, pattern: float = NO_PATTERN, second: Color = Color(0, 0, 0, 0)) -> void:
	# A transparent second swatch means the surface has a single colour.
	if second.a == 0.0:
		second = color
	surface.set_color(_skin_tone(point, color))
	surface.set_custom(0, _skin_tone(point, second))
	surface.set_uv2(Vector2(pattern, 0.0))
	var weight := 0.0 if flipper_vector == Vector3.ZERO else clampf((point - flipper_origin).dot(flipper_vector) / flipper_vector.length_squared(), 0.0, 1.0)
	surface.set_uv(Vector2(weight * flipper_amplitude, 0.0))
	surface.add_vertex(point)


func _skin_tone(point: Vector3, color: Color) -> Color:
	# Bake skin variation and roughness once; no fragment noise in gameplay.
	var value := maxf(color.r, maxf(color.g, color.b))
	if value > 0.09:
		var variation := skin_noise.get_noise_3dv(point)
		var strength: float = [0.035, 0.06, 0.025, 0.08][kind]
		color = Color(color.r, color.g, color.b) * (1.0 + variation * strength)
	if value < 0.09:
		color.a = 0.18
	else:
		color.a = roughness_override if roughness_override >= 0.0 else ROUGHNESS[kind]
	return color


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_triangle(a, b, c, ca, cb, cc)
	_triangle(a, c, d, ca, cc, cd)


func _triangle(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	if (b - a).cross(c - a).length_squared() < 0.000000000001:
		return
	_vertex(a, ca)
	_vertex(b, cb)
	_vertex(c, cc)


## Quad whose corners switch between two swatches along a signed distance.
func _patterned_quad(points: Array[Vector3], colors: Array[Color], patterns: Array[float], seconds: Array[Color]) -> void:
	for triangle in [[0, 1, 2], [0, 2, 3]]:
		var a: Vector3 = points[triangle[0]]
		if (points[triangle[1]] - a).cross(points[triangle[2]] - a).length_squared() < 0.000000000001:
			continue
		for corner in triangle:
			_vertex(points[corner], colors[corner], patterns[corner], seconds[corner])


func _section(z: float) -> Vector4:
	for i in range(profile.size() - 1):
		if z <= profile[i + 1].x:
			var t := clampf((z - profile[i].x) / (profile[i + 1].x - profile[i].x), 0.0, 1.0)
			# Hermite tangents use actual section spacing, avoiding kinks at the jaw
			# and shoulders where tightly spaced head sections meet the longer body.
			var a := profile[maxi(0, i - 1)]
			var b := profile[i]
			var c := profile[i + 1]
			var d := profile[mini(profile.size() - 1, i + 2)]
			var span := c.x - b.x
			var slope_b := (c - a) / maxf(c.x - a.x, 0.0001)
			var slope_c := (d - b) / maxf(d.x - b.x, 0.0001)
			var t2 := t * t
			var t3 := t2 * t
			var value := b * (2.0 * t3 - 3.0 * t2 + 1.0) + slope_b * span * (t3 - 2.0 * t2 + t) + c * (-2.0 * t3 + 3.0 * t2) + slope_c * span * (t3 - t2)
			return Vector4(z, maxf(0.001, value.y), maxf(0.001, value.z), value.w)
	return profile[-1]


func _mouth_limits() -> Vector2:
	return [Vector2(-1.53, -0.98), Vector2(-3.97, -1.96), Vector2(-2.575, -1.89), Vector2(-1.254, -0.94)][kind]


func _mouth_height(t: float) -> float:
	# Height in the local cross-section, not a shared smile across all species.
	match kind:
		0:
			# Set by absolute height: highest under the snout and falling steadily to
			# the corners, so it reads as an arch from the front and never as a grin.
			var section := _section(lerpf(_mouth_limits().x, _mouth_limits().y, t))
			var height := lerpf(-0.16, -0.25, t) - 0.015 * sin(PI * t)
			return clampf((height - section.w) / (section.z * 0.95), -1.0, 0.99)
		1: return -0.10 - sin(PI * t) * 0.25 + t * 0.06 # Long baleen jaw, high rear corner.
		2: return -0.40 - sin(PI * t) * 0.12 + t * 0.12
		_: return -0.26 - sin(PI * t) * 0.26 - t * 0.06


func _mouth_mask(z: float, angle: float) -> float:
	var limits := _mouth_limits()
	if z < limits.x or z > limits.y:
		return 0.0
	var t := inverse_lerp(limits.x, limits.y, z)
	var along := smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.92, 1.0, t))
	return exp(-pow((sin(angle) - _mouth_height(t)) / 0.035, 2.0)) * along


func _gill_z(gill: int, angle: float) -> float:
	return -0.66 + gill * 0.106 + 0.028 * cos(angle * 2.0)


func _gill_mask(z: float, angle: float) -> float:
	if kind != 0:
		return 0.0
	var band := smoothstep(-0.7, -0.5, sin(angle)) * (1.0 - smoothstep(0.3, 0.52, sin(angle)))
	var mask := 0.0
	for gill in 5:
		mask = maxf(mask, exp(-pow((z - _gill_z(gill, angle)) / 0.013, 2.0)))
	return mask * band


func _pleat_mask(z: float, angle: float) -> float:
	if kind != 1:
		return 0.0
	var belly := 1.0 - smoothstep(-0.85, -0.63, sin(angle))
	# Rorqual pleats run from the chin back to the navel.
	var length := smoothstep(-3.7, -3.3, z) * (1.0 - smoothstep(-0.2, 0.5, z))
	return pow(0.5 + 0.5 * cos((angle + PI * 0.5) * 64.0), 6.0) * belly * length


func _skin(z: float, angle: float, offset: float = 0.0) -> Vector3:
	var section := _section(z)
	var mouth := _mouth_mask(z, angle)
	var gills := _gill_mask(z, angle)
	var crease := mouth * 0.001 + gills * 0.008 + _pleat_mask(z, angle) * 0.013
	var x := cos(angle) * (section.y + offset - crease)
	var y := sin(angle) * (section.z + offset - crease)
	# A flatter jaw and a fuller upper head break the generic elliptical cross-section.
	if sin(angle) < 0.0 and kind < 3:
		y *= 0.93 + 0.07 * absf(sin(angle))
	if kind == 1:
		# The rostral ridge belongs to the head surface, rather than an attached tube.
		var ridge := exp(-pow(cos(angle) / 0.11, 2.0)) * smoothstep(0.7, 0.95, sin(angle))
		y += 0.021 * ridge * smoothstep(-3.9, -3.5, z) * (1.0 - smoothstep(-2.0, -1.55, z))
	return Vector3(x, section.w + y, z)


## Colour, pattern distance and second colour for a point of the body loft.
func _shade(point: Vector3, angle: float) -> Array:
	var s := sin(angle)
	var z := point.z
	var first := dark
	var second := pale
	var pattern := NO_PATTERN
	match kind:
		0:
			pattern = _shark_boundary(z) - s
		1:
			# Blue-grey back over a paler throat, dappled with soft light blotches
			# and finer speckles. Mottling has no hard edge, so it stays baked.
			first = dark.lerp(pale, 1.0 - smoothstep(-0.6, 0.05, s))
			var blotches := smoothstep(0.05, 0.4, pattern_noise.get_noise_3d(point.x * 2.2, point.y * 2.2, z * 1.6))
			var speckles := smoothstep(0.2, 0.5, pattern_noise.get_noise_3d(point.x * 7.0 + 30.0, point.y * 7.0, z * 5.0))
			var dapple := maxf(blotches * 0.4, speckles * 0.3) * smoothstep(-3.5, -2.7, z)
			first = first.lerp(Color("b9c9cf"), dapple)
		2:
			pattern = _orca_white(z, s)
			# Grey saddle behind the dorsal fin.
			var saddle := exp(-pow((z - 0.8) / 0.5, 2.0)) * smoothstep(0.35, 0.85, s)
			first = dark.lerp(Color("98a3a4"), saddle * 0.85)
		3:
			first = _turtle_skin(point, angle)
			second = first
	return [_details(first, point, angle), pattern, _details(second, point, angle)]


func _details(color: Color, point: Vector3, angle: float) -> Color:
	color = color.lerp(dark.darkened(0.65), _gill_mask(point.z, angle) * 0.35)
	# Mouth shading is subtle; a fitted seam supplies a continuous fine edge.
	color = color.lerp(dark.darkened(0.25), _mouth_mask(point.z, angle) * 0.30)
	color = color.lerp(pale.darkened(0.22), _pleat_mask(point.z, angle) * 0.7)
	return color


func _shark_boundary(z: float) -> float:
	# Great whites carry a sharp, ragged line: just above the jaw on the head,
	# low across the gills and pectorals, high along the flank, then down onto
	# the tail stock. Returned as a height in the cross-section.
	var line := lerpf(-0.14, -0.3, smoothstep(-1.8, -1.1, z))
	line = lerpf(line, -0.05, smoothstep(-0.3, 0.5, z))
	line = lerpf(line, -0.45, smoothstep(1.2, 2.0, z))
	var ragged := pattern_noise.get_noise_1d(z * 7.0) * 0.08
	ragged += 0.035 * pow(absf(sin(z * 19.0 + pattern_noise.get_noise_1d(z * 3.0 + 40.0) * 4.0)), 3.0)
	return line + ragged


func _orca_white(z: float, s: float) -> float:
	# Chin and belly, narrowing gently between the flippers and ending before the flukes.
	var belly := lerpf(-0.47, -0.32, smoothstep(-2.0, -1.2, z))
	belly = lerpf(belly, -0.5, smoothstep(-1.4, -0.4, z) * (1.0 - smoothstep(-0.3, 0.5, z)))
	belly = lerpf(belly, -1.1, smoothstep(1.25, 2.3, z))
	var white := belly - s
	# Flank lobe sweeping up and back behind the dorsal fin, blended smoothly
	# into the belly so the join has no corner.
	var t := inverse_lerp(-0.1, 1.6, z)
	if t > 0.0 and t < 1.0:
		var centre := lerpf(-0.6, -0.1, smoothstep(0.05, 0.6, t)) - 0.1 * smoothstep(0.6, 1.0, t)
		var half := 0.22 * pow(sin(PI * t), 0.8) * (1.0 - 0.35 * t)
		var lobe := half - absf(s - centre)
		var blend := 0.05
		white = maxf(white, lobe) + blend * log(1.0 + exp(-absf(white - lobe) / blend))
	return white


func _turtle_skin(point: Vector3, angle: float) -> Color:
	var s := sin(angle)
	# Olive-brown above, pale yellow throat and belly.
	var color := pale.lerp(Color("4f4b27"), smoothstep(-0.5, 0.05, s))
	var top := smoothstep(-0.35, 0.05, s)
	# Distance from the dorsal midline: left and right scales mirror each other.
	var around := absf(wrapf(angle - PI * 0.5, -PI, PI)) * _section(point.z).y
	if point.z < -0.84:
		# Large plates on the head, each with a pale yellow border.
		var edge := _cell_edge(Vector2(point.z / 0.075, around / 0.075), 11)
		color = color.lerp(Color("cdbd84"), (1.0 - smoothstep(0.03, 0.1, edge)) * top)
	else:
		var edge := _cell_edge(Vector2(point.z / 0.04, around / 0.04), 23)
		color = color.lerp(Color("b9aa75"), (1.0 - smoothstep(0.03, 0.12, edge)) * top * 0.45)
	var beak := 1.0 - smoothstep(-1.24, -1.18, point.z)
	return color.lerp(Color("8a7a4c"), beak * 0.7)


func _hash(cell: Vector2, salt: int) -> float:
	return fposmod(sin(cell.x * 127.1 + cell.y * 311.7 + salt * 74.7) * 43758.5453, 1.0)


## Distance to the nearest cell border of a jittered Voronoi pattern, in cell units.
func _cell_edge(point: Vector2, salt: int) -> float:
	var base := point.floor()
	var seeds: Array[Vector2] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := base + Vector2(dx, dy)
			seeds.append(cell + Vector2(0.1 + 0.8 * _hash(cell, salt), 0.1 + 0.8 * _hash(cell, salt + 17)))
	var nearest := seeds[0]
	for seed in seeds:
		if point.distance_squared_to(seed) < point.distance_squared_to(nearest):
			nearest = seed
	var edge := INF
	for seed in seeds:
		if seed != nearest:
			edge = minf(edge, (point.distance_squared_to(seed) - point.distance_squared_to(nearest)) / (2.0 * seed.distance_to(nearest)))
	return edge


func _body() -> void:
	var rings: int = [160, 176, 160, 100][kind]
	var sides: int = [96, 96, 96, 64][kind]
	for ring in rings:
		var z0 := _body_z(float(ring) / rings)
		var z1 := _body_z(float(ring + 1) / rings)
		for side in sides:
			var a0 := TAU * side / sides
			var a1 := TAU * (side + 1) / sides
			var points: Array[Vector3] = []
			var colors: Array[Color] = []
			var patterns: Array[float] = []
			var seconds: Array[Color] = []
			for corner in [Vector2(z0, a0), Vector2(z1, a0), Vector2(z1, a1), Vector2(z0, a1)]:
				var point := _skin(corner.x, corner.y)
				var shade := _shade(point, corner.y)
				points.append(point)
				colors.append(shade[0])
				patterns.append(shade[1])
				seconds.append(shade[2])
			_patterned_quad(points, colors, patterns, seconds)


func _body_z(t: float) -> float:
	# Spend more of the existing tessellation on the snout, jaw and cheeks.
	var head_fraction := 0.20 if kind == 3 else 0.30
	var fraction := lerpf(0.0, head_fraction, t * 2.0) if t < 0.5 else lerpf(head_fraction, 1.0, (t - 0.5) * 2.0)
	return lerpf(profile[0].x, profile[-1].x, fraction)


func _bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	return a * pow(1.0 - t, 3) + b * 3.0 * t * pow(1.0 - t, 2) + c * 3.0 * t * t * (1.0 - t) + d * t * t * t


func _edge(start: Vector3, tip: Vector3, away: Vector3, curve: float, tip_round: float, length: float, span: float) -> Vector3:
	# `away` lies in the fin plane, perpendicular to the edge and out of the fin.
	# Positive curve bows the edge outward (convex), negative gives a falcate edge;
	# tip_round keeps the edges apart until late, so the tip closes as a paddle.
	var along := tip - start
	var first := start + along / 3.0 + away * curve * length
	var second := tip - along * 0.25 + away * (curve * 0.6 + tip_round) * length
	return _bezier(start, first, second, tip, span)


func _fin(lead: Vector3, trail: Vector3, tip: Vector3, normal: Vector3, thickness: float = 0.07, lead_curve: float = 0.06, trail_curve: float = 0.04, tip_round: float = 0.0, pale_under: bool = true, scales := Vector2.ZERO) -> void:
	flipper_origin = (lead + trail) * 0.5
	flipper_vector = tip - flipper_origin if kind == 3 else Vector3.ZERO
	var length := (tip - flipper_origin).length()
	# Planform directions come from the fin plane itself, not from world axes.
	var plane := (tip - lead).cross(trail - lead).normalized()
	if plane.dot(normal) < 0.0:
		plane = -plane
	var lead_away := (tip - lead).cross(plane).normalized()
	if lead_away.dot(trail - lead) > 0.0:
		lead_away = -lead_away
	var trail_away := (tip - trail).cross(plane).normalized()
	if trail_away.dot(lead - trail) > 0.0:
		trail_away = -trail_away
	# Scaled flippers need a finer grid for their pattern.
	var spans := 24 if scales == Vector2.ZERO else 36
	var chords := 12 if scales == Vector2.ZERO else 14
	for face in [-1.0, 1.0]:
		for span in spans:
			for chord in chords:
				var points: Array[Vector3] = []
				var colors: Array[Color] = []
				for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
					var s: float = (span + corner.x) / spans
					var c: float = (chord + corner.y) / chords
					var leading := _edge(lead, tip, lead_away, lead_curve, tip_round, length, s)
					var trailing := _edge(trail, tip, trail_away, trail_curve, tip_round, length, s)
					# Cambered section: thickest near the rounded leading edge.
					var section := sin(PI * pow(c, 0.6)) * thickness * (0.2 + 0.8 * pow(1.0 - s, 0.8))
					points.append(leading.lerp(trailing, c) + plane * face * section)
					if scales != Vector2.ZERO:
						colors.append(_flipper_color(s, c, face, scales))
				if scales == Vector2.ZERO:
					var underside: bool = normal == Vector3.UP and face < 0.0
					var tint := dark.lerp(pale, 0.8 if pale_under and underside else 0.03)
					if kind == 0 and span > 19:
						tint = tint.darkened(0.22)
					# Black tips under the pectorals of a great white.
					if kind == 0 and underside and span > 20:
						tint = Color("25292c")
					colors = [tint, tint, tint, tint]
				if (points[2] - points[0]).cross(points[1] - points[0]).dot(plane * face) < 0.0:
					points.reverse()
					colors.reverse()
				_quad(points[0], points[1], points[2], points[3], colors[0], colors[1], colors[2], colors[3])
	flipper_vector = Vector3.ZERO
	flipper_amplitude = 1.0


func _flipper_color(s: float, c: float, face: float, scales: Vector2) -> Color:
	# Dark scales with pale borders above, a paler yellow underside, and a
	# light trailing margin as on green turtle flippers.
	var edge := _cell_edge(Vector2(s * scales.x, c * scales.y), 29)
	var inner := Color("4a4524") if face > 0.0 else Color("a39565")
	var border := Color("cdbd84") if face > 0.0 else Color("e0d4a4")
	var color := inner.lerp(border, 1.0 - smoothstep(0.03, 0.1, edge))
	return color.lerp(border, smoothstep(0.8, 0.96, c) * 0.85)


func _ellipsoid(center: Vector3, size: Vector3, color: Color) -> void:
	for ring in 16:
		for segment in 24:
			var points: Array[Vector3] = []
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				var latitude: float = PI * (ring + corner.x) / 16.0
				var longitude: float = TAU * (segment + corner.y) / 24.0
				points.append(center + Vector3(sin(latitude) * cos(longitude), cos(latitude), sin(latitude) * sin(longitude)) * size)
			_triangle(points[0], points[2], points[1], color, color, color)
			_triangle(points[0], points[3], points[2], color, color, color)


func _line(points: Array[Vector3], radius: float, color: Color, taper: bool = false) -> void:
	# One parallel-transported frame per point, shared by both adjoining
	# segments, so the tube bends smoothly instead of kinking like chain links.
	var rings: Array = []
	var side := Vector3.ZERO
	for i in points.size():
		var along := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		if side == Vector3.ZERO:
			side = along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
		side = (side - along * side.dot(along)).normalized()
		var up := along.cross(side)
		var width := radius
		if taper:
			width *= 0.25 + 0.75 * sqrt(sin(PI * i / (points.size() - 1)))
		var ring: Array[Vector3] = []
		for segment in 8:
			ring.append(points[i] + (side * cos(TAU * segment / 8.0) + up * sin(TAU * segment / 8.0)) * width)
		rings.append(ring)
	for i in range(points.size() - 1):
		for segment in 8:
			var next := (segment + 1) % 8
			_quad(rings[i][segment], rings[i + 1][segment], rings[i + 1][next], rings[i][next], color, color, color, color)


func _build() -> void:
	if kind == 3:
		_turtle()
		return
	if kind == 0:
		# Conical snout lifted above an underslung jaw; straight back line over a
		# deep chest; the tail root is wider than tall, carrying the keels.
		profile = [Vector4(-1.8, 0.001, 0.001, 0.03), Vector4(-1.74, 0.1, 0.065, 0.03), Vector4(-1.55, 0.24, 0.175, 0.02), Vector4(-1.18, 0.36, 0.32, 0.0), Vector4(-0.55, 0.45, 0.5, -0.035), Vector4(0.1, 0.41, 0.45, -0.02), Vector4(0.8, 0.24, 0.27, 0.0), Vector4(1.5, 0.105, 0.11, 0.01), Vector4(2.0, 0.06, 0.085, 0.02), Vector4(2.12, 0.001, 0.001, 0.02)]
	elif kind == 1:
		# Long, slender rorqual: a broad flat head and a laterally compressed tail stock.
		profile = [Vector4(-3.996, 0.001, 0.001, -0.08), Vector4(-3.94, 0.3, 0.08, -0.08), Vector4(-3.72, 0.55, 0.19, -0.08), Vector4(-3.1, 0.71, 0.37, -0.07), Vector4(-2.2, 0.77, 0.57, -0.03), Vector4(-1.2, 0.77, 0.7, 0), Vector4(0.0, 0.7, 0.72, 0), Vector4(1.3, 0.51, 0.58, 0), Vector4(2.6, 0.27, 0.38, 0), Vector4(3.5, 0.15, 0.25, 0), Vector4(4.4, 0.07, 0.11, 0), Vector4(4.65, 0.001, 0.001, 0)]
	else:
		# Conical head with a low melon, rather than a bulbous beluga forehead.
		profile = [Vector4(-2.6, 0.001, 0.001, -0.10), Vector4(-2.56, 0.15, 0.13, -0.09), Vector4(-2.42, 0.31, 0.30, -0.05), Vector4(-2.2, 0.46, 0.47, -0.01), Vector4(-1.85, 0.59, 0.62, 0.01), Vector4(-0.9, 0.75, 0.84, 0), Vector4(0, 0.66, 0.75, 0), Vector4(1.0, 0.42, 0.53, 0), Vector4(2.15, 0.15, 0.25, 0), Vector4(2.85, 0.07, 0.11, 0), Vector4(3.08, 0.001, 0.001, 0)]
	_body()
	var length: float = [1.6, 3.7, 2.4][kind]
	var up := PI * 0.5
	match kind:
		0:
			# Tall triangular first dorsal, small second dorsal and anal fin.
			_fin(_skin(-0.5, up, -0.06), _skin(0.3, up, -0.06), _skin(0.14, up) + Vector3(0, 0.6, 0.02), Vector3.RIGHT, 0.08, 0.07, -0.12)
			_fin(_skin(1.12, up, -0.02), _skin(1.42, up, -0.02), _skin(1.4, up) + Vector3(0, 0.13, 0.04), Vector3.RIGHT, 0.03, 0.05, -0.08)
			_fin(_skin(1.2, -up, -0.02), _skin(1.45, -up, -0.02), _skin(1.46, -up) + Vector3(0, -0.11, 0.05), Vector3.RIGHT, 0.03, 0.05, -0.08)
			# Lunate caudal: the upper lobe is only slightly longer than the lower one.
			_fin(Vector3(0, 0.03, 1.8), Vector3(0, 0.02, 2.14), Vector3(0, 0.98, 2.62), Vector3.RIGHT, 0.05, 0.07, -0.13)
			_fin(Vector3(0, -0.02, 1.84), Vector3(0, 0.0, 2.14), Vector3(0, -0.78, 2.5), Vector3.RIGHT, 0.045, 0.07, -0.13)
		1:
			# Blue whales carry a tiny dorsal far back on the body.
			_fin(_skin(2.25, up, -0.05), _skin(2.85, up, -0.05), _skin(2.75, up) + Vector3(0, 0.2, 0.1), Vector3.RIGHT, 0.06, 0.1, -0.1)
		2:
			# Tall, nearly straight dorsal.
			_fin(_skin(-0.5, up, -0.06), _skin(0.5, up, -0.06), _skin(0.12, up) + Vector3(0, 0.98, 0.0), Vector3.RIGHT, 0.09, 0.03, -0.05)
	for sign_x in [-1.0, 1.0]:
		var side := func(angle: float) -> float: return angle if sign_x > 0.0 else PI - angle
		match kind:
			0:
				# Long sickle pectorals angled down, pelvics and caudal keels.
				_fin(_skin(-0.66, side.call(-0.5), -0.05), _skin(-0.16, side.call(-0.56), -0.05), Vector3(sign_x * 1.05, -0.64, 0.3), Vector3.UP, 0.08, 0.1, -0.08, 0.01)
				_fin(_skin(0.55, side.call(-1.1), -0.02), _skin(0.85, side.call(-1.15), -0.02), Vector3(sign_x * 0.4, -0.33, 1.04), Vector3.UP, 0.035, 0.06, -0.05)
				_fin(Vector3(sign_x * 0.05, 0.01, 1.52), Vector3(sign_x * 0.045, 0.01, 2.06), Vector3(sign_x * 0.15, 0.01, 1.92), Vector3.UP, 0.025, 0.05, 0.02, 0.05)
			1:
				# Slender pointed flippers, about a seventh of the body length.
				_fin(_skin(-1.62, side.call(-0.45), -0.05), _skin(-1.2, side.call(-0.5), -0.05), Vector3(sign_x * 1.6, -0.95, -0.55), Vector3.UP, 0.08, 0.06, 0.03, 0.0)
				_fin(Vector3(0, 0, 3.92), Vector3(0, 0, 4.64), Vector3(sign_x * 1.3, 0.05, 4.8), Vector3.UP, 0.07, 0.16, -0.06, 0.03)
			2:
				# Large rounded paddles, black on both faces.
				_fin(_skin(-1.62, side.call(-0.62), -0.05), _skin(-1.22, side.call(-0.7), -0.05), Vector3(sign_x * 1.18, -0.9, -0.85), Vector3.UP, 0.08, 0.1, 0.14, 0.14, false)
				_fin(Vector3(0, 0, 2.66), Vector3(0, 0, 3.12), Vector3(sign_x * 0.88, 0.05, 3.3), Vector3.UP, 0.065, 0.12, -0.05, 0.02)
	_face_details(length)


func _eye_point(z: float, angle: float, size: Vector2, radius: float, theta: float, side: float) -> Vector3:
	var local_z := z + cos(theta) * size.x * radius
	var local_angle := angle + sin(theta) * size.y * radius / _section(z).z
	# A shallow cornea follows the actual head curvature, including the eyelids.
	var bulge := size.y * (0.06 + 0.24 * maxf(0.0, 1.0 - radius * radius))
	return _skin(local_z, local_angle if side > 0 else PI - local_angle, bulge)


func _eye(z: float, angle: float, size: Vector2, side: float) -> void:
	# Concentric surface patches replace stacked spheres and conspicuous eye rings.
	for ring in 8:
		for segment in 32:
			var points: Array[Vector3] = []
			var colors: Array[Color] = []
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				var r: float = (ring + corner.x) / 8.0
				var a: float = TAU * (segment + corner.y) / 32.0
				points.append(_eye_point(z, angle, size, r, a, side))
				# A great white's eye reads as solid black.
				var iris: Color = [Color("0b0e11"), Color("23343c"), Color("23343c"), Color("555432")][kind]
				var color := Color("080f16").lerp(iris, smoothstep(0.45, 0.72, r) * 0.65)
				# Only the outer edge blends into the skin; there is no white sclera.
				color = color.lerp(dark, smoothstep(0.78, 1.0, r))
				var glint := exp(-pow((cos(a) * r + 0.25) / 0.15, 2.0) - pow((sin(a) * r - 0.29) / 0.15, 2.0))
				colors.append(color.lerp(Color("b8d5d5"), glint * 0.72))
			if side < 0:
				points.reverse()
				colors.reverse()
			_quad(points[0], points[1], points[2], points[3], colors[0], colors[1], colors[2], colors[3])
	# A skin-colored upper lid, tapered at both corners, gives a calm expression.
	var lid: Array[Vector3] = []
	for step in 25:
		lid.append(_eye_point(z, angle, size, 0.97, PI * step / 24.0, side))
	_line(lid, size.y * 0.075, dark.lightened(0.025))


func _mouth_seam() -> void:
	var limits := _mouth_limits()
	var thickness: float = [0.0034, 0.0045, 0.0032, 0.0018][kind]
	for side in [-1.0, 1.0]:
		var seam: Array[Vector3] = []
		for step in 65:
			var t := float(step) / 64.0
			var angle := asin(_mouth_height(t))
			seam.append(_skin(lerpf(limits.x, limits.y, t), angle if side > 0 else PI - angle, thickness * 0.3))
		_line(seam, thickness, dark.darkened(0.58))


func _shark_gills() -> void:
	# Five slits cut as fine dark tubes, tapered at both ends, inside the creases.
	for side in [-1.0, 1.0]:
		for gill in 5:
			var slit: Array[Vector3] = []
			for step in 17:
				var height := lerpf(-0.6, 0.4 - gill * 0.035, step / 16.0)
				var angle := asin(height)
				# _skin already follows the crease, so the tube sits just under its floor.
				slit.append(_skin(_gill_z(gill, angle), angle if side > 0.0 else PI - angle, -0.0035))
			_line(slit, 0.0065, dark.darkened(0.72), true)


func _face_details(length: float) -> void:
	_mouth_seam()
	if kind == 0:
		_shark_gills()
	if kind == 2:
		_orca_eye_patches()
	for side in [-1.0, 1.0]:
		match kind:
			0: _eye(-1.30, 0.12, Vector2(0.036, 0.03), side)
			1: _eye(-2.07, 0.00, Vector2(0.041, 0.027), side)
			2: _eye(-2.01, 0.025, Vector2(0.029, 0.021), side)

	if kind != 0:
		var blowhole := _skin(-length * 0.44, PI * 0.5, 0.008)
		if kind == 1:
			for side in [-1.0, 1.0]:
				_ellipsoid(blowhole + Vector3(side * 0.055, 0, 0), Vector3(0.027, 0.014, 0.1), dark.darkened(0.7))
		else:
			_ellipsoid(blowhole, Vector3(0.06, 0.014, 0.08), dark.darkened(0.7))
	if kind == 0:
		for side in [-1.0, 1.0]:
			# Nostrils tucked under the broad snout.
			_ellipsoid(_skin(-1.56, -0.85 if side > 0.0 else PI + 0.85, 0.002), Vector3(0.008, 0.004, 0.018), dark.darkened(0.6))


func _orca_eye_patches() -> void:
	# Fit the iconic oval to the skin with its own curved outline. Painting it
	# on the body grid alone gives a visibly stair-stepped edge in close-ups.
	var radii := [0.0, 0.5, 0.9, 0.975, 1.0]
	for side in [-1.0, 1.0]:
		for ring in 4:
			for segment in 64:
				var points: Array[Vector3] = []
				var colors: Array[Color] = []
				for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
					var r: float = radii[ring + corner.x]
					var theta: float = TAU * (segment + corner.y) / 64.0
					# Tilted teardrop: tapers toward the eye, rises and widens to the rear.
					var z := -1.55 + cos(theta) * 0.32 * r
					var taper := lerpf(0.55, 1.0, 0.5 + 0.5 * cos(theta))
					var angle := asin(0.3 + (z + 1.55) * 0.28 + sin(theta) * 0.14 * r * taper)
					points.append(_skin(z, angle if side > 0.0 else PI - angle, 0.004))
					colors.append(dark if r == 1.0 else pale)
				if side < 0.0:
					points.reverse()
					colors.reverse()
				_quad(points[0], points[1], points[2], points[3], colors[0], colors[1], colors[2], colors[3])


func _shell_point(r: float, a: float, top: bool) -> Vector3:
	# A closed, low shell: gently domed carapace over a flatter plastron, parted
	# at the front where the neck leaves, and narrowing to a rounded point at the
	# tail. `r` and `a` are polar coordinates of the unwarped outline ellipse.
	var x := 0.65 * r * cos(a)
	var z := 0.85 * r * sin(a)
	var dome := sqrt(maxf(0.0, 1.0 - r * r))
	var opening := pow(maxf(0.0, -sin(a)), 30.0) * smoothstep(0.5, 1.0, r)
	var y := 0.03 - 0.17 * pow(dome, 0.7) - 0.13 * opening
	if top:
		y = 0.03 + 0.29 * pow(dome, 0.85) + 0.09 * opening
	return Vector3(x * (1.0 - 0.2 * smoothstep(0.0, 0.85, z)), y, z)


func _carapace_point(point: Vector2) -> Vector3:
	var normalized := Vector2(point.x / 0.65, point.y / 0.85)
	return _shell_point(minf(normalized.length(), 1.0), atan2(normalized.y, normalized.x), true)


func _snap(point: Vector2) -> Vector2:
	# Neighbouring scutes compute their shared seam separately; snapping makes
	# both copies identical so the carapace stays watertight and smooth-shaded.
	return (point * 100000.0).round() / 100000.0


func _clip(polygon: Array[Vector2], keep: Vector2, other: Vector2) -> Array[Vector2]:
	# Keeps the half of a convex polygon closer to `keep` than to `other`.
	var normal := other - keep
	var middle := (keep + other) * 0.5
	var result: Array[Vector2] = []
	for i in polygon.size():
		var p := polygon[i]
		var q := polygon[(i + 1) % polygon.size()]
		var dp := (p - middle).dot(normal)
		var dq := (q - middle).dot(normal)
		if dp <= 0.0:
			result.append(p)
		if (dp < 0.0 and dq > 0.0) or (dp > 0.0 and dq < 0.0):
			result.append(p.lerp(q, dp / (dp - dq)))
	return result


func _carapace() -> void:
	# Green turtle scute layout: five vertebrals down the midline, four costals
	# on each side and a ring of marginals. Each scute is the Voronoi cell of
	# its seed, tessellated from its own growth centre out to its seams, so
	# seams stay crisp and the amber rays radiate from the centre of each plate.
	var seeds: Array[Vector2] = [Vector2(0, -0.56), Vector2(0, -0.29), Vector2(0, -0.02), Vector2(0, 0.25), Vector2(0, 0.5)]
	for side in [-1.0, 1.0]:
		for z in [-0.4, -0.13, 0.14, 0.4]:
			seeds.append(Vector2(side * (0.36 - 0.06 * absf(z)), z))
	for i in 24:
		var a := TAU * (i + 0.5) / 24.0
		seeds.append(Vector2(cos(a) * 0.65 * 0.97, sin(a) * 0.85 * 0.97))
	var outline: Array[Vector2] = []
	for i in 96:
		outline.append(Vector2(cos(TAU * i / 96.0) * 0.65, sin(TAU * i / 96.0) * 0.85))
	for i in seeds.size():
		var cell := outline.duplicate()
		for j in seeds.size():
			if j != i:
				cell = _clip(cell, seeds[i], seeds[j])
		_scute(cell, i)


func _scute(cell: Array[Vector2], salt: int) -> void:
	var loop: Array[Vector2] = []
	for i in cell.size():
		var a := _snap(cell[i])
		var b := _snap(cell[(i + 1) % cell.size()])
		var steps := maxi(1, ceili(a.distance_to(b) / 0.03))
		for step in steps:
			var point := _snap(a.lerp(b, float(step) / steps))
			if loop.is_empty() or point.distance_squared_to(loop[-1]) > 0.0000000001:
				loop.append(point)
	if loop.size() > 1 and loop[0].distance_squared_to(loop[-1]) < 0.0000000001:
		loop.pop_back()
	var centre := Vector2.ZERO
	for point in loop:
		centre += point
	centre /= loop.size()
	var fractions := [0.0, 0.35, 0.65, 0.84, 0.93, 1.0]
	for ring in fractions.size() - 1:
		for i in loop.size():
			var next := (i + 1) % loop.size()
			var points: Array[Vector3] = []
			var colors: Array[Color] = []
			for corner in [Vector2i(ring, i), Vector2i(ring + 1, i), Vector2i(ring + 1, next), Vector2i(ring, next)]:
				var f: float = fractions[corner.x]
				var flat := centre.lerp(loop[corner.y], f)
				# Each plate bulges slightly and dips into a groove at its seams.
				var lift := 0.012 * (1.0 - f * f) - 0.006 * smoothstep(0.86, 1.0, f)
				points.append(_carapace_point(flat) + Vector3(0, lift, 0))
				colors.append(_scute_color(flat - centre, f, salt))
			var up := (points[1] - points[0]).cross(points[2] - points[0])
			if up.length_squared() < 0.000000000001:
				up = (points[2] - points[0]).cross(points[3] - points[0])
			if up.y < 0.0:
				points.reverse()
				colors.reverse()
			_quad(points[0], points[1], points[2], points[3], colors[0], colors[1], colors[2], colors[3])


func _scute_color(offset: Vector2, f: float, salt: int) -> Color:
	var theta := atan2(offset.y, offset.x)
	# Irregular amber streaks fanning out over an olive-brown plate.
	var wobble := sin(theta * 3.0 + salt) * 1.4 + sin(theta * 5.0 + salt * 2.3) * 0.7
	var ray := pow(0.5 + 0.5 * sin(theta * (6.0 + salt % 3) + salt * 1.7 + wobble), 3.0)
	var color := Color("574826").lerp(Color("9c7c3e"), ray * 0.8 * smoothstep(0.2, 0.8, f))
	color = color.lerp(Color("3d3419"), (1.0 - smoothstep(0.0, 0.45, f)) * 0.4)
	return color.lerp(Color("2e2716"), smoothstep(0.86, 0.93, f) * 0.85)


func _turtle() -> void:
	# The torso stays inside the shell; only neck, head and tail emerge.
	profile = [Vector4(-1.26, 0.001, 0.001, -0.022), Vector4(-1.245, 0.08, 0.056, -0.011), Vector4(-1.185, 0.14, 0.104, 0.007), Vector4(-1.065, 0.175, 0.16, 0.011), Vector4(-0.94, 0.155, 0.145, 0.007), Vector4(-0.77, 0.115, 0.1, 0), Vector4(-0.55, 0.3, 0.15, 0), Vector4(0, 0.45, 0.17, 0), Vector4(0.55, 0.28, 0.13, 0), Vector4(0.86, 0.1, 0.07, 0), Vector4(0.95, 0.001, 0.001, 0)]
	_body()
	_mouth_seam()
	roughness_override = 0.62
	_carapace()
	# Plain plastron underneath.
	for ring in 20:
		for segment in 96:
			var points: Array[Vector3] = []
			var colors: Array[Color] = []
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				var r: float = (ring + corner.x) / 20.0
				var a: float = TAU * (segment + corner.y) / 96.0
				points.append(_shell_point(r, a, false))
				colors.append(pale.lerp(Color("b59c62"), smoothstep(0.7, 1.0, r) * 0.5))
			points.reverse()
			colors.reverse()
			_quad(points[0], points[1], points[2], points[3], colors[0], colors[1], colors[2], colors[3])
	# Rounded rim along the smooth outline.
	var rim: Array[Vector3] = []
	var lip: Array[Vector3] = []
	for i in 97:
		var a := TAU * i / 96.0
		rim.append(_shell_point(1.0, a, true))
		if absf(a - PI * 1.5) < 0.4:
			lip.append(_shell_point(1.0, a, false))
	_line(rim, 0.02, Color("4e3c20"))
	_line(lip, 0.014, pale.darkened(0.2))
	roughness_override = -1.0
	for sign_x in [-1.0, 1.0]:
		# Long swept front flippers and short rounded rear paddles, both scaled.
		_fin(Vector3(sign_x * 0.33, 0.0, -0.55), Vector3(sign_x * 0.38, 0.0, -0.22), Vector3(sign_x * 1.2, -0.08, 0.28), Vector3.UP, 0.045, 0.1, -0.03, 0.02, true, Vector2(10.0, 3.5))
		# The rear paddles mostly steer; they beat with a fraction of the stroke.
		flipper_amplitude = 0.4
		_fin(Vector3(sign_x * 0.28, 0.0, 0.42), Vector3(sign_x * 0.2, 0.0, 0.68), Vector3(sign_x * 0.62, -0.05, 0.9), Vector3.UP, 0.035, 0.08, 0.08, 0.1, true, Vector2(4.5, 3.0))
		_eye(-1.05, 0.28, Vector2(0.032, 0.026), sign_x)
		_ellipsoid(_skin(-1.212, 0.18 if sign_x > 0 else PI - 0.18, 0.001), Vector3(0.0025, 0.003, 0.005), dark.darkened(0.5))

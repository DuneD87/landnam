extends SceneTree

## Offline sculpting: continuous body lofts, swept foil fins and surface details.
## All coordinates are unscaled; gameplay applies SimpleMarineMesh.MODEL_SCALES.
const IDS := ["shark", "whale", "orca", "turtle"]
var surface: SurfaceTool
var kind: int
var profile: Array[Vector4]
var dark: Color
var pale: Color
var skin_noise := FastNoiseLite.new()
var flipper_origin := Vector3.ZERO
var flipper_vector := Vector3.ZERO
var shell_seams: Array[Vector4] = []


func _initialize() -> void:
	skin_noise.seed = 71821
	skin_noise.frequency = 5.0
	DirAccess.make_dir_recursive_absolute("res://data/fauna/meshes/marine")
	for species in 4:
		kind = species
		surface = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		dark = [Color("587888"), Color("487889"), Color("14212b"), Color("747a47")][kind]
		pale = [Color("e1e4db"), Color("b0ccd0"), Color("f4f1e5"), Color("d5bf87")][kind]
		_build()
		surface.generate_normals()
		surface.index()
		var sculpt := surface.commit()
		var importer := ImporterMesh.new()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, sculpt.surface_get_arrays(0))
		importer.generate_lods(60.0, 25.0, [])
		var result := importer.get_mesh()
		print("Automatic LODs: ", importer.get_surface_lod_count(0))
		var lod_counts: Array[int] = []
		for lod in importer.get_surface_lod_count(0):
			lod_counts.append(importer.get_surface_lod_indices(0, lod).size() / 3)
		result.set_meta("lod_triangles", lod_counts)
		var path := "res://data/fauna/meshes/marine/%s.res" % IDS[kind]
		if ResourceSaver.save(result, path) != OK:
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


func _vertex(point: Vector3, color: Color) -> void:
	# Bake skin variation and roughness once; no fragment noise in gameplay.
	var value := maxf(color.r, maxf(color.g, color.b))
	if value > 0.09:
		var variation := skin_noise.get_noise_3dv(point)
		var strength: float = [0.035, 0.10, 0.025, 0.10][kind]
		color = Color(color.r, color.g, color.b) * (1.0 + variation * strength)
	color.a = 0.18 if value < 0.09 else (0.58 if kind == 3 else 0.43)
	if kind == 3 and flipper_vector != Vector3.ZERO:
		var pattern := pow(absf(sin(point.x * 58.0 + sin(point.z * 16.0)) * sin(point.z * 52.0)), 5.0)
		color = color.lerp(Color(0.67, 0.61, 0.37, color.a), pattern * 0.35)
	surface.set_color(color)
	var weight := 0.0 if flipper_vector == Vector3.ZERO else clampf((point - flipper_origin).dot(flipper_vector) / flipper_vector.length_squared(), 0.0, 1.0)
	surface.set_uv(Vector2(weight, 0.0))
	surface.add_vertex(point)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_triangle(a, b, c, ca, cb, cc)
	_triangle(a, c, d, ca, cc, cd)


func _triangle(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	if (b - a).cross(c - a).length_squared() < 0.000000000001:
		return
	_vertex(a, ca)
	_vertex(b, cb)
	_vertex(c, cc)


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
	return [Vector2(-1.53, -0.98), Vector2(-3.97, -1.96), Vector2(-2.575, -1.89), Vector2(-1.274, -0.955)][kind]


func _mouth_height(t: float) -> float:
	# Height in the local cross-section, not a shared smile across all species.
	match kind:
		0: return lerpf(-0.98, -0.38, t) # U-shaped mouth underneath a projecting snout.
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


func _gill_mask(z: float, angle: float) -> float:
	if kind != 0:
		return 0.0
	var band := smoothstep(-0.7, -0.5, sin(angle)) * (1.0 - smoothstep(0.3, 0.52, sin(angle)))
	var mask := 0.0
	for gill in 5:
		var slit := -0.66 + gill * 0.106 + 0.028 * cos(angle * 2.0)
		mask = maxf(mask, exp(-pow((z - slit) / 0.013, 2.0)))
	return mask * band


func _pleat_mask(z: float, angle: float) -> float:
	if kind != 1:
		return 0.0
	var belly := 1.0 - smoothstep(-0.85, -0.63, sin(angle))
	var length := smoothstep(-3.7, -3.3, z) * (1.0 - smoothstep(-0.8, 0.0, z))
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


func _color(point: Vector3, angle: float) -> Color:
	var boundary := -0.34 + 0.012 * sin(point.z * 7.0)
	if kind == 2:
		# White lower jaw sits below the mouth; the oval eye patch is separate.
		boundary = lerpf(-0.48, -0.30, smoothstep(-2.0, -0.9, point.z))
	var blend := 1.0 - smoothstep(boundary - 0.19, boundary + 0.05, sin(angle))
	var color := dark.lerp(pale, blend)
	if kind == 2:
		var flank := pow((point.z - 0.65) / 0.6, 2.0) + pow((sin(angle) + 0.32) / 0.23, 2.0)
		color = color.lerp(pale, 1.0 - smoothstep(0.82, 1.04, flank))
		var saddle := exp(-pow((point.z - 0.7) / 0.4, 2.0)) * smoothstep(0.45, 0.95, sin(angle))
		color = color.lerp(Color("657475"), saddle * 0.85)
	if kind == 3:
		# Broad head plates read as scales without speckling the face and eyes.
		var scales := pow(absf(sin(point.z * 25.0 + cos(angle * 6.0)) * sin(angle * 12.0)), 10.0)
		color = color.lerp(Color("c8b37d"), scales * 0.30)
		var beak := 1.0 - smoothstep(-1.22, -1.12, point.z)
		color = color.lerp(Color("c2ad78"), beak * 0.65)
	color = color.lerp(dark.darkened(0.65), _gill_mask(point.z, angle) * 0.75)
	# Mouth shading is subtle; a fitted seam supplies a continuous fine edge.
	color = color.lerp(dark.darkened(0.25), _mouth_mask(point.z, angle) * 0.30)
	color = color.lerp(pale.darkened(0.22), _pleat_mask(point.z, angle) * 0.7)
	return color


func _body() -> void:
	var rings := 80 if kind == 3 else (176 if kind == 1 else 160)
	var sides := 48 if kind == 3 else 96
	for ring in rings:
		var z0 := _body_z(float(ring) / rings)
		var z1 := _body_z(float(ring + 1) / rings)
		for side in sides:
			var a0 := TAU * side / sides
			var a1 := TAU * (side + 1) / sides
			var a := _skin(z0, a0)
			var b := _skin(z1, a0)
			var c := _skin(z1, a1)
			var d := _skin(z0, a1)
			_quad(a, b, c, d, _color(a, a0), _color(b, a0), _color(c, a1), _color(d, a1))


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


func _fin(lead: Vector3, trail: Vector3, tip: Vector3, normal: Vector3, thickness: float = 0.07, lead_curve: float = 0.06, trail_curve: float = 0.04, tip_round: float = 0.0, pale_under: bool = true) -> void:
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
	var spans := 24
	var chords := 12
	for face in [-1.0, 1.0]:
		for span in spans:
			for chord in chords:
				var points: Array[Vector3] = []
				for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
					var s: float = (span + corner.x) / spans
					var c: float = (chord + corner.y) / chords
					var leading := _edge(lead, tip, lead_away, lead_curve, tip_round, length, s)
					var trailing := _edge(trail, tip, trail_away, trail_curve, tip_round, length, s)
					# Cambered section: thickest near the rounded leading edge.
					var section := sin(PI * pow(c, 0.6)) * thickness * (0.2 + 0.8 * pow(1.0 - s, 0.8))
					points.append(leading.lerp(trailing, c) + plane * face * section)
				var tint := dark.lerp(pale, 0.8 if pale_under and normal == Vector3.UP and face < 0.0 else 0.03)
				if kind == 0 and span > 19:
					tint = tint.darkened(0.22)
				if (points[2] - points[0]).cross(points[1] - points[0]).dot(plane * face) < 0.0:
					points.reverse()
				_quad(points[0], points[1], points[2], points[3], tint, tint, tint, tint)
	flipper_vector = Vector3.ZERO


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


func _line(points: Array[Vector3], radius: float, color: Color) -> void:
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
		var ring: Array[Vector3] = []
		for segment in 8:
			ring.append(points[i] + (side * cos(TAU * segment / 8.0) + up * sin(TAU * segment / 8.0)) * radius)
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
		# Deep-chested torpedo; the tail root is wider than tall, carrying the keels.
		profile = [Vector4(-1.8, 0.001, 0.001, -0.025), Vector4(-1.73, 0.13, 0.055, -0.005), Vector4(-1.53, 0.27, 0.18, 0.015), Vector4(-1.18, 0.37, 0.33, 0), Vector4(-0.55, 0.45, 0.49, -0.01), Vector4(0.1, 0.41, 0.45, 0), Vector4(0.8, 0.24, 0.27, 0.005), Vector4(1.5, 0.105, 0.11, 0.01), Vector4(2.0, 0.06, 0.085, 0.02), Vector4(2.12, 0.001, 0.001, 0.02)]
	elif kind == 1:
		# Laterally compressed tail stock instead of a round stalk.
		profile = [Vector4(-3.996, 0.001, 0.001, -0.10), Vector4(-3.94, 0.34, 0.10, -0.10), Vector4(-3.72, 0.64, 0.25, -0.10), Vector4(-3.1, 0.86, 0.49, -0.10), Vector4(-2.2, 1.00, 0.79, -0.04), Vector4(-1.5, 1.03, 0.96, 0), Vector4(-0.4, 0.93, 0.98, 0), Vector4(1.0, 0.64, 0.74, 0), Vector4(2.5, 0.31, 0.44, 0), Vector4(3.5, 0.17, 0.29, 0), Vector4(4.4, 0.08, 0.12, 0), Vector4(4.65, 0.001, 0.001, 0)]
	else:
		# Conical head with a low melon, rather than a bulbous beluga forehead.
		profile = [Vector4(-2.6, 0.001, 0.001, -0.10), Vector4(-2.56, 0.15, 0.13, -0.09), Vector4(-2.42, 0.31, 0.30, -0.05), Vector4(-2.2, 0.46, 0.47, -0.01), Vector4(-1.85, 0.59, 0.62, 0.01), Vector4(-0.9, 0.75, 0.84, 0), Vector4(0, 0.66, 0.75, 0), Vector4(1.0, 0.42, 0.53, 0), Vector4(2.15, 0.15, 0.25, 0), Vector4(2.85, 0.07, 0.11, 0), Vector4(3.08, 0.001, 0.001, 0)]
	_body()
	var length: float = [1.6, 3.7, 2.4][kind]
	var up := PI * 0.5
	match kind:
		0:
			# Falcate first dorsal, small second dorsal and anal fin.
			_fin(_skin(-0.5, up, -0.06), _skin(0.28, up, -0.06), _skin(0.1, up) + Vector3(0, 0.52, 0.02), Vector3.RIGHT, 0.08, 0.08, -0.12)
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
				# Broad swept pectorals, pelvics and caudal keels.
				_fin(_skin(-0.66, side.call(-0.55), -0.05), _skin(-0.18, side.call(-0.6), -0.05), Vector3(sign_x * 1.0, -0.46, 0.22), Vector3.UP, 0.08, 0.1, -0.06, 0.02)
				_fin(_skin(0.55, side.call(-1.1), -0.02), _skin(0.85, side.call(-1.15), -0.02), Vector3(sign_x * 0.4, -0.33, 1.04), Vector3.UP, 0.035, 0.06, -0.05)
				_fin(Vector3(sign_x * 0.05, 0.01, 1.52), Vector3(sign_x * 0.045, 0.01, 2.06), Vector3(sign_x * 0.15, 0.01, 1.92), Vector3.UP, 0.025, 0.05, 0.02, 0.05)
			1:
				# Slender pointed flippers, about a seventh of the body length.
				_fin(_skin(-1.62, side.call(-0.45), -0.05), _skin(-1.2, side.call(-0.5), -0.05), Vector3(sign_x * 1.78, -0.98, -0.5), Vector3.UP, 0.08, 0.06, 0.03, 0.0)
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
				var iris := Color("555432") if kind == 3 else Color("23343c")
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
	var thickness: float = [0.0026, 0.0045, 0.0032, 0.0018][kind]
	for side in [-1.0, 1.0]:
		var seam: Array[Vector3] = []
		for step in 65:
			var t := float(step) / 64.0
			var angle := asin(_mouth_height(t))
			seam.append(_skin(lerpf(limits.x, limits.y, t), angle if side > 0 else PI - angle, thickness * 0.3))
		_line(seam, thickness, dark.darkened(0.58))


func _face_details(length: float) -> void:
	_mouth_seam()
	if kind == 2:
		_orca_eye_patches()
	for side in [-1.0, 1.0]:
		match kind:
			0: _eye(-1.30, 0.10, Vector2(0.027, 0.021), side)
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


func _shell_seam_distance(point: Vector2) -> float:
	var nearest := INF
	for edge in shell_seams:
		var a := Vector2(edge.x, edge.y)
		var b := Vector2(edge.z, edge.w)
		var edge_vector := b - a
		var t := clampf((point - a).dot(edge_vector) / edge_vector.length_squared(), 0.0, 1.0)
		nearest = minf(nearest, point.distance_squared_to(a + edge_vector * t))
	return sqrt(nearest)


func _prepare_shell() -> void:
	shell_seams.clear()
	for z in [-0.48, -0.16, 0.16, 0.48]:
		for i in 6:
			var a := Vector2(cos(TAU * i / 6.0) * 0.22, z + sin(TAU * i / 6.0) * 0.185)
			var b := Vector2(cos(TAU * (i + 1) / 6.0) * 0.22, z + sin(TAU * (i + 1) / 6.0) * 0.185)
			shell_seams.append(Vector4(a.x, a.y, b.x, b.y))
		for side in [-1.0, 1.0]:
			shell_seams.append(Vector4(side * 0.22, z, side * 0.57 * sqrt(1.0 - z * z / 0.65), z * 1.12))
	for i in 48:
		var a := TAU * i / 48.0
		var b := TAU * (i + 1) / 48.0
		shell_seams.append(Vector4(cos(a) * 0.58, sin(a) * 0.76, cos(b) * 0.58, sin(b) * 0.76))
	for i in 18:
		var a := TAU * i / 18.0
		shell_seams.append(Vector4(cos(a) * 0.58, sin(a) * 0.76, cos(a) * 0.65, sin(a) * 0.85))


func _shell_point(r: float, a: float, top: bool, grooved: bool = true) -> Vector3:
	# A closed shell: domed carapace over a flatter plastron, parted at the front
	# where the neck leaves, and narrowing toward the tail. Seams and colors use
	# the unwarped ellipse coordinates so the scute layout stays symmetric.
	var x := 0.65 * r * cos(a)
	var z := 0.85 * r * sin(a)
	var dome := sqrt(maxf(0.0, 1.0 - r * r))
	var opening := pow(maxf(0.0, -sin(a)), 30.0) * smoothstep(0.5, 1.0, r)
	var y := 0.03 - 0.2 * pow(dome, 0.7) - 0.15 * opening
	if top:
		var groove := 0.012 * exp(-pow(_shell_seam_distance(Vector2(x, z)) / 0.01, 2.0)) if grooved else 0.0
		y = 0.03 + 0.36 * dome + 0.1 * opening - groove
	return Vector3(x * (1.0 - 0.14 * smoothstep(0.0, 0.85, z)), y, z)


func _shell_color(x: float, z: float, r: float) -> Color:
	var scute_z := clampf(round((z + 0.48) / 0.32) * 0.32 - 0.48, -0.48, 0.48)
	var theta := atan2(z - scute_z, x)
	var streak := 0.5 + 0.5 * cos(theta * 13.0 + sin(theta * 3.0))
	var color := Color("927140").lerp(Color("4b482c"), r * 0.3 + streak * 0.25)
	var seam := 1.0 - smoothstep(0.002, 0.014, _shell_seam_distance(Vector2(x, z)))
	return color.lerp(Color("393629"), seam * 0.8)


func _turtle() -> void:
	_prepare_shell()
	# The torso stays inside the shell; only neck, head and tail emerge.
	profile = [Vector4(-1.28, 0.001, 0.001, -0.025), Vector4(-1.265, 0.09, 0.062, -0.012), Vector4(-1.20, 0.155, 0.115, 0.008), Vector4(-1.07, 0.195, 0.177, 0.012), Vector4(-0.94, 0.17, 0.16, 0.008), Vector4(-0.77, 0.125, 0.105, 0), Vector4(-0.55, 0.3, 0.15, 0), Vector4(0, 0.45, 0.17, 0), Vector4(0.55, 0.28, 0.13, 0), Vector4(0.86, 0.1, 0.07, 0), Vector4(0.95, 0.001, 0.001, 0)]
	_body()
	_mouth_seam()
	# Carapace with engraved polygonal scute seams, then the plain plastron.
	for top in [true, false]:
		var rings := 48 if top else 20
		for ring in rings:
			for segment in 96:
				var points: Array[Vector3] = []
				var colors: Array[Color] = []
				for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
					var r: float = (ring + corner.x) / rings
					var a: float = TAU * (segment + corner.y) / 96.0
					points.append(_shell_point(r, a, top))
					colors.append(_shell_color(0.65 * r * cos(a), 0.85 * r * sin(a), r) if top else pale.lerp(Color("b59c62"), smoothstep(0.7, 1.0, r) * 0.5))
				if not top:
					points.reverse()
					colors.reverse()
				_quad(points[0], points[1], points[2], points[3], colors[0], colors[1], colors[2], colors[3])
	# Rounded rim, following the smooth edge rather than the engraved seams.
	var rim: Array[Vector3] = []
	var lip: Array[Vector3] = []
	for i in 97:
		var a := TAU * i / 96.0
		rim.append(_shell_point(1.0, a, true, false))
		if absf(a - PI * 1.5) < 0.4:
			lip.append(_shell_point(1.0, a, false))
	_line(rim, 0.02, Color("7d6a3e"))
	_line(lip, 0.014, pale.darkened(0.2))
	for sign_x in [-1.0, 1.0]:
		# Long swept front flippers and short rounded rear paddles.
		_fin(Vector3(sign_x * 0.33, 0.0, -0.55), Vector3(sign_x * 0.38, 0.0, -0.22), Vector3(sign_x * 1.2, -0.08, 0.28), Vector3.UP, 0.045, 0.1, -0.03, 0.02)
		_fin(Vector3(sign_x * 0.28, 0.0, 0.42), Vector3(sign_x * 0.2, 0.0, 0.68), Vector3(sign_x * 0.62, -0.05, 0.9), Vector3.UP, 0.035, 0.08, 0.08, 0.1)
		_eye(-1.055, 0.28, Vector2(0.034, 0.027), sign_x)
		_ellipsoid(_skin(-1.231, 0.18 if sign_x > 0 else PI - 0.18, 0.001), Vector3(0.0025, 0.003, 0.005), dark.darkened(0.5))

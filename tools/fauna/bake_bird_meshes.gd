extends SceneTree

## Offline bird sculpting. Y is up, -Z is the beak; feet remain at y=0.
## Wing coordinates are relative to the shoulder and shared by both sides.
const IDS := ["sparrow", "robin", "blue_tit", "gull", "duck"]
const BACK := [Color("92704c"), Color("7d8266"), Color("809a58"), Color("aab9c6"), Color("8d8170")]
const BELLY := [Color("d8c8a5"), Color("e7daca"), Color("ecda70"), Color("f4f1e5"), Color("c9bda7")]
const WING := [Color("78583b"), Color("747459"), Color("4b91ba"), Color("b3c0ca"), Color("827365")]
var st: SurfaceTool
var kind := 0
var profile: Array[Vector4]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/fauna/meshes/birds")
	for species in 5:
		kind = species
		_begin()
		_body()
		_face()
		_tail()
		_feet()
		if not _save("body"):
			quit(1)
			return
		_begin()
		_wing()
		if not _save("wing"):
			quit(1)
			return
	quit()


func _begin() -> void:
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


func _save(part: String) -> bool:
	st.generate_normals()
	st.index()
	var sculpt := st.commit()
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, sculpt.surface_get_arrays(0))
	importer.generate_lods(60.0, 25.0, [])
	var mesh := importer.get_mesh()
	var lods: Array[int] = []
	for i in importer.get_surface_lod_count(0):
		lods.append(importer.get_surface_lod_indices(0, i).size() / 3)
	mesh.set_meta("lod_triangles", lods)
	var path := "res://data/fauna/meshes/birds/%s_%s.res" % [IDS[kind], part]
	if ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS) != OK:
		push_error("Cannot bake " + path)
		return false
	print("BAKED ", IDS[kind], " ", part, ": ", mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3, " triangles; LODs ", lods, "; bounds ", mesh.get_aabb())
	if "--review" in OS.get_cmdline_user_args():
		var arrays := mesh.surface_get_arrays(0)
		var rows: Array = []
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			var p: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
			var n: Vector3 = arrays[Mesh.ARRAY_NORMAL][i]
			var c: Color = arrays[Mesh.ARRAY_COLOR][i]
			c = c.linear_to_srgb()
			rows.append([p.x, p.y, p.z, c.r, c.g, c.b, n.x, n.y, n.z])
		FileAccess.open("/tmp/bird_%s_%s.json" % [IDS[kind], part], FileAccess.WRITE).store_string(JSON.stringify({"vertices": rows, "indices": Array(arrays[Mesh.ARRAY_INDEX])}))
	return true


func _tri(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	if (b - a).cross(c - a).length_squared() < 1.0e-18:
		return
	for v in [0, 1, 2]:
		st.set_color(([ca, cb, cc][v] as Color).srgb_to_linear())
		st.add_vertex([a, b, c][v])


func _quad(points: Array[Vector3], colors: Array[Color], outward: Vector3 = Vector3.ZERO) -> void:
	if outward != Vector3.ZERO and (points[2] - points[0]).cross(points[1] - points[0]).dot(outward) < 0.0:
		points.reverse()
		colors.reverse()
	_tri(points[0], points[1], points[2], colors[0], colors[1], colors[2])
	_tri(points[0], points[2], points[3], colors[0], colors[2], colors[3])


func _section(y: float) -> Vector4:
	for i in range(profile.size() - 1):
		if y <= profile[i + 1].x:
			var a := profile[maxi(0, i - 1)]
			var b := profile[i]
			var c := profile[i + 1]
			var d := profile[mini(profile.size() - 1, i + 2)]
			var span := c.x - b.x
			var t := clampf((y - b.x) / span, 0.0, 1.0)
			var result := b * (2*t*t*t - 3*t*t + 1) + (c-a) / (c.x-a.x) * span * (t*t*t - 2*t*t + t) + c * (-2*t*t*t + 3*t*t) + (d-b) / (d.x-b.x) * span * (t*t*t - t*t)
			return Vector4(y, maxf(0.0001, result.y), maxf(0.0001, result.z), result.w)
	return profile[-1]


func _skin(y: float, angle: float, offset: float = 0.0) -> Vector3:
	var s := _section(y)
	return Vector3(cos(angle) * (s.y + offset), y, s.w + sin(angle) * (s.z + offset))


func _plumage(p: Vector3, angle: float) -> Color:
	var front := -sin(angle)
	var belly := smoothstep(-0.05, 0.65, front)
	var color: Color = BACK[kind].lerp(BELLY[kind], belly)
	if kind == 0:
		var cheek := smoothstep(0.275, 0.30, p.y) * (1.0 - smoothstep(0.337, 0.36, p.y))
		color = color.lerp(Color("e6d3ad"), cheek * smoothstep(-0.65, 0.1, front))
		var bib := smoothstep(0.235, 0.285, p.y) * (1.0 - smoothstep(0.326, 0.343, p.y)) * smoothstep(0.72, 0.95, front)
		color = color.lerp(Color("473e36"), bib)
		var crown := smoothstep(0.365, 0.385, p.y)
		color = color.lerp(Color("aaa38c"), crown)
		var brow := exp(-pow((p.y - 0.352) / 0.008, 2.0)) * smoothstep(-0.5, 0.3, front)
		color = color.lerp(Color("d3b587"), brow * 0.7)
	elif kind == 1:
		color = color.lerp(BACK[kind], smoothstep(.33, .375, p.y))
		var bib := smoothstep(0.175, 0.215, p.y) * (1.0 - smoothstep(0.35, 0.382, p.y)) * smoothstep(-0.12, 0.5, front)
		color = color.lerp(Color("e68a43"), bib)
	elif kind == 2:
		var cheek := smoothstep(0.278, 0.302, p.y)
		color = color.lerp(Color("f4edd4"), cheek * smoothstep(-0.5, -0.2, front))
		var cap := smoothstep(0.365, 0.380, p.y)
		color = color.lerp(Color("438cac"), cap)
		var eye_band := exp(-pow((p.y - 0.336) / 0.009, 4.0)) * (1.0 - cap)
		color = color.lerp(Color("263e50"), eye_band * 0.95)
		var collar := exp(-pow((p.y - 0.293) / 0.011, 4.0)) * smoothstep(-0.1, 0.4, front)
		color = color.lerp(Color("314958"), collar * 0.9)
	elif kind == 3:
		color = color.lerp(BELLY[kind], smoothstep(0.29, 0.36, p.y))
	else:
		var chest := smoothstep(0.21, 0.26, p.y) * smoothstep(0.05, 0.7, front)
		color = color.lerp(Color("824c3e"), chest)
		var neck := smoothstep(0.353, 0.376, p.y)
		color = color.lerp(Color("256952").lerp(Color("3c8265"), front * 0.3 + 0.3), neck)
		var collar := smoothstep(0.349, 0.355, p.y) * (1.0 - smoothstep(0.368, 0.374, p.y))
		color = color.lerp(Color("f1e8ce"), collar)
	# Broad, subdued feather shading rather than noisy surface speckles.
	var down := pow(0.5 + 0.5 * cos(angle * 18.0 + p.y * 60.0), 8.0)
	return color.darkened(down * 0.022 * (1.0 - smoothstep(0.28, 0.33, p.y)))


func _body() -> void:
	if kind < 3:
		profile = [Vector4(0.072, .001, .001, .03), Vector4(.105, .055, .068, .034), Vector4(.16, .091, .114, .026), Vector4(.22, .100, .119, .006), Vector4(.267, .084, .097, -.029), Vector4(.30, .078, .085, -.076), Vector4(.335, .086, .085, -.099), Vector4(.37, .068, .063, -.098), Vector4(.401, .001, .001, -.093)]
		if kind == 1:
			profile[3] = Vector4(.22, .109, .126, .002)
			profile[4] = Vector4(.267, .095, .105, -.035)
		elif kind == 2:
			profile[2] = Vector4(.16, .083, .112, .026)
			profile[3] = Vector4(.22, .093, .113, .006)
		# Extra sections close the crown as a dome instead of a pointed loft cap.
		profile.insert(profile.size()-1, Vector4(.390, .042, .039, -.095))
		profile.insert(profile.size()-1, Vector4(.398, .020, .019, -.094))
	elif kind == 3:
		profile = [Vector4(.087,.001,.001,.06), Vector4(.14,.098,.215,.07), Vector4(.23,.145,.29,.05), Vector4(.29,.129,.262,.055), Vector4(.34,.094,.18,-.035), Vector4(.383,.066,.08,-.188), Vector4(.43,.096,.111,-.23), Vector4(.485,.101,.109,-.242), Vector4(.53,.064,.073,-.241), Vector4(.551,.001,.001,-.235)]
	else:
		profile = [Vector4(.082,.001,.001,.065), Vector4(.14,.137,.242,.065), Vector4(.23,.193,.303,.061), Vector4(.29,.171,.268,.039), Vector4(.33,.128,.185,-.041), Vector4(.369,.073,.086,-.189), Vector4(.42,.103,.111,-.244), Vector4(.475,.118,.118,-.247), Vector4(.533,.078,.079,-.245), Vector4(.561,.001,.001,-.237)]
	for ring in 80:
		for segment in 64:
			var points: Array[Vector3] = []
			var colors: Array[Color] = []
			for corner in [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]:
				var y: float = lerpf(profile[0].x, profile[-1].x, (ring + corner.x) / 80.0)
				var a: float = TAU * (segment + corner.y) / 64.0
				var p := _skin(y, a)
				points.append(p)
				colors.append(_plumage(p, a))
			_quad(points, colors, Vector3(cos(TAU*(segment+.5)/64.0), 0, sin(TAU*(segment+.5)/64.0)))


func _ellipsoid(center: Vector3, size: Vector3, color: Color, rings: int = 10, segments: int = 20) -> void:
	for ring in rings:
		for segment in segments:
			var points: Array[Vector3] = []
			for corner in [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]:
				var latitude: float = PI * (ring + corner.x) / rings
				var longitude: float = TAU * (segment + corner.y) / segments
				points.append(center + Vector3(sin(latitude)*cos(longitude), cos(latitude), sin(latitude)*sin(longitude)) * size)
			_quad(points, [color,color,color,color], points[0] - center)


func _tube(points: Array[Vector3], radius: float, color: Color) -> void:
	for i in range(points.size()-1):
		var axis := (points[i+1]-points[i]).normalized()
		var side := axis.cross(Vector3.UP if absf(axis.y)<.9 else Vector3.RIGHT).normalized()
		var up := axis.cross(side)
		for j in 6:
			var a := (side*cos(TAU*j/6.0)+up*sin(TAU*j/6.0))*radius
			var b := (side*cos(TAU*(j+1)/6.0)+up*sin(TAU*(j+1)/6.0))*radius
			_quad([points[i]+a,points[i+1]+a,points[i+1]+b,points[i]+b], [color,color,color,color], a+b)


func _face() -> void:
	var eye_y: float = [.339, .338, .339, .479, .482][kind]
	var eye_angle: float = [-.67, -.63, -.62, -.64, -.60][kind]
	var radius: float = [.009, .0105, .0085, .010, .0105][kind]
	for side in [-1.0, 1.0]:
		var a: float = eye_angle if side > 0 else PI-eye_angle
		var eye := _skin(eye_y, a, .0005)
		var normal := Vector3(side*cos(eye_angle), .12, sin(eye_angle)).normalized()
		# Small dark eyes seated into the head; a restrained upper orbital lid.
		_ellipsoid(eye, Vector3(radius*.58,radius,radius), Color("182024"))
		_ellipsoid(eye+normal*radius*.35+Vector3(0,radius*.3,-radius*.22), Vector3.ONE*radius*.16, Color("e7e6d4"), 6, 10)
		var lid: Array[Vector3] = []
		for i in 13:
			var theta := PI*i/12.0
			lid.append(_skin(eye_y+sin(theta)*radius*1.13, a+cos(theta)*radius/_section(eye_y).z, .0008))
		_tube(lid, radius*.085, _plumage(eye, a).darkened(.18))
	_bill()


func _bill() -> void:
	var root: Vector3 = [Vector3(0,.316,-.174),Vector3(0,.315,-.177),Vector3(0,.320,-.177),Vector3(0,.446,-.331),Vector3(0,.435,-.338)][kind]
	var length: float = [.071,.063,.053,.19,.175][kind]
	var width: float = [.026,.016,.016,.031,.064][kind]
	var height: float = [.023,.013,.013,.030,.022][kind]
	var color: Color = [Color("817058"),Color("4c4a40"),Color("414f54"),Color("e6bc53"),Color("dcb75a")][kind]
	for ring in 14:
		for j in 24:
			var points: Array[Vector3] = []
			var colors: Array[Color] = []
			for corner in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
				var t: float = (ring+corner.x)/14.0
				var a: float = TAU*(j+corner.y)/24.0
				var taper := pow(1.0-t, .63)
				if kind == 4:
					taper = sqrt(maxf(0,1.0-pow(t,8.0))) * (.80+.20*sin(PI*t))
				var p := root+Vector3(cos(a)*width*taper,sin(a)*height*taper-t*t*height*.40,-length*t)
				var c := color.lightened(.1*maxf(0,sin(a)))
				var seam := exp(-pow(sin(a)/.10,2.0))
				c = c.darkened(seam*.4)
				if kind == 4:
					c = c.lerp(Color("655842"),smoothstep(.91,.98,t)*.8)
				if kind == 3:
					var spot := exp(-pow((t-.69)/.13,2.0))*smoothstep(.2,.8,-sin(a))
					c = c.lerp(Color("bd633b"),spot*.85)
				points.append(p)
				colors.append(c)
			_quad(points,colors,Vector3(cos(TAU*(j+.5)/24.0),sin(TAU*(j+.5)/24.0),0))
	for side in [-1.0,1.0]:
		if kind >= 3:
			_ellipsoid(root+Vector3(side*width*.68,height*.30,-length*.26),Vector3(.0015,.0025,.008),color.darkened(.55),6,10)


func _feather(root: Vector3, tip: Vector3, width: float, color: Color, normal: Vector3 = Vector3.UP, marking: int = 0) -> void:
	var axis := (tip-root).normalized()
	var across := axis.cross(normal).normalized()
	var up := across.cross(axis).normalized()
	for face in [-1.0,1.0]:
		for row in 12:
			for col in 4:
				var points: Array[Vector3] = []
				var colors: Array[Color] = []
				for corner in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
					# Dense stations at both ends keep feather tips rounded.
					var t: float = (1.0-cos(PI*(row+corner.x)/12.0))*.5
					var u: float = (col+corner.y)/2.0-1.0
					var outline := pow(sin(PI*t),.52)
					var bend := sin(PI*t)*width*.23
					points.append(root.lerp(tip,t)+across*u*width*outline+up*(bend+face*(1.0-u*u)*outline*width*.085))
					var c := color.lightened(.07*(1.0-absf(u))).darkened(.10*pow(absf(u),4.0))
					if face < 0:
						c = c.lerp(BELLY[kind],.35)
					if marking == 1:
						c = c.lerp(Color("f5eddb"),smoothstep(.77,.89,t))
					elif marking == 2:
						var speculum := smoothstep(.33,.39,t)*(1.0-smoothstep(.71,.77,t))
						c = c.lerp(Color("476caa"),speculum)
						var bars := exp(-pow((t-.29)/.045,2))+exp(-pow((t-.81)/.05,2))
						c = c.lerp(Color("e7e2cf"),clampf(bars,0,1))
					colors.append(c)
				_quad(points,colors,up*face)


func _wing() -> void:
	var reach: float = [.29,.285,.30,.59,.39][kind]
	var base: Color = WING[kind]
	# Secondaries form a broad inner fan; primaries give a scalloped outer edge.
	for i in 7:
		var t := i/6.0
		var color := base.darkened(.16).lightened(i*.009)
		_feather(Vector3(.02+t*reach*.46,0,.007),Vector3(.035+t*reach*.49,-.010,.142 if kind<3 else .215),.024 if kind<3 else .035,color,Vector3.UP,2 if kind==4 else 0)
	for i in 8:
		var t := i/7.0
		var root := Vector3(reach*(.28+t*.23),.001,-.012+t*.025)
		var tip := Vector3(reach*(.64+t*.36),-.012-t*.014,.135-t*.14 if kind<3 else .22-t*.20)
		var color := base.darkened(.20).lightened(i*.012)
		if kind == 3:
			color = Color("39434d") if i>2 else base
		_feather(root,tip,.024 if kind<3 else .039,color,Vector3.UP,1 if kind==3 and i>4 else 0)
	# Overlapping coverts conceal feather roots and shape the rounded shoulder.
	for row in 2:
		for i in 7:
			var t := i/6.0
			var start := Vector3(.012+t*reach*.66,.011+row*.003,-.045+row*.025)
			var end := start+Vector3(.045,.002,.070 if kind<3 else .10)
			var color := base.lightened(.06 if row==0 else .01)
			_feather(start,end,.025 if kind<3 else .038,color,Vector3.UP,1 if (kind==0 or kind==2) and row==1 else 0)
	_ellipsoid(Vector3(reach*.25,.004,-.017),Vector3(reach*.30,.019,.046 if kind<3 else .065),base,8,20)


func _tail() -> void:
	for i in 8:
		var fan := (i-3.5)/3.5
		var end_z: float = [.32,.29,.34,.47,.46][kind]
		var root_y := .19 if kind<3 else .25
		var root_z := .093 if kind<3 else .25
		var tip := Vector3(fan*(.068 if kind<3 else .10),root_y-.013,end_z-absf(fan)*.025)
		var color: Color = WING[kind].darkened(.18) if kind!=3 else BELLY[kind]
		_feather(Vector3(fan*.025,root_y,root_z),tip,.019 if kind<3 else .027,color)
	if kind==4:
		for side in [-1.0,1.0]:
			var curl: Array[Vector3] = []
			for i in 17:
				var t := i/16.0
				curl.append(Vector3(side*.017,.27+.036*sin(PI*t),.33+.09*t))
			_tube(curl,.006,Color("344438"))


func _feet() -> void:
	var color := Color("9b7e63") if kind<3 else (Color("ceaa94") if kind==3 else Color("d79b47"))
	for side in [-1.0,1.0]:
		var x: float = side*(.045 if kind<3 else .07)
		_tube([Vector3(x,.11,.022),Vector3(x,.062,.025),Vector3(x,.015,-.009)],.0055 if kind<3 else .008,color)
		for toe in [-1.0,0.0,1.0]:
			var tip := Vector3(x+toe*(.018 if kind<3 else .037),.004,-.060 if kind<3 else -.094)
			_tube([Vector3(x,.012,-.009),tip.lerp(Vector3(x,.017,-.009),.35),tip],.003 if kind<3 else .004,color)
			_tube([tip,tip+Vector3(0,-.003,-.007)],.0017,color.darkened(.4))
			if kind>=3 and toe<1:
				var next := tip+Vector3(.037,0,0)
				_tri(Vector3(x,.01,-.009),tip,next,color,color.darkened(.1),color)
		if kind<3:
			_tube([Vector3(x,.010,-.009),Vector3(x,.005,.03),Vector3(x,.002,.038)],.003,color)

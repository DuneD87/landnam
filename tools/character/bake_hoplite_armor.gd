extends SceneTree

## Equipo del Grifo en el espacio de reposo del escaneo. El juego solo carga las mallas horneadas.
## godot --headless --path . --script res://tools/character/bake_hoplite_armor.gd
const OUT := "res://models/equipable/bronze_age/"
const SKIN := preload("res://models/player/xavivar/firstage_human_male_player_skirt_skin.tres")
const PALETTE := {
	"bronze": ["b77b42", 0.73, 0.36], "edge": ["e9bc73", 0.72, 0.29],
	"recess": ["664734", 0.53, 0.56], "oxblood": ["8e2430", 0.02, 0.92],
	"scarlet": ["c53b3e", 0.02, 0.77], "leather": ["653e2a", 0.0, 0.82],
	"ivory": ["e8ce98", 0.2, 0.54],
}

var surfaces := {}
var bone_ids := {}
var bind_pair := Vector2i.ZERO
var weight_fn: Callable


func _initialize() -> void:
	for i in SKIN.get_bind_count():
		bone_ids[String(SKIN.get_bind_name(i)).trim_prefix("mixamorig_")] = i
	var pieces := {"helm": _helmet, "cuirass": _cuirass, "pteruges": _skirt,
		"bracers": _bracers, "greaves": _greaves, "aspis": _shield}
	for part in pieces:
		surfaces.clear()
		_rigid("Hips")
		pieces[part].call()
		var mesh := ArrayMesh.new()
		for key in surfaces:
			var tool: SurfaceTool = surfaces[key]
			var material := StandardMaterial3D.new()
			material.resource_name = key
			material.albedo_color = Color(PALETTE[key][0])
			material.metallic = PALETTE[key][1]
			material.roughness = PALETTE[key][2]
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			tool.set_material(material)
			tool.commit(mesh)
		if ResourceSaver.save(mesh, OUT + "hoplite_%s.res" % part, ResourceSaver.FLAG_COMPRESS) != OK:
			quit(1)
			return
	quit()


func _rigid(bone: String) -> void:
	bind_pair = Vector2i(bone_ids[bone], bone_ids[bone])
	weight_fn = Callable()


## Parche paramétrico indexado con normales continuas. La posición de cada muestra también
## determina sus influencias, para que el borde y el paño sigan juntos al animarse.
func _patch(material: String, cols: int, rows: int, point: Callable, reverse := false) -> void:
	if not surfaces.has(material):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[material] = surface
	var st: SurfaceTool = surfaces[material]
	var base := ProcMesh.vertex_count(st)
	for j in rows + 1:
		var v := float(j) / rows
		for i in cols + 1:
			var u := float(i) / cols
			var p: Vector3 = point.call(u, v)
			var du: Vector3 = point.call(minf(1, u + 0.0005), v) - point.call(maxf(0, u - 0.0005), v)
			var dv: Vector3 = point.call(u, minf(1, v + 0.0005)) - point.call(u, maxf(0, v - 0.0005))
			var normal := du.cross(dv).normalized()
			st.set_normal(-normal if reverse else normal)
			if bind_pair.x >= 0:
				if weight_fn.is_valid():
					weight_fn.call(st, p)
				else:
					_blend(st, bind_pair.x, bind_pair.x, 0.0)
			ProcMesh.emit(st, Vector2(u, v), p)
	for j in rows:
		for i in cols:
			var a := base + j * (cols + 1) + i
			var c := a + cols + 1
			for index in ([a, a + 1, c, a + 1, c + 1, c] if reverse else [a, c, a + 1, a + 1, c, c + 1]):
				st.add_index(index)


## Cordones de metal, nervaduras y orlas. El perfil es perpendicular al trazo.
func _cord(material: String, curve: Callable, radius: float, steps: int, guide := Vector3.BACK) -> void:
	_patch(material, 8, steps, func(u: float, v: float) -> Vector3:
		var at: Vector3 = curve.call(v)
		var forward: Vector3 = (curve.call(minf(1, v + 0.001)) - curve.call(maxf(0, v - 0.001))).normalized()
		var axis := forward.cross(guide)
		if axis.length_squared() < 0.001:
			axis = forward.cross(Vector3.RIGHT)
		axis = axis.normalized()
		return at + radius * (axis * cos(TAU*u) + forward.cross(axis) * sin(TAU*u)))


func _ellipse(a: float, y: float, rx: float, rz: float, z := 0.0) -> Vector3:
	return Vector3(rx * sin(a), y, z + rz * cos(a))


func _helmet() -> void:
	_rigid("Head")
	# La ceja desciende en las sienes; las aberturas quedan entre el nasal y las carrilleras.
	var brow := func(a: float) -> float: return 0.790 + 0.044 * cos(a) + 0.013 * cos(2.0*a)
	var dome := func(u: float, v: float) -> Vector3:
		var a := TAU*u
		var t := v * 1.563
		return _ellipse(a, brow.call(a) + (0.986 - float(brow.call(a))) * sin(t),
			0.112*cos(t), 0.146*cos(t), 0.020 - 0.012*sin(t))
	_patch("bronze", 64, 18, dome)
	_cord("edge", func(t: float): return dome.call(t, 0.005), 0.005, 64, Vector3.UP)
	# Nuca y carrilleras forman una lámina continua con un calado a la altura de los ojos.
	var cheek := func(u: float, v: float) -> Vector3:
		var gap := lerpf(0.30, 0.73, smoothstep(0.65, 1.0, v))
		var a := lerpf(gap, TAU-gap, u)
		var jaw := 0.697 - 0.023 * cos(a) + 0.052 * absf(sin(a))
		return _ellipse(a, lerpf(jaw, float(brow.call(a)), v),
			lerpf(0.098, 0.112, v), lerpf(0.144, 0.146, v), 0.021)
	_patch("bronze", 76, 14, cheek)
	for u: float in [0.0, 1.0]:
		_cord("edge", func(t: float): return cheek.call(u, t), 0.003, 18)
	_cord("edge", func(t: float): return cheek.call(t, 0.0), 0.003, 64, Vector3.UP)
	_patch("bronze", 6, 12, func(u: float, v: float) -> Vector3:
		var x := (u-0.5) * lerpf(0.018, 0.035, v)
		return Vector3(x, lerpf(0.751 + absf(x)*0.55, 0.851, v), 0.168 + 0.011*(1.0-v) - absf(x)*0.4))
	for side: float in [-1.0, 1.0]:
		_cord("edge", func(t: float) -> Vector3:
			var a := side*(0.035 + t*1.58)
			return _ellipse(a, brow.call(a) + 0.010 + 0.014*sin(PI*t), 0.113, 0.145, 0.020), 0.0036, 24)
	# Crin en abanico sagital. Los mechones abren hacia la nuca y alternan rojos en las caras.
	for i in 36:
		for side: float in [-1.0, 1.0]:
			_patch("scarlet" if i % 5 < 2 else "oxblood", 2, 6, func(u: float, v: float) -> Vector3:
				var t := (i + u) / 36.0
				var a := lerpf(-1.38, 1.72, t)
				var hair := 0.076 + 0.020 * sin(t*PI) + 0.003 * sin(23.0*i)
				var x := side * ((0.016 + 0.008*sin(t*PI))*(1.0 - 0.48*v) + 0.0015*sin(PI*u))
				return Vector3(x, 0.879 + (0.124 + hair*v)*cos(a),
					0.015 + (0.117 + hair*v)*sin(a) - 0.035*v), side < 0)
	_patch("scarlet", 54, 3, func(u: float, v: float) -> Vector3:
		var a := lerpf(-1.38, 1.72, u)
		var hair := 0.076 + 0.020 * sin(u*PI)
		return Vector3((v-0.5)*0.022, 0.879 + (0.124 + hair)*cos(a), -0.020 + (0.117+hair)*sin(a)))
	_cord("edge", func(t: float) -> Vector3:
		var a := lerpf(-1.38, 1.72, t)
		return Vector3(0, 0.881+0.123*cos(a), 0.015+0.117*sin(a)), 0.021, 42, Vector3.RIGHT)


func _blend(st: SurfaceTool, a: int, b: int, mix: float) -> void:
	st.set_bones(PackedInt32Array([a,b,0,0]))
	st.set_weights(PackedFloat32Array([1.0-mix,mix,0.0,0.0]))


func _trunk_weights(st: SurfaceTool, p: Vector3) -> void:
	for interval in [["Hips", "Spine", 0.11, 0.245], ["Spine", "Spine1", 0.245, 0.38],
			["Spine1", "Spine2", 0.38, 0.50]]:
		if p.y < interval[3]:
			_blend(st,bone_ids[interval[0]],bone_ids[interval[1]],smoothstep(interval[2], interval[3], p.y))
			return
	_blend(st,bone_ids["Spine2"],0,0.0)


## La musculatura está repujada en la misma chapa. Las sisas bajan a los costados y
## el cuello sube hasta los hombros, dejando el brazo libre.
func _breast(u: float, v: float) -> Vector3:
	var a := TAU*u
	var front := maxf(0, cos(a))
	var waist := 0.138 - 0.044 * pow(front, 4)
	var collar := 0.622 - 0.194 * pow(absf(sin(a)), 7) - 0.060*pow(front, 7)
	var p := _ellipse(a, lerpf(waist, collar, v), 0.180 + 0.043*sin(PI*v*0.69),
		0.166 + 0.012*sin(PI*v) - 0.039*pow(v, 3), -0.003)
	var ax := absf(p.x)
	var relief := 0.042 * exp(-pow((ax-0.101)/0.081, 4) - pow((p.y-0.453)/0.055, 4))
	for y: float in [0.362, 0.300, 0.242]:
		relief += 0.018 * exp(-pow((ax-0.047)/0.039, 2) - pow((p.y-y)/0.022, 2))
	return p + Vector3(0, 0, relief*pow(front, 2))


func _cuirass() -> void:
	weight_fn = _trunk_weights
	_patch("bronze", 96, 48, _breast)
	for height: float in [0.0, 1.0]:
		_cord("edge", func(t: float): return _breast(t, height), 0.006, 96, Vector3.UP)
	_cord("recess", func(t: float): return _breast(t, 0.027), 0.0025, 80, Vector3.UP)
	# Manto escarlata corto, con pliegues que se reúnen en el hombro izquierdo.
	var mantle := func(u: float, v: float) -> Vector3:
		var a := lerpf(1.06, TAU-1.06, u)
		var top := 0.628 - 0.024 * pow(-cos(a), 2)
		var bottom := 0.124 + 0.250 * pow(absf(2.0*u-1.0), 2) + 0.041*u
		var fold := (0.010 + 0.014*(1-v))*cos(12.0*PI*u+0.6*v)
		return _ellipse(a, lerpf(bottom, top, v), lerpf(0.237, 0.161, v)+fold,
			lerpf(0.202, 0.125, v)+fold, -0.043)
	_patch("oxblood", 62, 18, mantle)
	_cord("scarlet", func(t: float): return mantle.call(t,0.015), 0.004, 64, Vector3.UP)
	for side: float in [-1.0, 1.0]:
		var name_side := "Left" if side > 0 else "Right"
		var shoulder: Vector3 = SKIN.get_bind_pose(bone_ids[name_side+"Arm"]).affine_inverse().origin
		var elbow: Vector3 = SKIN.get_bind_pose(bone_ids[name_side+"ForeArm"]).affine_inverse().origin
		var axis := (elbow-shoulder).normalized()
		var lateral := axis.cross(Vector3.BACK).normalized()
		var forward := lateral.cross(axis).normalized()
		_rigid(name_side+"Arm")
		var sleeve := func(a: float, v: float) -> Vector3:
			var radius := lerpf(0.098, 0.081, v)
			return shoulder + axis*lerpf(-0.037, 0.127, v) + radius*(lateral*sin(a)+forward*cos(a))
		_patch("oxblood", 32, 6, func(u: float,v: float): return sleeve.call(TAU*u,v))
		for i in 9:
			var tab := func(u: float,v: float) -> Vector3:
				var a := TAU*(i + 0.06 + 0.88*u)/9.0
				var h := v*(0.81 - 0.09*absf(2*u-1))
				return sleeve.call(a,h) + 0.008*(lateral*sin(a)+forward*cos(a))
			_patch("bronze", 5, 6, tab)
			_cord("edge", func(t: float): return tab.call(t,1.0), 0.0028, 6, axis)
	# Dos fíbulas y bandas de hombro unen la coraza al manto.
	weight_fn = _trunk_weights
	for side: float in [-1.0, 1.0]:
		_patch("oxblood", 12, 22, func(u: float,v: float) -> Vector3:
			var a := lerpf(-1.52, 1.64, v)
			return Vector3(side*(0.125+0.072*u), 0.540+(0.094-0.019*u)*cos(a), -0.029+0.138*sin(a)))
		var pin := Vector3(side*0.144,0.550,0.114)
		_patch("edge", 24, 7, func(u: float,v: float) -> Vector3:
			var r := lerpf(0.024, 0.0001,v)
			return pin+Vector3(r*sin(TAU*u),r*cos(TAU*u),0.008*sin(v*PI/2)), true)


func _skirt_weights(st: SurfaceTool, p: Vector3) -> void:
	# Las láminas cortas acompañan el muslo de su lado al dar un paso.
	var hips := smoothstep(-0.115, 0.102, p.y)
	var left := smoothstep(-0.10, 0.10, p.x)
	st.set_bones(PackedInt32Array([bone_ids["Hips"], bone_ids["LeftUpLeg"], bone_ids["RightUpLeg"], 0]))
	st.set_weights(PackedFloat32Array([hips, left * (1.0 - hips), (1.0 - left) * (1.0 - hips), 0.0]))


func _skirt() -> void:
	weight_fn = _skirt_weights
	var cloth := func(a: float,v: float) -> Vector3:
		var fold := (0.006 + 0.007*(1-v))*cos(18*a)
		return _ellipse(a, lerpf(-0.227+0.009*cos(9*a), 0.156, v),
			lerpf(0.254,0.182,v)+fold, lerpf(0.235,0.163,v)+fold, -0.010)
	_patch("oxblood", 108, 18, func(u: float,v: float): return cloth.call(TAU*u,v))
	_cord("scarlet",func(t: float): return cloth.call(TAU*t,0.021),0.004,100,Vector3.UP)
	for i in 18:
		var plate := func(u: float,v: float) -> Vector3:
			var a := TAU*(i+0.06+u*0.88)/18.0
			var hem := -0.174 - 0.015*cos(i*TAU/6) + 0.021*absf(2*u-1)
			return _ellipse(a,lerpf(hem,0.125,v),lerpf(0.272,0.198,v),lerpf(0.253,0.177,v),-0.010)
		_patch("bronze", 6, 12, plate)
		_cord("edge",func(t: float): return plate.call(t,0.015),0.0028,8,Vector3.UP)
		for u: float in [0.08,0.92]:
			_cord("edge",func(t: float): return plate.call(u,t),0.0016,10)
	# Faja alta y dos filetes pulidos.
	_rigid("Hips")
	var belt := func(u: float,v: float) -> Vector3: return _ellipse(TAU*u, 0.092+0.046*v,0.201,0.181,-0.010)
	_patch("leather", 64, 4, belt)
	for v: float in [0.0,1.0]:
		_cord("edge",func(t: float): return belt.call(t,v),0.004,64,Vector3.UP)


func _bracers() -> void:
	for side: String in ["Left", "Right"]:
		_rigid(side+"ForeArm")
		var elbow: Vector3 = SKIN.get_bind_pose(bone_ids[side+"ForeArm"]).affine_inverse().origin
		var wrist: Vector3 = SKIN.get_bind_pose(bone_ids[side+"Hand"]).affine_inverse().origin
		var axis := (elbow-wrist).normalized()
		var lateral := axis.cross(Vector3.BACK).normalized()
		var forward := lateral.cross(axis).normalized()
		var shell := func(u: float,v: float) -> Vector3:
			var a := TAU*u
			var t := lerpf(0.09, 0.79+0.06*cos(a),v)
			var r := lerpf(0.046,0.070,v) + 0.004*sin(v*PI)
			return wrist.lerp(elbow,t) + lateral*(r*sin(a)) + forward*(r*cos(a))
		_patch("bronze", 32, 10, shell)
		for v: float in [0.0, 0.95, 1.0]:
			_cord("edge",func(t: float): return shell.call(t,v),0.003,32,axis)
		for u: float in [0.0,0.333,0.666]:
			_cord("edge",func(t: float): return shell.call(u+0.034*sin(PI*t),t),0.002,16)


func _greaves() -> void:
	for sign_x: float in [-1.0,1.0]:
		var side := "Left" if sign_x > 0 else "Right"
		_rigid(side+"Leg")
		var shin := func(u: float,v: float) -> Vector3:
			var a := lerpf(-2.28,2.28,u)
			var bulge := sin(v*PI)
			var y := lerpf(-0.842+0.018*absf(sin(a)), -0.444+0.073*pow(maxf(0,cos(a)),2), v)
			var x := sign_x*lerpf(0.155,0.118,v)
			var z := lerpf(-0.068,-0.043,v) - 0.023*bulge
			return Vector3(x+(0.048+0.035*v+0.020*bulge)*sin(a),y,
				z+(0.067+0.052*v+0.013*bulge)*cos(a) + 0.008*exp(-a*a*20))
		_patch("bronze", 38, 22, shin)
		for v: float in [0.0,1.0]:
			_cord("edge",func(t: float): return shin.call(t,v),0.004,36,Vector3.UP)
		for u: float in [0.0,0.5,1.0]:
			_cord("edge",func(t: float): return shin.call(u,t),0.003,24)
		# Correas por detrás de la pantorrilla, entre los dos bordes de la greba.
		for v: float in [0.20,0.73]:
			_patch("leather", 18, 3, func(u: float,h: float) -> Vector3:
				var end: Vector3 = shin.call(1.0,v)
				var center := sign_x*lerpf(0.155,0.118,v)
				var a := lerpf(2.28,TAU-2.28,u)
				var rx := (end.x-center)/sin(2.28)
				return Vector3(center+rx*sin(a),end.y+0.016*h,end.z+rx*(cos(a)-cos(2.28))))
		_rigid(side+"Foot")
		var sole := func(u: float,v: float) -> Vector3:
			var a := TAU*u
			var toe := cos(a)
			return Vector3(sign_x*(0.168+0.027*toe)+(0.056+0.014*toe)*sin(a),
				-0.954+0.018*v+0.013*pow(maxf(toe,0),3),0.008+0.154*toe)
		_patch("leather",40,3,sole)
		for v: float in [0.0,1.0]:
			_patch("leather",40,4,func(u: float,r: float) -> Vector3:
				var edge: Vector3 = sole.call(u,v)
				return Vector3(lerpf(sign_x*0.168,edge.x,0.001+0.999*r),edge.y,lerpf(0.008,edge.z,0.001+0.999*r)), v > 0)
		for z: float in [0.064,0.104]:
			_patch("leather",16,3,func(u: float,v: float) -> Vector3:
				var a := PI*u
				return Vector3(sign_x*0.184+0.066*cos(a),-0.937+0.061*sin(a),
					z+0.016*v+0.02*(u-0.5)))


func _shield() -> void:
	bind_pair.x = -1
	# Cara abombada de laca roja. El motivo es una palmeta simétrica con hojas en relieve.
	var face := func(radius: float,a: float) -> Vector3:
		return Vector3(radius*sin(a), radius*cos(a), 0.028 + 0.092*(1.0-pow(radius/0.385,2)))
	_patch("oxblood",80,20,func(u: float,v: float): return face.call(0.0001+0.379*v,TAU*u))
	for r: float in [0.303,0.314,0.372,0.382]:
		_cord("edge",func(t: float): return face.call(r,TAU*t),0.005 if r<0.38 else 0.009,80)
	for i in 32:
		var start := i*TAU/32.0
		# Greca escalonada en la orla.
		var corners := [Vector2(0,0.329),Vector2(0.78,0.329),Vector2(0.78,0.358),Vector2(0.26,0.358),Vector2(0.26,0.344),Vector2(0.56,0.344)]
		for k in corners.size()-1:
			_cord("edge",func(t: float) -> Vector3:
				var p: Vector2 = corners[k].lerp(corners[k+1], t)
				return face.call(p.y,start+p.x*TAU/32.0),0.003,4)
	for i in range(-3,4):
		var angle := i*0.41
		var length := 0.26 - 0.018*absf(i)
		_patch("ivory",8,14,func(u: float,v: float) -> Vector3:
			var mid := Vector2(sin(angle)*(v+0.22*v*v)*length, -0.075+cos(angle)*v*length)
			var xy := mid + Vector2(cos(angle),-sin(angle))*(u-0.5)*0.043*pow(maxf(0.0001,sin(PI*v)),0.65)
			var p: Vector3 = face.call(xy.length(),atan2(xy.x,xy.y))
			p.z += 0.003+0.003*sin(PI*u)
			return p)
	for side: float in [-1.0,1.0]:
		_cord("edge",func(t: float) -> Vector3:
			var a := lerpf(-0.55,1.70*PI,t)
			var r := lerpf(0.077,0.009,t)
			var xy := Vector2(side*(0.088 - r*cos(a)),-0.113+r*sin(a))
			return face.call(xy.length(),atan2(xy.x,xy.y)) + Vector3.BACK*0.004,0.006,34)
	_patch("leather",72,14,func(u: float,v: float) -> Vector3:
		var p: Vector3 = face.call(0.0001 + 0.383*v,TAU*u)
		return p-Vector3.BACK*0.016,true)
	_cord("leather",func(t: float) -> Vector3: return Vector3(0,lerpf(-0.13,0.13,t),0.089-0.091*sin(PI*t)),0.015,20)

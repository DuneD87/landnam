class_name HumanCarcass
extends RefCounted

## La canal de un humano: el vientre y el pecho abiertos del jugador devorado (PlayerRemains.open_torso).
##   - wound(): el hueco, que se vacía de la piel y de lo que lleve puesto (Dismemberment.carve). Va del
##     pubis a bajo el esternón por delante, a la medida de su cuerpo: se mide en la malla del cuerpo, en
##     el espacio de su piel (metros, +Y arriba, +Z delante), dónde están su vientre y su espalda y lo
##     ancho que es a esa altura.
##   - cavity(): lo que se ve por el hueco. Una cavidad de carne húmeda que lo cierra por detrás, con la
##     sangre encharcada en el fondo; la columna, y las costillas rotas por delante. Se hace aquí
##     (SurfaceTool), en el espacio de la piel, y va pegada al hueso del tronco (sigue a los tirones).
## Granate oscuro, como la sangre, la canal de los animales y los muñones (stump_flesh.gdshader).

const BONE := &"mixamorig_Spine1"
const LOW_BONE := &"mixamorig_Spine"
const HIGH_BONE := &"mixamorig_Spine2"
## Lo que se pasa la abertura por debajo del hueso de abajo y por encima del de arriba (m).
const MARGIN := Vector2(0.07, 0.04)
## Su medio ancho, en fracción del medio ancho del tronco a esa altura, y como mucho (m).
const WIDTH := 0.62
const MAX_HALF_WIDTH := 0.12
## La cavidad: lo que se pasa del hueco por los lados, a qué hondura del grueso del tronco está su
## borde (desde delante) y su fondo (desde detrás), y dónde se encharca la sangre (desde el fondo).
const CAVITY_SPREAD := 1.08
const RIM_DEPTH := 0.25
const FLOOR_HEIGHT := 0.22
const POOL_HEIGHT := 0.3
## Costillas por lado, su grosor (m) y lo que asoman por encima del borde, rotas.
const RIBS := 5
const RIB_RADIUS := 0.0075
const RIB_OVERHANG := 0.55
## La columna: vértebras cada tanto (m), su grosor y el del tubo que las une.
const VERTEBRA_STEP := 0.034
const VERTEBRA_RADIUS := 0.017
const SPINE_RADIUS := 0.011

const FLESH := Color(0.2, 0.022, 0.022)
const BLOOD := Color(0.11, 0.0, 0.004)
const BONE_COLOR := Color(0.68, 0.58, 0.5)

static var _materials := {}


## El hueco del cuerpo de [body] (Mesh_0, en [skeleton]): {bone (el hueso del tronco), body_bind (su
## bind en la piel del cuerpo), center, radii (el cilindro de frente que se vacía), front y back (la
## piel de delante y la de detrás en el centro, en z)}. Vacío si su piel no lleva el tronco.
static func wound(skeleton: Skeleton3D, body: MeshInstance3D) -> Dictionary:
	if body == null or body.skin == null or not (body.mesh is ArrayMesh):
		return {}
	var skin := body.skin
	var binds := {}
	for b in skin.get_bind_count():
		var bind_name := skin.get_bind_name(b)
		var bone := skeleton.find_bone(bind_name) if bind_name != &"" else skin.get_bind_bone(b)
		if bone >= 0:
			binds[skeleton.get_bone_name(bone)] = b
	if not (binds.has(BONE) and binds.has(LOW_BONE) and binds.has(HIGH_BONE)):
		return {}
	var low := skin.get_bind_pose(binds[LOW_BONE]).affine_inverse().origin
	var high := skin.get_bind_pose(binds[HIGH_BONE]).affine_inverse().origin
	var y0 := low.y - MARGIN.x
	var y1 := high.y + MARGIN.y
	var axis_x := (low.x + high.x) * 0.5
	# El grueso por el centro (delante y detrás) y el ancho del tronco en la mitad de abajo (la de
	# arriba roza los brazos, en cruz).
	var front := -INF
	var back := INF
	var half_width := 0.0
	var mesh := body.mesh as ArrayMesh
	for s in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			if v.y < y0 or v.y > y1:
				continue
			if absf(v.x - axis_x) < 0.05:
				front = maxf(front, v.z)
				back = minf(back, v.z)
			if v.y < (y0 + y1) * 0.5 and absf(v.x - axis_x) < 0.3:
				half_width = maxf(half_width, absf(v.x - axis_x))
	if front == -INF or front - back < 0.05:
		return {}
	var radii := Vector3(minf(half_width * WIDTH, MAX_HALF_WIDTH), (y1 - y0) * 0.5, (front - back) * 0.5)
	return {
		bone = skeleton.find_bone(BONE), body_bind = skin.get_bind_pose(binds[BONE]),
		center = Vector3(axis_x, (y0 + y1) * 0.5, (front + back) * 0.5), radii = radii,
		front = front, back = back,
	}


## La cavidad de [wound] (de wound()) en [skeleton], pegada al hueso del tronco.
static func cavity(skeleton: Skeleton3D, wound: Dictionary) -> Node3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = "TorsoCavity"
	attachment.bone_idx = wound.bone
	skeleton.add_child(attachment)
	var node := MeshInstance3D.new()
	node.name = "Cavity"
	node.mesh = build(wound)
	attachment.add_child(node)
	# En el espacio de la piel: el bind lo lleva al marco del hueso, como a la propia piel.
	node.transform = wound.body_bind
	attachment.on_skeleton_update()
	return attachment


## La malla de la cavidad, en el espacio de la piel: carne, sangre y hueso (una superficie cada uno).
static func build(wound: Dictionary) -> ArrayMesh:
	var center: Vector3 = wound.center
	var radii: Vector3 = wound.radii
	var front: float = wound.front
	var back: float = wound.back
	var thick := front - back
	var rim := front - thick * RIM_DEPTH
	var floor_z := back + thick * FLOOR_HEIGHT
	var depth := rim - floor_z
	var rx := radii.x * CAVITY_SPREAD
	var ry := radii.y * CAVITY_SPREAD
	var mesh := ArrayMesh.new()
	mesh.resource_name = "TorsoCavity"

	# La cavidad: medio elipsoide abierto hacia delante, visto por dentro, con la carne irregular.
	var flesh := SurfaceTool.new()
	flesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 10
	var sides := 28
	for i in rings:
		for j in sides:
			var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			var points := []
			for corner in quad:
				points.append(_bowl_point(corner[0] / float(rings), corner[1] / float(sides), center, rx, ry, rim, depth))
			for k in [0, 1, 2, 0, 2, 3]:
				var p: Array = points[k]
				flesh.set_normal(p[1])
				flesh.add_vertex(p[0])
	flesh.set_material(_material(&"flesh"))
	flesh.commit(mesh)

	# La sangre encharcada en el fondo (lo de detrás, abajo: está tumbado boca arriba).
	var blood := SurfaceTool.new()
	blood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pool_z := floor_z + depth * POOL_HEIGHT
	var spread := cos(asin(clampf(1.0 - POOL_HEIGHT, 0.0, 1.0)))
	for j in sides:
		var a0 := TAU * j / sides
		var a1 := TAU * (j + 1) / sides
		for p in [Vector3(center.x, center.y, pool_z),
				Vector3(center.x + cos(a1) * rx * spread * 0.97, center.y + sin(a1) * ry * spread * 0.97, pool_z),
				Vector3(center.x + cos(a0) * rx * spread * 0.97, center.y + sin(a0) * ry * spread * 0.97, pool_z)]:
			blood.set_normal(Vector3.BACK)
			blood.add_vertex(p)
	blood.set_material(_material(&"blood"))
	blood.commit(mesh)

	# La columna y las costillas.
	var bones := SurfaceTool.new()
	bones.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spine_z := floor_z + VERTEBRA_RADIUS * 0.6
	_tube(bones, [Vector3(center.x, center.y - ry * 0.95, spine_z), Vector3(center.x, center.y + ry * 0.95, spine_z)],
		[SPINE_RADIUS, SPINE_RADIUS])
	var y := center.y - ry * 0.9
	while y < center.y + ry * 0.9:
		_blob(bones, Vector3(center.x, y, spine_z), Vector3(VERTEBRA_RADIUS * 1.3, VERTEBRA_RADIUS * 0.7, VERTEBRA_RADIUS))
		y += VERTEBRA_STEP
	for r in RIBS:
		var t := (r + 0.5) / RIBS
		var rib_y := lerpf(0.05, 0.92, t)
		for side in [-1.0, 1.0]:
			_tube(bones, _rib(center, rx, ry, rim, depth, rib_y, side, spine_z), _rib_radii())
	bones.set_material(_material(&"bone"))
	bones.commit(mesh)
	return mesh


## Un punto de la cavidad: [t] del borde (0) al fondo (1), [u] la vuelta. [punto, normal hacia dentro].
static func _bowl_point(t: float, u: float, center: Vector3, rx: float, ry: float, rim: float, depth: float) -> Array:
	var a := t * PI * 0.5
	var angle := u * TAU
	# Carne irregular: bultos que no dependen de la vuelta en el cierre (u = 0 y u = 1 coinciden).
	var bump := 1.0 + 0.06 * sin(angle * 5.0 + t * 7.0) * sin(t * PI) + 0.04 * sin(angle * 11.0 + 1.3)
	var ring := cos(a) * bump
	var point := Vector3(center.x + cos(angle) * rx * ring, center.y + sin(angle) * ry * ring, rim - depth * sin(a))
	var outward := Vector3(cos(angle) * cos(a) / rx, sin(angle) * cos(a) / ry, -sin(a) / depth)
	return [point, -outward.normalized()]


## Una costilla a la altura [height] (0-1 de la mitad de arriba) del lado [side]: de la columna por la
## pared de la cavidad hasta el borde, y por encima del hueco hasta donde se rompió.
static func _rib(center: Vector3, rx: float, ry: float, rim: float, depth: float, height: float, side: float,
		spine_z: float) -> Array:
	var points := []
	var y0 := center.y + ry * height
	var fit := sqrt(maxf(1.0 - height * height, 0.05))
	var steps := 9
	for i in steps + 1:
		var theta := PI * 0.5 * i / steps
		# Bajan algo al rodear el cuerpo.
		var y := y0 - 0.025 * theta
		var x := center.x + side * rx * fit * sin(theta) * 0.95
		var z := maxf(rim - depth * fit * cos(theta), spine_z)
		points.append(Vector3(x, y, z))
	var last: Vector3 = points[-1]
	for i in range(1, 4):
		var k := RIB_OVERHANG * i / 3.0
		points.append(Vector3(last.x - side * rx * fit * 0.35 * k, last.y - 0.01 * k, last.z + 0.03 * k))
	return points


static func _rib_radii() -> Array:
	var radii := []
	for i in 13:
		# Se afina hacia la punta rota.
		radii.append(RIB_RADIUS * (1.0 if i < 10 else lerpf(1.0, 0.45, (i - 9) / 3.0)))
	return radii


## Un tubo por [points] con el grosor [radii] de cada punto.
static func _tube(st: SurfaceTool, points: Array, radii: Array) -> void:
	var sides := 6
	var rings := []
	for i in points.size():
		var p: Vector3 = points[i]
		var along: Vector3 = ((points[mini(i + 1, points.size() - 1)] as Vector3) - (points[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := along.cross(Vector3.BACK if absf(along.z) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(along)
		var ring := []
		for j in sides + 1:
			var a := TAU * j / sides
			var n := side * cos(a) + up * sin(a)
			ring.append([p + n * float(radii[i]), n])
		rings.append(ring)
	for i in rings.size() - 1:
		for j in sides:
			var quad := [rings[i][j], rings[i + 1][j], rings[i + 1][j + 1], rings[i][j + 1]]
			for k in [0, 2, 1, 0, 3, 2]:
				st.set_normal(quad[k][1])
				st.add_vertex(quad[k][0])


## Un bulto (una vértebra): elipsoide de radios [radii] en [center].
static func _blob(st: SurfaceTool, center: Vector3, radii: Vector3) -> void:
	var rings := 4
	var sides := 6
	for i in rings:
		for j in sides:
			var quad := []
			for corner in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var v: float = PI * corner[0] / rings
				var u: float = TAU * corner[1] / sides
				var n := Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u))
				quad.append([center + n * radii, (n / radii).normalized()])
			for k in [0, 2, 1, 0, 3, 2]:
				st.set_normal(quad[k][1])
				st.add_vertex(quad[k][0])


static func _material(kind: StringName) -> StandardMaterial3D:
	if _materials.has(kind):
		return _materials[kind]
	var material := StandardMaterial3D.new()
	# Se ve por dentro y por fuera (la cavidad, el charco, las costillas finas).
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	match kind:
		&"flesh":
			material.albedo_color = FLESH
			material.roughness = 0.35
			material.clearcoat_enabled = true
			material.clearcoat = 0.8
			material.clearcoat_roughness = 0.25
		&"blood":
			material.albedo_color = BLOOD
			material.roughness = 0.06
			material.metallic_specular = 0.7
		_:
			material.albedo_color = BONE_COLOR
			material.roughness = 0.55
	_materials[kind] = material
	return material

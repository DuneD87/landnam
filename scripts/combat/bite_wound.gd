class_name BiteWound
extends RefCounted

## Un bocado que se lleva la carne de los restos de un devorado (PlayerRemains.bite): el hueco en la
## piel y en lo que lleve puesto (Dismemberment.carve, un cilindro corto que entra por donde muerde la
## fiera hacia el hueso, sin atravesar el cuerpo) y dentro un cráter de carne viva, con el borde
## empapado de sangre y, si el bocado es hondo, el hueso asomando.
##
## Todo va en el espacio de la piel del cuerpo (Mesh_0: metros, en reposo), en el marco del bocado
## (frame): +Y a lo largo del hueso, +Z hacia fuera (por donde entra la boca), con el origen en el eje
## del hueso. El cráter cuelga del hueso (BoneAttachment3D, como la canal: HumanCarcass.cavity), así
## que sigue a los tirones, y si se arranca el miembro se va con él (PlayerRemains._on_limb_dropped).
##
## El grosor del miembro en cada sitio se mide una vez de la malla del cuerpo, en un hilo (measure):
## por cada parte que se muerde, una tabla del radio de la piel a lo largo del hueso y alrededor.

const ATTACHMENT_PREFIX := "BiteWound_"
## En el cráter (su BoneAttachment3D): la región del bocado.
const META := &"bite_wound"
## Las partes que se muerden (las de PlayerRemains._spots): su eje (de un hueso a otro) y los huesos
## cuya piel es suya (el dominante de cada vértice).
const PARTS := {
	&"mixamorig_Spine1": {a = &"mixamorig_Hips", b = &"mixamorig_Spine2",
		skin = [&"mixamorig_Hips", &"mixamorig_Spine", &"mixamorig_Spine1", &"mixamorig_Spine2"]},
	&"mixamorig_LeftArm": {a = &"mixamorig_LeftArm", b = &"mixamorig_LeftForeArm", skin = [&"mixamorig_LeftArm"]},
	&"mixamorig_RightArm": {a = &"mixamorig_RightArm", b = &"mixamorig_RightForeArm", skin = [&"mixamorig_RightArm"]},
	&"mixamorig_LeftUpLeg": {a = &"mixamorig_LeftUpLeg", b = &"mixamorig_LeftLeg", skin = [&"mixamorig_LeftUpLeg"]},
	&"mixamorig_RightUpLeg": {a = &"mixamorig_RightUpLeg", b = &"mixamorig_RightLeg", skin = [&"mixamorig_RightUpLeg"]},
}
## La tabla de grosores: tramos a lo largo del eje y sectores alrededor.
const BINS_T := 12
const BINS_A := 24
## Por dónde del eje se muerde (fracción): lejos de las articulaciones, donde la piel es de dos huesos;
## y lo que se aparta al azar de donde muerde la boca, para que no caigan todos en el mismo sitio.
const ALONG := Vector2(0.15, 0.85)
const SPREAD := 0.25
## Medio ancho del bocado (fracción del grosor, y m como mucho) y medio largo a lo largo del hueso (m,
## entre los dos; en el tronco, el doble como mucho).
const WIDTH := 0.6
const MAX_HALF_WIDTH := 0.055
const LENGTH := Vector2(0.03, 0.05)
## Dónde empieza el hueco (fracción del grosor desde el eje): de ahí hacia fuera se va la piel. Y lo que
## se pasa por fuera de la piel, por la ropa y la armadura.
const CUT_FROM := 0.3
const CLOTH := 0.06
## El fondo del cráter (fracción del grosor desde el eje); uno hondo llega al hueso.
const FLOOR := Vector2(0.35, 0.55)
const DEEP_FLOOR := 0.08
const DEEP_CHANCE := 0.45
const BONE_RADIUS := 0.014
## El borde del cráter se mete bajo la piel que queda (fracción de los radios del hueco; como mucho,
## fracción del grosor) y lo que se hunde bajo ella (m): el hueco sale en estrella (no se parten los
## triángulos) y lo que asome entre las puntas es el borde empapado. Sigue la piel de verdad (los
## grosores medidos), no la de un cilindro.
const RIM_SPREAD := 1.6
const RIM_MAX := 0.8
const RIM_SINK := 0.005
## La malla del cráter: anillos del borde al fondo y lados.
const RINGS := 6
const SIDES := 16
## La parte de los anillos (desde el borde) que va empapada de sangre.
const LIP := 0.34


## En un hilo: los grosores de cada parte, de las superficies [surfaces] (los arrays de cada superficie
## de la malla del cuerpo) con su piel. [parts]: {nombre: {a, b (los extremos del eje en el espacio de la
## piel), ref (el eje X de referencia alrededor), binds (los binds de su piel)}}. Deja en [job].result
## {nombre: PackedFloat32Array (BINS_T × BINS_A radios, los más cortos; los sin medir, de su tramo)}.
static func measure(job: Dictionary) -> void:
	var parts: Dictionary = job.parts
	var names := parts.keys()
	var owner := {}
	var starts: Array[Vector3] = []
	var axes: Array[Vector3] = []
	var lengths: Array[float] = []
	var refs: Array[Vector3] = []
	var sides: Array[Vector3] = []
	for i in names.size():
		var spec: Dictionary = parts[names[i]]
		for b: int in spec.binds:
			owner[b] = i
		var axis: Vector3 = spec.b - spec.a
		starts.append(spec.a)
		lengths.append(axis.length())
		axes.append(axis.normalized())
		refs.append(spec.ref)
		sides.append(axis.normalized().cross(spec.ref))
	# Todas las tablas seguidas, una por parte.
	var cells := BINS_T * BINS_A
	# Lo más cerca del eje que pasa la piel en cada tramo y sector: el borde del cráter va por debajo
	# de ella (el máximo se iría a los bultos de al lado, la nalga, que también son de ese hueso; la
	# media, por encima de la piel donde el miembro no es redondo).
	var radii := PackedFloat32Array()
	radii.resize(cells * names.size())
	for arrays: Array in job.surfaces:
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
			continue
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var n := verts.size()
		if n == 0 or bones.size() < n or weights.size() != bones.size():
			continue
		var wc := bones.size() / n
		for i in n:
			var best := i * wc
			for k in range(i * wc + 1, i * wc + wc):
				if weights[k] > weights[best]:
					best = k
			var part: Variant = owner.get(bones[best])
			if part == null:
				continue
			var axis := axes[part]
			var rel := verts[i] - starts[part]
			var along := rel.dot(axis)
			var t := along / lengths[part]
			if t < 0.0 or t >= 1.0:
				continue
			var radial := rel - axis * along
			var cell: int = part * cells + int(t * BINS_T) * BINS_A \
				+ _sector(atan2(radial.dot(sides[part]), radial.dot(refs[part])))
			var r := radial.length()
			radii[cell] = r if radii[cell] <= 0.0 else minf(radii[cell], r)
	var result := {}
	for i in names.size():
		result[names[i]] = _fill(radii.slice(i * cells, (i + 1) * cells))
	job.result = result


## Los sectores sin medir, con lo que haya en su tramo (o en todo el miembro).
static func _fill(table: PackedFloat32Array) -> PackedFloat32Array:
	var total := 0.0
	var count := 0
	for v in table:
		if v > 0.0:
			total += v
			count += 1
	var overall := total / count if count > 0 else 0.0
	for t in BINS_T:
		var row := 0.0
		var got := 0
		for s in BINS_A:
			if table[t * BINS_A + s] > 0.0:
				row += table[t * BINS_A + s]
				got += 1
		for s in BINS_A:
			if table[t * BINS_A + s] <= 0.0:
				table[t * BINS_A + s] = row / got if got > 0 else overall
	return table


static func _sector(angle: float) -> int:
	return posmod(int(floor((angle + PI) / TAU * BINS_A)), BINS_A)


## Lo que measure necesita de la parte [part_name] en la piel [skin] (la del cuerpo, en [skeleton]), o
## {} si su piel no la lleva.
static func part_spec(skeleton: Skeleton3D, skin: Skin, part_name: StringName) -> Dictionary:
	var part: Dictionary = PARTS[part_name]
	var binds := _binds(skeleton, skin)
	if not (binds.has(part.a) and binds.has(part.b)):
		return {}
	var frame_a := skin.get_bind_pose(binds[part.a]).affine_inverse()
	var b := skin.get_bind_pose(binds[part.b]).affine_inverse().origin
	var axis := (b - frame_a.origin).normalized()
	var ref := frame_a.basis.x - axis * frame_a.basis.x.dot(axis)
	if ref.length_squared() < 1e-6:
		ref = axis.cross(Vector3.FORWARD)
	var skin_binds := PackedInt32Array()
	for bone_name: StringName in part.skin:
		if binds.has(bone_name):
			skin_binds.append(binds[bone_name])
	return {a = frame_a.origin, b = b, ref = ref.normalized(), binds = skin_binds}


## Hueso → bind de [skin], por nombre.
static func _binds(skeleton: Skeleton3D, skin: Skin) -> Dictionary:
	var binds := {}
	for b in skin.get_bind_count():
		var bind_name := skin.get_bind_name(b)
		var bone := skeleton.find_bone(bind_name) if bind_name != &"" else skin.get_bind_bone(b)
		if bone >= 0:
			binds[skeleton.get_bone_name(bone)] = b
	return binds


## El bocado en la parte [part_name] de [body] (Mesh_0 de [skeleton]) por [point] (mundo), entrando
## desde [outward] (mundo: hacia fuera de la carne), con los grosores [table] (de measure) y la parte
## [spec] (de part_spec). Devuelve la región para Dismemberment.carve y crater(): {bone, body_bind,
## frame, center, radii, depth (lo del carve), name, thick (el grosor allí), floor (la hondura del
## fondo, desde el eje), deep (si asoma el hueso)}; {} si no se puede.
static func region(skeleton: Skeleton3D, body: MeshInstance3D, part_name: StringName, spec: Dictionary,
		table: PackedFloat32Array, point: Vector3, outward: Vector3) -> Dictionary:
	if body == null or body.skin == null or spec.is_empty() or table.size() != BINS_T * BINS_A:
		return {}
	var bone := skeleton.find_bone(part_name)
	var binds := _binds(skeleton, body.skin)
	if bone < 0 or not binds.has(part_name):
		return {}
	var body_bind := body.skin.get_bind_pose(binds[part_name])
	# Del mundo a la piel: como la piel lo lleva al mundo, por el hueso.
	var to_world := skeleton.global_transform * skeleton.get_bone_global_pose(bone) * body_bind
	var to_skin := to_world.affine_inverse()
	var p := to_skin * point
	var out := (to_skin.basis * outward).normalized()
	var a: Vector3 = spec.a
	var axis: Vector3 = spec.b - a
	var length := axis.length()
	axis /= length
	var t := clampf((p - a).dot(axis) / length + randf_range(-SPREAD, SPREAD), ALONG.x, ALONG.y)
	var center := a + axis * t * length
	var z := out - axis * out.dot(axis)
	if z.length_squared() < 1e-4:
		z = (p - center) - axis * (p - center).dot(axis)
	if z.length_squared() < 1e-8:
		return {}
	z = z.normalized()
	var x := axis.cross(z).normalized()
	var ref: Vector3 = spec.ref
	var angle := atan2(z.dot(axis.cross(ref)), z.dot(ref))
	var thick := table[mini(int(t * BINS_T), BINS_T - 1) * BINS_A + _sector(angle)]
	if thick <= 0.01:
		return {}
	var torso := part_name == PlayerRemains.TORSO_BONE
	var half_length := randf_range(LENGTH.x, LENGTH.y) * (1.6 if torso else 1.0)
	var deep := not torso and randf() < DEEP_CHANCE
	var wound := make(part_name, skeleton.find_bone(part_name), body_bind, Transform3D(Basis(x, axis, z), center),
		thick, minf(thick * WIDTH, MAX_HALF_WIDTH), half_length,
		thick * (DEEP_FLOOR if deep else randf_range(FLOOR.x, FLOOR.y)), deep, randf() * TAU)
	wound.rim = _rim(wound, func(at: Vector3) -> float: return _radius_at(spec, table, at))
	return wound


## La región de un bocado de medidas dadas (al hacerlo, o al rehacerlo de la partida: ver to_save).
## [phase] da su desgarro. Sin rim (lo hace region), el borde va sobre un cilindro del grosor.
static func make(part_name: StringName, bone: int, body_bind: Transform3D, frame: Transform3D, thick: float,
		half_width: float, half_length: float, floor_z: float, deep: bool, phase: float) -> Dictionary:
	var wound := {
		bone = bone, body_bind = body_bind, frame = frame,
		center = Vector3(0.0, 0.0, thick * CUT_FROM), radii = Vector3(half_width, half_length, 0.0),
		depth = thick * (1.0 - CUT_FROM) + CLOTH, centroid = true,
		name = part_name, thick = thick, floor = floor_z, deep = deep, phase = phase,
	}
	wound.rim = _rim(wound, func(_at: Vector3) -> float: return thick)
	return wound


## Los radios del borde del cráter (en su marco) y su desgarro en el lado [theta]: hacia el fondo
## ([s] 1) se pierde.
static func _rim_size(wound: Dictionary) -> Vector2:
	var radii: Vector3 = wound.radii
	var most: float = wound.thick * RIM_MAX
	return Vector2(minf(radii.x * RIM_SPREAD, most), minf(radii.y * RIM_SPREAD, most * 2.0))


static func _tear(theta: float, s: float, phase: float) -> float:
	return 1.0 + 0.12 * sin(theta * 3.0 + phase) * (1.0 - s) + 0.06 * sin(theta * 7.0 + phase * 2.0)


## Lo alto (z, en el marco del bocado) del borde del cráter en cada lado: sobre la piel, que [radius]
## da a cada punto (en el espacio de la piel) como su distancia al eje, algo hundido.
static func _rim(wound: Dictionary, radius: Callable) -> PackedFloat32Array:
	var frame: Transform3D = wound.frame
	var size := _rim_size(wound)
	var rim := PackedFloat32Array()
	for j in SIDES:
		var theta := TAU * j / SIDES
		var tear := _tear(theta, 0.0, wound.phase)
		var x := cos(theta) * size.x * tear
		var y := sin(theta) * size.y * tear
		var z: float = wound.thick
		# El radio de la piel depende de por dónde se mida: unas vueltas hasta que casa.
		for i in 3:
			var r: float = radius.call(frame * Vector3(x, y, z))
			z = sqrt(maxf(r * r - x * x, r * r * 0.12))
		rim.append(z - RIM_SINK)
	return rim


## La distancia al eje de la piel de la parte [spec] por donde pasa [at] (espacio de la piel), de los
## grosores [table] (interpolados entre tramos y sectores).
static func _radius_at(spec: Dictionary, table: PackedFloat32Array, at: Vector3) -> float:
	var a: Vector3 = spec.a
	var axis: Vector3 = spec.b - a
	var length := axis.length()
	axis /= length
	var ref: Vector3 = spec.ref
	var rel := at - a
	var radial := rel - axis * rel.dot(axis)
	var ft := clampf(rel.dot(axis) / length * BINS_T - 0.5, 0.0, BINS_T - 1.0)
	var fa := (atan2(radial.dot(axis.cross(ref)), radial.dot(ref)) + PI) / TAU * BINS_A - 0.5
	var t0 := mini(int(ft), BINS_T - 2)
	var a0 := int(floor(fa))
	var wt := ft - t0
	var wa := fa - a0
	var cells := []
	for dt in 2:
		for da in 2:
			cells.append(table[(t0 + dt) * BINS_A + posmod(a0 + da, BINS_A)])
	return lerpf(lerpf(cells[0], cells[1], wa), lerpf(cells[2], cells[3], wa), clampf(wt, 0.0, 1.0))


## Para la partida guardada: lo justo para rehacerlo con from_save.
static func to_save(wound: Dictionary) -> Dictionary:
	var f: Transform3D = wound.frame
	return {
		name = String(wound.name), thick = wound.thick, floor = wound.floor, deep = wound.deep,
		radii = [wound.radii.x, wound.radii.y], phase = wound.phase, rim = Array(wound.rim),
		frame = [f.basis.x.x, f.basis.x.y, f.basis.x.z, f.basis.y.x, f.basis.y.y, f.basis.y.z,
			f.basis.z.x, f.basis.z.y, f.basis.z.z, f.origin.x, f.origin.y, f.origin.z],
	}


## El bocado guardado [data] en [body] (Mesh_0 de [skeleton]), o {} si ya no casa.
static func from_save(skeleton: Skeleton3D, body: MeshInstance3D, data: Dictionary) -> Dictionary:
	var part_name := StringName(data.get("name", ""))
	var f: Array = data.get("frame", [])
	var radii: Array = data.get("radii", [])
	if body == null or body.skin == null or f.size() != 12 or radii.size() != 2:
		return {}
	var binds := _binds(skeleton, body.skin)
	if not binds.has(part_name):
		return {}
	var frame := Transform3D(Basis(Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5]), Vector3(f[6], f[7], f[8])),
		Vector3(f[9], f[10], f[11]))
	var wound := make(part_name, skeleton.find_bone(part_name), body.skin.get_bind_pose(binds[part_name]), frame,
		float(data.get("thick", 0.05)), float(radii[0]), float(radii[1]), float(data.get("floor", 0.02)),
		bool(data.get("deep", false)), float(data.get("phase", 0.0)))
	var rim: Array = data.get("rim", [])
	if rim.size() == SIDES:
		wound.rim = PackedFloat32Array(rim)
	return wound


## El cráter de [wound] (de region) en [skeleton], pegado a su hueso.
static func crater(skeleton: Skeleton3D, wound: Dictionary) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = ATTACHMENT_PREFIX + String(wound.name).trim_prefix(HumanRig.PREFIX)
	attachment.bone_idx = wound.bone
	attachment.set_meta(META, wound)
	skeleton.add_child(attachment, true)
	var node := MeshInstance3D.new()
	node.name = "Crater"
	node.mesh = build(wound)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	attachment.add_child(node)
	node.transform = wound.body_bind
	attachment.on_skeleton_update()
	return attachment


## La malla del cráter, en el espacio de la piel: el borde empapado, la carne y, si es hondo, el hueso.
static func build(wound: Dictionary) -> ArrayMesh:
	var frame: Transform3D = wound.frame
	var thick: float = wound.thick
	var floor_z: float = wound.floor
	var size := _rim_size(wound)
	var rx := size.x
	var ry := size.y
	# Cada bocado, con su desgarro (phase): los bultos de la carne y lo mordido del borde.
	var phase: float = wound.phase
	var rim: PackedFloat32Array = wound.rim
	var grid := []
	for i in RINGS + 1:
		var row := []
		var s := float(i) / RINGS
		for j in SIDES + 1:
			var theta := TAU * j / SIDES
			var ring := cos(s * PI * 0.5) * _tear(theta, s, phase)
			var x := cos(theta) * rx * ring
			var y := sin(theta) * ry * ring
			var bump := 0.08 * thick * sin(theta * 5.0 + s * 6.0 + phase) * sin(s * PI)
			row.append(Vector3(x, y, lerpf(rim[j % SIDES], floor_z, sin(s * PI * 0.5)) + bump))
		grid.append(row)
	var mesh := ArrayMesh.new()
	mesh.resource_name = "BiteWound"
	var lip_rings := maxi(1, roundi(RINGS * LIP))
	for kind in [&"blood", &"flesh"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var from := 0 if kind == &"blood" else lip_rings
		var to := lip_rings if kind == &"blood" else RINGS
		for i in range(from, to):
			for j in SIDES:
				var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
				for k in [0, 1, 2, 0, 2, 3]:
					var c: Array = quad[k]
					st.set_normal(frame.basis * _grid_normal(grid, c[0], c[1]))
					st.add_vertex(frame * (grid[c[0]][c[1]] as Vector3))
		st.set_material(HumanCarcass._material(kind))
		st.commit(mesh)
	if wound.deep:
		var bones := SurfaceTool.new()
		bones.begin(Mesh.PRIMITIVE_TRIANGLES)
		var r := minf(BONE_RADIUS, thick * 0.3)
		var points := []
		var widths := []
		for k in 5:
			var y := lerpf(-wound.radii.y * 1.2, wound.radii.y * 1.2, k / 4.0)
			points.append(frame * Vector3(0.0, y, 0.0))
			widths.append(r * (1.0 + 0.1 * sin(k * 2.0 + phase)))
		HumanCarcass._tube(bones, points, widths)
		bones.set_material(HumanCarcass._material(&"bone"))
		bones.commit(mesh)
	return mesh


## La normal de la carne en el punto [i][j] de la malla, mirando hacia fuera del hueco (+Z).
static func _grid_normal(grid: Array, i: int, j: int) -> Vector3:
	var row: Array = grid[i]
	var around: Vector3 = (row[(j + 1) % SIDES] as Vector3) - (row[(j - 1 + SIDES) % SIDES] as Vector3)
	var down: Vector3 = (grid[mini(i + 1, RINGS)][j] as Vector3) - (grid[maxi(i - 1, 0)][j] as Vector3)
	var n := around.cross(down)
	if n.length_squared() < 1e-12:
		return Vector3.BACK
	n = n.normalized()
	return n if n.z >= 0.0 else -n

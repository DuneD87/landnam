class_name FleshStrand
extends MeshInstance3D

## Una hebra de carne o un tendón entre dos puntos que se separan: la boca de una fiera que tira hacia
## atrás tras un bocado y la carne de la que tira (Devouring), o el muñón y el miembro recién arrancado
## que la fiera se lleva en la boca (PlayerRemains). Cuelga cuando está floja y adelgaza al estirarse;
## pasado [stretch] más de lo que medía (o al cabo de [life] s) se rompe: unas gotas, y cada mitad se
## recoge hacia su extremo, cayendo, hasta desaparecer. Si uno de los extremos se va (null o INF), se
## rompe también.
##
## Los extremos son Callables que dan cada fotograma un punto del mundo (on_bone, on_node, o lo que sea).
## La malla (un tubo por la curva) se rehace cada fotograma: unos pocos triángulos.

## Tramos y lados del tubo.
const SEGMENTS := 8
const HALF_SEGMENTS := 4
const SIDES := 5
## Lo más delgada que se queda al estirarse (fracción del grosor).
const MIN_THIN := 0.3
## Lo que tarda cada mitad en recogerse tras romperse (s), y lo que cae mientras (m).
const RETRACT := 0.35
const DROOP := 0.06
const FLESH := Color(0.32, 0.035, 0.035)

static var _material: StandardMaterial3D

var _a: Callable
var _b: Callable
var _radius := 0.005
var _rest := 0.05
var _snap_length := 0.2
var _life := 1.5
var _time := 0.0
var _snapped := false
var _snap_time := 0.0
## Al romperse: dónde (mundo) y por qué fracción de la hebra, y los extremos que tenía.
var _break_point := Vector3.ZERO
var _break_t := 0.5
var _last_a := Vector3.ZERO
var _last_b := Vector3.ZERO
var _im: ImmediateMesh
var _verts := PackedVector3Array()
var _normals := PackedVector3Array()


## Una hebra de [a] a [b] (Callables que dan un punto del mundo) de grosor [radius] (m), que se rompe
## al estirarse [stretch] m más de lo que mide ahora, o a los [life] s.
static func spawn(context: Node, a: Callable, b: Callable, radius: float, stretch: float, life := 1.5) -> FleshStrand:
	if context == null or not context.is_inside_tree():
		return null
	var host := context.get_tree().current_scene
	var from: Variant = a.call()
	var to: Variant = b.call()
	if host == null or not (from is Vector3) or not (to is Vector3) or from == Vector3.INF or to == Vector3.INF:
		return null
	var strand := FleshStrand.new()
	strand.name = "FleshStrand"
	strand._a = a
	strand._b = b
	strand._radius = radius
	strand._rest = maxf((from as Vector3).distance_to(to), 0.02)
	strand._snap_length = strand._rest + stretch
	strand._life = life
	strand._last_a = from
	strand._last_b = to
	strand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strand._im = ImmediateMesh.new()
	strand.mesh = strand._im
	host.add_child(strand)
	strand.global_position = from
	strand._draw()
	return strand


## Un extremo pegado al hueso [bone] de [skeleton], donde ahora está [point] (mundo).
static func on_bone(skeleton: Skeleton3D, bone: int, point: Vector3) -> Callable:
	var local := (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).affine_inverse() * point
	return func() -> Vector3:
		if not is_instance_valid(skeleton):
			return Vector3.INF
		return skeleton.global_transform * (skeleton.get_bone_global_pose(bone) * local)


## Un extremo pegado a [node] (con el desplazamiento de [point] respecto a él ahora, en su marco) que
## sigue a lo que el propio nodo diga con cut_point() si lo tiene (un SeveredLimb).
static func on_node(node: Node3D, point: Vector3) -> Callable:
	if node.has_method(&"cut_point"):
		var offset := point - (node.call(&"cut_point") as Vector3)
		return func() -> Vector3:
			return (node.call(&"cut_point") as Vector3) + offset if is_instance_valid(node) else Vector3.INF
	var local := node.global_transform.affine_inverse() * point
	return func() -> Vector3:
		return node.global_transform * local if is_instance_valid(node) else Vector3.INF


## Un extremo que sigue al marco que da [frame] (un Callable que da un Transform3D del mundo: la boca de
## una fiera), donde ahora está [point].
static func on_frame(frame: Callable, point: Vector3) -> Callable:
	var at: Transform3D = frame.call()
	var local := at.affine_inverse() * point
	return func() -> Vector3:
		var now: Variant = frame.call() if frame.is_valid() else null
		return (now as Transform3D) * local if now is Transform3D else Vector3.INF


func _process(delta: float) -> void:
	_time += delta
	var a := _point(_a)
	var b := _point(_b)
	if not _snapped:
		var gone := a == Vector3.INF or b == Vector3.INF
		if gone or a.distance_to(b) > _snap_length or _time > _life:
			_snap(_last_a if a == Vector3.INF else a, _last_b if b == Vector3.INF else b)
	else:
		_snap_time += delta
		if _snap_time > RETRACT + 0.1:
			queue_free()
			return
	if a != Vector3.INF:
		_last_a = a
	if b != Vector3.INF:
		_last_b = b
	_draw()


func _point(end: Callable) -> Vector3:
	if not end.is_valid():
		return Vector3.INF
	var p: Variant = end.call()
	return p if p is Vector3 else Vector3.INF


func _snap(a: Vector3, b: Vector3) -> void:
	_snapped = true
	_snap_time = 0.0
	_break_t = randf_range(0.3, 0.7)
	_break_point = _curve(a, b, _break_t)
	CombatFx.drip(self, _break_point, 3)


func _draw() -> void:
	_im.clear_surfaces()
	_verts.clear()
	_normals.clear()
	var a := _last_a
	var b := _last_b
	global_position = a
	if not _snapped:
		var length := a.distance_to(b)
		var thin := clampf(sqrt(_rest / maxf(length, _rest)), MIN_THIN, 1.0)
		var points: Array[Vector3] = []
		var radii: Array[float] = []
		for i in SEGMENTS + 1:
			var t := float(i) / SEGMENTS
			points.append(_curve(a, b, t))
			# Más delgada por el medio, por donde se estira.
			radii.append(_radius * lerpf(thin, 1.0, absf(t * 2.0 - 1.0) * 0.6))
		_tube(points, radii)
	else:
		# Cada mitad se recoge hacia su extremo, cayendo, y se afina hasta la punta.
		var k := clampf(_snap_time / RETRACT, 0.0, 1.0)
		var shrink := 1.0 - k * k
		for side in 2:
			var anchor := a if side == 0 else b
			var span := _break_t if side == 0 else 1.0 - _break_t
			if span * shrink < 0.02:
				continue
			var tip := anchor.lerp(_break_point, shrink) + CombatFx._down() * DROOP * k
			var points: Array[Vector3] = []
			var radii: Array[float] = []
			for i in HALF_SEGMENTS + 1:
				var t := float(i) / HALF_SEGMENTS
				var mid := anchor.lerp(tip, 0.5) + CombatFx._down() * DROOP * 0.5 * k
				points.append(_bezier(anchor, mid, tip, t))
				radii.append(_radius * MIN_THIN * (1.0 - t * 0.8) * (1.0 - k * 0.5))
			_tube(points, radii)
	if _verts.is_empty():
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _flesh())
	for i in _verts.size():
		_im.surface_set_normal(_normals[i])
		_im.surface_add_vertex(_verts[i])
	_im.surface_end()


## Un punto de la hebra entre [a] y [b] ([t] de 0 a 1): cuelga cuando está floja, recta si está tensa.
func _curve(a: Vector3, b: Vector3, t: float) -> Vector3:
	var length := a.distance_to(b)
	var sag := maxf(_rest * 1.2 - length, 0.0) * 0.6 + length * 0.06
	return _bezier(a, (a + b) * 0.5 + CombatFx._down() * sag, b, t)


static func _bezier(a: Vector3, c: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(c, t).lerp(c.lerp(b, t), t)


## Un tubo por [points] (mundo) con el grosor [radii] de cada uno, con tapa en la punta.
func _tube(points: Array[Vector3], radii: Array[float]) -> void:
	var origin := global_position
	var rings := []
	for i in points.size():
		var along := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)])
		if along.length_squared() < 1e-10:
			along = Vector3.UP
		along = along.normalized()
		var side := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(along)
		var ring := []
		for j in SIDES:
			var angle := TAU * j / SIDES
			var n := side * cos(angle) + up * sin(angle)
			ring.append([points[i] - origin + n * radii[i], n])
		rings.append(ring)
	for i in rings.size() - 1:
		for j in SIDES:
			var j1 := (j + 1) % SIDES
			var quad := [rings[i][j], rings[i + 1][j], rings[i + 1][j1], rings[i][j1]]
			for k in [0, 2, 1, 0, 3, 2]:
				_normals.append(quad[k][1])
				_verts.append(quad[k][0])


static func _flesh() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = FLESH
		_material.roughness = 0.3
		_material.clearcoat_enabled = true
		_material.clearcoat = 0.7
		_material.clearcoat_roughness = 0.2
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material

class_name GutPile
extends RefCounted

## Las vísceras de un animal destripado, en el suelo junto a él (Carcass.spill_guts): un
## montón de tripas enroscadas, la panza, el hígado, los pulmones y el corazón, húmedos y
## brillantes. La malla se hace una vez, a la escala de un ciervo (REFERENCE_RADIUS), y se escala
## al animal. Sale de golpe (como al tirar de ellas) y deja un charco de sangre. Cuelga del animal:
## sigue al origen flotante y se va con él.

const INTESTINE := &"intestine"
const STOMACH := &"stomach"
const LIVER := &"liver"
const LUNG := &"lung"
const HEART := &"heart"
## Radio del cuerpo (m) del animal para el que está hecha la malla.
const REFERENCE_RADIUS := 0.4
## Desde las de un pájaro (0,08 m de radio) hasta las de un mamut.
const SCALE_LIMITS := Vector2(0.15, 3.0)

static var _mesh: ArrayMesh


## Pone las vísceras de [npc] (un animal grande o uno pequeño) en el suelo, desde [point] hacia
## [side] (horizontal), para un cuerpo de [radius] m. Devuelve el nodo, o null si no hay suelo.
static func spawn(npc: Node3D, point: Vector3, side: Vector3, up: Vector3, radius: float) -> Node3D:
	var at := point + side * (radius * 0.6 + 0.1)
	var hit := Raycast.ground(npc, at, up, 1.5, 3.0, PhysicsLayers.WORLD)
	if hit.is_empty():
		return null
	var pile := MeshInstance3D.new()
	pile.name = "GutPile"
	pile.mesh = mesh()
	npc.add_child(pile)
	# Sobre el suelo tal como está: con su normal, no con la vertical.
	var ground_up: Vector3 = (hit.normal as Vector3).normalized()
	var forward := (side - ground_up * side.dot(ground_up)).normalized()
	var basis := Basis(ground_up.cross(forward).normalized(), ground_up, forward)
	var size := clampf(radius / REFERENCE_RADIUS, SCALE_LIMITS.x, SCALE_LIMITS.y)
	pile.global_transform = Transform3D(basis.scaled(Vector3.ONE * size * 0.3), hit.position)
	# Sale del vientre de golpe y se asienta.
	var tween := pile.create_tween()
	tween.tween_property(pile, "scale", pile.scale / 0.3, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# El charco, con la pila de blanco: el cadáver no se mancha (BloodStains busca un esqueleto).
	CombatFx.blood(pile, hit.position + up * 0.1, up, ItemData.DamageKind.BLUNT, 40.0 * size)
	return pile


static func mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = _build()
	return _mesh


static func _build() -> ArrayMesh:
	var b := ProcMesh.Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	# Las tripas: un tubo largo, enredado al azar sobre sí mismo dentro del montón y cada vez más
	# arriba, con pliegues apretados.
	var points := PackedVector3Array()
	var radii := PackedVector2Array()
	var steps := 260
	var heading := 0.0
	var turn := 0.0
	var at := Vector2(0.0, 0.0)
	for i in steps:
		var t := float(i) / steps
		turn = clampf(turn + rng.randf_range(-0.35, 0.35), -0.9, 0.9)
		heading += turn
		at += Vector2(cos(heading), sin(heading)) * 0.03
		# Dentro del montón: lo que se sale, se vuelve hacia el centro.
		var limit := Vector2(0.22, 0.15)
		if absf(at.x) > limit.x or absf(at.y) > limit.y:
			heading = lerp_angle(heading, atan2(-at.y, -at.x), 0.6)
		at = at.clamp(-limit, limit)
		var lift := 0.022 + 0.08 * t * (1.0 - at.length() / 0.3)
		points.append(Vector3(at.x - 0.04, maxf(lift, 0.022), at.y))
		radii.append(Vector2(0.021, 0.019) * (0.9 + 0.2 * sin(t * 40.0)))
	ProcMesh.tube(b.st(INTESTINE), points, radii, 7)
	# La panza: un saco grande y algo caído, a un lado.
	_blob(b.st(STOMACH), Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.2, 0.09, -0.05)), Vector3(0.15, 0.09, 0.12), 0.18, rng)
	# El hígado: un lóbulo oscuro y aplastado encima.
	_blob(b.st(LIVER), Transform3D(Basis(Vector3.UP, -0.6) * Basis(Vector3.RIGHT, 0.25), Vector3(-0.02, 0.13, 0.11)),
		Vector3(0.12, 0.028, 0.08), 0.12, rng)
	# Los pulmones, dos lóbulos rosados, y el corazón entre ellos.
	for s in [-1.0, 1.0]:
		_blob(b.st(LUNG), Transform3D(Basis(Vector3.UP, 0.3 * s), Vector3(-0.24 + 0.02 * s, 0.05, 0.05 * s)),
			Vector3(0.08, 0.045, 0.055), 0.2, rng)
	_blob(b.st(HEART), Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(-0.2, 0.08, 0.0)), Vector3(0.04, 0.05, 0.035), 0.08, rng)
	return b.commit(_material)


## Un bulto blando: una esfera de [radii] (m) con [bumps] de abolladura, en [xform].
static func _blob(st: SurfaceTool, xform: Transform3D, radii: Vector3, bumps: float, rng: RandomNumberGenerator) -> void:
	var rings := 10
	var segments := 14
	var phase := rng.randf() * TAU
	var base := ProcMesh.vertex_count(st)
	for i in rings + 1:
		var v := float(i) / rings
		var lat := PI * (v - 0.5)
		for j in segments + 1:
			var u := float(j) / segments
			var lon := TAU * u
			var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var dent := 1.0 + bumps * (0.5 * sin(lon * 3.0 + phase) * cos(lat * 2.0) + 0.3 * sin(lat * 5.0 + phase))
			# Aplastado por abajo contra el suelo.
			var p := dir * radii * dent
			p.y = maxf(p.y, -radii.y * 0.55)
			ProcMesh.emit(st, Vector2(u * 2.0, v), xform * p)
	for i in rings:
		for j in segments:
			var a := base + i * (segments + 1) + j
			var c := a + segments + 1
			st.add_index(a)
			st.add_index(c)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(c)
			st.add_index(c + 1)


## Húmedo: brillo de capa transparente sobre cada víscera.
static func _material(kind: StringName) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = String(kind)
	match kind:
		INTESTINE:
			# Gris rosado sucio de sangre, con vetas de grasa.
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.28, 0.15, 0.14), Color(0.48, 0.3, 0.27), 7.0, 71)
			mat.roughness = 0.3
		STOMACH:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.3, 0.24, 0.2), Color(0.46, 0.38, 0.3), 4.0, 73)
			mat.roughness = 0.35
		LIVER:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.09, 0.015, 0.015), Color(0.19, 0.035, 0.03), 3.0, 79)
			mat.roughness = 0.2
		LUNG:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.34, 0.13, 0.13), Color(0.52, 0.24, 0.23), 9.0, 83)
			mat.roughness = 0.45
		HEART:
			mat.albedo_texture = ProcMesh.noise_texture(Color(0.13, 0.02, 0.02), Color(0.25, 0.05, 0.04), 4.0, 89)
			mat.roughness = 0.25
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.7
	mat.clearcoat_roughness = 0.12
	return mat

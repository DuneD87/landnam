class_name CombatFx
extends RefCounted

## Efectos de combate: sangre, polvo de impacto y sonidos. El proyecto no trae audio de combate,
## así que los sonidos se sintetizan una vez (ruido filtrado, golpes graves, cuerda) y se sirven
## por AudioManager con su reparto de voces y distancias, como cualquier otro evento.

const RATE := 22050

static var _events: Dictionary = {}
static var _droplet_mesh: QuadMesh
static var _mist_mesh: QuadMesh
static var _shrink: CurveTexture
static var _mist_grow: CurveTexture
static var _mist_fade: GradientTexture1D

const DROPLET_SHADER := preload("res://shaders/combat/blood_droplet.gdshader")
const MIST_SHADER := preload("res://shaders/combat/blood_mist.gdshader")


## Suena el efecto [id] en [pos]. opts se pasa a AudioManager (pitch, volume_offset_db…).
static func play(id: StringName, pos: Vector3, opts: Dictionary = {}) -> void:
	var ev := _event(id)
	if ev == null:
		return
	AudioManager.play_event_3d(ev, pos, opts)


## Sangre de un golpe que entra por [point] en el sentido [direction]: gotas que caen con la gravedad
## del planeta, una neblina fina, manchas en el suelo donde caen y una mancha en el cuerpo
## (BloodStains). Cada tipo de golpe salpica a su manera: un tajo, muchas gotas rápidas en abanico;
## una estocada, un chorro estrecho; un golpe contundente, pocas gotas y más neblina. [amount] (el
## daño) da la cantidad. (La nube del hábitat queda para la muerte de la fauna pequeña.)
static func blood(target: Node, point: Vector3, direction: Vector3,
		kind := ItemData.DamageKind.SLASH, amount := 25.0) -> void:
	if SettingsManager.gore_level() == SettingsManager.GORE_OFF:
		return
	var host := _host(target)
	if host == null:
		return
	var dir := direction.normalized() if direction.length_squared() > 1e-6 else -_down()
	var power := clampf(amount / 25.0, 0.6, 2.0)
	# Gotas, goterones (pocos, gordos y lentos: la sangre se ve espesa) y neblina.
	match kind:
		ItemData.DamageKind.PIERCE:
			_droplets(host, point, dir, int(50 * power), 12.0, Vector2(3.5, 8.5), Vector2(0.7, 1.4))
			_droplets(host, point, dir, int(4 * power), 18.0, Vector2(1.5, 3.5), Vector2(2.0, 3.2), 1.2)
			_mist(host, point, dir, int(8 * power))
		ItemData.DamageKind.BLUNT:
			_droplets(host, point, dir, int(30 * power), 75.0, Vector2(1.5, 4.0), Vector2(0.8, 1.6))
			_droplets(host, point, dir, int(6 * power), 60.0, Vector2(0.8, 2.5), Vector2(2.0, 3.5), 1.2)
			_mist(host, point, dir, int(20 * power))
			power *= 0.7
		_:
			_droplets(host, point, dir, int(80 * power), 38.0, Vector2(2.5, 7.0), Vector2(0.8, 1.7))
			_droplets(host, point, dir, int(8 * power), 30.0, Vector2(1.0, 3.0), Vector2(2.0, 3.5), 1.2)
			_mist(host, point, dir, int(14 * power))
	_ground_splats(target, point, dir, power)
	BloodStains.stain(target, point, dir, power)
	# Salpica las matas de alrededor, a la altura del golpe.
	BloodFoliage.add(point + dir * 0.3, 0.5 * power)


## Al cercenar un miembro: un chorro grande y abierto desde el muñón ([direction], hacia fuera).
static func sever_burst(target: Node, point: Vector3, direction: Vector3) -> void:
	var host := _host(target)
	if host == null or SettingsManager.gore_level() == SettingsManager.GORE_OFF:
		return
	var dir := direction.normalized() if direction.length_squared() > 1e-6 else -_down()
	_droplets(host, point, dir, 160, 50.0, Vector2(2.0, 7.0), Vector2(1.0, 2.2), 1.2)
	_droplets(host, point, dir, 20, 40.0, Vector2(1.0, 3.5), Vector2(2.5, 4.0), 1.3)
	_mist(host, point, dir, 24)
	_ground_splats(target, point, dir, 2.0)
	BloodFoliage.add(point + dir * 0.4, 1.0)
	play(&"hit_blunt", point, {"pitch": randf_range(0.65, 0.75)})


## Un borbotón de una herida abierta (un muñón, a cada latido): [strength] 0..1, de goteo a chorro.
static func spurt(target: Node, point: Vector3, direction: Vector3, strength: float) -> void:
	var host := _host(target)
	if host == null or SettingsManager.gore_level() == SettingsManager.GORE_OFF:
		return
	var s := clampf(strength, 0.0, 1.0)
	var dir := direction.normalized() if direction.length_squared() > 1e-6 else -_down()
	_droplets(host, point, dir, int(lerpf(10.0, 40.0, s)), lerpf(28.0, 12.0, s),
		Vector2(0.4, 1.0) * lerpf(1.0, 3.2, s), Vector2(0.8, 1.6), 0.9)
	_droplets(host, point, dir, int(lerpf(1.0, 5.0, s)), 15.0, Vector2(0.3, 1.0) * lerpf(1.0, 2.5, s),
		Vector2(2.0, 3.0), 1.0)


## Golpe contra algo: sonido según el tipo de golpe y, si no es carne, polvo.
static func impact(node: Node, point: Vector3, kind: ItemData.DamageKind, flesh: bool) -> void:
	if flesh:
		play(&"hit_blunt" if kind == ItemData.DamageKind.BLUNT else &"hit_flesh", point,
			{"pitch": randf_range(0.9, 1.1)})
	else:
		play(&"hit_world", point, {"pitch": randf_range(0.85, 1.15)})
		var host := _host(node)
		if host != null:
			_spray(host, point, -_down(), Color(0.45, 0.40, 0.34), 10, 0.06)


static func _host(node: Node) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().current_scene


static func _down() -> Vector3:
	var p := GameManager.player
	if p != null and is_instance_valid(p) and "gravity_direction" in p:
		return (p.gravity_direction as Vector3).normalized()
	return Vector3.DOWN


static func _spray(host: Node, point: Vector3, direction: Vector3, color: Color, amount: int,
		size: float, speed := Vector2(1.5, 4.5), spread := 40.0) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = 0.8
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	var dir := direction.normalized() if direction.length_squared() > 1e-6 else -_down()
	process.direction = dir
	process.spread = spread
	process.initial_velocity_min = speed.x
	process.initial_velocity_max = speed.y
	process.gravity = _down() * 9.8
	process.scale_min = 0.6
	process.scale_max = 1.4
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.05
	process.damping_min = 0.5
	process.damping_max = 1.5
	particles.process_material = process
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.35 if color.r > color.g * 2.0 else 0.95
	mesh.material = mat
	particles.draw_pass_1 = mesh
	particles.visibility_aabb = AABB(Vector3.ONE * -3.0, Vector3.ONE * 6.0)
	host.add_child(particles)
	particles.global_position = point
	particles.add_to_group(&"floating_origin")
	particles.emitting = true
	particles.get_tree().create_timer(1.6).timeout.connect(particles.queue_free)


## Gotas de sangre: lágrimas alineadas con su velocidad (blood_droplet.gdshader) que salen de una
## franja corta atravesada al golpe (el tajo abre en abanico) hacia [dir] con [spread] grados, caen
## con la gravedad del planeta y se encogen al final, cuando ya han llegado al suelo.
static func _droplets(host: Node, point: Vector3, dir: Vector3, amount: int, spread: float,
		speed: Vector2, scale: Vector2, lifetime := 0.9) -> void:
	if amount <= 0:
		return
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.randomness = 0.3
	particles.local_coords = false
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	# En el marco del emisor (ver _frame): +Y es [dir] y +X la franja de la que salen.
	process.direction = Vector3.UP
	process.spread = spread
	process.initial_velocity_min = speed.x
	process.initial_velocity_max = speed.y
	process.gravity = _down() * 9.8
	process.damping_min = 0.2
	process.damping_max = 0.8
	process.scale_min = scale.x
	process.scale_max = scale.y
	process.scale_curve = _shrink_curve()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.06, 0.01, 0.03)
	particles.process_material = process
	particles.draw_pass_1 = _droplet()
	particles.visibility_aabb = AABB(Vector3.ONE * -4.0, Vector3.ONE * 8.0)
	host.add_child(particles)
	particles.global_transform = Transform3D(_frame(dir), point)
	particles.add_to_group(&"floating_origin")
	particles.emitting = true
	particles.get_tree().create_timer(lifetime + 0.8).timeout.connect(particles.queue_free)


## Neblina: unas manchas suaves que salen despacio, crecen y se desvanecen (blood_mist.gdshader).
static func _mist(host: Node, point: Vector3, dir: Vector3, amount: int) -> void:
	if amount <= 0:
		return
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = 1.2
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.randomness = 0.4
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 70.0
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 1.4
	process.damping_min = 2.0
	process.damping_max = 4.0
	process.gravity = _down() * 0.6
	process.scale_min = 0.25
	process.scale_max = 0.55
	process.scale_curve = _mist_grow_curve()
	process.color_ramp = _mist_fade_ramp()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.05
	particles.process_material = process
	particles.draw_pass_1 = _mist_quad()
	particles.visibility_aabb = AABB(Vector3.ONE * -2.0, Vector3.ONE * 4.0)
	host.add_child(particles)
	particles.global_transform = Transform3D(_frame(dir), point)
	particles.add_to_group(&"floating_origin")
	particles.emitting = true
	particles.get_tree().create_timer(2.2).timeout.connect(particles.queue_free)


## Manchas en el suelo donde caen las gotas: por delante del golpe, un poco después.
static func _ground_splats(target: Node, point: Vector3, dir: Vector3, power: float) -> void:
	var body := target as Node3D
	if body == null or not body.is_inside_tree():
		return
	var down := _down()
	var flat := dir - down * dir.dot(down)
	flat = flat.normalized() if flat.length_squared() > 1e-4 else Vector3.ZERO
	var side := flat.cross(down)
	var mask := _ground_mask()
	for i in 2 + int(power * 1.5):
		var at := point + flat * randf_range(0.2, 1.6) * power + side * randf_range(-0.45, 0.45)
		var size := randf_range(0.4, 0.7) * clampf(power, 0.7, 1.6)
		body.get_tree().create_timer(randf_range(0.2, 0.45)).timeout.connect(func() -> void:
			if is_instance_valid(body) and body.is_inside_tree():
				BloodPool.spawn(body, at, down * 9.8, size, 0.2, mask, true))


## Lo que cuenta como suelo para la sangre: con lo que choca el jugador (terreno y construcciones).
static func _ground_mask() -> int:
	var p := GameManager.player
	if p != null and is_instance_valid(p) and "collision_mask" in p:
		return p.collision_mask
	return 1


## Marco del emisor: +Y hacia [dir] y +X de través, a lo ancho.
static func _frame(dir: Vector3) -> Basis:
	var across := dir.cross(_down())
	if across.length_squared() < 1e-4:
		across = dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD)
	across = across.normalized()
	return Basis(across, dir, across.cross(dir))


static func _droplet() -> QuadMesh:
	if _droplet_mesh == null:
		_droplet_mesh = QuadMesh.new()
		_droplet_mesh.size = Vector2(0.022, 0.07)
		var mat := ShaderMaterial.new()
		mat.shader = DROPLET_SHADER
		_droplet_mesh.material = mat
	return _droplet_mesh


static func _mist_quad() -> QuadMesh:
	if _mist_mesh == null:
		_mist_mesh = QuadMesh.new()
		_mist_mesh.size = Vector2.ONE
		var mat := ShaderMaterial.new()
		mat.shader = MIST_SHADER
		_mist_mesh.material = mat
	return _mist_mesh


static func _shrink_curve() -> CurveTexture:
	if _shrink == null:
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(0.7, 1.0))
		curve.add_point(Vector2(1.0, 0.0))
		_shrink = CurveTexture.new()
		_shrink.curve = curve
	return _shrink


static func _mist_grow_curve() -> CurveTexture:
	if _mist_grow == null:
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.4))
		curve.add_point(Vector2(1.0, 1.0))
		_mist_grow = CurveTexture.new()
		_mist_grow.curve = curve
	return _mist_grow


static func _mist_fade_ramp() -> GradientTexture1D:
	if _mist_fade == null:
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
		ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0.0)])
		_mist_fade = GradientTexture1D.new()
		_mist_fade.gradient = ramp
	return _mist_fade


# ---------------------------------------------------------------------------------------------
# Sonido sintetizado


static func _event(id: StringName) -> SoundEvent:
	if _events.has(id):
		return _events[id]
	var ev := SoundEvent.new()
	ev.event_id = StringName("combat_" + String(id))
	ev.bus = "SFX"
	ev.pitch_jitter = 0.06
	ev.max_voices = 6
	ev.cooldown = 0.03
	match id:
		&"swing_windup":
			ev.streams = [_whoosh(0.30, 350.0, 1900.0, 0.45)]
			ev.volume_db = -8.0
		&"bear_swipe":
			ev.streams = [_whoosh(0.45, 180.0, 900.0, 0.8)]
			ev.volume_db = -2.0
			ev.max_distance = 50.0
		&"throw":
			ev.streams = [_whoosh(0.35, 220.0, 1100.0, 0.6)]
			ev.volume_db = -5.0
		&"dodge":
			ev.streams = [_rustle(0.38)]
			ev.volume_db = -10.0
		&"hit_flesh":
			ev.streams = [_thump(0.24, 120.0, 55.0, 0.55, 900.0)]
			ev.volume_db = -1.0
		&"hit_blunt":
			ev.streams = [_thump(0.30, 85.0, 42.0, 0.35, 500.0)]
			ev.volume_db = 0.0
		&"hit_world":
			ev.streams = [_thump(0.14, 220.0, 150.0, 0.8, 2500.0)]
			ev.volume_db = -8.0
		&"bow_release":
			ev.streams = [_twang(0.4, 196.0)]
			ev.volume_db = -4.0
		&"player_hurt":
			ev.streams = [_grunt(0.22, 150.0)]
			ev.volume_db = -3.0
			ev.cooldown = 0.2
		&"player_death":
			ev.streams = [_grunt(0.7, 110.0)]
			ev.volume_db = 0.0
		&"bear_roar":
			ev.streams = [_roar(1.4, 82.0)]
			ev.volume_db = 2.0
			ev.max_distance = 90.0
			ev.cooldown = 1.0
		&"bear_growl":
			ev.streams = [_roar(0.7, 64.0)]
			ev.volume_db = -2.0
			ev.max_distance = 60.0
			ev.cooldown = 0.5
		&"heartbeat":
			ev.streams = [_heartbeat()]
			ev.volume_db = -2.0
			ev.pitch_jitter = 0.0
			ev.cooldown = 0.25
		&"lock":
			ev.streams = [_click(0.08, 1250.0)]
			ev.volume_db = -14.0
		_:
			return null
	_events[id] = ev
	return ev


static func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	var peak := 0.001
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain := minf(0.9 / peak, 4.0)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## Filtro de variable de estado (paso banda) sobre ruido con la frecuencia barriendo: el silbido
## de algo que corta el aire.
static func _whoosh(duration: float, f_lo: float, f_hi: float, amp: float) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var band := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in n:
		var t := float(i) / n
		var env := pow(sin(PI * t), 2.0) * (1.0 - 0.3 * t)
		var f := lerpf(f_lo, f_hi, sin(PI * t * 0.8))
		var k := 2.0 * sin(PI * f / RATE)
		var x := rng.randf_range(-1.0, 1.0)
		low += k * band
		var high := x - low - 0.5 * band
		band += k * high
		out[i] = band * env * amp
	return _to_stream(out)


static func _rustle(duration: float) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var t := float(i) / n
		var env := minf(t / 0.12, 1.0) * pow(1.0 - t, 1.5)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.25
		out[i] = lp * env * (0.7 + 0.3 * sin(t * 60.0))
	return _to_stream(out)


## Golpe sordo: seno que cae de tono y ruido corto filtrado (el chasquido del contacto).
static func _thump(duration: float, f0: float, f1: float, noise_amt: float, noise_cut: float) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp := 0.0
	var a := clampf(2.0 * PI * noise_cut / RATE, 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var s := float(i) / RATE
		var f := lerpf(f0, f1, minf(s / duration, 1.0))
		phase += TAU * f / RATE
		var body := sin(phase) * exp(-s * 22.0)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * a
		var crack := lp * exp(-s * 45.0) * noise_amt * 2.0
		out[i] = body + crack
	return _to_stream(out)


## Cuerda de arco: armónicos que se apagan deprisa con un leve descenso de tono y el chasquido
## de la cuerda al llegar al tope.
static func _twang(duration: float, f0: float) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in n:
		var s := float(i) / RATE
		var f := f0 * (1.0 - 0.08 * minf(s / 0.1, 1.0))
		phase += TAU * f / RATE
		var tone := (sin(phase) + 0.5 * sin(phase * 2.0) + 0.25 * sin(phase * 3.0) + 0.12 * sin(phase * 5.0))
		var v := tone * exp(-s * 13.0) * 0.6 + rng.randf_range(-1.0, 1.0) * exp(-s * 90.0) * 0.8
		out[i] = v
	return _to_stream(out)


## Quejido corto: diente de sierra grave con dos formantes aproximados.
static func _grunt(duration: float, f0: float) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / n
		var s := float(i) / RATE
		var f := f0 * (1.0 + 0.15 * sin(PI * t)) * (1.0 - 0.2 * t)
		phase = fmod(phase + f / RATE, 1.0)
		var saw := phase * 2.0 - 1.0
		lp1 += (saw - lp1) * 0.12
		lp2 += (lp1 - lp2) * 0.2
		var env := minf(s / 0.02, 1.0) * pow(1.0 - t, 1.4)
		out[i] = (lp2 * 1.4 + (lp1 - lp2) * 0.6) * env
	return _to_stream(out)


## Rugido: sierra grave con vibrato lento, un temblor rápido (la garganta) y aire filtrado.
static func _roar(duration: float, f0: float) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp := 0.0
	var lp2 := 0.0
	var nlp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	for i in n:
		var t := float(i) / n
		var s := float(i) / RATE
		var f := f0 * (1.0 + 0.25 * sin(PI * t) + 0.04 * sin(TAU * 5.0 * s))
		phase = fmod(phase + f / RATE, 1.0)
		var saw := phase * 2.0 - 1.0
		var growl := 0.55 + 0.45 * sin(TAU * 27.0 * s + sin(TAU * 3.0 * s))
		lp += (saw * growl - lp) * 0.10
		lp2 += (lp - lp2) * 0.25
		nlp += (rng.randf_range(-1.0, 1.0) - nlp) * 0.18
		var env := minf(t / 0.12, 1.0) * minf((1.0 - t) / 0.35, 1.0)
		out[i] = (lp2 * 1.6 + nlp * 0.45 * growl) * env
	return _to_stream(out)


## Latido: dos golpes graves ("pum-pum"), el segundo más flojo, con el roce sordo de la sangre.
static func _heartbeat() -> AudioStreamWAV:
	var n := int(0.55 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i in n:
		var s := float(i) / RATE
		var v := 0.0
		for beat in [[0.0, 1.0, 58.0], [0.17, 0.6, 50.0]]:
			var t: float = s - beat[0]
			if t >= 0.0:
				var f: float = beat[2] * (1.0 - 0.25 * minf(t / 0.12, 1.0))
				v += sin(TAU * f * t) * exp(-t * 18.0) * minf(t / 0.008, 1.0) * beat[1]
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.03
		out[i] = v + lp * exp(-s * 6.0) * 0.4
	return _to_stream(out)


static func _click(duration: float, f: float) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var s := float(i) / RATE
		out[i] = sin(TAU * f * s) * exp(-s * 55.0)
	return _to_stream(out)

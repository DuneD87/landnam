class_name CombatFx
extends RefCounted

## Efectos de combate: sangre, polvo de impacto y sonidos. El proyecto no trae audio de combate,
## así que los sonidos se sintetizan una vez (ruido filtrado, golpes graves, cuerda) y se sirven
## por AudioManager con su reparto de voces y distancias, como cualquier otro evento.

const RATE := 22050

static var _events: Dictionary = {}
static var _blood_process: ParticleProcessMaterial
static var _blood_mesh: Mesh
static var _dust_mesh: Mesh


## Suena el efecto [id] en [pos]. opts se pasa a AudioManager (pitch, volume_offset_db…).
static func play(id: StringName, pos: Vector3, opts: Dictionary = {}) -> void:
	var ev := _event(id)
	if ev == null:
		return
	AudioManager.play_event_3d(ev, pos, opts)


## Sangre en el punto del golpe: un chorro que sale en el sentido del golpe y cae con la
## gravedad del planeta. (La nube del hábitat queda para la muerte.)
static func blood(target: Node, point: Vector3, direction: Vector3) -> void:
	var host := _host(target)
	if host == null:
		return
	_spray(host, point, direction, Color(0.36, 0.015, 0.015), 34, 0.018)


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
		size: float) -> void:
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
	process.spread = 40.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 4.5
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


static func _click(duration: float, f: float) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var s := float(i) / RATE
		out[i] = sin(TAU * f * s) * exp(-s * 55.0)
	return _to_stream(out)

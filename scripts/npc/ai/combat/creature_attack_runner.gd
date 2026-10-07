class_name CreatureAttackRunner
extends RefCounted

## Ejecuta un CreatureAttack de principio a fin para una criatura, sea cual sea el estado que lo
## lanza:
##   - aviso: se planta [member CreatureAttack.tell] segundos y arranca la animación, lenta hasta
##     poco antes del primer golpe;
##   - seguimiento: hasta comprometerse gira hacia el objetivo a track_windup grados/s, apuntando
##     a donde estará (lead); comprometida, solo a track_active, así que apartarse a tiempo
##     funciona y hacerlo pronto no;
##   - avance: la embestida del lunge, que se frena para no pasarse del objetivo;
##   - golpes: en cada ventana, los huesos hieren por colisión (esferas barridas entre fotogramas
##     contra los Hurtbox), cada cuerpo una vez por ventana;
##   - armadura: en su tramo, los golpes que encaja gastan primero la guardia extra del ataque.
## Mientras corre, manda en el cuerpo: controller.desired_direction, desired_facing, turn_rate y
## movement.speed.

## Cuánto antes del primer golpe deja el aviso lento y pasa al ritmo del golpe (s de animación).
const WINDUP_LEAD := 0.12
## Lo que se aleja como mucho el punto al que apunta de donde está el objetivo (m).
const MAX_LEAD_OFFSET := 3.0

var attack: CreatureAttack
## Tiempo de la animación (s, a ritmo 1).
var time: float = 0.0
## Cuerpos golpeados en este ataque.
var landed: int = 0

var _npc: NPCController
var _controller: AIController
var _profile: CreatureCombatProfile
var _channel: CreatureActionChannel
var _skeleton: Skeleton3D
var _bone_cache: Dictionary = {}
var _tell: float = 0.0
var _armor_left: float = 0.0
## Un barrido por hueso de cada ventana: [ventana][hueso].
var _sweeps: Array = []


func _init(npc: NPCController, profile: CreatureCombatProfile) -> void:
	_npc = npc
	_controller = npc.ai_controller
	_profile = profile
	_skeleton = npc.get_skeleton()


## Empieza [next]. [chained]: sigue a otro ataque sin plantarse a avisar; la animación se funde
## sobre la del anterior.
func start(next: CreatureAttack, chained: bool = false) -> void:
	attack = next
	time = 0.0
	landed = 0
	_tell = 0.0 if chained else next.tell
	_armor_left = next.armor.z
	_channel = _npc.get_action_channel()
	_sweeps.clear()
	for hit in next.hits:
		var per_bone: Array[MeleeSweep] = []
		for bone in hit.bones:
			var sweep := MeleeSweep.new(hit.radius)
			for box in _npc.hurtboxes:
				sweep.exclude.append(box.get_rid())
			per_bone.append(sweep)
		_sweeps.append(per_bone)
	var sound := next.sound if next.sound != &"" else _profile.attack_sound
	if sound != &"":
		CombatFx.play(sound, _npc.global_position, {"pitch": randf_range(0.9, 1.1) * _profile.voice_pitch})
	if _tell <= 0.0:
		_play_anim()


func is_running() -> bool:
	return attack != null


## Si aún está en el aviso, plantado antes de arrancar la animación.
func in_tell() -> bool:
	return attack != null and _tell > 0.0


## Si ya hiere o ha herido: la preparación ha acabado.
func past_windup() -> bool:
	return attack != null and _tell <= 0.0 and time >= attack.first_hit()


## Cuándo se abre la siguiente ventana de golpe (s de animación), o -1 si ya no quedan.
func next_hit_time() -> float:
	if attack == null:
		return -1.0
	for hit in attack.hits:
		if hit.from > time:
			return hit.from
	return -1.0


## Si ya puede encadenar otro ataque.
func can_chain() -> bool:
	return attack != null and _tell <= 0.0 and time >= attack.chain_time()


## Lo que queda de un golpe de [poise] de desgaste tras gastar la armadura del ataque, si está en
## su tramo.
func absorb_poise(poise: float) -> float:
	if attack == null or _armor_left <= 0.0 or time < attack.armor.x or time > attack.armor.y:
		return poise
	var used := minf(_armor_left, poise)
	_armor_left -= used
	return poise - used


## Corta el ataque (tambaleo, muerte, cambio de estado) y suelta la animación.
func cancel() -> void:
	if attack == null:
		return
	attack = null
	if _channel != null:
		_channel.stop()


## Avanza el ataque. Devuelve false cuando ha acabado.
func update(delta: float) -> bool:
	if attack == null:
		return false
	var movement := _controller.movement
	movement.speed = AIController.TURN_ONLY_SPEED
	if _tell > 0.0:
		_tell -= delta
		_face(attack.track_windup)
		if _tell <= 0.0:
			_play_anim()
		return true
	var first_hit := attack.first_hit()
	var speed := attack.windup_speed if time < first_hit - WINDUP_LEAD else attack.speed
	if _channel != null:
		_channel.set_speed(speed)
	var prev := time
	time += delta * speed
	_face(attack.track_active if time >= attack.commit_time() else attack.track_windup)
	var lunge := attack.lunge
	if lunge.z > 0.0 and lunge.y > lunge.x and time >= lunge.x and prev <= lunge.y:
		var full := lunge.z / ((lunge.y - lunge.x) / maxf(attack.speed, 0.01))
		var room := INF
		if attack.lunge_min_distance > 0.0:
			room = maxf(0.0, _controller.distance_to_target() - attack.lunge_min_distance)
		var left := maxf((lunge.y - time) / maxf(attack.speed, 0.01), delta)
		movement.speed = maxf(minf(full, room / left), AIController.TURN_ONLY_SPEED)
		_controller.desired_direction = _forward()
	for i in attack.hits.size():
		var hit := attack.hits[i]
		if time >= hit.from and prev <= hit.to:
			if prev < hit.from:
				var sound := hit.sound if hit.sound != &"" else _profile.swing_sound
				if sound != &"":
					CombatFx.play(sound, _npc.global_position)
			_sweep_hit(hit, _sweeps[i])
			# Una parada corta el ataque en mitad del barrido (on_parried → cancel()).
			if attack == null:
				return false
	if time >= attack.end:
		cancel()
		return false
	return true


func _play_anim() -> void:
	if _channel != null:
		_channel.play(attack.anim, attack.windup_speed, _profile.action_fade_in, _profile.action_fade_out)


## Mira hacia donde estará el objetivo, girando como mucho [rate] grados/s (0 = no gira).
func _face(rate: float) -> void:
	if rate <= 0.0:
		_controller.desired_facing = _forward()
		_controller.turn_rate = 0.001
		return
	var aim := _controller.predicted_target_position(attack.lead, MAX_LEAD_OFFSET)
	var dir := _controller.project_on_gravity_plane(aim - _npc.global_position)
	_controller.desired_facing = dir if dir != Vector3.ZERO else _forward()
	_controller.turn_rate = rate


func _forward() -> Vector3:
	return _controller.project_on_gravity_plane(_npc.global_basis.z)


func _sweep_hit(hit: CreatureHit, sweeps: Array) -> void:
	var space := _npc.get_world_3d().direct_space_state
	for i in hit.bones.size():
		var point := _bone_world(hit.bones[i])
		if point == Vector3.INF:
			continue
		var sweep: MeleeSweep = sweeps[i]
		for result in sweep.sweep_point(space, point):
			var box: Hurtbox = result.hurtbox
			for other in sweeps:
				(other as MeleeSweep).mark_hit(box.owner_body)
			if box.owner_body == _npc:
				continue
			var dir := _controller.project_on_gravity_plane(box.owner_body.global_position - _npc.global_position)
			var info := DamageInfo.create(hit.damage, _npc, result.point, dir, hit.poise)
			info.kind = hit.kind
			info.knockback = hit.knockback
			info.parryable = hit.parryable
			# Lo parado con la guardia ni sangra ni suena a carne: suena la guardia (Guard).
			if box.receive(info) > 0.0 and info.guarded != Guard.Result.BLOCKED:
				landed += 1
				CombatFx.blood(box.owner_body, result.point, dir, hit.kind, hit.damage)
				CombatFx.impact(_npc, result.point, hit.kind, true)
			if attack == null:
				return


func _bone_world(bone: StringName) -> Vector3:
	if _skeleton == null:
		return Vector3.INF
	if not _bone_cache.has(bone):
		_bone_cache[bone] = _skeleton.find_bone(bone)
	var idx: int = _bone_cache[bone]
	if idx < 0:
		return Vector3.INF
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(idx).origin

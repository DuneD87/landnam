class_name Devouring
extends Node

## Morir a manos de una fiera que come carne (CreatureCombatProfile.feed_anims). El cuerpo cae como
## siempre (Ragdoll) y, ya asentado, pasa a ser unos restos que se quedan en el mundo
## (PlayerRemains). La fiera que lo ha matado, y las de su manada que peleaban con él, van a
## comérselo (NPCController.feed_on, FeedState). Mientras comen (EAT_TIME, más deprisa cuantas más
## son) lo descuartizan:
##   - cada bocado (BITE_EVERY) desgarra y salpica, mancha el cuerpo y le da un tirón hacia la fiera;
##   - le arrancan uno tras otro los brazos y las piernas que le queden (entre TEARS), empezando por
##     el que tienen más cerca; lo arrancado cae y se queda;
##   - a media comida le abren el vientre y el pecho (la canal: PlayerRemains.open_torso) y le sacan
##     las vísceras (GUTS_AT);
##   - mientras vive grita (player_agony, y entre medias quejidos), cada vez más débil (SCREAM_EVERY),
##     hasta su estertor (player_gurgle, DEATH_AT).
## La cámara lo mira todo de cine (CameraController.cinematic), girando despacio alrededor.
## El tiempo solo corre mientras alguna come: si no llega ninguna, o dejan de comer, en GIVE_UP
## segundos se queda como esté. Saltarlo (skip) lo acaba de golpe, a oscuras: lo que faltaba por
## arrancar ya se lo han comido. Con menos gore (SettingsManager.gore_level) no hay despiece
## (GORE_BLOOD), ni sangre ni desgarros (GORE_OFF): la fiera comiendo y los gritos.

const EAT_TIME := Vector2(6.0, 9.0)
const BITE_EVERY := Vector2(0.55, 1.1)
const TEARS := Vector2(0.18, 0.82)
const GUTS_AT := 0.5
const SCREAM_EVERY := Vector2(0.9, 1.8)
## El primer grito, el que más alto, y los que van más bajos (dB); y cuántos son de agonía (los demás,
## quejidos).
const SCREAM_VOLUME := Vector2(2.0, -8.0)
const AGONY_SHARE := 0.65
const DEATH_AT := 0.7
const GIVE_UP := 6.0
## Lo que acelera cada fiera de más comiendo a la vez.
const EXTRA_FEEDER := 0.4
## Cuántas comen como mucho, y a qué distancia (m) tienen que estar las de la manada.
const MAX_FEEDERS := 3
const PACK_RADIUS := 25.0
## Probabilidad de arrancar el brazo o la pierna entero (por arriba) en vez del antebrazo o la pierna.
const UPPER_CHANCE := 0.7
## Si en este rato (s) no llega la pose del esqueleto, los restos se montan con la que haya.
const POSE_TIMEOUT := 1.0

var remains: PlayerRemains

var _combat: PlayerCombat
var _skeleton: Skeleton3D
var _killer: NPCController
var _active := false
var _over := false
var _over_time := 0.0
var _skipping := false
var _pose_requested := false
var _pose_wait := 0.0
var _duration := 7.0
var _progress := 0.0
## Segundos sin que coma ninguna.
var _idle := 0.0
var _bite_timer := 0.0
var _bites := 0
var _scream_timer := 0.0
var _screaming := false
## Lo que queda por arrancar, en orden: {zone, upper, at (progreso)}.
var _plan: Array[Dictionary] = []
var _guts_done := false
var _collision_layer := 0


func setup(combat: PlayerCombat, skeleton: Skeleton3D) -> void:
	_combat = combat
	_skeleton = skeleton
	set_process(false)


func is_active() -> bool:
	return _active


## Ya se ha acabado (despiezado, dejado a medias o saltado): falta reaparecer.
func is_over() -> bool:
	return _active and _over


## Segundos desde que se acabó.
func over_time() -> float:
	return _over_time


## Empieza con [killer] (la fiera que lo ha matado) y las de su manada que peleaban con él.
func start(killer: NPCController) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var player := _combat.player
	_active = true
	_over = false
	_over_time = 0.0
	_skipping = false
	_pose_requested = false
	_progress = 0.0
	_idle = 0.0
	_bites = 0
	_screaming = true
	_plan.clear()
	_guts_done = false
	_killer = killer
	remains = PlayerRemains.spawn(host, player.player_model.global_transform, _combat.ragdoll)
	var feeders: Array[NPCController] = [killer]
	for node in CombatDirector.engaged(player):
		var npc := node as NPCController
		if feeders.size() >= MAX_FEEDERS:
			break
		if npc == null or npc == killer or npc.feed_profile() == null \
				or npc.global_position.distance_to(player.global_position) > PACK_RADIUS:
			continue
		feeders.append(npc)
	# Al acabar el fotograma: ahora la fiera puede estar a mitad de su ataque.
	for npc in feeders:
		npc.feed_on.call_deferred(remains)
	# Que la cápsula del jugador no le impida a la fiera llegar al cuerpo.
	_collision_layer = player.collision_layer
	player.collision_layer = 0
	_combat.hud.show_skip_hint()
	set_process(true)


## Lo acaba de golpe (a oscuras, al reaparecer). Lo que quedaba por arrancar ya se lo han comido:
## quedan los muñones, pero lo arrancado no cae. Si el cuerpo aún no se ha asentado, en cuanto lo
## haga.
func skip() -> void:
	if not _active:
		return
	_skipping = true
	if is_instance_valid(remains) and remains.built and not _over:
		_complete()


## Antes de reaparecer, ya a oscuras: acaba lo que falte (skip), espera a que los cortes se apliquen
## y deja los restos quietos para siempre (PlayerRemains.seal). El jugador vuelve a verse y a chocar.
func release() -> void:
	if not _active:
		return
	skip()
	var tree := get_tree()
	var waited := 0.0
	while _active and is_instance_valid(remains) and not remains.built and waited < 4.0:
		await tree.process_frame
		waited += get_process_delta_time()
	waited = 0.0
	while _active and is_instance_valid(remains) and remains.dismemberment != null \
			and remains.dismemberment.is_busy() and waited < 3.0:
		await tree.process_frame
		waited += get_process_delta_time()
	cancel()


## Lo deja como esté (al reaparecer, al cargar una partida): los restos se quedan quietos, o se van si
## aún no se habían montado.
func cancel() -> void:
	if not _active:
		return
	if is_instance_valid(remains):
		if remains.built:
			remains.seal()
		else:
			remains.queue_free()
	if _skeleton.skeleton_updated.is_connected(_on_pose):
		_skeleton.skeleton_updated.disconnect(_on_pose)
	_active = false
	set_process(false)
	remains = null
	_killer = null
	var player := _combat.player
	player.player_model.visible = true
	player.collision_layer = _collision_layer
	player.camera_controller.end_cinematic()
	_combat.hud.hide_skip_hint()


func _process(delta: float) -> void:
	if not is_instance_valid(remains):
		_over = true
		_over_time += delta
		_combat.player.camera_controller.cinematic = null
		return
	# La cámara, de cine, a lo que queda (ver CameraController.cinematic).
	_combat.player.camera_controller.cinematic = remains.torso_point() if remains.built else remains.feed_point()
	if not remains.built:
		_await_body(delta)
		return
	if _over:
		_over_time += delta
		return
	var eating := remains.eating()
	if eating.is_empty():
		_idle += delta
		if _idle >= GIVE_UP:
			_finish()
		return
	_idle = 0.0
	_progress = minf(_progress + delta * (1.0 + EXTRA_FEEDER * (eating.size() - 1)) / _duration, 1.0)
	# La que trabaja el miembro que toca es la que lo arranca.
	var main := remains.main_feeder()
	if _gore() == SettingsManager.GORE_FULL:
		while not _plan.is_empty() and _progress >= float(_plan[0].at):
			_tear(_plan.pop_front(), main)
		if not _guts_done and _progress >= GUTS_AT:
			_spill_guts(main)
		# Va a por el miembro que toca arrancar.
		if _plan.is_empty():
			remains.set_focus(&"", false)
		else:
			remains.set_focus(_plan[0].zone, _plan[0].upper)
	_bite_timer -= delta
	if _bite_timer <= 0.0:
		_bite_timer = randf_range(BITE_EVERY.x, BITE_EVERY.y)
		_bite(eating.pick_random())
	_update_voice(delta)
	if _progress >= 1.0:
		_finish()


## Hasta que el cuerpo se asienta no hay restos. Entonces se lee su pose cuando el esqueleto se
## actualiza (skeleton_updated: fuera de esa señal da la pose sin el muñeco ni los demás
## modificadores) y se montan.
func _await_body(delta: float) -> void:
	var ragdoll := _combat.ragdoll
	if not _pose_requested:
		if ragdoll.is_running() and not ragdoll.is_settled():
			return
		_pose_requested = true
		_pose_wait = 0.0
		_skeleton.skeleton_updated.connect(_on_pose, CONNECT_ONE_SHOT)
		return
	_pose_wait += delta
	if _pose_wait >= POSE_TIMEOUT and _skeleton.skeleton_updated.is_connected(_on_pose):
		_skeleton.skeleton_updated.disconnect(_on_pose)
		_build(_read_pose())


func _on_pose() -> void:
	_build.call_deferred(_read_pose())


func _read_pose() -> Array[Transform3D]:
	var pose: Array[Transform3D] = []
	for b in _skeleton.get_bone_count():
		pose.append(_skeleton.get_bone_pose(b))
	return pose


## Los restos ocupan el sitio del cuerpo: el del jugador se esconde y su muñeco se va.
func _build(pose: Array[Transform3D]) -> void:
	if not _active or not is_instance_valid(remains) or remains.built:
		return
	var player := _combat.player
	var lost: Array[StringName] = []
	for zone in PlayerRemains.LIMBS:
		if _combat.body_damage.is_severed(zone):
			lost.append(zone)
	remains.build(_skeleton, pose, player.player_model, _combat.body_damage.dismemberment, _gravity(), lost)
	player.player_model.visible = false
	_combat.ragdoll.stop()
	_duration = randf_range(EAT_TIME.x, EAT_TIME.y)
	_bite_timer = 0.3
	_scream_timer = 0.0
	_plan_tears()
	if _skipping:
		_complete()


## Los brazos y las piernas que le quedan, del que la fiera tiene más cerca al que más lejos,
## repartidos entre TEARS.
func _plan_tears() -> void:
	_plan.clear()
	if _gore() != SettingsManager.GORE_FULL:
		return
	var zones: Array[StringName] = []
	for zone in PlayerRemains.LIMBS:
		if not _combat.body_damage.is_severed(zone):
			zones.append(zone)
	var from := _killer.global_position if is_instance_valid(_killer) else remains.global_position
	zones.sort_custom(func(a: StringName, b: StringName) -> bool:
		return remains.limb_point(a, true).distance_squared_to(from) < remains.limb_point(b, true).distance_squared_to(from))
	for i in zones.size():
		var at := (TEARS.x + TEARS.y) * 0.5
		if zones.size() > 1:
			at = lerpf(TEARS.x, TEARS.y, float(i) / (zones.size() - 1))
		_plan.append({zone = zones[i], upper = randf() < UPPER_CHANCE, at = at})


## Un bocado de [state] donde come: la cabeza entra y tira, desgarro y sangre, una mancha en el
## cuerpo y un tirón de él hacia la fiera.
func _bite(state: FeedState) -> void:
	_bites += 1
	var point := remains.bite_point(state) + _jitter(0.04)
	var up := _up()
	var pull := _pull(state.npc(), point)
	state.bite(pull)
	if _gore() != SettingsManager.GORE_OFF:
		CombatFx.play(&"devour_bite", point, {"pitch": randf_range(0.85, 1.1) / sqrt(maxf(state.npc().body_size, 0.3))})
		if _bites % 3 == 1:
			CombatFx.play(&"skin_tear", point, {"pitch": randf_range(0.8, 1.05), "volume_offset_db": -4.0})
		if _bites % 3 == 0:
			CombatFx.play(&"bone_snap", point, {"pitch": randf_range(0.85, 1.15), "volume_offset_db": -4.0})
		CombatFx.spurt(remains, point, (up + pull * 0.6).normalized(), randf_range(0.35, 0.8))
		# Hacia abajo: gotea al suelo y la mancha queda en lo que mira arriba.
		if _bites % 2 == 1:
			CombatFx.blood(remains, point, -(up * 0.8 + pull * 0.2).normalized(), ItemData.DamageKind.SLASH,
				randf_range(12.0, 22.0))
	remains.tug(remains.bite_bone(state), pull, randf_range(8.0, 16.0), randf_range(0.03, 0.07))
	remains.tug(PlayerRemains.CHEST_BONE, pull, randf_range(3.0, 6.0))


## Le arranca un miembro [state] (que se lo lleva en la boca): crujen los huesos, se desgarra la
## carne, tira del cuerpo y, si aún vive, grita.
func _tear(entry: Dictionary, state: FeedState) -> void:
	var point := remains.limb_point(entry.zone, entry.upper)
	var feeder := state.npc() if state != null else null
	var pull := _pull(feeder, point)
	# Sale hacia la boca, que lo agarra en cuanto cae; sin fiera, despedido.
	var fling := pull * randf_range(0.4, 0.8) + _up() * 0.6 if state != null \
		else pull * randf_range(1.6, 2.6) + _up() * randf_range(1.0, 1.8)
	if not remains.sever(entry.zone, entry.upper, pull, fling, false, state):
		return
	CombatFx.play(&"bone_snap", point, {"pitch": randf_range(0.85, 1.0), "volume_offset_db": 3.0})
	CombatFx.play(&"bone_snap", point, {"pitch": randf_range(1.05, 1.2)})
	CombatFx.play(&"skin_tear", point, {"pitch": randf_range(0.8, 0.9), "volume_offset_db": 3.0})
	CombatFx.play(&"skin_squelch", point, {"pitch": randf_range(0.8, 0.95)})
	remains.tug(PlayerRemains.TORSO_BONE, pull, 10.0, 0.1)
	if _screaming:
		_scream(SCREAM_VOLUME.x + 1.0, true)
		_scream_timer = randf_range(SCREAM_EVERY.x, SCREAM_EVERY.y)


## Las vísceras fuera, por el lado de la fiera [state]: chapoteo, desgarro y mucha sangre.
func _spill_guts(state: FeedState) -> void:
	_guts_done = true
	var point := remains.torso_point()
	var side := _pull(state.npc() if state != null else null, point)
	remains.open_torso()
	remains.spill_guts(side)
	CombatFx.play(&"skin_squelch", point, {"pitch": randf_range(0.75, 0.85), "volume_offset_db": 4.0})
	CombatFx.play(&"skin_tear", point, {"pitch": randf_range(0.75, 0.85), "volume_offset_db": 2.0})
	CombatFx.blood(remains, point, -_up(), ItemData.DamageKind.BLUNT, 40.0)
	_soak(3)
	BloodPool.spawn(remains, point, _gravity(), randf_range(1.4, 1.9), 6.0, GutPile.WORLD_MASK)
	remains.tug(PlayerRemains.TORSO_BONE, side, 12.0, 0.08)


## El tronco empapado: [count] manchas grandes sobre lo que mira arriba.
func _soak(count: int) -> void:
	for i in count:
		BloodStains.stain(remains, remains.torso_point() + _jitter(0.18), -_up(), 1.6)


## Grita mientras vive, cada vez más débil; al llegar a DEATH_AT, el estertor y silencio.
func _update_voice(delta: float) -> void:
	if not _screaming:
		return
	if _progress >= DEATH_AT:
		_screaming = false
		CombatFx.play(_combat.voice(&"player_gurgle"), remains.head_point(), {"pitch": randf_range(0.95, 1.02)})
		return
	_scream_timer -= delta
	if _scream_timer <= 0.0:
		_scream_timer = randf_range(SCREAM_EVERY.x, SCREAM_EVERY.y)
		_scream(lerpf(SCREAM_VOLUME.x, SCREAM_VOLUME.y, _progress / DEATH_AT))


## Un grito a [volume_db]: de agonía (siempre, si [agony]) o un quejido.
func _scream(volume_db: float, agony := false) -> void:
	var id := &"player_agony" if agony or randf() < AGONY_SHARE else &"player_hurt"
	CombatFx.play(_combat.voice(id), remains.head_point(), {"pitch": randf_range(0.94, 1.06), "volume_offset_db": volume_db})


## Lo que faltaba, de golpe y sin ruido (a oscuras): los miembros que quedaban ya se los han comido.
func _complete() -> void:
	if _gore() == SettingsManager.GORE_FULL:
		remains.dismemberment.drop_parts = false
		for entry in _plan:
			remains.sever(entry.zone, entry.upper, _up(), Vector3.ZERO, true)
		_plan.clear()
		if not _guts_done:
			_guts_done = true
			remains.open_torso()
			remains.spill_guts(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).slide(_up()).normalized())
	if _gore() != SettingsManager.GORE_OFF:
		_soak(4)
	_finish()


## Se acaba, despiezado o no: los restos se quedan como estén y las fieras comen un rato más.
func _finish() -> void:
	if _over:
		return
	_over = true
	_over_time = 0.0
	_screaming = false
	if is_instance_valid(remains):
		remains.set_focus(&"", false)
		remains.devoured = true


## Hacia la fiera desde [point], por el suelo: hacia donde tira al morder.
func _pull(feeder: NPCController, point: Vector3) -> Vector3:
	var up := _up()
	var to := feeder.global_position - point if is_instance_valid(feeder) else Vector3.ZERO
	to -= up * to.dot(up)
	if to.length_squared() < 1e-4:
		to = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).slide(up)
	return to.normalized()


func _jitter(size: float) -> Vector3:
	return Vector3(randf_range(-size, size), randf_range(-size, size), randf_range(-size, size))


func _up() -> Vector3:
	return -_combat.player.gravity_direction.normalized()


func _gravity() -> Vector3:
	var player := _combat.player
	return player.gravity_direction.normalized() * (player.planet.gravity_strength if player.planet else 9.8)


func _gore() -> int:
	return SettingsManager.gore_level()

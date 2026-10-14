class_name Butchering
extends Node

## Despellejar un animal muerto (E con un cuchillo en la mano: SurvivalActions.open_corpse) lleva un
## rato, más cuanto más grande. El jugador se agacha de cara al cadáver y trabaja con el cuchillo
## (el clip ANIM en bucle, en tronco y brazos: PlayerCombat.play_task). Va por fases, y del animal
## queda la canal (Carcass):
##   - Desmembrar (hasta DISMEMBER_END): a cada tajo se le corta un miembro de los que le queden,
##     del más cercano al más lejano (AnimalGore.butcher_cuts: cada pata por arriba, el cuello y la
##     cola). Lo cortado cae junto al cuerpo como en las mutilaciones (Dismemberment), con el muñón
##     tapado; cruje el hueso (bone_snap), el muñón echa un chorro y deja charco.
##   - Despellejar (hasta SKIN_END): a cada tajo del clip el cuchillo corta (skin_cut) y salpica
##     (CombatFx), y de vez en cuando se arranca un buen trozo de piel (skin_tear). Al acabar, la
##     piel se quita y en lugar del cuerpo queda la canal, abierta y sin cabeza (Carcass).
##   - Destripar (hasta DEBONE_START): las vísceras salen al suelo (GutPile) con un chapoteo, y
##     cada tajo chapotea (skin_squelch).
##   - Descarnar (desde DEBONE_START): se saca la carne y crujen los huesos (bone_snap).
## Moverse, atacar, rodar o alejarse lo deja a medias, y se retoma donde se dejó
## (NPCController.butcher_progress). Al acabar avisa (finished) para llenar el cadáver (HuntingLoot)
## y abrirlo como un botín.
## Con menos gore (SettingsManager.gore_level) el cuerpo no se cambia por la canal y, sin gore,
## ni sangre ni chapoteos ni huesos: solo el cuchillo y la piel.

signal finished(npc: NPCController)

## Segundos por metro de radio del cuerpo, entre MIN_TIME y MAX_TIME: un lobo, unos 7 s; un ciervo,
## 11; un mamut, 22.
const SECONDS_PER_RADIUS := 20.0
const MIN_TIME := 6.0
const MAX_TIME := 22.0
## El clip y en qué instantes de cada vuelta corta el cuchillo (s), medidos en él: el tajo, que
## salpica, y el revés, más flojo. Provisional: un tajo de espada en guardia baja (Mixamo, Sword And
## Shield Slash), hasta tener uno de trabajar de rodillas.
const ANIM := &"butcher"
const ANIM_SPEED := 0.9
const CUT := 0.6
const BACKCUT := 1.07
## Sin el clip, entre tajo y tajo (s).
const STROKE_TIME := Vector2(0.45, 0.8)
## Lo deprisa que se vuelve hacia el cadáver.
const TURN_SPEED := 8.0
## Cuánto puede apartarse de donde empezó sin dejarlo (m).
const LEEWAY := 1.5
## Fases: hasta DISMEMBER_END se desmiembra; hasta SKIN_END se despelleja (y entonces se quita la
## piel); de ahí a DEBONE_START se destripa, y luego se descarna.
const DISMEMBER_END := 0.35
const SKIN_END := 0.55
const DEBONE_START := 0.72
## Cuándo se arrancan trozos de piel y cuándo salen las vísceras (de toda la tarea).
const TEARS := [0.42, 0.47, 0.52]
const GUTS_OUT := 0.62
## El charco bajo cada muñón (m) y lo que tarda en extenderse (s).
const STUMP_POOL := Vector2(0.45, 3.0)

var _player: PlayerController
var _npc: NPCController
## Dónde corta, en el marco del cadáver (sigue al origen flotante).
var _local_point := Vector3.ZERO
var _duration := 0.0
var _max_distance := 0.0
var _stroke_timer := 0.0
var _strokes := 0
var _was_crouching := false
## Por dónde iba el clip el fotograma anterior (s): los tajos se disparan al pasar por su instante.
var _anim_time := -1.0
## Los miembros que quedan por cortar, del más cercano al más lejano, y desde dónde (progreso) se
## reparten hasta DISMEMBER_END.
var _animal_gore: AnimalGore
var _pending: Array[StringName] = []
var _pending_total := 0
var _pending_from := 0.0


func setup(player: PlayerController) -> void:
	_player = player
	set_process(false)


func is_active() -> bool:
	return _npc != null


## Empieza (o retoma) a despellejar [npc].
func start(npc: NPCController) -> void:
	_npc = npc
	var center := _body_center(npc)
	var radius := _body_radius(npc)
	# Corta por el lado del cuerpo que da al jugador, a media altura.
	var up := -_player.gravity_direction.normalized()
	var to_player := _player.global_position - center
	to_player -= up * to_player.dot(up)
	var side := to_player.normalized() if to_player.length() > 0.05 else _player.global_basis.z
	var point := center + side * radius * 0.6
	_local_point = npc.global_transform.affine_inverse() * point
	_duration = clampf(radius * SECONDS_PER_RADIUS, MIN_TIME, MAX_TIME)
	_max_distance = _player.global_position.distance_to(npc.global_position) + LEEWAY
	_stroke_timer = 0.25
	_strokes = 0
	_was_crouching = _player.locomotion.crouching
	_player.locomotion.set_crouching(true)
	_player.combat.play_task(ANIM, ANIM_SPEED)
	_anim_time = -1.0
	_plan_cuts()
	set_process(true)


## Lo deja a medias.
func cancel() -> void:
	if _npc == null:
		return
	_stop()
	_player.survival.notify("Lo dejas a medias")


func _process(delta: float) -> void:
	if not _still_valid():
		cancel()
		return
	if _interrupted():
		cancel()
		return
	var before := _npc.butcher_progress
	_npc.butcher_progress = minf(before + delta / _duration, 1.0)
	for at in TEARS:
		if before < at and _npc.butcher_progress >= at:
			_tear()
	# Lo que no haya cortado ningún tajo a tiempo, de golpe.
	if before < DISMEMBER_END and _npc.butcher_progress >= DISMEMBER_END:
		while not _pending.is_empty():
			_sever(_pending.pop_front())
	if before < SKIN_END and _npc.butcher_progress >= SKIN_END:
		_strip()
	if before < GUTS_OUT and _npc.butcher_progress >= GUTS_OUT:
		_spill_guts()
	_player.rotate_toward_direction(_flat_to(_point()), delta, TURN_SPEED)
	_cut_strokes(delta)
	if _npc.butcher_progress >= 1.0:
		_finish()


## Los tajos al ritmo del clip: cuando pasa por CUT o por BACKCUT. Sin clip, a su aire.
func _cut_strokes(delta: float) -> void:
	var time := _player.combat.task_time(ANIM)
	if time < 0.0:
		_stroke_timer -= delta
		if _stroke_timer <= 0.0:
			_stroke_timer = randf_range(STROKE_TIME.x, STROKE_TIME.y)
			_stroke(true)
		return
	if _anim_time >= 0.0:
		if _passed(_anim_time, time, CUT):
			_stroke(true)
		elif _passed(_anim_time, time, BACKCUT):
			_stroke(false)
	_anim_time = time


## Si de [from] a [to] (un clip en bucle, que puede haber dado la vuelta) se pasa por [at].
static func _passed(from: float, to: float, at: float) -> bool:
	if to >= from:
		return from < at and at <= to
	return at > from or at <= to


## Se quita la piel y del cuerpo queda la canal: un desgarro, los huesos que se parten y sangre.
func _strip() -> void:
	var point := _point()
	var up := -_player.gravity_direction.normalized()
	CombatFx.play(&"skin_tear", point, {"pitch": randf_range(0.85, 0.95), "volume_offset_db": 3.0})
	CombatFx.play(&"bone_snap", point, {"pitch": randf_range(0.9, 1.0)})
	CombatFx.play(&"bone_snap", point, {"pitch": randf_range(1.05, 1.15), "volume_offset_db": -3.0})
	if _gore() >= SettingsManager.GORE_BLOOD:
		CombatFx.blood(_npc, point, up, ItemData.DamageKind.SLASH, 16.0)
	Carcass.strip(_npc, _body_center(_npc), up)


## Las vísceras salen al suelo, por el lado del que corta: un chapoteo, un desgarro y sangre.
func _spill_guts() -> void:
	var point := _point()
	var up := -_player.gravity_direction.normalized()
	CombatFx.play(&"skin_squelch", point, {"pitch": randf_range(0.75, 0.85), "volume_offset_db": 3.0})
	CombatFx.play(&"skin_tear", point, {"pitch": randf_range(0.8, 0.9)})
	if _gore() < SettingsManager.GORE_BLOOD:
		return
	CombatFx.blood(_npc, point, up, ItemData.DamageKind.BLUNT, 14.0)
	BloodStains.stain(_player, _hand_point(), up, 1.0)
	var to_player := _player.global_position - point
	to_player -= up * to_player.dot(up)
	Carcass.spill_guts(_npc, point, to_player.normalized(), up, _body_radius(_npc))


func _still_valid() -> bool:
	return is_instance_valid(_npc) and _npc.is_dead and not _npc.butchered


## Lo que lo deja a medias: moverse, saltar, pelear (golpe, guardia, voltereta, tambaleo), trepar,
## nadar o alejarse.
func _interrupted() -> bool:
	var input := _player.movement.get_input_direction(_player.camera, _player.gravity_direction)
	return input.length_squared() > 0.01 or _player.combat.is_busy() or _player.climb.is_active() \
		or _player.movement.is_swimming or _player.movement.is_jumping \
		or _player.global_position.distance_to(_npc.global_position) > _max_distance


func _finish() -> void:
	var npc := _npc
	var point := _point()
	if _gore() >= SettingsManager.GORE_BLOOD:
		CombatFx.play(&"bone_snap", point, {"pitch": randf_range(0.9, 1.1)})
		CombatFx.play(&"skin_squelch", point)
	_stop()
	finished.emit(npc)


func _stop() -> void:
	set_process(false)
	_player.combat.stop_task(ANIM)
	if not _was_crouching:
		_player.locomotion.set_crouching(false)
	_npc = null


## Un tajo ([full]) o un revés: el cuchillo y unas gotas. Los tajos, de vez en cuando, salpican
## (manchan el suelo, el cadáver y la mano) y chapotean. Desmembrando, cada uno corta un miembro
## cuando le toca.
func _stroke(full: bool) -> void:
	if not _pending.is_empty():
		var done := _pending_total - _pending.size()
		var due := lerpf(_pending_from, DISMEMBER_END, float(done) / _pending_total)
		if _npc.butcher_progress >= due:
			_sever(_pending.pop_front())
			return
	var point := _point() + _jitter(0.12)
	CombatFx.play(&"skin_cut", point, {"pitch": randf_range(0.9, 1.1),
		"volume_offset_db": 0.0 if full else -5.0})
	if _gore() < SettingsManager.GORE_BLOOD:
		return
	var dir := _spray_dir()
	if not full:
		CombatFx.spurt(_npc, point, dir, randf_range(0.1, 0.2))
		return
	_strokes += 1
	CombatFx.spurt(_npc, point, dir, randf_range(0.2, 0.5))
	if _strokes % 2 == 0:
		CombatFx.blood(_npc, point, dir, ItemData.DamageKind.SLASH, 10.0)
		BloodStains.stain(_player, _hand_point(), -dir, 0.5)
	# Destripando, cada tajo chapotea; despellejando, de vez en cuando; descarnando, crujen huesos.
	var done := _npc.butcher_progress
	if (done >= SKIN_END and done < DEBONE_START) or _strokes % 3 == 1:
		CombatFx.play(&"skin_squelch", point, {"pitch": randf_range(0.85, 1.1)})
	if done >= DEBONE_START and _strokes % 2 == 0:
		CombatFx.play(&"bone_snap", point, {"pitch": randf_range(0.9, 1.2), "volume_offset_db": -4.0})


## Los miembros que le quedan por cortar (solo con todo el gore), del más cercano al jugador al más
## lejano, repartidos desde donde va hasta DISMEMBER_END.
func _plan_cuts() -> void:
	_pending.clear()
	_animal_gore = _npc.get_node_or_null(^"AnimalGore") as AnimalGore
	if _animal_gore == null or _animal_gore.dismemberment.skeleton == null \
			or _gore() < SettingsManager.GORE_FULL or _npc.butcher_progress >= DISMEMBER_END:
		return
	var from := _player.global_position
	_pending = _animal_gore.butcher_cuts()
	_pending.sort_custom(func(a: StringName, b: StringName) -> bool:
		return _animal_gore.butcher_point(a).distance_squared_to(from) \
			< _animal_gore.butcher_point(b).distance_squared_to(from))
	_pending_total = _pending.size()
	_pending_from = _npc.butcher_progress


## Corta [bone]: cruje el hueso, se desgarra la carne, el muñón echa un chorro y deja charco.
func _sever(bone: StringName) -> void:
	var cut := _animal_gore.butcher_cut(bone, _body_center(_npc))
	if cut.is_empty():
		return
	var stump: Array = _animal_gore.dismemberment.stump(cut)
	var point: Vector3 = stump[0]
	var out: Vector3 = stump[1]
	var down := _player.gravity_direction.normalized()
	CombatFx.play(&"skin_cut", point, {"pitch": randf_range(0.85, 0.95)})
	CombatFx.play(&"bone_snap", point, {"pitch": randf_range(0.85, 1.05), "volume_offset_db": 2.0})
	CombatFx.play(&"skin_squelch", point, {"pitch": randf_range(0.8, 0.95)})
	CombatFx.spurt(_npc, point, out, 1.0)
	CombatFx.spurt(_npc, point, (out - down).normalized(), 0.6)
	BloodPool.spawn(_npc, point, down * 9.8, STUMP_POOL.x * randf_range(0.8, 1.2), STUMP_POOL.y,
		CombatFx._ground_mask())
	BloodStains.stain(_player, _hand_point(), -out, 0.6)


## Se arranca un buen trozo de piel: el desgarro y un borbotón.
func _tear() -> void:
	var point := _point()
	CombatFx.play(&"skin_tear", point, {"pitch": randf_range(0.92, 1.08)})
	if _gore() >= SettingsManager.GORE_BLOOD:
		CombatFx.spurt(_npc, point, _spray_dir(), 0.8)
		BloodStains.stain(_npc, point, _spray_dir(), 1.0)


func _point() -> Vector3:
	return _npc.global_transform * _local_point


## Hacia [point], en horizontal y de largo 1 (como lo quiere rotate_toward_direction).
func _flat_to(point: Vector3) -> Vector3:
	var up := -_player.gravity_direction.normalized()
	var d := point - _player.global_position
	d -= up * d.dot(up)
	return d.normalized() if d.length_squared() > 1e-6 else Vector3.ZERO


## Hacia arriba y hacia el jugador: la sangre sale hacia el que corta.
func _spray_dir() -> Vector3:
	var up := -_player.gravity_direction.normalized()
	var to_player := (_player.global_position - _point()).normalized()
	return (up + to_player * 0.6 + _jitter(0.4)).normalized()


func _jitter(size: float) -> Vector3:
	return Vector3(randf_range(-size, size), randf_range(-size, size), randf_range(-size, size))


func _gore() -> int:
	return SettingsManager.gore_level()


## La mano derecha del jugador, la del cuchillo.
func _hand_point() -> Vector3:
	var skeleton := _player.player_model.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	if skeleton != null:
		var bone := skeleton.find_bone("mixamorig_RightHand")
		if bone >= 0:
			return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	return _player.global_position


## El centro del cuerpo tal como ha quedado (la media de sus huesos: tumbado, si cayó de lado).
static func _body_center(npc: NPCController) -> Vector3:
	var skeleton := npc.get_skeleton()
	if skeleton == null or skeleton.get_bone_count() == 0:
		return npc.get_lock_point()
	var sum := Vector3.ZERO
	for bone in skeleton.get_bone_count():
		sum += skeleton.get_bone_global_pose(bone).origin
	return skeleton.global_transform * (sum / skeleton.get_bone_count())


## El radio del cuerpo (m): el de su cápsula, a su tamaño.
static func _body_radius(npc: NPCController) -> float:
	var capsule := npc.collision_shape.shape as CapsuleShape3D if npc.collision_shape != null else null
	if capsule == null:
		return 0.4
	return capsule.radius * npc.collision_shape.global_basis.get_scale().x

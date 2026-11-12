extends Node

## Los colonos y el grupo que acompaña al jugador, sin el planeta: sobre un suelo llano de física, con
## un jugador de pega. Comprueba la formación (cuña y fila) y las órdenes al grupo (esperad, seguidme,
## a la base con su trabajo), el constructor (lleva del cofre a la obra y la levanta; parado sin
## martillo o sin material; lejos del jugador), el guardia (ronda, turnos y cuándo duerme), el
## cocinero (del cofre a la hoguera y lo asado al cofre; lejos), las comidas (comen de los cofres;
## con hambre van a medio ritmo), el cazador lejos y lo que se guarda de cada trabajo.
##   godot --headless --path . --audio-driver Dummy res://tests/world/test_settlers.tscn

const RADIUS := 10000.0
const SPEEDUP := 8.0

## El compañero con la hora que diga la prueba (sin sol no hay hora solar).
class TestCompanion extends Companion:
	var hour := 10.0

	func _hour() -> float:
		return hour


## El jugador de pega: un cuerpo que anda a [walk] (mundo) y sabe su velocidad real.
class FakePlayer extends CharacterBody3D:
	var walk := Vector3.ZERO
	var hotbar: Node = null
	var planet: Node = null

	func _physics_process(_delta: float) -> void:
		velocity = walk
		move_and_slide()


var failures := 0
var _terrain: Node3D
var _host: Node3D
var _player: FakePlayer
var _companions: SettlementCompanions
var _made := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	Engine.time_scale = SPEEDUP
	Engine.max_physics_steps_per_frame = 32
	GameManager.current_state = GameManager.State.PLAYING
	_build_world()
	await _wait(0.3)
	print("SECTION _check_formation t=%.1f" % (Time.get_ticks_msec() / 1000.0))
	await _check_formation()
	print("SECTION _check_orders t=%.1f" % (Time.get_ticks_msec() / 1000.0))
	await _check_orders()
	print("SECTION _check_builder t=%.1f" % (Time.get_ticks_msec() / 1000.0))
	await _check_builder()
	print("SECTION _check_guard t=%.1f" % (Time.get_ticks_msec() / 1000.0))
	await _check_guard()
	print("SECTION _check_cook t=%.1f" % (Time.get_ticks_msec() / 1000.0))
	await _check_cook()
	_check_meals()
	_check_hunter_away()
	_check_saved()
	_check_task_cargo()
	_check_task_cleanup()
	await _clear()
	Engine.time_scale = 1.0
	print("RESULT: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)


# --- El mundo de pega --------------------------------------------------------------------------------

func _build_world() -> void:
	_host = Node3D.new()
	_host.name = "Host"
	add_child(_host)
	# El «terreno» solo da el centro del planeta: muy abajo, así que arriba es +Y.
	_terrain = Node3D.new()
	_terrain.name = "Terrain"
	_host.add_child(_terrain)
	_terrain.global_position = Vector3(0.0, -RADIUS, 0.0)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600.0, 1.0, 600.0)
	shape.shape = box
	floor_body.add_child(shape)
	_host.add_child(floor_body)
	floor_body.global_position = Vector3(0.0, -0.5, 0.0)
	_player = FakePlayer.new()
	_player.name = "FakePlayer"
	_player.collision_layer = 0
	_player.collision_mask = PhysicsLayers.WORLD
	var capsule := CollisionShape3D.new()
	capsule.shape = CapsuleShape3D.new()
	capsule.position = Vector3(0.0, 1.0, 0.0)
	_player.add_child(capsule)
	_host.add_child(_player)
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	_companions = SettlementCompanions.new()
	_companions.name = "Companions"
	_companions._terrain = _terrain
	_companions._player = _player
	_companions._host = _host
	_companions.add_to_group(SettlementCompanions.GROUP)
	add_child(_companions)


func _spawn(at: Vector3, mode := Companion.Mode.FOLLOW) -> TestCompanion:
	_made += 1
	var who := {"id": "test:%d" % _made, "name": "Colono%d" % _made, "sex": &"male" if _made % 2 == 0 else &"female",
		"look": 100 + _made}
	var c := TestCompanion.new()
	c.setup(who, 0, "Prueba", null, Villager.build_model(who, []), _terrain, _player, Vector3(0.0, RADIUS, 500.0))
	c.mode = mode
	_companions._list.append(c)
	_host.add_child(c)
	c.global_position = at
	c.reset_physics_interpolation()
	return c


func _clear() -> void:
	for c in _companions._list.duplicate():
		if is_instance_valid(c):
			c.work.stop()
			c.queue_free()
	_companions._list.clear()
	_player.walk = Vector3.ZERO
	await _wait(0.1)


## Espera [seconds] de juego (la prueba va acelerada: cada paso de física es time_scale veces más largo).
func _wait(seconds: float) -> void:
	var frames := ceili(seconds * Engine.physics_ticks_per_second / Engine.time_scale)
	for i in frames:
		await get_tree().physics_frame


func _local(world: Vector3) -> Vector3:
	return _terrain.global_transform.affine_inverse() * world


func _chest(at: Vector3) -> Storage:
	var chest := Storage.new()
	chest.item_id = &"wooden_chest"
	_host.add_child(chest)
	chest.global_position = at
	return chest


func _item(id: StringName) -> ItemData:
	return ItemCatalog.get_item(id)


# --- El grupo ----------------------------------------------------------------------------------------

func _check_formation() -> void:
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	var group: Array[TestCompanion] = []
	for i in 4:
		group.append(_spawn(Vector3(-3.0 - i, 0.05, 1.5 * (i - 1.5))))
	check(not _companions.is_full() and _companions.party().size() == 4, "cuatro en el grupo y aún caben más")
	_companions.formation = SettlementCompanions.Formation.WEDGE
	_player.walk = Vector3(2.0, 0.0, 0.0)
	await _wait(12.0)
	var behind := true
	var in_slot := true
	var gaps := PackedStringArray()
	var apart := true
	for i in group.size():
		var c := group[i]
		behind = behind and c.global_position.x < _player.global_position.x - 0.5
		var off := (_companions.slot_of(c) - c.global_position).slide(Vector3.UP).length()
		gaps.append("%.2f" % off)
		in_slot = in_slot and off < 1.0
		for j in range(i + 1, group.size()):
			apart = apart and c.global_position.distance_to(group[j].global_position) > 0.8
	check(behind, "en cuña van detrás del jugador")
	check(in_slot, "cada uno, en su hueco mientras anda (a %s m)" % ", ".join(gaps))
	check(apart, "y no se pisan")
	var rows := absf(group[0].global_position.z - group[1].global_position.z) > 1.5 \
		and group[2].global_position.x < group[0].global_position.x - 0.8
	check(rows, "la cuña se abre a los lados y la segunda fila va más atrás")
	_player.walk = Vector3.ZERO
	await _wait(4.0)
	var still := true
	for c in group:
		still = still and c.get_real_velocity().length() < 0.2
	check(still, "con el jugador quieto, se paran")
	# En fila: por donde ha pasado el jugador, tras un giro.
	_companions.formation = SettlementCompanions.Formation.FILE
	_player.walk = Vector3(0.0, 0.0, 2.0)
	await _wait(10.0)
	var lined := true
	for i in group.size():
		var c := group[i]
		lined = lined and absf(c.global_position.x - _player.global_position.x) < 1.2 \
			and c.global_position.z < _player.global_position.z - 0.8
	check(lined, "en fila van uno detrás de otro por el rastro del jugador")
	var ordered := true
	var zs := PackedStringArray()
	for i in group.size():
		zs.append("%.1f/%.1f" % [group[i].global_position.x, group[i].global_position.z])
		if i > 0:
			ordered = ordered and group[i].global_position.z < group[i - 1].global_position.z - 0.5
	check(ordered, "y cada uno detrás del anterior (jugador z=%.1f; x/z: %s)" % [_player.global_position.z, ", ".join(zs)])
	_companions.formation = SettlementCompanions.Formation.LOOSE
	check(not _companions.slot_of(group[0]).is_finite(), "sueltos no tienen hueco")
	check(_companions.next_formation() == SettlementCompanions.Formation.WEDGE, "la formación siguiente a sueltos es la cuña")
	for i in SettlementCompanions.MAX - group.size():
		_spawn(Vector3(-20.0 - i, 0.05, 5.0))
	check(_companions.is_full(), "con %d el grupo está lleno" % SettlementCompanions.MAX)
	await _clear()


func _check_orders() -> void:
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	var a := _spawn(Vector3(-2.0, 0.05, 0.0))
	var b := _spawn(Vector3(-2.0, 0.05, 2.0))
	check(_companions.order_wait() == 2 and a.mode == Companion.Mode.WAIT and b.mode == Companion.Mode.WAIT,
		"«esperad aquí» deja a los dos esperando")
	check(_companions.order_follow() == 2 and a.mode == Companion.Mode.FOLLOW, "«seguidme» los pone a seguir")
	# Un colono con trabajo que se va con el jugador y vuelve a su base.
	var base := _local(Vector3(30.0, 0.05, 0.0))
	a.settle_here(base)
	a.work.assign(SettlerWork.Job.GUARD, _local(Vector3(34.0, 0.05, 0.0)), 10.0, 1)
	check(_companions.settler_count() == 1 and _companions.party().size() == 1, "el colono no cuenta en el grupo")
	a.follow()
	check(a.mode == Companion.Mode.FOLLOW and a.has_return_base() and a.return_base.is_equal_approx(base)
		and int(a.return_work.get("job", 0)) == SettlerWork.Job.GUARD and not a.work.active(),
		"al irse con el jugador se acuerda de su base y de su trabajo")
	var saved := _companions.get_save_data()
	var entry: Dictionary = (saved.companions as Array).filter(func(e: Dictionary) -> bool: return e.id == a.resident.id)[0]
	check(entry.has("return_base") and int((entry.get("return_work", {}) as Dictionary).get("job", 0)) == SettlerWork.Job.GUARD
		and int(saved.formation) == int(_companions.formation), "y se guarda con él (y la formación del grupo)")
	var result := _companions.order_home()
	check(int(result[0]) == 1 and int(result[1]) == 1, "«a la base»: vuelve el que tiene base; el otro no tiene")
	check(a.mode == Companion.Mode.SETTLE and a.base.is_equal_approx(base) and a.work.job == SettlerWork.Job.GUARD
		and a.work.shift == 1 and is_equal_approx(a.work.zone_radius, 10.0) and a.homing,
		"vuelve a ser colono de su base, con el trabajo, la zona y el turno que tenía")
	var before := a.global_position.distance_to(Vector3(30.0, 0.05, 0.0))
	await _wait(6.0)
	var after := a.global_position.distance_to(Vector3(30.0, 0.05, 0.0))
	check(after < before - 8.0, "y va hacia ella trotando (%.1f -> %.1f m)" % [before, after])
	# Fuera de la vista del jugador llega cuando habría llegado andando.
	a.global_position = Vector3(200.0, 0.05, 0.0)
	a.homing = true
	await _wait(1.0)
	check(a.global_position.x > 190.0 and a.homing, "lejos del jugador no se mueve, pero va de camino")
	a._travel = 1000.0
	await _wait(0.5)
	check(a.global_position.distance_to(Vector3(30.0, 0.05, 0.0)) < 1.0 and not a.homing,
		"y aparece en su base cuando habría llegado")
	# Retirada: deja de pelear un rato y, si esperaba, vuelve a seguir.
	b.wait_here()
	_companions.order_retreat()
	check(b.mode == Companion.Mode.FOLLOW and b._retreat_left > 0.0, "«retirada» los trae de vuelta")
	await _clear()


# --- El constructor ------------------------------------------------------------------------------------

func _blueprint() -> Dictionary:
	var blocks := {}
	for x in 3:
		for y in 2:
			blocks["%d,%d,0" % [x, y]] = {"block_id": 0, "material_id": "stone"}
	return {"version": 1, "created": "2026-11-12T12:00:00", "dynamic": false, "bounds_min": [0, 0, 0],
		"bounds_max": [3, 2, 1], "block_count": 6, "prop_count": 0,
		"grids": [{"cell_size": 1.0, "blocks": blocks, "materials": {}, "props": []}]}


func _check_builder() -> void:
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	var planet := Node3D.new()
	planet.name = "TestPlanet"
	_host.add_child(planet)
	var site := BlueprintSite.create(_blueprint(), planet, Transform3D(Basis.IDENTITY, Vector3(10.0, 0.0, 6.0)), "caseta")
	var cost := site.get_cost()
	check(not cost.is_empty() and not site.is_complete(), "la obra de prueba pide materiales (%s)" % [cost])
	var chest := _chest(Vector3(4.0, 0.0, -4.0))
	var builder := _spawn(Vector3(3.0, 0.05, 0.0), Companion.Mode.SETTLE)
	builder.settle_here(_local(Vector3(3.0, 0.05, 0.0)))
	builder.work.assign(SettlerWork.Job.BUILD)
	await _wait(1.0)
	check(builder.work.status == SettlerWork.Status.BLOCKED and builder.work.describe().contains(tr("SETTLER_NEED_HAMMER")),
		"sin martillo se queda parado y lo dice: «%s»" % builder.work.describe())
	builder.pack.add_item(_item(&"stone_hammer_01"), 1)
	await _wait(4.0)
	check(builder.work.status == SettlerWork.Status.BLOCKED and site.progress() == 0.0,
		"sin material en los cofres, también: «%s»" % builder.work.describe())
	for id: StringName in cost:
		chest.inventory.add_item(_item(id), int(cost[id]) + 5)
	var left := 90.0
	while left > 0.0 and is_instance_valid(site) and not site.is_complete():
		await _wait(1.0)
		left -= 1.0
	var done := not is_instance_valid(site) or site.is_complete()
	check(done, "con material en el cofre levanta la obra (%.0f s)" % (90.0 - left))
	check(builder.work.gathered == 6, "y lleva la cuenta de los bloques puestos (%d)" % builder.work.gathered)
	await _wait(12.0)
	var back := true
	for id: StringName in cost:
		back = back and chest.inventory.get_item_count(_item(id)) == 5 and builder.pack.get_item_count(_item(id)) == 0
	check(back, "lo que sobra se queda en el cofre, no en su morral")
	# Lejos del jugador: lo mismo sin moverse.
	var far := BlueprintSite.create(_blueprint(), planet, Transform3D(Basis.IDENTITY, Vector3(14.0, 0.0, -8.0)), "otra")
	for id: StringName in cost:
		chest.inventory.add_item(_item(id), int(cost[id]))
	_player.global_position = Vector3(-400.0, 0.05, 0.0)
	var at := builder.global_position
	left = 240.0
	while left > 0.0 and is_instance_valid(far) and not far.is_complete():
		await _wait(2.0)
		left -= 2.0
	check(not is_instance_valid(far) or far.is_complete(), "lejos del jugador también la acaba (%.0f s)" % (240.0 - left))
	check(builder.global_position.distance_to(at) < 0.5, "sin moverse del sitio")
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	chest.queue_free()
	GridManager.clear_all()
	planet.queue_free()
	await _clear()


# --- El guardia ------------------------------------------------------------------------------------------

func _check_guard() -> void:
	var guard := _spawn(Vector3(20.0, 0.05, 20.0), Companion.Mode.SETTLE)
	guard.settle_here(_local(Vector3(20.0, 0.05, 20.0)))
	guard.work.assign(SettlerWork.Job.GUARD, _local(Vector3(20.0, 0.05, 20.0)), 12.0, 0)
	guard.hour = 10.0
	_player.global_position = Vector3(20.0, 0.05, 40.0)
	var seen := {}
	var out_far := 0.0
	for i in 120:
		await _wait(1.0)
		var flat := (guard.global_position - Vector3(20.0, 0.05, 20.0)).slide(Vector3.UP)
		out_far = maxf(out_far, flat.length())
		seen[roundi(rad_to_deg(atan2(flat.z, flat.x)) / 45.0)] = true
	check(out_far > 8.0 and out_far < 12.5 and seen.size() >= 3,
		"de ronda recorre el borde de su zona (hasta %.1f m, %d tramos)" % [out_far, seen.size()])
	check(guard.work.describe().contains(tr("SETTLER_JOB_GUARD_DAY")), "y lo dice: «%s»" % guard.work.describe())
	var task := guard.work.task as SettlerGuard
	check(task.on_duty(10.0) and task.on_duty(20.0) and not task.on_duty(23.0) and task.sleeps(2.0) and not task.sleeps(12.0),
		"el guardia de día vigila hasta acostarse y duerme de noche")
	guard.work.assign(SettlerWork.Job.GUARD, _local(Vector3(20.0, 0.05, 20.0)), 4.0, 1)
	task = guard.work.task as SettlerGuard
	check(task.is_post() and task.on_duty(23.0) and task.on_duty(3.0) and not task.on_duty(12.0) and task.sleeps(12.0)
		and not task.sleeps(2.0), "el de noche vigila de noche y duerme de día; con zona pequeña es un puesto")
	check(is_equal_approx(guard.work.defend_radius(), 4.0 + SettlerGuard.ALERT)
		and guard.work.guard_point().distance_to(Vector3(20.0, 0.05, 20.0)) < 0.1, "y lo que guarda es su zona")
	guard.hour = 23.0
	await _wait(25.0)
	check((guard.global_position - Vector3(20.0, 0.05, 20.0)).slide(Vector3.UP).length() < 1.5
		and guard._chore != Companion.Chore.SLEEP, "de noche está en su puesto, despierto")
	await _clear()
	_player.global_position = Vector3(0.0, 0.05, 0.0)


# --- El cocinero y la comida -----------------------------------------------------------------------------

func _check_cook() -> void:
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	var chest := _chest(Vector3(-6.0, 0.0, -3.0))
	var fire := Campfire.new()
	_host.add_child(fire)
	fire.global_position = Vector3(-10.0, 0.0, 2.0)
	var raw := _item(&"raw_meat")
	var cooked := _item(&"cooked_meat")
	var wood := _item(SettlerWork.WOOD_ID)
	chest.inventory.add_item(raw, 5)
	chest.inventory.add_item(wood, 20)
	var cook := _spawn(Vector3(-5.0, 0.05, 0.0), Companion.Mode.SETTLE)
	cook.settle_here(_local(Vector3(-5.0, 0.05, 0.0)))
	cook.work.assign(SettlerWork.Job.COOK)
	var left := 240.0
	while left > 0.0 and chest.inventory.get_item_count(cooked) < 5:
		await _wait(2.0)
		left -= 2.0
	check(chest.inventory.get_item_count(cooked) == 5 and chest.inventory.get_item_count(raw) == 0,
		"el cocinero asa lo crudo del cofre y guarda lo asado (%.0f s; quedan %d de leña)" % [240.0 - left,
			chest.inventory.get_item_count(wood)])
	check(chest.inventory.get_item_count(wood) < 20 and cook.work.gathered == 5, "con leña del cofre, y lleva la cuenta")
	check(cook.pack.get_item_count(cooked) == 0 and cook.pack.get_item_count(raw) == 0, "sin quedarse nada en el morral")
	# Lejos: igual, sin andar.
	chest.inventory.add_item(raw, 3)
	_player.global_position = Vector3(-400.0, 0.05, 0.0)
	left = 300.0
	while left > 0.0 and chest.inventory.get_item_count(cooked) < 8:
		await _wait(2.0)
		left -= 2.0
	check(chest.inventory.get_item_count(cooked) == 8, "lejos del jugador también asa (%.0f s)" % (300.0 - left))
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	var task := cook.work.task as SettlerCook
	check(task.on_duty(10.0) and task.on_duty(20.0) and not task.on_duty(23.0), "trabaja hasta la hora de acostarse")
	# Las comidas: come de los cofres de su base, lo asado antes que lo crudo.
	chest.inventory.add_item(raw, 2)
	cook.meals.fed = 1.0
	var eaten := cook.meals.eat()
	check(eaten >= 1 and cook.meals.fed >= SettlerMeals.EAT_UNTIL and chest.inventory.get_item_count(cooked) == 8 - eaten
		and chest.inventory.get_item_count(raw) == 2, "con hambre come lo asado del cofre (%d piezas)" % eaten)
	chest.inventory.remove_item(cooked, 99)
	cook.meals.fed = 0.5
	cook.meals.eat()
	check(chest.inventory.get_item_count(raw) < 2, "y lo crudo solo si no hay otra cosa")
	fire.queue_free()
	chest.queue_free()
	await _clear()


func _check_meals() -> void:
	var c := _spawn(Vector3(40.0, 0.05, 0.0), Companion.Mode.SETTLE)
	c.settle_here(_local(Vector3(40.0, 0.05, 0.0)))
	c.work.assign(SettlerWork.Job.FELL)
	check(is_equal_approx(c.work.pace(), 1.0), "saciado trabaja a su ritmo")
	c.meals.fed = 0.0
	check(c.meals.hungry() and is_equal_approx(c.work.pace(), SettlerWork.HUNGRY_PACE), "con hambre, a la mitad")
	c.work.status = SettlerWork.Status.WORKING
	check(c.work.describe().ends_with(tr("SETTLER_HUNGRY")), "y se dice: «%s»" % c.work.describe())
	c.pack.add_item(_item(&"cooked_meat"), 2)
	c.meals.eat()
	check(not c.meals.hungry() and c.pack.get_item_count(_item(&"cooked_meat")) < 2, "come de su morral si lleva algo")
	c.work.stop()
	c.queue_free()
	_companions._list.clear()


func _check_hunter_away() -> void:
	var chest := _chest(Vector3(60.0, 0.0, 0.0))
	var hunter := _spawn(Vector3(62.0, 0.05, 0.0), Companion.Mode.SETTLE)
	hunter.settle_here(_local(Vector3(62.0, 0.05, 0.0)))
	hunter.work.assign(SettlerWork.Job.HUNT)
	hunter._weapon = null
	hunter.work.away(1.0, 10.0)
	check(hunter.work.status == SettlerWork.Status.BLOCKED, "el cazador sin arma se queda parado: «%s»" % hunter.work.describe())
	hunter.pack.add_item(_item(&"stone_axe_01"), 1)
	check(hunter._weapon != null, "con un hacha en el morral ya tiene arma")
	hunter.work.away(SettlerHunt.AWAY_KILL + 1.0, 10.0)
	var meat := chest.inventory.get_item_count(_item(HuntingLoot.MEAT))
	check(meat == SettlerHunt.AWAY_MEAT and hunter.work.status == SettlerWork.Status.AWAY,
		"lejos del jugador trae una pieza cada tanto (%d de carne)" % meat)
	hunter.work.away(1.0, 2.0)
	check(hunter.work.status == SettlerWork.Status.OFF_HOURS, "fuera de su horario, no")
	# El pescador sin caña, y sin haber visto el agua.
	hunter.work.assign(SettlerWork.Job.FISH)
	hunter.work.away(500.0, 10.0)
	check(hunter.work.status == SettlerWork.Status.BLOCKED, "el pescador sin caña se queda parado")
	hunter.pack.add_item(_item(&"fishing_rod"), 1)
	hunter.work.away(500.0, 10.0)
	check(chest.inventory.get_item_count(_item(&"raw_fish")) == 0, "y sin haber encontrado orilla no saca nada lejos")
	(hunter.work.task as SettlerFish)._spot = _local(Vector3(70.0, 0.0, 0.0))
	(hunter.work.task as SettlerFish)._water = _local(Vector3(72.0, 0.0, 0.0))
	hunter.work.away(SettlerFish.AWAY_CATCH + 1.0, 10.0)
	check(chest.inventory.get_item_count(_item(&"raw_fish")) == 1, "con su orilla ya vista, sí")
	chest.queue_free()


func _check_saved() -> void:
	var c: TestCompanion = _companions._list[_companions._list.size() - 1]
	var data := c.work.save_data()
	c.work.stop()
	c.work.restore(data)
	check(c.work.job == SettlerWork.Job.FISH and c.work.task is SettlerFish
		and (c.work.task as SettlerFish)._spot.is_finite(), "el trabajo se guarda con lo suyo (la orilla del pescador)")
	c.work.assign(SettlerWork.Job.GUARD, _local(Vector3(5.0, 0.0, 5.0)), 8.0, 1)
	data = c.work.save_data()
	c.work.stop()
	c.work.restore(data)
	check(c.work.job == SettlerWork.Job.GUARD and c.work.shift == 1 and is_equal_approx(c.work.zone_radius, 8.0)
		and c.work.zone.is_finite(), "y el guardia, con su turno y su zona")
	for job: SettlerWork.Job in SettlerWork.JOB_NAMES:
		check(tr(SettlerWork.JOB_NAMES[job]) != SettlerWork.JOB_NAMES[job], "el oficio %d tiene nombre" % job)


## Guardar a mitad de viaje no debe dejar la carga olvidada en el morral.
func _check_task_cargo() -> void:
	var chest := _chest(Vector3(80, 0, 0))
	var fire := Campfire.new()
	_host.add_child(fire)
	fire.global_position = Vector3(82, 0, 0)
	var c := _spawn(Vector3(80, 0.05, 0), Companion.Mode.SETTLE)
	c.process_mode = Node.PROCESS_MODE_DISABLED
	c.settle_here(_local(c.global_position))
	c.work.assign(SettlerWork.Job.COOK)
	var cooked := _item(&"cooked_meat")
	var raw := _item(&"raw_meat")
	var wood := _item(SettlerWork.WOOD_ID)
	c.pack.add_item(cooked, 2)
	c.pack.add_item(raw, 1)
	c.pack.add_item(wood, 2)
	(c.work.task as SettlerCook)._done = {cooked.id: 2}
	(c.work.task as SettlerCook)._load = {raw.id: 1, wood.id: 2}
	var saved: Dictionary = JSON.parse_string(JSON.stringify(c.work.save_data()))
	c.work.stop()
	c.work.restore(saved)
	c.work.away(1.0, 10.0)
	check(chest.inventory.get_item_count(cooked) == 2 and c.pack.get_item_count(cooked) == 0,
		"tras cargar la partida el cocinero entrega lo asado que llevaba")
	check(c.pack.get_item_count(raw) == 0 and fire.inventory.get_item_count(raw) == 1
		and fire.lit, "tras cargar lleva a la hoguera lo crudo y la leña que cargaba")
	c.pack.clear()
	c.work.assign(SettlerWork.Job.HUNT)
	var meat := _item(HuntingLoot.MEAT)
	var hide := _item(HuntingLoot.HIDE)
	c.pack.add_item(meat, 4)
	c.pack.add_item(hide, 1)
	(c.work.task as SettlerHunt)._haul = {meat.id: 4, hide.id: 1}
	saved = JSON.parse_string(JSON.stringify(c.work.save_data()))
	c.work.stop()
	c.work.restore(saved)
	(c.work.task as SettlerHunt)._depositing(0.1)
	check(chest.inventory.get_item_count(meat) == 4 and chest.inventory.get_item_count(hide) == 1
		and c.pack.get_item_count(meat) == 0, "tras cargar el cazador entrega la pieza que transportaba")
	c.work.stop()
	chest.queue_free()
	fire.queue_free()


func _check_task_cleanup() -> void:
	var c := _spawn(Vector3(90, 0.05, 0), Companion.Mode.SETTLE)
	c.settle_here(_local(c.global_position))
	c.work.assign(SettlerWork.Job.GUARD)
	var task: WeakRef = weakref(c.work.task)
	_companions._list.erase(c)
	c.free()
	check(task.get_ref() == null, "al desaparecer un colono se libera también su tarea")

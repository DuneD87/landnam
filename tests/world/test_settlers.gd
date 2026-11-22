extends Node

## Los colonos y el grupo que acompaña al jugador, sin el planeta: sobre un suelo llano de física, con
## un jugador de pega. Comprueba la formación (cuña y fila) y las órdenes al grupo (esperad, seguidme,
## a la base con su trabajo), el constructor (lleva del cofre a la obra y la levanta; parado sin
## martillo o sin material; lejos del jugador), el guardia (ronda, turnos y cuándo duerme), el
## cocinero (del cofre a la hoguera y lo asado al cofre o al comedero; lejos), las comidas (comen del
## comedero; con hambre van a medio ritmo), la sed (beben del bebedero, lejos sin moverse y cerca
## andando; el aguador lo llena), los bordes (no se tira de un risco, sí baja un escalón), el cazador lejos, lo que se guarda de cada trabajo,
## el equipo del morral (ropa, armadura, escudo, arco), rodear una pared siguiendo al jugador y nadar.
##   godot --headless --path . --audio-driver Dummy res://tests/world/test_settlers.tscn [-- --only=swim,climb]

const RADIUS := 10000.0
const SPEEDUP := 8.0

## El compañero con la hora que diga la prueba (sin sol no hay hora solar).
class TestCompanion extends Companion:
	var hour := 10.0

	func _hour() -> float:
		return hour


## El planeta de pega para el agua (_check_swim): el mar a [sea] m del centro.
class FakeCore extends RefCounted:
	var has_water := true
	var radius := 0.0
	var water_radius := 0.0


## Lo que trepa el jugador de pega (como ClimbController, para ClimbRoutes).
class FakeClimb extends RefCounted:
	var active := false
	var topping := false
	var normal := Vector3.BACK
	var frame := Transform3D.IDENTITY

	func is_active() -> bool:
		return active

	func on_ship() -> bool:
		return false

	func descending() -> bool:
		return false

	func topping_up() -> bool:
		return topping

	func wall_normal() -> Vector3:
		return normal

	func top_frame() -> Transform3D:
		return frame


class FakeLoader extends Node3D:
	var planet := FakeCore.new()
	var global_pos := Vector3.ZERO


## El jugador de pega: un cuerpo que anda a [walk] (mundo) y sabe su velocidad real.
class FakePlayer extends CharacterBody3D:
	var walk := Vector3.ZERO
	var hotbar: Node = null
	var planet: Node = null
	var climb: FakeClimb = null

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


## Las secciones que pide la línea de órdenes (-- --only=swim,climb), o todas.
func _want(section: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			return section in arg.trim_prefix("--only=").split(",")
	return true


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
	if _want("formation"):
		print("SECTION _check_formation t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_formation()
	if _want("orders"):
		print("SECTION _check_orders t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_orders()
	if _want("builder"):
		print("SECTION _check_builder t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_builder()
	if _want("scaffold"):
		print("SECTION _check_scaffold t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_scaffold()
	if _want("guard"):
		print("SECTION _check_guard t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_guard()
	if _want("cook"):
		print("SECTION _check_cook t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_cook()
	if _want("field_work"):
		print("SECTION _check_field_work t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_field_work()
	if _want("field_delivery"):
		print("SECTION _check_field_delivery t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_field_delivery()
	if _want("tree_dodge"):
		print("SECTION _check_tree_dodge t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_tree_dodge()
	if _want("ledge"):
		print("SECTION _check_ledge t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_ledge()
	if _want("thirst"):
		print("SECTION _check_thirst t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_thirst()
	if _want("supplies"):
		print("SECTION _check_supplies t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_supplies()
	if _want("gear"):
		print("SECTION _check_gear t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_gear()
	if _want("follow_wall"):
		print("SECTION _check_follow_wall t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_follow_wall()
	if _want("swim"):
		print("SECTION _check_swim t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_swim()
	if _want("climb"):
		print("SECTION _check_climb t=%.1f" % (Time.get_ticks_msec() / 1000.0))
		await _check_climb()
	if _want("meals"):
		_check_meals()
	if _want("hunter_away"):
		_check_hunter_away()
	if _want("saved"):
		_check_saved()
	if _want("talk"):
		_check_talk()
	if _want("far_zone"):
		_check_far_zone()
	if _want("task_cargo"):
		_check_task_cargo()
	if _want("task_cleanup"):
		_check_task_cleanup()
	await _clear()
	if _want("food_drop"):
		await _check_food_drop()
	if _want("zones"):
		await _check_zones()
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


func _spawn(at: Vector3, mode := Companion.Mode.FOLLOW, outfit: Array[StringName] = []) -> TestCompanion:
	_made += 1
	var who := {"id": "test:%d" % _made, "name": "Colono%d" % _made, "sex": &"male" if _made % 2 == 0 else &"female",
		"look": 100 + _made, "outfit": outfit}
	var c := TestCompanion.new()
	c.setup(who, 0, "Prueba", null, Villager.build_model(who, SettlementVillagers.pieces_of(who)), _terrain, _player,
		Vector3(0.0, RADIUS, 500.0))
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


func _feeder(at: Vector3) -> Storage:
	var feeder := Storage.new()
	feeder.item_id = &"feeding_trough"
	_host.add_child(feeder)
	feeder.global_position = at
	return feeder


func _trough(at: Vector3) -> WaterTrough:
	var trough := WaterTrough.new()
	_host.add_child(trough)
	trough.global_position = at
	return trough


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
	# «Id allí»: uno al sitio y el otro a su lado; llegan y se quedan esperando.
	var spot := Vector3(8.0, 0.05, 0.0)
	check(_companions.order_goto(spot, Vector3.UP) == 2 and a.mode == Companion.Mode.WAIT and a.is_going()
		and b.is_going(), "«id allí» los pone de camino, esperando")
	var going: Dictionary = (_companions.get_save_data().companions as Array)[0]
	check(going.has("goto"), "y adónde van se guarda con la partida")
	await _wait(8.0)
	var near_a := a.global_position.distance_to(spot)
	var near_b := b.global_position.distance_to(spot)
	check(not a.is_going() and not b.is_going() and minf(near_a, near_b) < 1.0
		and maxf(near_a, near_b) < SettlementCompanions.GOTO_RING + 1.0 and a.global_position.distance_to(b.global_position) > 1.0,
		"llegan, uno al sitio y el otro al lado (%.1f y %.1f m)" % [near_a, near_b])
	check(a.mode == Companion.Mode.WAIT and _companions.order_follow() == 2, "y allí esperan hasta «seguidme»")
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


## Una obra alta: lo de arriba lo pone desde un andamio (SettlerScaffold) al que sube por la escalera, y
## al acabar baja y lo quita.
func _check_scaffold() -> void:
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	var planet := Node3D.new()
	planet.name = "TestPlanet"
	_host.add_child(planet)
	var blocks := {}
	for x in 2:
		for y in 5:
			blocks["%d,%d,0" % [x, y]] = {"block_id": 0, "material_id": "stone"}
	var data := {"version": 1, "created": "2026-11-21T12:00:00", "dynamic": false, "bounds_min": [0, 0, 0],
		"bounds_max": [2, 5, 1], "block_count": 10, "prop_count": 0,
		"grids": [{"cell_size": 1.0, "blocks": blocks, "materials": {}, "props": []}]}
	var site := BlueprintSite.create(data, planet, Transform3D(Basis.IDENTITY, Vector3(8.0, 0.0, 6.0)), "muro")
	var chest := _chest(Vector3(4.0, 0.0, -4.0))
	var cost := site.get_cost()
	for id: StringName in cost:
		chest.inventory.add_item(_item(id), int(cost[id]) + 5)
	var builder := _spawn(Vector3(3.0, 0.05, 0.0), Companion.Mode.SETTLE)
	builder.settle_here(_local(Vector3(3.0, 0.05, 0.0)))
	builder.pack.add_item(_item(&"stone_hammer_01"), 1)
	builder.work.assign(SettlerWork.Job.BUILD)
	var left := 150.0
	var planted := false
	var aloft := 0.0
	var high := 0.0
	while left > 0.0 and is_instance_valid(site) and not site.is_complete():
		await _wait(0.5)
		left -= 0.5
		var task := builder.work.task as SettlerBuild
		if task != null and task._scaffold != null and is_instance_valid(task._scaffold):
			planted = true
			high = maxf(high, task._scaffold.height)
			if task._on_scaffold():
				aloft += 0.5
	check(not is_instance_valid(site) or site.is_complete(), "levanta el muro de 5 m (%.0f s)" % (150.0 - left))
	check(planted and high >= 1.0, "planta un andamio para lo alto (hasta %.1f m)" % high)
	check(aloft > 2.0, "y martillea desde arriba (%.1f s en la plataforma)" % aloft)
	await _wait(15.0)
	var task := builder.work.task as SettlerBuild
	check(task == null or task._scaffold == null, "al acabar lo quita")
	check(not builder.is_climbing() and (builder.global_position - Vector3(0, 0, 0)).y < 0.6,
		"y queda en el suelo (a %.2f m)" % builder.global_position.y)
	chest.queue_free()
	GridManager.clear_all()
	planet.queue_free()
	await _clear()


# --- Trabajo en campo (la rueda del grupo) ------------------------------------------------------------

func _check_field_work() -> void:
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	var planet := Node3D.new()
	planet.name = "FieldPlanet"
	_host.add_child(planet)
	var site := BlueprintSite.create(_blueprint(), planet, Transform3D(Basis.IDENTITY, Vector3(10.0, 0.0, 6.0)), "campo")
	var cost := site.get_cost()
	var builder := _spawn(Vector3(3.0, 0.05, 0.0))
	builder.pack.add_item(_item(&"stone_hammer_01"), 1)
	for id: StringName in cost:
		builder.pack.add_item(_item(id), int(cost[id]) + 5)
	var who: Array[Companion] = [builder]
	check(_companions.order_work(SettlerWork.Job.BUILD, site.get_center(), who) == 1 and builder.is_field_working()
		and builder.mode == Companion.Mode.WAIT and builder.work.field, "«trabajad: construid» lo pone a construir en campo")
	var saved: Dictionary = (_companions.get_save_data().companions as Array)[0]
	check(saved.has("field_work") and bool((saved.field_work as Dictionary).get("field", false)),
		"y el trabajo en campo se guarda con él")
	var left := 90.0
	while left > 0.0 and is_instance_valid(site) and not site.is_complete():
		await _wait(1.0)
		left -= 1.0
	check(not is_instance_valid(site) or site.is_complete(),
		"sin cofres, levanta la obra con lo de su morral (%.0f s; %s)" % [90.0 - left, builder.work.describe()])
	var kept := true
	for id: StringName in cost:
		kept = kept and builder.pack.get_item_count(_item(id)) == 5
	check(kept, "y lo que sobra se queda en su morral")
	check(_companions.order_follow(who) == 1 and not builder.work.active() and builder.mode == Companion.Mode.FOLLOW,
		"«seguidme» lo saca del trabajo")
	# Cocinar en campo: la hoguera de cerca, lo crudo y la leña de su morral.
	var fire := Campfire.new()
	_host.add_child(fire)
	fire.global_position = Vector3(-10.0, 0.0, 2.0)
	var raw := _item(&"raw_meat")
	var cooked := _item(&"cooked_meat")
	var cook := _spawn(Vector3(-5.0, 0.05, 0.0))
	cook.pack.add_item(raw, 3)
	cook.pack.add_item(_item(SettlerWork.WOOD_ID), 10)
	who = [cook]
	check(_companions.order_work(SettlerWork.Job.COOK, fire.global_position, who) == 1, "«cocinad» lo pone a cocinar en campo")
	left = 240.0
	while left > 0.0 and cook.pack.get_item_count(cooked) < 3:
		await _wait(2.0)
		left -= 2.0
	check(cook.pack.get_item_count(cooked) == 3 and cook.pack.get_item_count(raw) == 0,
		"asa lo crudo de su morral y se queda lo asado (%.0f s)" % (240.0 - left))
	cook.work.pack_full()
	check(not cook.work.active() and cook.mode == Companion.Mode.WAIT, "con el morral lleno lo deja y se queda esperando")
	fire.queue_free()
	GridManager.clear_all()
	planet.queue_free()
	await _clear()


## En campo, los que recolectan llevan lo que sacan a quien lo necesita: al constructor, a su obra; al
## cocinero, en mano. Solo lo que falta.
func _check_field_delivery() -> void:
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	var planet := Node3D.new()
	planet.name = "DeliveryPlanet"
	_host.add_child(planet)
	var site := BlueprintSite.create(_blueprint(), planet, Transform3D(Basis.IDENTITY, Vector3(10.0, 0.0, 6.0)), "reparto")
	var cost := site.get_cost()
	var builder := _spawn(Vector3(8.0, 0.05, 2.0))
	builder.pack.add_item(_item(&"stone_hammer_01"), 1)
	var quarry := _spawn(Vector3(-12.0, 0.05, -6.0))
	quarry.pack.add_item(_item(&"stone_pickaxe_01"), 1)
	for id: StringName in cost:
		quarry.pack.add_item(_item(id), int(cost[id]) + 4)
	_companions.order_work(SettlerWork.Job.BUILD, site.get_center(), [builder] as Array[Companion])
	# El cantero pica lejos de la obra (no hay rocas en la prueba: lo que lleva hace de lo picado).
	_companions.order_work(SettlerWork.Job.MINE, Vector3(-14.0, 0.0, -8.0), [quarry] as Array[Companion])
	var left := 120.0
	while left > 0.0 and is_instance_valid(site) and not site.is_complete():
		await _wait(1.0)
		left -= 1.0
	check(not is_instance_valid(site) or site.is_complete(),
		"el cantero lleva la piedra a la obra y el constructor la levanta (%.0f s; %s)" % [120.0 - left, builder.work.describe()])
	var only_needed := true
	for id: StringName in cost:
		only_needed = only_needed and quarry.pack.get_item_count(_item(id)) == 4 and builder.pack.get_item_count(_item(id)) == 0
	check(only_needed, "solo lleva lo que falta: el resto se lo queda")
	check(not SettlerBuild._hauls.has(quarry.get_instance_id()), "y ya no se apunta como que trae nada")
	# Al cocinero: lo crudo y la leña, en mano.
	var fire := Campfire.new()
	_host.add_child(fire)
	fire.global_position = Vector3(-6.0, 0.0, 8.0)
	var raw := _item(&"raw_meat")
	var cook := _spawn(Vector3(-4.0, 0.05, 8.0))
	var woodcutter := _spawn(Vector3(6.0, 0.05, -10.0))
	woodcutter.pack.add_item(_item(&"stone_axe_01"), 1)
	woodcutter.pack.add_item(raw, 3)
	woodcutter.pack.add_item(_item(SettlerWork.WOOD_ID), 20)
	_companions.order_work(SettlerWork.Job.COOK, fire.global_position, [cook] as Array[Companion])
	_companions.order_work(SettlerWork.Job.FELL, Vector3(8.0, 0.0, -12.0), [woodcutter] as Array[Companion])
	left = 240.0
	var cooked := _item(&"cooked_meat")
	while left > 0.0 and cook.pack.get_item_count(cooked) < 3:
		await _wait(2.0)
		left -= 2.0
	check(cook.pack.get_item_count(cooked) == 3 and woodcutter.pack.get_item_count(raw) == 0,
		"el leñador le lleva lo crudo y la leña al cocinero, que lo asa (%.0f s)" % (240.0 - left))
	check(woodcutter.pack.get_item_count(_item(SettlerWork.WOOD_ID)) == 20 - SettlerCook.WANT_FUEL,
		"y de leña, solo lo que pide (le quedan %d)" % woodcutter.pack.get_item_count(_item(SettlerWork.WOOD_ID)))
	fire.queue_free()
	GridManager.clear_all()
	planet.queue_free()
	await _clear()


## Al oír caer un árbol, el que está en su camino se aparta de lado; el que está detrás del tocón, no.
func _check_tree_dodge() -> void:
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	check(is_equal_approx(Companion.hear_chance(10.0, false), Companion.HEAR_SURE_CHANCE)
		and Companion.hear_chance(60.0, false) == 0.0 and Companion.hear_chance(10.0, true) < 0.5
		and Companion.hear_chance(35.0, false) < Companion.HEAR_SURE_CHANCE,
		"cerca casi siempre lo oye; lejos, no; dormido, la mitad")
	var a := Vector3(20.0, 0.05, 0.0)
	var b := Vector3(20.0, 0.05, 12.0)
	var half := 1.0
	var under := _spawn(Vector3(20.3, 0.05, 6.0))
	under.wait_here()
	var behind := _spawn(Vector3(20.0, 0.05, -3.0))
	behind.wait_here()
	check(under.dodge_fall(a, b, half) and not behind.dodge_fall(a, b, half),
		"se aparta el que está en su camino, no el que está detrás del tocón")
	await _wait(3.0)
	var lateral := absf(under.global_position.x - 20.0)
	check(lateral > half + Villager.BODY_RADIUS + Companion.FLEE_MARGIN,
		"y en 3 s ya está fuera de su camino (a %.1f m del tronco)" % lateral)
	check(behind.global_position.distance_to(Vector3(20.0, 0.05, -3.0)) < 0.5, "el de detrás sigue donde estaba")
	await _clear()


## Una caja de [size] con la base en [base] (mundo), de suelo.
func _block(base: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_host.add_child(body)
	body.global_position = base + Vector3(0.0, size.y * 0.5, 0.0)
	return body


## Mandado a un sitio al pie de un risco de 6 m (sin bajada) se para en el borde; de un escalón de 1 m
## baja andando.
func _check_ledge() -> void:
	_player.global_position = Vector3(-140.0, 0.05, 0.0)
	var cliff := _block(Vector3(-150.0, 0.0, 0.0), Vector3(10.0, 6.0, 10.0))
	var step := _block(Vector3(-150.0, 0.0, 30.0), Vector3(10.0, 1.0, 10.0))
	var top := _spawn(Vector3(-150.0, 6.05, 0.0))
	var low := _spawn(Vector3(-150.0, 1.05, 30.0))
	await _wait(0.3)
	check(top.go_to(Vector3(-150.0, 0.05, 12.0)) and low.go_to(Vector3(-150.0, 0.05, 42.0)), "se les manda bajar")
	await _wait(10.0)
	var height := top.global_position.y
	check(height > 5.5, "no se tira del risco (a %.1f m de alto, a %.1f m del borde)"
		% [height, 5.0 - absf(top.global_position.z)])
	check(low.global_position.y < 0.5 and low.global_position.distance_to(Vector3(-150.0, 0.05, 42.0)) < 1.5,
		"del escalón baja y llega (a %.1f m)" % low.global_position.distance_to(Vector3(-150.0, 0.05, 42.0)))
	cliff.queue_free()
	step.queue_free()
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
	# Las comidas: del comedero de su base (los cofres ya no dan de comer), lo asado antes que lo crudo.
	cook.meals.fed = 1.0
	check(cook.meals.eat(cook.meals._feeders()) == 0 and chest.inventory.get_item_count(cooked) == 8,
		"sin comedero no come de los cofres")
	var feeder := _feeder(Vector3(-4.0, 0.0, -5.0))
	check(feeder.inventory.add_item(wood, 1) == 1 and not feeder.accepts_job(&"fell"),
		"el comedero solo admite comida y nadie deja allí lo que saca")
	feeder.inventory.add_item(cooked, 3)
	feeder.inventory.add_item(raw, 2)
	var eaten := cook.meals.eat(cook.meals._feeders())
	check(eaten >= 1 and cook.meals.fed >= SettlerMeals.EAT_UNTIL and feeder.inventory.get_item_count(cooked) == 3 - eaten
		and feeder.inventory.get_item_count(raw) == 2, "con hambre come lo asado del comedero (%d piezas)" % eaten)
	feeder.inventory.remove_item(cooked, 99)
	cook.meals.fed = 0.5
	cook.meals.eat(cook.meals._feeders())
	check(feeder.inventory.get_item_count(raw) < 2, "y lo crudo solo si no hay otra cosa")
	# Con comedero, lo asado va a él.
	feeder.inventory.remove_item(raw, 99)
	chest.inventory.add_item(raw, 2)
	left = 240.0
	while left > 0.0 and feeder.inventory.get_item_count(cooked) < 2:
		await _wait(2.0)
		left -= 2.0
	check(feeder.inventory.get_item_count(cooked) == 2 and chest.inventory.get_item_count(cooked) == 8,
		"con comedero, el cocinero deja en él lo asado (%.0f s)" % (240.0 - left))
	fire.queue_free()
	chest.queue_free()
	feeder.queue_free()
	await _clear()


## Lo que tiene la base (BaseSupplies, el panel del trono): camas, comida del comedero, de los morrales
## y de los cofres, agua y para cuántos días.
func _check_supplies() -> void:
	await _clear()
	for node in get_tree().get_nodes_in_group(Storage.GROUP) + get_tree().get_nodes_in_group(WaterTrough.GROUP) \
			+ get_tree().get_nodes_in_group(Bedroll.GROUP):
		node.queue_free()
	await _wait(0.1)
	var at := Vector3(60.0, 0.05, -60.0)
	var group: Array[Companion] = []
	for k in 2:
		var c := _spawn(at + Vector3(k, 0.0, 0.0), Companion.Mode.SETTLE)
		c.settle_here(_local(at))
		c.pack.clear()
		group.append(c)
	var empty := BaseSupplies.gather(get_tree(), group)
	check(empty.settlers == 2 and empty.beds == 0 and empty.feeders == 0 and empty.troughs == 0
		and is_zero_approx(empty.water_days), "sin nada en la base: dos colonos, sin camas ni comedero ni bebedero")
	check(BaseSupplies.level_of_beds(0, 2) == BaseSupplies.Level.BAD and BaseSupplies.level_of_beds(1, 2) == BaseSupplies.Level.LOW
		and BaseSupplies.level_of_beds(2, 2) == BaseSupplies.Level.GOOD, "camas: ninguna mal, alguna regular, una por cabeza bien")
	var bed := Bedroll.new()
	_host.add_child(bed)
	bed.global_position = at + Vector3(5.0, 0.0, 0.0)
	var far_bed := Bedroll.new()
	_host.add_child(far_bed)
	far_bed.global_position = at + Vector3(Companion.BASE_RADIUS + 10.0, 0.0, 0.0)
	var feeder := _feeder(at + Vector3(0.0, 0.0, 4.0))
	feeder.inventory.add_item(_item(&"cooked_meat"), 4)
	var chest := _chest(at + Vector3(0.0, 0.0, -4.0))
	chest.inventory.add_item(_item(&"cooked_meat"), 3)
	var trough := _trough(at + Vector3(4.0, 0.0, 4.0))
	trough.pour(30)
	group[0].pack.add_item(_item(&"cooked_meat"), 1)
	var b := BaseSupplies.gather(get_tree(), group)
	var meal := (_item(&"cooked_meat").get_trait(EdibleTrait) as EdibleTrait).hunger * SettlerMeals.FULL_HOURS
	check(b.beds == 1, "cuenta el petate de la base y no el de lejos (%d)" % b.beds)
	check(b.feeders == 1 and b.feeder_food == 4 and b.cooked == 4 and b.pack_food == 1 and b.chest_food == 3,
		"comida: 4 en el comedero (asadas), 1 en un morral y 3 en el cofre aparte")
	check(is_equal_approx(b.food_days, meal * 5.0 / 48.0), "días de comida: lo del comedero y los morrales entre dos (%.2f)" % b.food_days)
	check(b.troughs == 1 and b.water == 30 and b.water_capacity == WaterTrough.CAPACITY
		and is_equal_approx(b.water_days, 30.0 * SettlerMeals.SIP_HOURS / 48.0), "agua: 30 tragos, %.1f días para dos" % b.water_days)
	group[1].meals.fed = 0.0
	group[1].meals.watered = 0.0
	b = BaseSupplies.gather(get_tree(), group)
	check(b.hungry == 1 and b.thirsty == 1, "cuenta quién tiene hambre y sed")
	for node in [bed, far_bed, feeder, chest, trough]:
		node.queue_free()
	await _clear()


## La sed y el bebedero: beben de él lejos sin moverse y cerca van andando, primero a comer.
func _check_thirst() -> void:
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	var c := _spawn(Vector3(20.0, 0.05, 20.0), Companion.Mode.SETTLE)
	c.settle_here(_local(c.global_position))
	c.hour = 15.0
	var trough := _trough(Vector3(26.0, 0.0, 20.0))
	check(trough.pour(70) == WaterTrough.CAPACITY and trough.room() == 0, "el bebedero guarda hasta %d tragos" % WaterTrough.CAPACITY)
	trough.take(WaterTrough.CAPACITY)
	c.meals.watered = 0.0
	check(c.meals.thirsty() and is_equal_approx(c.work.pace(), SettlerWork.HUNGRY_PACE), "con sed, a la mitad")
	c.meals.fed = 0.0
	check(is_equal_approx(c.work.pace(), SettlerWork.HUNGRY_PACE * SettlerWork.HUNGRY_PACE), "con hambre y sed, a un cuarto")
	check(c.work.wants() == tr("SETTLER_HUNGRY") + tr("SETTLER_THIRSTY"), "y se dice: «%s»" % c.work.wants())
	c.meals._check_left = 0.0
	c.meals.tick(0.01, false)
	check(c.meals.thirsty(), "con el bebedero vacío sigue con sed")
	trough.pour(10)
	c.meals._check_left = 0.0
	c.meals.tick(0.01, false)
	check(not c.meals.thirsty() and c.meals.watered >= SettlerMeals.DRINK_BELOW and trough.water < 10 and c.meals.trip == null,
		"lejos bebe del bebedero sin moverse (%d tragos)" % (10 - trough.water))
	# Cerca va andando: con hambre y sed, primero al comedero y luego al bebedero.
	var feeder := _feeder(Vector3(20.0, 0.0, 27.0))
	var chest := _chest(Vector3(19.0, 0.0, 18.0))
	chest.inventory.add_item(_item(&"cooked_meat"), 5)
	feeder.inventory.add_item(_item(&"cooked_meat"), 3)
	c.meals.fed = 1.0
	c.meals.watered = 1.0
	c.meals._check_left = 0.0
	c.meals.tick(0.01, true)
	check(c.meals.trip == feeder, "cerca, con hambre y sed, va antes al comedero")
	var left := 40.0
	while left > 0.0 and (c.meals.fed < SettlerMeals.EAT_UNTIL or c.meals.watered < SettlerMeals.DRINK_BELOW):
		await _wait(1.0)
		left -= 1.0
	check(c.meals.fed >= SettlerMeals.EAT_UNTIL and feeder.inventory.get_item_count(_item(&"cooked_meat")) < 3
		and chest.inventory.get_item_count(_item(&"cooked_meat")) == 5, "llega andando al comedero y come (%.0f s)" % (40.0 - left))
	check(c.meals.watered >= SettlerMeals.DRINK_BELOW and c.global_position.distance_to(trough.global_position) < 2.5,
		"y luego bebe en el bebedero (a %.1f m)" % c.global_position.distance_to(trough.global_position))
	# El aguador.
	c.process_mode = Node.PROCESS_MODE_DISABLED
	c.work.assign(SettlerWork.Job.WATER)
	c.work.away(1.0, 10.0)
	check(c.work.status == SettlerWork.Status.BLOCKED, "el aguador sin odre se queda parado: «%s»" % c.work.describe())
	c.pack.add_item(_item(&"waterskin"), 1)
	var water := c.work.task as SettlerWater
	var before := trough.water
	c.work.away(SettlerWater.AWAY_TRIP + 1.0, 10.0)
	check(trough.water == before, "sin haber encontrado agua dulce no trae nada lejos")
	water._spot = _local(Vector3(30.0, 0.0, 20.0))
	water._water = _local(Vector3(32.0, 0.0, 20.0))
	c.work.away(SettlerWater.AWAY_TRIP + 1.0, 10.0)
	check(trough.water == mini(before + water.capacity(), WaterTrough.CAPACITY) and water.capacity() > 0,
		"con su orilla vista, lejos llena el bebedero (%d → %d)" % [before, trough.water])
	water._carry = 7
	var data: Dictionary = JSON.parse_string(JSON.stringify(c.work.save_data()))
	c.work.stop()
	c.work.restore(data)
	check(c.work.task is SettlerWater and (c.work.task as SettlerWater)._carry == 7
		and (c.work.task as SettlerWater)._spot.is_finite(), "el aguador guarda lo que lleva y su orilla")
	trough.water = WaterTrough.CAPACITY
	var saved := trough.get_save_data()
	var copy := WaterTrough.new()
	copy.restore_save_data(saved)
	check(copy.water == WaterTrough.CAPACITY, "el bebedero se guarda con su agua")
	copy.free()
	trough.queue_free()
	feeder.queue_free()
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
	c.meals.eat([])
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


## Sin cocinero en la base, lo que se come que traen el cazador y el pescador va al comedero; con
## cocinero, al cofre (él lo asa). Y despiezan con el clip agachado (AnimSplice).
func _check_food_drop() -> void:
	var chest := _chest(Vector3(80.0, 0.0, 0.0))
	var feeder := _feeder(Vector3(82.0, 0.0, 0.0))
	var hunter := _spawn(Vector3(81.0, 0.05, 2.0), Companion.Mode.SETTLE)
	hunter.settle_here(_local(Vector3(81.0, 0.05, 2.0)))
	check(hunter.has_anim(AnimSplice.BUTCHER), "el colono tiene el clip de despiezar agachado")
	hunter.pack.add_item(_item(&"stone_axe_01"), 1)
	hunter.work.assign(SettlerWork.Job.HUNT)
	hunter.work.away(SettlerHunt.AWAY_KILL + 1.0, 10.0)
	var meat := _item(HuntingLoot.MEAT)
	check(feeder.inventory.get_item_count(meat) == SettlerHunt.AWAY_MEAT and chest.inventory.get_item_count(meat) == 0,
		"sin cocinero, la carne al comedero (%d en el comedero, %d en el cofre)" % [
			feeder.inventory.get_item_count(meat), chest.inventory.get_item_count(meat)])
	check(chest.inventory.get_item_count(_item(HuntingLoot.HIDE)) == SettlerHunt.AWAY_HIDE, "y la piel al cofre")
	var cook := _spawn(Vector3(84.0, 0.05, 2.0), Companion.Mode.SETTLE)
	cook.settle_here(_local(Vector3(84.0, 0.05, 2.0)))
	cook.work.assign(SettlerWork.Job.COOK)
	hunter.work.away(SettlerHunt.AWAY_KILL + 1.0, 10.0)
	check(chest.inventory.get_item_count(meat) == SettlerHunt.AWAY_MEAT, "con cocinero, al cofre")
	chest.queue_free()
	feeder.queue_free()
	await _clear()


## Las zonas del trono (SettlerZones): los sin oficio de cerca la llenan hasta el cupo; bajarlo suelta
## al que sobra; quitarla para a los suyos; y se guardan.
func _check_zones() -> void:
	var zones := _companions.zones
	var settlers: Array[TestCompanion] = []
	for i in 3:
		var c := _spawn(Vector3(-30.0 - i * 2.0, 0.05, 10.0), Companion.Mode.SETTLE)
		c.settle_here(_local(c.global_position))
		settlers.append(c)
	var zone := zones.add(SettlerWork.Job.FELL, 0, _local(Vector3(-40.0, 0.0, 20.0)), 10.0, 2)
	var id := int(zone.id)
	await _wait(SettlerZones.TICK + 0.5)
	var inside := zones.members(id, _companions.get_companions())
	check(inside.size() == 2, "dos de los tres sin oficio van a la zona de cupo 2 (%d)" % inside.size())
	check(inside.all(func(c: Companion) -> bool: return c.work.job == SettlerWork.Job.FELL and c.work.zone.is_finite()),
		"talando en ella")
	zones.set_quota(id, 1)
	await _wait(SettlerZones.TICK + 0.5)
	check(zones.members(id, _companions.get_companions()).size() == 1, "con cupo 1, uno la deja")
	var saved := zones.save_data()
	var copy := SettlerZones.new()
	copy.restore(saved)
	check(copy.list.size() == 1 and int(copy.find(id).quota) == 1, "se guarda con su cupo")
	zones.remove(id, _companions.get_companions())
	check(zones.list.is_empty() and settlers.all(func(c: Companion) -> bool: return c.work.job == SettlerWork.Job.NONE),
		"al quitarla, los suyos lo dejan")
	await _clear()


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


## La charla con un colono: «¿qué haces?» y «¿qué te falta?» dicen en primera persona lo que le para,
## y el aviso de que está parado sale una vez.
func _check_talk() -> void:
	var c := _spawn(Vector3(-60.0, 0.05, 0.0), Companion.Mode.SETTLE)
	c.settle_here(_local(Vector3(-60.0, 0.05, 0.0)))
	var needs := VillagerTalk.settler_needs(c)
	check(needs.text.contains(tr("SETTLER_ME_NO_JOB")), "sin oficio dice que se lo mandes: «%s»" % needs.text)
	check(VillagerTalk.settler_doing(c).key == "SETTLER_SAY_IDLE", "y que hace su vida")
	c.work.assign(SettlerWork.Job.FELL)
	c.work.away(1.0, 10.0)
	var stuck := c.work.stuck()
	check(not stuck.is_empty() and stuck[0] == "SETTLER_ME_NO_AXE", "el leñador sin hacha sabe qué le falta")
	var doing := VillagerTalk.settler_doing(c)
	check(doing.text.contains(tr("SETTLER_ME_NO_AXE")) and doing.text.contains(tr("SETTLER_SAY_AROUND_BASE")),
		"«¿qué haces?»: «%s»" % doing.text)
	check(VillagerTalk.settler_needs(c).text.contains(tr("SETTLER_ME_NO_AXE")), "«¿qué te falta?» también lo dice")
	# El aviso: tras seguir parado por lo mismo, una vez.
	c.work.watch(SettlerWork.WATCH_EVERY)
	c.work._stuck_since -= SettlerWork.STUCK_NOTICE + 1.0
	c.work.watch(SettlerWork.WATCH_EVERY)
	c.work.watch(SettlerWork.WATCH_EVERY)
	check(c.work._noticed.size() == 1, "avisa una vez de que está parado (%d)" % c.work._noticed.size())
	c.work.block("SETTLER_BUILD_SHORT", [12, "Madera"])
	check(c.work.reason == tr("SETTLER_BUILD_SHORT") % [12, "Madera"]
		and c.work.say_stuck(c.work.stuck()) == tr("SETTLER_BUILD_SHORT_ME") % [12, "Madera"],
		"parado por algo con argumentos: «%s»" % c.work.say_stuck(c.work.stuck()))
	# Todas las frases existen.
	for key in ["SETTLER_NEED_HAMMER", "SETTLER_NEED_WEAPON", "SETTLER_NEED_ROD", "SETTLER_NEED_SKIN",
			"SETTLER_NO_WATER", "SETTLER_NO_FRESH_WATER", "SETTLER_NO_TROUGH", "SETTLER_NO_FIRE",
			"SETTLER_CHEST_FULL_SHORT", "SETTLER_NO_CHEST_SHORT", "SETTLER_BUILD_NO_CHEST", "SETTLER_BUILD_SHORT",
			"SETTLER_ME_NO_PICK", "SETTLER_ME_NO_TOOL_CLEAR", "SETTLER_ME_FINE", "SETTLER_ME_NO_BED", "SETTLER_ME_HURT"]:
		var me: String = key if key.begins_with("SETTLER_ME_") else key + "_ME"
		check(tr(me) != me, "existe la frase %s" % me)
	for what in ["FOOD", "WATER"]:
		for state in ["LACKING", "LACKING_EMPTY", "LACKING_NONE", "EMPTY", "NONE"]:
			var key := "SETTLER_ME_%s_%s" % [what, state]
			check(tr(key) != key, "existe la frase %s" % key)
	for job: int in SettlerWork.Job.values():
		if job == SettlerWork.Job.NONE:
			continue
		var key: String = "SETTLER_SAY_" + SettlerWork.Job.keys()[job]
		for variant in (["_DAY", "_NIGHT"] if job == SettlerWork.Job.GUARD else [""]):
			check(tr(key + variant) != key + variant, "existe la frase %s" % (key + variant))
	c.work.stop()


## Con la zona marcada lejos de la cámara (sin cargar: no se ven orillas ni animales), el pescador y el
## cazador van hacia ella en vez de quedarse en la base diciendo que trabajan.
func _check_far_zone() -> void:
	var camera := Camera3D.new()
	_host.add_child(camera)
	camera.global_position = Vector3(0.0, 2.0, 0.0)
	camera.current = true
	var chest := _chest(Vector3(-80.0, 0.0, 40.0))
	var c := _spawn(Vector3(-80.0, 0.05, 45.0), Companion.Mode.SETTLE)
	c.settle_here(_local(Vector3(-80.0, 0.05, 45.0)))
	c.pack.add_item(_item(&"fishing_rod"), 1)
	c.work.assign(SettlerWork.Job.FISH, _local(Vector3(-80.0, 0.0, 230.0)), 20.0)
	check(not c.work._zone_loaded(), "la zona lejana no está cargada")
	for label in ["al buscar", "y entre búsqueda y búsqueda"]:
		var go: Array = c.work.step(0.1)
		check(float(go[1]) > 0.0 and (go[0] as Vector3).dot(Vector3.BACK) > 0.5,
			"el pescador va hacia su zona lejana %s (%s)" % [label, str(go)])
	check(c.work.status == SettlerWork.Status.WORKING, "y no se da por parado")
	c.pack.add_item(_item(&"stone_axe_01"), 1)
	c.work.assign(SettlerWork.Job.HUNT, _local(Vector3(-80.0, 0.0, 230.0)), 20.0)
	c.work.step(0.1)
	var hunt: Array = c.work.step(0.1)
	check(float(hunt[1]) > 0.0 and (hunt[0] as Vector3).dot(Vector3.BACK) > 0.5,
		"el cazador sin presas a la vista va a su zona (%s)" % str(hunt))
	c.work.stop()
	chest.queue_free()
	camera.queue_free()


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


# --- Equipo, caminos y agua ------------------------------------------------------------------------

## Se pone del morral la ropa, la armadura, el escudo y el arco; quitándoselos vuelve a lo suyo.
func _check_gear() -> void:
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	var outfit: Array[StringName] = [&"fur_mantle", &"fur_loincloth", &"fur_moccasins"]
	var c := _spawn(Vector3(3.0, 0.05, 0.0), Companion.Mode.WAIT, outfit)
	await _wait(0.2)
	var worn := c.gear.worn()
	check(worn.size() == 3 and (worn[ItemData.ArmorSlot.CHEST] as ItemData).id == &"fur_mantle",
		"lleva puesta la ropa de su poblado (%s)" % [worn.values().map(func(d): return d.id)])
	var before := c.health.armor_slash + c.health.armor_blunt + c.health.armor_pierce
	var tunic := _item(&"hide_tunic")
	c.pack.add_item(tunic, 1)
	worn = c.gear.worn()
	check((worn[ItemData.ArmorSlot.CHEST] as ItemData).id == (&"hide_tunic" if Armor.of(tunic).length() > Armor.of(_item(&"fur_mantle")).length() else &"fur_mantle"),
		"se pone la pieza del morral que más protege en su hueco (%s)" % (worn[ItemData.ArmorSlot.CHEST] as ItemData).id)
	var skeleton := c.get_node("%s/Armature/Skeleton3D" % c._model.name) as Skeleton3D
	var tunics := skeleton.get_children().filter(func(n): return n.scene_file_path == tunic.scene_path).size()
	var mantles := skeleton.get_children().filter(func(n): return n.scene_file_path == _item(&"fur_mantle").scene_path \
		and not n.is_queued_for_deletion()).size()
	if (worn[ItemData.ArmorSlot.CHEST] as ItemData).id == &"hide_tunic":
		check(tunics == 1 and mantles == 0, "y se quita la de su poblado (túnicas %d, mantos %d)" % [tunics, mantles])
		var after := c.health.armor_slash + c.health.armor_blunt + c.health.armor_pierce
		check(after > before, "y le protege más (%.1f → %.1f)" % [before, after])
	var helmet: ItemData
	for id in [&"hide_hood", &"firstage_skin_hood", &"fur_hood", &"wolf_hood"]:
		if _item(id) != null and _item(id).armor_slot == ItemData.ArmorSlot.HEAD:
			helmet = _item(id)
			break
	if helmet != null:
		c.pack.add_item(helmet, 1)
		check(c.gear.worn().has(ItemData.ArmorSlot.HEAD), "se pone en la cabeza lo que le falta (%s)" % helmet.id)
		c.pack.remove_item(helmet, 1)
		check(not c.gear.worn().has(ItemData.ArmorSlot.HEAD), "y se lo quita al sacárselo del morral")
	c.pack.remove_item(tunic, 1)
	worn = c.gear.worn()
	check((worn[ItemData.ArmorSlot.CHEST] as ItemData).id == &"fur_mantle", "sin la túnica vuelve a su manto")
	check(is_equal_approx(c.health.armor_slash + c.health.armor_blunt + c.health.armor_pierce, before),
		"y a lo que le protegía")
	# Escudo y arco.
	c.pack.add_item(_item(&"hide_shield"), 1)
	check(c.gear.shield != null and c.gear.shield.id == &"hide_shield" and c.health.guard.item == c.gear.shield,
		"lleva el escudo y para con él")
	c.pack.add_item(_item(&"hunting_bow"), 1)
	check(c.gear.bow != null and not c._can_shoot(), "con el arco y sin flechas no dispara")
	c.pack.add_item(_item(&"arrow"), 5)
	check(c._can_shoot() and c.gear.ammo_left(c.pack) == 5, "con flechas sí")
	check(c._weapon == null or c._weapon.id != &"hunting_bow", "el arco no es su arma de mano")
	c.pack.remove_item(_item(&"hide_shield"), 1)
	check(c.gear.shield == null and c.health.guard.item == null, "sin escudo no para")
	# Sin escudo: con un arma a dos manos que para, para con ella; con lo demás, esquiva.
	c._weapon = _item(&"stone_maul")
	check(c._guard_item() == c._weapon, "con la maza a dos manos se cubre con ella")
	c._weapon = _item(&"stone_axe_01")
	check(c._guard_item() == null, "con un hacha de una mano no tiene con qué parar")
	c._dodge_dir = Vector3.BACK
	c._dodge_t = 0.0
	c.combat_pose()
	var went := 0.0
	var safe := false
	for i in 60:
		var step: Array = c._dodging(1.0 / 60.0)
		went += float(step[1]) / 60.0
		safe = safe or not c._hurtbox.is_enabled()
		if c._dodge_t < 0.0:
			break
	check(c._dodge_t < 0.0 and absf(went - PlayerCombat.BACKSTEP_DISTANCE) < 0.4,
		"el paso atrás recorre lo del jugador (%.2f m)" % went)
	check(safe and c._hurtbox.is_enabled(), "sin que le den al principio, y luego otra vez sí")
	await _clear()


## Suelto, siguiendo al jugador al otro lado de una pared, la rodea por un camino (sin aparecer de golpe).
func _check_follow_wall() -> void:
	_companions.formation = SettlementCompanions.Formation.LOOSE
	_player.global_position = Vector3(0.0, 0.05, -4.0)
	# Una pared de 12 m de ancho y 3 de alto entre los dos.
	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 3.0, 0.4)
	shape.shape = box
	wall.add_child(shape)
	_host.add_child(wall)
	wall.global_position = Vector3(0.0, 1.5, 0.0)
	var c := _spawn(Vector3(0.0, 0.05, 3.0))
	c.follow()
	var last := c.global_position
	var jump := 0.0
	for i in 40:
		await _wait(0.5)
		jump = maxf(jump, c.global_position.distance_to(last))
		last = c.global_position
		if c.global_position.distance_to(_player.global_position) < 4.0:
			break
	var d := c.global_position.distance_to(_player.global_position)
	check(d < 4.5, "rodea la pared hasta el jugador (a %.1f m)" % d)
	check(jump < 4.0, "andando, sin aparecer de golpe (mayor salto %.1f m en 0,5 s)" % jump)
	wall.queue_free()
	_companions.formation = SettlementCompanions.Formation.WEDGE
	await _clear()


## En agua honda nada con la cabeza fuera (quieto, los pies a SWIM_FLOAT_IDLE m; nadando, a
## SWIM_FLOAT_MOVE) y sigue al jugador; donde hace pie vuelve a andar.
func _check_swim() -> void:
	_companions.formation = SettlementCompanions.Formation.LOOSE
	var loader := FakeLoader.new()
	_host.add_child(loader)
	loader.global_position = _terrain.global_position
	loader.global_pos = _terrain.global_position
	# El suelo (y = 0) a RADIUS del centro: el mar 3,5 m por encima.
	loader.planet.radius = RADIUS + 3.5
	loader.planet.water_radius = 0.0
	_player.planet = loader
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	var c := _spawn(Vector3(0.0, 0.05, 1.0))
	c.follow()
	await _wait(3.0)
	check(c.is_swimming(), "en agua de 3,5 m nada")
	var feet := c.global_position.distance_to(_terrain.global_position)
	check(absf(RADIUS + 3.5 - feet - Companion.SWIM_FLOAT_IDLE) < 0.3,
		"quieto flota con los pies a %.2f m bajo la superficie, la cabeza fuera (%.2f)" % [Companion.SWIM_FLOAT_IDLE,
		RADIUS + 3.5 - feet])
	_player.global_position = Vector3(0.0, 0.05, -20.0)
	var lowest := INF
	for i in 12:
		await _wait(0.5)
		lowest = minf(lowest, c.global_position.distance_to(_terrain.global_position))
	check(RADIUS + 3.5 - lowest < Companion.SWIM_FLOAT_IDLE + 0.3,
		"nadando no se hunde (los pies, como mucho a %.2f m)" % (RADIUS + 3.5 - lowest))
	check(c.is_swimming(), "y sigue nadando aunque lleve los pies más arriba de donde se pone a nadar")
	var d := c.global_position.distance_to(_player.global_position)
	check(d < 6.0, "nadando sigue al jugador (a %.1f m)" % d)
	check(c._anim == Companion.ANIM_SWIM or c._anim == Companion.ANIM_SWIM_IDLE, "con la animación de nadar (%s)" % c._anim)
	loader.planet.radius = RADIUS + 1.0
	await _wait(1.5)
	check(not c.is_swimming() and c.is_on_floor(), "donde hace pie vuelve a andar por el fondo")
	_player.planet = null
	loader.queue_free()
	_companions.formation = SettlementCompanions.Formation.WEDGE
	await _clear()


## El jugador trepa una pared de 4 m y corona: el compañero va al pie, trepa por donde él y queda de pie
## arriba (sin aparecer de golpe); el que viene detrás espera su turno.
func _check_climb() -> void:
	_companions.formation = SettlementCompanions.Formation.LOOSE
	# Un bloque de 6 m de ancho y 4 de alto: su cara, en z = 0, mirando a +Z.
	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 4.0, 4.0)
	shape.shape = box
	wall.add_child(shape)
	_host.add_child(wall)
	wall.global_position = Vector3(0.0, 2.0, -2.0)
	var climb := FakeClimb.new()
	_player.climb = climb
	_player.global_position = Vector3(0.0, 0.05, 1.0)
	var a := _spawn(Vector3(-1.0, 0.05, 6.0))
	var b := _spawn(Vector3(1.0, 0.05, 6.5))
	a.follow()
	b.follow()
	await _wait(0.5)
	# Trepa: de pie contra la pared hasta 2,4 m, y corona hasta 0,8 m dentro de lo alto.
	climb.active = true
	for i in 25:
		_player.global_position = Vector3(0.0, 0.05 + 0.1 * i, 0.38)
		await get_tree().physics_frame
	await _wait(1.0)
	var foot := Vector3(0.0, 0.05, 0.38)
	check(a.global_position.distance_to(foot) < 2.0 and not a.is_climbing(),
		"mientras trepa, el compañero va a su pie y espera (a %.1f m)" % a.global_position.distance_to(foot))
	climb.frame = Transform3D(Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD), Vector3(0.0, 4.0, -0.8))
	climb.topping = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	climb.active = false
	climb.topping = false
	_player.global_position = Vector3(0.0, 4.05, -1.2)
	await get_tree().physics_frame
	var route_done: bool = not _companions.routes.routes.is_empty() and _companions.routes.routes[-1].done
	check(route_done, "al coronar, la ruta queda hecha (%d puntos)" % (_companions.routes.routes[-1].points.size() if not _companions.routes.routes.is_empty() else 0))
	var climbed := {a: false, b: false}
	var started := {a: -1.0, b: -1.0}
	var jump := 0.0
	var last := {a: a.global_position, b: b.global_position}
	var topping := {a: false, b: false}
	for i in 60:
		await _wait(0.25)
		for c in [a, b]:
			climbed[c] = climbed[c] or c.is_climbing()
			if c.is_climbing() and started[c] < 0.0:
				started[c] = _companions.routes.clock
			# Al empezar a coronar el cuerpo salta al marco del clip (la cadera no): eso no cuenta.
			if c._topping == topping[c]:
				jump = maxf(jump, c.global_position.distance_to(last[c]))
			topping[c] = c._topping
			last[c] = c.global_position
		if not a.is_climbing() and not b.is_climbing() and a.global_position.y > 3.5 and b.global_position.y > 3.5:
			break
	check(climbed[a] and climbed[b], "los dos trepan")
	check(a.global_position.y > 3.5 and b.global_position.y > 3.5,
		"y quedan arriba (a %.2f y %.2f m)" % [a.global_position.y, b.global_position.y])
	check(a.is_on_floor() or b.is_on_floor() or (not a.is_climbing() and not b.is_climbing()), "de pie")
	var gap := absf(float(started[b]) - float(started[a]))
	check(gap >= ClimbRoutes.GAP - 0.3, "de uno en uno: el segundo empieza %.1f s después" % gap)
	check(jump < 1.5, "sin aparecer de golpe (mayor salto %.2f m en 0,25 s)" % jump)
	_player.climb = null
	_companions.routes.routes.clear()
	wall.queue_free()
	_companions.formation = SettlementCompanions.Formation.WEDGE
	await _clear()

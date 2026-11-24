extends Node

## Lo que el jugador les hace a los poblados, sin mundo ni gente vestida: el rencor (SettlementRelations:
## cerrar la puerta, la guardia hostil, enfriarse, guardarse), lo que se les da pasa a su género y se gasta
## (SettlementTrade.receive), lo de los arcones (stash) y robarlo (SettlementStash), y los golpes y la
## hostilidad del poblado (SettlementVillage.struck, target); y las fieras: solo ellas quitan vida a un aldeano,
## que sin ella cae malherido y luego se va a casa, y quién les planta cara (Villager._should_fight,
## SettlementVillage.beast_for). Ver con la gente de verdad, en juego.
##   godot --headless --path . --audio-driver Dummy res://tests/world/test_reputation.tscn

var failures := 0


func _ready() -> void:
	_run()
	print("RESULT: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)


func _run() -> void:
	_check_grudge()
	_check_received()
	_check_stash()
	_check_village()
	_check_beasts()


func _check_grudge() -> void:
	var r := SettlementRelations.new()
	r.add(0, 30.0)
	r.offend(0, SettlementVillage.HIT_GRUDGE, SettlementVillage.HIT_TRUST)
	check(r.closed(0) and not r.hostile(0) and r.trust(0) < 30.0 and not r.closed(1),
		"un golpe cierra la puerta del poblado y baja la confianza, no la de otro")
	r.offend(0, SettlementVillage.HIT_GRUDGE, SettlementVillage.HIT_TRUST)
	check(r.hostile(0), "dos golpes lo ponen hostil")
	var saved := r.save_data()
	var back := SettlementRelations.new()
	back.restore(saved)
	check(is_equal_approx(back.grudge(0), r.grudge(0)), "el rencor se guarda")
	r.advance(r.grudge(0) / SettlementRelations.GRUDGE_DECAY + 0.1)
	check(r.grudge(0) == 0.0 and not r.closed(0), "con las horas se enfría del todo")


func _check_received() -> void:
	var r := SettlementRelations.new()
	var trade := SettlementTrade.new(r, 3)
	var who := {"id": "0:0:0", "job": {"kind": &"woodpile"}}
	var before := int(trade.stock(who).get(&"bone", 0))
	trade.receive(who, {&"bone": 8})
	check(int(trade.stock(who).get(&"bone", 0)) == before + 8, "lo que se le da pasa a su género")
	var bone := ItemCatalog.get_item(&"bone")
	trade.deal(who, 0, {bone: 3}, {})
	check(int(trade.stock(who).get(&"bone", 0)) == before + 5, "y se puede volver a comprar")
	var axe := ItemCatalog.get_item(&"stone_axe_01")
	trade.deal(who, 0, {}, {axe: 1})
	check(int(trade.stock(who).get(&"stone_axe_01", 0)) >= 1, "lo que se entrega en un trato también")
	var saved := trade.save_data()
	r.advance(24.0)
	var next := int(trade.stock(who).get(&"bone", 0)) - int(trade._roll(SettlementTrade.STOCK[&"woodpile"], "0:0:0",
		"stock").get(&"bone", 0))
	check(next == 2, "al día siguiente le queda la mitad de lo recibido (%d)" % next)
	var back := SettlementTrade.new(SettlementRelations.new(), 3)
	back.restore(saved)
	check(int(back._given.get("0:0:0", {}).get("items", {}).get("bone", 0)) == 5, "lo recibido se guarda")


func _check_stash() -> void:
	var manager := SettlementManager.new()
	add_child(manager)
	var stash := SettlementStash.new()
	stash.key = "0:1:2"
	stash.kind = &"crate"
	stash.manager = manager
	add_child(stash)
	var found := ""
	for i in 20:
		stash.key = "0:1:%d" % i
		if not manager.trade.stash(stash.key, &"crate").is_empty():
			found = stash.key
			break
	check(found != "", "las cajas tienen género")
	stash.refill()
	var inv := stash.inventory
	var first: InventoryItem
	for item in inv.get_all_items():
		if item != null:
			first = item
			break
	var data := first.data
	var had := inv.get_item_count(data)
	# El jugador deja algo suyo y lo vuelve a coger: no es robar.
	var torch := ItemCatalog.get_item(&"waterskin")
	inv.add_item(torch, 1)
	for slot in inv.max_slots:
		var item := inv.get_item_at_slot(slot)
		if item != null and item.data == torch:
			inv.take_at(slot)
			# Como InventoryUI al mover algo.
			inv.inventory_changed.emit()
			break
	check(manager.trade.stash(found, &"crate").get(data.id, 0) == had, "coger lo que dejó el jugador no cuenta")
	for slot in inv.max_slots:
		var item := inv.get_item_at_slot(slot)
		if item != null and item.data == data:
			inv.take_at(slot, 1)
			inv.inventory_changed.emit()
			break
	check(int(manager.trade.stash(found, &"crate").get(data.id, 0)) == had - 1, "llevarse lo suyo se apunta")
	stash.refill()
	check(inv.get_item_count(data) == had - 1, "y no vuelve a salir hasta el día siguiente")
	manager.trade.relations.advance(24.0)
	check(not manager.trade.stash(found, &"crate").is_empty(), "al día siguiente se repone")
	stash.queue_free()
	manager.queue_free()


func _check_village() -> void:
	var plan := {"center": Vector3.UP, "ground": 1000.0, "template": &"aldea", "buildings": [], "extent": 30.0}
	var terrain := Node3D.new()
	add_child(terrain)
	var village := SettlementVillage.new(0, plan, {}, terrain)
	village.relations = SettlementRelations.new()
	var player := Node3D.new()
	add_child(player)
	player.global_position = Vector3.UP * 1000.0
	village.player = player
	var guard := Villager.new()
	guard.resident = {"id": "0:0:0", "name": "Guardia", "job": {"kind": &"guard"}}
	var farmer := Villager.new()
	farmer.resident = {"id": "0:0:1", "name": "Granjero", "job": {}}
	village.struck(farmer)
	village.struck(farmer)
	check(is_equal_approx(village.relations.grudge(0), SettlementVillage.HIT_GRUDGE),
		"un combo contra el mismo vecino cuenta una vez")
	check(village.closed() and village.target() == null, "pegar a uno cierra la puerta, sin guardia aún")
	village.struck(guard)
	village.update(SettlementVillage.DANGER_INTERVAL)
	check(village.hostile and village.danger and village.target() == player,
		"pegar al guardia pone hostil al poblado: cunde la alarma y la guardia va a por el jugador")
	player.global_position = Vector3.UP.rotated(Vector3.RIGHT, 0.2) * 1000.0
	village.update(SettlementVillage.DANGER_INTERVAL)
	check(not village.hostile and village.target() == null, "lejos del poblado ya no va a por él")
	check(village.robbed(10.0, player.global_position) == null and village.relations.grudge(0) <= 50.0,
		"sin testigos, robar no se apunta")
	guard.free()
	farmer.free()
	player.queue_free()
	terrain.queue_free()


func _check_beasts() -> void:
	var plan := {"center": Vector3.UP, "ground": 1000.0, "template": &"aldea", "buildings": [], "extent": 30.0}
	var terrain := Node3D.new()
	add_child(terrain)
	var village := SettlementVillage.new(1, plan, {}, terrain)
	village.relations = SettlementRelations.new()
	village.hour_override = 12.5
	var home := village.center + Vector3(6.0, 0.0, 0.0)
	village.homes = {0: {"door": home, "out": Vector3.RIGHT, "inside": home, "outside": home,
		"beds": [Transform3D(Basis.IDENTITY, home)], "work": []}}
	var player := Node3D.new()
	player.add_to_group(&"player")
	add_child(player)
	var who := {"id": "1:0:0", "name": "Leñador", "sex": &"male", "look": 7, "home": 0, "bed": 0,
		"job": {"kind": &"woodpile", "tool": &"stone_axe_01"}}
	var woodcutter := Villager.new()
	woodcutter.setup(who, village, Villager.build_model(who, [], SettlementVillagers.tool_of(who)))
	terrain.add_child(woodcutter)
	village.villagers.append(woodcutter)
	var seller_who := {"id": "1:0:1", "name": "Tendero", "sex": &"female", "look": 8, "home": 0, "bed": 0, "job": {}}
	var seller := Villager.new()
	seller.setup(seller_who, village, Villager.build_model(seller_who, []))
	terrain.add_child(seller)
	village.villagers.append(seller)
	var wolf := (load("res://scenes/animals/Wolf.tscn") as PackedScene).instantiate() as NPCController
	add_child(wolf)
	wolf.set_physics_process(false)
	wolf.perception.set_physics_process(false)
	wolf.global_position = woodcutter.global_position + Vector3(40.0, 0.0, 0.0)
	var health := woodcutter.health
	var hit := func(source: Node3D, amount: float) -> void:
		health.receive_hit(DamageInfo.create(amount, source, woodcutter.global_position, Vector3.FORWARD))
	hit.call(player, 30.0)
	check(is_equal_approx(health.health, Villager.HEALTH) and village.relations.grudge(1) > 0.0,
		"el golpe del jugador no le quita vida (pero cuenta para el rencor)")
	village.relations = SettlementRelations.new()
	hit.call(wolf, 60.0)
	check(is_equal_approx(health.health, Villager.HEALTH - 60.0) and woodcutter.act == Villager.Act.FLINCH,
		"la dentellada de una fiera sí: se dobla y le queda %.0f" % health.health)
	hit.call(wolf, 60.0)
	check(woodcutter.act == Villager.Act.DOWN and health.is_dead and woodcutter._hurtbox.collision_layer == 0
		and not woodcutter.can_chat(), "sin vida cae malherido: no encaja más golpes ni se le puede hablar")
	woodcutter._physics_process(Villager.DOWN_TIME + 0.1)
	check(woodcutter.act == Villager.Act.WALK and not health.is_dead and is_equal_approx(health.health, Villager.HEALTH)
		and woodcutter._scared_left > 0.0 and woodcutter._path[woodcutter._path.size() - 1].is_equal_approx(village.bed_foot(0, 0)),
		"a los %.0f s se levanta con toda su vida y se va a casa" % Villager.DOWN_TIME)
	check(not woodcutter._should_fight(), "y, asustado, no planta cara")
	woodcutter._scared_left = 0.0
	village.threat = wolf
	check(not woodcutter._should_fight(), "a la fiera que ataca lejos (40 m) no va")
	wolf.global_position = woodcutter.global_position + Vector3(10.0, 0.0, 0.0)
	check(woodcutter._should_fight() and not seller._should_fight(),
		"a la de 10 m va quien tiene herramienta; quien no, se esconde")
	wolf.global_position = woodcutter.global_position + Vector3(40.0, 0.0, 0.0)
	wolf.ai_controller.target = seller
	check(woodcutter._should_fight(), "y a la que va a por uno de los suyos, aunque esté lejos")
	wolf.ai_controller.target = null
	woodcutter._inside = 0
	wolf.global_position = woodcutter.global_position + Vector3(5.0, 0.0, 0.0)
	check(not woodcutter._should_fight(), "dentro de casa no sale")
	wolf.queue_free()
	woodcutter.queue_free()
	seller.queue_free()
	player.queue_free()
	terrain.queue_free()

extends Node

## Los encargos de los aldeanos sin mundo (SettlementQuests): que salgan todos los tipos donde se pueden
## pedir, su plazo, el regateo, fallar y dejarlo (baja la confianza), el recado, a dónde hay que ir y el
## guardado. Lo del mundo (el perdido, la escolta, la fiera) lo lleva QuestDirector y se prueba en juego.
##   godot --headless --path . --audio-driver Dummy res://tests/world/test_quests.tscn

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


func _quests(relations: SettlementRelations) -> SettlementQuests:
	var quests := SettlementQuests.new(relations, 7)
	# Dos poblados a 1,2 km en una esfera de 10 km.
	var a := Vector3(0, 1, 0)
	var b := Vector3(0.12, 1, 0).normalized()
	quests.villages = [{"center": a, "ground": 10000.0}, {"center": b, "ground": 10000.0}]
	quests.residents_of = func(v: int) -> Array:
		var out: Array = []
		for k in 4:
			out.append({"id": "%d:0:%d" % [v, k], "name": "Vecino%d_%d" % [v, k], "job": {}})
		return out
	return quests


func _run() -> void:
	var relations := SettlementRelations.new()
	relations.add(0, 30.0)
	var quests := _quests(relations)
	var prey: Array[StringName] = [&"Wolf", &"Bear"]
	var kinds := {}
	for p in 40:
		relations.clock = p * 24.0 * SettlementQuests.PERIOD
		for k in 4:
			var who := {"id": "0:0:%d" % k, "name": "Vecino0_%d" % k, "job": {}}
			var offer := quests.offer(who, 0, "Aldea", prey)
			if not offer.is_empty():
				kinds[String(offer.kind)] = int(kinds.get(String(offer.kind), 0)) + 1
	check(kinds.size() == SettlementQuests.KINDS.size(), "salen todos los tipos: %s" % [kinds])

	# Uno de cada tipo, para probarlo.
	var by_kind := {}
	for p in 80:
		relations.clock = p * 24.0 * SettlementQuests.PERIOD
		for k in 4:
			var who := {"id": "0:0:%d" % k, "name": "Vecino0_%d" % k, "job": {}}
			var offer := quests.offer(who, 0, "Aldea", prey)
			if not offer.is_empty() and not by_kind.has(String(offer.kind)):
				by_kind[String(offer.kind)] = [p, String(who.id)]
	var rescue := _take(quests, relations, by_kind, "rescue")
	check(rescue.has("due") and is_equal_approx(float(rescue.due) - relations.clock, SettlementQuests.HOURS.rescue),
		"al aceptarlo corre su plazo (%.0f h)" % (float(rescue.get("due", 0.0)) - relations.clock))
	check(String(rescue.get("stage", "")) == "search" and String(rescue.lost) != String(rescue.who),
		"el rescate busca a otro vecino (%s)" % rescue.get("lost_name", ""))
	check(quests.away_ids().has(String(rescue.lost)), "el perdido no está en su poblado")
	var target := quests.target_of(rescue)
	var spot := SettlementQuests.vec(rescue.spot)
	var hint := SettlementQuests.vec(target.at)
	check(bool(target.area) and hint.distance_to(spot) <= SettlementQuests.HINT_OFF + 1.0,
		"en el mapa sale la zona, no el sitio (a %.0f m)" % hint.distance_to(spot))
	var from := quests.center_of(0).distance_to(spot)
	check(from >= SettlementQuests.LOST_REACH.x - 1.0 and from <= SettlementQuests.LOST_REACH.y + 1.0,
		"y está a %.0f m del poblado" % from)
	var before := relations.trust(0)
	relations.clock = float(rescue.due) + 1.0
	check(quests.overdue().has(String(rescue.who)), "pasado el plazo, se pierde")
	var failed := quests.fail(String(rescue.who))
	check(relations.trust(0) < before and float(failed.lost) >= SettlementQuests.FAIL_MIN - 0.01,
		"y baja la confianza (−%.1f)" % float(failed.get("lost", 0.0)))

	# Regatear: una vez por oferta; si sale bien sube la paga.
	var escort := _offer(quests, relations, by_kind, "escort")
	var id := String(escort.get("who", ""))
	var trust := relations.trust(0)
	var haggled := quests.haggle(id)
	check(haggled != 0 and quests.haggle(id) == 0, "se regatea una sola vez (%d)" % haggled)
	check((haggled > 0 and float(escort.bonus) > 1.0) or (haggled < 0 and relations.trust(0) < trust),
		"y o paga más o se molesta")
	var open := quests.accept(id)
	check(String(open.get("stage", "")) == "travel" and int(open.dest) == 1, "la escolta va al poblado vecino")
	check(not quests.is_ready(open, null), "y no se cobra hasta llegar")
	trust = relations.trust(0)
	var dropped := quests.drop(id)
	check(dropped > 0.0 and relations.trust(0) < trust, "dejarlo baja la confianza (−%.1f)" % dropped)

	# El recado: se entrega al del otro poblado y se vuelve a cobrar.
	var errand := _take(quests, relations, by_kind, "errand")
	var to := String(errand.get("to", ""))
	check(to.begins_with("1:") and not quests.errand_for(to).is_empty(), "el recado es para uno del poblado vecino")
	var there := relations.trust(1)
	var got := quests.deliver_errand(to, &"")
	check(not got.is_empty() and relations.trust(1) > there and String(quests.open_of(String(errand.who)).stage) == "back",
		"al dárselo sube la confianza allí y hay que volver")
	check(quests.is_ready(quests.open_of(String(errand.who)), null), "y ya se puede cobrar")
	check(not quests.target_of(quests.open_of(String(errand.who))).area, "el mapa marca el poblado de quien lo pidió")
	var paid := quests.complete(String(errand.who))
	check(float(paid.gain) > 0.0, "cobrado: sube la confianza (+%.1f)" % float(paid.gain))

	# La fiera con nombre: su trofeo.
	var beast := _take(quests, relations, by_kind, "beast")
	check(String(beast.get("beast_name", "")).begins_with("VBEAST_"), "la fiera tiene nombre (%s)" % tr(String(beast.get("beast_name", ""))))
	check(not SettlementQuests.trophy_of(StringName(beast.species)).is_empty(), "y trofeo")

	# Guardar y cargar con los números y el plazo.
	var saved := quests.save_data()
	var copy := _quests(SettlementRelations.new())
	copy.restore(JSON.parse_string(JSON.stringify(saved)))
	var back := copy.open_of(String(beast.who))
	check(not back.is_empty() and back.due is float and back.village is int and back.stage == "hunt",
		"se guarda con su plazo y su estado")
	check(VillagerTalk.quest_details(back, quests.villages) != "", "y se pueden pedir los detalles")


## La oferta del tipo [kind] (sin aceptarla), en su periodo.
func _offer(quests: SettlementQuests, relations: SettlementRelations, by_kind: Dictionary, kind: String) -> Dictionary:
	if not by_kind.has(kind):
		check(false, "hay una oferta de %s" % kind)
		return {}
	relations.clock = int(by_kind[kind][0]) * 24.0 * SettlementQuests.PERIOD
	var id := String(by_kind[kind][1])
	for open: Dictionary in quests.open_list():
		quests._open.erase(String(open.who))
	return quests.offer({"id": id, "name": "Vecino", "job": {}}, 0, "Aldea", [&"Wolf", &"Bear"] as Array[StringName])


func _take(quests: SettlementQuests, relations: SettlementRelations, by_kind: Dictionary, kind: String) -> Dictionary:
	var offer := _offer(quests, relations, by_kind, kind)
	return quests.accept(String(offer.get("who", ""))) if not offer.is_empty() else {}

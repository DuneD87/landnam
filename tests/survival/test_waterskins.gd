extends Node

## Varios odres: capacidad, llenado al beber, consumo y guardado, sin cargar una partida.
## godot --headless --path . res://tests/survival/test_waterskins.tscn

class WaterActions extends SurvivalActions:
	var kind: StringName = &"fresh"
	var notice := ""

	func water_here() -> StringName:
		return kind

	func notify(message: String) -> void:
		notice = message


var failures := 0
var checks := 0
var _player: PlayerController
var _needs: SurvivalNeeds
var _actions: WaterActions
var _skin: ItemData


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var body := CharacterBody3D.new()
	add_child(body)
	body.set_script(PlayerController)
	_player = body as PlayerController
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_player.inventory = Inventory.new()
	_player.add_child(_player.inventory)
	_needs = SurvivalNeeds.new()
	_player.add_child(_needs)
	_player.needs = _needs
	_needs.setup(_player)
	_actions = WaterActions.new()
	_player.add_child(_actions)
	_actions._player = _player
	_skin = ItemCatalog.get_item(&"waterskin")
	_test_capacity()
	_test_filling()
	_test_drinking()
	_test_water_access()
	_player.free()
	await get_tree().process_frame
	print("WATERSKINS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func _reset(skins: int, thirst := 1.0, water := 0) -> void:
	_player.inventory.clear()
	_player.inventory.add_item(_skin, skins)
	_needs.thirst = thirst
	_needs.water = water
	_actions.kind = &"fresh"
	_actions.notice = ""
	_actions._cooldown = 0.0


func _test_capacity() -> void:
	_reset(0)
	check(_needs.water_capacity() == 0, "sin odres no cabe agua")
	_reset(1)
	check(_needs.water_capacity() == 20, "un odre admite 20 tragos")
	_reset(2)
	check(_needs.water_capacity() == 40, "dos odres admiten 40 tragos")
	_player.inventory.resize_slots(28)
	_player.inventory.add_item_at(_skin, 1, 27)
	check(_needs.water_capacity() == 60, "también cuenta un tercer odre en los huecos de la mochila")
	_player.inventory.remove_item(_skin, 1)
	check(_needs.water_capacity() == 40, "al retirar un odre se reduce la capacidad")


func _test_filling() -> void:
	_reset(2)
	check(_actions.drink_here() and _needs.water == 40, "una interacción llena los dos odres vacíos")
	check(_actions.notice == tr("SURV_FILL_SKINS") % 40, "el aviso muestra los 40 tragos de ambos odres")
	_needs.water = 7
	_actions.drink_here()
	check(_needs.water == 40, "rellena todos los odres parcialmente vacíos")
	_actions.drink_here()
	check(_needs.water == 40 and _actions.notice == tr("SURV_NOT_THIRSTY_FULL"),
		"los odres llenos no se desbordan")
	_reset(1)
	_actions.drink_here()
	_player.inventory.add_item(_skin)
	_actions.drink_here()
	check(_needs.water == 40, "añadir otro odre permite rellenarlo aunque el primero estuviera lleno")
	_reset(2, 0.4, 3)
	_actions.drink_here()
	check(is_equal_approx(_needs.thirst, 0.6) and _needs.water == 40,
		"con sed bebe un trago y llena ambos odres en la misma interacción")
	check(_actions.notice.contains(tr("SURV_DRINK_FRESH"))
		and _actions.notice.contains(tr("SURV_FILL_SKINS") % 40), "el aviso confirma que bebe y llena los odres")
	_reset(2, 0.4, 40)
	_actions.drink_here()
	check(is_equal_approx(_needs.thirst, 0.6) and _needs.water == 40
		and _actions.notice == tr("SURV_DRINK_FRESH"), "beber del río no gasta agua de los odres llenos")


func _test_drinking() -> void:
	_reset(2, 0.0)
	_actions.drink_here()
	for sip in 21:
		_actions._cooldown = 0.0
		_actions.use_item(_skin)
	check(_needs.water == 19, "se pueden beber más de 20 tragos usando el agua del segundo odre")
	check(_player.inventory.get_item_count(_skin) == 2, "beber conserva ambos odres")
	check(is_equal_approx(_needs.thirst, 1.0), "los tragos sacian la sed")
	var saved := _needs.save_data()
	_needs.water = 0
	_needs.load_data(saved)
	check(_needs.water == 19 and _needs.water_capacity() == 40, "guardar y cargar conserva el agua de ambos odres")
	_needs.water = 1
	_actions._cooldown = 0.0
	_actions.use_item(_skin)
	_actions._cooldown = 0.0
	_actions.use_item(_skin)
	check(_needs.water == 0 and _actions.notice == tr("SURV_SKIN_EMPTY"), "al acabar el agua avisa sin dejar tragos negativos")


func _test_water_access() -> void:
	_reset(2, 0.4, 7)
	_actions.kind = &"salt"
	check(_actions.drink_here() and _needs.water == 7 and is_equal_approx(_needs.thirst, 0.4)
		and _actions.notice == tr("SURV_SEA_WATER"), "el mar no llena los odres ni quita la sed")
	_actions.kind = &""
	check(not _actions.drink_here() and _needs.water == 7 and is_equal_approx(_needs.thirst, 0.4),
		"sin agua al alcance no se bebe ni se rellenan los odres")
	_reset(0, 0.4)
	_actions.drink_here()
	check(_needs.water == 0 and is_equal_approx(_needs.thirst, 0.6), "sin odres se puede beber del río")
	_needs.thirst = 1.0
	_actions.drink_here()
	check(_needs.water == 0 and _actions.notice == tr("SURV_NOT_THIRSTY"), "sin sed ni odres no se crea agua")

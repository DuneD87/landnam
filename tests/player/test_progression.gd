extends Node

## Nivel, XP y atributos (Progression) sin cargar una partida: la curva, el límite de lo repetido,
## lo que dan los atributos, la XP de matar y de fabricar, la que se pierde al morir y se recupera
## de la bolsa, y el guardado.
## godot --headless --path . res://tests/player/test_progression.tscn

var failures := 0
var checks := 0
var _player: PlayerController
var _health: HealthComponent
var _stamina: StaminaComponent
var _body: BodyDamage
var _needs: SurvivalNeeds
var _progression: Progression


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_player()
	_test_curve()
	_test_repeat_cap()
	_test_attributes()
	_test_soft_cap_and_respec()
	_test_kill()
	_test_craft()
	await _test_death_loot()
	_test_save_load()
	_player.combat.free()
	print("%d/%d checks passed" % [checks - failures, checks])
	get_tree().quit(1 if failures else 0)


## Solo lo que toca Progression, sobre nodos ya listos: vida, aguante, partes del cuerpo y necesidades.
func _build_player() -> void:
	var body := CharacterBody3D.new()
	add_child(body)
	body.set_script(PlayerController)
	_player = body as PlayerController
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_health = HealthComponent.new()
	_player.add_child(_health)
	_player.health_component = _health
	# PlayerCombat sin montar (fuera del árbol): solo lleva el aguante y las partes del cuerpo.
	_player.combat = PlayerCombat.new()
	_stamina = StaminaComponent.new()
	_player.add_child(_stamina)
	_player.combat.stamina = _stamina
	_body = BodyDamage.new()
	_player.add_child(_body)
	_body.health = _health
	_body.restore()
	_player.combat.body_damage = _body
	_needs = SurvivalNeeds.new()
	_player.add_child(_needs)
	_player.needs = _needs
	_progression = Progression.new()
	_player.add_child(_progression)
	_player.progression = _progression
	_progression.setup(_player)


func _reset() -> void:
	_progression.load_data({})
	_health.revive()
	_stamina.refill()
	_body.restore()


func _test_curve() -> void:
	_reset()
	var balance := _progression.balance
	check(balance.xp_to_next(1) == 80.0 and balance.xp_to_next(2) == 226.0 and balance.xp_to_next(5) == 894.0,
		"la curva pide 80 XP al nivel 2, 226 al 3 y 894 al 6")
	var levels: Array[int] = []
	_progression.leveled_up.connect(func(level: int) -> void: levels.append(level))
	_progression.gain(80.0, &"test")
	check(_progression.level == 2 and _progression.points == 1 and is_zero_approx(_progression.xp),
		"80 XP suben al nivel 2 con un punto")
	_progression.gain(226.0 + 416.0 + 10.0, &"test")
	check(_progression.level == 4 and _progression.points == 3 and is_equal_approx(_progression.xp, 10.0),
		"una ganancia grande sube varios niveles y guarda lo que sobra (%d, %.1f)" % [_progression.level, _progression.xp])
	check(levels == [2, 3, 4], "avisa de cada nivel: %s" % str(levels))


func _test_repeat_cap() -> void:
	_reset()
	var first := _progression.gain(120.0, &"fell_tree")
	var second := _progression.gain(120.0, &"fell_tree")
	check(is_equal_approx(first, 120.0) and absf(second - 60.0) < 0.5,
		"lo repetido seguido rinde la mitad al pasar su límite (%.1f, %.1f)" % [first, second])
	check(is_equal_approx(_progression.gain(30.0, &"kill"), 30.0), "matar no tiene límite de lo repetido")
	var xp_before := _progression.xp
	Progression.reward(_player, &"fish")
	check(is_equal_approx(_progression.xp - xp_before, _progression.balance.xp[&"fish"]),
		"reward da la XP de su motivo a quien lleva progresión")
	var stranger := Node.new()
	xp_before = _progression.xp
	Progression.reward(stranger, &"fish")
	stranger.free()
	check(is_equal_approx(_progression.xp, xp_before), "reward sin progresión no hace nada")


func _test_attributes() -> void:
	_reset()
	_progression.set_level(7)
	check(_progression.points == 6, "el nivel 7 trae seis puntos")
	_health.health = 50.0
	check(_progression.spend(&"vitality"), "se pone un punto en vitalidad")
	check(is_equal_approx(_health.max_health, 105.0) and is_equal_approx(_health.health, 55.0),
		"la vitalidad sube la vida máxima y la que se tiene (%.0f / %.0f)" % [_health.health, _health.max_health])
	check(is_equal_approx(_body.zone_ratio(&"chest"), 1.0) and is_equal_approx(_body.zone_max(&"chest"), 105.0),
		"cada parte del cuerpo crece con la vida y sigue sana")
	_progression.spend(&"endurance")
	check(is_equal_approx(_stamina.max_stamina, 104.0) and is_equal_approx(_stamina.regen_rate, 38.0 * 1.02),
		"el aguante sube el máximo y la recuperación")
	_progression.spend(&"toughness")
	check(is_equal_approx(_health.armor_slash, 0.5) and is_equal_approx(_health.armor_pierce, 0.5)
		and is_equal_approx(_body.bleed_scale, 0.98) and is_equal_approx(_progression.poise_bonus(), 1.0),
		"la dureza da armadura natural, guardia y menos sangrado")
	_progression.spend(&"fortitude")
	check(is_equal_approx(_needs.upkeep_scale, 0.98) and is_equal_approx(_needs.hardiness, 0.3),
		"el temple baja el gasto de hambre y sed y aguanta más frío y calor")
	_progression.spend(&"strength")
	_progression.spend(&"dexterity")
	check(is_equal_approx(_progression.strength_mult(), 1.03) and is_equal_approx(_progression.ranged_mult(), 1.03)
		and is_equal_approx(_progression.draw_speed_mult(), 1.02),
		"fuerza y destreza multiplican el daño y el tensado")
	check(not _progression.spend(&"vitality") and _progression.points == 0, "sin puntos no se pone nada")
	check(not _progression.spend(&"luck"), "lo que no es un atributo no se pone")


func _test_soft_cap_and_respec() -> void:
	_reset()
	_progression.set_attribute(&"strength", 20)
	check(is_equal_approx(_progression.effective(&"strength"), 17.5),
		"pasados 15 puntos rinden la mitad (%.1f)" % _progression.effective(&"strength"))
	_progression.set_level(11)
	_progression.set_attribute(&"vitality", 10)
	check(is_equal_approx(_health.max_health, 150.0), "diez puntos de vitalidad dan 150 de vida")
	var spent := _progression.spent()
	_progression.respec()
	check(_progression.spent() == 0 and _progression.points >= spent and is_equal_approx(_health.max_health, 100.0)
		and _health.health <= _health.max_health, "respec devuelve los puntos y la vida vuelve a la base")


func _test_kill() -> void:
	_reset()
	var bear := HealthComponent.new()
	bear.max_health = 240.0
	bear.armor_slash = 8.0
	bear.armor_blunt = 10.0
	bear.armor_pierce = 5.0
	var holder := Node.new()
	add_child(holder)
	holder.add_child(bear)
	check(is_equal_approx(_progression.kill_xp(bear), 83.0), "la XP de una presa sale de su vida y su armadura")
	var small := Node3D.new()
	check(is_equal_approx(_progression.kill_xp(small), _progression.balance.kill_small),
		"un animal pequeño sin vida propia da poca")
	small.free()
	var before := _progression.level * 1000.0 + _progression.xp
	bear.take_damage(100.0, _player)
	bear.drain(200.0)
	check(bear.is_dead and _progression.level * 1000.0 + _progression.xp > before,
		"lo que muere desangrado se le cuenta a quien lo hirió")
	var deer := HealthComponent.new()
	deer.xp_reward = 7.0
	holder.add_child(deer)
	var xp := _progression.xp
	deer.take_damage(10.0, null)
	deer.take_damage(500.0, holder)
	check(is_equal_approx(_progression.xp, xp), "lo que muere sin que el jugador lo hiera no le da nada")
	holder.queue_free()


func _test_craft() -> void:
	_reset()
	var recipe := RecipeData.new()
	recipe.result = &"test_spear"
	recipe.inputs = {&"wood_01": 2, &"stone_01": 3}
	var first := _progression.reward_craft(recipe, 1)
	var second := _progression.reward_craft(recipe, 1)
	check(is_equal_approx(first, 11.5 * 3.0), "la primera vez que se fabrica algo da el triple (%.1f)" % first)
	check(second > 0.0 and second < 11.5, "las siguientes, lo suyo con el límite de lo repetido (%.1f)" % second)
	var brew := RecipeData.new()
	brew.result = &"test_draught"
	brew.inputs = {&"yarrow": 4}
	brew.station = Campfire.ITEM_ID
	check(is_zero_approx(_progression.reward_craft(brew, 1)) and not _progression.crafted.has(&"test_draught"),
		"lo que se cuece en la hoguera no da XP")


func _test_death_loot() -> void:
	_reset()
	_progression.gain(50.0, &"test")
	var lost := _progression.forfeit()
	check(is_equal_approx(lost, 50.0) and is_zero_approx(_progression.xp) and _progression.level == 1,
		"al morir se pierde la XP del nivel, no el nivel")
	var empty: Array[InventoryItem] = []
	check(DeathLoot.spawn(_player, empty, 0.0) == null, "sin objetos ni XP no queda bolsa")
	var bag := DeathLoot.spawn(_player, empty, lost)
	check(bag != null and not bag.is_empty() and is_equal_approx(bag.xp, 50.0), "con XP queda una bolsa aunque no haya objetos")
	var saved := bag.get_save_data()
	check(is_equal_approx(float(JSON.parse_string(JSON.stringify(saved)).get("xp", 0.0)), 50.0),
		"la bolsa guarda su XP")
	check(DeathLoot.nearest(get_tree(), bag.global_position) == bag, "la bolsa con solo XP se encuentra al acercarse")
	_progression.recover(bag.take_xp())
	check(is_equal_approx(_progression.xp, 50.0) and bag.is_empty(), "al abrirla vuelve la XP")
	await get_tree().process_frame
	check(not is_instance_valid(bag) or bag.is_queued_for_deletion(), "vacía, la bolsa se va")


func _test_save_load() -> void:
	_reset()
	_progression.set_level(5)
	_progression.spend(&"vitality")
	_progression.spend(&"toughness")
	_progression.gain(40.0, &"test")
	var recipe := RecipeData.new()
	recipe.result = &"test_axe"
	_progression.reward_craft(recipe, 1)
	var data: Dictionary = JSON.parse_string(JSON.stringify(_progression.save_data()))
	_progression.load_data({})
	check(_progression.level == 1 and is_equal_approx(_health.max_health, 100.0), "una partida sin progresión empieza de cero")
	_progression.load_data(data)
	check(_progression.level == 5 and _progression.points == 2 and _progression.get_attribute(&"vitality") == 1
		and _progression.get_attribute(&"toughness") == 1, "se carga el nivel, los puntos y los atributos")
	check(is_equal_approx(_health.max_health, 105.0) and is_equal_approx(_health.armor_blunt, 0.5),
		"al cargar se aplican los atributos")
	check(_progression.crafted.has(&"test_axe"), "se recuerda lo que ya se ha fabricado")


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

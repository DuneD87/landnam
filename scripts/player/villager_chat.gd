class_name VillagerChat
extends CanvasLayer

## Hablar con un aldeano (Villager) o con un compañero (Companion): E delante de uno abre abajo su ficha
## (nombre, oficio o compañero, poblado y la confianza del poblado, SettlementRelations) con lo que dice
## (VillagerTalk) y qué hacer: hablar otra vez, regalarle algo del inventario, cambiar cosas con él
## (SettlementTrade: lo suyo a un lado, lo del jugador al otro y la cuenta) o despedirse; si tiene algo
## que pedir, su encargo (SettlementQuests: aceptarlo, entregarlo o dejarlo); a un aldeano de un poblado
## que se fía bastante, pedirle que venga (SettlementCompanions); a un compañero, darle cosas para que
## las lleve o quitárselas, que siga o espere, o que vuelva a casa (devuelve lo que lleva); a un colono,
## qué trabajo hacer (SettlerWork: talar, picar, limpiar alrededor del jugador o dejarlo), con cómo va. Mientras, él
## se para y mira al jugador, y el jugador no se mueve (el ratón va suelto). Se cierra con E, Escape,
## alejándose o si él se va (una fiera). Ver docs/villagers.md.

## Lo que se ve: la charla, los regalos, el trueque, el encargo o el morral del compañero.
enum View {TALK, GIFT, TRADE, QUEST, PACK}

## Más lejos de esto (m) se acaba la charla.
const REACH := 4.0
## Lo que se ve la subida de confianza (s).
const GAIN_TIME := 2.5
const GIFT_COLUMNS := 8
## Las dos columnas del trueque.
const TRADE_COLUMNS := 5

var _player: PlayerController
## Con quien se habla: un aldeano o un compañero (uno de los dos).
var _villager: Villager
var _companion: Companion
var _rng := RandomNumberGenerator.new()
var _last_line := ""
var _view := View.TALK
## El trueque: lo que se lleva el jugador y lo que da (ItemData -> cuántos).
var _take := {}
var _give := {}
var _gain_left := 0.0
var _previous_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _root: Control
var _panel: PanelContainer
var _margin: MarginContainer
var _box: VBoxContainer
var _name: Label
var _subtitle: Label
var _trust_label: Label
var _trust_bar: ProgressBar
var _gain: Label
var _line: Label
var _gift_scroll: ScrollContainer
var _gift_grid: GridContainer
var _hint: Label
var _trade_box: HBoxContainer
var _stock_scroll: ScrollContainer
var _stock_grid: GridContainer
var _offer_scroll: ScrollContainer
var _offer_grid: GridContainer
var _balance: Label
var _theirs_title: Label
var _quests_label: Label
var _buttons: HFlowContainer
var _talk_button: Button
var _gift_button: Button
var _trade_button: Button
var _recruit_button: Button
var _follow_button: Button
var _home_button: Button
var _settle_button: Button
var _fell_button: Button
var _mine_button: Button
var _clear_button: Button
var _stop_button: Button
var _work_label: Label
var _pack_button: Button
var _quest_button: Button
var _accept_button: Button
var _deliver_button: Button
var _drop_button: Button
var _deal_button: Button
var _back_button: Button
var _bye_button: Button


func _ready() -> void:
	layer = 14
	_rng.randomize()
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false


func setup(player: PlayerController) -> void:
	_player = player
	_player.health_component.died.connect(close)
	_player.inventory.inventory_changed.connect(_on_inventory_changed)
	GameManager.state_changed.connect(func(state: GameManager.State) -> void:
		if state != GameManager.State.PLAYING:
			close(false))


func is_open() -> bool:
	return visible


## Lo que se ve del inventario del jugador, al día.
func _on_inventory_changed() -> void:
	if not visible:
		return
	match _view:
		View.GIFT:
			_fill_gifts()
		View.TRADE:
			_fill_trade()
		View.QUEST:
			_fill_quest()
			_refresh()
		View.PACK:
			_fill_pack()


## Habla con el compañero o el aldeano que tiene delante, si hay alguno a mano. Falso si no hay ninguno.
func try_open() -> bool:
	var look := -_player.camera.global_basis.z
	var companion := Companion.find(get_tree(), _player.global_position, look)
	if companion != null:
		if companion.can_chat():
			_open(null, companion)
		return true
	var villager := Villager.find(get_tree(), _player.global_position, look)
	if villager == null:
		return false
	if not villager.can_chat():
		_player.hotbar.notify(tr("VILLAGER_ASLEEP") % villager.resident.name)
		return true
	_open(villager, null)
	return true


func open(villager: Villager) -> void:
	_open(villager, null)


func _open(villager: Villager, companion: Companion) -> void:
	if companion != null:
		if not companion.begin_chat():
			return
	elif villager == null or not villager.begin_chat():
		return
	_villager = villager
	_companion = companion
	_view = View.TALK
	_last_line = ""
	_previous_mouse_mode = Input.get_mouse_mode()
	_layout()
	visible = true
	_player.capture_mouse(false)
	_speak()
	_show_gain(_relations().talk(_v(), String(_who().id)))
	_refresh()


func close(capture_mouse := true) -> void:
	var was_open := visible
	visible = false
	_view = View.TALK
	_take.clear()
	_give.clear()
	if _villager != null and is_instance_valid(_villager):
		_villager.end_chat()
	if _companion != null and is_instance_valid(_companion):
		_companion.end_chat()
	_villager = null
	_companion = null
	if was_open and capture_mouse and is_instance_valid(_player):
		_player.capture_mouse(_previous_mouse_mode == Input.MOUSE_MODE_CAPTURED)


func _exit_tree() -> void:
	close(false)


func _process(delta: float) -> void:
	if not visible:
		return
	var node := _node()
	if node == null or not _is_chatting() \
			or _player.global_position.distance_to(node.global_position) > REACH \
			or _player.health_component.is_dead:
		close()
		return
	if _gain_left > 0.0:
		_gain_left -= delta
		_gain.modulate.a = clampf(_gain_left / 0.6, 0.0, 1.0)
		if _gain_left <= 0.0:
			_gain.text = ""


## Con quien se habla, si sigue ahí.
func _node() -> Node3D:
	if _companion != null and is_instance_valid(_companion):
		return _companion
	if _villager != null and is_instance_valid(_villager):
		return _villager
	return null


func _is_chatting() -> bool:
	return _companion.is_chatting() if _companion != null else _villager.is_chatting()


## Su vecino (SettlementPopulation.residents), su poblado y su nombre, y la confianza.
func _who() -> Dictionary:
	return _companion.resident if _companion != null else _villager.resident


func _v() -> int:
	return _companion.village if _companion != null else _villager.village.index


func _place() -> String:
	return _companion.village_name if _companion != null else _villager.village.name


func _relations() -> SettlementRelations:
	return _companion.relations if _companion != null else _villager.village.relations


func _companions() -> SettlementCompanions:
	return get_tree().get_first_node_in_group(SettlementCompanions.GROUP) as SettlementCompanions


func _quests() -> SettlementQuests:
	if _villager != null:
		return _villager.village.quests
	var companions := _companions()
	return companions.quests() if companions != null else null


## El encargo de con quien se habla: el que tiene abierto con el jugador o (un aldeano) el que pide, o {}.
func _quest_of() -> Dictionary:
	var quests := _quests()
	if quests == null or _node() == null:
		return {}
	var open := quests.open_of(String(_who().id))
	if not open.is_empty() or _villager == null:
		return open
	var village := _villager.village
	return quests.offer(_villager.resident, village.index, village.name,
		village.prey_near(SettlementQuests.SCOUT_REACH))


func _quest_open() -> bool:
	var quests := _quests()
	return quests != null and not quests.open_of(String(_who().id)).is_empty()


func _speak() -> void:
	if _companion != null:
		_say(VillagerTalk.companion_line(_companion, _player, _rng, _last_line))
	else:
		_say(VillagerTalk.line(_villager, _player, _rng, _last_line))


func _say(said: Dictionary) -> void:
	_last_line = said.key
	_line.text = tr("VILLAGER_QUOTE") % said.text
	if _companion != null:
		_companion.say()
	else:
		_villager.say()


func _show_gain(gain: float) -> void:
	if gain <= 0.0:
		return
	_gain.text = "+%d" % maxi(1, roundi(gain))
	_gain.modulate.a = 1.0
	_gain_left = GAIN_TIME


func _refresh() -> void:
	if _node() == null:
		return
	var who := _who()
	_name.text = who.name
	var title := VillagerTalk.job_title(who)
	if _companion != null:
		title = VillagerTalk.settler_title(who) if _settled() else VillagerTalk.companion_title(who)
	_subtitle.text = "%s · %s" % [tr(title), _place()]
	var trust := _relations().trust(_v())
	_trust_label.text = tr("VILLAGE_TRUST") % [tr(SettlementRelations.tier_name(SettlementRelations.tier_of(trust))),
		floori(trust)]
	_trust_bar.value = trust
	var talk := _view == View.TALK
	_gift_scroll.visible = _view == View.GIFT
	_trade_box.visible = _view == View.TRADE or _view == View.PACK
	_theirs_title.text = "VILLAGER_PACK_THEIRS" if _view == View.PACK else "VILLAGER_TRADE_THEIRS"
	_balance.visible = _view == View.TRADE
	_hint.visible = not talk
	_talk_button.visible = talk
	_gift_button.visible = talk
	_back_button.visible = not talk
	_deal_button.visible = _view == View.TRADE
	var danger := _villager != null and _villager.village.danger
	_gift_button.disabled = danger
	# Al aldeano se le cambian cosas y se le pide que venga; al compañero se le dan cosas, que siga o
	# espere, que se quede a vivir en la base o que vuelva.
	_trade_button.visible = talk and _villager != null
	_trade_button.disabled = danger
	_recruit_button.visible = talk and _villager != null
	_pack_button.visible = talk and _companion != null
	_follow_button.visible = talk and _companion != null
	_home_button.visible = talk and _companion != null
	_settle_button.visible = talk and _companion != null and not _settled()
	var working := _settled() and _companion.work.active()
	var job := _companion.work.job if working else SettlerWork.Job.NONE
	_fell_button.visible = talk and _settled() and job != SettlerWork.Job.FELL
	_mine_button.visible = talk and _settled() and job != SettlerWork.Job.MINE
	_clear_button.visible = talk and _settled()
	_stop_button.visible = talk and working
	_work_label.text = _companion.work.describe() if _settled() else ""
	_work_label.visible = talk and _work_label.text != ""
	var open := _quest_open()
	_quest_button.visible = talk and not _quest_of().is_empty()
	_quest_button.text = "VILLAGER_QUEST_OPEN" if open else "VILLAGER_QUEST"
	var asking := _view == View.QUEST
	_accept_button.visible = asking and not open
	_deliver_button.visible = asking and open
	_drop_button.visible = asking and open
	_quests_label.visible = asking and not _quests_label.text.is_empty()
	if asking and open:
		var quest := _quests().open_of(String(_who().id))
		_deliver_button.text = "VILLAGER_QUEST_DONE" if quest.kind == "hunt" else "VILLAGER_QUEST_DELIVER"
		_deliver_button.disabled = not _quests().is_ready(quest, _player.inventory)
	if _villager != null:
		var companions := _companions()
		var full := companions == null or companions.is_full()
		_recruit_button.disabled = danger or full or trust < SettlementRelations.RECRUIT_TRUST
		_recruit_button.tooltip_text = tr("VILLAGER_RECRUIT_FULL") if full \
			else (tr("VILLAGER_RECRUIT_NEED") % roundi(SettlementRelations.RECRUIT_TRUST)
				if trust < SettlementRelations.RECRUIT_TRUST else "")
	if _companion != null:
		_follow_button.text = "VILLAGER_WAIT" if _companion.mode == Companion.Mode.FOLLOW else "VILLAGER_FOLLOW"
		var companions := _companions()
		# El colono solo vuelve a acompañar si hay hueco; y a la base solo caben MAX_SETTLERS.
		var no_room := _settled() and (companions == null or companions.is_full())
		_follow_button.disabled = no_room
		_follow_button.tooltip_text = tr("VILLAGER_RECRUIT_FULL") if no_room else ""
		var base_full := companions == null or companions.settlers_full()
		_settle_button.disabled = base_full
		_settle_button.tooltip_text = tr("VILLAGER_SETTLE_FULL") % SettlementCompanions.MAX_SETTLERS \
			if base_full else ""


func _settled() -> bool:
	return _companion != null and _companion.mode == Companion.Mode.SETTLE


func _on_talk() -> void:
	_speak()
	_refresh()


func _on_gift() -> void:
	_view = View.GIFT
	_fill_gifts()
	_refresh()


func _on_trade() -> void:
	if _villager == null:
		return
	_view = View.TRADE
	_take.clear()
	_give.clear()
	_say(VillagerTalk.pick(&"TRADE_OPEN", _rng, _last_line))
	_fill_trade()
	_refresh()


func _on_back() -> void:
	_view = View.TALK
	_take.clear()
	_give.clear()
	_refresh()


## El aldeano se va con el jugador: la charla sigue con el compañero que lo sustituye.
func _on_recruit() -> void:
	var companions := _companions()
	if _villager == null or companions == null or companions.is_full():
		return
	var companion := companions.recruit(_villager)
	_villager = null
	_companion = companion
	companion.begin_chat()
	_say(VillagerTalk.pick(&"RECRUIT_YES", _rng, _last_line))
	_refresh()


## Que siga al jugador o que lo espere aquí.
func _on_follow() -> void:
	if _companion == null:
		return
	if _companion.mode == Companion.Mode.FOLLOW:
		_companion.wait_here()
		_say(VillagerTalk.pick(&"WAIT_OK", _rng, _last_line))
	else:
		var companions := _companions()
		if _settled() and (companions == null or companions.is_full()):
			return
		_companion.follow()
		_say(VillagerTalk.pick(&"FOLLOW_OK", _rng, _last_line))
	_refresh()


## Se queda a vivir aquí: es un colono de la base y deja libre el sitio de quien acompaña.
func _on_settle() -> void:
	var companions := _companions()
	if _companion == null or _settled() or companions == null or companions.settlers_full():
		return
	_companion.settle_here()
	_say(VillagerTalk.pick(&"SETTLE_OK", _rng, _last_line))
	_refresh()


## Al colono: que tale o pique alrededor de la base, que limpie alrededor del jugador o que lo deje.
func _on_work(job: SettlerWork.Job) -> void:
	if not _settled():
		return
	var work := _companion.work
	if job == SettlerWork.Job.NONE:
		work.stop()
		_say(VillagerTalk.pick(&"WORK_STOP", _rng, _last_line))
	else:
		var at := Vector3.INF
		if job == SettlerWork.Job.CLEAR:
			var terrain := _companion.get("_terrain") as Node3D
			at = terrain.global_transform.affine_inverse() * _player.global_position
		work.assign(job, at)
		_say(VillagerTalk.pick(&"WORK_OK", _rng, _last_line))
	_refresh()


## Vuelve a su poblado: devuelve lo que lleva (lo que no quepa, al suelo), se despide (en el aviso de la
## barra, que la charla se cierra) y se va.
func _on_home() -> void:
	if _companion == null:
		return
	var companion := _companion
	var carried := {}
	for item in companion.pack.get_all_items():
		if item != null:
			carried[item.data.id] = int(carried.get(item.data.id, 0)) + item.quantity
	companion.pack.clear()
	BuildCost.give(carried, _player.inventory, _player, _player.gravity_direction)
	var said := VillagerTalk.pick(&"HOME_OK", _rng, _last_line)
	_player.hotbar.notify(tr("VILLAGER_GOES_HOME") % [companion.resident.name, said.text])
	close()
	companion.go_home()


## Su encargo: lo que pide (para aceptarlo) o cómo va (para entregarlo o dejarlo).
func _on_quest() -> void:
	var quest := _quest_of()
	if quest.is_empty():
		return
	_view = View.QUEST
	if _quest_open():
		_say(VillagerTalk.pick(&"QUEST_WAITING", _rng, _last_line))
	else:
		_say(VillagerTalk.quest_line(quest, _rng, _last_line))
	_fill_quest()
	_refresh()


func _on_accept() -> void:
	var quests := _quests()
	var quest := quests.accept(String(_who().id)) if quests != null else {}
	if quest.is_empty():
		return
	_say(VillagerTalk.pick(&"QUEST_YES", _rng, _last_line))
	_player.hotbar.notify(tr("VQUEST_ACCEPTED") % [quest.name, VillagerTalk.quest_status(quest, _player.inventory)])
	_fill_quest()
	_refresh()


## Lo entrega (lo que pedía sale del inventario) o le dice que ya está: le da las gracias, sube la
## confianza y le da algo de lo suyo.
func _on_deliver() -> void:
	var quests := _quests()
	var id := String(_who().id)
	var quest := quests.open_of(id) if quests != null else {}
	if quest.is_empty() or not quests.is_ready(quest, _player.inventory):
		return
	if quest.kind == "fetch":
		_player.inventory.remove_item(ItemCatalog.get_item(StringName(quest.item)), int(quest.count))
	var result := quests.complete(id)
	var reward: Dictionary = result.get("reward", {})
	BuildCost.give(reward, _player.inventory, _player, _player.gravity_direction)
	_say(VillagerTalk.pick(&"QUEST_THANKS", _rng, _last_line))
	_show_gain(float(result.get("gain", 0.0)))
	if not reward.is_empty():
		var parts: PackedStringArray = []
		for item_id: StringName in reward:
			parts.append("%s ×%d" % [ItemCatalog.get_item(item_id).get_display_name(), int(reward[item_id])])
		_player.hotbar.notify(tr("VQUEST_REWARD") % [quest.name, ", ".join(parts)])
	AudioManager.play_ui(&"item_pickup")
	_view = View.TALK
	_refresh()


func _on_drop() -> void:
	var quests := _quests()
	if quests == null:
		return
	quests.drop(String(_who().id))
	_say(VillagerTalk.pick(&"QUEST_DROP", _rng, _last_line))
	_view = View.TALK
	_refresh()


## Cómo va el encargo (o qué se pide) y, debajo, todos los que tiene abiertos el jugador.
func _fill_quest() -> void:
	var quests := _quests()
	var quest := _quest_of()
	if quests == null or quest.is_empty():
		_hint.text = ""
		_quests_label.text = ""
		return
	var status := VillagerTalk.quest_status(quest, _player.inventory)
	if not _quest_open():
		_hint.text = tr("VILLAGER_QUEST_OFFER") % status
	elif quest.kind == "hunt":
		_hint.text = "%s · %s" % [status, tr("VILLAGER_QUEST_HOW_HUNT") % roundi(SettlementQuests.HUNT_REACH)]
	else:
		_hint.text = "%s · %s" % [status, tr("VILLAGER_QUEST_HOW_FETCH")]
	var parts: PackedStringArray = []
	for open: Dictionary in quests.open_list():
		parts.append(tr("VILLAGER_QUEST_ENTRY") % [open.name, open.village_name,
			VillagerTalk.quest_status(open, _player.inventory)])
	_quests_label.text = tr("VILLAGER_QUESTS") % " · ".join(parts) if not parts.is_empty() else ""


## Lo que lleva el compañero, para darle o quitarle cosas.
func _on_pack() -> void:
	if _companion == null:
		return
	_view = View.PACK
	_fill_pack()
	_refresh()


## Sus cosas a un lado y las del jugador al otro: clic pasa una al otro lado; clic derecho, todas.
func _fill_pack() -> void:
	if _companion == null:
		return
	var pack := _companion.pack
	var theirs: Array[ItemData] = []
	var carried := _counts(pack, theirs)
	var yours: Array[ItemData] = []
	var counts := _counts(_player.inventory, yours)
	_fill_moves(_stock_grid, theirs, carried, pack, _player.inventory)
	_fill_moves(_offer_grid, yours, counts, _player.inventory, pack)
	_hint.text = tr("VILLAGER_PACK_HINT")


func _fill_moves(grid: GridContainer, order: Array[ItemData], available: Dictionary, from: Inventory,
		to: Inventory) -> void:
	for child in grid.get_children():
		child.queue_free()
	for data in order:
		var slot := _slot(data, int(available[data]), data.get_display_name())
		slot.slot_clicked.connect(func(_s: ItemSlotView, button: int) -> void:
			if button == MOUSE_BUTTON_LEFT:
				_move_items(data, 1, from, to)
			elif button == MOUSE_BUTTON_RIGHT:
				_move_items(data, from.get_item_count(data), from, to))
		grid.add_child(slot)


## Pasa [amount] de [data] de [from] a [to], lo que quepa.
func _move_items(data: ItemData, amount: int, from: Inventory, to: Inventory) -> void:
	var have := mini(amount, from.get_item_count(data))
	if have <= 0 or _companion == null:
		return
	var left := to.add_item(data, have)
	if left >= have:
		_player.hotbar.notify(tr("VILLAGER_PACK_FULL") if to == _companion.pack else tr("VILLAGER_PACK_YOURS_FULL"))
		return
	from.remove_item(data, have - left)
	AudioManager.play_ui(&"item_pickup")
	_fill_pack()


## Los montones de [inventory], uno por objeto, con lo que hay de cada uno: ItemData -> cuántos, y el
## orden en [order].
func _counts(inventory: Inventory, order: Array[ItemData]) -> Dictionary:
	var counts := {}
	for item in inventory.get_all_items():
		if item == null or item.data == null:
			continue
		if not counts.has(item.data):
			counts[item.data] = 0
			order.append(item.data)
		counts[item.data] += item.quantity
	_sort(order)
	return counts


func _sort(order: Array[ItemData]) -> void:
	order.sort_custom(func(a: ItemData, b: ItemData) -> bool:
		return ItemTaxonomy._less(ItemTaxonomy.sort_key(a), ItemTaxonomy.sort_key(b)))


func _fill_gifts() -> void:
	for child in _gift_grid.get_children():
		child.queue_free()
	var order: Array[ItemData] = []
	var counts := _counts(_player.inventory, order)
	for data in order:
		var slot := _slot(data, counts[data], data.get_display_name())
		slot.slot_clicked.connect(func(_s: ItemSlotView, button: int) -> void:
			if button == MOUSE_BUTTON_LEFT:
				_give_gift(data))
		_gift_grid.add_child(slot)
	_hint.text = tr("VILLAGER_GIFT_EMPTY") if order.is_empty() else tr("VILLAGER_GIFT_HINT")


func _slot(data: ItemData, count: int, tooltip: String) -> ItemSlotView:
	var slot := ItemSlotView.new()
	slot.size_kind = &"hotbar"
	slot.show_item(data.icon, count)
	slot.tooltip_text = tooltip
	return slot


## Le da una unidad de [data].
func _give_gift(data: ItemData) -> void:
	if _node() == null or _player.inventory.remove_item(data, 1) < 1:
		return
	var value := ItemValue.of(data)
	var taste := VillagerTalk.taste(StringName(_who().get("job", {}).get("kind", "")), data)
	var gain := _relations().gift(_v(), value, taste)
	_say(VillagerTalk.gift_line(gain, taste, value * taste, _rng, _last_line))
	_show_gain(gain)
	AudioManager.play_ui(&"item_pickup")
	_refresh()


## Las dos columnas del trueque: lo que tiene él hoy y lo que lleva el jugador, cada hueco con lo que hay,
## lo que se ha elegido arriba («×2») y su precio en la ficha; y la cuenta.
func _fill_trade() -> void:
	if _villager == null:
		return
	var trade := _villager.village.trade
	var v := _v()
	var stock := {}
	var theirs: Array[ItemData] = []
	var today := trade.stock(_villager.resident)
	for id: StringName in today:
		var data := ItemCatalog.get_item(id)
		stock[data] = today[id]
		theirs.append(data)
	_sort(theirs)
	var yours: Array[ItemData] = []
	var counts := _counts(_player.inventory, yours)
	_clamp(_take, stock)
	_clamp(_give, counts)
	_fill_column(_stock_grid, theirs, stock, _take, func(data: ItemData) -> float: return trade.sell_price(v, data))
	_fill_column(_offer_grid, yours, counts, _give, func(data: ItemData) -> float: return trade.buy_price(v, data))
	_hint.text = tr("VILLAGER_TRADE_HINT")
	var sums := trade.balance(v, _take, _give)
	var cost := float(sums.cost)
	var credit := float(sums.credit)
	_balance.text = tr("VILLAGER_TRADE_BALANCE") % [ItemTrait.number(snappedf(cost, 0.1)),
		ItemTrait.number(snappedf(credit, 0.1))]
	_balance.theme_type_variation = &"ValueLabel" if _take.is_empty() \
		else (&"BetterLabel" if credit >= cost else &"WorseLabel")
	_deal_button.disabled = _take.is_empty()


## Lo elegido de [chosen] que ya no hay en [available] (se ha gastado o vendido), fuera.
func _clamp(chosen: Dictionary, available: Dictionary) -> void:
	for data: ItemData in chosen.keys():
		var left := mini(int(chosen[data]), int(available.get(data, 0)))
		if left > 0:
			chosen[data] = left
		else:
			chosen.erase(data)


## Una columna: un hueco por objeto de [order] con [available]; clic, uno más a [chosen]; clic derecho,
## uno menos. [price]: lo que vale cada uno en el trato.
func _fill_column(grid: GridContainer, order: Array[ItemData], available: Dictionary, chosen: Dictionary,
		price: Callable) -> void:
	for child in grid.get_children():
		child.queue_free()
	for data in order:
		var picked := int(chosen.get(data, 0))
		var slot := _slot(data, int(available[data]), tr("VILLAGER_TRADE_PRICE") % [data.get_display_name(),
			ItemTrait.number(snappedf(float(price.call(data)), 0.1))])
		slot.set_mark("×%d" % picked if picked > 0 else "")
		slot.set_selected(picked > 0)
		slot.slot_clicked.connect(func(_s: ItemSlotView, button: int) -> void:
			var now := int(chosen.get(data, 0))
			if button == MOUSE_BUTTON_LEFT and now < int(available[data]):
				chosen[data] = now + 1
			elif button == MOUSE_BUTTON_RIGHT and now > 0:
				if now == 1:
					chosen.erase(data)
				else:
					chosen[data] = now - 1
			else:
				return
			_fill_trade())
		grid.add_child(slot)


## Cierra el trato si lo que da el jugador llega: se lleva lo elegido (lo que no cabe, al suelo) y da lo
## suyo. Si no llega, se lo dice.
func _on_deal() -> void:
	if _villager == null or _take.is_empty():
		return
	var trade := _villager.village.trade
	var v := _v()
	var sums := trade.balance(v, _take, _give)
	if float(sums.credit) < float(sums.cost):
		_say(VillagerTalk.pick(&"TRADE_SHORT", _rng, _last_line))
		return
	for data: ItemData in _give:
		if not _player.inventory.has_item(data, int(_give[data])):
			_fill_trade()
			return
	var take := _take.duplicate()
	var give := _give.duplicate()
	_take.clear()
	_give.clear()
	for data: ItemData in give:
		_player.inventory.remove_item(data, int(give[data]))
	var gain := trade.deal(_villager.resident, v, take, give)
	var received := {}
	for data: ItemData in take:
		received[data.id] = int(take[data])
	BuildCost.give(received, _player.inventory, _player, _player.gravity_direction)
	_say(VillagerTalk.pick(&"TRADE_DONE", _rng, _last_line))
	_show_gain(gain)
	AudioManager.play_ui(&"item_pickup")
	_fill_trade()
	_refresh()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"WindowPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_panel)
	_margin = MarginContainer.new()
	_panel.add_child(_margin)
	_box = VBoxContainer.new()
	_margin.add_child(_box)

	var header := HBoxContainer.new()
	_box.add_child(header)
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(who)
	_name = Label.new()
	_name.theme_type_variation = &"HeaderLabel"
	who.add_child(_name)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"HintLabel"
	who.add_child(_subtitle)
	var trust := VBoxContainer.new()
	trust.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(trust)
	var trust_row := HBoxContainer.new()
	trust_row.alignment = BoxContainer.ALIGNMENT_END
	trust.add_child(trust_row)
	_gain = Label.new()
	_gain.theme_type_variation = &"BetterLabel"
	trust_row.add_child(_gain)
	_trust_label = Label.new()
	_trust_label.theme_type_variation = &"ValueLabel"
	_trust_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	trust_row.add_child(_trust_label)
	_trust_bar = ProgressBar.new()
	_trust_bar.max_value = SettlementRelations.MAX_TRUST
	_trust_bar.show_percentage = false
	trust.add_child(_trust_bar)

	_box.add_child(HSeparator.new())
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.add_theme_font_override("font", load("res://fonts/AlegreyaSans-Italic.ttf"))
	_box.add_child(_line)

	_hint = Label.new()
	_hint.theme_type_variation = &"HintLabel"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_hint)
	_gift_scroll = ScrollContainer.new()
	_gift_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(_gift_scroll)
	_gift_grid = GridContainer.new()
	_gift_grid.columns = GIFT_COLUMNS
	_gift_scroll.add_child(_gift_grid)

	_trade_box = HBoxContainer.new()
	_box.add_child(_trade_box)
	var theirs := _trade_column("VILLAGER_TRADE_THEIRS")
	_stock_scroll = theirs[0]
	_stock_grid = theirs[1]
	_theirs_title = theirs[2]
	var yours := _trade_column("VILLAGER_TRADE_YOURS")
	_offer_scroll = yours[0]
	_offer_grid = yours[1]
	_balance = Label.new()
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_balance)
	_quests_label = Label.new()
	_quests_label.theme_type_variation = &"HintLabel"
	_quests_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_quests_label)
	_work_label = Label.new()
	_work_label.theme_type_variation = &"HintLabel"
	_work_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_work_label)

	# Si no caben en una fila, en dos.
	_buttons = HFlowContainer.new()
	_buttons.alignment = FlowContainer.ALIGNMENT_CENTER
	_box.add_child(_buttons)
	_talk_button = _button(_buttons, "VILLAGER_TALK", _on_talk)
	_talk_button.theme_type_variation = &"AccentButton"
	_gift_button = _button(_buttons, "VILLAGER_GIFT", _on_gift)
	_trade_button = _button(_buttons, "VILLAGER_TRADE", _on_trade)
	_pack_button = _button(_buttons, "VILLAGER_PACK", _on_pack)
	_quest_button = _button(_buttons, "VILLAGER_QUEST", _on_quest)
	_recruit_button = _button(_buttons, "VILLAGER_RECRUIT", _on_recruit)
	_follow_button = _button(_buttons, "VILLAGER_WAIT", _on_follow)
	_settle_button = _button(_buttons, "VILLAGER_SETTLE", _on_settle)
	_home_button = _button(_buttons, "VILLAGER_GO_HOME", _on_home)
	_fell_button = _button(_buttons, "SETTLER_ORDER_FELL", _on_work.bind(SettlerWork.Job.FELL))
	_mine_button = _button(_buttons, "SETTLER_ORDER_MINE", _on_work.bind(SettlerWork.Job.MINE))
	_clear_button = _button(_buttons, "SETTLER_ORDER_CLEAR", _on_work.bind(SettlerWork.Job.CLEAR))
	_stop_button = _button(_buttons, "SETTLER_ORDER_STOP", _on_work.bind(SettlerWork.Job.NONE))
	_deal_button = _button(_buttons, "VILLAGER_TRADE_DEAL", _on_deal)
	_deal_button.theme_type_variation = &"AccentButton"
	_accept_button = _button(_buttons, "VILLAGER_QUEST_ACCEPT", _on_accept)
	_accept_button.theme_type_variation = &"AccentButton"
	_deliver_button = _button(_buttons, "VILLAGER_QUEST_DELIVER", _on_deliver)
	_deliver_button.theme_type_variation = &"AccentButton"
	_drop_button = _button(_buttons, "VILLAGER_QUEST_DROP", _on_drop)
	_back_button = _button(_buttons, "VILLAGER_GIFT_DONE", _on_back)
	_bye_button = _button(_buttons, "VILLAGER_BYE", close)


## Una columna del trueque con su título: [scroll, grid, título].
func _trade_column(title: String) -> Array:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trade_box.add_child(column)
	var label := Label.new()
	label.text = title
	label.theme_type_variation = &"SectionLabel"
	column.add_child(label)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = TRADE_COLUMNS
	scroll.add_child(grid)
	return [scroll, grid, label]


func _button(row: Container, text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(pressed)
	row.add_child(button)
	return button


func _layout() -> void:
	var ui_scale := GameTheme.scale_for(get_viewport())
	_root.theme = GameTheme.build(ui_scale)
	_panel.custom_minimum_size.x = 900.0 * ui_scale
	_panel.offset_top = -200.0 * ui_scale
	_panel.offset_bottom = -200.0 * ui_scale
	_line.custom_minimum_size = Vector2(840, 80) * ui_scale
	_trust_bar.custom_minimum_size = Vector2(260, 14) * ui_scale
	# Tres filas enteras de huecos.
	var slot_side := float(_root.theme.get_constant(&"hotbar", &"ItemSlot"))
	var gap := roundi(6.0 * ui_scale)
	for grid in [_gift_grid, _stock_grid, _offer_grid]:
		grid.add_theme_constant_override("h_separation", gap)
		grid.add_theme_constant_override("v_separation", gap)
	for scroll in [_gift_scroll, _stock_scroll, _offer_scroll]:
		scroll.custom_minimum_size.y = slot_side * 3.0 + gap * 2.0
	_trade_box.add_theme_constant_override("separation", roundi(24.0 * ui_scale))
	_box.add_theme_constant_override("separation", roundi(14.0 * ui_scale))
	_buttons.add_theme_constant_override("h_separation", gap)
	_buttons.add_theme_constant_override("v_separation", gap)
	for side in ["left", "top", "right", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, roundi(24.0 * ui_scale))
	for button: Button in [_talk_button, _gift_button, _trade_button, _pack_button, _quest_button,
			_recruit_button, _follow_button, _settle_button, _home_button, _fell_button, _mine_button, _clear_button,
			_stop_button, _deal_button, _accept_button, _deliver_button,
			_drop_button, _back_button, _bye_button]:
		button.custom_minimum_size.x = 130.0 * ui_scale

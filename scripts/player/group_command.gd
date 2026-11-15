class_name GroupCommand
extends Node

## Las órdenes del jugador al grupo que lo acompaña (SettlementCompanions.party), lejos del trono: su
## tecla (group_orders) abre la rueda (GroupOrderWheel) y lo elegido va a todos a la vez. Seguidme
## (los que esperan echan a andar), esperad aquí (se quedan y defienden el sitio), atacad (van a por
## la fiera fijada o, sin ella, a la que el jugador mira), retirada (dejan la pelea y vuelven
## corriendo), volved a la base (cada colono vuelve a la suya, con el trabajo que tenía) y la
## formación (cuña, fila o sueltos, que se despliegan en la rueda) y a los bancos (se sientan en las
## bancadas del barco en el que va el jugador, o de cerca en tierra: RowingBench) e id allí (van al
## suelo al que mira el jugador y esperan allí, repartidos en corro) y trabajad (se despliegan los
## oficios: se ponen con el elegido en campo alrededor de lo que mira el jugador, Companion.field_work,
## hasta que se les mande otra cosa). Sin nadie en el grupo, la tecla
## solo avisa. Lo hecho se dice en el aviso de la barra. Ver docs/villagers.md.
##
## Las órdenes (no la formación) van solo a los elegidos: al abrir, todos o, si el jugador mira a uno
## del grupo, solo ese; con la rueda abierta, las teclas 1-9 y 0 cambian la elección (GroupOrderWheel).
## Mientras está abierta, cada uno lleva su número encima, encendido si está elegido, y abajo, tapando
## la hotbar, sale el grupo en tarjetas (CompanionCards) con su retrato, su vida, su comida y su agua.

## A lo que mira el jugador: la criatura viva a menos de AIM_RANGE m que queda a menos de AIM_ANGLE
## grados del centro de la vista.
const AIM_RANGE := 60.0
const AIM_ANGLE := 12.0
## A quién del grupo mira el jugador al abrir la rueda: a menos de MATE_RANGE m y MATE_ANGLE grados.
const MATE_RANGE := 40.0
const MATE_ANGLE := 6.0
## Id allí: el suelo al que mira el jugador, a menos de GOTO_RANGE m de la vista.
const GOTO_RANGE := 80.0
## Trabajad: los oficios que se despliegan, en orden, y su texto en la rueda (el dibujo, el de
## SettlerOrders).
const WORK_JOBS: Array[SettlerWork.Job] = [SettlerWork.Job.FELL, SettlerWork.Job.MINE, SettlerWork.Job.CLEAR,
	SettlerWork.Job.HUNT, SettlerWork.Job.FISH, SettlerWork.Job.COOK, SettlerWork.Job.BUILD]
const WORK_LABELS := {SettlerWork.Job.FELL: "GROUP_WORK_FELL", SettlerWork.Job.MINE: "GROUP_WORK_MINE",
	SettlerWork.Job.CLEAR: "GROUP_WORK_CLEAR", SettlerWork.Job.HUNT: "GROUP_WORK_HUNT",
	SettlerWork.Job.FISH: "GROUP_WORK_FISH", SettlerWork.Job.COOK: "GROUP_WORK_COOK",
	SettlerWork.Job.BUILD: "GROUP_WORK_BUILD"}
## El número sobre la cabeza: a MARK_HEIGHT m sobre los pies.
const MARK_HEIGHT := Villager.BODY_HEIGHT + 0.45
const MARK_ON := Color(0.93, 0.78, 0.45)
const MARK_OFF := Color(0.75, 0.72, 0.66, 0.35)
## Cada cuánto (s) se refresca la vida y la comida en la rueda abierta, y se miran los retratos que
## faltan con ella cerrada (para tenerlos hechos al abrirla).
const ROSTER_EVERY := 0.25
const PORTRAITS_EVERY := 2.0

var wheel: GroupOrderWheel
var _player: PlayerController
## El grupo tal como salió en la rueda (su puesto en la lista) y su número encima.
var _members: Array[Companion] = []
var _marks: Array[Label3D] = []
var _portraits: CompanionPortraits
var _refresh_left := 0.0


func setup(player: PlayerController) -> void:
	_player = player
	wheel = GroupOrderWheel.new()
	wheel.name = "GroupOrderWheel"
	wheel.order_chosen.connect(_on_order)
	wheel.formation_chosen.connect(_on_formation)
	wheel.work_chosen.connect(_on_work)
	wheel.selection_changed.connect(_show_marks)
	wheel.closed.connect(_clear_marks)
	wheel.closed.connect(_show_hotbar.bind(true))
	add_child(wheel)
	_portraits = CompanionPortraits.new()
	_portraits.name = "CompanionPortraits"
	_portraits.portrait_ready.connect(_on_portrait)
	add_child(_portraits)
	_player.health_component.died.connect(close)
	GameManager.state_changed.connect(func(state: GameManager.State) -> void:
		if state != GameManager.State.PLAYING:
			close())


func is_open() -> bool:
	return wheel != null and wheel.is_open()


func close() -> void:
	if wheel != null:
		wheel.close()


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or not event.is_action_pressed(GroupOrderWheel.ACTION) or event.is_echo():
		return
	if GameManager.current_state != GameManager.State.PLAYING or not _player.is_mouse_captured() \
			or not _player.input_enabled or _player.free_flight_enabled or _player.combat.is_dead() \
			or wheel.is_open() or (_player.build_radial != null and _player.build_radial.is_open()) \
			or (_player.throne_view != null and _player.throne_view.is_open()):
		return
	get_viewport().set_input_as_handled()
	var companions := _companions()
	var group := companions.party() if companions != null else ([] as Array[Companion])
	if group.is_empty():
		_player.hotbar.notify(tr("GROUP_NOBODY"))
		return
	var following := companions.followers().size()
	var summary := tr("GROUP_SUMMARY") % [following, group.size() - following]
	var names: Array[String] = []
	var glyphs: Array[StringName] = []
	for f in SettlementCompanions.Formation.size():
		names.append(tr(SettlementCompanions.FORMATION_NAMES[f]))
		glyphs.append(SettlementCompanions.FORMATION_GLYPHS[f])
	_members = group
	for c in group:
		_portraits.request(c)
	var jobs: Array[String] = []
	var job_glyphs: Array[StringName] = []
	for job in WORK_JOBS:
		jobs.append(tr(WORK_LABELS[job]))
		job_glyphs.append(SettlerOrders.find(job).get("glyph", &"work"))
	wheel.set_jobs(jobs, job_glyphs)
	var mate := aimed_companion(group)
	var strip := _player.hotbar.get_panel().get_global_rect() if _player.hotbar != null else Rect2()
	# Los ocupados (trabajando o de camino) no se eligen solos al abrir.
	var busy: Array[bool] = []
	for c in group:
		busy.append(c.is_field_working() or c.is_going())
	wheel.open(summary, names, glyphs, int(companions.formation),
		tr("GROUP_HINT_PREY") if aimed_creature() != null else "", _roster(), group.find(mate), strip, busy)
	_show_hotbar(false)
	_refresh_left = ROSTER_EVERY
	_show_marks(wheel.selection())


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	if wheel != null and wheel.is_open():
		_refresh_left = ROSTER_EVERY
		wheel.set_roster(_roster())
		return
	# Cerrada: los retratos que falten, para tenerlos al abrirla.
	_refresh_left = PORTRAITS_EVERY
	var companions := _companions()
	if companions != null:
		for c in companions.party():
			_portraits.request(c)


## Lo que la rueda enseña de cada uno del grupo (_members): nombre, qué hace, vida, comida, agua y retrato.
func _roster() -> Array[Dictionary]:
	var roster: Array[Dictionary] = []
	for c in _members:
		if not is_instance_valid(c):
			roster.append({"name": "", "state": "", "bars": [], "down": true})
			continue
		var state := tr("GROUP_STATE_FOLLOW")
		if c.dead or c.is_down():
			state = tr("GROUP_STATE_DOWN")
		elif c.is_rowing():
			state = tr("GROUP_STATE_ROWING")
		elif c.is_seated():
			state = tr("GROUP_STATE_SEATED")
		elif c.is_going():
			state = tr("GROUP_STATE_GOING")
		elif c.is_field_working():
			state = c.work.describe()
		elif c.mode == Companion.Mode.WAIT:
			state = tr("GROUP_STATE_WAIT")
		roster.append({"name": String(c.resident.get("name", "")), "state": state,
			"bars": CompanionCards.bars_of(c), "down": c.dead or c.is_down(),
			"portrait": CompanionPortraits.cached(c)})
	return roster


func _on_portrait(key: String, texture: Texture2D) -> void:
	if not is_open():
		return
	for k in _members.size():
		if is_instance_valid(_members[k]) and CompanionPortraits.key_of(_members[k]) == key:
			wheel.set_portrait(k, texture)


## La hotbar (sus huecos), que la barra del grupo tapa mientras la rueda está abierta.
func _show_hotbar(shown: bool) -> void:
	if _player == null or _player.hotbar == null:
		return
	_player.hotbar.get_panel().modulate.a = 1.0 if shown else 0.0


func _on_order(order: GroupOrderWheel.Order, picked: Array[int]) -> void:
	var who: Array[Companion] = []
	for k in picked:
		if k < _members.size() and is_instance_valid(_members[k]) and not _members[k].dead:
			who.append(_members[k])
	if who.is_empty():
		return
	give(order, who)


## Trabajad: el oficio [index] de WORK_JOBS a los puestos [picked], alrededor de lo que mira el jugador.
func _on_work(index: int, picked: Array[int]) -> void:
	var companions := _companions()
	if companions == null or index < 0 or index >= WORK_JOBS.size():
		return
	var who: Array[Companion] = []
	for k in picked:
		if k < _members.size() and is_instance_valid(_members[k]) and not _members[k].dead:
			who.append(_members[k])
	if who.is_empty():
		return
	var spot := aimed_spot()
	if not spot.is_finite():
		_player.hotbar.notify(tr("GROUP_SAID_NO_SPOT"))
		return
	var job := WORK_JOBS[index]
	var count := companions.order_work(job, spot, who)
	if count > 0:
		_player.hotbar.notify(tr("GROUP_SAID_WORK") % [count, tr(WORK_LABELS[job])])


func _on_formation(index: int) -> void:
	var companions := _companions()
	if companions == null:
		return
	companions.set_formation(index as SettlementCompanions.Formation)
	_player.hotbar.notify(tr("GROUP_SAID_FORMATION") % tr(SettlementCompanions.FORMATION_NAMES[companions.formation]))


## El número de cada uno del grupo sobre su cabeza, encendido si está elegido ([selected]).
func _show_marks(selected: Array[bool]) -> void:
	_clear_marks()
	for k in _members.size():
		var c := _members[k]
		if not is_instance_valid(c) or c.dead:
			continue
		var on := k < selected.size() and selected[k]
		var mark := Label3D.new()
		mark.text = str(k + 1)
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mark.no_depth_test = true
		mark.fixed_size = true
		mark.pixel_size = 0.0006 if on else 0.00045
		mark.font_size = 64
		mark.outline_size = 14
		mark.modulate = MARK_ON if on else MARK_OFF
		mark.outline_modulate = Color(0.08, 0.06, 0.04, 0.9 if on else 0.3)
		mark.render_priority = 10
		mark.outline_render_priority = 9
		mark.position = Vector3.UP * MARK_HEIGHT
		c.add_child(mark)
		_marks.append(mark)


func _clear_marks() -> void:
	for mark in _marks:
		if is_instance_valid(mark):
			mark.queue_free()
	_marks.clear()


## Al del grupo [group] al que mira el jugador (el más centrado en la vista), o null.
func aimed_companion(group: Array[Companion]) -> Companion:
	var camera := _player.camera
	if camera == null:
		return null
	var forward := -camera.global_basis.z
	var best: Companion
	var best_angle := deg_to_rad(MATE_ANGLE)
	for c in group:
		var to := c.get_lock_point() - camera.global_position
		if to.length() > MATE_RANGE:
			continue
		var angle := forward.angle_to(to)
		if angle < best_angle:
			best = c
			best_angle = angle
	return best


## Da [order] a [who] (vacío: a todo el grupo) y lo dice en la barra.
func give(order: GroupOrderWheel.Order, who: Array[Companion] = []) -> void:
	var companions := _companions()
	if companions == null:
		return
	var said := ""
	match order:
		GroupOrderWheel.Order.FOLLOW:
			var count := companions.order_follow(who)
			said = tr("GROUP_SAID_FOLLOW") % companions.followers().size() if count > 0 else tr("GROUP_SAID_ALREADY")
		GroupOrderWheel.Order.WAIT:
			var count := companions.order_wait(who)
			said = tr("GROUP_SAID_WAIT") % count if count > 0 else tr("GROUP_SAID_NONE_FOLLOWING")
		GroupOrderWheel.Order.ATTACK:
			var prey := aimed_creature()
			var count := companions.order_attack(prey, who) if prey != null else 0
			said = tr("GROUP_SAID_ATTACK") % count if count > 0 else tr("GROUP_HINT_NO_PREY")
		GroupOrderWheel.Order.RETREAT:
			companions.order_retreat(who)
			said = tr("GROUP_SAID_RETREAT")
		GroupOrderWheel.Order.HOME:
			var result := companions.order_home(who)
			if int(result[0]) == 0:
				said = tr("GROUP_SAID_NO_BASE")
			elif int(result[1]) > 0:
				said = tr("GROUP_SAID_HOME_SOME") % [result[0], result[1]]
			else:
				said = tr("GROUP_SAID_HOME") % result[0]
		GroupOrderWheel.Order.BOARD:
			var ship: DynamicGridBody = _player._platform_body if is_instance_valid(_player._platform_body) else null
			var result := companions.order_board(_player.global_position, ship, who)
			if int(result[0]) == 0:
				said = tr("GROUP_SAID_NO_BENCH")
			elif int(result[1]) > 0:
				said = tr("GROUP_SAID_BOARD_SOME") % [result[0], result[1]]
			else:
				said = tr("GROUP_SAID_BOARD") % result[0]
		GroupOrderWheel.Order.GOTO:
			var spot := aimed_spot()
			var count := companions.order_goto(spot, _player.up_direction, who) if spot.is_finite() else 0
			if not spot.is_finite():
				said = tr("GROUP_SAID_NO_SPOT")
			elif count > 0:
				said = tr("GROUP_SAID_GOTO") % count
		GroupOrderWheel.Order.FORMATION:
			said = tr("GROUP_SAID_FORMATION") % tr(SettlementCompanions.FORMATION_NAMES[companions.next_formation()])
	if said != "":
		_player.hotbar.notify(said)


## El suelo (o lo construido) al que mira el jugador, a menos de GOTO_RANGE m de la vista, o INF.
func aimed_spot() -> Vector3:
	var camera := _player.camera
	if camera == null:
		return Vector3.INF
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * GOTO_RANGE,
		PhysicsLayers.WORLD, [_player.get_rid()])
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else Vector3.INF


## La fiera a la que irían: la fijada o, sin ella, la criatura viva más centrada en la vista.
func aimed_creature() -> NPCController:
	var locked := _player.combat.lock_target as NPCController if _player.combat != null else null
	if Companion._alive(locked):
		return locked
	var camera := _player.camera
	if camera == null:
		return null
	var forward := -camera.global_basis.z
	var best: NPCController
	var best_angle := deg_to_rad(AIM_ANGLE)
	for creature in CreatureGrid.near(_player.global_position, AIM_RANGE):
		if not Companion._alive(creature):
			continue
		var to := creature.get_lock_point() - camera.global_position if creature.has_method(&"get_lock_point") \
			else creature.global_position - camera.global_position
		var angle := forward.angle_to(to)
		if angle < best_angle:
			best = creature
			best_angle = angle
	return best


func _companions() -> SettlementCompanions:
	return get_tree().get_first_node_in_group(SettlementCompanions.GROUP) as SettlementCompanions

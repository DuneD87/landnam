class_name GroupCommand
extends Node

## Las órdenes del jugador al grupo que lo acompaña (SettlementCompanions.party), lejos del trono: su
## tecla (group_orders) abre la rueda (GroupOrderWheel) y lo elegido va a todos a la vez. Seguidme
## (los que esperan echan a andar), esperad aquí (se quedan y defienden el sitio), atacad (van a por
## la fiera fijada o, sin ella, a la que el jugador mira), retirada (dejan la pelea y vuelven
## corriendo), volved a la base (cada colono vuelve a la suya, con el trabajo que tenía) y la
## formación (cuña, fila o sueltos). Sin nadie en el grupo, la tecla solo avisa. Lo hecho se dice en
## el aviso de la barra. Ver docs/villagers.md.

## A lo que mira el jugador: la criatura viva a menos de AIM_RANGE m que queda a menos de AIM_ANGLE
## grados del centro de la vista.
const AIM_RANGE := 60.0
const AIM_ANGLE := 12.0

var wheel: GroupOrderWheel
var _player: PlayerController


func setup(player: PlayerController) -> void:
	_player = player
	wheel = GroupOrderWheel.new()
	wheel.name = "GroupOrderWheel"
	wheel.order_chosen.connect(give)
	add_child(wheel)
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
	wheel.open(summary, tr(SettlementCompanions.FORMATION_NAMES[companions.formation]),
		tr("GROUP_HINT_PREY") if aimed_creature() != null else "")


## Da [order] al grupo y lo dice en la barra.
func give(order: GroupOrderWheel.Order) -> void:
	var companions := _companions()
	if companions == null:
		return
	var said := ""
	match order:
		GroupOrderWheel.Order.FOLLOW:
			var count := companions.order_follow()
			said = tr("GROUP_SAID_FOLLOW") % companions.followers().size() if count > 0 else tr("GROUP_SAID_ALREADY")
		GroupOrderWheel.Order.WAIT:
			var count := companions.order_wait()
			said = tr("GROUP_SAID_WAIT") % count if count > 0 else tr("GROUP_SAID_NONE_FOLLOWING")
		GroupOrderWheel.Order.ATTACK:
			var prey := aimed_creature()
			var count := companions.order_attack(prey) if prey != null else 0
			said = tr("GROUP_SAID_ATTACK") % count if count > 0 else tr("GROUP_HINT_NO_PREY")
		GroupOrderWheel.Order.RETREAT:
			companions.order_retreat()
			said = tr("GROUP_SAID_RETREAT")
		GroupOrderWheel.Order.HOME:
			var result := companions.order_home()
			if int(result[0]) == 0:
				said = tr("GROUP_SAID_NO_BASE")
			elif int(result[1]) > 0:
				said = tr("GROUP_SAID_HOME_SOME") % [result[0], result[1]]
			else:
				said = tr("GROUP_SAID_HOME") % result[0]
		GroupOrderWheel.Order.FORMATION:
			said = tr("GROUP_SAID_FORMATION") % tr(SettlementCompanions.FORMATION_NAMES[companions.next_formation()])
	if said != "":
		_player.hotbar.notify(said)


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

class_name SiteBuilder
extends Node

## Las obras (BlueprintSite) desde el jugador. Se apunta a una con el rayo de construcción, antes que a
## lo que haya detrás, y a tiro de él. Apuntándola:
## - la E le aporta lo que le falta y se lleva encima (con cualquier cosa en la mano);
## - con el martillo en modo poner, el clic izquierdo es un martillazo (PlayerCombat.work_strike):
##   sube lo construido. Mantenido, se sigue martilleando. Sin material para lo que queda no se
##   golpea y avisa;
## - con el martillo en modo quitar, dos clics seguidos la desmontan: devuelve lo aportado y lo
##   construido.
## Mientras se apunta, un panel (BlueprintSitePanel) dice cómo va y qué le falta.

## Margen (m) con el que lo que golpea el rayo de física cuenta como la obra: el rayo la toca en el
## borde de la celda y la física, en la cara del bloque.
const AIM_SLACK := 0.06
## Tiempo para el segundo clic que desmonta (s).
const DISMANTLE_WINDOW := 4.0
## Cada cuánto se mira qué le pasa a la obra apuntada para el panel (s): en una grande, recorrer lo
## que falta cada fotograma se nota.
const PANEL_CHECK := 0.25

## La obra apuntada (null si ninguna).
var site: BlueprintSite = null

var _player: PlayerController
var _panel: BlueprintSitePanel
var _holding := false
var _armed: BlueprintSite = null
var _armed_left := 0.0
var _problem := &""
var _problem_left := 0.0


func setup(player: PlayerController) -> void:
	_player = player
	name = "SiteBuilder"
	_panel = BlueprintSitePanel.new()
	add_child(_panel)


## Busca la obra apuntada con el rayo de la cámara ([hit], lo que golpea la física; vacío si nada). A
## tiro: el punto a menos de [reach] de [from].
func update_aim(origin: Vector3, direction: Vector3, length: float, hit: Dictionary, from: Vector3,
	reach: float) -> void:
	var best: BlueprintSite = null
	var best_t := INF
	var hit_t := origin.distance_to(hit["position"]) if not hit.is_empty() else INF
	var hit_grid: GridBase = _player.building_system.get_aimed_grid(hit) if not hit.is_empty() else null
	if _can_aim():
		for node in get_tree().get_nodes_in_group(BlueprintSite.GROUP):
			var candidate := node as BlueprintSite
			if candidate == null or candidate.is_queued_for_deletion():
				continue
			if candidate.get_center().distance_to(from) > candidate.get_radius() + reach + length:
				continue
			var t := hit_t if candidate.owns_grid(hit_grid) else candidate.ray_distance(origin, direction, length)
			if t < 0.0 or t > hit_t + AIM_SLACK or t >= best_t:
				continue
			if from.distance_to(origin + direction * t) > reach:
				continue
			best = candidate
			best_t = t
	if best != site:
		if site != null and is_instance_valid(site):
			site.set_aimed(false)
		site = best
		_problem_left = 0.0
		if site != null:
			site.set_aimed(true)
	if site != null:
		_refresh_panel()
	else:
		_panel.hide_site()


func is_aiming() -> bool:
	return site != null and is_instance_valid(site) and not site.is_queued_for_deletion()


## Las obras se apuntan jugando, sin menús ni el ratón suelto, y sin estar colocando un blueprint.
func _can_aim() -> bool:
	var p := _player
	return p.visible and p.input_enabled and not p.free_flight_enabled and p.is_mouse_captured() \
		and not p.inventory_ui.visible and not p.blueprint_placer.is_active() and not p.combat.is_dead()


## El clic del martillo apuntando a una obra (en modo poner, martillear; en quitar, desmontar).
## false si no se apunta a ninguna.
func primary_pressed() -> bool:
	if not is_aiming() or not _player._holds_hammer():
		return false
	if _player.building_system.current_action_mode == BuildingSystem.ActionMode.DESTROY:
		_press_dismantle()
		return true
	_holding = true
	_strike()
	return true


## La E apuntando a una obra: le aporta lo que le falta. false si no se apunta a ninguna.
func deposit() -> bool:
	if not is_aiming():
		return false
	if BuildingSystem.free_build:
		_notify(tr("SITE_FREE"))
		return true
	var moved := site.deposit(_player.inventory)
	if not moved.is_empty():
		AudioManager.play_ui(&"item_pickup")
		_notify(tr("SITE_DEPOSITED") % BuildCost.describe(moved))
	elif site.get_missing().is_empty():
		_notify(tr("SITE_HAS_ALL"))
	else:
		_notify(tr("SITE_NOTHING_TO_GIVE"))
	_problem_left = 0.0
	_refresh_panel()
	return true


func _process(delta: float) -> void:
	_armed_left -= delta
	_problem_left -= delta
	if not _holding:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or not is_aiming() or not _player._holds_hammer() \
			or _player.building_system.current_action_mode != BuildingSystem.ActionMode.BUILD:
		_holding = false
		return
	if not _player.combat.is_busy():
		_strike()


## Un martillazo, si hay qué poner; si no, deja de martillear y avisa de por qué. Pulsado a media
## martillada, el siguiente sale al acabar esta (_process).
func _strike() -> void:
	var problem := site.work_problem([_player.global_position])
	if problem != &"":
		_holding = false
		_notify(_problem_text(problem))
		return
	if _player.combat.is_busy():
		return
	if not _player.combat.work_strike(_on_impact.bind(site)):
		_holding = false


## El impacto del martillazo en [target]: pone lo que toca, suena como poner un bloque (plano, como
## al construir con el martillo) y avisa al acabarla.
func _on_impact(target: BlueprintSite) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	var name_shown := target.blueprint_name
	var result := target.work([_player.global_position])
	_problem_left = 0.0
	if result["placed"] == 0:
		_holding = false
		_notify(_problem_text(result["problem"]))
		return false
	AudioManager.play_material_flat(&"block_place", result["sound"])
	if result["finished"]:
		_holding = false
		var leftover := target.take_deposited()
		BuildCost.give(leftover, _player.inventory, _player, _player.gravity_direction)
		_notify(tr("SITE_FINISHED") % (name_shown if name_shown != "" else tr("SITE_TITLE")))
	return true


func _press_dismantle() -> void:
	if _armed != site or _armed_left <= 0.0:
		_armed = site
		_armed_left = DISMANTLE_WINDOW
		_notify(tr("SITE_DISMANTLE_CONFIRM"))
		return
	_armed = null
	_holding = false
	var target := site
	var deposited := target.take_deposited()
	var grid_id := target.get_grid_id()
	target.remove()
	site = null
	_panel.hide_site()
	# Lo construido vuelve como al desmontar una construcción (según la vida de cada bloque) y lo
	# aportado, entero.
	var back := deposited.duplicate()
	if grid_id != "":
		var built := _player.building_system.dismantle_group(grid_id)
		for id: StringName in built:
			BuildCost.add(back, id, int(built[id]))
	BuildCost.give(deposited, _player.inventory, _player, _player.gravity_direction)
	AudioManager.play_material_flat(&"block_remove", &"wood")
	_notify(tr("SITE_DISMANTLED") % (BuildCost.describe(back) if not back.is_empty() else tr("GRID_VALUE_NONE").to_lower()))


func _refresh_panel() -> void:
	if not is_aiming():
		_panel.hide_site()
		return
	if _problem_left <= 0.0:
		_problem_left = PANEL_CHECK
		_problem = site.work_problem([_player.global_position])
	var hammer := _player._holds_hammer()
	var state := ""
	var ok := _problem == &""
	if ok:
		state = tr("SITE_READY") if hammer else tr("SITE_NEED_HAMMER")
		ok = hammer
	else:
		state = _problem_text(_problem)
	_panel.show_site(site, _player.inventory, state, ok)


func _problem_text(problem: StringName) -> String:
	match problem:
		&"missing":
			return tr("SITE_NEEDS_MATERIALS")
		&"blocked":
			return tr("SITE_BLOCKED")
		&"done":
			return tr("SITE_DONE")
	return ""


func _notify(text: String) -> void:
	if _player.hotbar != null and text != "":
		_player.hotbar.notify(text)

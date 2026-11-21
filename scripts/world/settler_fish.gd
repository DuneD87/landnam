class_name SettlerFish extends SettlerTask

## El colono pescador: pesca en el agua de su zona. Necesita una caña en el morral (ni anzuelos ni
## cebo: como las demás herramientas de los colonos, no se gasta). Busca la orilla más cercana a él
## (_find_spot: tantea el agua en anillos alrededor del centro de su zona y vuelve hacia tierra hasta
## pisar seco), va hasta ella y pesca como el jugador (_fishing): lanza la boya, espera a que un pez de
## los que hay a la vista (AmbientFish) vaya a por el anzuelo, lo engancha o se le escapa y lo recoge
## hasta la orilla (los brazos, CombatPose.fishing). Lo que saca es lo que pesca su caña
## (FishingRodTrait.catch_id). Los peces solo salen alrededor del jugador: sin ninguno cerca, pica uno
## que no se ve cada UNSEEN s. Con CARRY encima los lleva al cofre de la base que acepte su oficio (sin
## cocinero en la base, al comedero: food_drop) y vuelve. Sin agua en su zona no hace nada; sin cofre
## con sitio, tampoco.
##
## Si no ve agua porque su zona está
## lejos de la cámara (sin cargar), va hacia ella (toward_zone). Lejos del jugador, si ya había
## encontrado su orilla o el mapa dice que en su zona hay mar (map_water), saca uno cada AWAY_CATCH s. En campo (SettlerWork.field) sin cofre cerca, lo
## pescado se queda en el morral hasta llenarlo. Ver docs/villagers.md.

enum Phase {SEEK, FISH, DEPOSIT}

const AWAY_CATCH := 90.0
const CARRY := 5
const SPOT_REACH := 1.2

## Lo que hace en la orilla (_fishing).
enum Cast {IDLE, CASTING, WAITING, BITE, REELING}

## Entre lanzar y lanzar (s); cuánto más allá de la orilla cae la boya (m) y hasta qué parte del alcance
## de la caña; cuánto espera sin picada antes de recoger y volver a lanzar (s).
const CAST_PAUSE := Vector2(2.0, 5.0)
const CAST_BEYOND := Vector2(3.0, 7.0)
const CAST_SHARE := 0.6
const RECAST := Vector2(40.0, 70.0)
## Sin peces a la vista, pica uno que no se ve cada tanto (s, a su ritmo).
const UNSEEN := Vector2(90.0, 180.0)

var _phase := Phase.SEEK
var _cast := Cast.IDLE
var _at_spot := false
var _float: FishingFloat
var _fish: AmbientFish
var _hooked := false
## El tiempo en lo que hace ahora; la pausa antes de lanzar; lo que le queda esperando la picada; y para
## volver a mirar si hay peces.
var _t := 0.0
var _pause := 0.0
var _wait_left := 0.0
var _scan_left := 0.0
var _unseen_left := 0.0
## De dónde sale y dónde cae la boya (marco del terreno).
var _cast_from := Vector3.ZERO
var _cast_to := Vector3.ZERO
## Donde se pone y el agua a la que mira (marco del terreno), o Vector3.INF.
var _spot := Vector3.INF
var _water := Vector3.INF
var _seek_left := 0.0
var _empty_seeks := 0
var _owed := 0.0
## Sin orilla a la vista y con la zona sin cargar: va hacia ella (toward_zone). Y, lejos, si el mapa dice
## que en la zona hay agua (map_water; -1: sin mirar).
var _to_zone := false
var _map_wet := -1


func describe() -> String:
	var what := c.tr("SETTLER_JOB_FISH")
	match w.status:
		SettlerWork.Status.OFF_HOURS:
			return c.tr("SETTLER_OFF_HOURS") % [what, w.gathered]
		SettlerWork.Status.AWAY:
			return c.tr("SETTLER_AWAY") % [what, w.gathered]
	return c.tr("SETTLER_WORKING") % [what, w.gathered]


func save_data() -> Dictionary:
	if not _spot.is_finite():
		return {}
	return {"spot": [_spot.x, _spot.y, _spot.z], "water": [_water.x, _water.y, _water.z]}


func restore(data: Dictionary) -> void:
	var spot: Array = data.get("spot", [])
	var water: Array = data.get("water", [])
	if spot.size() == 3 and water.size() == 3:
		_spot = Vector3(spot[0], spot[1], spot[2])
		_water = Vector3(water[0], water[1], water[2])


func step(delta: float) -> Array:
	_at_spot = false
	var out := _step(delta)
	if not _at_spot:
		_end_cast()
	return out


func stop() -> void:
	_end_cast()


func paused() -> void:
	_end_cast()


func _step(delta: float) -> Array:
	var rod := _rod()
	if rod == null:
		w.block("SETTLER_NEED_ROD")
		return still()
	var fish := _catch(rod)
	if _spot.is_finite() or _phase == Phase.DEPOSIT or w.status != SettlerWork.Status.BLOCKED:
		w.status = SettlerWork.Status.WORKING
	# En campo, con una tanda, antes a quien la necesite (un cocinero): el viaje lo lleva SettlerWork.
	if w.field and carried(fish) >= CARRY and w.plan_delivery():
		return still()
	# En campo, sin cofre cerca, lo pescado se queda en el morral.
	var to_chest := not w.field or chest_with_room(chests(SettlerWork.JOB_IDS[SettlerWork.Job.FISH], true), fish) != null
	if to_chest and (_phase == Phase.DEPOSIT or carried(fish) >= CARRY):
		return _depositing(delta, fish)
	if _phase == Phase.DEPOSIT:
		_phase = Phase.FISH
	if not _spot.is_finite():
		return _seek(fish, delta)
	var to_world := c._terrain.global_transform
	var state := walk(to_world * _spot, SPOT_REACH, delta, self)
	if state == Walk.GOING:
		return [heading, SettlerWork.WALK_SPEED]
	if state == Walk.GAVE_UP:
		# No llega a esa orilla: busca otra.
		_spot = Vector3.INF
		return still()
	_at_spot = true
	if rod.scene_path != "":
		c.hold_work_tool(rod)
	if not _fishing(delta, rod):
		return still()
	if c.pack.add_item(fish, 1) == 0:
		w.gathered += 1
	elif w.field and not to_chest:
		w.pack_full()
	elif carried(fish) > 0:
		# No le cabe más: a dejar lo que lleva.
		_phase = Phase.DEPOSIT
	return still()


# --- En la orilla: lanzar, esperar, tirar ---------------------------------------------------------

## Un paso pescando en su sitio, como el jugador (PlayerFishing): lanza la boya al agua, espera a que un
## pez de los que hay (AmbientFish) vaya a por el anzuelo y pique, lo engancha (o se le escapa) y recoge
## hasta tenerlo en la orilla. Cierto cuando saca uno. Sin peces cerca (solo los hay alrededor del
## jugador), alguno pica igual cada UNSEEN s.
func _fishing(delta: float, rod: ItemData) -> bool:
	var rod_trait := rod.get_trait(FishingRodTrait) as FishingRodTrait
	var to_world := c._terrain.global_transform
	_t += delta
	var landed := false
	match _cast:
		Cast.IDLE:
			c._face(to_world * _water - c.global_position, delta)
			if _t >= _pause:
				_begin_cast(rod_trait)
		Cast.CASTING:
			_casting()
		Cast.WAITING, Cast.BITE:
			_waiting(delta, rod_trait)
		Cast.REELING:
			landed = _reeling(delta, rod_trait)
	_update_pose(delta)
	return landed


## Lanza: hacia el agua que tiene delante, un poco más allá de la orilla y sin pasar del alcance de la caña.
func _begin_cast(rod_trait: FishingRodTrait) -> void:
	var to_world := c._terrain.global_transform
	var water := to_world * _water
	var out := (water - c.global_position).slide(c.up_direction)
	if out.length() < 0.1:
		_pause = 2.0
		_t = 0.0
		return
	var reach := clampf(out.length() + c._rng.randf_range(CAST_BEYOND.x, CAST_BEYOND.y), rod_trait.min_distance,
		rod_trait.max_distance * CAST_SHARE)
	var target := c.global_position + out.normalized() * reach
	if not _wet_at(target):
		target = water
	_cast_to = c._terrain.global_transform.affine_inverse() * _surface(target)
	_cast_from = c._terrain.global_transform.affine_inverse() * _tip()
	if _float == null or not is_instance_valid(_float):
		_float = FishingFloat.new()
		_float.npc = true
		_float.name = "SettlerFloat"
		c._terrain.add_child(_float)
	_float.position = _cast_from
	_cast = Cast.CASTING
	_t = 0.0
	_unseen_left = c._rng.randf_range(UNSEEN.x, UNSEEN.y) if _unseen_left <= 0.0 else _unseen_left


func _casting() -> void:
	var k := clampf((_t - PlayerFishing.CAST_TIME * 0.35) / PlayerFishing.FLIGHT_TIME, 0.0, 1.0)
	var to_world := c._terrain.global_transform
	var to := to_world * _cast_to
	var point := (to_world * _cast_from).lerp(to, k) + (to - c._terrain.global_position).normalized() * sin(k * PI) * 3.0
	_float.global_transform = Transform3D(_float_frame(to), point)
	_float.present(get_delta(), false, true, false, false, true)
	_float.draw_line(_tip(), true)
	if k >= 1.0:
		_cast = Cast.WAITING
		_t = 0.0
		_scan_left = 0.0
		_wait_left = c._rng.randf_range(RECAST.x, RECAST.y)


func _waiting(delta: float, rod_trait: FishingRodTrait) -> void:
	var to_world := c._terrain.global_transform
	_float.global_transform = Transform3D(_float_frame(to_world * _cast_to), to_world * _cast_to)
	_float.present(delta, false, true, _cast == Cast.BITE, false)
	_float.draw_line(_tip(), false)
	c._face(_float.global_position - c.global_position, delta)
	if _fish != null and (not is_instance_valid(_fish) or not _fish.active or not _fish.follows_lure(_float.hook)):
		_fish = null
		_cast = Cast.WAITING
	_scan_left -= delta
	if _fish == null and _scan_left <= 0.0:
		_scan_left = 0.5
		_fish = _find_fish(rod_trait)
		if _fish != null:
			_fish.follow_lure(_float.hook)
	if _fish == null:
		# Sin peces a la vista: de vez en cuando pica uno que no se ve; si no, recoge y vuelve a lanzar.
		_unseen_left -= delta * w.pace()
		if _unseen_left <= 0.0:
			_unseen_left = 0.0
			_hooked = true
			_cast = Cast.REELING
			_t = 0.0
			return
		_wait_left -= delta
		if _wait_left <= 0.0:
			_hooked = false
			_cast = Cast.REELING
			_t = 0.0
		return
	if _fish.global_position.distance_to(_float.hook.global_position) > PlayerFishing.BITE_DISTANCE:
		_cast = Cast.WAITING
		return
	if _cast == Cast.WAITING:
		_cast = Cast.BITE
		_t = 0.0
	elif _t >= rod_trait.bite_time:
		# Engancharlo o no, como al jugador; el que no pica se va.
		_hooked = c._rng.randf() < rod_trait.hook_chance
		if not _hooked:
			_fish.release_lure()
			_fish = null
		_cast = Cast.REELING
		_t = 0.0


## Recoge la boya hacia él (con el pez detrás si lo ha enganchado). Cierto si lo saca.
func _reeling(delta: float, rod_trait: FishingRodTrait) -> bool:
	if _fish != null and (not is_instance_valid(_fish) or not _fish.active or not _fish.follows_lure(_float.hook)):
		# Se ha soltado.
		_fish = null
		_hooked = false
	var to_world := c._terrain.global_transform
	var here := _float.global_position
	var next := _surface(here.move_toward(_surface(c.global_position), rod_trait.reel_speed * (1.0 if _hooked else 2.0) * delta))
	var close := next.distance_to(c.global_position) <= PlayerFishing.CATCH_DISTANCE
	if close or not _wet_at(next):
		var landed := _hooked
		if _fish != null:
			_fish.deactivate()
			_fish = null
		_hooked = false
		_end_cast(false)
		return landed
	_float.global_transform = Transform3D(_float_frame(next), next)
	_cast_to = to_world.affine_inverse() * next
	_float.present(delta, false, true, false, _hooked)
	_float.draw_line(_tip(), false)
	c._face(next - c.global_position, delta)
	return false


## Los brazos (CombatPose.fishing): preparar y lanzar, la caña arriba esperando y los tirones al recoger.
func _update_pose(delta: float) -> void:
	var p := c.combat_pose()
	p.grip_right = true
	var pose := p.fishing
	pose.weight = move_toward(pose.weight, 1.0, delta * 8.0)
	pose.direction = (_float.global_position - c.global_position).normalized() \
		if _float != null and is_instance_valid(_float) else c.facing()
	pose.cast_phase = clampf(_t / PlayerFishing.CAST_TIME, 0.0, 1.0) if _cast == Cast.CASTING else -1.0
	pose.pull = 0.65 + sin(_t * 14.0) * 0.15 if _cast == Cast.REELING and _hooked else 0.0
	var visual := c._tool as FishingRodVisual
	if visual != null:
		visual.update_tension(pose.pull)


## Recoge el aparejo (sin pez) y suelta la caña. Con [all], también la pose: deja de pescar.
func _end_cast(all := true) -> void:
	if _fish != null and is_instance_valid(_fish):
		_fish.release_lure()
	_fish = null
	_hooked = false
	if _float != null and is_instance_valid(_float):
		_float.queue_free()
	_float = null
	_cast = Cast.IDLE
	_t = 0.0
	_pause = c._rng.randf_range(CAST_PAUSE.x, CAST_PAUSE.y)
	if all and c.pose != null:
		c.pose.fishing.weight = 0.0
		c.pose.grip_right = false
		var visual := c._tool as FishingRodVisual
		if visual != null and is_instance_valid(visual):
			visual.update_tension(0.0)


## El pez más cercano a la boya que puede ir a por el anzuelo, a menos del alcance de la caña, o null.
func _find_fish(rod_trait: FishingRodTrait) -> AmbientFish:
	var best: AmbientFish
	var best_d := rod_trait.attraction_radius * rod_trait.attraction_radius
	for node in c.get_tree().get_nodes_in_group(AmbientAnimal.GROUP):
		var fish := node as AmbientFish
		if fish == null or not fish.can_be_fished() or fish.habitat.host() != c._terrain:
			continue
		var d := fish.global_position.distance_squared_to(_float.hook.global_position)
		if d < best_d and fish.can_follow_lure(_float.hook):
			best = fish
			best_d = d
	return best


## La punta de la caña (mundo), o algo por delante de su cabeza.
func _tip() -> Vector3:
	var visual := c._tool as FishingRodVisual
	if visual != null and is_instance_valid(visual) and visual.visible:
		return visual.tip_world()
	return c.global_position + c.up_direction * 1.6 + c.facing() * 0.8


## [point] a la altura del agua (el mar, los ríos y los lagos están a la del mar).
func _surface(point: Vector3) -> Vector3:
	var origin := c._terrain.global_position
	return origin + (point - origin).normalized() * _sea_radius()


func _float_frame(point: Vector3) -> Basis:
	var up := (point - c._terrain.global_position).normalized()
	var right := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	return Basis(right, up, right.cross(up))


## Si en [point] hay agua para el anzuelo (FishingFloat.HOOK_DEPTH m).
func _wet_at(point: Vector3) -> bool:
	var terrain := c._terrain as VoxelLodTerrain
	var sea := _sea_radius()
	if terrain == null or sea <= 0.0:
		return false
	var tool := terrain.get_voxel_tool() as VoxelToolLodTerrain
	tool.channel = VoxelBuffer.CHANNEL_SDF
	var origin := terrain.global_position
	var dir := (point - origin).normalized()
	return WaterAccess._has_water(terrain, tool, origin + dir * sea) \
		and WaterAccess._has_water(terrain, tool, origin + dir * (sea - FishingFloat.HOOK_DEPTH))


func get_delta() -> float:
	return c.get_physics_process_delta_time()


func _seek(fish: ItemData, delta: float) -> Array:
	if SettlerWork._now() < _seek_left:
		return _going_to_zone(delta)
	_seek_left = SettlerWork._now() + SettlerWork.SEEK_EVERY
	w.status = SettlerWork.Status.WORKING
	_to_zone = false
	if not _has_chest(fish):
		return still()
	if _find_spot():
		_empty_seeks = 0
		return still()
	# Con el terreno de la zona sin cargar no se ve el agua: va hacia ella, y no se da por seca hasta
	# verla tres veces.
	if not w._zone_loaded():
		_empty_seeks = 0
		_to_zone = true
		return _going_to_zone(delta)
	_empty_seeks += 1
	if _empty_seeks >= SettlerWork.EMPTY_SEEKS:
		_empty_seeks = 0
		w.block("SETTLER_NO_WATER")
		w._seek_left = SettlerWork._now() + SettlerWork.DONE_RECHECK
		_seek_left = w._seek_left
	return still()


func _going_to_zone(delta: float) -> Array:
	var going := toward_zone(delta) if _to_zone else []
	return going if not going.is_empty() else still()


func _depositing(delta: float, fish: ItemData) -> Array:
	_phase = Phase.DEPOSIT
	if carried(fish) == 0:
		_phase = Phase.FISH
		return still()
	var chest := food_drop(fish)
	if chest == null:
		chest = chest_with_room(chests(SettlerWork.JOB_IDS[SettlerWork.Job.FISH], true), fish)
	if chest == null:
		_has_chest(fish)
		return still()
	if walk(chest.global_position, SettlerWork.DEPOSIT_REACH, delta, chest) == Walk.GOING:
		return [heading, SettlerWork.WALK_SPEED]
	move(c.pack, chest.inventory, fish, carried(fish))
	_phase = Phase.FISH
	return still()


func away(delta: float, _hour: float) -> void:
	var rod := _rod()
	if rod == null:
		w.block("SETTLER_NEED_ROD")
		return
	var fish := _catch(rod)
	if not _has_chest(fish):
		return
	w.status = SettlerWork.Status.AWAY
	# Sin haber visto la orilla, le vale con que el mapa diga que en su zona hay mar.
	if not _spot.is_finite():
		if _map_wet < 0:
			_map_wet = int(map_water())
		if _map_wet == 0:
			return
	_owed += delta * w.pace() / AWAY_CATCH
	if _owed < 1.0:
		return
	_owed -= 1.0
	var chest := food_drop(fish)
	if chest == null:
		chest = chest_with_room(chests(SettlerWork.JOB_IDS[SettlerWork.Job.FISH], true), fish)
	w.gathered += 1 - chest.inventory.add_item(fish, 1)


func _rod() -> ItemData:
	return best_in_pack(func(data: ItemData) -> float:
		return 1.0 if data.get_trait(FishingRodTrait) != null else 0.0)


func _catch(rod: ItemData) -> ItemData:
	return ItemCatalog.get_item((rod.get_trait(FishingRodTrait) as FishingRodTrait).catch_id)


func _has_chest(fish: ItemData) -> bool:
	if w.field:
		if w.field_room(fish):
			return true
		w.pack_full()
		return false
	var from := chests(SettlerWork.JOB_IDS[SettlerWork.Job.FISH], true)
	if chest_with_room(from, fish) != null or food_drop(fish) != null:
		return true
	if from.is_empty():
		w.block("SETTLER_NO_CHEST_SHORT", [c.tr("SETTLER_JOB_FISH")])
	else:
		w.block("SETTLER_CHEST_FULL_SHORT")
	return false


## Busca la orilla de su zona más cercana a él (SettlerTask.find_shore). Falso si no hay (o el terreno
## aún no está cargado).
func _find_spot() -> bool:
	var shore := find_shore()
	if shore.is_empty():
		return false
	_spot = shore[0]
	_water = shore[1]
	return true

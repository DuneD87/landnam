class_name SettlerFish extends SettlerTask

## El colono pescador: pesca en el agua de su zona. Necesita una caña en el morral (ni anzuelos ni
## cebo: como las demás herramientas de los colonos, no se gasta). Busca la orilla más cercana a él
## (_find_spot: tantea el agua en anillos alrededor del centro de su zona y vuelve hacia tierra hasta
## pisar seco), va hasta ella y, de cara al agua con la caña en la mano, saca un pescado (lo que
## pesca su caña, FishingRodTrait.catch_id) cada CATCH_TIME s. Con CARRY encima los lleva al cofre de
## la base que acepte su oficio y vuelve. Sin agua en su zona no hace nada; sin cofre con sitio,
## tampoco.
##
## No lanza de verdad ni depende de los peces que haya a la vista. Lejos del jugador, si ya había
## encontrado su orilla, saca uno cada AWAY_CATCH s. Ver docs/villagers.md.

enum Phase {SEEK, FISH, DEPOSIT}

const CATCH_TIME := Vector2(60.0, 120.0)
const AWAY_CATCH := 90.0
const CARRY := 5
## La orilla: anillos cada RING_STEP m con ANGLES tanteos; del agua hacia tierra, pasos de SHORE_STEP m
## (hasta SHORE_STEPS). El agua tiene que cubrir WATER_DEPTH m.
const RING_STEP := 3.0
const ANGLES := 16
const SHORE_STEP := 0.75
const SHORE_STEPS := 16
const WATER_DEPTH := 0.6
const SPOT_REACH := 1.2

var _phase := Phase.SEEK
## Donde se pone y el agua a la que mira (marco del terreno), o Vector3.INF.
var _spot := Vector3.INF
var _water := Vector3.INF
var _catch_left := 0.0
var _seek_left := 0.0
var _empty_seeks := 0
var _owed := 0.0


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
	var rod := _rod()
	if rod == null:
		w.block(c.tr("SETTLER_NEED_ROD"))
		return still()
	var fish := _catch(rod)
	if _spot.is_finite() or _phase == Phase.DEPOSIT or w.status != SettlerWork.Status.BLOCKED:
		w.status = SettlerWork.Status.WORKING
	if _phase == Phase.DEPOSIT or carried(fish) >= CARRY:
		return _depositing(delta, fish)
	if not _spot.is_finite():
		return _seek(fish)
	var to_world := c._terrain.global_transform
	var state := walk(to_world * _spot, SPOT_REACH, delta, self)
	if state == Walk.GOING:
		return [heading, SettlerWork.WALK_SPEED]
	if state == Walk.GAVE_UP:
		# No llega a esa orilla: busca otra.
		_spot = Vector3.INF
		return still()
	c._face(to_world * _water - c.global_position, delta)
	if rod.scene_path != "":
		c.hold_work_tool(rod)
	if _catch_left <= 0.0:
		_catch_left = c._rng.randf_range(CATCH_TIME.x, CATCH_TIME.y)
	_catch_left -= delta * w.pace()
	if _catch_left <= 0.0:
		if c.pack.add_item(fish, 1) == 0:
			w.gathered += 1
		elif carried(fish) > 0:
			# No le cabe más: a dejar lo que lleva.
			_phase = Phase.DEPOSIT
	return still()


func _seek(fish: ItemData) -> Array:
	if SettlerWork._now() < _seek_left:
		return still()
	_seek_left = SettlerWork._now() + SettlerWork.SEEK_EVERY
	w.status = SettlerWork.Status.WORKING
	if not _has_chest(fish):
		return still()
	if _find_spot():
		_empty_seeks = 0
		return still()
	# Con el terreno de la zona sin cargar no se ve el agua: no se da por seca hasta verla tres veces.
	_empty_seeks = _empty_seeks + 1 if w._zone_loaded() else 0
	if _empty_seeks >= SettlerWork.EMPTY_SEEKS:
		_empty_seeks = 0
		w.block(c.tr("SETTLER_NO_WATER"))
		w._seek_left = SettlerWork._now() + SettlerWork.DONE_RECHECK
		_seek_left = w._seek_left
	return still()


func _depositing(delta: float, fish: ItemData) -> Array:
	_phase = Phase.DEPOSIT
	if carried(fish) == 0:
		_phase = Phase.FISH
		return still()
	var chest := chest_with_room(chests(SettlerWork.JOB_IDS[SettlerWork.Job.FISH], true), fish)
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
		w.block(c.tr("SETTLER_NEED_ROD"))
		return
	var fish := _catch(rod)
	if not _has_chest(fish):
		return
	w.status = SettlerWork.Status.AWAY
	if not _spot.is_finite():
		return
	_owed += delta * w.pace() / AWAY_CATCH
	if _owed < 1.0:
		return
	_owed -= 1.0
	var chest := chest_with_room(chests(SettlerWork.JOB_IDS[SettlerWork.Job.FISH], true), fish)
	w.gathered += 1 - chest.inventory.add_item(fish, 1)


func _rod() -> ItemData:
	return best_in_pack(func(data: ItemData) -> float:
		return 1.0 if data.get_trait(FishingRodTrait) != null else 0.0)


func _catch(rod: ItemData) -> ItemData:
	return ItemCatalog.get_item((rod.get_trait(FishingRodTrait) as FishingRodTrait).catch_id)


func _has_chest(fish: ItemData) -> bool:
	var from := chests(SettlerWork.JOB_IDS[SettlerWork.Job.FISH], true)
	if chest_with_room(from, fish) != null:
		return true
	w.block(c.tr("SETTLER_CHEST_FULL_SHORT") if not from.is_empty()
		else c.tr("SETTLER_NO_CHEST_SHORT") % c.tr("SETTLER_JOB_FISH"))
	return false


## Busca la orilla de su zona más cercana a él: el agua más cercana y, de ella hacia el centro de la
## zona, el primer sitio seco. Falso si no hay (o el terreno aún no está cargado).
func _find_spot() -> bool:
	var terrain := c._terrain as VoxelLodTerrain
	var sea := _sea_radius()
	if terrain == null or sea <= 0.0:
		return false
	var tool := terrain.get_voxel_tool() as VoxelToolLodTerrain
	tool.channel = VoxelBuffer.CHANNEL_SDF
	var origin := terrain.global_position
	var middle := center()
	var up := (middle - origin).normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	var best := Vector3.INF
	var best_d := INF
	var r := RING_STEP
	while r <= w.zone_radius:
		for k in ANGLES:
			var point := middle + side.rotated(up, TAU * k / ANGLES) * r
			if not _wet(terrain, tool, origin, point, sea):
				continue
			var d := point.distance_to(c.global_position)
			if d < best_d:
				best = point
				best_d = d
		r += RING_STEP
	if not best.is_finite():
		return false
	var inland := (middle - best).slide(up)
	if inland.length() < 0.1:
		return false
	inland = inland.normalized()
	for i in range(1, SHORE_STEPS + 1):
		var point := best + inland * SHORE_STEP * i
		if _wet(terrain, tool, origin, point, sea):
			continue
		var to_local := terrain.global_transform.affine_inverse()
		# Un paso más adentro: los pies, en seco.
		_spot = to_local * (point + inland * SHORE_STEP)
		_water = to_local * best
		return true
	return false


## Si en la vertical de [point] hay agua que cubra WATER_DEPTH m (los vóxeles sin cargar no cuentan).
func _wet(terrain: VoxelLodTerrain, tool: VoxelToolLodTerrain, origin: Vector3, point: Vector3, sea: float) -> bool:
	var dir := (point - origin).normalized()
	return WaterAccess._has_water(terrain, tool, origin + dir * sea) \
		and WaterAccess._has_water(terrain, tool, origin + dir * (sea - WATER_DEPTH))


## El radio del mar del planeta, o 0 si no tiene agua.
func _sea_radius() -> float:
	var host: Variant = c._player.get("planet") if c._player != null and is_instance_valid(c._player) else null
	var core := (host as Node).get("planet") as Planet if host is Node else null
	if core == null or not core.has_water:
		return 0.0
	return core.radius - core.water_radius

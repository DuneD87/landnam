class_name SettlerWater extends SettlerTask

## El colono aguador: llena de agua dulce los bebederos de la base (WaterTrough). Necesita odres en el
## morral (WaterContainerTrait): lleva los tragos que caben en todos (capacity × cuántos). Busca la
## orilla de agua dulce más cercana de su zona (find_shore: ríos, lagos y charcas; el mar no vale), va
## hasta ella, llena los odres en FILL_TIME s y los vacía en el bebedero de la base con más sitio. Con
## todos llenos espera junto a ellos y vuelve a mirar cada FULL_RECHECK s. Sin odre, sin bebedero o
## sin agua dulce en su zona, parado.
##
## Lejos del jugador, si ya había encontrado su orilla, echa en los bebederos lo que lleva una vez cada
## AWAY_TRIP s. Lo que lleva en los odres al guardar se guarda con su oficio. Ver docs/villagers.md.

enum Phase {SEEK, FILL, POUR}

const FILL_TIME := 6.0
const AWAY_TRIP := 120.0
const SPOT_REACH := 1.2
const POUR_REACH := 1.5
const FULL_RECHECK := 20.0

var _phase := Phase.SEEK
## Donde se pone y el agua a la que mira (marco del terreno), o Vector3.INF.
var _spot := Vector3.INF
var _water := Vector3.INF
## Los tragos que lleva en los odres.
var _carry := 0
var _fill_left := 0.0
var _seek_left := 0.0
var _empty_seeks := 0
var _owed := 0.0


func describe() -> String:
	var what := c.tr("SETTLER_JOB_WATER")
	match w.status:
		SettlerWork.Status.OFF_HOURS:
			return c.tr("SETTLER_OFF_HOURS") % [what, w.gathered]
		SettlerWork.Status.AWAY:
			return c.tr("SETTLER_AWAY") % [what, w.gathered]
	return c.tr("SETTLER_WORKING") % [what, w.gathered]


func save_data() -> Dictionary:
	var out := {}
	if _carry > 0:
		out.carry = _carry
	if _spot.is_finite():
		out.spot = [_spot.x, _spot.y, _spot.z]
		out.water = [_water.x, _water.y, _water.z]
	return out


func restore(data: Dictionary) -> void:
	_carry = int(data.get("carry", 0))
	var spot: Array = data.get("spot", [])
	var water: Array = data.get("water", [])
	if spot.size() == 3 and water.size() == 3:
		_spot = Vector3(spot[0], spot[1], spot[2])
		_water = Vector3(water[0], water[1], water[2])
	if _carry > 0:
		_phase = Phase.POUR


func step(delta: float) -> Array:
	var room := capacity()
	if room <= 0:
		w.block(c.tr("SETTLER_NEED_SKIN"))
		return still()
	_carry = mini(_carry, room)
	var trough := _trough()
	if trough == null:
		if not _has_trough():
			return still()
		# Todos llenos: espera y vuelve a mirar.
		w.rest_done()
		w._seek_left = SettlerWork._now() + FULL_RECHECK
		return still()
	w.status = SettlerWork.Status.WORKING
	if _phase == Phase.POUR or _carry >= room:
		return _pouring(delta, trough)
	if not _spot.is_finite():
		return _seek()
	var to_world := c._terrain.global_transform
	var state := walk(to_world * _spot, SPOT_REACH, delta, self)
	if state == Walk.GOING:
		return [heading, SettlerWork.WALK_SPEED]
	if state == Walk.GAVE_UP:
		# No llega a esa orilla: busca otra.
		_spot = Vector3.INF
		return still()
	c._face(to_world * _water - c.global_position, delta)
	_phase = Phase.FILL
	if _fill_left <= 0.0:
		_fill_left = FILL_TIME
	_fill_left -= delta * w.pace()
	if _fill_left <= 0.0:
		_carry = room
		_phase = Phase.POUR
	return still()


func _pouring(delta: float, trough: WaterTrough) -> Array:
	_phase = Phase.POUR
	if _carry <= 0:
		_phase = Phase.SEEK
		return still()
	if walk(trough.global_position, POUR_REACH, delta, trough) == Walk.GOING:
		return [heading, SettlerWork.WALK_SPEED]
	c._face(trough.global_position - c.global_position, delta)
	var poured := trough.pour(_carry)
	_carry -= poured
	w.gathered += poured
	# Lo que no cabe se lo echa al siguiente; sin sitio en ninguno, lo tira y vuelve.
	if _carry > 0 and _trough() == null:
		_carry = 0
	if _carry <= 0:
		_phase = Phase.SEEK
	return still()


func _seek() -> Array:
	if SettlerWork._now() < _seek_left:
		return still()
	_seek_left = SettlerWork._now() + SettlerWork.SEEK_EVERY
	var shore := find_shore(true)
	if not shore.is_empty():
		_spot = shore[0]
		_water = shore[1]
		_empty_seeks = 0
		return still()
	# Con el terreno de la zona sin cargar no se ve el agua: no se da por seca hasta verla tres veces.
	_empty_seeks = _empty_seeks + 1 if w._zone_loaded() else 0
	if _empty_seeks >= SettlerWork.EMPTY_SEEKS:
		_empty_seeks = 0
		w.block(c.tr("SETTLER_NO_FRESH_WATER"))
		w._seek_left = SettlerWork._now() + SettlerWork.DONE_RECHECK
		_seek_left = w._seek_left
	return still()


func away(delta: float, _hour: float) -> void:
	var room := capacity()
	if room <= 0:
		w.block(c.tr("SETTLER_NEED_SKIN"))
		return
	if not _has_trough():
		return
	w.status = SettlerWork.Status.AWAY
	if not _spot.is_finite():
		return
	_owed += delta * w.pace() / AWAY_TRIP
	if _owed < 1.0:
		return
	_owed -= 1.0
	_carry = room
	for trough in troughs():
		var poured := trough.pour(_carry)
		_carry -= poured
		w.gathered += poured
	_carry = 0
	_phase = Phase.SEEK


## Los tragos que caben en los odres de su morral.
func capacity() -> int:
	var total := 0
	for item in c.pack.get_all_items():
		var container := item.data.get_trait(WaterContainerTrait) as WaterContainerTrait if item != null else null
		if container != null:
			total += container.capacity * item.quantity
	return total


## Los bebederos de la base (en campo, los de cerca de la zona), del más cercano a él.
func troughs() -> Array[WaterTrough]:
	var home := w.home()
	if not home.is_finite():
		return []
	return WaterTrough.around(c.get_tree(), home, w.chest_reach(), c.global_position)


## El bebedero al que llevar el agua: el que tiene más sitio (y de ellos el más cercano), o null si
## están todos llenos.
func _trough() -> WaterTrough:
	var best: WaterTrough
	for trough in troughs():
		if trough.room() > 0 and (best == null or trough.room() > best.room()):
			best = trough
	return best


## Si hay algún bebedero en la base; si no, parado.
func _has_trough() -> bool:
	if not troughs().is_empty():
		return true
	w.block(c.tr("SETTLER_NO_TROUGH"))
	return false

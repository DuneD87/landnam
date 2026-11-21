class_name SettlerZones extends RefCounted

## Las zonas de trabajo de la base como objetos (se marcan desde el trono, ThroneView): un oficio
## (SettlerWork.Job, y su turno si es la guardia), un círculo y un cupo, cuántos trabajan en ella. No
## hace falta mandar a nadie: cada TICK s, los colonos sin oficio cuya base está a menos de REACH m la
## van llenando hasta el cupo, el más cercano antes; si sobra alguno (se ha bajado el cupo), el más lejano
## lo deja. Quien recibe otra orden en el trono sale de la zona, y otro sin oficio ocupa su sitio.
## Quitar una zona para a los suyos. Una zona de limpiar se quita sola cuando la dejan limpia. Las guarda
## SettlementCompanions con la partida. Ver docs/villagers.md (El trono).

const TICK := 3.0
const REACH := 200.0
const MAX_ZONES := 24
const MAX_QUOTA := 20

## Las zonas: {"id", "job" (SettlerWork.Job), "shift", "at" (marco del terreno), "radius", "quota"}.
var list: Array[Dictionary] = []
var _next := 1
var _tick := 0.0


## Una zona nueva de [job] ([shift]: el turno del guardia) en [at] (marco del terreno), de [radius] m,
## con [quota] puestos. La zona, o {} si ya hay MAX_ZONES.
func add(job: SettlerWork.Job, shift: int, at: Vector3, radius: float, quota: int) -> Dictionary:
	if list.size() >= MAX_ZONES:
		return {}
	var zone := {"id": _next, "job": int(job), "shift": shift, "at": at, "radius": radius,
		"quota": clampi(quota, 1, MAX_QUOTA)}
	_next += 1
	list.append(zone)
	_tick = 0.0
	return zone


func find(id: int) -> Dictionary:
	for zone in list:
		if int(zone.id) == id:
			return zone
	return {}


## Quita la zona [id]: los que trabajaban en ella lo dejan (de [settlers]).
func remove(id: int, settlers: Array[Companion]) -> void:
	for c in members(id, settlers):
		c.work.stop()
		c.work.zone_id = -1
	for i in list.size():
		if int(list[i].id) == id:
			list.remove_at(i)
			return


func set_quota(id: int, quota: int) -> void:
	var zone := find(id)
	if not zone.is_empty():
		zone.quota = clampi(quota, 1, MAX_QUOTA)
		_tick = 0.0


## Los de [settlers] que trabajan en la zona [id].
func members(id: int, settlers: Array[Companion]) -> Array[Companion]:
	var out: Array[Companion] = []
	var zone := find(id)
	for c in settlers:
		if is_instance_valid(c) and not c.dead and c.work.zone_id == id and not zone.is_empty() \
				and int(c.work.job) == int(zone.job):
			out.append(c)
	return out


## Mete a [c] en la zona [id] (con su oficio, su sitio y su turno).
func join(id: int, c: Companion) -> void:
	var zone := find(id)
	if zone.is_empty():
		return
	c.work.assign(int(zone.job) as SettlerWork.Job, zone.at, float(zone.radius), int(zone.shift))
	c.work.zone_id = id


## Cada TICK s: llena o vacía cada zona hasta su cupo con los colonos de [settlers].
func tick(delta: float, settlers: Array[Companion]) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var live: Array[Companion] = []
	for c in settlers:
		if is_instance_valid(c) and not c.dead and c.mode == Companion.Mode.SETTLE:
			live.append(c)
	# Los que van a una zona que ya no existe (o han cambiado de oficio) quedan sueltos.
	for c in live:
		if c.work.zone_id >= 0:
			var zone := find(c.work.zone_id)
			if zone.is_empty() or int(zone.job) != int(c.work.job):
				c.work.zone_id = -1
	for zone in list.duplicate():
		var id := int(zone.id)
		var inside := members(id, live)
		var center: Vector3 = zone.at
		# Limpia del todo: se quita.
		if int(zone.job) == SettlerWork.Job.CLEAR and not inside.is_empty():
			var done := true
			for c in inside:
				done = done and c.work.status == SettlerWork.Status.DONE
			if done:
				remove(id, live)
				continue
		inside.sort_custom(func(a: Companion, b: Companion) -> bool:
			return a.base.distance_to(center) < b.base.distance_to(center))
		while inside.size() > int(zone.quota):
			var out: Companion = inside.pop_back()
			out.work.stop()
			out.work.zone_id = -1
		var want := int(zone.quota) - inside.size()
		if want <= 0:
			continue
		var idle: Array[Companion] = []
		for c in live:
			if c.work.job == SettlerWork.Job.NONE and c.base.is_finite() and c.base.distance_to(center) <= REACH:
				idle.append(c)
		idle.sort_custom(func(a: Companion, b: Companion) -> bool:
			return a.base.distance_to(center) < b.base.distance_to(center))
		for i in mini(want, idle.size()):
			join(id, idle[i])


func save_data() -> Array:
	var out: Array = []
	for zone in list:
		var at: Vector3 = zone.at
		out.append({"id": zone.id, "job": zone.job, "shift": zone.shift, "at": [at.x, at.y, at.z],
			"radius": zone.radius, "quota": zone.quota})
	return out


func restore(data: Array) -> void:
	list.clear()
	_next = 1
	for raw in data:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var at: Array = entry.get("at", [])
		if at.size() != 3:
			continue
		var id := int(entry.get("id", 0))
		list.append({"id": id, "job": int(entry.get("job", 0)), "shift": int(entry.get("shift", 0)),
			"at": Vector3(at[0], at[1], at[2]), "radius": float(entry.get("radius", SettlerWork.WORK_RADIUS)),
			"quota": clampi(int(entry.get("quota", 1)), 1, MAX_QUOTA)})
		_next = maxi(_next, id + 1)

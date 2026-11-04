class_name SettlementSites extends RefCounted

## Dónde puede ir un poblado: en las puntas sueltas de las sendas del mundo (TrailNetwork), las de los
## ramales que se apartan de la red y acaban en un llano y las de la red que no siguen a ninguna parte
## (la punta de un trazo que llega a un cruce queda encima de otro trazo y no cuenta), y a un lado de
## las sendas, cada cierto trecho.

## Una punta es suelta si no hay otro trazo a menos de esto (m).
const END_GAP := 30.0
## Tramo del final del trazo que da la dirección de llegada (m).
const TAIL := 40.0
## Un sitio a un lado de la senda no va a menos de esto (m) de los extremos de su trazo (cruces y
## puntas: las puntas ya tienen el suyo) ni de otro trazo.
const ROAD_END_GAP := 200.0
const ROAD_CROSS_GAP := 60.0


## Las puntas sueltas de [strokes] (polilíneas de direcciones unitarias en un planeta de [radius]):
## [{"dir": la punta, "into": hacia dónde sigue la senda más allá de ella (tangente, unitario)}], en el
## orden de los trazos.
static func dead_ends(strokes: Array, radius: float) -> Array:
	var cell := END_GAP * 2.0 / radius
	var buckets := {}
	for s in strokes.size():
		for p: Vector3 in strokes[s]:
			var key := Vector3i((p / cell).floor())
			if not buckets.has(key):
				buckets[key] = {}
			buckets[key][s] = true
	var limit := END_GAP / radius
	var out: Array = []
	for s in strokes.size():
		var line: PackedVector3Array = strokes[s]
		if line.size() < 2:
			continue
		for tip in [0, line.size() - 1]:
			var p := line[tip]
			if not _alone(p, s, strokes, buckets, cell, limit):
				continue
			# Hacia fuera: de un punto TAIL m atrás a la punta.
			var step := 1 if tip == 0 else -1
			var back := p
			var i: int = tip
			while i + step >= 0 and i + step < line.size() and back.distance_to(p) * radius < TAIL:
				i += step
				back = line[i]
			var into := (p - back).slide(p)
			if into.length_squared() < 1.0e-14:
				continue
			out.append({"dir": p, "into": into.normalized()})
	return out


static func _alone(p: Vector3, own: int, strokes: Array, buckets: Dictionary, cell: float, limit: float) -> bool:
	var key := Vector3i((p / cell).floor())
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				for other: int in buckets.get(key + Vector3i(dx, dy, dz), {}):
					if other == own:
						continue
					for q: Vector3 in strokes[other]:
						if q.distance_to(p) < limit:
							return false
	return true


## Sitios a un lado de las sendas de [strokes]: uno cada [spacing] m de trazo, apartado [setback] m
## del eje, a la derecha o a la izquierda según toque. [{"dir", "into": hacia fuera de la senda, "alt":
## el mismo sitio al otro lado ({"dir", "into"}), por si en este no hay llano}]. Como en una punta, la
## senda llega al poblado por detrás de "into".
static func roadside(strokes: Array, radius: float, spacing: float, setback: float) -> Array:
	var out: Array = []
	if spacing <= 0.0:
		return out
	var cell := ROAD_CROSS_GAP / radius
	var buckets := {}
	for s in strokes.size():
		for p: Vector3 in strokes[s]:
			var key := Vector3i((p / cell).floor())
			if not buckets.has(key):
				buckets[key] = {}
			buckets[key][s] = true
	for s in strokes.size():
		var line: PackedVector3Array = strokes[s]
		var length := 0.0
		for i in range(1, line.size()):
			length += line[i].distance_to(line[i - 1]) * radius
		var next := spacing * 0.5
		var walked := 0.0
		var k := 0
		for i in range(1, line.size() - 1):
			walked += line[i].distance_to(line[i - 1]) * radius
			if walked < next:
				continue
			next += spacing
			k += 1
			if walked < ROAD_END_GAP or length - walked < ROAD_END_GAP:
				continue
			var p := line[i]
			if not _alone(p, s, strokes, buckets, cell, cell):
				continue
			var along := (line[i + 1] - line[i - 1]).slide(p)
			if along.length_squared() < 1.0e-14:
				continue
			var side := p.cross(along).normalized() * (1.0 if (s + k) % 2 == 0 else -1.0)
			out.append({"dir": (p * radius + side * setback).normalized(), "into": side,
				"alt": {"dir": (p * radius - side * setback).normalized(), "into": -side}})
	return out


## El sorteo: los índices de [chances] que salen, cada uno con su probabilidad. Siempre los mismos para
## la misma [seed], y la tirada de un sitio no depende de los de antes (va antes de mirar si tiene
## llano o si queda lejos de los demás).
static func roll(chances: PackedFloat32Array, seed: int) -> PackedInt32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := PackedInt32Array()
	for i in chances.size():
		if rng.randf() < chances[i]:
			out.append(i)
	return out


## Los índices de [candidates] (direcciones unitarias, en orden) que quedan a [spacing] m o más de los
## ya elegidos: los primeros mandan.
static func space(candidates: Array, radius: float, spacing: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var limit := spacing / radius
	for i in candidates.size():
		var p: Vector3 = candidates[i]
		var free := true
		for j in out:
			if (candidates[j] as Vector3).distance_to(p) < limit:
				free = false
				break
		if free:
			out.append(i)
	return out

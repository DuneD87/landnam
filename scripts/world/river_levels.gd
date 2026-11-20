class_name RiverLevels extends RefCounted

## Cota del AGUA de cada tramo de río, medida sobre el terreno real (el generador sin ríos), no sobre
## el mapa de hidrología.
##
## El mapa de hidrología tiene un píxel cada ~90 m y el cauce no pasa por los centros de sus celdas
## (suavizado, meandros, Catmull-Rom): con su cota el agua quedaba metros por encima del terreno real
## en muchos sitios, y el tallado (que solo excava) no podía arreglarlo. Aquí se muestrea la superficie
## en cada nodo del cauce, de orilla a orilla, y el agua va 'bank_height' por debajo del punto más
## bajo. Después:
##   - aguas abajo nunca sube (mínimo con los de aguas arriba): donde el terreno remonta, el río lo
##     atraviesa en garganta;
##   - el corte tiene tope ('level_max_cut'): pasado ese punto el agua se queda más alta y el grafo
##     levanta una ribera bajo ella (relleno), en vez de abrir un cañón de cientos de metros.
## Sustituye seg[4] y seg[5] (antes, cota del lecho) por la cota del agua en cada extremo.

const _OFFSETS := [-1.2, -0.6, 0.0, 0.6, 1.2]


static func resolve(generator: VoxelGeneratorGraph, seg: PackedFloat32Array, hs: Vector2i,
		radius: float, sea_h: float, cfg: Dictionary) -> PackedFloat32Array:
	var count := seg.size() / 8
	if count == 0 or generator == null:
		return seg
	var t0 := Time.get_ticks_msec()
	var bank_h := float(cfg.get("bank_height", 1.5))
	var max_cut := float(cfg.get("level_max_cut", 40.0))

	# Nodos por extremo, con la misma clave que RiverWater.
	var node_of := {}
	var dirs := PackedVector3Array()
	var tang := PackedVector3Array()
	var half := PackedFloat32Array()
	var guess := PackedFloat32Array()
	var ends := PackedInt32Array()
	ends.resize(count * 2)
	for k in count:
		var o := k * 8
		for e in 2:
			var key := Vector2i(roundi(seg[o + e * 2] * 64.0), roundi(seg[o + e * 2 + 1] * 64.0))
			key.x = posmod(key.x, hs.x * 64)
			var id: int = node_of.get(key, -1)
			if id < 0:
				id = dirs.size()
				node_of[key] = id
				dirs.append(RiverField.hydro_dir(seg[o + e * 2], seg[o + e * 2 + 1], hs.x, hs.y))
				tang.append(Vector3.ZERO)
				half.append(0.0)
				guess.append(seg[o + 4 + e])
			ends[k * 2 + e] = id
			half[id] = maxf(half[id], seg[o + 6 + e])
	var n := dirs.size()
	for k in count:
		var a := ends[k * 2]
		var b := ends[k * 2 + 1]
		var d := (dirs[b] - dirs[a]).normalized() * seg[k * 8 + 6]
		tang[a] += d
		tang[b] += d

	# Orden de aguas arriba a aguas abajo (cada tramo va de a, aguas arriba, a b).
	var indeg := PackedInt32Array()
	indeg.resize(n)
	var outs := []
	outs.resize(n)
	for i in n:
		outs[i] = PackedInt32Array()
	for k in count:
		var a := ends[k * 2]
		var b := ends[k * 2 + 1]
		if a == b:
			continue
		outs[a].append(b)
		indeg[b] += 1
	var order := PackedInt32Array()
	for i in n:
		if indeg[i] == 0:
			order.append(i)
	var head := 0
	while head < order.size():
		var i := order[head]
		head += 1
		for b in outs[i]:
			indeg[b] -= 1
			if indeg[b] == 0:
				order.append(b)
	if order.size() < n:
		# Ciclos por claves que coinciden: los que falten se tratan al final, sin orden.
		var seen := PackedByteArray()
		seen.resize(n)
		for i in order:
			seen[i] = 1
		for i in n:
			if seen[i] == 0:
				order.append(i)

	# Encaje en el fondo real del valle: el trazado sale de un mapa de ~90 m por píxel (más el
	# suavizado y los meandros), y en un valle estrecho eso lo deja en la ladera. Cada nodo se mueve
	# en horizontal, perpendicular al cauce, hasta el punto más bajo cerca (con una pequeña
	# preferencia por no moverse), y los desplazamientos se suavizan a lo largo del río.
	var buf := VoxelBuffer.new()
	buf.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)
	buf.create(1, 1, 1)
	var calls := 0
	var sides := PackedVector3Array()
	sides.resize(n)
	for i in n:
		var up := dirs[i]
		var side := tang[i].cross(up)
		if side.length_squared() < 1.0e-12:
			side = up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT)
		sides[i] = side.normalized()
	var snap_reach := float(cfg.get("snap_reach", 40.0))
	var snap_step := float(cfg.get("snap_step", 6.0))
	var snap_cost := float(cfg.get("snap_cost", 0.04))
	var shift := PackedFloat32Array()
	shift.resize(n)
	if snap_reach > 0.0:
		var ups := []
		ups.resize(n)
		for i in n:
			ups[i] = PackedInt32Array()
		for i in n:
			for b in outs[i]:
				ups[b].append(i)
		for i in n:
			var reach := snap_reach + half[i] * 2.0
			var steps := int(ceil(reach / snap_step))
			var best := INF
			var h := guess[i]
			for j in range(-steps, steps + 1):
				var o := j * reach / steps
				var dir := (dirs[i] * radius + sides[i] * o).normalized()
				var r := _surface(generator, buf, dir, radius, h)
				calls += int(r.y)
				h = r.x
				var score := r.x + snap_cost * absf(o)
				if score < best:
					best = score
					shift[i] = o
		for it in 3:
			var nxt := shift.duplicate()
			for i in n:
				var sum := shift[i] * 2.0
				var wsum := 2.0
				for b in outs[i]:
					sum += shift[b]
					wsum += 1.0
				for u in ups[i]:
					sum += shift[u]
					wsum += 1.0
				nxt[i] = sum / wsum
			shift = nxt
		for i in n:
			dirs[i] = (dirs[i] * radius + sides[i] * shift[i]).normalized()
		# Extremos de los tramos a la nueva posición (coordenadas de téxel de hidrología).
		for k in count:
			var o := k * 8
			for e in 2:
				var d := dirs[ends[k * 2 + e]]
				var px := fposmod(atan2(-d.z, d.x) / TAU + 0.5, 1.0) * hs.x
				var py := acos(clampf(d.y, -1.0, 1.0)) / PI * hs.y
				# Mismo lado de la costura que el valor original, que es lo que usa el pintado.
				px += roundf((seg[o + e * 2] - px) / hs.x) * hs.x
				seg[o + e * 2] = px
				seg[o + e * 2 + 1] = py
	var shifts := shift.duplicate()
	for i in n:
		shifts[i] = absf(shifts[i])
	shifts.sort()
	print("[rivers] encaje en el fondo del valle: desplazamiento p50 %.0f p90 %.0f máx %.0f m" % [
		shifts[n / 2], shifts[n * 9 / 10], shifts[n - 1]])

	# Terreno más bajo de orilla a orilla (un poco más allá del borde, para que la ribera también
	# quede por encima del agua).
	var tmin := PackedFloat32Array()
	tmin.resize(n)
	for i in n:
		var up := dirs[i]
		var side := sides[i]
		var m := INF
		var h := guess[i]
		for s: float in _OFFSETS:
			var dir := (up * radius + side * (s * half[i])).normalized()
			var r := _surface(generator, buf, dir, radius, h)
			calls += int(r.y)
			m = minf(m, r.x)
		tmin[i] = m

	var dem_err := PackedFloat32Array()
	for i in n:
		dem_err.append(tmin[i] - guess[i])
	dem_err.sort()
	print("[rivers] terreno real - lecho viejo: p1 %.1f p10 %.1f p50 %.1f p90 %.1f p99 %.1f m" % [
		dem_err[n / 100], dem_err[n / 10], dem_err[n / 2], dem_err[n * 9 / 10], dem_err[n * 99 / 100]])

	var level := PackedFloat32Array()
	level.resize(n)
	for i in n:
		level[i] = tmin[i] - bank_h
	for i in order:
		for b in outs[i]:
			level[b] = minf(level[b], level[i])
	var cut := PackedFloat32Array()
	for i in n:
		cut.append(tmin[i] - bank_h - level[i])
	cut.sort()
	print("[rivers] corte sobre terreno real (sin tope): p50 %.1f p90 %.1f p99 %.1f máx %.1f m" % [
		cut[n / 2], cut[n * 9 / 10], cut[n * 99 / 100], cut[n - 1]])
	# Tope del corte, propagado aguas arriba para que siga sin subir. Sin suelo en el mar: bajo él el
	# cauce sigue tallando el fondo y la lámina no se dibuja (la cubre el océano).
	var raised := 0
	var max_raise := 0.0
	for idx in range(order.size() - 1, -1, -1):
		var i := order[idx]
		var want := tmin[i] - bank_h - max_cut
		for b in outs[i]:
			want = maxf(want, level[b])
		if want > level[i]:
			level[i] = want
		var over := level[i] - (tmin[i] - bank_h)
		if over > 0.5:
			raised += 1
			max_raise = maxf(max_raise, over)

	# Pendiente máxima del agua: sin esto el nivel se queda plano mientras el terreno remonta y luego
	# cae de golpe donde el terreno vuelve a bajar (rampas de agua). Solo se BAJA el nivel aguas arriba
	# de cada caída (el cauce se talla un poco más), así que sigue sin flotar. Los ríos anchos van más
	# tendidos que los arroyos. Hacia el mar la rampa termina en su nivel, no en el fondo marino.
	var slope_k := float(cfg.get("water_slope_k", 0.8))
	var slope_lo := float(cfg.get("water_slope_min", 0.02))
	var slope_hi := float(cfg.get("water_slope_max", 0.10))
	# Tope de lo que se baja cada nodo: un río de montaña con más pendiente media que el límite no se
	# entierra (rápidos), solo se reparten los escalones.
	var max_lower := float(cfg.get("water_max_lower", 15.0))
	var env := level.duplicate()
	var lowered := PackedFloat32Array()
	lowered.resize(n)
	for idx in range(order.size() - 1, -1, -1):
		var i := order[idx]
		var s_max := clampf(slope_k / maxf(half[i], 1.0), slope_lo, slope_hi)
		for b in outs[i]:
			var lim := maxf(level[b], sea_h - 1.0) + s_max * (dirs[b] - dirs[i]).length() * radius
			lim = maxf(lim, env[i] - max_lower)
			if level[i] > lim:
				level[i] = lim
		lowered[i] = env[i] - level[i]
	var low_sorted := lowered.duplicate()
	low_sorted.sort()
	print("[rivers] pendiente del agua limitada: bajada extra p50 %.1f p90 %.1f p99 %.1f máx %.1f m" % [
		low_sorted[n / 2], low_sorted[n * 9 / 10], low_sorted[n * 99 / 100], low_sorted[n - 1]])

	var diffs := PackedFloat32Array()
	for k in count:
		var o := k * 8
		var a := ends[k * 2]
		var b := ends[k * 2 + 1]
		diffs.append(level[a] - seg[o + 4])
		seg[o + 4] = level[a]
		seg[o + 5] = level[b]
	diffs.sort()
	var m2 := diffs.size()
	var slopes := PackedFloat32Array()
	for k in count:
		var o := k * 8
		var len_m := (dirs[ends[k * 2 + 1]] - dirs[ends[k * 2]]).length() * radius
		slopes.append((seg[o + 4] - seg[o + 5]) / maxf(len_m, 1.0))
	slopes.sort()
	print("[rivers] pendiente del agua por tramo: p50 %.3f p90 %.3f p99 %.3f máx %.3f" % [
		slopes[m2 / 2], slopes[m2 * 9 / 10], slopes[m2 * 99 / 100], slopes[m2 - 1]])
	print(("[rivers] cota del agua sobre terreno real: %d nodos, %d muestras en %.1f s; respecto al " +
		"lecho viejo p10 %.1f p50 %.1f p90 %.1f m; %d nodos con ribera levantada (máx %.1f m)") % [n,
		calls, (Time.get_ticks_msec() - t0) / 1000.0, diffs[m2 / 10], diffs[m2 / 2], diffs[m2 * 9 / 10],
		raised, max_raise])
	return seg


## Altura de la superficie sobre 'radius' en 'dir' (Newton sobre la SDF, que es casi una distancia
## en vertical). Devuelve (altura, llamadas al generador).
static func _surface(generator: VoxelGeneratorGraph, buf: VoxelBuffer, dir: Vector3, radius: float,
		h0: float) -> Vector2:
	var h := h0
	var calls := 0
	for it in 8:
		var p := dir * (radius + h)
		var c := Vector3i(p.round())
		generator.generate_block(buf, c, 0)
		calls += 1
		var s := buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)
		# El punto redondeado no es el pedido: se corrige por lo que se ha movido en vertical.
		s -= (Vector3(c) - p).dot(dir)
		h -= clampf(s, -200.0, 200.0)
		if absf(s) < 0.2:
			break
	return Vector2(h, calls)

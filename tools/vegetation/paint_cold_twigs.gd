extends SceneTree

## Pinta las texturas de ramita de los árboles fríos, que no tienen foto de partida como las demás:
##   twig_spruce.png  rama pinnada de picea: brotes alternos cubiertos de acículas cortas,
##                    verde azulado oscuro con los brotes nuevos más claros.
##   twig_birch.png   ramillas finas de abedul con hojas ovadas y dentadas en otoño boreal
##                    (amarillo dorado, algo de verde lima y naranja).
## Mismo encuadre que las fotos (tallo abajo en el centro, abanico hacia arriba) para que el
## generador Branching las oriente igual. Después hay que rellenar el color de las zonas
## transparentes: python3 tools/vegetation/fill_transparent_color.py (ver docs/trees.md).
##   godot --path . -s res://tools/vegetation/paint_cold_twigs.gd

const SIZE := 2048
const OUT_DIR := "res://textures/planet/vegetation/tree/twigs/"


class Painter extends Node2D:
	var kind := "spruce"
	var rng := RandomNumberGenerator.new()

	func _draw() -> void:
		rng.seed = 4101 if kind == "spruce" else 7717
		if kind == "spruce":
			_spruce()
		else:
			_birch()

	func _spruce() -> void:
		var base := Vector2(SIZE * 0.5, SIZE * 0.985)
		var tip := Vector2(SIZE * 0.52, SIZE * 0.05)
		# Brotes laterales primero, el eje encima.
		var shoots := 16
		for i in shoots:
			var t := 0.10 + 0.86 * float(i) / (shoots - 1)
			var origin := base.lerp(tip, t)
			var side := -1.0 if i % 2 == 0 else 1.0
			var length := SIZE * lerpf(0.50, 0.18, t) * rng.randf_range(0.88, 1.1)
			var angle := deg_to_rad(side * rng.randf_range(52.0, 66.0))
			var dir := Vector2(sin(angle), -cos(angle))
			var end := origin + dir * length
			var bend := dir.orthogonal() * side * length * rng.randf_range(-0.08, 0.04)
			_needled_shoot(origin, origin.lerp(end, 0.5) + bend, end, lerpf(16.0, 8.0, t), 1.0 - t * 0.3)
			# Brotes de segundo orden, cortos, a los dos lados del brote.
			for j in 6:
				var u := 0.18 + 0.13 * j
				var o2 := _bezier(origin, origin.lerp(end, 0.5) + bend, end, u)
				var a2 := angle + side * deg_to_rad(rng.randf_range(35.0, 50.0)) * (1.0 if j % 2 == 0 else -1.0)
				var d2 := Vector2(sin(a2), -cos(a2))
				var l2 := length * rng.randf_range(0.26, 0.38) * (1.0 - u * 0.5)
				_needled_shoot(o2, o2 + d2 * l2 * 0.5, o2 + d2 * l2, 5.0, 0.8)
		_needled_shoot(base, base.lerp(tip, 0.5) + Vector2(SIZE * 0.015, 0), tip, 22.0, 1.0)

	## Brote cubierto de acículas cortas a ambos lados y por encima (vistas en proyección).
	func _needled_shoot(a: Vector2, c: Vector2, b: Vector2, width: float, vigor: float) -> void:
		var bark := Color(0.42, 0.26, 0.15)
		var steps := 24
		var prev := a
		for s in range(1, steps + 1):
			var p := _bezier(a, c, b, float(s) / steps)
			draw_line(prev, p, bark.darkened(0.15), width * lerpf(1.0, 0.45, float(s) / steps), true)
			prev = p
		var length_px := a.distance_to(b) + 1.0
		var count := int(length_px / 1.9)
		var dark := Color(0.10, 0.20, 0.15)
		var mid := Color(0.16, 0.30, 0.20)
		var fresh := Color(0.36, 0.52, 0.28)
		for n in count:
			var t := rng.randf()
			var p := _bezier(a, c, b, t)
			var tangent := (_bezier(a, c, b, minf(t + 0.01, 1.0)) - _bezier(a, c, b, maxf(t - 0.01, 0.0))).normalized()
			var side := -1.0 if n % 2 == 0 else 1.0
			# Las del centro apuntan hacia delante (tapan el eje); las laterales se abren.
			var spread := deg_to_rad(rng.randf_range(20.0, 75.0)) * side
			if rng.randf() < 0.25:
				spread *= 0.3
			var dir := tangent.rotated(spread)
			var needle := rng.randf_range(44.0, 66.0) * lerpf(0.8, 1.05, vigor)
			var color := dark.lerp(mid, rng.randf())
			# Brotes del año en la punta: verde claro.
			color = color.lerp(fresh, smoothstep(0.78, 0.98, t) * rng.randf_range(0.5, 1.0))
			color = color.lightened(rng.randf_range(-0.04, 0.08))
			var root := p + tangent.orthogonal() * side * rng.randf_range(0.0, 3.0)
			draw_line(root, root + dir * needle, color, rng.randf_range(4.8, 6.6), true)
			# Brillo en el haz de algunas acículas.
			if rng.randf() < 0.3:
				draw_line(root + dir * needle * 0.2, root + dir * needle * 0.8, color.lightened(0.18), 1.2, true)

	func _birch() -> void:
		var twig := Color(0.30, 0.17, 0.12)
		var base := Vector2(SIZE * 0.5, SIZE * 0.99)
		var fork := Vector2(SIZE * 0.5, SIZE * 0.80)
		_stroke(base, base.lerp(fork, 0.5), fork, 18.0, 12.0, twig)
		var tips: Array[Array] = []
		for i in 9:
			var angle := deg_to_rad(lerpf(-62.0, 62.0, float(i) / 8.0) + rng.randf_range(-6.0, 6.0))
			var dir := Vector2(sin(angle), -cos(angle))
			var length := SIZE * rng.randf_range(0.46, 0.62) * (1.0 - absf(angle) * 0.25)
			var start := fork + Vector2(0, -rng.randf_range(0.0, 0.18)) * SIZE * (absf(angle) / 1.0)
			var end := start + dir * length + Vector2(0, length * 0.18 * absf(sin(angle)))
			var ctrl: Vector2 = start.lerp(end, 0.5) - dir.orthogonal() * signf(angle) * length * 0.12
			_stroke(start, ctrl, end, 9.0, 3.0, twig.lightened(0.05))
			tips.append([start, ctrl, end])
		# Hojas a lo largo de cada ramilla, alternas, algo colgantes; de las puntas a la base.
		var palette := [Color(0.93, 0.74, 0.18), Color(0.88, 0.62, 0.12), Color(0.97, 0.83, 0.30),
			Color(0.70, 0.72, 0.22), Color(0.90, 0.52, 0.12)]
		for spec in tips:
			var leaves := 22
			for k in leaves:
				var t := 0.2 + 0.8 * float(k) / (leaves - 1)
				var p := _bezier(spec[0], spec[1], spec[2], t)
				var tangent := (_bezier(spec[0], spec[1], spec[2], minf(t + 0.01, 1.0)) - p).normalized()
				var side := -1.0 if k % 2 == 0 else 1.0
				var dir := tangent.rotated(side * deg_to_rad(rng.randf_range(35.0, 70.0)))
				dir = (dir + Vector2(0, 0.35)).normalized()
				var size := rng.randf_range(80.0, 118.0) * lerpf(0.8, 1.0, t)
				var color: Color = palette[rng.randi() % palette.size()]
				color = color.lightened(rng.randf_range(-0.08, 0.06))
				var petiole := p + dir * size * 0.28
				draw_line(p, petiole, twig.lightened(0.2), 3.0, true)
				_leaf(petiole, dir, size, color)

	## Hoja ovada-triangular con el borde dentado y el nervio central.
	func _leaf(root: Vector2, dir: Vector2, size: float, color: Color) -> void:
		var side_axis := dir.orthogonal()
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		var teeth := 14
		for i in range(teeth + 1):
			var t := float(i) / teeth
			# Perfil: ancho en la base, punta aguda (abedul).
			var half_width := size * 0.42 * pow(sin(PI * pow(t, 0.62)), 1.1) * (1.0 - t * 0.15)
			var tooth := 1.0 + (0.06 if i % 2 == 0 else -0.02)
			points.append(root + dir * size * t + side_axis * half_width * tooth)
		for i in range(teeth - 1, 0, -1):
			var t := float(i) / teeth
			var half_width := size * 0.42 * pow(sin(PI * pow(t, 0.62)), 1.1) * (1.0 - t * 0.15)
			var tooth := 1.0 + (0.06 if i % 2 == 0 else -0.02)
			points.append(root + dir * size * t - side_axis * half_width * tooth)
		for i in points.size():
			colors.append(color.darkened(0.08) if i < points.size() / 2 else color.lightened(0.04))
		draw_polygon(points, colors)
		draw_polyline(points + PackedVector2Array([points[0]]), color.darkened(0.25), 1.5, true)
		draw_line(root, root + dir * size * 0.92, color.darkened(0.22), 2.0, true)
		for v in 4:
			var t := 0.25 + v * 0.17
			var o := root + dir * size * t
			for s in [-1.0, 1.0]:
				draw_line(o, o + (dir * 0.6 + side_axis * s).normalized() * size * 0.2, color.darkened(0.14), 1.2, true)

	func _stroke(a: Vector2, c: Vector2, b: Vector2, w0: float, w1: float, color: Color) -> void:
		var prev := a
		for s in range(1, 21):
			var t := float(s) / 20.0
			var p := _bezier(a, c, b, t)
			draw_line(prev, p, color.lightened(t * 0.1), lerpf(w0, w1, t), true)
			prev = p

	func _bezier(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
		return a.lerp(c, t).lerp(c.lerp(b, t), t)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for kind in ["spruce", "birch"]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(SIZE, SIZE)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		root.add_child(viewport)
		var painter := Painter.new()
		painter.kind = kind
		viewport.add_child(painter)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var path := OUT_DIR + "twig_%s.png" % kind
		image.save_png(path)
		print("TWIG ", path)
		viewport.queue_free()
	quit()

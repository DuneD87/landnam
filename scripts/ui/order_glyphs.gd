class_name OrderGlyphs
extends RefCounted

## Los dibujos de las órdenes (la rueda del grupo, GroupOrderWheel) y de los oficios de los colonos
## (el trono, ThroneView; SettlerOrders): trazos sencillos en un cuadrado, sobre cualquier CanvasItem
## (su RID). Para usarlos de icono en un botón o un TextureRect, GlyphTexture.


## Dibuja [key] en un cuadrado de [size] centrado en [at], del color [color], en [ci].
static func draw(ci: RID, key: StringName, at: Vector2, size: float, color: Color) -> void:
	var w := maxf(2.0, size * 0.07)
	var h := size * 0.32
	match key:
		&"follow":
			# Una flecha hacia arriba con dos puntos detrás: los que siguen.
			arrow(ci, at + Vector2(0, h * 0.5), at + Vector2(0, -h), color, w)
			for side in [-1.0, 1.0]:
				_dot(ci, at + Vector2(side * h * 0.8, h * 0.8), w * 1.1, color)
		&"wait":
			# Una mano en alto: un palmo y cuatro dedos.
			_line(ci, at + Vector2(-h * 0.7, h), at + Vector2(h * 0.7, h), color, w)
			for k in 4:
				var x := lerpf(-h * 0.6, h * 0.6, k / 3.0)
				var top := -h * (0.95 if k == 1 or k == 2 else 0.7)
				_line(ci, at + Vector2(x, h), at + Vector2(x, top), color, w)
		&"attack":
			# Dos hojas cruzadas.
			_line(ci, at + Vector2(-h, h), at + Vector2(h, -h), color, w)
			_line(ci, at + Vector2(h, h), at + Vector2(-h, -h), color, w)
			for side in [-1.0, 1.0]:
				var hilt := at + Vector2(side * h * 0.55, h * 0.55)
				var across := Vector2(side, 1.0).normalized() * h * 0.3
				_line(ci, hilt - Vector2(across.x, -across.y), hilt + Vector2(across.x, -across.y), color, w * 0.8)
		&"retreat":
			# Una flecha que da la vuelta.
			var center := at + Vector2(0, -h * 0.1)
			_arc(ci, center, h * 0.75, -PI * 0.5, PI * 0.75, color, w)
			var tip := center + Vector2(cos(PI * 0.75), sin(PI * 0.75)) * h * 0.75
			_line(ci, tip, tip + Vector2(h * 0.55, -h * 0.05), color, w)
			_line(ci, tip, tip + Vector2(-h * 0.1, -h * 0.55), color, w)
		&"home":
			# Una casa: el tejado y las paredes.
			_poly(ci, [at + Vector2(-h, -h * 0.1), at + Vector2(0, -h), at + Vector2(h, -h * 0.1)], color, w)
			_poly(ci, [at + Vector2(-h * 0.7, -h * 0.1), at + Vector2(-h * 0.7, h), at + Vector2(h * 0.7, h),
				at + Vector2(h * 0.7, -h * 0.1)], color, w)
		&"board":
			# Una bancada con su remo: el tablón, las patas y el remo cruzado con su pala.
			_line(ci, at + Vector2(-h, h * 0.05), at + Vector2(h, h * 0.05), color, w * 1.2)
			for side in [-1.0, 1.0]:
				_line(ci, at + Vector2(side * h * 0.65, h * 0.05), at + Vector2(side * h * 0.65, h), color, w)
			_line(ci, at + Vector2(-h * 0.9, -h), at + Vector2(h * 0.55, h * 0.55), color, w * 0.8)
			_fill(ci, [at + Vector2(h * 0.4, h * 0.35), at + Vector2(h * 1.0, h * 0.8), at + Vector2(h * 0.85, h * 1.05),
				at + Vector2(h * 0.3, h * 0.7)], color)
		&"goto":
			# Un banderín clavado en el suelo: el mástil, la bandera y la marca en el suelo.
			_line(ci, at + Vector2(-h * 0.35, h * 0.75), at + Vector2(-h * 0.35, -h), color, w)
			_fill(ci, [at + Vector2(-h * 0.35, -h), at + Vector2(h * 0.75, -h * 0.6), at + Vector2(-h * 0.35, -h * 0.2)],
				color)
			var ground: Array = []
			for k in 17:
				var t := TAU * k / 16.0
				ground.append(at + Vector2(-h * 0.35 + cos(t) * h * 0.8, h * 0.75 + sin(t) * h * 0.25))
			_poly(ci, ground, color, w * 0.8)
		&"formation", &"wedge":
			# La cuña: uno delante y dos filas detrás.
			_dot(ci, at + Vector2(0, -h * 0.9), w * 1.3, color)
			for row in [1, 2]:
				for side in [-1.0, 1.0]:
					_dot(ci, at + Vector2(side * h * 0.5 * row, -h * 0.9 + h * 0.85 * row), w * 1.1, color)
		&"file":
			# La fila: uno detrás de otro.
			for k in 4:
				_dot(ci, at + Vector2(0, lerpf(-h * 0.9, h * 0.9, k / 3.0)), w * (1.3 if k == 0 else 1.1), color)
		&"loose":
			# Sueltos: puntos desperdigados.
			for p: Vector2 in [Vector2(-0.7, -0.6), Vector2(0.45, -0.85), Vector2(0.05, -0.05), Vector2(0.8, 0.35),
					Vector2(-0.6, 0.75), Vector2(0.3, 0.9)]:
				_dot(ci, at + p * h, w * 1.1, color)
		&"work":
			# Un hacha y un pico cruzados: los mangos en aspa, la hoja arriba a la derecha y la cabeza del
			# pico arriba a la izquierda.
			_line(ci, at + Vector2(-h * 0.8, h), at + Vector2(h * 0.6, -h * 0.75), color, w)
			_line(ci, at + Vector2(h * 0.8, h), at + Vector2(-h * 0.6, -h * 0.75), color, w)
			_fill(ci, [at + Vector2(h * 0.45, -h * 0.95), at + Vector2(h * 1.05, -h * 0.6), at + Vector2(h * 0.75, -h * 0.15),
				at + Vector2(h * 0.35, -h * 0.5)], color)
			_poly(ci, [at + Vector2(-h * 1.05, -h * 0.25), at + Vector2(-h * 0.85, -h * 0.8), at + Vector2(-h * 0.35, -h * 1.0)],
				color, w * 1.2)
		&"fell":
			# Un hacha: el mango y la hoja que se abre hacia el filo.
			_line(ci, at + Vector2(h * 0.25, h), at + Vector2(h * 0.25, -h), color, w)
			_fill(ci, [at + Vector2(h * 0.25, -h * 0.9), at + Vector2(-h * 0.8, -h * 1.05), at + Vector2(-h * 0.8, -h * 0.05),
				at + Vector2(h * 0.25, -h * 0.35)], color)
		&"mine":
			# Un pico: el mango y la cabeza curva.
			_line(ci, at + Vector2(0, h), at + Vector2(0, -h * 0.65), color, w)
			_poly(ci, [at + Vector2(-h, -h * 0.1), at + Vector2(-h * 0.55, -h * 0.6), at + Vector2(0, -h * 0.75),
				at + Vector2(h * 0.55, -h * 0.6), at + Vector2(h, -h * 0.1)], color, w * 1.3)
		&"clear":
			# Una escoba: el palo, la atadura y las cerdas abiertas.
			var base := at + Vector2(-h * 0.15, h * 0.3)
			_line(ci, at + Vector2(h * 0.7, -h), base, color, w)
			for k in 4:
				_line(ci, base, at + Vector2(lerpf(-h, h * 0.2, k / 3.0), h), color, w * 0.8)
			_line(ci, base + Vector2(-h * 0.3, -h * 0.05), base + Vector2(h * 0.2, h * 0.15), color, w)
		&"build":
			# Un mazo: el mango y la cabeza.
			_line(ci, at + Vector2(0, h), at + Vector2(0, -h * 0.4), color, w)
			_fill(ci, [at + Vector2(-h * 0.75, -h), at + Vector2(h * 0.75, -h), at + Vector2(h * 0.75, -h * 0.4),
				at + Vector2(-h * 0.75, -h * 0.4)], color)
		&"hunt":
			# Un arco tensado con su flecha.
			var center := at + Vector2(-h * 0.15, 0)
			_arc(ci, center, h, -PI * 0.36, PI * 0.36, color, w)
			var nock := at + Vector2(-h * 0.55, 0)
			for side in [-1.0, 1.0]:
				_line(ci, center + Vector2(cos(PI * 0.36), side * sin(PI * 0.36)) * Vector2(h, h), nock, color, w * 0.5)
			arrow(ci, nock, at + Vector2(h * 1.05, 0), color, w * 0.8)
		&"fish":
			# Un pez: el cuerpo, la cola y el ojo.
			var points: Array = []
			for k in 25:
				var a := TAU * k / 24.0
				points.append(at + Vector2(-h * 0.15 + cos(a) * h * 0.75, sin(a) * h * 0.42))
			_poly(ci, points, color, w)
			_poly(ci, [at + Vector2(h * 0.55, 0), at + Vector2(h, -h * 0.45), at + Vector2(h, h * 0.45),
				at + Vector2(h * 0.55, 0)], color, w)
			_dot(ci, at + Vector2(-h * 0.55, -h * 0.08), w * 0.8, color)
		&"cook":
			# Una llama sobre dos leños cruzados.
			_line(ci, at + Vector2(-h * 0.85, h), at + Vector2(h * 0.85, h * 0.55), color, w)
			_line(ci, at + Vector2(h * 0.85, h), at + Vector2(-h * 0.85, h * 0.55), color, w)
			_fill(ci, [at + Vector2(0, -h), at + Vector2(h * 0.35, -h * 0.4), at + Vector2(h * 0.5, h * 0.05),
				at + Vector2(h * 0.25, h * 0.4), at + Vector2(-h * 0.25, h * 0.4), at + Vector2(-h * 0.5, h * 0.05),
				at + Vector2(-h * 0.35, -h * 0.4)], color)
		&"guard", &"guard_day", &"guard_night":
			# Un escudo; de día con un sol y de noche con una luna.
			_poly(ci, [at + Vector2(-h * 0.75, -h * 0.85), at + Vector2(h * 0.75, -h * 0.85), at + Vector2(h * 0.75, 0),
				at + Vector2(0, h), at + Vector2(-h * 0.75, 0), at + Vector2(-h * 0.75, -h * 0.85)], color, w)
			var mark := at + Vector2(0, -h * 0.25)
			if key == &"guard_day":
				_dot(ci, mark, h * 0.24, color)
			elif key == &"guard_night":
				_arc(ci, mark, h * 0.26, PI * 0.35, PI * 1.65, color, w)
		&"stop":
			# Un círculo tachado.
			_arc(ci, at, h * 0.9, 0.0, TAU, color, w)
			_line(ci, at + Vector2(-h * 0.62, -h * 0.62), at + Vector2(h * 0.62, h * 0.62), color, w)
		&"idle":
			# Tres puntos: nada que hacer.
			for k in 3:
				_dot(ci, at + Vector2((k - 1) * h * 0.65, h * 0.3), w * 0.9, color)


static func arrow(ci: RID, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	_line(ci, from, to, color, width)
	var back := (from - to).normalized() * width * 4.0
	_line(ci, to, to + back.rotated(0.6), color, width)
	_line(ci, to, to + back.rotated(-0.6), color, width)


static func _line(ci: RID, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	RenderingServer.canvas_item_add_line(ci, from, to, color, width, true)


static func _poly(ci: RID, points: Array, color: Color, width: float) -> void:
	RenderingServer.canvas_item_add_polyline(ci, PackedVector2Array(points), PackedColorArray([color]), width, true)


static func _fill(ci: RID, points: Array, color: Color) -> void:
	RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array(points), PackedColorArray([color]))


static func _dot(ci: RID, at: Vector2, radius: float, color: Color) -> void:
	RenderingServer.canvas_item_add_circle(ci, at, radius, color, true)


## Un arco de [a0] a [a1] (radianes desde +x, en el sentido de las agujas en pantalla).
static func _arc(ci: RID, center: Vector2, radius: float, a0: float, a1: float, color: Color, width: float) -> void:
	var points: Array = []
	var steps := maxi(6, ceili(absf(a1 - a0) / TAU * 32.0))
	for k in steps + 1:
		var a := lerpf(a0, a1, float(k) / steps)
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	_poly(ci, points, color, width)

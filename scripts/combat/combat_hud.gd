class_name CombatHUD
extends CanvasLayer

## Interfaz de combate: vida y aguante arriba a la izquierda (con el tramo perdido que se vacía
## con retraso, como en los souls), marca del objetivo fijado, barras de vida sobre los enemigos
## tocados, mira al apuntar con la tensión y la munición, destello rojo al recibir, la pantalla
## de muerte y los fundidos a negro de la reaparición.
##
## La UI del proyecto no se estira: todo se escala por la altura de la ventana (base 1440).

const HP_COLOR := Color(0.62, 0.08, 0.07)
const HP_TRAIL := Color(0.86, 0.66, 0.30)
const ST_COLOR := Color(0.28, 0.55, 0.22)
const FRAME := Color(0.03, 0.03, 0.03, 0.78)
const BAR_BACK := Color(0.10, 0.09, 0.08, 0.7)
## Segundos que se ve la barra de una criatura después de golpearla.
const ENEMY_BAR_TIME := 6.0

var combat: PlayerCombat
var _canvas: Control
var _vignette: TextureRect
var _fade: ColorRect
var _death_band: TextureRect
var _death_label: Label
var _ammo_label: Label

var _scale: float = 1.0
var _hp_trail: float = 1.0
var _hp_trail_hold: float = 0.0
var _st_flash: float = 0.0
var _damage_flash: float = 0.0
var _enemy_seen: Dictionary = {}
var _enemy_trail: Dictionary = {}
var _death_shown: bool = false


func setup(owner_combat: PlayerCombat) -> void:
	combat = owner_combat
	layer = 12
	_scale = 1.0
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)

	_vignette = TextureRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := Gradient.new()
	grad.set_color(0, Color(0.5, 0.0, 0.0, 0.0))
	grad.set_color(1, Color(0.55, 0.0, 0.0, 0.85))
	grad.add_point(0.55, Color(0.5, 0.0, 0.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 256
	tex.height = 256
	_vignette.texture = tex
	_vignette.modulate.a = 0.0
	add_child(_vignette)

	_ammo_label = Label.new()
	_ammo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo_label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80))
	_ammo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_ammo_label.add_theme_constant_override("outline_size", 6)
	_ammo_label.visible = false
	add_child(_ammo_label)

	_death_band = TextureRect.new()
	_death_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_death_band.stretch_mode = TextureRect.STRETCH_SCALE
	var band := Gradient.new()
	band.set_color(0, Color(0, 0, 0, 0.0))
	band.set_color(1, Color(0, 0, 0, 0.0))
	band.add_point(0.5, Color(0, 0, 0, 0.82))
	var band_tex := GradientTexture2D.new()
	band_tex.gradient = band
	band_tex.fill_from = Vector2(0.5, 0.0)
	band_tex.fill_to = Vector2(0.5, 1.0)
	band_tex.width = 8
	band_tex.height = 128
	_death_band.texture = band_tex
	_death_band.modulate.a = 0.0
	_death_band.visible = false
	add_child(_death_band)

	_death_label = Label.new()
	_death_label.text = "HAS MUERTO"
	_death_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Cormorant Garamond", "Georgia",
		"DejaVu Serif", "Liberation Serif", "Times New Roman", "serif"])
	font.font_weight = 500
	_death_label.add_theme_font_override("font", font)
	_death_label.add_theme_color_override("font_color", Color(0.58, 0.06, 0.05))
	_death_label.add_theme_color_override("font_outline_color", Color(0.05, 0.0, 0.0, 0.9))
	_death_label.add_theme_constant_override("outline_size", 4)
	_death_label.modulate.a = 0.0
	_death_label.visible = false
	add_child(_death_label)

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_fade.visible = false
	add_child(_fade)
	_relayout()
	get_viewport().size_changed.connect(_relayout)


func _relayout() -> void:
	var size := get_viewport().get_visible_rect().size
	_scale = clampf(size.y / 1440.0, 0.5, 2.0)
	_vignette.size = size
	_fade.size = size
	var band_h := 260.0 * _scale
	_death_band.position = Vector2(0, size.y * 0.5 - band_h * 0.5)
	_death_band.size = Vector2(size.x, band_h)
	_death_label.position = _death_band.position
	_death_label.size = _death_band.size
	_death_label.add_theme_font_size_override("font_size", int(150 * _scale))
	_ammo_label.add_theme_font_size_override("font_size", int(26 * _scale))


func _process(delta: float) -> void:
	if combat == null or combat.player == null:
		return
	# Tramo perdido: espera un momento y luego se vacía hasta la vida real.
	var health := combat.player.health_component
	var ratio := health.get_health_ratio()
	if ratio >= _hp_trail:
		_hp_trail = ratio
		_hp_trail_hold = 0.0
	else:
		_hp_trail_hold += delta
		if _hp_trail_hold > 0.7:
			_hp_trail = move_toward(_hp_trail, ratio, delta * 0.6)
	for npc in _enemy_trail.keys():
		if not is_instance_valid(npc):
			_enemy_trail.erase(npc)
			_enemy_seen.erase(npc)
			continue
		var r: float = (npc as NPCController).health_component.get_health_ratio()
		_enemy_trail[npc] = move_toward(_enemy_trail[npc], r, delta * 0.5) if _enemy_trail[npc] > r else r
		_enemy_seen[npc] = float(_enemy_seen[npc]) + delta
		if _enemy_seen[npc] > ENEMY_BAR_TIME and npc != combat.lock_target:
			_enemy_seen.erase(npc)
			_enemy_trail.erase(npc)
	# Un objetivo liberado compara igual a null: hay que mirar is_instance_valid antes que nada.
	if not is_instance_valid(combat.lock_target):
		if combat.lock_target != null or combat.player.camera_controller.lock_point != null:
			combat.release_lock()
	elif combat.lock_target is NPCController and not _enemy_trail.has(combat.lock_target):
		_enemy_trail[combat.lock_target] = (combat.lock_target as NPCController).health_component.get_health_ratio()
		_enemy_seen[combat.lock_target] = 0.0
	_st_flash = maxf(0.0, _st_flash - delta * 2.5)
	_damage_flash = maxf(0.0, _damage_flash - delta * 1.8)
	_vignette.modulate.a = _damage_flash
	_update_ammo()
	_canvas.queue_redraw()


func _update_ammo() -> void:
	var data := combat.weapon()
	var aiming := combat.state == PlayerCombat.State.AIM
	if data == null or not data.is_ranged() or not aiming:
		_ammo_label.visible = false
		return
	var count := combat.ammo_count()
	var label := "Flechas" if data.weapon_type == ItemData.WeaponType.BOW else \
		("Piedras" if data.weapon_type == ItemData.WeaponType.SLINGSHOT else "Lanzas")
	_ammo_label.text = "%s  %d" % [label, count] if count > 0 else "Sin %s" % label.to_lower()
	var center := get_viewport().get_visible_rect().size * 0.5
	_ammo_label.position = center + Vector2(46, 30) * _scale
	_ammo_label.visible = true
	_ammo_label.modulate = Color(1, 0.55, 0.5) if count == 0 else Color.WHITE


func note_enemy_hit(body: Node) -> void:
	var npc := body as NPCController
	if npc == null or npc.health_component == null:
		return
	if not _enemy_trail.has(npc):
		_enemy_trail[npc] = minf(1.0, npc.health_component.get_health_ratio() + 0.2)
	_enemy_seen[npc] = 0.0


func flash_damage(strength: float) -> void:
	_damage_flash = maxf(_damage_flash, clampf(strength, 0.0, 1.0))


func flash_stamina() -> void:
	_st_flash = 1.0


# ---------------------------------------------------------------------------------------------
# Dibujo


func _on_draw() -> void:
	if combat == null or combat.player == null:
		return
	if combat.player.free_flight_enabled or not combat.player.visible:
		return
	_draw_player_bars()
	_draw_enemy_bars()
	_draw_lock()
	_draw_crosshair()


func _bar(pos: Vector2, size: Vector2, fill: float, trail: float, color: Color, trail_color: Color) -> void:
	var border := maxf(2.0, 2.0 * _scale)
	_canvas.draw_rect(Rect2(pos - Vector2(border, border), size + Vector2(border, border) * 2.0), FRAME)
	_canvas.draw_rect(Rect2(pos, size), BAR_BACK)
	if trail > fill:
		_canvas.draw_rect(Rect2(pos, Vector2(size.x * trail, size.y)), trail_color)
	_canvas.draw_rect(Rect2(pos, Vector2(size.x * clampf(fill, 0.0, 1.0), size.y)), color)
	# Brillo superior, para que la barra no sea un rectángulo plano.
	_canvas.draw_rect(Rect2(pos, Vector2(size.x * clampf(fill, 0.0, 1.0), size.y * 0.35)), Color(1, 1, 1, 0.10))


func _draw_player_bars() -> void:
	var health := combat.player.health_component
	var origin := Vector2(48, 44) * _scale
	var per_point := 3.4 * _scale
	var hp_size := Vector2(health.max_health * per_point, 14.0 * _scale)
	_bar(origin, hp_size, health.get_health_ratio(), _hp_trail, HP_COLOR, HP_TRAIL)
	var st := combat.stamina
	var st_size := Vector2(st.max_stamina * per_point, 10.0 * _scale)
	var st_color := ST_COLOR
	if st.exhausted:
		st_color = ST_COLOR.darkened(0.45)
	st_color = st_color.lerp(Color(0.85, 0.75, 0.3), _st_flash)
	_bar(origin + Vector2(0, 26 * _scale), st_size, st.get_ratio(), 0.0, st_color, st_color)


func _draw_enemy_bars() -> void:
	var cam := combat.player.camera
	if cam == null:
		return
	var up := -combat.player.gravity_direction.normalized()
	for npc in _enemy_trail:
		if not is_instance_valid(npc):
			continue
		var body := npc as NPCController
		if body.is_dead and npc != combat.lock_target:
			continue
		var head := combat._lock_point(body) + up * 1.25
		if cam.is_position_behind(head):
			continue
		var dist := cam.global_position.distance_to(head)
		if dist > 45.0:
			continue
		var screen := cam.unproject_position(head)
		var width := lerpf(170.0, 90.0, clampf(dist / 40.0, 0.0, 1.0)) * _scale
		var size := Vector2(width, 8.0 * _scale)
		_bar(screen - Vector2(width * 0.5, 0), size, body.health_component.get_health_ratio(),
			_enemy_trail[npc], HP_COLOR, HP_TRAIL)


func _draw_lock() -> void:
	var target := combat.lock_target
	if target == null or not is_instance_valid(target):
		return
	var cam := combat.player.camera
	var point := combat._lock_point(target)
	if cam.is_position_behind(point):
		return
	var screen := cam.unproject_position(point)
	var r := 11.0 * _scale
	var pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.006)
	_canvas.draw_circle(screen, r * 0.42, Color(1, 1, 1, 0.95))
	_canvas.draw_arc(screen, r * 1.35 * pulse, 0, TAU, 32, Color(0, 0, 0, 0.6), 3.0 * _scale)
	_canvas.draw_arc(screen, r * 1.35 * pulse, 0, TAU, 32, Color(1, 1, 1, 0.75), 1.5 * _scale)


func _draw_crosshair() -> void:
	var data := combat.weapon()
	if combat.state != PlayerCombat.State.AIM or data == null or not data.is_ranged():
		return
	if combat.lock_target != null:
		return
	var center := get_viewport().get_visible_rect().size * 0.5
	var draw := combat._draw
	var gap := lerpf(26.0, 6.0, draw) * _scale
	var len := 9.0 * _scale
	var col := Color(1, 1, 1, 0.85) if draw < 0.99 else Color(1.0, 0.85, 0.55, 0.95)
	var width := 2.0 * _scale
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		_canvas.draw_line(center + d * gap, center + d * (gap + len), Color(0, 0, 0, 0.5), width + 2.0)
		_canvas.draw_line(center + d * gap, center + d * (gap + len), col, width)
	_canvas.draw_circle(center, 2.0 * _scale, col)
	if draw > 0.0:
		_canvas.draw_arc(center, 34.0 * _scale, -PI * 0.5, -PI * 0.5 + TAU * draw, 40,
			Color(1, 1, 1, 0.35 + 0.4 * draw), 2.5 * _scale)


# ---------------------------------------------------------------------------------------------
# Muerte y fundidos


func show_death() -> void:
	_death_shown = true
	_death_band.visible = true
	_death_label.visible = true
	_death_label.scale = Vector2.ONE
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_death_band, "modulate:a", 1.0, 1.2)
	tween.tween_property(_death_label, "modulate:a", 1.0, 1.8).set_trans(Tween.TRANS_SINE)
	CombatFx.play(&"player_death", combat.player.global_position, {"volume_offset_db": -6.0, "pitch": 0.7})


func hide_death() -> void:
	_death_shown = false
	_death_band.visible = false
	_death_label.visible = false
	_death_band.modulate.a = 0.0
	_death_label.modulate.a = 0.0


func is_death_shown() -> bool:
	return _death_shown


func fade_to_black(duration: float) -> void:
	_fade.visible = true
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, duration)
	await tween.finished


func fade_from_black(duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 0.0, duration)
	await tween.finished
	_fade.visible = false

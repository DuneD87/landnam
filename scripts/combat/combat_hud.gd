class_name CombatHUD
extends CanvasLayer

## Interfaz de combate: vida y aguante en las dos orbes de la barra rápida (VitalOrb en la consola de
## Hotbar, con el tramo perdido que se vacía con retraso, como en los souls), la silueta del
## cuerpo herido y sus estados a la izquierda de la consola, marca del objetivo fijado, barras de
## vida sobre los enemigos tocados, mira al apuntar con la tensión y la munición, destello rojo al
## recibir, la pantalla de muerte y los fundidos a negro de la reaparición.
##
## Va con Saga (GameTheme): placas de hierro biseladas con filete de bronce, rombos por remaches y
## texto color hueso. La UI del proyecto no se estira: todo se escala por la altura de la ventana
## (base 1440).

## Vida y tramo perdido de las criaturas: los de la orbe de vida (VitalOrb).
const HP_COLOR := Color(0.71, 0.1, 0.08)
const HP_TRAIL := Color(0.86, 0.66, 0.30)
## Segundos que se ve la barra de una criatura después de golpearla.
const ENEMY_BAR_TIME := 6.0
const BLOOD_LOSS_SHADER := preload("res://shaders/combat/blood_loss.gdshader")
## Separación entre la consola de la barra rápida y la silueta, y entre la silueta y los estados.
const BODY_GAP := 26.0
const STATUS_GAP := 14.0
## Desangrarse: a cuánta sangre perdida por segundo llega al máximo, y por debajo de qué vida empieza
## (y en qué tramo llega al máximo).
const LOSS_FULL_BLEED := 2.0
const LOSS_LOW_HEALTH := Vector2(0.35, 0.25)

var combat: PlayerCombat
var _canvas: Control
var _vignette: TextureRect
var _fade: ColorRect
var _death_band: TextureRect
var _death_label: Label
var _ammo_label: Label
## Estados en curso (pierna rota…) con lo que les queda, bajo la silueta.
var _status_label: Label

var _scale: float = 1.0
var _hp_trail: float = 1.0
var _hp_trail_hold: float = 0.0
var _st_flash: float = 0.0
var _damage_flash: float = 0.0
var _enemy_seen: Dictionary = {}
var _enemy_trail: Dictionary = {}
var _death_shown: bool = false
## Desangrarse: el mundo pierde color y los bordes laten (blood_loss.gdshader), con el corazón.
var _blood_loss: ColorRect
var _loss: float = 0.0
var _beat: float = 0.0
## Latido de este fotograma (0..1), para que la orbe de vida lata con él.
var _pulse: float = 0.0
## Rectángulo en pantalla de la orbe de vida y borde izquierdo de la consola: la silueta y los
## estados se colocan a su lado.
var _health_rect := Rect2()
var _plate_left := 0.0


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

	# En su propia capa, por debajo de la barra rápida (10) y del resto del HUD: las orbes, la barra
	# y las marcas no pierden el color.
	var loss_layer := CanvasLayer.new()
	loss_layer.name = "BloodLossLayer"
	loss_layer.layer = 9
	add_child(loss_layer)
	_blood_loss = ColorRect.new()
	_blood_loss.name = "BloodLoss"
	_blood_loss.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blood_loss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var loss_material := ShaderMaterial.new()
	loss_material.shader = BLOOD_LOSS_SHADER
	_blood_loss.material = loss_material
	_blood_loss.visible = false
	loss_layer.add_child(_blood_loss)

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
	_ammo_label.add_theme_font_override("font", GameTheme.medium_font())
	_ammo_label.add_theme_color_override("font_color", GameTheme.BONE)
	_ammo_label.add_theme_color_override("font_outline_color", Color(GameTheme.INK, 0.9))
	_ammo_label.add_theme_constant_override("outline_size", 6)
	_ammo_label.visible = false
	add_child(_ammo_label)

	_status_label = Label.new()
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.add_theme_font_override("font", GameTheme.medium_font())
	_status_label.add_theme_color_override("font_color", GameTheme.BONE)
	_status_label.add_theme_color_override("font_outline_color", Color(GameTheme.INK, 0.9))
	_status_label.add_theme_constant_override("outline_size", 5)
	_status_label.visible = false
	add_child(_status_label)

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
	_death_label.add_theme_font_override("font", GameTheme.title_font(1.0, 500))
	_death_label.add_theme_color_override("font_color", Color(0.58, 0.06, 0.05))
	_death_label.add_theme_color_override("font_outline_color", Color(0.05, 0.0, 0.0, 0.9))
	_death_label.add_theme_constant_override("outline_size", 4)
	_death_label.modulate.a = 0.0
	_death_label.visible = false
	# Un filete de Saga encima y otro debajo del cartel; se funden con él.
	_death_label.draw.connect(_draw_death_rules)
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
	# El destello, el desangrarse y el fundido van anclados a toda la pantalla: no hace falta medirlos.
	var band_h := 260.0 * _scale
	_death_band.position = Vector2(0, size.y * 0.5 - band_h * 0.5)
	_death_band.size = Vector2(size.x, band_h)
	_death_label.position = _death_band.position
	_death_label.size = _death_band.size
	_death_label.add_theme_font_size_override("font_size", int(150 * _scale))
	_ammo_label.add_theme_font_size_override("font_size", int(26 * _scale))
	_status_label.add_theme_font_size_override("font_size", int(22 * _scale))


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
	_update_blood_loss(delta)
	_update_orbs(delta)
	_update_ammo()
	_update_status()
	_canvas.queue_redraw()


## Llena las orbes de la barra rápida. En vuelo libre o sin cuerpo no salen (ni su consola).
func _update_orbs(delta: float) -> void:
	var hotbar: Hotbar = combat.player.hotbar
	if hotbar == null or hotbar.health_orb == null:
		return
	var shown := not combat.player.free_flight_enabled and combat.player.visible
	hotbar.set_vitals_shown(shown)
	if not shown:
		return
	var health_orb := hotbar.health_orb
	var stamina_orb := hotbar.stamina_orb
	_health_rect = Rect2(health_orb.position, health_orb.size)
	_plate_left = hotbar.vitals_left

	var health := combat.player.health_component
	health_orb.flash = _damage_flash
	health_orb.set_levels(health.get_health_ratio(), _hp_trail, maxf(_pulse * _loss, _damage_flash * 0.5), 0.0,
		"%d / %d" % [ceili(health.health), roundi(health.max_health)], delta)
	var st := combat.stamina
	stamina_orb.flash = _st_flash
	stamina_orb.set_levels(st.get_ratio(), 0.0, _st_flash * 0.4, 0.55 if st.exhausted else 0.0,
		str(floori(st.stamina)), delta)
	hotbar.show_needs(combat.player.needs, delta)


## Cuánto se está desangrando (sangre perdida por segundo, o poca vida) y el latido: el corazón
## se acelera con ello, y por encima de un poco se oye.
func _update_blood_loss(delta: float) -> void:
	var health := combat.player.health_component
	var damage := combat.body_damage
	var target := 0.0
	if not health.is_dead and damage != null:
		var bleeding := clampf(damage.bleed_rate() / LOSS_FULL_BLEED, 0.0, 1.0) * 0.8
		var weak := clampf((LOSS_LOW_HEALTH.x - health.get_health_ratio()) / LOSS_LOW_HEALTH.y, 0.0, 1.0)
		target = maxf(bleeding, weak)
	_loss = move_toward(_loss, target, delta * 0.5)
	_blood_loss.visible = _loss > 0.01
	if not _blood_loss.visible:
		_pulse = 0.0
		return
	var bpm := lerpf(70.0, 140.0, _loss)
	var before := _beat
	_beat = fmod(_beat + delta * bpm / 60.0, 1.0)
	if _beat < before and _loss > 0.25:
		CombatFx.play(&"heartbeat", combat.player.global_position, {"volume_offset_db": lerpf(-12.0, 0.0, _loss)})
	# "Pum-pum": el segundo golpe va 0,17 s después del primero, como en el sonido.
	var dub := 0.17 * bpm / 60.0
	var pulse := exp(-_beat * 14.0)
	if _beat >= dub:
		pulse += 0.6 * exp(-(_beat - dub) * 14.0)
	_pulse = clampf(pulse, 0.0, 1.0)
	var mat := _blood_loss.material as ShaderMaterial
	mat.set_shader_parameter("amount", _loss)
	mat.set_shader_parameter("pulse", clampf(pulse, 0.0, 1.0))


## Un renglón por estado, con los minutos y segundos que le quedan, a la izquierda de la silueta
## y apoyados en el borde de abajo de la orbe de vida.
func _update_status() -> void:
	var status := combat.status
	var shown := status != null and not status.effects().is_empty() and not combat.player.free_flight_enabled \
		and combat.player.visible
	_status_label.visible = shown
	if not shown:
		return
	var lines := PackedStringArray()
	for effect in status.effects():
		var left := ceili(maxf(effect.remaining, 0.0))
		lines.append("%s  %d:%02d" % [effect.label(), floori(left / 60.0), left % 60])
	_status_label.text = "\n".join(lines)
	var width := 360.0 * _scale
	var origin := _body_origin()
	_status_label.size = Vector2(width, 0.0)
	_status_label.position = Vector2(origin.x - STATUS_GAP * _scale - width,
		_health_rect.end.y - _status_label.get_combined_minimum_size().y)


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
	_ammo_label.modulate = GameTheme.BLOOD.lightened(0.35) if count == 0 else Color.WHITE


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
	_draw_body()
	_draw_enemy_bars()
	_draw_lock()
	_draw_crosshair()


## Barra de Saga: placa de hierro con las puntas biseladas y filete de bronce, un rombo de bronce
## en cada punta, el tramo perdido en ámbar y lo que queda en [color], con un brillo arriba.
func _bar(pos: Vector2, size: Vector2, fill: float, trail: float, color: Color, trail_color: Color) -> void:
	var pad := maxf(2.0, 3.0 * _scale)
	var plate := Rect2(pos - Vector2(pad, pad), size + Vector2(pad, pad) * 2.0)
	# Casi la mitad del alto: las puntas quedan en pico, como una hoja (la mitad justa repetiría
	# puntos y el polígono no se triangula).
	var plate_cut := plate.size.y * 0.45
	_canvas.draw_colored_polygon(SagaFrame.chamfered(plate, plate_cut), GameTheme.IRON)
	var cut := size.y * 0.45
	_canvas.draw_colored_polygon(SagaFrame.chamfered(Rect2(pos, size), cut), GameTheme.IRON_DEEP)
	fill = clampf(fill, 0.0, 1.0)
	if trail > fill:
		_fill_bar(pos, size, trail, cut, trail_color)
	_fill_bar(pos, size, fill, cut, color)
	if size.x * fill > cut * 2.0 + 1.0:
		var shine := maxf(1.0, size.y * 0.2)
		_canvas.draw_line(pos + Vector2(cut, shine), pos + Vector2(size.x * fill - cut, shine),
			Color(1, 1, 1, 0.14), shine)
	var outline := SagaFrame.chamfered(plate, plate_cut)
	outline.append(outline[0])
	_canvas.draw_polyline(outline, GameTheme.BRONZE_LINE, maxf(1.0, _scale), true)
	var mid := plate.position.y + plate.size.y * 0.5
	var rivet := maxf(2.0, 3.5 * _scale)
	for x in [plate.position.x - rivet * 1.6, plate.end.x + rivet * 1.6]:
		_canvas.draw_colored_polygon(SagaFrame.diamond(Vector2(x, mid), rivet + 1.0), Color(GameTheme.INK, 0.8))
		_canvas.draw_colored_polygon(SagaFrame.diamond(Vector2(x, mid), rivet), GameTheme.BRONZE)


## El tramo [amount] (0..1) de la barra, con las mismas puntas biseladas.
func _fill_bar(pos: Vector2, size: Vector2, amount: float, cut: float, color: Color) -> void:
	var width := size.x * amount
	if width < 1.0:
		return
	_canvas.draw_colored_polygon(SagaFrame.chamfered(Rect2(pos, Vector2(width, size.y)), minf(cut, width * 0.45)), color)


## Silueta de espaldas (como se ve al personaje) a la izquierda de la consola de la barra rápida, con cada parte del cuerpo del color
## de su estado; solo cuando hay algo herido (o algún estado en curso). Un miembro perdido queda en
## contorno con el muñón rojo, uno roto amoratado y con la grieta, y una gota late mientras sangra.
const BODY_SHAPES := {
	&"head": Rect2(15, 0, 12, 13),
	&"chest": Rect2(12, 15, 18, 15),
	&"stomach": Rect2(13, 31, 16, 12),
	&"left_arm": Rect2(4, 16, 7, 30),
	&"right_arm": Rect2(31, 16, 7, 30),
	&"left_leg": Rect2(12, 45, 8, 38),
	&"right_leg": Rect2(22, 45, 8, 38),
}


const BODY_SCALE := 1.15
const BRUISE := Color(0.42, 0.24, 0.50, 0.92)
const CRACK := Color(0.96, 0.92, 0.80)


## Esquina de arriba a la izquierda de la silueta: a la izquierda de la consola de la barra rápida,
## con los pies a la altura del borde de abajo de la orbe de vida (la silueta y la gota ocupan 52
## de ancho y 83 de alto).
func _body_origin() -> Vector2:
	var s := BODY_SCALE * _scale
	return Vector2(_plate_left - BODY_GAP * _scale - 52.0 * s, _health_rect.end.y - 83.0 * s)


func _draw_body() -> void:
	var damage := combat.body_damage
	var status := combat.status
	var has_status := status != null and not status.effects().is_empty()
	if damage == null or not (damage.is_hurt() or has_status):
		return
	var s := BODY_SCALE * _scale
	var origin := _body_origin()
	var t := Time.get_ticks_msec() / 1000.0
	for zone: StringName in BODY_SHAPES:
		var r: Rect2 = BODY_SHAPES[zone]
		var rect := Rect2(origin + r.position * s, r.size * s)
		if damage.is_severed(zone):
			# Lo que queda del miembro (el arranque) y el muñón.
			var stub := Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.35))
			_canvas.draw_rect(rect, Color(0.6, 0.55, 0.5, 0.35), false, maxf(1.0, s))
			_canvas.draw_rect(stub, Color(0.30, 0.03, 0.03, 0.9))
			_canvas.draw_rect(Rect2(stub.position + Vector2(0, stub.size.y - 2.0 * s), Vector2(stub.size.x, 2.0 * s)),
				Color(0.85, 0.08, 0.06))
			continue
		var color := _zone_color(damage.zone_ratio(zone))
		if zone == damage.last_zone:
			color = color.lerp(Color(1, 0.9, 0.8), _damage_flash * 0.6)
		var broken := status != null and status.is_zone_impaired(zone)
		if broken:
			color = BRUISE.lerp(color, 0.25)
		if zone == &"head":
			_canvas.draw_circle(rect.get_center(), rect.size.x * 0.55, color)
		else:
			_canvas.draw_rect(rect, color)
		if broken:
			_draw_crack(rect, s)
	var bleed := damage.bleed_rate()
	if bleed > 0.0:
		var pulse := 0.55 + 0.45 * sin(t * TAU * clampf(0.8 + bleed * 1.5, 0.8, 3.0))
		var c := origin + Vector2(46, 70) * s
		var drop := Color(0.75, 0.04, 0.04, clampf(0.35 + bleed, 0.4, 1.0) * pulse)
		_canvas.draw_circle(c, 4.5 * s, drop)
		_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-4.2, -1.5) * s, c + Vector2(0, -11) * s,
			c + Vector2(4.2, -1.5) * s]), drop)


## Grieta en zigzag de lado a lado, a media altura del miembro.
func _draw_crack(rect: Rect2, s: float) -> void:
	var y := rect.position.y + rect.size.y * 0.55
	var x0 := rect.position.x - 1.5 * s
	var w := rect.size.x + 3.0 * s
	var points := PackedVector2Array()
	for i in 5:
		points.append(Vector2(x0 + w * i / 4.0, y + (3.0 if i % 2 == 1 else -3.0) * s))
	_canvas.draw_polyline(points, Color(0, 0, 0, 0.6), maxf(2.5, 2.5 * s))
	_canvas.draw_polyline(points, CRACK, maxf(1.2, 1.2 * s))


## Sana: hueso claro y transparente; herida: de ámbar a rojo; inutilizada (bajo cero): granate.
static func _zone_color(ratio: float) -> Color:
	if ratio >= 0.999:
		return Color(0.82, 0.78, 0.70, 0.45)
	if ratio > 0.0:
		return Color(0.80, 0.16, 0.08, 0.9).lerp(Color(0.90, 0.72, 0.40, 0.85), ratio)
	return Color(0.42, 0.03, 0.04, 0.95).lerp(Color(0.18, 0.01, 0.02, 0.95), clampf(-ratio, 0.0, 1.0))


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
	var s := _scale
	var pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.006)
	# Un rombo de hueso en el punto y, alrededor, otro de bronce con un remache en cada vértice,
	# que late (como los biseles de SagaFrame).
	_canvas.draw_colored_polygon(SagaFrame.diamond(screen, 6.5 * s), Color(GameTheme.INK, 0.85))
	_canvas.draw_colored_polygon(SagaFrame.diamond(screen, 4.5 * s), GameTheme.BONE)
	var reach := 17.0 * s * pulse
	var ring := SagaFrame.diamond(screen, reach)
	ring.append(ring[0])
	_canvas.draw_polyline(ring, Color(GameTheme.INK, 0.55), 3.5 * s, true)
	_canvas.draw_polyline(ring, Color(GameTheme.BRONZE, 0.8), 1.5 * s, true)
	for corner in ring.slice(0, 4):
		_canvas.draw_colored_polygon(SagaFrame.diamond(corner, 4.5 * s), Color(GameTheme.INK, 0.85))
		_canvas.draw_colored_polygon(SagaFrame.diamond(corner, 3.0 * s), GameTheme.BRONZE)


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
	# Hueso; a tensión completa, bronce. El centro es un rombo y la tensión un arco de bronce.
	var col := Color(GameTheme.BONE, 0.9) if draw < 0.99 else GameTheme.BRONZE
	var shadow := Color(GameTheme.INK, 0.6)
	var width := 2.0 * _scale
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		_canvas.draw_line(center + d * gap, center + d * (gap + len), shadow, width + 2.0)
		_canvas.draw_line(center + d * gap, center + d * (gap + len), col, width)
	_canvas.draw_colored_polygon(SagaFrame.diamond(center, 3.5 * _scale), shadow)
	_canvas.draw_colored_polygon(SagaFrame.diamond(center, 2.2 * _scale), col)
	if draw > 0.0:
		var to := -PI * 0.5 + TAU * draw
		_canvas.draw_arc(center, 34.0 * _scale, -PI * 0.5, to, 40, Color(GameTheme.INK, 0.4), 4.5 * _scale)
		_canvas.draw_arc(center, 34.0 * _scale, -PI * 0.5, to, 40,
			Color(GameTheme.BRONZE, 0.45 + 0.45 * draw), 2.5 * _scale)


# ---------------------------------------------------------------------------------------------
# Muerte y fundidos


## Filetes de Saga (SagaRule) encima y debajo de HAS MUERTO, dibujados en el propio cartel: van por
## encima de la franja oscura y se funden con él.
func _draw_death_rules() -> void:
	var rule := SagaRule.new()
	rule.color = Color(GameTheme.BRONZE, 0.6)
	rule.thickness = maxf(1.0, 1.5 * _scale)
	rule.diamond = 6.0 * _scale
	rule.gap = 12.0 * _scale
	var size := _death_label.size
	var half := minf(520.0 * _scale, size.x * 0.45)
	for dy in [-105.0, 105.0]:
		var y: float = size.y * 0.5 + dy * _scale
		rule.draw(_death_label.get_canvas_item(), Rect2(size.x * 0.5 - half, y - 6.0 * _scale, half * 2.0, 12.0 * _scale))


func show_death() -> void:
	_death_shown = true
	_death_band.visible = true
	_death_label.visible = true
	_death_label.scale = Vector2.ONE
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_death_band, "modulate:a", 1.0, 1.2)
	tween.tween_property(_death_label, "modulate:a", 1.0, 1.8).set_trans(Tween.TRANS_SINE)
	CombatFx.play(&"death_stinger", combat.player.global_position, {"volume_offset_db": -6.0, "pitch": 0.7})


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

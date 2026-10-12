class_name Hotbar
extends CanvasLayer

## Barra rápida: diez huecos con lo que se saca con las teclas 1-0, encajada en una consola de
## hierro (VitalsPlate) que se levanta a cada lado en el hueco de una orbe: la vida a la
## izquierda y el aguante a la derecha (VitalOrb, que llena CombatHUD). En el centro asoma la media
## orbe de la cordura, alrededor de la vida van el hambre y la sed, alrededor del aguante la
## temperatura y el descanso (NeedGauge), y bajo el agua las runas del aguante cuentan el aire
## (BreathRing). Las necesidades las da SurvivalNeeds (show_needs).

signal selection_changed(old_data: ItemData, new_data: ItemData)
signal hotbar_slot_clicked(slot_index: int)
## La tecla de un escudo no lo selecciona: lo pone en la otra mano o lo quita, y el arma de la
## derecha sigue donde estaba.
signal offhand_toggled(data: ItemData)

const HOTBAR_SLOTS := 10
## Alto del zócalo que une la barra al borde inferior, con el nombre del objeto grabado.
const BOTTOM_GAP := 28.0
## Orbes (escala base): radio, hueco entre su aro y el panel y cuánto bajan de la línea de abajo
## del panel. La consola está dibujada para estas medidas: si cambian, hay que cambiarlas también
## en tools/ui/bake_hotbar_console.py y volver a hornearla.
const ORB_RADIUS := 76.0
const ORB_GAP := 16.0
const ORB_DROP := 12.0
## Altura de los avisos sobre el panel (por encima de la cresta) y lo que duran.
const NOTICE_LIFT := 112.0
const NOTICE_HOLD := 2.6
const NOTICE_FADE := 0.6
## Media orbe de la cordura, con el centro en el borde de arriba del panel.
const SANITY_RADIUS := 35.0
const SANITY_LIFT := 6.0
## Medidores: radio y grosor del arco en su canal, y el medallón del icono del que arranca
## (distancia al centro del engaste y radio). También tallados en la consola.
const GAUGE_RADIUS := 101.0
const GAUGE_WIDTH := 6.0
const MEDALLION_DISTANCE := 111.0
const MEDALLION_RADIUS := 16.0
## Por necesidad (su nombre en SurvivalNeeds): engaste (-1 el de la vida, 1 el del aguante), grados
## desde lo alto, en el sentido de las agujas del reloj, de donde asoma la barra del medallón, de
## donde acaba y del medallón, y color. Se llenan en ese sentido, desde el icono.
const GAUGES := {
	"sed": [-1, -116.5, -84.0, -126.0, Color(0.36, 0.64, 0.88)],
	"hambre": [-1, -60.5, -16.0, -70.0, Color(0.86, 0.62, 0.27)],
	"temperatura": [1, 35.5, 72.0, 26.0, Color.WHITE],
	"descanso": [1, 93.5, 138.0, 84.0, Color(0.7, 0.72, 0.92)],
}

@onready var slot_container: HBoxContainer = $BottomAnchor/PanelContainer/MarginContainer/HBoxContainer

var slots: Array[HotbarSlot] = []
var health_orb: VitalOrb
var stamina_orb: VitalOrb
var sanity_orb: VitalOrb
var gauges := {}
var breath: BreathRing
## Avisos cortos sobre la consola («Bebes agua dulce», «Necesitas un cuchillo...»): notify().
var _notice: Label
var _item_name: Label
var _notice_age := INF
## La consola (también cuenta como barra para el inventario: clicar en ella no tira nada).
var plate: VitalsPlate
## Borde izquierdo de la consola en pantalla, para lo que va a su lado (la silueta del cuerpo).
var vitals_left := 0.0
var selected_index: int = -1
var is_ctrl_hold: bool = false
## Lo que lleva la otra mano (id), para resaltar su hueco. Lo dice el jugador con set_offhand().
var _offhand_id: StringName = &""
var _vitals_shown := true

var _key_actions: Array[StringName] = [
	&"hotbar_1", &"hotbar_2", &"hotbar_3", &"hotbar_4", &"hotbar_5",
	&"hotbar_6", &"hotbar_7", &"hotbar_8", &"hotbar_9", &"hotbar_0",
]


func _ready() -> void:
	_ensure_input_actions()
	# Detrás del panel la consola; delante, las orbes en sus huecos.
	plate = VitalsPlate.new()
	add_child(plate)
	move_child(plate, 0)
	breath = BreathRing.new()
	add_child(breath)
	for need in GAUGES:
		var gauge := NeedGauge.new(NeedGauge.Mode.BIPOLAR if need == "temperatura" else NeedGauge.Mode.FILL,
			GAUGES[need][4])
		add_child(gauge)
		gauges[need] = gauge
	health_orb = VitalOrb.health()
	add_child(health_orb)
	stamina_orb = VitalOrb.stamina()
	add_child(stamina_orb)
	sanity_orb = VitalOrb.sanity()
	add_child(sanity_orb)
	_notice = Label.new()
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_font_override("font", GameTheme.medium_font())
	_notice.add_theme_color_override("font_color", GameTheme.BONE)
	_notice.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_notice.modulate.a = 0.0
	add_child(_notice)
	_item_name = Label.new()
	_item_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_name.add_theme_font_override("font", GameTheme.medium_font())
	_item_name.add_theme_color_override("font_color", GameTheme.BONE.darkened(0.2))
	_item_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_child(_item_name)
	selection_changed.connect(_show_selected_name)
	get_panel().item_rect_changed.connect(_layout_vitals)
	_apply_theme()
	get_viewport().size_changed.connect(_apply_theme)
	_create_slots()
	# Los iconos de bloque se renderizan uno a uno al arrancar y la tanda dura segundos. assign()
	# copia la textura del item en ese instante y no vuelve a mirarla, así que restaurar una
	# partida a medias dejaba en blanco todo lo que aún no se hubiera renderizado. Repintar solo al
	# final tampoco basta: hay huecos que estrenan icono en mitad de la tanda, así que se repinta
	# con cada uno hasta que están todos.
	if not BlockDatabase.are_materials_ready():
		BlockDatabase.icon_generated.connect(_refresh_slot_icons)
		BlockDatabase.materials_ready.connect(_on_block_icons_ready)


## El panel de la barra (el inventario mira si el ratón está encima).
func get_panel() -> Control:
	return $BottomAnchor/PanelContainer


## Saga a la escala de la ventana; los huecos toman su lado del tema.
func _apply_theme() -> void:
	var ui_scale := GameTheme.scale_for(get_viewport())
	var anchor: Control = $BottomAnchor
	anchor.theme = GameTheme.build(ui_scale)
	var panel := get_panel() as PanelContainer
	panel.theme_type_variation = &"HotbarPanel"
	panel.offset_bottom = -roundf(BOTTOM_GAP * ui_scale) if _vitals_shown else 0.0
	slot_container.add_theme_constant_override("separation", roundi(8.0 * ui_scale))
	var margin: MarginContainer = $BottomAnchor/PanelContainer/MarginContainer
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 0)
	_layout_vitals()


## Orbes y consola alrededor del panel, que es quien manda: si cambia de tamaño o de sitio, le siguen.
func _layout_vitals() -> void:
	if plate == null:
		return
	var ui_scale := GameTheme.scale_for(get_viewport())
	var bar := get_panel().get_global_rect()
	if bar.size.x <= 0.0:
		return
	var radius := ORB_RADIUS * ui_scale
	var y := bar.end.y - radius + ORB_DROP * ui_scale
	var left := Vector2(bar.position.x - ORB_GAP * ui_scale - radius, y)
	var right := Vector2(bar.end.x + ORB_GAP * ui_scale + radius, y)
	health_orb.place(left, radius, ui_scale)
	stamina_orb.place(right, radius, ui_scale)
	sanity_orb.place(Vector2(bar.position.x + bar.size.x * 0.5, bar.position.y - SANITY_LIFT * ui_scale),
		SANITY_RADIUS * ui_scale, ui_scale)
	for need in gauges:
		var spec: Array = GAUGES[need]
		(gauges[need] as NeedGauge).place(left if spec[0] < 0 else right, GAUGE_RADIUS * ui_scale,
			GAUGE_WIDTH * ui_scale, spec[1], spec[2], spec[3], MEDALLION_DISTANCE * ui_scale,
			MEDALLION_RADIUS * ui_scale, ui_scale)
	breath.place(right, ui_scale)
	_notice.add_theme_font_size_override("font_size", roundi(26 * ui_scale))
	_notice.add_theme_constant_override("outline_size", roundi(7 * ui_scale))
	_notice.size = Vector2(bar.size.x, 40.0 * ui_scale)
	_notice.position = Vector2(bar.position.x, bar.position.y - (NOTICE_LIFT + 40.0) * ui_scale)
	_item_name.add_theme_font_size_override("font_size", roundi(18 * ui_scale))
	_item_name.add_theme_constant_override("outline_size", roundi(3 * ui_scale))
	_item_name.size = Vector2(bar.size.x, 22.0 * ui_scale)
	_item_name.position = Vector2(bar.position.x,
		bar.end.y + 4.0 * ui_scale if _vitals_shown else bar.position.y - 26.0 * ui_scale)
	plate.layout(bar, ui_scale)
	vitals_left = plate.left_edge(bar, ui_scale)


func _show_selected_name(_old_data: ItemData, new_data: ItemData) -> void:
	_item_name.text = new_data.display_name if new_data != null else ""


## Enseña u oculta las orbes y los medidores con su consola (sin ellas queda la barra sola).
func set_vitals_shown(shown: bool) -> void:
	if _vitals_shown == shown:
		return
	_vitals_shown = shown
	for item: CanvasItem in [health_orb, stamina_orb, sanity_orb, breath, plate]:
		item.visible = shown
	for need in gauges:
		gauges[need].visible = shown
	var ui_scale := GameTheme.scale_for(get_viewport())
	get_panel().offset_bottom = -roundf(BOTTOM_GAP * ui_scale) if shown else 0.0
	_layout_vitals()


## Llena la media orbe de la cordura, los medidores y el aire (lo llama CombatHUD cada fotograma).
func show_needs(needs: SurvivalNeeds, delta: float) -> void:
	if needs == null:
		return
	var low := needs.is_critical("cordura")
	sanity_orb.flash = (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)) if low else 0.0
	sanity_orb.set_levels(needs.sanity, 0.0, sanity_orb.flash * 0.3, 0.0, "%d %%" % roundi(needs.sanity * 100.0), delta)
	for need in gauges:
		(gauges[need] as NeedGauge).set_value(needs.get_value(need), needs.is_critical(need), delta)
	breath.set_oxygen(needs.oxygen, needs.submerged, delta)


func _on_block_icons_ready() -> void:
	if BlockDatabase.icon_generated.is_connected(_refresh_slot_icons):
		BlockDatabase.icon_generated.disconnect(_refresh_slot_icons)
	_refresh_slot_icons()


func _refresh_slot_icons() -> void:
	for slot in slots:
		slot.refresh_icon()

## Un aviso corto sobre la consola, que se va solo.
func notify(text: String) -> void:
	_notice.text = text
	_notice_age = 0.0
	_notice.modulate.a = 1.0


func _process(delta: float) -> void:
	if _notice_age < NOTICE_HOLD + NOTICE_FADE:
		_notice_age += delta
		_notice.modulate.a = clampf(1.0 - (_notice_age - NOTICE_HOLD) / NOTICE_FADE, 0.0, 1.0)
	if Input.is_action_pressed("left_ctrl"):
		is_ctrl_hold = true
	else:
		is_ctrl_hold = false
		
func _create_slots() -> void:
	for child in slot_container.get_children():
		child.queue_free()
	slots.clear()

	for i in HOTBAR_SLOTS:
		var slot := HotbarSlot.new()
		slot.slot_index = i
		slot.slot_clicked.connect(_on_slot_clicked)
		slot_container.add_child(slot)
		slots.append(slot)


func assign_to_slot(index: int, item_data: ItemData) -> void:
	if index < 0 or index >= HOTBAR_SLOTS:
		return
	for i in HOTBAR_SLOTS:
		if slots[i].assigned_data and item_data and slots[i].assigned_data.id == item_data.id:
			slots[i].clear()
			
	var old_data: ItemData = slots[selected_index].assigned_data if index == selected_index else null
	slots[index].assign(item_data)
	
	if index == selected_index:
		var new_data := item_data
		# Un escudo no queda seleccionado: se suelta lo que había en la mano.
		if item_data != null and item_data.is_shield():
			slots[index].set_selected(false)
			selected_index = -1
			new_data = null
		selection_changed.emit(old_data, new_data)
	_refresh_offhand_marks()


func clear_slot(index: int) -> void:
	if index >= 0 and index < HOTBAR_SLOTS:
		if index == selected_index:
			slots[index].set_selected(false)
			selection_changed.emit(slots[index].assigned_data, null)
			selected_index = -1
		slots[index].clear()
		slots[index].set_equipped(false)


## Resalta el hueco de lo que lleva la otra mano (null = nada).
func set_offhand(data: ItemData) -> void:
	_offhand_id = data.id if data != null else &""
	_refresh_offhand_marks()


func _refresh_offhand_marks() -> void:
	for slot in slots:
		slot.set_equipped(_offhand_id != &"" and slot.assigned_data != null \
			and slot.assigned_data.id == _offhand_id)


func get_selected_data() -> ItemData:
	if selected_index < 0:
		return null
	return slots[selected_index].assigned_data


func select_slot(index: int) -> void:
	if index < 0 or index >= HOTBAR_SLOTS:
		return
	if not slots[index].assigned_data:
		return
	if slots[index].assigned_data.is_shield():
		offhand_toggled.emit(slots[index].assigned_data)
		return

	var old_data: ItemData = slots[selected_index].assigned_data if selected_index >= 0 else null

	if index == selected_index:
		slots[selected_index].set_selected(false)
		selected_index = -1
		selection_changed.emit(old_data, null)
		return

	if selected_index >= 0:
		slots[selected_index].set_selected(false)
	selected_index = index
	slots[selected_index].set_selected(true)
	selection_changed.emit(old_data, slots[selected_index].assigned_data)


func _on_slot_clicked(slot: HotbarSlot, _button_index: int) -> void:
	hotbar_slot_clicked.emit(slot.slot_index)


## _unhandled_input (y no _input) para que la GUI tenga prioridad:
## con la consola abierta, su LineEdit consume los números antes de llegar aquí.
func _unhandled_input(event: InputEvent) -> void:
	for i in HOTBAR_SLOTS:
		if event.is_action_pressed(_key_actions[i]):
			select_slot(i)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed and is_ctrl_hold:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select_step(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select_step(1)
			get_viewport().set_input_as_handled()


## Ctrl+rueda: el hueco de al lado, saltando los escudos (pasar por encima no los pone ni los
## quita).
func _select_step(step: int) -> void:
	var index := selected_index
	for i in HOTBAR_SLOTS:
		index = posmod(index + step, HOTBAR_SLOTS)
		var data := slots[index].assigned_data
		if data == null or not data.is_shield():
			select_slot(index)
			return


func _ensure_input_actions() -> void:
	var keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
	for i in HOTBAR_SLOTS:
		var action := _key_actions[i]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.keycode = keys[i]
			InputMap.action_add_event(action, ev)


func get_save_data() -> Array:
	var result: Array = []
	for slot in slots:
		if not slot.assigned_data:
			result.append(null)
		elif slot.assigned_data.category == ItemData.Category.BLOCK:
			result.append({
				"type": "block",
				"id": str(slot.assigned_data.id),
				"block_id": slot.assigned_data.block_id,
				"build_material_id": slot.assigned_data.build_material_id,
			})
		else:
			result.append({
				"type": "item",
				"id": str(slot.assigned_data.id),
			})
	return result


## Vuelca en la barra los huecos guardados. Cargar puede pasar sobre una partida en curso, así que
## primero se vacía entera: los huecos que el save dejó vacíos tienen que quedar vacíos, y la
## selección se reinicia para que select_slot() no lea el hueco ya elegido como un clic y lo apague.
func restore_save_data(data: Array, config: Object) -> void:
	var previous: ItemData = get_selected_data()
	for i in HOTBAR_SLOTS:
		slots[i].set_selected(false)
		slots[i].clear()
	selected_index = -1
	if previous:
		selection_changed.emit(previous, null)

	for i in mini(data.size(), HOTBAR_SLOTS):
		var value = data[i]
		if value == null:
			continue
		var item_data: ItemData
		if value["type"] == "block":
			var mat_id: String = value.get("build_material_id", "")
			if mat_id != "":
				var items_by_mat := BlockDatabase.get_block_items_by_material()
				if items_by_mat.has(mat_id):
					for item in items_by_mat[mat_id]["items"]:
						if item.block_id == value["block_id"]:
							item_data = item
							break
			if not item_data:
				push_warning("[Hotbar] Sin item para bloque %s de material '%s'; se restaura el bloque genérico." % [value["block_id"], mat_id])
				item_data = BlockDatabase.get_block_item(value["block_id"])
		else:
			item_data = config.get_item(StringName(value["id"]))
		if item_data:
			slots[i].assign(item_data)
	_refresh_offhand_marks()
		

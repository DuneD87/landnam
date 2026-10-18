class_name ItemCard
extends PanelContainer

## Ficha del objeto que sale junto al hueco bajo el ratón en la pantalla de equipo: nombre, tipo
## (ItemTaxonomy), sus cifras comparadas con lo que se lleva puesto en el mismo hueco (▲ mejor,
## ▼ peor), lo que dan sus rasgos (ItemTrait), la descripción y qué hacen ahí los clics. Los nombres
## de las filas son claves (los traduce su Label); los valores y la pista llegan ya traducidos.

const Config = preload("res://scripts/config.gd")

## Ancho de la ficha y separación del hueco, en la escala base.
const WIDTH := 470.0
const GAP := 16.0

var ui_scale := 1.0:
	set(value):
		ui_scale = value
		custom_minimum_size.x = roundf(WIDTH * value)

var _column := VBoxContainer.new()


func _init() -> void:
	theme_type_variation = &"Card"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	custom_minimum_size.x = WIDTH
	_column.add_theme_constant_override("separation", 6)
	add_child(_column)


## [compare] es lo que se lleva puesto en el hueco del objeto (null si nada, o si es él mismo).
func show_item(data: ItemData, quantity: int, compare: ItemData, hint: String) -> void:
	_clear()
	_label(data.get_display_name(), &"CardTitle")
	_label(kind_line(data), &"HintLabel")
	var rows := stat_rows(data, compare)
	if data.stackable and data.max_stack > 1 and quantity > 0:
		rows.append(["CARD_QUANTITY", "%d / %d" % [quantity, data.max_stack], 0.0])
	if not rows.is_empty():
		_column.add_child(HSeparator.new())
		var grid := GridContainer.new()
		grid.columns = 3
		for row in rows:
			var name_label := _make(row[0], &"StatLabel")
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(name_label)
			var value := _make(row[1], &"StatValue")
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(value)
			var delta: float = row[2]
			var delta_label := _make("", &"BetterLabel" if delta > 0.0 else &"WorseLabel")
			delta_label.custom_minimum_size.x = roundf(70 * ui_scale)
			delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			if not is_zero_approx(delta):
				delta_label.text = ("▲ " if delta > 0.0 else "▼ ") + _number(absf(row[3] if row.size() > 3 else delta))
			grid.add_child(delta_label)
		_column.add_child(grid)
	var text := data.get_description().strip_edges()
	if text != "":
		var description := _label(text, &"StatLabel")
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer(hint)
	_present()


## Ficha de un hueco vacío: su nombre y lo que se puede hacer (claves o textos ya traducidos).
func show_empty(title: String, hint: String) -> void:
	_clear()
	_label(title, &"CardTitle")
	_label("CARD_EMPTY", &"HintLabel")
	_footer(hint)
	_present()


## Encima de [target] (un hueco de la barra rápida), centrada.
func place_above(target: Rect2) -> void:
	var bounds := get_viewport().get_visible_rect()
	var card := get_combined_minimum_size()
	var gap := GAP * ui_scale
	var x := clampf(target.get_center().x - card.x * 0.5, gap, maxf(bounds.end.x - card.x - gap, gap))
	global_position = Vector2(x, maxf(target.position.y - gap - card.y, gap))


## Junto a [target] (rectángulo global): a su derecha si cabe, si no a su izquierda, con el
## borde de arriba a la altura del suyo.
func place_beside(target: Rect2) -> void:
	var bounds := get_viewport().get_visible_rect()
	var card := get_combined_minimum_size()
	var gap := GAP * ui_scale
	var x := target.end.x + gap
	if x + card.x > bounds.end.x - gap:
		x = target.position.x - gap - card.x
	var y := clampf(target.position.y, bounds.position.y + gap, maxf(bounds.end.y - card.y - gap, gap))
	global_position = Vector2(maxf(x, gap), y)


## Tipo del objeto en una línea: «Arma · Tajo · Dos manos», «Armadura · Torso», «Escudo».
static func kind_line(data: ItemData) -> String:
	return ItemTaxonomy.kind_line(data)


## Cifras de [data]: [nombre, valor, diferencia con [compare] en el sentido en que es mejor
## (positiva = mejor) y, si hay comparación, la diferencia tal cual].
static func stat_rows(data: ItemData, compare: ItemData) -> Array:
	var rows := []
	var other := compare if compare != null and compare.id != data.id else null
	if data.is_shield():
		rows.append(["CARD_BLOCK", "%d %%" % roundi(data.guard_reduction * 100.0)]
			+ _delta(other, data.guard_reduction * 100.0, other.guard_reduction * 100.0 if other else 0.0))
		rows.append(["CARD_STABILITY", _number(data.guard_stability)]
			+ _delta(other, data.guard_stability, other.guard_stability if other else 0.0))
		if data.guard_projectiles:
			rows.append(["CARD_STOPS_ARROWS", TranslationServer.translate(&"UI_YES"), 0.0])
		return rows
	match data.category:
		ItemData.Category.WEAPON, ItemData.Category.TOOL:
			if data.damage > 0:
				rows.append(["CARD_DAMAGE", str(data.damage)]
					+ _delta(other, data.damage, other.damage if other else 0.0))
				rows.append(["CARD_SPEED", "×" + _number(data.attack_speed)]
					+ _delta(other, data.attack_speed, other.attack_speed if other else 0.0))
				if data.armor_penetration > 0.0:
					rows.append(["CARD_PENETRATION", "%d %%" % roundi(data.armor_penetration * 100.0)]
						+ _delta(other, data.armor_penetration * 100.0,
							other.armor_penetration * 100.0 if other else 0.0))
				if data.is_melee():
					rows.append(["CARD_STAMINA_PER_HIT", _number(data.stamina_cost)]
						+ _delta(other, data.stamina_cost, other.stamina_cost if other else 0.0, false))
					rows.append(["CARD_REACH", _number(data.reach) + " m"]
						+ _delta(other, data.reach, other.reach if other else 0.0))
			if data.ammo_id != &"":
				var ammo: ItemData = Config.get_item(data.ammo_id)
				rows.append(["CARD_AMMO", ammo.get_display_name() if ammo else String(data.ammo_id), 0.0])
			if data.mining_power > 0:
				rows.append(["CARD_POWER", str(data.mining_power)]
					+ _delta(other, data.mining_power, other.mining_power if other else 0.0))
		ItemData.Category.ARMOR:
			var mine := Armor.of(data)
			var theirs := Armor.of(other)
			for kind in [ItemData.DamageKind.SLASH, ItemData.DamageKind.BLUNT, ItemData.DamageKind.PIERCE]:
				rows.append([Armor.KIND_NAMES[kind], _number(Armor.against(mine, kind))]
					+ _delta(other, Armor.against(mine, kind), Armor.against(theirs, kind)))
			var covers := Armor.describe_coverage(Armor.coverage_of(data))
			if covers != "":
				rows.append(["CARD_COVERS", covers, 0.0])
	# Lo que se puede hacer con él: comerlo, quemarlo, abrigarse...
	for item_trait in data.traits:
		if item_trait != null:
			for row in item_trait.describe():
				rows.append(row + [0.0])
	return rows


static func _delta(other: ItemData, mine: float, theirs: float, higher_better := true) -> Array:
	if other == null:
		return [0.0]
	var d := mine - theirs
	return [d if higher_better else -d, d]


static func _number(value: float) -> String:
	return ItemTrait.number(value)


func _footer(hint: String) -> void:
	if hint == "":
		return
	_column.add_child(HSeparator.new())
	var label := _label(hint, &"SlotCaption")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _present() -> void:
	visible = true
	reset_size()


func _clear() -> void:
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()


func _label(text: String, variation: StringName) -> Label:
	var label := _make(text, variation)
	_column.add_child(label)
	return label


func _make(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label

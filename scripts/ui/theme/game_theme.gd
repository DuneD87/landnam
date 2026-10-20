class_name GameTheme
extends RefCounted

## Saga, el aspecto de toda la interfaz: placas de hierro oscuro translúcido, superficies de
## cuero, filetes y remaches de bronce y texto color hueso. Las esquinas van biseladas, no
## redondeadas (StyleBoxFlat con corner_detail = 1, o SagaFrame en las ventanas). Los títulos
## usan Cinzel y el texto Alegreya Sans (fonts/, licencia OFL).
##
## Las medidas son para 1440 px de alto y build() las multiplica por `ui_scale` (scale_for()),
## porque el proyecto no estira la UI. Los huecos de objeto leen su lado de las constantes del
## tipo "ItemSlot", así que cambiar de tema también los redimensiona. Ver docs/ui.md.

# --- Paleta ---------------------------------------------------------------------------------------

## Paneles y ventanas.
const IRON := Color(0.043, 0.047, 0.054, 0.93)
## Campos de texto, huecos vacíos y pistas de barras.
const IRON_DEEP := Color(0.02, 0.022, 0.027, 0.9)
## Botones y huecos con objeto.
const LEATHER := Color("211b15")
const LEATHER_LIGHT := Color("2f261d")
const BRONZE := Color("c9a46a")
const BRONZE_DARK := Color("6e5a38")
## Filetes: el normal, el de los bordes discretos y el más tenue.
const BRONZE_LINE := Color(0.79, 0.64, 0.42, 0.36)
const BRONZE_FAINT := Color(0.79, 0.64, 0.42, 0.14)
const BONE := Color("ece6da")
const MUTED := Color("9c968c")
## Texto sobre bronce.
const INK := Color("16130f")
## Vida, daño y lo que empeora.
const BLOOD := Color("b23a2e")
## Aguante y lo que mejora.
const MOSS := Color("8aab5e")
## Lo que se lleva puesto en la otra mano.
const FROST := Color("8db4d0")

# --- Fuentes --------------------------------------------------------------------------------------

const _CINZEL := preload("res://fonts/Cinzel-Variable.ttf")
const _ALEGREYA := preload("res://fonts/AlegreyaSans-Regular.ttf")
const _ALEGREYA_MEDIUM := preload("res://fonts/AlegreyaSans-Medium.ttf")
const _ALEGREYA_BOLD := preload("res://fonts/AlegreyaSans-Bold.ttf")
const _ALEGREYA_ITALIC := preload("res://fonts/AlegreyaSans-Italic.ttf")

## Lado de los huecos de objeto, por uso (constantes del tipo "ItemSlot"): los de la ventana de
## fabricar son las recetas, lo que piden y el objeto elegido en grande.
const SLOT_SIDES := {&"inventory": 112, &"equipment": 112, &"hotbar": 92, &"held": 96, &"recipe": 104,
	&"ingredient": 64, &"preview": 150}


## Factor de la UI para una ventana de este tamaño (1 a 1440 px de alto).
static func scale_for(viewport: Viewport) -> float:
	return clampf(viewport.get_visible_rect().size.y / 1440.0, 0.5, 2.0)


## Títulos: Cinzel seminegrita, algo espaciada.
static func title_font(ui_scale := 1.0, weight := 600) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = _CINZEL
	var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
	font.variation_opentype = {tag: weight}
	font.spacing_glyph = roundi(1.5 * ui_scale)
	return font


static func body_font() -> Font:
	return _ALEGREYA


static func medium_font() -> Font:
	return _ALEGREYA_MEDIUM


static func bold_font() -> Font:
	return _ALEGREYA_BOLD


static func build(ui_scale: float) -> Theme:
	var theme := Theme.new()
	var px := func(value: float) -> int: return maxi(1, roundi(value * ui_scale))
	var title := title_font(ui_scale)
	theme.default_font = _ALEGREYA
	theme.default_font_size = px.call(28)

	# Textos. Las variaciones con fuente propia la declaran; el resto usa la de por defecto.
	theme.set_color("font_color", "Label", BONE)
	for variation in [
			# nombre, base, fuente, tamaño, color
			["TitleLabel", "Label", title, 44, BRONZE],
			["HeaderLabel", "Label", title, 30, BONE],
			["SectionLabel", "Label", title, 24, BRONZE],
			["CardTitle", "Label", title, 30, BONE],
			["HintLabel", "Label", _ALEGREYA_ITALIC, 23, MUTED],
			["ValueLabel", "Label", _ALEGREYA_MEDIUM, 24, BRONZE],
			["StatLabel", "Label", _ALEGREYA, 25, MUTED],
			["StatValue", "Label", _ALEGREYA_MEDIUM, 26, BONE],
			["BetterLabel", "Label", _ALEGREYA_MEDIUM, 24, MOSS],
			["WorseLabel", "Label", _ALEGREYA_MEDIUM, 24, BLOOD],
			["SlotCount", "Label", _ALEGREYA_BOLD, 24, BONE],
			["SlotKey", "Label", _ALEGREYA_MEDIUM, 19, MUTED],
			["SlotCaption", "Label", _ALEGREYA_MEDIUM, 20, MUTED]]:
		theme.set_type_variation(variation[0], variation[1])
		theme.set_font("font", variation[0], variation[2])
		theme.set_font_size("font_size", variation[0], px.call(variation[3]))
		theme.set_color("font_color", variation[0], variation[4])
	for outlined in ["SlotCount", "SlotKey"]:
		theme.set_color("font_outline_color", outlined, Color(0, 0, 0, 0.9))
		theme.set_constant("outline_size", outlined, px.call(5))
	# Las ayudas también van sobre el 3D (la piel clara de la vista previa): un contorno suave.
	theme.set_color("font_outline_color", "HintLabel", Color(0, 0, 0, 0.55))
	theme.set_constant("outline_size", "HintLabel", px.call(4))

	# Ventanas y placas.
	theme.set_stylebox("panel", "PanelContainer", window_frame(ui_scale))
	theme.set_type_variation("WindowPanel", "PanelContainer")
	theme.set_stylebox("panel", "WindowPanel", window_frame(ui_scale))
	theme.set_type_variation("Card", "PanelContainer")
	var card := window_frame(ui_scale)
	card.fill = Color(0.03, 0.033, 0.038, 0.97)
	card.chamfer = px.call(10)
	card.inset = px.call(4)
	card.rivet = px.call(3)
	card.set_content_margin_all(px.call(22))
	theme.set_stylebox("panel", "Card", card)
	# La barra rápida va hundida en la consola de hierro (VitalsPlate): un fondo oscuro con su filete.
	theme.set_type_variation("HotbarPanel", "PanelContainer")
	var strip := window_frame(ui_scale)
	strip.fill = Color(IRON_DEEP, 0.9)
	strip.chamfer = px.call(10)
	strip.inset = 0.0
	strip.rivet = 0.0
	strip.set_content_margin_all(px.call(10))
	theme.set_stylebox("panel", "HotbarPanel", strip)
	theme.set_type_variation("Inset", "PanelContainer")
	theme.set_stylebox("panel", "Inset", box(IRON_DEEP, 8, 16, 1, BRONZE_FAINT, ui_scale))

	# Huecos de objeto (ItemSlotView): vacío, con objeto, bajo el ratón, elegido, en la otra
	# mano y el que va en el cursor.
	for side in SLOT_SIDES:
		theme.set_constant(side, "ItemSlot", px.call(SLOT_SIDES[side]))
	var slot_margin := 10
	var slots := {
		"SlotEmpty": box(Color(IRON_DEEP, 0.72), 8, slot_margin, 1, BRONZE_FAINT, ui_scale),
		"Slot": box(LEATHER, 8, slot_margin, 1, BRONZE_LINE, ui_scale),
		"SlotHover": box(LEATHER_LIGHT, 8, slot_margin, 1, BRONZE, ui_scale),
		"SlotSelected": glow(box(LEATHER_LIGHT, 8, slot_margin, 2, BRONZE, ui_scale), BRONZE, ui_scale),
		"SlotEquipped": box(Color("1c232a"), 8, slot_margin, 2, FROST, ui_scale),
		"SlotHeld": glow(box(LEATHER_LIGHT, 8, slot_margin, 2, BRONZE, ui_scale), Color.BLACK, ui_scale),
	}
	for variation in slots:
		theme.set_type_variation(variation, "PanelContainer")
		theme.set_stylebox("panel", variation, slots[variation])
	# La barra conserva su talla y sus medidas; los huecos reservan un pie para los atajos.
	for state in ["SlotEmpty", "Slot", "SlotHover", "SlotSelected", "SlotEquipped", "SlotHeld"]:
		var frame := HotbarSlotFrame.new()
		frame.ui_scale = ui_scale
		frame.empty = state == "SlotEmpty"
		frame.fill = Color("151512") if frame.empty else Color("29231b")
		frame.accent = FROST if state == "SlotEquipped" else BRONZE
		if state in ["SlotSelected", "SlotHeld", "SlotEquipped"]:
			frame.emphasis = 1.0
			frame.fill = Color("202b30") if state == "SlotEquipped" else Color("3b3021")
		elif state == "SlotHover":
			frame.emphasis = 0.35
			frame.fill = Color("352d22")
		frame.set_content_margin_all(0)
		theme.set_type_variation("Hotbar" + state, "PanelContainer")
		theme.set_stylebox("panel", "Hotbar" + state, frame)

	# Botones.
	var margin := 14
	theme.set_stylebox("normal", "Button", box(LEATHER, 6, margin, 1, BRONZE_FAINT, ui_scale))
	theme.set_stylebox("hover", "Button", box(LEATHER_LIGHT, 6, margin, 1, BRONZE_LINE, ui_scale))
	theme.set_stylebox("pressed", "Button", box(BRONZE_DARK, 6, margin, 1, BRONZE, ui_scale))
	theme.set_stylebox("hover_pressed", "Button", box(BRONZE_DARK.lightened(0.08), 6, margin, 1, BRONZE, ui_scale))
	theme.set_stylebox("disabled", "Button", box(Color(IRON_DEEP, 0.6), 6, margin, 1, Color(1, 1, 1, 0.04), ui_scale))
	theme.set_stylebox("focus", "Button", box(Color.TRANSPARENT, 6, margin, 1, BRONZE, ui_scale))
	theme.set_font("font", "Button", _ALEGREYA_MEDIUM)
	theme.set_color("font_color", "Button", BONE)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", BONE)
	theme.set_color("font_disabled_color", "Button", Color(MUTED, 0.55))

	# El botón principal de cada pantalla: bronce, con la fuente de los títulos.
	theme.set_type_variation("AccentButton", "Button")
	theme.set_stylebox("normal", "AccentButton", box(BRONZE_DARK, 8, 18, 1, BRONZE, ui_scale))
	theme.set_stylebox("hover", "AccentButton", box(BRONZE, 8, 18, 1, BRONZE.lightened(0.2), ui_scale))
	theme.set_stylebox("pressed", "AccentButton", box(BRONZE.lightened(0.1), 8, 18, 1, BONE, ui_scale))
	theme.set_stylebox("disabled", "AccentButton", box(Color(IRON_DEEP, 0.6), 8, 18, 1, BRONZE_FAINT, ui_scale))
	theme.set_font("font", "AccentButton", title)
	theme.set_font_size("font_size", "AccentButton", px.call(28))
	theme.set_color("font_hover_color", "AccentButton", INK)
	theme.set_color("font_pressed_color", "AccentButton", INK)

	# Pestañas: texto subrayado en bronce la elegida.
	theme.set_type_variation("TabButton", "Button")
	var tab := func(line: Color) -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = Color.TRANSPARENT
		style.border_color = line
		style.border_width_bottom = px.call(2)
		style.content_margin_left = px.call(6)
		style.content_margin_right = px.call(6)
		style.content_margin_top = px.call(6)
		style.content_margin_bottom = px.call(8)
		return style
	theme.set_stylebox("normal", "TabButton", tab.call(Color.TRANSPARENT))
	theme.set_stylebox("hover", "TabButton", tab.call(BRONZE_LINE))
	theme.set_stylebox("pressed", "TabButton", tab.call(BRONZE))
	theme.set_stylebox("hover_pressed", "TabButton", tab.call(BRONZE))
	theme.set_stylebox("focus", "TabButton", StyleBoxEmpty.new())
	theme.set_color("font_color", "TabButton", MUTED)
	theme.set_color("font_hover_color", "TabButton", BONE)
	theme.set_color("font_pressed_color", "TabButton", BRONZE)
	theme.set_color("font_hover_pressed_color", "TabButton", BRONZE)
	theme.set_font_size("font_size", "TabButton", px.call(25))

	# Barra de categorías: texto a la izquierda y, la elegida, con una barra de bronce delante.
	theme.set_type_variation("RailButton", "Button")
	var rail := func(fill: Color, bar: Color) -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = fill
		style.border_color = bar
		style.border_width_left = px.call(3)
		style.content_margin_left = px.call(18)
		style.content_margin_right = px.call(12)
		style.content_margin_top = px.call(9)
		style.content_margin_bottom = px.call(9)
		return style
	theme.set_stylebox("normal", "RailButton", rail.call(Color.TRANSPARENT, Color.TRANSPARENT))
	theme.set_stylebox("hover", "RailButton", rail.call(Color(1, 1, 1, 0.03), BRONZE_FAINT))
	theme.set_stylebox("pressed", "RailButton", rail.call(Color(BRONZE, 0.09), BRONZE))
	theme.set_stylebox("hover_pressed", "RailButton", rail.call(Color(BRONZE, 0.12), BRONZE))
	theme.set_stylebox("focus", "RailButton", StyleBoxEmpty.new())
	theme.set_color("font_color", "RailButton", MUTED)
	theme.set_color("font_hover_color", "RailButton", BONE)
	theme.set_color("font_pressed_color", "RailButton", BRONZE)
	theme.set_color("font_hover_pressed_color", "RailButton", BRONZE)
	theme.set_font_size("font_size", "RailButton", px.call(27))

	# Fichas con miniatura (peinados, rostros...): la imagen arriba y el nombre debajo.
	theme.set_type_variation("Tile", "Button")
	theme.set_stylebox("normal", "Tile", box(Color(IRON_DEEP, 0.8), 8, 8, 1, BRONZE_FAINT, ui_scale))
	theme.set_stylebox("hover", "Tile", box(LEATHER_LIGHT, 8, 8, 1, BRONZE_LINE, ui_scale))
	theme.set_stylebox("pressed", "Tile", glow(box(LEATHER_LIGHT, 8, 8, 2, BRONZE, ui_scale), BRONZE, ui_scale))
	theme.set_stylebox("hover_pressed", "Tile", glow(box(LEATHER_LIGHT, 8, 8, 2, BRONZE, ui_scale), BRONZE, ui_scale))
	theme.set_stylebox("focus", "Tile", StyleBoxEmpty.new())
	theme.set_font_size("font_size", "Tile", px.call(21))
	theme.set_color("font_color", "Tile", MUTED)
	theme.set_color("font_hover_color", "Tile", BONE)
	theme.set_color("font_pressed_color", "Tile", BRONZE)
	theme.set_color("font_hover_pressed_color", "Tile", BRONZE)

	# Menú principal: el nombre del juego y botones de solo texto, con una barra de bronce delante
	# del que tiene el ratón.
	theme.set_type_variation("MenuTitle", "Label")
	var big_title := title_font(ui_scale, 700)
	big_title.spacing_glyph = roundi(8 * ui_scale)
	theme.set_font("font", "MenuTitle", big_title)
	theme.set_font_size("font_size", "MenuTitle", px.call(120))
	theme.set_color("font_color", "MenuTitle", BRONZE)
	theme.set_color("font_shadow_color", "MenuTitle", Color(0, 0, 0, 0.6))
	theme.set_constant("shadow_offset_y", "MenuTitle", px.call(4))
	theme.set_type_variation("SagaMenuButton", "Button")
	var entry := func(fill: Color, bar: Color) -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = fill
		style.border_color = bar
		style.border_width_left = px.call(3)
		style.content_margin_left = px.call(26)
		style.content_margin_right = px.call(26)
		style.content_margin_top = px.call(12)
		style.content_margin_bottom = px.call(12)
		return style
	theme.set_stylebox("normal", "SagaMenuButton", entry.call(Color.TRANSPARENT, Color.TRANSPARENT))
	theme.set_stylebox("hover", "SagaMenuButton", entry.call(Color(BRONZE, 0.1), BRONZE))
	theme.set_stylebox("pressed", "SagaMenuButton", entry.call(Color(BRONZE, 0.18), BRONZE))
	theme.set_stylebox("disabled", "SagaMenuButton", entry.call(Color.TRANSPARENT, Color.TRANSPARENT))
	theme.set_stylebox("focus", "SagaMenuButton", entry.call(Color.TRANSPARENT, BRONZE_LINE))
	theme.set_font("font", "SagaMenuButton", title)
	theme.set_font_size("font_size", "SagaMenuButton", px.call(38))
	theme.set_color("font_color", "SagaMenuButton", BONE)
	theme.set_color("font_hover_color", "SagaMenuButton", BRONZE)
	theme.set_color("font_pressed_color", "SagaMenuButton", BRONZE.lightened(0.2))
	theme.set_color("font_focus_color", "SagaMenuButton", BONE)
	theme.set_color("font_disabled_color", "SagaMenuButton", Color(MUTED, 0.5))
	theme.set_color("font_outline_color", "SagaMenuButton", Color(0, 0, 0, 0.5))
	theme.set_constant("outline_size", "SagaMenuButton", px.call(4))

	# Cerrar: una aspa sin placa.
	theme.set_type_variation("CloseButton", "Button")
	var bare := StyleBoxEmpty.new()
	bare.set_content_margin_all(px.call(6))
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		theme.set_stylebox(state, "CloseButton", bare)
	theme.set_font("font", "CloseButton", _ALEGREYA)
	theme.set_font_size("font_size", "CloseButton", px.call(44))
	theme.set_color("font_color", "CloseButton", MUTED)
	theme.set_color("font_hover_color", "CloseButton", BRONZE)
	theme.set_color("font_pressed_color", "CloseButton", BONE)

	var field := box(IRON_DEEP, 6, 14, 1, BRONZE_FAINT, ui_scale)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", box(Color.TRANSPARENT, 6, 14, 1, BRONZE, ui_scale))
	theme.set_color("font_color", "LineEdit", BONE)
	theme.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.7))
	theme.set_color("caret_color", "LineEdit", BRONZE)
	theme.set_font_size("font_size", "LineEdit", px.call(30))

	# Cantidades: el campo de LineEdit con dos flechas de bronce a la derecha, una sobre otra.
	var arrow_side: int = px.call(18)
	theme.set_icon("up", "SpinBox", chevron_icon(arrow_side, true))
	theme.set_icon("down", "SpinBox", chevron_icon(arrow_side, false))
	for state in ["", "_hover", "_pressed", "_disabled"]:
		theme.set_icon("up" + state, "SpinBox", chevron_icon(arrow_side, true))
		theme.set_icon("down" + state, "SpinBox", chevron_icon(arrow_side, false))
	for half in ["up", "down"]:
		theme.set_stylebox(half + "_background", "SpinBox", box(LEATHER, 4, 0, 1, BRONZE_FAINT, ui_scale))
		theme.set_stylebox(half + "_background_hovered", "SpinBox", box(LEATHER_LIGHT, 4, 0, 1, BRONZE_LINE, ui_scale))
		theme.set_stylebox(half + "_background_pressed", "SpinBox", box(BRONZE_DARK, 4, 0, 1, BRONZE, ui_scale))
		theme.set_stylebox(half + "_background_disabled", "SpinBox", box(Color(IRON_DEEP, 0.6), 4, 0, 1, Color(1, 1, 1, 0.04), ui_scale))
		theme.set_color(half + "_icon_modulate", "SpinBox", BONE)
		theme.set_color(half + "_hover_icon_modulate", "SpinBox", Color.WHITE)
		theme.set_color(half + "_pressed_icon_modulate", "SpinBox", INK)
		theme.set_color(half + "_disabled_icon_modulate", "SpinBox", Color(MUTED, 0.5))
	theme.set_stylebox("field_and_buttons_separator", "SpinBox", StyleBoxEmpty.new())
	theme.set_stylebox("up_down_buttons_separator", "SpinBox", StyleBoxEmpty.new())
	theme.set_constant("buttons_width", "SpinBox", px.call(40))
	theme.set_constant("field_and_buttons_separation", "SpinBox", px.call(6))
	theme.set_constant("buttons_vertical_separation", "SpinBox", px.call(3))
	theme.set_constant("set_min_buttons_width_from_icons", "SpinBox", 0)

	var track := box(Color(1, 1, 1, 0.1), 2, 0, 0, Color.TRANSPARENT, ui_scale)
	track.content_margin_top = px.call(3)
	track.content_margin_bottom = px.call(3)
	var filled := box(BRONZE_DARK, 2, 0, 0, Color.TRANSPARENT, ui_scale)
	filled.content_margin_top = px.call(3)
	filled.content_margin_bottom = px.call(3)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	theme.set_icon("grabber", "HSlider", diamond_icon(px.call(30), BONE))
	theme.set_icon("grabber_highlight", "HSlider", diamond_icon(px.call(32), BRONZE))

	theme.set_stylebox("scroll", "VScrollBar", box(Color(1, 1, 1, 0.04), 2, 0, 0, Color.TRANSPARENT, ui_scale))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var grabber := box(BRONZE_DARK if state == "grabber" else BRONZE, 2, 0, 0, Color.TRANSPARENT, ui_scale)
		grabber.content_margin_left = px.call(4)
		grabber.content_margin_right = px.call(4)
		theme.set_stylebox(state, "VScrollBar", grabber)

	# Barras de vida y aguante.
	theme.set_stylebox("background", "ProgressBar", box(IRON_DEEP, 3, 0, 1, BRONZE_FAINT, ui_scale))
	theme.set_stylebox("fill", "ProgressBar", box(BRONZE_DARK, 3, 0, 0, Color.TRANSPARENT, ui_scale))
	for bar in [["HealthBar", BLOOD], ["StaminaBar", MOSS]]:
		theme.set_type_variation(bar[0], "ProgressBar")
		theme.set_stylebox("fill", bar[0], box(bar[1].darkened(0.15), 3, 0, 0, Color.TRANSPARENT, ui_scale))

	# Desplegables, interruptores y la ayuda que sale al dejar el ratón encima.
	theme.set_stylebox("panel", "PopupMenu", box(Color(0.03, 0.033, 0.038, 0.98), 8, 10, 1, BRONZE_LINE, ui_scale))
	theme.set_stylebox("hover", "PopupMenu", box(BRONZE_DARK, 4, 8, 0, Color.TRANSPARENT, ui_scale))
	theme.set_font("font", "PopupMenu", _ALEGREYA)
	theme.set_color("font_color", "PopupMenu", BONE)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_color("font_disabled_color", "PopupMenu", MUTED)
	theme.set_font_size("font_size", "PopupMenu", px.call(27))
	theme.set_constant("v_separation", "PopupMenu", px.call(14))
	theme.set_constant("item_start_padding", "PopupMenu", px.call(14))
	theme.set_constant("item_end_padding", "PopupMenu", px.call(14))
	var plain := StyleBoxEmpty.new()
	plain.set_content_margin_all(px.call(8))
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		theme.set_stylebox(state, "CheckButton", plain)
	# El interruptor por defecto mide lo mismo a cualquier escala y a 1440 px apenas se ve.
	for icon in ["checked", "checked_mirrored"]:
		theme.set_icon(icon, "CheckButton", switch_icon(true, ui_scale))
	for icon in ["unchecked", "unchecked_mirrored"]:
		theme.set_icon(icon, "CheckButton", switch_icon(false, ui_scale))
	var tooltip := window_frame(ui_scale)
	tooltip.chamfer = px.call(6)
	tooltip.inset = 0.0
	tooltip.rivet = 0.0
	tooltip.set_content_margin_all(px.call(12))
	theme.set_stylebox("panel", "TooltipPanel", tooltip)
	theme.set_color("font_color", "TooltipLabel", BONE)
	theme.set_font_size("font_size", "TooltipLabel", px.call(23))

	var rule := SagaRule.new()
	rule.thickness = maxf(1.0, roundf(ui_scale))
	rule.diamond = px.call(4)
	rule.gap = px.call(8)
	theme.set_stylebox("separator", "HSeparator", rule)
	theme.set_constant("separation", "HSeparator", px.call(22))
	theme.set_constant("separation", "VBoxContainer", px.call(12))
	theme.set_constant("separation", "HBoxContainer", px.call(12))
	theme.set_constant("h_separation", "HFlowContainer", px.call(10))
	theme.set_constant("v_separation", "HFlowContainer", px.call(10))
	theme.set_constant("h_separation", "GridContainer", px.call(10))
	theme.set_constant("v_separation", "GridContainer", px.call(10))
	return theme


## Marco de ventana: placa biselada con filete interior y remaches.
static func window_frame(ui_scale: float) -> SagaFrame:
	var frame := SagaFrame.new()
	frame.fill = IRON
	frame.border = BRONZE_LINE
	frame.border_width = maxf(1.0, roundf(ui_scale))
	frame.chamfer = roundf(16 * ui_scale)
	frame.inset = roundf(7 * ui_scale)
	frame.inset_color = BRONZE_FAINT
	frame.rivet = roundf(4 * ui_scale)
	frame.rivet_color = BRONZE
	frame.set_content_margin_all(roundf(30 * ui_scale))
	return frame


## Muestra de color: el color mismo, con un filete de bronce si es el elegido.
static func swatch(color: Color, selected: bool, ui_scale: float) -> StyleBoxFlat:
	var border := BRONZE if selected else Color(1, 1, 1, 0.15)
	return box(color, 6, 0, 3 if selected else 1, border, ui_scale)


## Placa con las esquinas biseladas. Radio, margen y borde en la escala base.
static func box(color: Color, cut: float, margin: float, border: int, border_color: Color, ui_scale: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(roundi(cut * ui_scale))
	# Un solo punto por esquina: bisel en vez de curva.
	style.corner_detail = 1
	style.set_content_margin_all(roundf(margin * ui_scale))
	style.set_border_width_all(maxi(1, roundi(border * ui_scale)) if border > 0 else 0)
	style.border_color = border_color
	style.anti_aliasing = true
	return style


## La misma placa con un halo alrededor.
static func glow(style: StyleBoxFlat, color: Color, ui_scale: float) -> StyleBoxFlat:
	style.shadow_color = Color(color, 0.35)
	style.shadow_size = roundi(8 * ui_scale)
	return style


## Rombo con el borde suavizado (el tirador de los sliders).
static func diamond_icon(size: int, color: Color) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := size * 0.5
	for y in size:
		for x in size:
			var d := absf(x + 0.5 - half) + absf(y + 0.5 - half)
			image.set_pixel(x, y, Color(color, clampf((half - 1.0 - d) * 0.75, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)


## Flecha en ángulo (hacia arriba o hacia abajo), blanca: el tema la tiñe con su modulate.
static func chevron_icon(size: int, up: bool) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := size * 0.5
	var thick := maxf(1.5, size * 0.14)
	for y in size:
		for x in size:
			var px := x + 0.5 - half
			var py := (y + 0.5 - half) * (1.0 if up else -1.0)
			# Dos trazos que se juntan en la punta, algo por encima del centro.
			var d := absf(py - absf(px) * 0.9 + size * 0.14) / 1.35
			var inside := absf(px) <= half * 0.62
			image.set_pixel(x, y, Color(1, 1, 1, clampf(thick * 0.5 - d + 0.5, 0.0, 1.0) if inside else 0.0))
	return ImageTexture.create_from_image(image)


## Pastilla del interruptor, con el botón a la derecha (encendido, en bronce) o a la izquierda.
static func switch_icon(on: bool, ui_scale: float) -> ImageTexture:
	var height := roundi(34 * ui_scale)
	var width := roundi(64 * ui_scale)
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var track := BRONZE_DARK if on else Color(1, 1, 1, 0.16)
	var knob := BRONZE if on else MUTED
	var radius := height * 0.5
	var knob_center := Vector2(width - radius if on else radius, radius)
	for y in height:
		for x in width:
			var p := Vector2(x, y) + Vector2(0.5, 0.5)
			var nearest := Vector2(clampf(p.x, radius, width - radius), radius)
			var track_alpha := clampf(radius - p.distance_to(nearest), 0.0, 1.0)
			var knob_alpha := clampf(radius - 5.0 * ui_scale - p.distance_to(knob_center), 0.0, 1.0)
			image.set_pixel(x, y, Color(track, track.a * track_alpha).blend(Color(knob, knob_alpha)))
	return ImageTexture.create_from_image(image)

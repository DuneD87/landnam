class_name Furnace
extends Node3D

## Horno de fundición de la Edad del bronce, plantado en el suelo como la hoguera (lo planta
## SurvivalActions desde su objeto). Se ve con FurnaceVisual: una cuba de barro sobre un zócalo de
## piedras, con la boca delante y el fuelle de piel al lado. Tiene un hueco de combustible, que solo
## acepta lo que calienta para fundir (FuelTrait.smelt_heat: la madera poco, el carbón del todo),
## cuatro de crisol para la mena y dos de salida.
##
## Encendido, quema el combustible de una unidad en una unidad, como la hoguera, y funde lo del
## crisol con sus recetas (RecipeData con station = el horno y su time): cada segundo de fuego suma
## el calor de la pieza que arde y, al llegar al tiempo de la receta, gasta lo que pide y pone lo
## que sale en la salida. Con la salida llena, espera. De las recetas que se pueden hacer con lo del
## crisol, la que junta más cosas distintas: la aleación antes que un metal solo. Da algo de calor y
## de luz. Se abre con E en la columna de la derecha del inventario (InventoryUI.open_furnace) y se
## guarda con la partida. Ver docs/items.md.

signal changed

const GROUP := &"furnace"
const ITEM_ID := &"smelting_furnace"
const FUEL_SLOT := 0
## Huecos del crisol (1-4) y de la salida (5-6).
const ORE_SLOTS := 4
const OUT_SLOTS := 2
const FIRST_OUT := 1 + ORE_SLOTS
## Distancia desde la que se abre (m, desde los pies).
const REACH := 2.6
## Calor a pie de horno (°C) y hasta dónde llega; luz, igual. Menos que la hoguera: el fuego va
## dentro.
const HEAT := 10.0
const HEAT_RADIUS := 4.0
const LIGHT_RADIUS := 6.0
const VISUAL := preload("res://scenes/world/smelting_furnace_visual.tscn")
const FLAME_MATERIAL := preload("res://data/resources/torch_flame_material.tres")
const FIRE_SCRIPT := preload("res://scripts/effects/volumetric_fire.gd")
const AUDIO_SCRIPT := preload("res://scripts/audio/entity_audio.gd")

var entity_id := ""
var save_category := "planet"
var discard_on_load := true
## El barco del que colgaba al guardar (GroundPlaceableTrait.restore_ship).
var _ship_id := ""
var inventory := Inventory.new()
var lit := false
## Segundos que le quedan al combustible que arde ahora, los que daba entero (para la barra) y lo
## que funde (FuelTrait.smelt_heat).
var fuel_left := 0.0
var fuel_total := 0.0
var fuel_heat := 0.0
## Calor que lleva la receta que funde (segundos a pleno calor, como RecipeData.time).
var progress := 0.0

## La receta a la que va el calor: si cambia lo del crisol y sale otra, se empieza de cero.
var _recipe: RecipeData
var _visual: FurnaceVisual
var _flame: MeshInstance3D
var _light: OmniLight3D
var _audio: Node
var _ui_tick := 0.0


func _init() -> void:
	inventory.max_slots = FIRST_OUT + OUT_SLOTS
	inventory.rules = FurnaceInventoryRules.new()


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(GroundPlaceableTrait.PLACED_GROUP)
	add_to_group(GameManager.SAVEABLE_GROUP)
	if entity_id == "":
		entity_id = "furnace_%d_%d" % [Time.get_unix_time_from_system(), randi()]
	add_child(inventory)
	_visual = VISUAL.instantiate()
	add_child(_visual)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = FurnaceVisual.RADIUS
	cylinder.height = FurnaceVisual.HEIGHT
	shape.shape = cylinder
	shape.position.y = FurnaceVisual.HEIGHT * 0.5
	body.add_child(shape)
	add_child(body)
	# Antes que la llama y con este nombre: VolumetricFire la busca al arrancar para hacerla parpadear.
	# Delante de la boca, para que alumbre el suelo de donde se trabaja.
	_light = OmniLight3D.new()
	_light.name = "OmniLight3D"
	_light.light_color = Color(1.0, 0.6, 0.32)
	_light.light_energy = 2.2
	_light.omni_range = LIGHT_RADIUS + 2.0
	_light.shadow_enabled = true
	_light.distance_fade_enabled = true
	_light.distance_fade_shadow = 20.0
	_light.position = FurnaceVisual.MOUTH + Vector3(0.0, 0.05, 0.25)
	add_child(_light)
	# La llama asoma por la chimenea.
	_flame = MeshInstance3D.new()
	var quad := QuadMesh.new()
	var material := FLAME_MATERIAL.duplicate() as ShaderMaterial
	material.set_shader_parameter(&"fire_height", 0.45)
	material.set_shader_parameter(&"fire_width", 0.22)
	quad.material = material
	_flame.mesh = quad
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.extra_cull_margin = 2.0
	_flame.position.y = FurnaceVisual.HEIGHT - 0.06
	_flame.set_script(FIRE_SCRIPT)
	add_child(_flame)
	_audio = Node.new()
	_audio.set_script(AUDIO_SCRIPT)
	_audio.set(&"loop_event", &"fire_loop")
	_audio.set(&"loop_autostart", false)
	_light.add_child(_audio)
	_apply_lit()


func _process(delta: float) -> void:
	if not lit:
		return
	advance(WorldTime.scaled_delta(delta))
	_ui_tick -= delta
	if _ui_tick <= 0.0:
		_ui_tick = 0.2
		_point_flame()
		changed.emit()


## Consume todo el tiempo, aunque pase por varias piezas de combustible, y funde con el calor de
## cada una mientras ha ardido.
func advance(seconds: float) -> void:
	if not lit or seconds <= 0.0:
		return
	var remaining := seconds
	while remaining > 0.0:
		if fuel_left <= 0.0 and not _take_fuel():
			fuel_left = 0.0
			break
		var step := minf(remaining, fuel_left)
		fuel_left = maxf(fuel_left - step, 0.0)
		remaining -= step
		_smelt(step * fuel_heat)
	if fuel_left <= 0.0 and not has_fuel():
		extinguish()


## Si [data] va en el hueco [slot] (0 = combustible; 1-4, crisol; la salida, nada).
func accepts(slot: int, data: ItemData) -> bool:
	return inventory.accepts(slot, data)


## Lo que funde en el horno (va en el crisol): lo que pide alguna de sus recetas.
static func smelts(id: StringName) -> bool:
	for recipe in Recipes.of_station(ITEM_ID):
		if recipe.inputs.has(id):
			return true
	return false


## Enciende si tiene con qué arder.
func ignite() -> bool:
	if lit:
		return true
	if fuel_left <= 0.0 and not _take_fuel():
		return false
	lit = true
	_apply_lit()
	changed.emit()
	return true


func extinguish() -> void:
	lit = false
	_apply_lit()
	changed.emit()


## Hay algo que pueda arder (lo que arde ahora o en el hueco).
func has_fuel() -> bool:
	return fuel_left > 0.0 or inventory.items[FUEL_SLOT] != null


## Segundos de fuego que quedan con todo el combustible del hueco.
func burn_seconds_left() -> float:
	var total := maxf(fuel_left, 0.0)
	var stock := inventory.items[FUEL_SLOT]
	var fuel := stock.data.get_trait(FuelTrait) as FuelTrait if stock != null else null
	if fuel != null:
		total += fuel.burn_time * stock.quantity
	return total


## La receta que funde (o fundiría encendido): de las del horno que se pueden hacer con lo del
## crisol y caben en la salida, la que junta más cosas distintas; a igualdad, la primera del
## recetario. null si no hay.
func current_recipe() -> RecipeData:
	var best: RecipeData = null
	for recipe in Recipes.of_station(ITEM_ID):
		if best != null and recipe.inputs.size() <= best.inputs.size():
			continue
		if _has_inputs(recipe) and _out_room(ItemCatalog.get_item(recipe.result)) >= recipe.amount:
			best = recipe
	return best


## De 0 a 1, lo que lleva fundido la receta de ahora.
func smelt_ratio() -> float:
	var recipe := current_recipe()
	if recipe == null or recipe != _recipe:
		return 0.0
	return clampf(progress / maxf(recipe.time, 1.0), 0.0, 1.0)


func is_empty() -> bool:
	for item in inventory.items:
		if item != null:
			return false
	return true


## Calor (°C) que da en [world_pos]: lleno a pie de horno y nada pasado HEAT_RADIUS.
func heat_at(world_pos: Vector3) -> float:
	if not lit:
		return 0.0
	var t := 1.0 - global_position.distance_to(world_pos) / HEAT_RADIUS
	return HEAT * pow(clampf(t, 0.0, 1.0), 1.5)


## Luz (0-1) en [world_pos], para la cordura.
func light_at(world_pos: Vector3) -> float:
	if not lit:
		return 0.0
	return clampf(1.0 - global_position.distance_to(world_pos) / LIGHT_RADIUS, 0.0, 1.0)


## El horno más cercano a [world_pos] a menos de [reach] (m), o null.
static func nearest(tree: SceneTree, world_pos: Vector3, reach: float = REACH) -> Furnace:
	var best: Furnace = null
	var best_d := reach
	for node in tree.get_nodes_in_group(GROUP):
		var furnace := node as Furnace
		if furnace == null or not is_instance_valid(furnace):
			continue
		var d := furnace.global_position.distance_to(world_pos)
		if d <= best_d:
			best = furnace
			best_d = d
	return best


## Suma [heat] (segundos a pleno calor) a lo que se funde; al acabar una receta sigue con la
## siguiente si queda calor.
func _smelt(heat: float) -> void:
	while heat > 0.0:
		var recipe := current_recipe()
		if recipe != _recipe:
			_recipe = recipe
			progress = 0.0
		if recipe == null:
			return
		var time := maxf(recipe.time, 1.0)
		var step := minf(heat, time - progress)
		progress += step
		heat -= step
		if progress < time - 1e-4:
			return
		_finish(recipe)
		progress = 0.0


## Gasta del crisol lo que pide [recipe] y pone lo que sale en la salida.
func _finish(recipe: RecipeData) -> void:
	for id: StringName in recipe.inputs:
		var left: int = recipe.inputs[id]
		for slot in range(1, FIRST_OUT):
			var item := inventory.items[slot]
			if left <= 0 or item == null or item.data.id != id:
				continue
			var taken := mini(left, item.quantity)
			item.remove(taken)
			left -= taken
			if item.is_empty():
				inventory.items[slot] = null
	var result: ItemData = ItemCatalog.get_item(recipe.result)
	var left := recipe.amount
	# Primero sobre lo que ya hay de eso, luego en un hueco libre. La salida no admite nada de
	# fuera (FurnaceInventoryRules), así que se pone a mano.
	for pass_empty in [false, true]:
		for slot in range(FIRST_OUT, FIRST_OUT + OUT_SLOTS):
			if left <= 0:
				break
			var item := inventory.items[slot]
			if item == null and pass_empty:
				var put := mini(left, maxi(result.max_stack, 1) if result.stackable else 1)
				inventory.items[slot] = InventoryItem.new(result, put)
				left -= put
			elif item != null and not pass_empty and item.data.id == result.id:
				left = item.add(left)
	inventory.inventory_changed.emit()


func _has_inputs(recipe: RecipeData) -> bool:
	for id: StringName in recipe.inputs:
		var have := 0
		for slot in range(1, FIRST_OUT):
			var item := inventory.items[slot]
			if item != null and item.data.id == id:
				have += item.quantity
		if have < recipe.inputs[id]:
			return false
	return true


## Cuántos de [data] caben todavía en la salida.
func _out_room(data: ItemData) -> int:
	if data == null:
		return 0
	var stack := maxi(data.max_stack, 1) if data.stackable else 1
	var room := 0
	for slot in range(FIRST_OUT, FIRST_OUT + OUT_SLOTS):
		var item := inventory.items[slot]
		if item == null:
			room += stack
		elif item.data.id == data.id:
			room += maxi(stack - item.quantity, 0)
	return room


func _take_fuel() -> bool:
	var stock := inventory.items[FUEL_SLOT]
	var fuel := stock.data.get_trait(FuelTrait) as FuelTrait if stock != null else null
	if fuel == null:
		return false
	stock.remove(1)
	if stock.is_empty():
		inventory.items[FUEL_SLOT] = null
	fuel_total = fuel.burn_time
	fuel_left += fuel.burn_time
	fuel_heat = fuel.smelt_heat
	inventory.inventory_changed.emit()
	return true


func _apply_lit() -> void:
	if _flame == null:
		return
	_point_flame()
	_visual.set_lit(lit)
	_flame.visible = lit
	_light.visible = lit
	if _audio != null and _audio.has_method(&"set_loop_active"):
		_audio.call(&"set_loop_active", lit)


## La llama sube por la vertical del planeta, como la de la hoguera (Campfire._point_flame).
func _point_flame() -> void:
	if _flame == null or not is_inside_tree():
		return
	var planet := get_parent() as Node3D
	var up := global_position - planet.global_position if planet != null else global_basis.y
	_flame.set_instance_shader_parameter(&"up_axis", up.normalized() if up.length_squared() > 1e-6 else global_basis.y)


func get_save_data() -> Dictionary:
	var items := []
	for item in inventory.items:
		items.append([String(item.data.id), item.quantity] if item != null else null)
	var t := transform
	return {
		"basis": [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
			t.basis.z.x, t.basis.z.y, t.basis.z.z],
		"origin": [t.origin.x, t.origin.y, t.origin.z],
		"lit": lit, "fuel_left": fuel_left, "fuel_total": fuel_total, "fuel_heat": fuel_heat,
		"items": items, "progress": progress,
		"recipe": String(_recipe.result) if _recipe != null else "",
		"ship": GroundPlaceableTrait.ship_id(self),
	}


func restore_save_data(data: Dictionary) -> void:
	_ship_id = String(data.get("ship", ""))
	var b: Array = data.get("basis", [])
	var o: Array = data.get("origin", [])
	if b.size() == 9 and o.size() == 3:
		transform = Transform3D(Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])),
			Vector3(o[0], o[1], o[2]))
	var items: Array = data.get("items", [])
	for i in mini(items.size(), inventory.items.size()):
		var entry = items[i]
		var item_data: ItemData = ItemCatalog.get_item(StringName(entry[0])) if entry is Array else null
		inventory.items[i] = InventoryItem.new(item_data, int(entry[1])) if item_data != null else null
	fuel_left = float(data.get("fuel_left", 0.0))
	fuel_total = float(data.get("fuel_total", 0.0))
	fuel_heat = float(data.get("fuel_heat", 0.0))
	progress = float(data.get("progress", 0.0))
	_recipe = null
	var saved_recipe := StringName(data.get("recipe", ""))
	for recipe in Recipes.of_station(ITEM_ID):
		if recipe.result == saved_recipe:
			_recipe = recipe
	lit = bool(data.get("lit", false))
	_apply_lit()
	inventory.inventory_changed.emit()


func post_restore() -> void:
	GroundPlaceableTrait.restore_ship(self, _ship_id)

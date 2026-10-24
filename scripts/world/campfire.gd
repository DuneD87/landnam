class_name Campfire
extends Node3D

## Hoguera plantada en el suelo (la planta SurvivalActions desde el objeto «Hoguera», asentada con
## GroundFit). Se ve con CampfireVisual: el corro de piedras, la leña y la ceniza. Tiene un
## hueco de combustible, que acepta cualquier cosa que arda (FuelTrait), y ocho de cocina, de una
## pieza cada uno, para lo que se asa (CookableTrait). Encendida, va quemando el combustible de una
## unidad en una unidad y asa lo de los huecos; sin combustible, se apaga. Además da calor y luz:
## SurvivalNeeds suma el calor a la temperatura que se siente y, a su luz, la oscuridad no quita
## cordura. Se abre con E en la columna de la derecha del inventario (InventoryUI.open_campfire) y
## se guarda con la partida. Ver docs/items.md.

signal changed

const GROUP := &"campfire"
const ITEM_ID := &"campfire"
const FUEL_SLOT := 0
const COOK_SLOTS := 8
## Distancia desde la que se abre (m, desde los pies).
const REACH := 2.6
## Calor a pie de fuego (°C que se suman a lo que se siente) y hasta dónde llega; luz, igual.
const HEAT := 18.0
const HEAT_RADIUS := 6.0
const LIGHT_RADIUS := 9.0
## Al raso con temporal, la lluvia hace que se consuma antes.
const STORM_BURN := 1.6
## Lo que se ve: el corro, la leña y la ceniza (CampfireVisual).
const VISUAL := preload("res://scenes/world/campfire_visual.tscn")
const FLAME_MATERIAL := preload("res://data/resources/torch_flame_material.tres")
const FIRE_SCRIPT := preload("res://scripts/effects/volumetric_fire.gd")
const AUDIO_SCRIPT := preload("res://scripts/audio/entity_audio.gd")

var entity_id := ""
var save_category := "planet"
var discard_on_load := true
var inventory := Inventory.new()
var lit := false
## Segundos que le quedan al combustible que arde ahora, y los que daba entero (para la barra).
var fuel_left := 0.0
var fuel_total := 0.0
## Segundos de fuego que lleva cada hueco de cocina.
var progress: Array[float] = []

var _visual: CampfireVisual
var _flame: MeshInstance3D
var _light: OmniLight3D
var _audio: Node
var _ui_tick := 0.0


func _init() -> void:
	inventory.max_slots = 1 + COOK_SLOTS
	inventory.rules = CampfireInventoryRules.new()
	progress.resize(COOK_SLOTS)
	progress.fill(0.0)


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(GroundPlaceableTrait.PLACED_GROUP)
	add_to_group(GameManager.SAVEABLE_GROUP)
	if entity_id == "":
		entity_id = "campfire_%d_%d" % [Time.get_unix_time_from_system(), randi()]
	add_child(inventory)
	_visual = VISUAL.instantiate()
	add_child(_visual)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = CampfireVisual.RADIUS
	cylinder.height = 0.24
	shape.shape = cylinder
	shape.position.y = 0.1
	body.add_child(shape)
	add_child(body)
	# Antes que la llama y con este nombre: VolumetricFire la busca al arrancar para hacerla parpadear.
	_light = OmniLight3D.new()
	_light.name = "OmniLight3D"
	_light.light_color = Color(1.0, 0.68, 0.4)
	_light.light_energy = 3.0
	_light.omni_range = LIGHT_RADIUS + 3.0
	_light.shadow_enabled = true
	_light.distance_fade_enabled = true
	_light.distance_fade_shadow = 20.0
	_light.position.y = 0.5
	add_child(_light)
	_flame = MeshInstance3D.new()
	var quad := QuadMesh.new()
	var material := FLAME_MATERIAL.duplicate() as ShaderMaterial
	material.set_shader_parameter(&"fire_height", 0.75)
	material.set_shader_parameter(&"fire_width", 0.5)
	quad.material = material
	_flame.mesh = quad
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.extra_cull_margin = 2.0
	_flame.position.y = 0.04
	_flame.set_script(FIRE_SCRIPT)
	add_child(_flame)
	_audio = Node.new()
	_audio.set_script(AUDIO_SCRIPT)
	_audio.set(&"loop_event", &"fire_loop")
	_audio.set(&"loop_autostart", false)
	_flame.add_child(_audio)
	_apply_lit()


func _process(delta: float) -> void:
	if not lit:
		return
	var burn_rate := 1.0
	var weather := get_tree().get_first_node_in_group("weather")
	if weather != null and weather.get_current_weather_name() == "storm" and not weather.is_sheltered():
		burn_rate = STORM_BURN
	advance(WorldTime.scaled_delta(delta), burn_rate)
	_ui_tick -= delta
	if _ui_tick <= 0.0:
		_ui_tick = 0.2
		_point_flame()
		changed.emit()


## Consume todo el tiempo, incluso si atraviesa varias piezas de combustible. Solo se cocina
## durante el tiempo que ha habido fuego, también en la última fracción antes de apagarse.
func advance(seconds: float, burn_rate := 1.0) -> void:
	if not lit or seconds <= 0.0 or burn_rate <= 0.0:
		return
	var cooking := 0.0
	var remaining := seconds
	while remaining > 0.0:
		if fuel_left <= 0.0 and not _take_fuel():
			fuel_left = 0.0
			extinguish()
			break
		var step := minf(remaining, fuel_left / burn_rate)
		fuel_left = maxf(fuel_left - step * burn_rate, 0.0)
		remaining -= step
		cooking += step
	if fuel_left <= 0.0 and not has_fuel():
		extinguish()
	for i in COOK_SLOTS:
		var item := inventory.items[1 + i]
		var cookable := item.data.get_trait(CookableTrait) as CookableTrait if item != null else null
		if cookable == null:
			continue
		progress[i] += cooking
		if progress[i] >= cookable.cook_time:
			var result: ItemData = ItemCatalog.get_item(cookable.result)
			if result != null:
				inventory.items[1 + i] = InventoryItem.new(result, item.quantity)
			progress[i] = 0.0
			inventory.inventory_changed.emit()


## Si [data] va en el hueco [slot] (0 = combustible; 1-8, cocina).
func accepts(slot: int, data: ItemData) -> bool:
	return inventory.accepts(slot, data)


## Lo que cabe en el hueco: el de combustible, un montón; los de cocina, una pieza.
func capacity(slot: int, data: ItemData) -> int:
	return inventory.capacity(slot, data)


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
	if stock != null:
		var fuel := stock.data.get_trait(FuelTrait) as FuelTrait
		if fuel != null:
			total += fuel.burn_time * stock.quantity
	return total


## De 0 a 1, lo que lleva asado el hueco de cocina [i] (0-7).
func cook_ratio(i: int) -> float:
	var item := inventory.items[1 + i]
	var cookable := item.data.get_trait(CookableTrait) as CookableTrait if item != null else null
	if cookable == null or cookable.cook_time <= 0.0:
		return 0.0
	return clampf(progress[i] / cookable.cook_time, 0.0, 1.0)


func is_empty() -> bool:
	for item in inventory.items:
		if item != null:
			return false
	return true


## Calor (°C) que da en [world_pos]: lleno a pie de fuego y nada pasado HEAT_RADIUS.
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


## La hoguera más cercana a [world_pos] a menos de [reach] (m), o null.
static func nearest(tree: SceneTree, world_pos: Vector3, reach: float = REACH) -> Campfire:
	var best: Campfire = null
	var best_d := reach
	for node in tree.get_nodes_in_group(GROUP):
		var fire := node as Campfire
		if fire == null or not is_instance_valid(fire):
			continue
		var d := fire.global_position.distance_to(world_pos)
		if d <= best_d:
			best = fire
			best_d = d
	return best


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


## La llama sube por la vertical del planeta (la hoguera se inclina con la pendiente, el fuego
## no). VolumetricFire solo la pone si la lleva un cuerpo (una antorcha en la mano), y esta no la
## lleva nadie. La hoguera cuelga del planeta, cuyo origen es su centro.
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
		"lit": lit, "fuel_left": fuel_left, "fuel_total": fuel_total,
		"items": items, "progress": Array(progress),
	}


func restore_save_data(data: Dictionary) -> void:
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
	var saved: Array = data.get("progress", [])
	for i in mini(saved.size(), COOK_SLOTS):
		progress[i] = float(saved[i])
	fuel_left = float(data.get("fuel_left", 0.0))
	fuel_total = float(data.get("fuel_total", 0.0))
	lit = bool(data.get("lit", false))
	_apply_lit()
	inventory.inventory_changed.emit()

class_name WaterTrough
extends Node3D

## Bebedero: guarda agua en tragos, como los odres (SurvivalNeeds.water), hasta CAPACITY. De él beben
## los colonos de la base (SettlerMeals). Lo llenan el jugador (E: vierte lo que llevan sus odres y,
## si no lleva nada, bebe de él: SurvivalActions.use_trough), el aguador (SettlerWater) y la lluvia
## (la nieve, a la mitad), pero solo cerca del jugador: el tiempo es el del sitio del jugador
## (WeatherController.get_local_precipitation), como el de los poblados. Lo que tiene se guarda con
## él. Ver docs/villagers.md.

signal level_changed

const GROUP := &"water_trough"
const ITEM_ID := &"water_trough"
const REACH := 2.6
const CAPACITY := 60
## Lo que le echa la lluvia más fuerte (tragos por hora de juego); la nieve, la mitad. Solo a menos de
## RAIN_REACH m de la cámara; se mira cada RAIN_CHECK s.
const RAIN_SIPS_PER_HOUR := 4.0
const SNOW_SHARE := 0.5
const RAIN_REACH := 200.0
const RAIN_CHECK := 5.0
const VisualScript = preload("res://scripts/world/water_trough_visual.gd")

var water := 0:
	set(value):
		var clamped := clampi(value, 0, CAPACITY)
		if clamped == water:
			return
		water = clamped
		_update_surface()
		level_changed.emit()
var entity_id := ""
var save_category := "planet"
var discard_on_load := true
## El barco del que colgaba al guardar (GroundPlaceableTrait.restore_ship).
var _ship_id := ""
var _surface: MeshInstance3D
var _rain := 0.0
var _rain_left := RAIN_CHECK


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(GroundPlaceableTrait.PLACED_GROUP)
	add_to_group(GameManager.SAVEABLE_GROUP)
	if entity_id == "":
		entity_id = "water_trough_%d_%d" % [Time.get_unix_time_from_system(), randi()]
	_make_surface()
	_update_surface()


func _process(delta: float) -> void:
	_rain_left -= delta
	if _rain_left > 0.0:
		return
	var span := RAIN_CHECK - _rain_left
	_rain_left = RAIN_CHECK
	if water >= CAPACITY:
		_rain = 0.0
		return
	var falling := _precipitation()
	if falling <= 0.0:
		return
	_rain += falling * RAIN_SIPS_PER_HOUR * WorldTime.hours_elapsed(span)
	if _rain >= 1.0:
		var sips := floori(_rain)
		_rain -= sips
		water += sips


## Lo que cabe aún (tragos).
func room() -> int:
	return CAPACITY - water


## Echa hasta [amount] tragos; devuelve los que caben.
func pour(amount: int) -> int:
	var added := mini(maxi(amount, 0), room())
	water += added
	return added


## Saca hasta [amount] tragos; devuelve los que había.
func take(amount: int) -> int:
	var taken := mini(maxi(amount, 0), water)
	water -= taken
	return taken


## Cuánto llueve (0-1) encima, si está cerca del jugador; la nieve cuenta SNOW_SHARE.
func _precipitation() -> float:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or camera.global_position.distance_to(global_position) > RAIN_REACH:
		return 0.0
	var weather := get_tree().get_first_node_in_group("weather") as WeatherController
	if weather == null:
		return 0.0
	var local := weather.get_local_precipitation()
	return clampf(local.x + local.y * SNOW_SHARE, 0.0, 1.0)


static func nearest(tree: SceneTree, position: Vector3, reach := REACH) -> WaterTrough:
	var best: WaterTrough
	var distance := reach
	for node in tree.get_nodes_in_group(GROUP):
		var trough := node as WaterTrough
		if trough != null and trough.is_inside_tree() and not trough.is_queued_for_deletion():
			var d := trough.global_position.distance_to(position)
			if d <= distance:
				best = trough
				distance = d
	return best


## Los bebederos a menos de [reach] m de [at] (mundo), del más cercano a [from] al más lejano.
static func around(tree: SceneTree, at: Vector3, reach: float, from: Vector3) -> Array[WaterTrough]:
	var out: Array[WaterTrough] = []
	for node in tree.get_nodes_in_group(GROUP):
		var trough := node as WaterTrough
		if trough != null and trough.is_inside_tree() and not trough.is_queued_for_deletion() \
				and trough.global_position.distance_to(at) <= reach:
			out.append(trough)
	out.sort_custom(func(a: WaterTrough, b: WaterTrough) -> bool:
		return a.global_position.distance_to(from) < b.global_position.distance_to(from))
	return out


# --- El agua que se ve ----------------------------------------------------------------------------

func _make_surface() -> void:
	_surface = MeshInstance3D.new()
	_surface.name = "Water"
	var plane := PlaneMesh.new()
	var half := VisualScript.inner()
	plane.size = half * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.27, 0.3, 0.82)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.06
	material.metallic_specular = 0.6
	plane.material = material
	_surface.mesh = plane
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_surface)


func _update_surface() -> void:
	if _surface == null:
		return
	_surface.visible = water > 0
	var heights := VisualScript.water_heights()
	_surface.position.y = lerpf(heights.x, heights.y, float(water) / CAPACITY)


# --- Guardado -------------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	var t := transform
	return {"basis": [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y,
		t.basis.y.z, t.basis.z.x, t.basis.z.y, t.basis.z.z], "origin": [t.origin.x, t.origin.y, t.origin.z],
		"ship": GroundPlaceableTrait.ship_id(self), "water": water}


func restore_save_data(data: Dictionary) -> void:
	_ship_id = String(data.get("ship", ""))
	var b: Array = data.get("basis", [])
	var p: Array = data.get("origin", [])
	if b.size() == 9 and p.size() == 3:
		transform = Transform3D(Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]),
			Vector3(b[6], b[7], b[8])), Vector3(p[0], p[1], p[2]))
	water = int(data.get("water", 0))


func post_restore() -> void:
	GroundPlaceableTrait.restore_ship(self, _ship_id)

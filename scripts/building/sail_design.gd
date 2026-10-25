class_name SailDesign
extends RefCounted

## Medidas en metros, independientes del tamaño de celda del bloque de apoyo.
const ITEM := &"hide_sail"
const MIN_SIZE := Vector3(0.5, 0.5, 1.5)
const MAX_SIZE := Vector3(24.0, 16.0, 24.0)
const STEP := 0.25
const KEYS := ["width", "height", "mast_height"]
const DEFAULT := {"width": 4.0, "height": 3.0, "mast_height": 5.25}
## Los aparejos de partidas anteriores medían 5,1 m; se mantienen al faltar el diseño.
const LEGACY := {"width": 4.0, "height": 3.0, "mast_height": 5.1}


static func normalize(config: Dictionary) -> Dictionary:
	var result := {}
	for axis in 3:
		var key: String = KEYS[axis]
		var value := float(config.get(key, DEFAULT[key]))
		if not is_finite(value):
			value = DEFAULT[key]
		result[key] = clampf(value, MIN_SIZE[axis], MAX_SIZE[axis])
	result["mast_height"] = maxf(result["mast_height"], result["height"] + 0.75)
	return result


static func from_state(state: Dictionary) -> Dictionary:
	return normalize(state.get("design", LEGACY))


static func area(config: Dictionary) -> float:
	var design := normalize(config)
	return design["width"] * design["height"]


static func cost(config: Dictionary) -> Dictionary:
	var design := normalize(config)
	var width: float = design["width"]
	var height: float = design["height"]
	var rig_length: float = design["mast_height"] + width
	return {
		&"raw_hide": maxi(1, ceili(width * height / 2.0)),
		&"sinew": maxi(1, ceili((width + height) * 2.0 / 7.0)),
		&"plant_fiber": maxi(1, ceili(rig_length * 0.8)),
		&"branch_01": maxi(1, ceili(rig_length / 2.5)),
	}


static func mast_radius(config: Dictionary) -> float:
	return clampf(float(config["mast_height"]) * 0.022, 0.045, 0.30)


static func collider_size(config: Dictionary) -> Vector3:
	var design := normalize(config)
	var diameter := mast_radius(design) * 2.0
	return Vector3(diameter, design["mast_height"], diameter)


static func bounds(config: Dictionary) -> AABB:
	var design := normalize(config)
	var width: float = design["width"] + 0.5
	return AABB(Vector3(-width * 0.5, 0, -0.8), Vector3(width, design["mast_height"], 1.6))

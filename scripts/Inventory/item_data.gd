# item_data.gd
class_name ItemData

const config = preload("res://scripts/config.gd")

var object_type: config.OBJECT_TYPE
var object_name: String
var description: String
var icon: Texture2D
var max_stack: int
var value: int
var stackable: bool

func _init(item_type: config.OBJECT_TYPE) -> void:
	object_type = item_type
	var cfg = config.get_item_config(object_type)
	stackable = true
	if cfg.is_empty():
		push_warning("ItemData: tipo %s no tiene configuración" % item_type)
		return
	
	object_name = cfg.get("object_name", "Unknown")
	description = cfg.get("description", "")
	max_stack = cfg.get("max_stack", 99)
	value = cfg.get("value", 0)
	
	var icon_path = cfg.get("icon", "")
	if icon_path and ResourceLoader.exists(icon_path):
		icon = load(icon_path)

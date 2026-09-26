extends SceneTree

## Measures the body the armour was made for, the player scan, at the
## skeleton's rest, and saves it as BodyMeasurements.REFERENCE, which
## ArmorFit carries every armour from. Only needed again if the scan, its
## skin or the player skeleton change.
##
##   godot --headless --path . --script res://tools/character/bake_armor_reference.gd

const MODEL := "res://scenes/character/character_model.tscn"
const SKIN := "res://models/player/xavivar/firstage_human_male_player_skin.tres"
const MESH := "res://models/player/xavivar/firstage_human_male_player_mesh.tres"


func _initialize() -> void:
	var model: Node3D = load(MODEL).instantiate()
	var armature: Node3D = model.get_node("Armature")
	var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
	var globals := BodyMeasurements.rest_globals(skeleton)
	var measurements := BodyMeasurements.measure([[load(MESH), load(SKIN)]], skeleton, globals,
			armature.transform * skeleton.transform)
	DirAccess.make_dir_recursive_absolute(BodyMeasurements.REFERENCE.get_base_dir())
	var error := ResourceSaver.save(measurements, BodyMeasurements.REFERENCE)
	model.free()
	if error != OK:
		push_error("Could not save %s: %s" % [BodyMeasurements.REFERENCE, error_string(error)])
		quit(1)
		return
	for name in measurements.summary:
		print("  %s: %.1f cm" % [name, measurements.summary[name] * 100.0])
	print("Reference body saved to ", BodyMeasurements.REFERENCE)
	quit()

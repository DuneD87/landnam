extends SceneTree

## Writes the player skeleton for the Blender exporter
## (tools/character/blender/export_mpfb_human.py): every bone with its parent,
## its bind index in the player Skin and its joint position in the skin's
## space (the inverse of its bind pose).
##
##   godot --headless --path . --script res://tools/character/dump_skeleton.gd -- <output.json>

const MODEL := "res://scenes/character/character_model.tscn"
const SKIN := "res://models/player/xavivar/firstage_human_male_player_skin.tres"


func _initialize() -> void:
	var output := OS.get_cmdline_user_args()[0]
	var model: Node3D = load(MODEL).instantiate()
	var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
	var skin: Skin = load(SKIN)
	var bones := []
	for i in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(i)
		var bind_index := -1
		for b in skin.get_bind_count():
			if skin.get_bind_name(b) == name:
				bind_index = b
		var joint := skin.get_bind_pose(bind_index).affine_inverse().origin
		bones.append({name = name, parent = skeleton.get_bone_parent(i), bind_index = bind_index,
				mesh_joint = [joint.x, joint.y, joint.z]})
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({bones = bones}, "\t"))
	file.close()
	model.free()
	print("Skeleton with %d bones written to %s" % [bones.size(), output])
	quit()

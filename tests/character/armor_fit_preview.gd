extends Node3D

## Dresses a row of very different bodies in each armour set, as the game
## does (CharacterAppearanceRig baked, armour under the skeleton and fitted
## with dress()), and saves front, side and close-up shots under
## build/character/armor_fit/ (or the folder given with `-- --out <folder>`).
## The first figure is the player scan the armour was made for, wearing it
## unfitted. `--unfitted` leaves every body's armour as it was made and
## `--untucked` the hair through the hoods. Needs a
## window.
##
##   godot --path . res://tests/character/armor_fit_preview.tscn

const MODEL := preload("res://scenes/character/character_model.tscn")
const SETS := {
	&"firstage": [&"firstage_skin_chest", &"firstage_skin_pants", &"firstage_skin_boots",
			&"firstage_skin_hands", &"firstage_skin_hood"],
	&"leather": [&"leather_chest", &"leather_leggings", &"leather_boots", &"leather_hands",
			&"leather_hood"],
}
const ITEM_DIRS := ["res://data/items/Armor/FirstAge_Skin_Set/", "res://data/items/Armor/leather_armor/"]
const SCAN_MESH := "res://models/player/xavivar/firstage_human_male_player_mesh.tres"
const SCAN_SKIN := "res://models/player/xavivar/firstage_human_male_player_skin.tres"
const SPACING := 0.9
## Option values for each body in the row, with hair that meets the hoods:
## long, a fringe, a quiff, a bun, afro puffs.
const BODIES := [
	{&"sex": &"male", &"hair_style": &"long_m"},
	{&"sex": &"female", &"hair_style": &"layered"},
	{&"sex": &"male", &"body_weight": 1.0, &"abdomen": 0.8, &"hair_style": &"pompadour", &"beard": &"full"},
	{&"sex": &"male", &"muscle": 1.0, &"shoulder_width": 0.0, &"chest_depth": 1.0, &"lats": 1.0,
			&"hair_style": &"topknot"},
	{&"sex": &"female", &"height": 0.35, &"body_weight": -0.8, &"breast_size": 1.0, &"hips": 0.8,
			&"hair_style": &"afro_puffs"},
	{&"sex": &"male", &"height": -0.6, &"body_weight": -0.8, &"muscle": -0.6, &"hair_style": &"fringe"},
]

var _camera: Camera3D
var _models: Array[Node3D] = []
var _out := "res://build/character/armor_fit"
var _fit := true
var _tuck := true


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--out")
	if at >= 0 and at + 1 < args.size():
		_out = args[at + 1]
	_fit = not "--unfitted" in args
	_tuck = not "--untucked" in args
	DirAccess.make_dir_recursive_absolute(_out)
	get_window().size = Vector2i(1920, 1080)
	_build_stage()
	# The scan the armour was made for, first, wearing it as it was made.
	var scan: Node3D = MODEL.instantiate()
	scan.get_node("AppearanceRig").free()
	var scan_body: MeshInstance3D = scan.get_node("Armature/Skeleton3D/Mesh_0")
	scan_body.mesh = load(SCAN_MESH)
	scan_body.skin = load(SCAN_SKIN)
	_add_model(scan)
	for i in BODIES.size():
		var model: Node3D = MODEL.instantiate()
		_add_model(model)
		var appearance := CharacterAppearance.new()
		var values: Dictionary = BODIES[i]
		appearance.set_sex(values[&"sex"])
		for id in values:
			if id != &"sex":
				appearance.set_value(id, values[id])
		var rig: CharacterAppearanceRig = model.get_node("AppearanceRig")
		rig.apply(appearance)
		var line := "body %d:" % i
		for name in rig.measurements().summary:
			line += " %s %.0f" % [name, rig.measurements().summary[name] * 100.0]
		print(line)
	await _capture()
	get_tree().quit()


func _add_model(model: Node3D) -> void:
	add_child(model)
	model.position.x = (_models.size() - BODIES.size() * 0.5) * SPACING
	var animation: AnimationPlayer = model.get_node("AnimationPlayer")
	animation.play(&"idle")
	animation.seek(0.0, true)
	animation.pause()
	_models.append(model)


func _capture() -> void:
	await _shots("naked")
	for set_id in SETS:
		var started := Time.get_ticks_msec()
		for model in _models:
			for item_id in SETS[set_id]:
				_equip(model, item_id)
		while _models.any(func(model: Node3D) -> bool:
				return model.has_node("AppearanceRig") and model.get_node("AppearanceRig").is_dressing()):
			await get_tree().process_frame
		print("%s: %d bodies dressed in %d ms" % [set_id, _models.size(), Time.get_ticks_msec() - started])
		await _shots(set_id)
		for model in _models:
			_unequip(model)


func _shots(prefix: String) -> void:
	var width := SPACING * _models.size()
	_frame(Vector3(0, 0.95, 6.0), Vector3(0, 0.95, 0), width * 0.55)
	await _shot(prefix + "_front")
	for model in _models:
		model.rotation.y = PI * 0.5
	await _shot(prefix + "_side")
	for model in _models:
		model.rotation.y = 0.0
	# Torso close-ups, three-quarter view: the scan and the first three
	# bodies, then the last three.
	for model in _models:
		model.rotation.y = -0.6
	var centre := _models[0].position.x + SPACING * 1.5
	_frame(Vector3(centre, 1.2, 6.0), Vector3(centre, 1.2, 0), SPACING * 2.0)
	await _shot(prefix + "_torso")
	centre = _models[-1].position.x - SPACING
	_frame(Vector3(centre, 1.2, 6.0), Vector3(centre, 1.2, 0), SPACING * 1.6)
	await _shot(prefix + "_torso_extremes")
	# Heads, three-quarter front and back: bodies 1-3, then 4-6.
	for group in 2:
		centre = _models[1 + group * 3].position.x + SPACING
		_frame(Vector3(centre, 1.42, 6.0), Vector3(centre, 1.42, 0), SPACING * 1.35)
		for view in [["front", -0.6], ["back", PI - 0.6]]:
			for model in _models:
				model.rotation.y = view[1]
			await _shot("%s_heads%d_%s" % [prefix, group + 1, view[0]])
	for model in _models:
		model.rotation.y = 0.0


func _frame(from: Vector3, to: Vector3, half_width: float) -> void:
	_camera.position = from
	_camera.look_at(to)
	_camera.size = half_width * 2.0 * 1080.0 / 1920.0


func _equip(model: Node3D, item_id: StringName) -> void:
	var data := _item(item_id)
	var item: Node = load(data.scene_path).instantiate()
	item.item_data = ItemData.clone(data)
	var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
	skeleton.add_child(item)
	if _fit and model.has_node("AppearanceRig"):
		(model.get_node("AppearanceRig") as CharacterAppearanceRig).dress(item,
				data.armor_slot == ItemData.ArmorSlot.HEAD and _tuck)
	_light_planet_materials(item)


func _unequip(model: Node3D) -> void:
	for child in model.get_node("Armature/Skeleton3D").get_children():
		if "item_data" in child and child.item_data:
			if model.has_node("AppearanceRig"):
				(model.get_node("AppearanceRig") as CharacterAppearanceRig).undress(child)
			child.queue_free()


func _item(item_id: StringName) -> ItemData:
	for dir in ITEM_DIRS:
		for file in DirAccess.get_files_at(dir):
			var data: ItemData = load(dir + file.trim_suffix(".remap"))
			if data.id == item_id:
				return data
	push_error("No item %s" % item_id)
	return null


## Materials lit by the planet take their sun from uniforms the planet pushes;
## here the key light gives it.
func _light_planet_materials(node: Node) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false) + [node]:
		var mesh := child as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface) as ShaderMaterial
			if material != null:
				material.set_shader_parameter(&"light_direction", Vector3(-0.45, 0.5, 0.75).normalized())
				material.set_shader_parameter(&"planet_position", Vector3(0, -6000000.0, 0))


func _shot(name: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])


func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("15171b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b9c2cf")
	environment.ambient_light_energy = 0.3
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28, 32, 0)
	key.light_energy = 0.8
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, -48, 0)
	fill.light_energy = 0.3
	add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 160, 0)
	rim.light_energy = 0.4
	add_child(rim)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.current = true

extends Node

## Armas transportadas sobre el cuerpo real: frente, espalda, capa y mochila.
## godot --path . res://tests/combat/weapon_carry_preview.tscn -- --background
## Guarda build/combat/weapon_carry.png. Necesita render real.
const CASES := [
	[&"iron_sword", false, false, false], [&"greatsword", false, false, false],
	[&"hunting_bow", false, false, false], [&"spear", false, false, false],
	[&"iron_sword", true, true, false], [&"greatsword", true, true, false],
	[&"hunting_bow", true, true, true], [&"spear", true, true, true],
]
var root: Window
var _back_sword := false
var _back_shield := false
var _back_comparison := false


func _ready() -> void:
	root = get_tree().root
	_back_sword = "--back-sword" in OS.get_cmdline_user_args()
	_back_shield = "--back-shield" in OS.get_cmdline_user_args()
	_back_comparison = _back_sword or _back_shield
	if "--background" in OS.get_cmdline_user_args():
		root.unfocusable = true
		root.position = Vector2i(-4000, -4000)
	_run.call_deferred()


func _run() -> void:
	var cell := Vector2i(420, 560)
	root.size = cell
	var sheet := Image.create(cell.x * 4, cell.y * 2, false, Image.FORMAT_RGBA8)
	var world := Node3D.new()
	root.add_child(world)
	CharacterPreview.build_studio(world, false)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 38
	camera.current = true
	# --back-sword / --back-shield comparan equipo con/sin mochila desde cuatro ángulos,
	# con la misma ropa, cuerpo y pose en cada pareja.
	var cases := CASES.duplicate()
	if _back_comparison:
		cases.clear()
		for i in 8:
			cases.append([&"heater_shield" if _back_shield else &"dawn_greatsword", false, false, i % 2 == 1])
	for i in cases.size():
		var entry: Array = cases[i]
		var model: Node3D = load("res://scenes/character/character_model.tscn").instantiate()
		world.add_child(model)
		var rig: CharacterAppearanceRig = model.get_node("AppearanceRig")
		var appearance := CharacterAppearance.new()
		if not _back_comparison and i % 2 == 1:
			appearance.set_sex(&"female")
		rig.apply(appearance)
		var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
		var animator: AnimationPlayer = model.get_node("AnimationPlayer")
		animator.play(&"idle")
		animator.seek(0.6, true)
		animator.pause()
		var armor := [&"leather_chest", &"leather_leggings", &"leather_boots"]
		if _back_comparison:
			armor = [&"lionheart_cuirass", &"lionheart_kilt", &"lionheart_boots"]
		for id in armor:
			var clothing := ItemCatalog.get_item(id)
			var piece: Node = load(clothing.scene_path).instantiate()
			skeleton.add_child(piece)
			rig.dress(piece)
		if entry[2]:
			var cloak := ItemCatalog.get_item(&"bearpaw_cloak")
			var piece: Node = load(cloak.scene_path).instantiate()
			skeleton.add_child(piece)
			rig.dress(piece)
		if entry[3]:
			var pack := ItemCatalog.get_item(&"hide_backpack" if _back_comparison else &"bearpaw_backpack")
			if pack != null:
				BackEquipment.attach(skeleton, load(pack.scene_path), pack, rig)
		var weapon := ItemCatalog.get_item(entry[0])
		var carry := WeaponCarry.create(skeleton, weapon)
		carry.carry(load(weapon.scene_path).instantiate())
		carry.fit_to_body(rig)
		if entry[1]:
			var shield := ItemCatalog.get_item(&"heater_shield")
			var shield_carry := WeaponCarry.create(skeleton, shield)
			shield_carry.carry(load(shield.scene_path).instantiate())
			shield_carry.fit_to_body(rig)
		var painter := CharacterWindow.new()
		painter._light_for_studio(model)
		painter.free()
		# Los casos simples se ven por delante-lateral; las combinaciones, por detrás.
		var target := Vector3(0, 1.0, 0)
		camera.look_at_from_position(target + Vector3(-2.1, 0.3, 3.4 if i < 4 else -3.4), target)
		if _back_comparison:
			var eyes := [Vector3(0, 0.15, -4.0), Vector3(-4.0, 0.15, 0),
				Vector3(-2.5, 0.3, -3.4), Vector3(2.5, 0.3, -3.4)]
			camera.look_at_from_position(target + eyes[i / 2], target)
		var label := Label.new()
		label.text = str(entry[0]) + (" + escudo / capa" if entry[1] else "") + (" / mochila" if entry[3] else "")
		if _back_comparison:
			label.text = ["Espalda", "Perfil", "Tres cuartos", "Lado contrario"][i / 2] \
				+ (" / con mochila" if entry[3] else " / sin mochila")
		label.position = Vector2(12, 12)
		label.add_theme_font_size_override("font_size", 16)
		root.add_child(label)
		for frame in 20:
			await get_tree().process_frame
		while rig.is_dressing():
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, cell), Vector2i(i % 4, i / 4) * cell)
		label.queue_free()
		model.queue_free()
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute("res://build/combat")
	var path := "res://build/combat/weapon_carry_back_sword.png" if _back_sword else "res://build/combat/weapon_carry.png"
	if _back_shield:
		path = "res://build/combat/weapon_carry_back_shield.png"
	sheet.save_png(path)
	print("saved ", path)
	get_tree().quit()

extends SceneTree

## Paints the skin's tights mask (textures/character/human/skin/tights_mask.png):
## over the body's UVs, how high each point of the legs and the torso is at
## rest in the player skin space, as CharacterAppearanceRig.tights_value()
## encodes it; the arms, the neck and the head are 1 (over any waist: the
## filtering between them and the chest never passes through a waist). human_skin.gdshader
## dresses the skin in a garment's tights between two of those heights
## (a leg piece's hem and waist), so whatever shows through or between the
## plates is cloth, never skin, and can never come through them in a pose.
##
##   godot --headless --path . --script res://tools/character/bake_tights_mask.gd

const MODEL := "res://scenes/character/character_model.tscn"
const OUT := "res://textures/character/human/skin/tights_mask.png"
const PLAYER_SKIN := "res://models/player/xavivar/firstage_human_male_player_skin.tres"
const SIZE := 1024
## Texels the islands are grown past their UV edges, so filtering at a seam
## never blends in the background.
const GROW := 6
## Bones whose skin is never in tights.
const BARE := ["Shoulder", "Arm", "Hand", "Neck", "Head"]


func _initialize() -> void:
	var model: Node3D = load(MODEL).instantiate()
	root.add_child(model)
	var rig: CharacterAppearanceRig = model.get_node("AppearanceRig")
	rig.apply(CharacterAppearance.new())
	var body: MeshInstance3D = rig._body
	var mesh: ArrayMesh = body.mesh
	var skin: Skin = rig._data.skin
	var bare := PackedByteArray()
	bare.resize(skin.get_bind_count())
	for b in skin.get_bind_count():
		var name := String(skin.get_bind_name(b))
		bare[b] = 1 if BARE.any(func(part: String) -> bool: return name.contains(part)) else 0
	# At rest on this body, in the player skin's space (where armour is
	# made: Y up, origin at the hips), as tools/character/dump_skeleton.gd.
	var skeleton: Skeleton3D = model.get_node("Armature/Skeleton3D")
	var globals := rig._body_globals()
	var binds := BodyMeasurements.bind_transforms(skin, skeleton, globals)
	var player: Skin = load(PLAYER_SKIN)
	var hips := skeleton.find_bone(SkirtBones.HIPS)
	var to_skin := Transform3D.IDENTITY
	for b in player.get_bind_count():
		if player.get_bind_name(b) == SkirtBones.HIPS:
			to_skin = (BodyMeasurements.rest_globals(skeleton)[hips] * player.get_bind_pose(b)).affine_inverse()
	var values := PackedFloat32Array()
	values.resize(SIZE * SIZE)
	values.fill(-1.0)
	var low := INF
	var high := -INF
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var per := bones.size() / positions.size()
		var value := PackedFloat32Array()
		for i in positions.size():
			var on_bare := 0.0
			var rest := Vector3.ZERO
			for k in range(i * per, i * per + per):
				on_bare += weights[k] * bare[bones[k]]
				if weights[k] > 0.0:
					rest += binds[bones[k]] * positions[i] * weights[k]
			var height := (to_skin * rest).y
			value.append(1.0 if on_bare > 0.5 else CharacterAppearanceRig.tights_value(height))
			low = minf(low, height)
			high = maxf(high, height)
		for t in range(0, indices.size(), 3):
			_triangle(values, [uvs[indices[t]] * SIZE, uvs[indices[t + 1]] * SIZE, uvs[indices[t + 2]] * SIZE],
					[value[indices[t]], value[indices[t + 1]], value[indices[t + 2]]])
	print("Body heights %.3f .. %.3f m" % [low, high])
	for pass_index in GROW:
		var grown := values.duplicate()
		for y in SIZE:
			for x in SIZE:
				if values[y * SIZE + x] >= 0.0:
					continue
				var total := 0.0
				var count := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx := x + dx
						var ny := y + dy
						if nx >= 0 and ny >= 0 and nx < SIZE and ny < SIZE and values[ny * SIZE + nx] >= 0.0:
							total += values[ny * SIZE + nx]
							count += 1
				if count > 0:
					grown[y * SIZE + x] = total / count
		values = grown
	var bytes := PackedByteArray()
	bytes.resize(SIZE * SIZE)
	for i in values.size():
		bytes[i] = clampi(roundi(maxf(values[i], 0.0) * 255.0), 0, 255)
	var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_L8, bytes)
	image.save_png(ProjectSettings.globalize_path(OUT))
	print("Tights mask written to ", OUT)
	model.free()
	quit()


## Fills a triangle (texel corners `c`, values `v`), interpolated, at texel centres.
static func _triangle(values: PackedFloat32Array, c: Array, v: Array) -> void:
	var a: Vector2 = c[0]
	var b: Vector2 = c[1]
	var d: Vector2 = c[2]
	# Next to bare skin, no gradient from it through the heights.
	if maxf(v[0], maxf(v[1], v[2])) >= 1.0:
		v = [1.0, 1.0, 1.0]
	var area := (b - a).cross(d - a)
	if absf(area) < 1e-9:
		return
	var x0 := clampi(floori(minf(a.x, minf(b.x, d.x))), 0, SIZE - 1)
	var x1 := clampi(ceili(maxf(a.x, maxf(b.x, d.x))), 0, SIZE - 1)
	var y0 := clampi(floori(minf(a.y, minf(b.y, d.y))), 0, SIZE - 1)
	var y1 := clampi(ceili(maxf(a.y, maxf(b.y, d.y))), 0, SIZE - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var wa := (b - p).cross(d - p) / area
			var wb := (d - p).cross(a - p) / area
			var wd := 1.0 - wa - wb
			if wa < -0.01 or wb < -0.01 or wd < -0.01:
				continue
			values[y * SIZE + x] = wa * v[0] + wb * v[1] + wd * v[2]

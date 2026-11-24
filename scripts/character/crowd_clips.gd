class_name CrowdClips

## The clips the far crowd plays (CrowdBody), sampled once: the local pose of each of the human's
## bones at FPS, one row per sample. Every body bakes its own bone matrices from these rows
## (HumanMerge), with its own proportions, into a texture that its shader reads (CrowdShader).
##
## A looping clip of n rows covers [0, length) and wraps; a one-shot covers [0, length] and holds
## its last row. Only the model's own bones are sampled: the ones a hair style or a skirt adds
## follow the bone they hang from.

const MODEL := "res://scenes/character/character_model.tscn"
const ANIMS := "res://models/player/village_anims.tres"
const FPS := 15.0
const NAMES: Array[StringName] = [&"idle", &"village/walk_normal", &"village/jog", &"running",
	&"village/sit_idle", &"village/talk", &"village/dig", &"village/wave", &"attack_vertical"]

## The crowd's clock, seconds: the shaders read it as the global `crowd_time` (CrowdShader.tick).
static var time := 0.0

static var _mutex := Mutex.new()
static var _sampled := false
## Clip -> {first: its first row, rows, loop, length (s)}.
static var _clips := {}
## Row -> Array[Transform3D], the local pose of each bone.
static var _rows: Array = []
static var _bones := PackedStringArray()
static var _parents := PackedInt32Array()


## Samples the clips, the first time. Safe from a thread: it reads its own copy of the model.
static func ensure() -> void:
	_mutex.lock()
	if not _sampled:
		_sample()
		_sampled = true
	_mutex.unlock()


static func has(clip: StringName) -> bool:
	return _clips.has(clip)


static func bones() -> PackedStringArray:
	return _bones


static func parents() -> PackedInt32Array:
	return _parents


static func rows() -> Array:
	return _rows


## What an instance of the crowd carries (INSTANCE_CUSTOM) to play `clip` at `speed`, started `at`
## seconds into it: its first row, its rows (negative: a one-shot), when it started on the crowd's
## clock and its rows per second. Idle for a clip that is not baked.
static func params(clip: StringName, speed := 1.0, at := 0.0) -> Color:
	var info: Dictionary = _clips.get(clip, _clips.get(&"idle", {}))
	if info.is_empty():
		return Color(0.0, 1.0, 0.0, 0.0)
	var rate := float(info.rows) / float(info.length) * speed if info.loop else float(info.rows - 1) / float(info.length) * speed
	return Color(float(info.first), float(info.rows) if info.loop else -float(info.rows),
		time - at / maxf(speed, 0.01), rate)


static func _sample() -> void:
	var model := (load(MODEL) as PackedScene).instantiate()
	var skeleton := model.get_node("Armature/Skeleton3D") as Skeleton3D
	var player := model.get_node("AnimationPlayer") as AnimationPlayer
	if not player.has_animation_library(&"village"):
		player.add_animation_library(&"village", load(ANIMS))
	var count := skeleton.get_bone_count()
	var rests: Array[Transform3D] = []
	for b in count:
		_bones.append(skeleton.get_bone_name(b))
		_parents.append(skeleton.get_bone_parent(b))
		rests.append(skeleton.get_bone_rest(b))
	for clip in NAMES:
		if not player.has_animation(clip):
			continue
		var anim := player.get_animation(clip)
		var loop := anim.loop_mode != Animation.LOOP_NONE
		var n := maxi(int(ceil(anim.length * FPS)), 1) + (0 if loop else 1)
		var positions := PackedInt32Array()
		var rotations := PackedInt32Array()
		positions.resize(count)
		positions.fill(-1)
		rotations.resize(count)
		rotations.fill(-1)
		for t in anim.get_track_count():
			var path := anim.track_get_path(t)
			if path.get_subname_count() != 1:
				continue
			var bone := _bones.find(path.get_subname(0))
			if bone < 0:
				continue
			match anim.track_get_type(t):
				Animation.TYPE_POSITION_3D:
					positions[bone] = t
				Animation.TYPE_ROTATION_3D:
					rotations[bone] = t
		_clips[clip] = {first = _rows.size(), rows = n, loop = loop, length = anim.length}
		for r in n:
			var at := r * anim.length / float(n if loop else maxi(n - 1, 1))
			var row: Array[Transform3D] = []
			for b in count:
				var rest := rests[b]
				var origin: Vector3 = anim.position_track_interpolate(positions[b], at) if positions[b] >= 0 else rest.origin
				var basis := Basis(anim.rotation_track_interpolate(rotations[b], at)) if rotations[b] >= 0 else rest.basis
				row.append(Transform3D(basis, origin))
			_rows.append(row)
	model.free()

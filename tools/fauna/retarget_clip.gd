extends SceneTree

## Pasa un clip de un animal a otro de la misma familia de esqueleto (los huesos con el mismo nombre,
## como los del pack WildMesh que empiezan por Root, Pelvis, Spine1…): a cada hueso que tengan los
## dos le pone el giro del original respecto a su pose de reposo, sobre la pose de reposo del otro.
## Lo que desplazan Root y Pelvis se escala a la altura de la pelvis del otro animal, y --lift (m)
## lo sube a medida que cae la pelvis: un cuerpo más grueso que el original, tumbado, se hundiría.
## El clip sale como Animation con las pistas desde el esqueleto (".:Hueso"), para un AnimationPlayer
## colgado del Skeleton3D (el cadáver de FaunaCorpse).
##   godot --headless --path . --script res://tools/fauna/retarget_clip.gd -- \
##       --source=res://models/animals/_retarget/hyena.fbx --clip=WalkSlowWounded2Lying \
##       --target=res://models/animals/rabbit/rabbit.fbx --out=res://models/animals/rabbit/rabbit_death.res \
##       [--from=0.5] [--to=-1] [--fps=30] [--lift=0.065]

const MOVING := ["Root", "Pelvis"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	for key in ["source", "clip", "target", "out"]:
		if not args.has(key):
			push_error("Falta --%s" % key)
			quit(1)
			return
	var source: Node3D = (load(args.source) as PackedScene).instantiate()
	var target: Node3D = (load(args.target) as PackedScene).instantiate()
	root.add_child(source)
	root.add_child(target)
	var src_skel := source.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var dst_skel := target.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var take := StringName()
	for name in player.get_animation_list():
		if String(name).get_slice("|", String(name).get_slice_count("|") - 1) == args.clip:
			take = name
	if take == StringName():
		push_error("%s no tiene el clip %s" % [args.source, args.clip])
		quit(1)
		return
	var length := player.get_animation(take).length
	var from := float(args.get("from", "0"))
	var to := float(args.get("to", "-1"))
	if to <= from:
		to = length
	var fps := float(args.get("fps", "30"))
	var lift := float(args.get("lift", "0"))
	# Lo que mide la pelvis desde la raíz en cada esqueleto (en sus unidades): la escala de los
	# desplazamientos.
	var ratio := _pelvis_height(dst_skel) / maxf(_pelvis_height(src_skel), 1e-5)
	var pairs: Array = []
	for bone in dst_skel.get_bone_count():
		var src := src_skel.find_bone(dst_skel.get_bone_name(bone))
		if src >= 0:
			pairs.append([bone, src])
	var anim := Animation.new()
	anim.length = to - from
	var rot_tracks := {}
	var pos_tracks := {}
	for pair in pairs:
		var bone_name := dst_skel.get_bone_name(pair[0])
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath(".:" + bone_name))
		rot_tracks[pair[0]] = track
		if bone_name in MOVING:
			track = anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(track, NodePath(".:" + bone_name))
			pos_tracks[pair[0]] = track
	player.play(take)
	player.pause()
	# Cuánto cae la pelvis del original en el tramo (lo más), para repartir --lift.
	var src_pelvis := src_skel.find_bone("Pelvis")
	var src_up := (src_skel.global_basis.inverse() * Vector3.UP).normalized()
	var rest_height := src_skel.get_bone_global_rest(src_pelvis).origin.dot(src_up) if src_pelvis >= 0 else 0.0
	var max_drop := 0.0
	var t := from
	while t <= to + 0.0001:
		player.seek(t, true)
		if src_pelvis >= 0:
			max_drop = maxf(max_drop, rest_height - src_skel.get_bone_global_pose(src_pelvis).origin.dot(src_up))
		t += 1.0 / fps
	# Un metro hacia arriba en unidades del esqueleto de destino.
	var dst_up := dst_skel.global_basis.inverse() * Vector3.UP
	var dst_root := dst_skel.find_bone("Root")
	t = from
	while t <= to + 0.0001:
		player.seek(t, true)
		for pair in pairs:
			var dst: int = pair[0]
			var src: int = pair[1]
			var delta := src_skel.get_bone_rest(src).basis.get_rotation_quaternion().inverse() \
				* src_skel.get_bone_pose_rotation(src)
			var rotation := dst_skel.get_bone_rest(dst).basis.get_rotation_quaternion() * delta
			anim.rotation_track_insert_key(rot_tracks[dst], t - from, rotation.normalized())
			if pos_tracks.has(dst):
				var moved := src_skel.get_bone_pose_position(src) - src_skel.get_bone_rest(src).origin
				var position := dst_skel.get_bone_rest(dst).origin + moved * ratio
				if dst == dst_root and lift != 0.0 and max_drop > 0.0:
					var drop := rest_height - src_skel.get_bone_global_pose(src_pelvis).origin.dot(src_up)
					position += dst_up * lift * clampf(drop / max_drop, 0.0, 1.0)
				anim.position_track_insert_key(pos_tracks[dst], t - from, position)
		t += 1.0 / fps
	var err := ResourceSaver.save(anim, args.out, ResourceSaver.FLAG_COMPRESS)
	print("%s (%.2f–%.2f s) → %s: %d huesos, escala %.3f (%s)" % [take, from, to, args.out, pairs.size(), ratio, error_string(err)])
	quit(0 if err == OK else 1)


func _pelvis_height(skeleton: Skeleton3D) -> float:
	var pelvis := skeleton.find_bone("Pelvis")
	return skeleton.get_bone_global_rest(pelvis).origin.length() if pelvis >= 0 else 1.0

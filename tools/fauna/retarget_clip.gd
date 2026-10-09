extends SceneTree

## Pasa un clip de un animal a otro de la misma familia de esqueleto (los huesos con el mismo nombre,
## como los del pack WildMesh que empiezan por Root, Pelvis, Spine1…): a cada hueso que tengan los
## dos le pone el giro del original respecto a su pose de reposo, sobre la pose de reposo del otro.
## Lo que desplazan los huesos que se mueven en el clip (la raíz y la pelvis, o los de --moving) se
## escala a la altura de la pelvis del otro animal, y --lift (m) lo sube a medida que cae la pelvis:
## un cuerpo más grueso que el original, tumbado, se hundiría. Con el mismo modelo de origen y de
## destino solo cambia de dónde cuelgan las pistas: así se saca el clip de muerte que trae el modelo.
## El clip sale como Animation con las pistas desde el esqueleto (".:Hueso"), para un AnimationPlayer
## colgado del Skeleton3D (el cadáver de FaunaCorpse).
##   godot --headless --path . --script res://tools/fauna/retarget_clip.gd -- \
##       --source=res://models/animals/_retarget/hyena.fbx --clip=WalkSlowWounded2Lying \
##       --target=res://models/animals/rabbit/rabbit.fbx --out=res://models/animals/rabbit/rabbit_death.res \
##       [--from=0.5] [--to=-1] [--fps=30] [--lift=0.065] [--pelvis=Pelvis] [--moving=Root,Pelvis]
## Sin --pelvis, el primer hueso que se llame algo como pelvis o hips; sin --moving, los que tienen
## pista de posición en el clip.
## Entre familias de esqueleto distintas (otros nombres, otros ejes en los huesos), --map dice qué
## hueso del destino sigue a cuál del original, y el giro se pasa en el espacio del modelo (lo que
## gira cada hueso respecto a su reposo, visto desde fuera), que no depende de cómo apunten los ejes
## de cada hueso. Solo la pelvis se desplaza. Los modelos tienen que mirar al mismo lado (los del pack,
## a +Z) y estar de pie en reposo.
##   --map=names         los huesos con el mismo nombre, en el espacio del modelo;
##   --map=root_from_rig la familia Root (Pelvis, LegFL1…) desde la Rig (RigPelvis, RigLFLeg1…);
##   --map=dst:src,...   a mano.
## --track_root=lince/Lynx/Skeleton3D cuelga las pistas de ese nodo (las escenas de criatura, cuyo
## AnimationPlayer está en NPCModel) en vez de del esqueleto (".", el cadáver de FaunaCorpse).


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
	var src_pelvis := _find_pelvis(src_skel, args.get("pelvis", ""))
	var dst_pelvis := _find_pelvis(dst_skel, args.get("pelvis", ""))
	var moving: PackedStringArray = String(args.get("moving", "")).split(",", false)
	if moving.is_empty():
		var anim_src := player.get_animation(take)
		for track in anim_src.get_track_count():
			if anim_src.track_get_type(track) == Animation.TYPE_POSITION_3D:
				moving.append(String(anim_src.track_get_path(track).get_concatenated_subnames()))
	# Lo que mide la pelvis desde la raíz en cada esqueleto (en sus unidades): la escala de los
	# desplazamientos.
	var ratio := _pelvis_height(dst_skel, dst_pelvis) / maxf(_pelvis_height(src_skel, src_pelvis), 1e-5)
	var track_root: String = args.get("track_root", ".")
	if args.has("map"):
		var mapped := _mapping(src_skel, dst_skel, String(args.map))
		var anim_model := _model_space(source, target, src_skel, dst_skel, player, take, mapped, from, to, fps,
			src_pelvis, dst_pelvis, lift, track_root)
		var saved := ResourceSaver.save(anim_model, args.out, ResourceSaver.FLAG_COMPRESS)
		print("%s (%.2f–%.2f s) → %s: %d huesos en el espacio del modelo (%s)" % [take, from, to, args.out,
			mapped.size(), error_string(saved)])
		quit(0 if saved == OK else 1)
		return
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
		anim.track_set_path(track, NodePath("%s:%s" % [track_root, bone_name]))
		rot_tracks[pair[0]] = track
		if bone_name in moving:
			track = anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(track, NodePath("%s:%s" % [track_root, bone_name]))
			pos_tracks[pair[0]] = track
	player.play(take)
	player.pause()
	# Cuánto cae la pelvis del original en el tramo (lo más), para repartir --lift.
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
	# La raíz del esqueleto de destino (el primer hueso sin padre): la que sube --lift.
	var dst_root := 0
	while dst_root < dst_skel.get_bone_count() and dst_skel.get_bone_parent(dst_root) >= 0:
		dst_root += 1
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


func _pelvis_height(skeleton: Skeleton3D, pelvis: int) -> float:
	return skeleton.get_bone_global_rest(pelvis).origin.length() if pelvis >= 0 else 1.0


## La pelvis: [wanted] si se da, y si no el primer hueso cuyo nombre lleve pelvis o hips.
func _find_pelvis(skeleton: Skeleton3D, wanted: String) -> int:
	if wanted != "":
		return skeleton.find_bone(wanted)
	for bone in skeleton.get_bone_count():
		var lower := skeleton.get_bone_name(bone).to_lower()
		if lower.contains("pelvis") or lower.contains("hips"):
			return bone
	return -1


## Qué hueso del original sigue cada hueso del destino (índice de destino → índice de origen).
func _mapping(src: Skeleton3D, dst: Skeleton3D, how: String) -> Dictionary:
	var result := {}
	if how == "names" or how == "root_from_rig":
		var leg := RegEx.create_from_string("^Leg([FB])([LR])(.*)$")
		for bone in dst.get_bone_count():
			var bone_name := dst.get_bone_name(bone)
			var candidates := [bone_name]
			if how == "root_from_rig":
				var m := leg.search(bone_name)
				candidates = ["Rig%s%sLeg%s" % [m.get_string(2), m.get_string(1), m.get_string(3)]] if m != null \
					else ["Rig" + bone_name, "Rig%s1" % bone_name]
			for candidate in candidates:
				var src_bone := src.find_bone(candidate)
				if src_bone >= 0:
					result[bone] = src_bone
					break
		return result
	for pair in how.split(",", false):
		var dst_bone := dst.find_bone(pair.get_slice(":", 0).strip_edges())
		var src_bone := src.find_bone(pair.get_slice(":", 1).strip_edges())
		if dst_bone < 0 or src_bone < 0:
			push_error("--map: no hay %s" % pair)
			continue
		result[dst_bone] = src_bone
	return result


## El clip con el giro de cada hueso pasado en el espacio del modelo: lo que gira el hueso del
## original respecto a su reposo, aplicado sobre el reposo del de destino; los que no siguen a nadie
## se quedan en su reposo respecto a su padre.
func _model_space(source: Node3D, target: Node3D, src_skel: Skeleton3D, dst_skel: Skeleton3D,
		player: AnimationPlayer, take: StringName, mapped: Dictionary, from: float, to: float, fps: float,
		src_pelvis: int, dst_pelvis: int, lift: float, track_root: String) -> Animation:
	var src_model := _to_model(source, src_skel)
	var dst_model := _to_model(target, dst_skel)
	var qs := src_model.basis.get_rotation_quaternion()
	var qd := dst_model.basis.get_rotation_quaternion()
	# Padres antes que hijos.
	var order: Array[int] = []
	var pending: Array[int] = []
	pending.assign(Array(dst_skel.get_parentless_bones()))
	while not pending.is_empty():
		var bone: int = pending.pop_front()
		order.append(bone)
		pending.append_array(Array(dst_skel.get_bone_children(bone)))
	var anim := Animation.new()
	anim.length = to - from
	var tracks := {}
	for bone in mapped:
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath("%s:%s" % [track_root, dst_skel.get_bone_name(bone)]))
		tracks[bone] = track
	var pelvis_track := -1
	if dst_pelvis >= 0 and src_pelvis >= 0 and mapped.has(dst_pelvis):
		pelvis_track = anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(pelvis_track, NodePath("%s:%s" % [track_root, dst_skel.get_bone_name(dst_pelvis)]))
	# Altura de la pelvis en el espacio del modelo: la escala del desplazamiento, y lo que cae (--lift).
	var src_rest_pelvis := src_model * src_skel.get_bone_global_rest(src_pelvis).origin if src_pelvis >= 0 else Vector3.ZERO
	var dst_rest_pelvis := dst_model * dst_skel.get_bone_global_rest(dst_pelvis).origin if dst_pelvis >= 0 else Vector3.ZERO
	var ratio := dst_rest_pelvis.y / maxf(src_rest_pelvis.y, 1e-5)
	player.play(take)
	player.pause()
	var t := from
	while t <= to + 0.0001:
		player.seek(t, true)
		var glob := {}
		for bone in order:
			var parent := dst_skel.get_bone_parent(bone)
			var parent_rot: Quaternion = glob[parent] if parent >= 0 else Quaternion.IDENTITY
			var rot: Quaternion
			if mapped.has(bone):
				var src_bone: int = mapped[bone]
				var delta := (qs * src_skel.get_bone_global_pose(src_bone).basis.get_rotation_quaternion()) \
					* (qs * src_skel.get_bone_global_rest(src_bone).basis.get_rotation_quaternion()).inverse()
				rot = qd.inverse() * (delta * (qd * dst_skel.get_bone_global_rest(bone).basis.get_rotation_quaternion()))
				anim.rotation_track_insert_key(tracks[bone], t - from, (parent_rot.inverse() * rot).normalized())
			else:
				rot = parent_rot * dst_skel.get_bone_rest(bone).basis.get_rotation_quaternion()
			glob[bone] = rot.normalized()
		if pelvis_track >= 0:
			var moved := (src_model * src_skel.get_bone_global_pose(src_pelvis).origin - src_rest_pelvis) * ratio
			if lift != 0.0:
				moved.y += lift * clampf(-moved.y / maxf(dst_rest_pelvis.y, 1e-5), 0.0, 1.0)
			var wanted := dst_model.affine_inverse() * (dst_rest_pelvis + moved)
			var parent := dst_skel.get_bone_parent(dst_pelvis)
			var position := wanted
			if parent >= 0:
				var parent_xform := Transform3D(Basis(glob[parent]), dst_skel.get_bone_global_rest(parent).origin)
				position = parent_xform.affine_inverse() * wanted
			anim.position_track_insert_key(pelvis_track, t - from, position)
		t += 1.0 / fps
	return anim


## Del esqueleto al espacio del modelo (la raíz de la escena importada).
func _to_model(model: Node3D, skeleton: Skeleton3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var node: Node = skeleton
	while node != model:
		if node is Node3D:
			xform = (node as Node3D).transform * xform
		node = node.get_parent()
	return xform
